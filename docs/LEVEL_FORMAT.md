# Level format

Levels are JSON files in `levels/`. `levels/manifest.json` lists them in
play order (a level unlocks when the one before it is completed). The game
never hard-codes level content, so anything that can write this file (a
script, a spreadsheet export, the future editor) can make levels.

```json
{
  "format_version": 4,
  "id": "01_lemonade",
  "name": "Lemonade",
  "length": 691.0,
  "tunnel_radius": 4.0,
  "base_speed": 10.5,
  "speed_ramp": 0.2,
  "palette": [
    { "at": 0.0, "wall": "#5b6489", "void": "#0d1024", "accent": "#f3c98f" },
    { "at": 1.0, "wall": "#f5e5ca", "void": "#26355f", "accent": "#e0603f" }
  ],
  "spin": [
    { "s": 120.0, "rate": 0.0 },
    { "s": 140.0, "rate": 15.0 },
    { "s": 400.0, "rate": 15.0 },
    { "s": 403.0, "rate": 20.0 }
  ],
  "speed": [
    { "s": 300.0, "factor": 1.0 },
    { "s": 315.0, "factor": 1.1 }
  ],
  "hints": [
    { "s": 30.0, "text": "swipe up to jump" }
  ],
  "holes": [
    { "s": 36.75, "length": 2.64, "angle": 0.0,   "width": 360.0 },
    { "s": 53.62, "length": 5.07, "angle": 156.8, "width": 205.7 }
  ]
}
```

| Field | Unit | Meaning |
|---|---|---|
| `format_version` | | `4` (versions `1` to `3`, without `spin`, `twist`, `speed` or `hints`, still load). Bump it (and teach `LevelSerializer` to migrate) when the format changes. |
| `id` | | Unique, stable. Used for save data, so do not rename shipped levels. |
| `name` | | Shown to players. |
| `length` | m | The level is complete at this distance. For a 60 s level use `SpeedProfile.length_for_duration(60, base_speed, speed_ramp)`. |
| `tunnel_radius` | m | Inner radius. 4 m is tuned with the camera and jump heights. |
| `base_speed` | m/s | Forward speed at the start. |
| `speed_ramp` | fraction | Extra speed reached at the end (`0.2` = +20%), linear in progress. |
| `palette[]` | | Colour stops by progress `at` in [0, 1]: `wall` (the tunnel's flat colour), `void` (seen through holes and in the distance: keep it in strong contrast with `wall`), `accent` (echo rings, best-run marker). At least two stops. Interpolated in OKLab. |
| `holes[]` | | Rectangles on the tunnel surface, with rounded corners (0.6 m), optionally twisted. Order does not matter (they are sorted on load). |
| `holes[].s` | m | Where the hole starts along the tunnel. |
| `holes[].length` | m | How long it is along the tunnel. |
| `holes[].angle` | degrees | Centre of the hole around the tunnel. 0 is where the ball starts (the floor), positive is to the player's right. |
| `holes[].width` | degrees | Angular width, up to 360 (a full ring). A hole may cross 0°/360°. |
| `holes[].twist` | degrees/m | Optional, default 0. The hole's centre turns this much per metre along the tunnel, so it becomes a slanted band (`angle` is its centre at `s`). Within ±30. Use it for winding bridges and corkscrews instead of many small steps. |
| `spin[]` | | Optional ground spin keys, by distance. Between keys the rate is interpolated linearly; before the first and after the last it holds. Omitted or empty = no spin. |
| `spin[].s` | m | Where this rate applies. |
| `spin[].rate` | degrees/s | How fast the ball is carried round the tunnel if the player does not lean against it. Positive = to the player's right. Within ±180. Within a level, keep it turning one way and only speeding up (a design rule, not checked). |
| `speed[]` | | Optional speed surges (version 4). A factor on the speed profile above, by distance, interpolated linearly between keys and held before the first and after the last. Two keys a few metres apart make a sudden surge. Omitted or empty = factor 1 everywhere. |
| `speed[].s` | m | Where this factor applies. |
| `speed[].factor` | | Multiplier on `base_speed · (1 + speed_ramp · s/length)`. Within 0.25..4. |
| `hints[]` | | Optional (version 4). Short prompts shown on screen when the ball reaches `s` ("swipe up to jump", or an act's title), until the player has finished the level once. |
| `hints[].s` | m | Where it appears. |
| `hints[].text` | | What it says, a few words (shown in capitals). Must not be empty. |

Holes may touch or overlap; a point is open if it is inside any hole.
Holes closer than 1.2 m **blend** into one opening (a smooth union), so
there is never a seam where two holes meet and floor corners between them
are rounded too. Rectangles stacked into a staircase still work; make the
steps big and even, they read better than many small ones.

## Checks

- **Structure** (`LevelSerializer.validate`): required fields, sane ranges,
  holes inside the tunnel. Run on every load; errors are logged.
- **Playability** (`LevelValidator.check`): every stretch where the whole
  circumference is open must be jumpable at the local speed with a safety
  margin, and must be followed by enough floor to land on.
- **Play-through** (`tests/test_autopilot.gd`): a bot plays every listed
  level to the end with real inputs, also with a reaction delay on its
  steering (per level: see GAME_DESIGN.md, "The seven levels"). Use
  `godot --headless --script res://tools/trace_autopilot.gd -- <id> [delay]`
  to see where it struggles.

## Making levels

Use the **level editor** ([LEVEL_EDITOR.md](LEVEL_EDITOR.md)): a desktop
app (Windows, macOS) built from this project that edits these files with
live bot play-throughs, jump checks and a built-in playtest. It keeps a
level's speed surges and hints but cannot edit them yet.

The seven bundled levels are written by hand, in code: one script per
level in `tools/levels/` (`l1_lemonade.gd` …), using `LevelBuilder`, which
places everything on a clock ("a ring at 12.7 s") and knows the ball's
physics. `tools/author_levels.gd` runs them and writes the JSON files and
the manifest:

```sh
godot --headless --script res://tools/author_levels.gd             # all seven, into levels/
godot --headless --script res://tools/author_levels.gd -- --only 05_mixtape --out /tmp/try/
```

The scripts are the source of truth: re-running overwrites the seven JSON
files, so a level edited in the editor should be saved under a new id
(or its script updated). Then rate it and run the tests:

```sh
godot --headless --script res://tools/rate_levels.gd -- 05_mixtape --sweep
godot --headless --script res://tools/rate_levels.gd -- 05_mixtape --players 24
godot --headless --script res://tools/trace_path.gd -- levels/05_mixtape.json /tmp/path.csv 0.2
python3 tools/level_map.py levels/05_mixtape.json /tmp/map.png /tmp/path.csv   # the level unrolled, with the bot's path
```

The old procedural generator (`tools/level_generator.gd`) is still what the
editor's "Insert a pattern" uses (`LevelGenerator.stamp()`).
