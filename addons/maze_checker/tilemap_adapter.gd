class_name TileMapAdapter
extends RefCounted

## Turns a TileMapLayer's placed cells into the ASCII grid MazeCore understands.
## Pure and engine-light: takes an array of Vector2i, returns a grid string.
##
## mode = "walls": the painted tiles ARE the walls (common for a painted maze).
##                  empty cells inside the bounding box become walkable floor.
## mode = "floor": the painted tiles are the walkable floor; everything else
##                  inside the box is a wall (common for tile-per-tile levels).

const FLOOR_CHAR := "."
const WALL_CHAR := "#"
const SOFT_CHAR := "o"


static func grid_from_cells(cells: Array, mode: String = "walls") -> Dictionary:
	if cells.is_empty():
		return {"text": "", "width": 0, "height": 0, "origin": Vector2i.ZERO, "empty": true}

	var min_x := 2147483647
	var min_y := 2147483647
	var max_x := -2147483648
	var max_y := -2147483648
	var used := {}
	for c in cells:
		var p: Vector2i = c
		used[p] = true
		min_x = min(min_x, p.x)
		min_y = min(min_y, p.y)
		max_x = max(max_x, p.x)
		max_y = max(max_y, p.y)

	var w: int = max_x - min_x + 1
	var h: int = max_y - min_y + 1
	var rows: PackedStringArray = []
	for y in range(min_y, max_y + 1):
		var line := ""
		for x in range(min_x, max_x + 1):
			var is_used: bool = used.has(Vector2i(x, y))
			var walkable: bool = (not is_used) if mode == "walls" else is_used
			line += FLOOR_CHAR if walkable else WALL_CHAR
		rows.append(line)
	return {
		"text": "\n".join(rows),
		"width": w,
		"height": h,
		"origin": Vector2i(min_x, min_y),
		"empty": false,
	}


## Same as grid_from_cells, but cells listed in `obstacle_cells` are written as
## the soft char (destructible obstacle) instead of floor/wall. The bounding box
## covers both sets, so an obstacle sitting outside the floor still shows up.
static func grid_from_cells_and_obstacles(cells: Array, mode: String, obstacle_cells: Array) -> Dictionary:
	var all: Array = []
	all.append_array(cells)
	all.append_array(obstacle_cells)
	if all.is_empty():
		return {"text": "", "width": 0, "height": 0, "origin": Vector2i.ZERO, "empty": true}
	var base: Dictionary = grid_from_cells(all, mode)
	var obstacles := {}
	for c in obstacle_cells:
		obstacles[c] = true
	var origin: Vector2i = base["origin"]
	var w: int = base["width"]
	var h: int = base["height"]
	var rows: PackedStringArray = []
	for y in range(origin.y, origin.y + h):
		var line := ""
		for x in range(origin.x, origin.x + w):
			var p := Vector2i(x, y)
			if obstacles.has(p):
				line += SOFT_CHAR
			else:
				var is_used: bool = false
				for c in cells:
					if c == p:
						is_used = true
						break
				var walkable: bool = (not is_used) if mode == "walls" else is_used
				line += FLOOR_CHAR if walkable else WALL_CHAR
		rows.append(line)
	return {"text": "\n".join(rows), "width": w, "height": h, "origin": origin, "empty": false}


## Maps a per-cell dictionary (Vector2i -> value) onto flat grid ids (y*w+x),
## using the origin/width of a grid built by grid_from_cells. Used for edge walls
## authored as tile custom data.
static func cell_dict_to_ids(by_cell: Dictionary, origin: Vector2i, width: int) -> Dictionary:
	var out: Dictionary = {}
	for p in by_cell.keys():
		var v: Vector2i = p
		var x: int = v.x - origin.x
		var y: int = v.y - origin.y
		if x < 0 or y < 0:
			continue
		out[y * width + x] = by_cell[p]
	return out
