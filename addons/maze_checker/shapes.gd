class_name MazeShapes
extends RefCounted

## Builds a graph spec (for MazeGraph.analyze) out of a shape:
##   - a square grid parsed from text (the classic Maze Checker board)
##   - a hex grid (odd-r offset, 6 neighbours)
##   - an explicit link list (a "geomap": arbitrary nodes and connections)
## Walls can live on cells (wall tiles) or on the EDGE between two cells
## (edge walls), which is why the graph spec, not the grid, is the source of truth.

const OPEN := 0
const WALL := 1
const SOFT := 2

const DIR_N := 1
const DIR_E := 2
const DIR_S := 4
const DIR_W := 8

const _BIG := 1000000


static func _key(a: int, b: int) -> int:
	if a > b:
		var t := a
		a = b
		b = t
	return a * _BIG + b


static func _mask_dir(mask: int, dir: int) -> bool:
	return (mask & dir) != 0


## Square grid from text.
## opts: wallChar (default "#"), softChar (default "o"), startChar (default "P"),
##       wrap (bool), edgeMask (Dictionary id -> int bitmask of blocked sides)
static func from_square_text(text: String, opts: Dictionary = {}) -> Dictionary:
	var wall_char: String = str(opts.get("wallChar", "#"))
	var soft_char: String = str(opts.get("softChar", "o"))
	var start_char: String = str(opts.get("startChar", "P"))
	var wrap: bool = bool(opts.get("wrap", false))
	var edge_mask: Dictionary = opts.get("edgeMask", {})

	var raw: PackedStringArray = text.replace("\r", "").split("\n")
	while raw.size() > 0 and raw[raw.size() - 1].strip_edges() == "":
		raw.remove_at(raw.size() - 1)
	while raw.size() > 0 and raw[0].strip_edges() == "":
		raw.remove_at(0)
	var h: int = raw.size()
	var w := 0
	for row in raw:
		if row.length() > w:
			w = row.length()
	if w == 0 or h == 0:
		return {"count": 0, "edges": [], "nodeState": {}, "start": [0], "border": []}

	var node_state: Dictionary = {}
	var start_ids: Array = []
	var border: Array = []
	var grid: Array = []
	for y in h:
		var row: String = raw[y]
		var arr: Array = []
		for x in w:
			var ch := wall_char
			if x < row.length():
				ch = row[x]
			arr.append(ch)
			var id := y * w + x
			if ch == wall_char:
				node_state[id] = WALL
			elif ch == soft_char:
				node_state[id] = SOFT
			else:
				node_state[id] = OPEN
				if ch == start_char:
					start_ids.append(id)
				if x == 0 or y == 0 or x == w - 1 or y == h - 1:
					border.append(id)
		grid.append(arr)

	var edges: Array = []
	var seen: Dictionary = {}
	for y in h:
		for x in w:
			var id := y * w + x
			# east
			var ex := x + 1
			if ex >= w and wrap:
				ex = 0
			if ex < w:
				var eid := y * w + ex
				_add_edge(edges, seen, id, eid, _edge_state(id, eid, edge_mask, DIR_E, DIR_W))
			# south
			if y + 1 < h:
				var sid := (y + 1) * w + x
				_add_edge(edges, seen, id, sid, _edge_state(id, sid, edge_mask, DIR_S, DIR_N))

	if start_ids.is_empty():
		# fall back to the first open cell
		for y in h:
			var found := false
			for x in w:
				var id := y * w + x
				if node_state.get(id, OPEN) == OPEN:
					start_ids.append(id)
					found = true
					break
			if found:
				break

	return {
		"count": w * h, "width": w, "height": h, "grid": grid,
		"edges": edges, "nodeState": node_state,
		"start": start_ids, "border": border, "wrap": wrap,
	}


static func _edge_state(a: int, b: int, edge_mask: Dictionary, dir_ab: int, dir_ba: int) -> int:
	if edge_mask.is_empty():
		return OPEN
	var ma := int(edge_mask.get(a, 0))
	var mb := int(edge_mask.get(b, 0))
	if _mask_dir(ma, dir_ab) or _mask_dir(mb, dir_ba):
		return WALL
	return OPEN


static func _add_edge(edges: Array, seen: Dictionary, a: int, b: int, state: int) -> void:
	var k := _key(a, b)
	if seen.has(k):
		return
	seen[k] = true
	edges.append([a, b, state])


## Hex grid (odd-r offset, odd rows shifted right), 6 neighbours.
## opts: same chars as square, plus edgeMask.
static func from_hex_text(text: String, opts: Dictionary = {}) -> Dictionary:
	var wall_char: String = str(opts.get("wallChar", "#"))
	var soft_char: String = str(opts.get("softChar", "o"))
	var start_char: String = str(opts.get("startChar", "P"))
	var edge_mask: Dictionary = opts.get("edgeMask", {})

	var raw: PackedStringArray = text.replace("\r", "").split("\n")
	while raw.size() > 0 and raw[raw.size() - 1].strip_edges() == "":
		raw.remove_at(raw.size() - 1)
	while raw.size() > 0 and raw[0].strip_edges() == "":
		raw.remove_at(0)
	var h: int = raw.size()
	var w := 0
	for row in raw:
		if row.length() > w:
			w = row.length()
	if w == 0 or h == 0:
		return {"count": 0, "edges": [], "nodeState": {}, "start": [0], "border": []}

	var node_state: Dictionary = {}
	var start_ids: Array = []
	var border: Array = []
	for y in h:
		var row: String = raw[y]
		for x in w:
			var ch := wall_char
			if x < row.length():
				ch = row[x]
			var id := y * w + x
			if ch == wall_char:
				node_state[id] = WALL
			elif ch == soft_char:
				node_state[id] = SOFT
			else:
				node_state[id] = OPEN
				if ch == start_char:
					start_ids.append(id)
				if x == 0 or y == 0 or x == w - 1 or y == h - 1:
					border.append(id)

	var edges: Array = []
	var seen: Dictionary = {}
	for y in h:
		for x in w:
			var id := y * w + x
			var odd: bool = (y % 2) == 1
			# east / west
			if x + 1 < w:
				_add_edge(edges, seen, id, y * w + (x + 1), _hex_edge(id, y * w + (x + 1), edge_mask, DIR_E, DIR_W))
			# north
			var nx := x + 1 if odd else x
			if y - 1 >= 0 and nx < w:
				var nid := (y - 1) * w + nx
				_add_edge(edges, seen, id, nid, _hex_edge(id, nid, edge_mask, DIR_N, DIR_S))
			# south
			var sx := x + 1 if odd else x
			if y + 1 < h and sx < w:
				var sid := (y + 1) * w + sx
				_add_edge(edges, seen, id, sid, _hex_edge(id, sid, edge_mask, DIR_S, DIR_N))

	if start_ids.is_empty():
		for y in h:
			var found := false
			for x in w:
				var id := y * w + x
				if node_state.get(id, OPEN) == OPEN:
					start_ids.append(id)
					found = true
					break
			if found:
				break

	return {
		"count": w * h, "width": w, "height": h,
		"edges": edges, "nodeState": node_state,
		"start": start_ids, "border": border, "shape": "hex",
	}


static func _hex_edge(a: int, b: int, edge_mask: Dictionary, dir_ab: int, dir_ba: int) -> int:
	return _edge_state(a, b, edge_mask, dir_ab, dir_ba)


## Explicit graph (geomap-style): nodes 0..count-1, edges are pairs.
## opts: border (Array of ids), start (Array of ids)
static func from_links(count: int, pairs: Array, opts: Dictionary = {}) -> Dictionary:
	var edges: Array = []
	var seen: Dictionary = {}
	for p in pairs:
		if typeof(p) != TYPE_ARRAY or p.size() < 2:
			continue
		var a := int(p[0])
		var b := int(p[1])
		if a == b or a < 0 or b < 0 or a >= count or b >= count:
			continue
		var st := OPEN
		if p.size() >= 3:
			st = int(p[2])
		_add_edge(edges, seen, a, b, st)
	var start: Array = opts.get("start", [0])
	return {
		"count": count, "edges": edges, "nodeState": {},
		"start": start, "border": opts.get("border", []), "shape": "links",
	}
