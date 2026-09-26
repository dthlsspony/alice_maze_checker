# Maze Checker (Godot editor plugin)

Flags unreachable floor, sealed pockets, dead ends and stuck pickups in a
TileMapLayer level before you ever hit Play. Output goes to the editor's
**Output** panel; anything broken also raises a warning.

Author: Alice · Godot 4.x (tested on 4.5.1 and 4.7.2)

## Install

1. Copy the `addons/maze_checker` folder into your project.
2. Project > Project Settings > Plugins > enable **Maze Checker**.
3. Open the scene with your tilemap. The checks appear under **Project > Tools**.

## The four checks

| Menu item | What it does |
|---|---|
| `Check level: painted tiles are walls` | The classic: painted tiles are walls, the empty space between them is floor. |
| `Check level: painted tiles are floor` | The inverse: painted tiles are floor, everything else inside the box is wall. |
| `Check level: + obstacles & edge walls` | Square grid, plus destructible obstacles and walls on tile edges (see below). |
| `Check level: hex grid` | Treats the painted cells as a hex grid (odd-r offset, 6 neighbours). |

Each check runs over every `TileMapLayer` in the open scene.

## Runtime API (for procedural generators)

`maze_runtime.gd` skips the tilemap entirely: hand it your generated cells and
it returns `pass` / `regenerate` plus the reasons a floor failed, so a generator
can reroll bad rooms instead of shipping them.

```gdscript
const MazeRuntime = preload("res://addons/maze_checker/maze_runtime.gd")
var res := MazeRuntime.check_or_regenerate(rows, {"start": Vector2i(2, 2)})
if res.pass: build(res.report) else: regenerate(res.reasons)
```

Pure logic, no editor dependency: safe to call from a running game.

## Tests

80 headless checks across `test_core.gd`, `test_graph.gd`, `test_adapter.gd`
and `test_runtime.gd`, green on Godot 4.5.1 and 4.7.2:
`godot --headless --script res://addons/maze_checker/test_runtime.gd`

## Destructible obstacles

Make a second `TileMapLayer` whose name contains `obstacle` (e.g. `Obstacles`).
Its painted cells are treated as **destructible**: they block the path now, but
the report tells you which single one is worth removing:

```
[Maze Checker] Level (square, 3 obstacles) - BROKEN
  nodes 84  walkable 61  regions 2  unreachable 14  sealed 1  dead ends 6  edge openings 0
  destructible obstacles 3
  > remove obstacle on cell 39 -> reconnects 14 cell(s)
  ! 2 separate open regions; 14 cell(s) unreachable from the start.
```

That "remove this one -> reconnects N cells" line is the point: it turns the
checker from a yes/no into a level-design hint.

## Walls on tile edges

In the classic mode a wall is a whole cell. For thin walls that sit on the
**edge** between two cells, add a TileSet **custom data layer** named
`edge_mask`, type `int`. Give a tile a value whose bits say which sides are
walled:

| bit | side |
|---|---|
| 1 | North |
| 2 | East |
| 4 | South |
| 8 | West |

So a tile with `edge_mask = 6` walls off its East and South sides. The checker
reads the mask from the main layer and treats those connections as blocked.

## What's inside

- `graph_core.gd` - the generalized pass. Nodes + edges, each OPEN / WALL / SOFT.
  This is what makes square, hex, edge-walls and destructible obstacles all the
  same check.
- `shapes.gd` - builds a graph spec from a square grid, a hex grid, or an
  explicit link list (a "geomap": arbitrary nodes and connections).
- `maze_core.gd` - the original ASCII-grid core, kept for the two classic checks.
- `tilemap_adapter.gd` - TileMapLayer cells -> text / edge-mask ids.
- `test_core.gd`, `test_adapter.gd`, `test_graph.gd` - headless tests
  (`godot --headless --path . --script res://addons/maze_checker/test_graph.gd`).

## Status / roadmap

- v0.1.0: square grid, walls-as-tiles and floor-as-tiles.
- v0.2.0: graph core; hex grids; destructible obstacles with a "best removal"
  hint; edge walls via `edge_mask`.
- Next: multi-level runs, and arbitrary link graphs surfaced in the editor.
