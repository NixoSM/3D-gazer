# Contributing

## Workflow

1. Branch from `main`.
2. Make the change. Keep the layering in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
3. Run the tests: `godot --headless --script res://tests/run_tests.gd`.
4. If you changed anything visual, render reference shots and look at them:
   `godot res://tools/capture_screens.tscn -- /tmp/shots` (needs a GPU or `xvfb-run`).
   If you touched the tunnel's geometry or shaders, run the pixel oracle
   too (docs/ARCHITECTURE.md, "Checking the picture"): looking is not
   enough, a one-pixel pinhole flickers on the phone and is invisible in
   a screenshot.
5. Open a pull request describing *why*, with before/after shots for visual changes.

CI runs the tests on every pull request (`.github/workflows/tests.yml`).

## Code conventions

- GDScript with static types everywhere (`var x: float`, `-> void`).
  Untyped code is a bug magnet in a growing project.
- Follow the [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html):
  tabs, `snake_case` members, `PascalCase` classes, `_private` helpers.
- Every class starts with a `##` doc comment saying what it is *for*.
- SI units in code: metres, seconds, radians. Degrees only in JSON and UI.
- `src/core/` stays free of nodes, autoloads and randomness. If a test
  needs the scene tree, the code is probably in the wrong layer.
- Tuning numbers that change feel belong in `BallTuning`, not as literals.
- New gameplay rules come with a test in `tests/`.

## Tests

Tests are plain classes extending `TestCase` (see `tests/test_case.gd`) with
`test_*` methods. The runner discovers `tests/test_*.gd` automatically.
Prefer testing through `BallSimulation.step()` with `InputFrame`s: that is
how the real game and the bot drive it.
