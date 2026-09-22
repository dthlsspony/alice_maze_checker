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

## License

MIT. See LICENSE.
