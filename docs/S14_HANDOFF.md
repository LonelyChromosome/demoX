# S14 implementation checkpoint

Branch: `assistant/s14-final-gameplay-polish`.
Continued the existing working tree based on S13 `c1dd13326d22280b122ce62daf246d77c9be6f41`.
No changes to main, intro, menu, settings or audio branches. No push or PR.

## Completed from the interrupted work

- Finished the existing deterministic event pacing and storm definitions.
- Connected event decisions and pending repair orders to the existing OutsideRail.
- Completed localized warning, cost, damage, repair and recovery feedback.
- Replaced the incomplete RNG string conversion and corrected a renamed world-state parameter.
- Preserved the existing turn pipeline; repair is one commit step before production.

## Balance and crisis behavior

- Opening stockpile: 8 Food, 3 Materials, covering the four consumers for two days.
- Farm output stays 2 base + 2 per effective worker, capped at six workers.
- Workshop rank output remains 1/2/3; starvation grace remains three days.
- Early/mid/late phases are days 1–8 / 9–22 / 23–32.
- Automatic event selection uses run_seed, eligibility, phase weights, a three-day cooldown,
  at most one new definition per selection, and existing resolved-definition tracking.
- Storm eligibility starts on day 9, ends on day 28, and requires two operational production buildings.
- Warning is followed by a player choice. Reinforcement costs 2 Materials during turn resolution,
  not when clicked. Funds are rechecked at commit. An unanswered warning defaults to waiting
  on the next turn, as disclosed in the UI.
- Subsequent impact deterministically damages one eligible farm/workshop unless protected.
  Damage stops its production. Repair costs 2 Materials, commits through TurnResolver,
  records history and restores production. Repeated resolution does not repeat the effect.
- Follow-up recovery uses the Building report source. Weather is now a compatibility field;
  passive food, expedition-duration, storm-route and weather-threat modifiers are removed.
- Existing loyalty rules remain. A bonded pair with actual discontent can receive an explicit
  support choice using existing loyalty history/idempotency; no automatic romance or daily rewards.

## Exactly three visual implementation passes

1. Structure: stone wall faces, battlements, corner towers, recognizable open gate,
   semantic routes and irregular perimeter terrain. Existing BoardProjection is unchanged.
2. Material/depth: warm paved cells, planted building silhouettes, shadows, outlined chess
   glyphs, gentle selected-piece lift, layered trees/rocks/tents/rubble and distant haze.
3. Readability: gameplay theme and header hierarchy, prominent End Day, event/repair planning
   feedback, hover feedback, sparse forest leaves and occupied-camp smoke/fire.
   Ambient redraw is isolated to its own overlay at 10 Hz and does not mutate gameplay.

No fourth polish pass was performed. No visual acceptance is claimed without a render.

## Validation actually performed

One invocation of `python tools/validate_s14.py`:

- PASS: no duplicate VI/EN keys; key parity; placeholder parity.
- PASS: literal localization references exist.
- PASS: no unseeded RNG API calls in gameplay core/systems.
- PASS: `git diff --check`.
- SKIP: GDScript grammar parse — gdtoolkit unavailable; one installation attempt found no package.
- SKIP: Godot import/runtime/S14/S13/S12-B tests — no Godot executable.
- SKIP: launch/render and actual gameplay screenshot — no Godot renderer.

`tests/s14_balance_crisis_test.gd` covers opening resources, output contracts, weather removal,
seed variation/determinism, event cooldown, storm choices/effect idempotency, damage,
repair through TurnManager, follow-up/report integration, projection and locale parity.
It is authored but NOT runtime-verified here. The old weather production assertion was
updated to the new S14 no-passive-modifier contract; it was not runtime-executed.

## Remaining acceptance blockers

Godot semantic parsing/runtime validation and one actual gameplay screenshot remain required.
The source is checkpointed, but S14 is not claimed fully accepted in this environment.
The supplied reference is not an implementation screenshot.

On a machine with Godot, run `python tools/validate_s14.py` once. For an actual screenshot:

```sh
godot --path . --resolution 1600x900 --script tests/s14_capture.gd
```

The capture script renders the real new-game scene, prints the absolute output location,
and writes `user://s14-gameplay.png`. It does not substitute mock state or a concept image.

Pre-existing older tests and legacy untranslated gameplay strings outside S14 were not broadly
rewritten. No additional non-blocking runtime findings can be confirmed without running Godot.
