extends SceneTree

## Port of mazecheck/test_core.js. Exercises the ported GDScript core headlessly.
const Core = preload("res://addons/maze_checker/maze_core.gd")
## Run: godot --headless --script res://test_core.gd

var passed := 0
var fail := 0

func check(name: String, cond: bool, extra = null) -> void:
	if cond:
		passed += 1
		print("ok   " + name)
	else:
		fail += 1
		print("FAIL " + name + (" :: " + str(extra) if extra != null else ""))


func _initialize() -> void:
	var sample := "\n".join([
		"###################",
		"#........#........#",
		"#.##.###.#.###.##.#",
		"#.#...............#",
		"#.#.##.#####.##.#.#",
		"#......#...#......#",
		"####.#.# # #.#.####",
		"...................",
		"###################",
	])
	var a: Dictionary = Core.analyze(sample, {"wallChar": "#", "wrap": false})
	check("sample: 1 region", a.comps.size() == 1, {"comps": a.comps.size(), "unreachable": a.unreachable, "issues": a.issues})
	check("sample: no unreachable", a.unreachable == 0)
	check("sample: no isolated", a.isolated == 0)
	check("sample: tunnel mouths on edge", a.borderOpen == 2, {"borderOpen": a.borderOpen})
	check("sample: status warn (edge openings)", a.status == "warn", {"status": a.status})

	var aw: Dictionary = Core.analyze(sample, {"wallChar": "#", "wrap": true})
	check("sample wrap: still 1 region", aw.comps.size() == 1, {"comps": aw.comps.size()})

	var pocket := "\n".join([
		"#########",
		"#.......#",
		"#.#####.#",
		"#.#...#.#",
		"#.#####.#",
		"#.......#",
		"#########",
	])
	var b: Dictionary = Core.analyze(pocket, {"wallChar": "#"})
	check("pocket: >1 region", b.comps.size() > 1, {"comps": b.comps.size(), "issues": b.issues})
	check("pocket: unreachable > 0", b.unreachable > 0, {"unreachable": b.unreachable})
	check("pocket: broken", b.status == "broken", {"status": b.status})

	var c: Dictionary = Core.analyze("#####\n#####\n#####", {"wallChar": "#"})
	check("all walls: walkable 0", c.walkable == 0)
	check("all walls: broken", c.status == "broken", {"status": c.status})

	var stuck := "\n".join([
		"#########",
		"#.......#",
		"#########",
		"#...#...#",
		"#...#...#",
		"#########",
	])
	var d: Dictionary = Core.analyze(stuck, {"wallChar": "#"})
	check("stuck pellets: counted", d.unreachablePellets > 0, {"pellets": d.pellets, "stuck": d.unreachablePellets, "comps": d.comps.size()})

	var e: Dictionary = Core.analyze("#...\n#..\n####", {"wallChar": "#"})
	check("ragged: flagged", e.ragged == true)
	check("ragged: width = longest row", e.width == 4, {"width": e.width})

	var with_p := "\n".join([
		"#######",
		"#P....#",
		"#.###.#",
		"#.....#",
		"#######",
	])
	var f: Dictionary = Core.analyze(with_p, {"wallChar": "#"})
	check("P: start found", f.startX == 1 and f.startY == 1, {"x": f.startX, "y": f.startY})
	check("P: clean", f.status == "clean", {"status": f.status, "issues": f.issues})

	var de: Dictionary = Core.analyze("#....#\n######", {"wallChar": "#"})
	check("dead ends: found", de.deadEnds == 2, {"deadEnds": de.deadEnds})

	var box := "\n".join([
		"#######",
		"#.....#",
		"#.###.#",
		"#.....#",
		"#######",
	])
	var g1: Dictionary = Core.analyze(box, {"wallChar": "#"})
	check("box: enclosed is 0 (start region not a pocket)", g1.enclosed == 0, {"enclosed": g1.enclosed, "issues": g1.issues})
	var box_issue := false
	for i in g1.issues:
		if str(i).to_lower().find("sealed") != -1:
			box_issue = true
	check("box: no sealed-pocket issue", not box_issue, {"issues": g1.issues})

	var box_pocket := "\n".join([
		"#########",
		"#.......#",
		"#.#####.#",
		"#.#...#.#",
		"#.#####.#",
		"#.......#",
		"#########",
	])
	var g2: Dictionary = Core.analyze(box_pocket, {"wallChar": "#"})
	check("pocket: enclosed counts the pocket", g2.enclosed >= 1, {"enclosed": g2.enclosed})
	var pocket_issue := false
	for i in g2.issues:
		if str(i).to_lower().find("sealed") != -1:
			pocket_issue = true
	check("pocket: sealed-pocket issue present", pocket_issue, {"issues": g2.issues})

	print("\n" + str(passed) + " passed, " + str(fail) + " failed")
	quit(1 if fail > 0 else 0)
