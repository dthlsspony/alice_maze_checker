extends SceneTree

## Exercises the TileMapLayer -> ASCII grid adapter headlessly.
const Adapter = preload("res://addons/maze_checker/tilemap_adapter.gd")
const Core = preload("res://addons/maze_checker/maze_core.gd")

var passed := 0
var fail := 0

func check(name: String, cond: bool, extra = null) -> void:
	if cond:
		passed += 1
		print("ok   " + name)
	else:
		fail += 1
		print("FAIL " + name + (" :: " + str(extra) if extra != null else ""))


func ring_cells(ox: int, oy: int, w: int, h: int) -> Array:
	var cells: Array = []
	for x in range(ox, ox + w):
		cells.append(Vector2i(x, oy))
		cells.append(Vector2i(x, oy + h - 1))
	for y in range(oy + 1, oy + h - 1):
		cells.append(Vector2i(ox, y))
		cells.append(Vector2i(ox + w - 1, y))
	return cells


func _initialize() -> void:
	# empty
	var e: Dictionary = Adapter.grid_from_cells([], "walls")
	check("empty: flagged", e.empty == true)

	# painted walls form a closed box -> interior floor, clean
	var box: Dictionary = Adapter.grid_from_cells(ring_cells(0, 0, 7, 5), "walls")
	check("box: 7x5", box.width == 7 and box.height == 5, {"w": box.width, "h": box.height})
	check("box: origin 0,0", box.origin == Vector2i.ZERO)
	var rb: Dictionary = Core.analyze(box.text, {"wallChar": "#"})
	check("box: clean", rb.status == "clean", {"status": rb.status, "issues": rb.issues})
	check("box: enclosed 0", rb.enclosed == 0, {"enclosed": rb.enclosed})

	# painted walls form a box with a sealed inner ring -> pocket found
	var cells: Array = ring_cells(0, 0, 9, 7)
	cells.append_array(ring_cells(3, 2, 3, 3))
	var p: Dictionary = Adapter.grid_from_cells(cells, "walls")
	var rp: Dictionary = Core.analyze(p.text, {"wallChar": "#"})
	check("pocket: broken", rp.status == "broken", {"status": rp.status})
	check("pocket: sealed >= 1", rp.enclosed >= 1, {"enclosed": rp.enclosed, "issues": rp.issues})

	# painted floor: a cross of floor tiles, rest walls
	var floor_cells: Array = []
	for x in range(0, 7):
		floor_cells.append(Vector2i(x, 3))
	for y in range(0, 7):
		floor_cells.append(Vector2i(3, y))
	var f: Dictionary = Adapter.grid_from_cells(floor_cells, "floor")
	var rf: Dictionary = Core.analyze(f.text, {"wallChar": "#"})
	check("floor: 1 region", rf.comps.size() == 1, {"comps": rf.comps.size(), "issues": rf.issues})
	check("floor: 4 dead ends", rf.deadEnds == 4, {"deadEnds": rf.deadEnds})
	check("floor: edge openings", rf.borderOpen == 4, {"borderOpen": rf.borderOpen})

	# offset cells: origin is the min cell, grid starts there
	var off: Dictionary = Adapter.grid_from_cells([Vector2i(10, 20), Vector2i(11, 20), Vector2i(10, 21)], "floor")
	check("offset: origin 10,20", off.origin == Vector2i(10, 20), {"origin": off.origin})
	check("offset: 2x2", off.width == 2 and off.height == 2)

	print("\n" + str(passed) + " passed, " + str(fail) + " failed")
	quit(1 if fail > 0 else 0)
