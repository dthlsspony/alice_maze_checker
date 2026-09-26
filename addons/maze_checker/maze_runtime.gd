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
static func check_or_regenerate(cells, opts: Dictionary = {}) -> Dictionary:
	var report := analyze_cells(cells, opts)
	var verdict := judge(report, opts)
	return {
		"pass": verdict.pass,
		"action": verdict.action,
		"reasons": verdict.reasons,
		"report": report,
	}
