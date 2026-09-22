extends SceneTree

## Exercises the generalized graph core and the shape providers headlessly.
## Run: godot --headless --script res://addons/maze_checker/test_graph.gd
const G = preload("res://addons/maze_checker/graph_core.gd")
const S = preload("res://addons/maze_checker/shapes.gd")

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
	# --- a plain open chain: 0-1-2-3 ---
	var chain := G.analyze({"count": 4, "edges": [[0, 1], [1, 2], [2, 3]], "start": [0]})
	check("chain: reachable all", chain.unreachable == 0, chain)
	check("chain: 1 region", chain.comps.size() == 1, chain.comps)
	check("chain: 2 dead ends", chain.deadEnds == 2, chain.deadEnds)

	# --- permanent wall edge splits it ---
	var split := G.analyze({"count": 4, "edges": [[0, 1], [1, 2], [2, 3, G.WALL]], "start": [0]})
	check("split: 2 regions", split.comps.size() == 2, split.comps)
	check("split: unreachable 1", split.unreachable == 1, split.unreachable)
	check("split: broken", split.status == "broken", split.status)

	# --- destructible edge: removing it reconnects ---
	var soft := G.analyze({"count": 4, "edges": [[0, 1], [1, 2], [2, 3, G.SOFT]], "start": [0]})
	check("soft: still split", soft.comps.size() == 2, soft.comps)
	check("soft: one leverage item", soft.leverage.size() == 1, soft.leverage)
	check("soft: gain 1", soft.leverage.size() > 0 and soft.leverage[0]["gain"] == 1, soft.leverage)
	check("soft: kind edge", soft.leverage.size() > 0 and soft.leverage[0]["kind"] == "edge", soft.leverage)

	# --- destructible node joins two branches ---
	var softnode := G.analyze({
		"count": 5,
		"edges": [[0, 1], [1, 2], [2, 3], [3, 4]],
		"nodeState": {2: G.SOFT},
		"start": [0],
	})
	check("softnode: 2 regions", softnode.comps.size() == 2, softnode.comps)
	check("softnode: leverage found", softnode.leverage.size() == 1, softnode.leverage)
	check("softnode: gain 2", softnode.leverage.size() > 0 and softnode.leverage[0]["gain"] == 2, softnode.leverage)
	check("softnode: kind node", softnode.leverage.size() > 0 and softnode.leverage[0]["kind"] == "node", softnode.leverage)

	# --- isolated and sealed ---
	var iso := G.analyze({"count": 3, "edges": [[0, 1]], "start": [0]})
	check("iso: node 2 isolated", iso.isolated == 1, iso.isolated)
	check("iso: broken", iso.status == "broken", iso.status)

	var sealed := G.analyze({"count": 5, "edges": [[0, 1], [2, 3], [3, 4]], "start": [0], "border": [0, 1]})
	check("sealed: 1 sealed pocket", sealed.sealed == 1, sealed.sealed)

	# --- empty spec is handled, not crashed ---
	var none := G.analyze({"count": 0})
	check("empty: not ok", none.ok == false)

	# --- links graph (geomap) ---
	var links := S.from_links(5, [[0, 1], [1, 2], [3, 4], [2, 3]], {"start": [0]})
	var lr := G.analyze(links)
	check("links: all reachable", lr.unreachable == 0, lr.issues)

	# --- square grid with edge walls ---
	var txt := "\n".join(["....", "....", "...."])
	var plain := G.analyze(S.from_square_text(txt, {"wallChar": "#"}))
	check("square: 12 nodes", plain.count == 12, plain.count)
	check("square: 1 region", plain.comps.size() == 1, plain.comps)

	# block every vertical connection across the middle row boundary
	var masks := {}
	for x in 4:
		masks[4 + x] = S.DIR_S   # cells (x,1) block south
	var walled := G.analyze(S.from_square_text(txt, {"wallChar": "#", "edgeMask": masks}))
	check("edge walls: split in two", walled.comps.size() == 2, walled.comps)
	check("edge walls: unreachable 4", walled.unreachable == 4, walled.unreachable)

	# --- wrap joins left and right edges ---
	var wtext := "\n".join(["...."])
	var wplain := G.analyze(S.from_square_text(wtext, {"wallChar": "#"}))
	check("no wrap: 1 row is a path", wplain.comps.size() == 1, wplain.comps)
	check("no wrap: 2 dead ends", wplain.deadEnds == 2, wplain.deadEnds)
	var wwrap := G.analyze(S.from_square_text(wtext, {"wallChar": "#", "wrap": true}))
	check("wrap: no dead ends", wwrap.deadEnds == 0, wwrap.deadEnds)

	# --- hex grid: an interior cell has 6 neighbours ---
	var hex := "\n".join(["...", "....", "..."])
	var hspec := S.from_hex_text(hex, {"wallChar": "#"})
	var hr := G.analyze(hspec)
	check("hex: 1 region", hr.comps.size() == 1, hr.comps)
	# cell (1,1) is interior in odd-r with width 4
	var cid := 1 * 4 + 1
	check("hex: interior degree 6", hr.deg[cid] == 6, {"deg": hr.deg[cid], "id": cid})

	# --- start falls back to the first open cell ---
	var fb := G.analyze(S.from_square_text("#...\n#...", {"wallChar": "#"}))
	check("fallback start: reachable", fb.unreachable == 0, fb.issues)

	# --- format_report does not crash on a soft-edge case ---
	var rep := G.format_report(soft, "test")
	check("report: mentions remove", rep.find("remove") != -1, rep)

	print("\n" + str(passed) + " passed, " + str(fail) + " failed")
	quit(1 if fail > 0 else 0)
