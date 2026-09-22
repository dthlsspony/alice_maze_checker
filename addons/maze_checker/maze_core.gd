class_name MazeCore
extends RefCounted

## Grid reachability core, ported from the web Maze Checker.
## Pure logic: parse an ASCII grid, flood-fill from the start, report breaks.
## No engine dependencies, so it runs headless and inside an EditorPlugin.

static func parse_grid(text: String, wall_char: String = "#") -> Dictionary:
	var raw: PackedStringArray = text.replace("\r", "").split("\n")
	while raw.size() > 0 and raw[raw.size() - 1].strip_edges() == "":
		raw.remove_at(raw.size() - 1)
	while raw.size() > 0 and raw[0].strip_edges() == "":
		raw.remove_at(0)
	var height: int = raw.size()
	var width: int = 0
	for row in raw:
		if row.length() > width:
			width = row.length()
	var ragged := false
	var grid: Array = []
	for y in height:
		var row: String = raw[y]
		if row.length() != width:
			ragged = true
		var arr: Array = []
		for x in width:
			arr.append(row[x] if x < row.length() else wall_char)
		grid.append(arr)
	return {"grid": grid, "width": width, "height": height, "ragged": ragged}


static func _neighbors(walk: PackedByteArray, W: int, H: int, wrap: bool, x: int, y: int) -> Array:
	var out: Array = []
	if y > 0 and walk[(y - 1) * W + x] == 1:
		out.append(Vector2i(x, y - 1))
	if y < H - 1 and walk[(y + 1) * W + x] == 1:
		out.append(Vector2i(x, y + 1))
	if x > 0:
		if walk[y * W + (x - 1)] == 1:
			out.append(Vector2i(x - 1, y))
	elif wrap and W > 1 and walk[y * W + (W - 1)] == 1:
		out.append(Vector2i(W - 1, y))
	if x < W - 1:
		if walk[y * W + (x + 1)] == 1:
			out.append(Vector2i(x + 1, y))
	elif wrap and W > 1 and walk[y * W + 0] == 1:
		out.append(Vector2i(0, y))
	return out


static func analyze(text: String, opts: Dictionary = {}) -> Dictionary:
	var wall_char: String = opts.get("wallChar", "#")
	if typeof(wall_char) != TYPE_STRING or wall_char.length() != 1:
		wall_char = "#"
	var wrap: bool = bool(opts.get("wrap", false))
	var p: Dictionary = parse_grid(text, wall_char)
	var W: int = p.width
	var H: int = p.height
	var grid: Array = p.grid
	var N: int = W * H

	var walk := PackedByteArray()
	walk.resize(N)
	for y in H:
		for x in W:
			walk[y * W + x] = 0 if grid[y][x] == wall_char else 1

	# degree of each walkable cell (respecting wrap)
	var deg := PackedInt32Array()
	deg.resize(N)
	deg.fill(-1)
	var walkable := 0
	for y in H:
		for x in W:
			if walk[y * W + x] == 1:
				walkable += 1
				deg[y * W + x] = _neighbors(walk, W, H, wrap, x, y).size()

	# start: explicit 'P' if walkable, else first walkable cell
	var start_idx := -1
	var start_x := -1
	var start_y := -1
	for y in H:
		for x in W:
			if grid[y][x] == "P" and start_idx < 0:
				start_idx = y * W + x
				start_x = x
				start_y = y
	if start_idx < 0 or walk[start_idx] != 1:
		start_idx = -1
		for y in H:
			for x in W:
				if walk[y * W + x] == 1:
					start_idx = y * W + x
					start_x = x
					start_y = y
					break
			if start_idx >= 0:
				break

	# connected components of walkable cells
	var comp := PackedInt32Array()
	comp.resize(N)
	comp.fill(-1)
	var comps: Array = []
	for y in H:
		for x in W:
			var ii: int = y * W + x
			if walk[ii] != 1 or comp[ii] != -1:
				continue
			var cid: int = comps.size()
			var stack: Array = [ii]
			var size := 0
			var border := false
			comp[ii] = cid
			while stack.size() > 0:
				var cur: int = stack.pop_back()
				size += 1
				var cx: int = cur % W
				var cy: int = (cur - cx) / W
				if cx == 0 or cy == 0 or cx == W - 1 or cy == H - 1:
					border = true
				for n in _neighbors(walk, W, H, wrap, cx, cy):
					var ni: int = n.y * W + n.x
					if comp[ni] == -1:
						comp[ni] = cid
						stack.append(ni)
			comps.append({"size": size, "border": border})

	var start_comp := -1
	if start_idx >= 0:
		start_comp = comp[start_idx]
	if start_comp < 0 and comps.size() > 0:
		var best := 0
		for c in range(1, comps.size()):
			if comps[c].size > comps[best].size:
				best = c
		start_comp = best

	var unreachable := 0
	var dead_ends := 0
	var isolated := 0
	var pellets := 0
	var unreachable_pellets := 0
	var border_open := 0
	var enclosed := 0
	for ci in comps.size():
		if ci != start_comp and not comps[ci].border:
			enclosed += 1
	for y in H:
		for x in W:
			var j: int = y * W + x
			if walk[j] != 1:
				continue
			if comp[j] != start_comp:
				unreachable += 1
			if deg[j] == 1:
				dead_ends += 1
			if deg[j] == 0:
				isolated += 1
			if grid[y][x] == ".":
				pellets += 1
				if comp[j] != start_comp:
					unreachable_pellets += 1
			if x == 0 or y == 0 or x == W - 1 or y == H - 1:
				border_open += 1

	var issues: Array = []
	if walkable == 0:
		issues.append("no open cells at all: every tile is a wall.")
	if p.ragged:
		issues.append("rows have different lengths; short rows were padded with walls.")
	if comps.size() > 1:
		issues.append(str(comps.size()) + " separate open regions; " + str(unreachable) + " cell(s) unreachable from the start.")
	if unreachable_pellets > 0:
		issues.append(str(unreachable_pellets) + " pellet(s) sit in an unreachable region.")
	if isolated > 0:
		issues.append(str(isolated) + " isolated open cell(s) with no neighbour at all.")
	if enclosed > 0:
		issues.append(str(enclosed) + " unreachable region(s) are fully sealed (no opening to the outer edge).")
	if border_open > 0:
		issues.append(str(border_open) + " open cell(s) on the outer edge (tunnel mouths, or a leak).")
	if wrap and border_open > 0:
		issues.append("wrap is ON, so matching left/right edge cells on the same row are connected.")

	var status := "broken"
	if walkable == 0:
		status = "broken"
	elif unreachable > 0 or isolated > 0 or p.ragged:
		status = "broken"
	elif comps.size() > 1 or border_open > 0:
		status = "warn"
	else:
		status = "clean"
	if status != "broken" and comps.size() == 1 and unreachable == 0 and isolated == 0 and not p.ragged:
		status = "warn" if border_open > 0 else "clean"

	# per-cell class: 0 wall, 1 reachable, 2 unreachable, 3 dead end, 4 start
	var cls := PackedInt32Array()
	cls.resize(N)
	cls.fill(-1)
	for y in H:
		for x in W:
			var q: int = y * W + x
			if walk[q] != 1:
				cls[q] = 0
				continue
			if comp[q] != start_comp:
				cls[q] = 2
				continue
			if deg[q] == 1:
				cls[q] = 3
				continue
			cls[q] = 1
	if start_idx >= 0:
		cls[start_idx] = 4

	return {
		"ok": true,
		"width": W,
		"height": H,
		"wallChar": wall_char,
		"wrap": wrap,
		"ragged": p.ragged,
		"walkable": walkable,
		"walls": N - walkable,
		"comps": comps,
		"startComp": start_comp,
		"startX": start_x,
		"startY": start_y,
		"unreachable": unreachable,
		"deadEnds": dead_ends,
		"isolated": isolated,
		"pellets": pellets,
		"unreachablePellets": unreachable_pellets,
		"borderOpen": border_open,
		"enclosed": enclosed,
		"issues": issues,
		"status": status,
		"cls": cls,
		"grid": grid,
	}
