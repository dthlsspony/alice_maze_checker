extends SceneTree

## Exercises the runtime generator API headlessly: cells in, pass/regenerate out.
## Run: godot --headless --script res://addons/maze_checker/test_runtime.gd
const Rt = preload("res://addons/maze_checker/maze_runtime.gd")

var passed := 0
var fail := 0


func check(name: String, cond: bool, extra = null) -> void:
	if cond:
		passed += 1
		print("ok   " + name)
	else:
		fail += 1
		print("FAIL " + name + (" :: " + str(extra) if extra != null else ""))


func random_room(w: int, h: int, rng: RandomNumberGenerator, wall_pct: float) -> Array:
	var rows: Array = []
	for y in h:
		var row: Array = []
		for x in w:
			row.append(1 if rng.randf() < wall_pct else 0)
		rows.append(row)
	return rows


func _initialize() -> void:
	# --- cells -> grid ---
	var rows: Array = [
		[1, 1, 1, 1, 1],
		[1, 0, 0, 0, 1],
		[1, 0, 1, 0, 1],
		[1, 0, 0, 0, 1],
		[1, 1, 1, 1, 1],
	]
	var report: Dictionary = Rt.analyze_cells(rows)
	check("rows: 5x5", report.width == 5 and report.height == 5, {"w": report.width, "h": report.height})
	check("rows: clean room passes", Rt.judge(report).pass == true, {"issues": report.issues, "reasons": Rt.judge(report).reasons})
	check("rows: 1 region", report.comps.size() == 1, {"comps": report.comps.size()})

	# --- start marker anchors the report ---
	var s: Dictionary = Rt.analyze_cells(rows, {"start": Vector2i(3, 3)})
	check("start: honored", s.startX == 3 and s.startY == 3, {"sx": s.startX, "sy": s.startY})

	# --- flat PackedByteArray path ---
	var flat := PackedByteArray()
	for y in 5:
		for x in 5:
			flat.append(rows[y][x])
	var fr: Dictionary = Rt.analyze_cells(flat, {"width": 5, "height": 5})
	check("flat bytes: same walkable", fr.walkable == report.walkable, {"a": fr.walkable, "b": report.walkable})

	# --- all walls -> regenerate ---
	var solid := PackedByteArray()
	solid.resize(25)
	solid.fill(1)
	var sr: Dictionary = Rt.check_or_regenerate(solid, {"width": 5, "height": 5})
	check("solid: regenerate", sr.pass == false and sr.action == "regenerate", sr.reasons)
	check("solid: reason present", sr.reasons.size() > 0)

	# --- sealed pocket -> regenerate ---
	# a wall block in the middle with one lone floor cell trapped inside it
	var pocket: Array = []
	for y in 9:
		var row: Array = []
		for x in 9:
			var wall := (x == 0 or y == 0 or x == 8 or y == 8)
			if x >= 3 and x <= 5 and y >= 3 and y <= 5:
				wall = not (x == 4 and y == 4)
			row.append(1 if wall else 0)
		pocket.append(row)
	var pr: Dictionary = Rt.check_or_regenerate(pocket)
	check("pocket: regenerate", pr.pass == false, {"reasons": pr.reasons})
	check("pocket: unreachable named", int(pr.report.unreachable) > 0, {"unreachable": pr.report.unreachable})

	# --- edge openings are gated only when asked ---
	var open_room: Array = []
	for y in 6:
		var row: Array = []
		for x in 6:
			row.append(0)
		open_room.append(row)
	var orr: Dictionary = Rt.analyze_cells(open_room)
	check("edge: floor does reach the edge", int(orr.borderOpen) > 0, {"borderOpen": orr.borderOpen})
	check("edge: allowed by default", Rt.judge(orr).pass == true, Rt.judge(orr).reasons)
	check("edge: refused when asked", Rt.judge(orr, {"allowEdgeOpenings": false}).pass == false)

	# --- thin-floor gate ---
	var thin: Dictionary = Rt.judge({"walkable": 2, "width": 10, "height": 10, "comps": [{"size": 2}], "deadEnds": 0, "unreachable": 0, "isolated": 0, "ragged": false, "borderOpen": 0})
	check("thin: refused", thin.pass == false, thin.reasons)

	# --- a generator loop actually converges ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260926
	var tries := 0
	var accepted = null
	while tries < 200 and accepted == null:
		tries += 1
		var room := random_room(15, 11, rng, 0.32)
		var res: Dictionary = Rt.check_or_regenerate(room)
		if res.pass:
			accepted = room
	check("loop: found a passing floor", accepted != null, {"tries": tries})
	check("loop: converged quickly", tries < 200, {"tries": tries})

	# --- determinism: same seed, same accepted floor ---
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 20260926
	var accepted2 = null
	var t2 := 0
	while t2 < 200 and accepted2 == null:
		t2 += 1
		var room2 := random_room(15, 11, rng2, 0.32)
		if Rt.check_or_regenerate(room2).pass:
			accepted2 = room2
	check("loop: deterministic", str(accepted) == str(accepted2))
	check("loop: same try count", tries == t2, {"a": tries, "b": t2})

	# --- doors: name rule + reachability ---
	var droom: Array = [
		[1, 1, 1, 1, 1, 1, 1],
		[1, 0, 0, 0, 0, 0, 1],
		[1, 0, 1, 1, 1, 0, 1],
		[1, 0, 0, 0, 0, 0, 1],
		[1, 1, 1, 1, 1, 1, 1],
	]
	var closed_door: Dictionary = Rt.check_doors(droom, [{"name": "Door_A", "cell": Vector2i(3, 2), "state": "closed"}], {"start": Vector2i(1, 1)})
	check("door: closed door reachable from spawn", closed_door.doors[0].reachable == true, closed_door.doors)
	check("door: closed door not needing clearing", closed_door.doors[0].needsClearing == false, closed_door.doors)
	check("door: clean floor passes", closed_door.pass == true, closed_door.reasons)

	var open_door: Dictionary = Rt.check_doors(droom, [{"name": "Door_A", "cell": Vector2i(3, 2), "state": "open"}], {"start": Vector2i(1, 1)})
	check("door: open door is passable", open_door.doors[0].reachable == true and open_door.doors[0].needsClearing == false, open_door.doors)

	# a door whose only approach is through a destructible obstacle
	var block_room: Array = [
		[1, 1, 1, 1, 1, 1, 1],
		[1, 0, 0, 0, 0, 0, 1],
		[1, 1, 1, 1, 1, 1, 1],
	]
	var br: Dictionary = Rt.check_doors(block_room, [{"name": "Door_B", "cell": Vector2i(4, 1), "state": "closed"}], {"start": Vector2i(1, 1), "obstacles": [Vector2i(2, 1)]})
	check("door: needs clearing detected", br.doors[0].needsClearing == true, br.doors)
	check("door: needs clearing warns, not fails, by default", br.pass == true and br.warnings.size() == 1, br)
	var brs: Dictionary = Rt.check_doors(block_room, [{"name": "Door_B", "cell": Vector2i(4, 1), "state": "closed"}], {"start": Vector2i(1, 1), "obstacles": [Vector2i(2, 1)], "strictClearPath": true})
	check("door: strictClearPath flags it", brs.pass == false, brs.reasons)

	# a door sealed behind a permanent wall can never be used
	var sealed_room: Array = [
		[1, 1, 1, 1, 1, 1, 1],
		[1, 0, 1, 0, 1, 1, 1],
		[1, 1, 1, 1, 1, 1, 1],
	]
	var wr: Dictionary = Rt.check_doors(sealed_room, [{"name": "Door_C", "cell": Vector2i(3, 1), "state": "closed"}], {"start": Vector2i(1, 1)})
	check("door: walled off detected", wr.doors[0].walledOff == true, wr.doors)
	check("door: walled off fails", wr.pass == false and wr.reasons.size() == 1, wr.reasons)

	# locked doors are reported, not treated as a break by themselves
	var lr: Dictionary = Rt.check_doors(droom, [{"name": "Door_A", "cell": Vector2i(3, 2), "state": "locked"}], {"start": Vector2i(1, 1)})
	check("door: locked reported", lr.doors[0].note == "locked", lr.doors)
	check("door: locked does not fail", lr.pass == true, lr.reasons)

	# name rule + state reading
	var named: Array = Rt.doors_from_named([
		{"name": "Door_A", "cell": Vector2i(3, 2), "state": "locked"},
		{"name": "wall_1", "cell": Vector2i(0, 0)},
		{"name": "big_DOOR", "cell": Vector2i(1, 1)},
		{"name": "crate", "cell": Vector2i(2, 1), "locked": true},
		{"name": "Gate_North", "cell": Vector2i(5, 1)},
	])
	check("door: naming helper keeps doors and gates", named.size() == 3, named)
	check("door: locked state read", named[0].state == "locked", named[0])
	check("door: name match is case-insensitive", named[1].name == "big_DOOR", named[1])
	check("door: default state is closed", named[1].state == "closed", named[1])
	check("door: gate counts too", named[2].name == "Gate_North" and named[2].state == "closed", named[2])
	var only_doors: Array = Rt.doors_from_named([{"name": "Gate_North", "cell": Vector2i(5, 1)}], {"keywords": ["door"]})
	check("door: keyword list is overridable", only_doors.size() == 0, only_doors)

	# wired into the generation gate
	var cr: Dictionary = Rt.check_or_regenerate(droom, {"start": Vector2i(1, 1), "doors": [{"name": "Door_A", "cell": Vector2i(3, 2), "state": "closed"}]})
	check("door: exposed on check_or_regenerate", cr.has("doors") and cr.doors.pass == true, cr.keys())
	var cr_bad: Dictionary = Rt.check_or_regenerate(sealed_room, {"start": Vector2i(1, 1), "doors": [{"name": "Door_C", "cell": Vector2i(3, 1), "state": "closed"}]})
	check("door: a walled-off door forces regenerate", cr_bad.pass == false and cr_bad.action == "regenerate", cr_bad.reasons)

	print("\n" + str(passed) + " passed, " + str(fail) + " failed")
	quit(1 if fail > 0 else 0)
