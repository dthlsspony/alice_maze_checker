class_name MazeRuntime
extends RefCounted

## Runtime entry point for procedural generators.
##
## The editor plugin reads a painted TileMapLayer. A generator has no tilemap,
## only an array of cells it just rolled. This wrapper feeds those cells into
## the same flood fill and answers the one question a generation loop asks:
## accept this floor, or roll another one?
##
## Pure logic, no editor or engine dependencies, so it is safe to call from a
## running game at generation time, from a headless test, or from a tool.
##
## Cells come in as either
##   - an Array of rows; each row an Array where 1/true/'#' means WALL
##   - a flat PackedByteArray of length width*height, 1 = WALL
## and every non-wall cell is floor. A cell equal to 'P' marks the start.

const Core = preload("res://addons/maze_checker/maze_core.gd")
const Graph = preload("res://addons/maze_checker/graph_core.gd")

const _WALL := "#"
const _FLOOR := "."


static func _is_wall(v) -> bool:
	if typeof(v) == TYPE_BOOL:
		return v
	if typeof(v) == TYPE_INT:
		return v != 0
	if typeof(v) == TYPE_STRING:
		var s: String = v
		return s == _WALL or s == "1"
	return false


## Turn a generator's native cells into the ASCII grid the core already eats.
## start_cell (Vector2i or null) drops a 'P' marker so the report anchors there
## instead of on the first open cell.
static func to_grid(cells, opts: Dictionary = {}) -> String:
	var start_cell = opts.get("start", null)
	var sx := -1
	var sy := -1
	if start_cell is Vector2i:
		sx = start_cell.x
		sy = start_cell.y
	elif typeof(start_cell) == TYPE_ARRAY and start_cell.size() >= 2:
		sx = int(start_cell[0])
		sy = int(start_cell[1])

	var rows: Array = []
	if cells is PackedByteArray:
		var w: int = int(opts.get("width", 0))
		var h: int = int(opts.get("height", 0))
		if w <= 0 or h <= 0:
			return ""
		for y in h:
			var line := ""
			for x in w:
				var wall: bool = cells[y * w + x] != 0
				line += (_WALL if wall else (_FLOOR if (x != sx or y != sy) else "P"))
			rows.append(line)
	else:
		for y in cells.size():
			var row = cells[y]
			var line := ""
			for x in row.size():
				var wall: bool = _is_wall(row[x])
				var is_start: bool = (x == sx and y == sy)
				if wall:
					line += _WALL
				elif is_start:
					line += "P"
				else:
					line += _FLOOR
			rows.append(line)
	return "\n".join(rows)


static func analyze_cells(cells, opts: Dictionary = {}) -> Dictionary:
	var text := to_grid(cells, opts)
	if text == "":
		return {"ok": false, "status": "broken", "issues": ["no cells given"],
			"walkable": 0, "unreachable": 0, "isolated": 0, "deadEnds": 0,
			"borderOpen": 0, "ragged": false, "comps": [], "width": 0, "height": 0}
	var core_opts := {"wallChar": _WALL, "wrap": bool(opts.get("wrap", false))}
	return Core.analyze(text, core_opts)


## The generation loop's gate. Returns pass + the reasons a floor failed, so a
## generator can log why it threw a room away instead of silently rerolling.
static func judge(report: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var min_ratio := float(opts.get("minWalkableRatio", 0.25))
	var max_dead_ratio := float(opts.get("maxDeadEndRatio", 0.5))
	var allow_edge := bool(opts.get("allowEdgeOpenings", true))

	var reasons: Array = []
	var w := int(report.get("walkable", 0))
	var total := int(report.get("width", 0)) * int(report.get("height", 0))
	var comps: Array = report.get("comps", [])

	if w == 0:
		reasons.append("no floor at all")
	if total > 0 and float(w) / float(total) < min_ratio:
		reasons.append("floor too thin (" + str(w) + "/" + str(total) + ")")
	if int(report.get("unreachable", 0)) > 0:
		reasons.append(str(report["unreachable"]) + " unreachable floor cell(s)")
	if int(report.get("isolated", 0)) > 0:
		reasons.append(str(report["isolated"]) + " isolated cell(s)")
	if bool(report.get("ragged", false)):
		reasons.append("ragged grid")
	if comps.size() > 1:
		reasons.append(str(comps.size()) + " separate regions")
	if w > 0 and float(report.get("deadEnds", 0)) / float(w) > max_dead_ratio:
		reasons.append("too many dead ends (" + str(report.get("deadEnds", 0)) + ")")
	if not allow_edge and int(report.get("borderOpen", 0)) > 0:
		reasons.append(str(report["borderOpen"]) + " floor cell(s) leak off the edge")

	return {
		"pass": reasons.is_empty(),
		"action": "accept" if reasons.is_empty() else "regenerate",
		"reasons": reasons,
	}


## One call a generator makes per rolled floor: analyze, judge, hand back both.
## If opts carries "doors", the door pass runs too and a failed door forces a
## regenerate, so a generator never ships a floor whose exit cannot be walked to.
static func check_or_regenerate(cells, opts: Dictionary = {}) -> Dictionary:
	var report := analyze_cells(cells, opts)
	var verdict := judge(report, opts)
	var reasons: Array = verdict.reasons.duplicate()
	var out := {
		"pass": verdict.pass,
		"action": verdict.action,
		"reasons": reasons,
		"report": report,
	}
	if opts.has("doors"):
		var doors := check_doors(cells, opts["doors"], opts)
		out["doors"] = doors
		if not doors.pass:
			out["pass"] = false
			out["action"] = "regenerate"
			for r in doors.reasons:
				reasons.append(r)
	return out


# ---------------------------------------------------------------------------
# Doors
#
# A door is a cell with a name and a state. The naming rule is the simple one:
# if the object's name contains "door" or "gate" (any case, e.g. Door_A,
# big_door, DOOR_2, Gate_North) it is a door; nothing about its geometry matters.
# State decides whether it is a way through right now:
#   open    -> passable
#   closed  -> blocked (a push opens it)
#   locked  -> blocked until a key / condition (reported, not a break by itself)
#
# The question a level designer actually asks (and a rogue generator must ask
# before accepting a floor) is whether the door can be reached from spawn at all,
# and whether reaching it needs clearing the room first. This pass answers both:
#   reachable     -> stand on it (open) or beside it (closed/locked) with the
#                    floor exactly as rolled
#   needsClearing -> not reachable now, but reachable if every destructible
#                    obstacle were removed
#   walledOff     -> not reachable even then: the door can never be used
# ---------------------------------------------------------------------------

## Map any spelling of a door state onto open / closed / locked.
static func norm_door_state(v) -> String:
	var s := str(v).strip_edges().to_lower()
	if s == "open" or s == "opened" or s == "unlocked" or s == "true":
		return "open"
	if s == "locked" or s == "lock" or s == "key" or s == "sealed":
		return "locked"
	return "closed"


## Accepts a Vector2i, [x, y], a "x,y" string, or a dictionary with a "cell" key.
static func _cell_of(v) -> Vector2i:
	if v is Vector2i:
		return v
	if typeof(v) == TYPE_ARRAY and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	if typeof(v) == TYPE_DICTIONARY:
		return _cell_of(v.get("cell", null))
	if typeof(v) == TYPE_STRING:
		var parts: PackedStringArray = v.split(",")
		if parts.size() >= 2:
			return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(-1, -1)


## The naming rule, applied to a mixed list: dictionaries {name, cell, state},
## nodes with a name (plus optional "state" / "locked" / "cell" meta), or plain
## strings. Only names containing a keyword survive. The default keywords are
## "door" and "gate" (a world map has gates, a dungeon has doors); override with
## opts.keywords. Useful when a scene/room is a pile of nodes and you do not want
## to hand-annotate every one.
static func doors_from_named(objects: Array, opts: Dictionary = {}) -> Array:
	var keywords: Array = opts.get("keywords", ["door", "gate"])
	var out: Array = []
	for o in objects:
		var nm := ""
		var cell := Vector2i(-1, -1)
		var state := ""
		if typeof(o) == TYPE_DICTIONARY:
			nm = str(o.get("name", ""))
			cell = _cell_of(o)
			if o.has("state"):
				state = str(o["state"])
			elif bool(o.get("locked", false)):
				state = "locked"
			elif o.has("open"):
				state = "open" if bool(o["open"]) else "closed"
			elif o.has("closed"):
				state = "closed" if bool(o["closed"]) else "open"
		elif typeof(o) == TYPE_OBJECT:
			nm = str(o.get("name"))
			if o.has_method("get_meta"):
				cell = _cell_of(o.get_meta("cell", null))
				state = str(o.get_meta("state", ""))
				if state == "" and bool(o.get_meta("locked", false)):
					state = "locked"
		else:
			nm = str(o)
		var low := nm.to_lower()
		var hit := false
		for k in keywords:
			if low.find(str(k).to_lower()) >= 0:
				hit = true
				break
		if not hit:
			continue
		out.append({
			"name": nm,
			"cell": cell,
			"state": norm_door_state(state if state != "" else "closed"),
		})
	return out


static func _normalize_doors(doors) -> Array:
	var out: Array = []
	if doors == null:
		return out
	if typeof(doors) == TYPE_DICTIONARY:
		if doors.has("cell"):
			out.append({"name": str(doors.get("name", "door")), "cell": _cell_of(doors),
				"state": norm_door_state(doors.get("state", "closed"))})
			return out
		for k in doors.keys():
			var c := _cell_of(k)
			if c.x < 0:
				continue
			out.append({"name": str(k), "cell": c, "state": norm_door_state(doors[k])})
		return out
	if typeof(doors) == TYPE_ARRAY:
		for d in doors:
			if typeof(d) == TYPE_DICTIONARY:
				out.append({"name": str(d.get("name", "door")), "cell": _cell_of(d),
					"state": norm_door_state(d.get("state", "closed"))})
			else:
				var c2 := _cell_of(d)
				if c2.x >= 0:
					out.append({"name": str(d), "cell": c2, "state": "closed"})
	return out


static func _neighbor_idx(x: int, y: int, w: int, h: int, wrap: bool) -> Array:
	var out: Array = []
	if y > 0:
		out.append((y - 1) * w + x)
	if y < h - 1:
		out.append((y + 1) * w + x)
	if x > 0:
		out.append(y * w + (x - 1))
	elif wrap and w > 1:
		out.append(y * w + (w - 1))
	if x < w - 1:
		out.append(y * w + (x + 1))
	elif wrap and w > 1:
		out.append(y * w + 0)
	return out


## Build the grid dims + wall flags once, for both analyze and doors.
static func _wall_grid(cells, opts: Dictionary) -> Dictionary:
	var w := 0
	var h := 0
	var walls := PackedByteArray()
	var sx := -1
	var sy := -1
	var start_cell = opts.get("start", null)
	if start_cell is Vector2i:
		sx = start_cell.x
		sy = start_cell.y
	elif typeof(start_cell) == TYPE_ARRAY and start_cell.size() >= 2:
		sx = int(start_cell[0])
		sy = int(start_cell[1])
	if cells is PackedByteArray:
		w = int(opts.get("width", 0))
		h = int(opts.get("height", 0))
		if w <= 0 or h <= 0:
			return {"ok": false}
		walls = cells.duplicate()
	else:
		h = cells.size()
		for y in h:
			w = max(w, cells[y].size())
		if w <= 0 or h <= 0:
			return {"ok": false}
		walls.resize(w * h)
		for y in h:
			var row = cells[y]
			for x in w:
				var v = row[x] if x < row.size() else 1
				walls[y * w + x] = 1 if _is_wall(v) else 0
	return {"ok": true, "walls": walls, "w": w, "h": h, "sx": sx, "sy": sy}


static func _analyze_graph(node_state: Dictionary, w: int, h: int, wrap: bool, start_idx: int) -> Dictionary:
	var count := w * h
	var edges: Array = []
	for y in h:
		for x in w:
			var i := y * w + x
			for n in _neighbor_idx(x, y, w, h, wrap):
				if n > i:
					edges.append([i, n, Graph.OPEN])
	var ns: Dictionary = {}
	for i in count:
		ns[i] = int(node_state.get(i, Graph.OPEN))
	return Graph.analyze({
		"count": count,
		"edges": edges,
		"nodeState": ns,
		"start": [start_idx] if start_idx >= 0 else [],
		"border": [],
	})


static func _cell_reachable(res: Dictionary, node_state: Dictionary, w: int, h: int, idx: int, wrap: bool) -> bool:
	var start_comp := int(res.get("startComp", -1))
	if start_comp < 0:
		return false
	var comp: PackedInt32Array = res.get("comp", PackedInt32Array())
	if int(node_state.get(idx, Graph.OPEN)) == Graph.OPEN:
		return idx < comp.size() and comp[idx] == start_comp
	var x := idx % w
	var y := (idx - x) / w
	for n in _neighbor_idx(x, y, w, h, wrap):
		if int(node_state.get(n, Graph.OPEN)) == Graph.OPEN and n < comp.size() and comp[n] == start_comp:
			return true
	return false


## The door pass. `doors` is any shape _normalize_doors accepts; `opts.obstacles`
## is a list of destructible-obstacle cells to treat as clearable. Returns a
## per-door verdict plus reasons a generator can log and act on.
static func check_doors(cells, doors, opts: Dictionary = {}) -> Dictionary:
	var specs := _normalize_doors(doors)
	var g := _wall_grid(cells, opts)
	if not g.ok:
		return {"ok": false, "pass": false, "doors": [], "walledOff": 0,
			"needingClearing": 0, "reasons": ["no cells given"], "warnings": []}
	var w: int = g.w
	var h: int = g.h
	var count: int = w * h
	var wrap := bool(opts.get("wrap", false))

	var base: Dictionary = {}
	for i in count:
		base[i] = Graph.OPEN if g.walls[i] == 0 else Graph.WALL
	for ob in opts.get("obstacles", []):
		var oc := _cell_of(ob)
		if oc.x >= 0 and oc.x < w and oc.y >= 0 and oc.y < h:
			base[oc.y * w + oc.x] = Graph.SOFT
	for d in specs:
		var dc: Vector2i = d.cell
		if dc.x >= 0 and dc.x < w and dc.y >= 0 and dc.y < h:
			base[dc.y * w + dc.x] = Graph.OPEN if d.state == "open" else Graph.WALL

	var start_idx := -1
	if g.sx >= 0 and g.sx < w and g.sy >= 0 and g.sy < h:
		var si: int = g.sy * w + g.sx
		if int(base[si]) == Graph.OPEN:
			start_idx = si
	if start_idx < 0:
		for i in count:
			if int(base[i]) == Graph.OPEN:
				start_idx = i
				break

	var res := _analyze_graph(base, w, h, wrap, start_idx)
	var open_all: Dictionary = base.duplicate()
	for i in count:
		if int(open_all[i]) == Graph.SOFT:
			open_all[i] = Graph.OPEN
	var res_open := _analyze_graph(open_all, w, h, wrap, start_idx)

	var strict := bool(opts.get("strictClearPath", false))
	var out_doors: Array = []
	var reasons: Array = []
	var warnings: Array = []
	var walled := 0
	var needing := 0
	for d in specs:
		var c3: Vector2i = d.cell
		var idx := -1
		if c3.x >= 0 and c3.x < w and c3.y >= 0 and c3.y < h:
			idx = c3.y * w + c3.x
		var reach_now := false
		var reach_open := false
		if idx >= 0:
			reach_now = _cell_reachable(res, base, w, h, idx, wrap)
			reach_open = _cell_reachable(res_open, open_all, w, h, idx, wrap)
		var needs_clearing: bool = (not reach_now) and reach_open
		var walled_off: bool = (not reach_now) and (not reach_open)
		var note := "reachable"
		if walled_off:
			walled += 1
			note = "walled off"
			reasons.append("door '" + d.name + "' at " + str(c3) + " is walled off")
		elif needs_clearing:
			needing += 1
			note = "needs clearing"
			warnings.append("door '" + d.name + "' at " + str(c3) + " is only reachable after clearing obstacles")
			if strict:
				reasons.append("door '" + d.name + "' at " + str(c3) + " needs clearing")
		elif d.state == "locked":
			note = "locked"
		out_doors.append({
			"name": d.name,
			"cell": c3,
			"state": d.state,
			"reachable": reach_now,
			"needsClearing": needs_clearing,
			"walledOff": walled_off,
			"note": note,
		})

	return {
		"ok": true,
		"pass": reasons.is_empty(),
		"doors": out_doors,
		"walledOff": walled,
		"needingClearing": needing,
		"reasons": reasons,
		"warnings": warnings,
	}
