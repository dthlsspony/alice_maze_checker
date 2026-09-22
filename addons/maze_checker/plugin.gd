@tool
extends EditorPlugin

## Maze Checker: run a reachability pass over the TileMapLayer(s) in the open scene.
## Adds items to the Project > Tools menu.
##
## v0.2 generalizes the old grid flood fill into a graph pass, so the same check
## covers square grids, hex grids, walls that live on tile edges, and destructible
## obstacles. See graph_core.gd and shapes.gd.

const Core = preload("res://addons/maze_checker/maze_core.gd")
const Graph = preload("res://addons/maze_checker/graph_core.gd")
const Shapes = preload("res://addons/maze_checker/shapes.gd")
const Adapter = preload("res://addons/maze_checker/tilemap_adapter.gd")

const MENU_WALLS := "Check level: painted tiles are walls"
const MENU_FLOOR := "Check level: painted tiles are floor"
const MENU_GRAPH := "Check level: + obstacles & edge walls"
const MENU_HEX := "Check level: hex grid"

const EDGE_MASK_LAYER := "edge_mask"


func _enter_tree() -> void:
	add_tool_menu_item(MENU_WALLS, _on_check_walls)
	add_tool_menu_item(MENU_FLOOR, _on_check_floor)
	add_tool_menu_item(MENU_GRAPH, _on_check_graph)
	add_tool_menu_item(MENU_HEX, _on_check_hex)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_WALLS)
	remove_tool_menu_item(MENU_FLOOR)
	remove_tool_menu_item(MENU_GRAPH)
	remove_tool_menu_item(MENU_HEX)


func _on_check_walls() -> void:
	_check_legacy("walls")


func _on_check_floor() -> void:
	_check_legacy("floor")


func _on_check_graph() -> void:
	_check_graph_layers("walls")


func _on_check_hex() -> void:
	_check_graph_layers("floor", true)


func _collect_tilemap_layers(node: Node, out: Array) -> void:
	if node is TileMapLayer:
		out.append(node)
	for child in node.get_children():
		_collect_tilemap_layers(child, out)


func _edited_layers() -> Array:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		print("[Maze Checker] No scene open.")
		return []
	var layers: Array = []
	_collect_tilemap_layers(root, layers)
	if layers.is_empty():
		print("[Maze Checker] No TileMapLayer found in this scene.")
	return layers


func _is_obstacle_layer(layer: TileMapLayer) -> bool:
	return layer.name.to_lower().find("obstacle") != -1


func _obstacle_cells_for(layer: TileMapLayer, all_layers: Array) -> Array:
	for other in all_layers:
		if other != layer and _is_obstacle_layer(other):
			return other.get_used_cells()
	return []


func _edge_mask_for(layer: TileMapLayer, origin: Vector2i, width: int) -> Dictionary:
	# Optional: a TileSet custom data layer named "edge_mask", one int per tile,
	# bits 1/2/4/8 = blocked North / East / South / West side.
	var ts := layer.tile_set
	if ts == null:
		return {}
	var lid := ts.get_custom_data_layer_by_name(EDGE_MASK_LAYER)
	if lid < 0:
		return {}
	var by_cell: Dictionary = {}
	for c in layer.get_used_cells():
		var td := layer.get_cell_tile_data(c)
		if td == null:
			continue
		var v = td.get_custom_data_by_layer_id(lid)
		if v != null and int(v) != 0:
			by_cell[c] = int(v)
	if by_cell.is_empty():
		return {}
	return Adapter.cell_dict_to_ids(by_cell, origin, width)


## The original check, still on the ASCII core so its 21 tests guard it.
func _check_legacy(mode: String) -> void:
	for layer in _edited_layers():
		var used: Array = layer.get_used_cells()
		var built: Dictionary = Adapter.grid_from_cells(used, mode)
		if built.get("empty", false):
			print("[Maze Checker] " + layer.name + ": no tiles placed.")
			continue
		var r: Dictionary = Core.analyze(built["text"], {"wallChar": "#"})
		print("[Maze Checker] " + layer.name + " (" + mode + ") - " + str(r["status"]).to_upper())
		print("  size " + str(r["width"]) + "x" + str(r["height"]) +
			"  walkable " + str(r["walkable"]) +
			"  regions " + str(r["comps"].size()) +
			"  unreachable " + str(r["unreachable"]) +
			"  sealed " + str(r["enclosed"]) +
			"  dead ends " + str(r["deadEnds"]) +
			"  edge openings " + str(r["borderOpen"]))
		if r["issues"].is_empty():
			print("  no breaks found.")
		else:
			for issue in r["issues"]:
				print("  ! " + str(issue))
		if r["status"] == "broken":
			push_warning("[Maze Checker] " + layer.name + ": " + str(r["issues"]))


## The graph check: obstacles (a layer named like "obstacles"), edge walls
## (edge_mask custom data), and optionally hex adjacency.
func _check_graph_layers(mode: String, hex: bool = false) -> void:
	var layers: Array = _edited_layers()
	for layer in layers:
		if _is_obstacle_layer(layer):
			continue
		var used: Array = layer.get_used_cells()
		var obstacles: Array = _obstacle_cells_for(layer, layers)
		var built: Dictionary = Adapter.grid_from_cells_and_obstacles(used, mode, obstacles)
		if built.get("empty", false):
			print("[Maze Checker] " + layer.name + ": no tiles placed.")
			continue
		var origin: Vector2i = built["origin"]
		var width: int = built["width"]
		var edge_mask: Dictionary = _edge_mask_for(layer, origin, width)
		var spec: Dictionary
		var shape_name := "hex" if hex else "square"
		if hex:
			spec = Shapes.from_hex_text(built["text"], {"wallChar": "#", "softChar": "o", "edgeMask": edge_mask})
		else:
			spec = Shapes.from_square_text(built["text"], {"wallChar": "#", "softChar": "o", "edgeMask": edge_mask})
		var r: Dictionary = Graph.analyze(spec)
		var title: String = str(layer.name) + " (" + shape_name
		if not obstacles.is_empty():
			title += ", " + str(obstacles.size()) + " obstacles"
		if not edge_mask.is_empty():
			title += ", edge walls"
		title += ")"
		print(Graph.format_report(r, title))
		if r["status"] == "broken":
			push_warning("[Maze Checker] " + layer.name + ": " + str(r["issues"]))
