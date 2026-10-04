# DemoX

PC 2D post-war chess management game built with Godot 4.

## Project rule

Keep gameplay rules out of `main.gd`. Each mechanic belongs to its own system module.

```text
src/
  app/        scene composition only
  board/      8x8 board rendering/input
  core/       run state + End Day
  domain/     pure data
  systems/    buildings, food, reports, events, expeditions, prisoners, promotion, romance, ending
  ui/         interface widgets
docs/
  ARCHITECTURE.md
```
