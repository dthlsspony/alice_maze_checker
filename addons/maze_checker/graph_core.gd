class_name MazeGraph
extends RefCounted

## Generic reachability core: nodes + edges.
##
## This is the generalization of the grid flood fill. Anything you can draw as
## a graph of cells and connections can be checked with the same pass:
##   - a square grid is nodes on a lattice, edges to the 4 (or 8) neighbours
##   - a hex grid is the same idea with 6 neighbours
##   - a "geomap" with arbitrary links is just an explicit edge list
##   - walls that live on the EDGE between two cells are blocked edges
##
## Every node and every edge carries a state:
##   OPEN  always passable
##   WALL  permanently blocked (a wall tile, a fixed wall)
##   SOFT  blocked, but removable (a destructible obstacle)
## The SOFT state is what lets us answer the question a level designer actually
## asks: "if I blow up ONE thing, which one buys me the most floor?"
##
## Pure logic, no engine dependencies, so it runs headless in tests and inside
## an EditorPlugin.

enum { OPEN = 0, WALL = 1, SOFT = 2 }

const _NO_NODE := -1


static func _norm_state(v) -> int:
	if v == null:
		return OPEN
	var s := int(v)
	if s < OPEN or s > SOFT:
		return OPEN
	return s


## spec = {
##   count: int,                     # node ids are 0 .. count-1
##   edges: Array,                   # [ [u, v] or [u, v, state], ... ]
##   nodeState: Dictionary,          # id -> state (default OPEN)
##   start: Array or int,            # start node id(s); default [0]
##   border: Array,                  # node ids touching the outside
##   softBudget: int,                # how many soft things we may remove (default 1)
##   labels: Dictionary,             # id -> human label, for messages
## }
static func analyze(spec: Dictionary) -> Dictionary:
	var count: int = int(spec.get("count", 0))
	if count <= 0:
		return _empty_result("no nodes to check.")

	var node_state := PackedInt32Array()
	node_state.resize(count)
	node_state.fill(OPEN)
	var raw_nodes: Dictionary = spec.get("nodeState", {})
	for k in raw_nodes.keys():
		var i := int(k)
		if i >= 0 and i < count:
			node_state[i] = _norm_state(raw_nodes[k])

	# adjacency: id -> Array of [neighbour_id, edge_state]
	var adj: Array = []
	adj.resize(count)
	for i in count:
		adj[i] = []
	var soft_edges: Array = []   # [ [u, v] ]
	var wall_edges := 0
	var raw_edges: Array = spec.get("edges", [])
	for e in raw_edges:
		if typeof(e) != TYPE_ARRAY or e.size() < 2:
			continue
		var u := int(e[0])
		var v := int(e[1])
		if u < 0 or v < 0 or u >= count or v >= count or u == v:
			continue
		var st: int = OPEN
		if e.size() >= 3:
			st = _norm_state(e[2])
		adj[u].append([v, st])
		adj[v].append([u, st])
		if st == SOFT:
			soft_edges.append([u, v])
		elif st == WALL:
			wall_edges += 1

	# base passable graph: node is open, edge is OPEN
	var passable := PackedByteArray()
	passable.resize(count)
	for i in count:
		passable[i] = 1 if node_state[i] == OPEN else 0

	var deg := PackedInt32Array()
	deg.resize(count)
	deg.fill(0)
	for i in count:
		if passable[i] == 0:
			continue
		var d := 0
		for pair in adj[i]:
			if passable[pair[0]] == 1 and pair[1] == OPEN:
				d += 1
		deg[i] = d

	var start_ids: Array = _as_id_array(spec.get("start", [0]), count)
	var border_ids: Dictionary = {}
	for b in _as_id_array(spec.get("border", []), count):
		border_ids[b] = true

	# connected components over the base passable graph
	var comp := PackedInt32Array()
	comp.resize(count)
	comp.fill(_NO_NODE)
	var comps: Array = []
	for i in count:
		if passable[i] == 0 or comp[i] != _NO_NODE:
			continue
		var cid: int = comps.size()
		var stack: Array = [i]
		var size := 0
		var touches_border := false
		comp[i] = cid
		while stack.size() > 0:
			var cur: int = stack.pop_back()
			size += 1
			if border_ids.has(cur):
				touches_border = true
			for pair in adj[cur]:
				var nxt: int = pair[0]
				if passable[nxt] == 1 and pair[1] == OPEN and comp[nxt] == _NO_NODE:
					comp[nxt] = cid
					stack.append(nxt)
		comps.append({"size": size, "border": touches_border})

	var start_comp := -1
	for s in start_ids:
		if passable[s] == 1:
			start_comp = comp[s]
			break
	if start_comp < 0 and comps.size() > 0:
		var best := 0
		for c in range(1, comps.size()):
			if comps[c].size > comps[best].size:
				best = c
		start_comp = best

	var walkable := 0
	for i in count:
		if passable[i] == 1:
			walkable += 1

	var unreachable := 0
	var dead_ends := 0
	var isolated := 0
	var sealed := 0
	var border_open := 0
	for i in count:
		if passable[i] == 0:
			continue
		if comp[i] != start_comp:
			unreachable += 1
		if deg[i] == 1:
			dead_ends += 1
		elif deg[i] == 0:
			isolated += 1
		if border_ids.has(i):
			border_open += 1
	for ci in comps.size():
		if ci != start_comp and not comps[ci].border:
			sealed += 1

	# destructible leverage: what does removing ONE soft thing reconnect?
	var leverage := _leverage(adj, node_state, comp, comps, start_comp, soft_edges, count)

	# per-node class: 0 blocked, 1 reachable, 2 unreachable, 3 dead end, 4 start
	var cls := PackedInt32Array()
	cls.resize(count)
	cls.fill(0)
	for i in count:
		if passable[i] == 0:
			cls[i] = 0
		elif comp[i] != start_comp:
			cls[i] = 2
		elif deg[i] == 1:
			cls[i] = 3
		else:
			cls[i] = 1
	for s in start_ids:
		if s >= 0 and s < count and passable[s] == 1:
			cls[s] = 4

	var soft_nodes := 0
	for i in count:
		if node_state[i] == SOFT:
			soft_nodes += 1
	var soft_total := soft_nodes + soft_edges.size()

	var issues: Array = []
	if walkable == 0:
		issues.append("no open cells at all: every tile is a wall.")
	if comps.size() > 1:
		issues.append(str(comps.size()) + " separate open regions; " + str(unreachable) + " cell(s) unreachable from the start.")
	if isolated > 0:
		issues.append(str(isolated) + " isolated open cell(s) with no neighbour at all.")
	if sealed > 0:
		issues.append(str(sealed) + " unreachable region(s) are fully sealed (no opening to the outside).")
	if border_open > 0:
		issues.append(str(border_open) + " open cell(s) on the outside edge (tunnel mouths, or a leak).")
	if soft_total > 0:
		var best: int = leverage[0]["gain"] if leverage.size() > 0 else 0
		issues.append(str(soft_total) + " destructible obstacle(s); best single removal reconnects " + str(best) + " cell(s).")

	var status := "clean"
	if walkable == 0 or unreachable > 0 or isolated > 0:
		status = "broken"
	elif comps.size() > 1 or border_open > 0:
		status = "warn"

	return {
		"ok": true,
		"count": count,
		"walkable": walkable,
		"walls": count - walkable,
		"wallEdges": wall_edges,
		"softEdges": soft_edges.size(),
		"softNodes": soft_nodes,
		"softTotal": soft_total,
		"comps": comps,
		"startComp": start_comp,
		"unreachable": unreachable,
		"deadEnds": dead_ends,
		"isolated": isolated,
		"sealed": sealed,
		"borderOpen": border_open,
		"leverage": leverage,
		"issues": issues,
		"status": status,
		"cls": cls,
		"comp": comp,
		"deg": deg,
	}


static func _leverage(adj: Array, node_state: PackedInt32Array, comp: PackedInt32Array,
		comps: Array, start_comp: int, soft_edges: Array, count: int) -> Array:
	var out: Array = []
	# a soft EDGE between two base-passable nodes
	for pair in soft_edges:
		var u: int = pair[0]
		var v: int = pair[1]
		if node_state[u] != OPEN or node_state[v] != OPEN:
			continue
		var cu: int = comp[u]
		var cv: int = comp[v]
		if cu < 0 or cv < 0 or cu == cv:
			continue
		var gain := 0
		if cu != start_comp:
			gain += comps[cu].size
		if cv != start_comp:
			gain += comps[cv].size
		if gain > 0:
			out.append({"kind": "edge", "u": u, "v": v, "gain": gain,
				"label": "wall between " + str(u) + " and " + str(v)})

	# a soft NODE: removing it makes it walkable and joins its open neighbours
	for n in count:
		if node_state[n] != SOFT:
			continue
		var seen: Dictionary = {}
		var gain := 0
		for pair in adj[n]:
			var m: int = pair[0]
			if node_state[m] != OPEN or pair[1] != OPEN:
				continue
			var cm: int = comp[m]
			if cm < 0 or cm == start_comp or seen.has(cm):
				continue
			seen[cm] = true
			gain += comps[cm].size
		if gain > 0:
			out.append({"kind": "node", "u": n, "v": -1, "gain": gain,
				"label": "obstacle on cell " + str(n)})

	out.sort_custom(func(a, b): return a["gain"] > b["gain"])
	if out.size() > 8:
		out.resize(8)
	return out


static func _as_id_array(v, count: int) -> Array:
	var out: Array = []
	if typeof(v) == TYPE_INT:
		if v >= 0 and v < count:
			out.append(v)
	elif typeof(v) == TYPE_FLOAT:
		var i := int(v)
		if i >= 0 and i < count:
			out.append(i)
	elif typeof(v) == TYPE_ARRAY:
		for x in v:
			var i := int(x)
			if i >= 0 and i < count:
				out.append(i)
	return out


static func _empty_result(msg: String) -> Dictionary:
	return {
		"ok": false, "count": 0, "walkable": 0, "walls": 0,
		"wallEdges": 0, "softEdges": 0, "softNodes": 0, "softTotal": 0,
		"comps": [], "startComp": -1, "unreachable": 0, "deadEnds": 0,
		"isolated": 0, "sealed": 0, "borderOpen": 0, "leverage": [],
		"issues": [msg], "status": "broken", "cls": PackedInt32Array(),
		"comp": PackedInt32Array(), "deg": PackedInt32Array(),
	}


## Report a graph result as plain lines, for the editor Output panel.
static func format_report(r: Dictionary, title: String) -> String:
	if not r.get("ok", false):
		return "[Maze Checker] " + title + ": " + str(r.get("issues", ["nothing to check"]))
	var lines: Array = []
	lines.append("[Maze Checker] " + title + " - " + str(r["status"]).to_upper())
	lines.append("  nodes " + str(r["count"]) +
		"  walkable " + str(r["walkable"]) +
		"  regions " + str(r["comps"].size()) +
		"  unreachable " + str(r["unreachable"]) +
		"  sealed " + str(r["sealed"]) +
		"  dead ends " + str(r["deadEnds"]) +
		"  edge openings " + str(r["borderOpen"]))
	if int(r.get("softTotal", 0)) > 0:
		lines.append("  destructible obstacles " + str(r["softTotal"]))
		for item in r.get("leverage", []):
			lines.append("  > remove " + str(item["label"]) + " -> reconnects " + str(item["gain"]) + " cell(s)")
	if r["issues"].is_empty():
		lines.append("  no breaks found.")
	else:
		for issue in r["issues"]:
			lines.append("  ! " + str(issue))
	return "\n".join(lines)
