# Maze Checker

A Godot 4 editor plugin that flags unreachable floor, sealed pockets, dead ends
and stuck pickups in a TileMapLayer level before you ever press Play.

Every maze tool I could find generates levels. None of them tell you a level is
broken. This one does the opposite: it reads the level you already painted and
reports what a player can never reach.

## What it reports

- separate open regions (your level is secretly two levels)
- cells unreachable from the start point
- dead ends
- pellets / pickups you can never eat
- openings on the outer edge (tunnel mouths, or an accidental leak)
- for destructible obstacles: the single one worth removing, e.g.
  `remove obstacle on cell 39 -> reconnects 14 cell(s)`

## Install

1. Copy the `addons/maze_checker` folder into your project.
2. Project > Project Settings > Plugins > enable **Maze Checker**.
3. Open the scene with your tilemap. The checks appear under **Project > Tools**.

## The four checks

| Menu item | What it does |
|---|---|
| Check level: painted tiles are walls | Painted tiles are walls; the empty space between them is floor. |
| Check level: painted tiles are floor | The inverse: painted tiles are floor, everything else inside the box is wall. |
| Check level: + obstacles & edge walls | Square grid, plus destructible obstacles and walls on tile edges. |
| Check level: hex grid | Treats the painted cells as a hex grid (odd-r offset, 6 neighbours). |

## Use it from a generator (runtime)

The editor plugin reads a painted TileMapLayer. If you *generate* floors at run
time, there is no tilemap yet, so `MazeRuntime` takes your cells directly and
answers the only question a generation loop asks: **accept this floor, or roll
another one?** It has no editor or engine dependencies, so it is safe to call
from a running game, a headless test, or a tool.

```gdscript
const MazeRuntime = preload("res://addons/maze_checker/maze_runtime.gd")

# rows: Array of rows, 1 = wall, 0 = floor (PackedByteArray + width/height also works)
var res := MazeRuntime.check_or_regenerate(rows, {
    "start": Vector2i(2, 2),       # optional: anchor the report on the spawn
    "minWalkableRatio": 0.25,      # refuse a floor that is mostly wall
    "maxDeadEndRatio": 0.5,        # refuse a floor that is mostly dead ends
    "allowEdgeOpenings": true,     # set false if floor must not touch the border
})
if res.pass:
    build(res.report)              # res.report has unreachable / deadEnds / regions ...
else:
    regenerate(res.reasons)        # e.g. ["3 unreachable floor cell(s)", "2 separate regions"]
```

`res.reasons` is a short, loggable list, so a generator can say *why* it threw a
room away instead of silently rerolling.

## License

MIT. See LICENSE.
