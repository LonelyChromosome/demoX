# Architecture

DemoX is PC-first, 2D-only, Godot 4 + GDScript.

Dependency direction:

`UI / Board -> Systems -> Domain + GameState`

- **Main** wires modules only.
- **GameState** is the source of truth for a run.
- **TurnManager** queues daytime orders and commits them only on End Day.
- **BoardView** owns board presentation and later ghost/planned placement.
- **Systems** are isolated by mechanic so changing prisoners does not touch romance, reports, etc.

Day 1 is fully known. Later information comes from institutions/reports or direct inspection.
