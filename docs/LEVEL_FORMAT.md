# Level format

Levels are JSON files in `levels/`. `levels/manifest.json` lists them in
play order (a level unlocks when the one before it is completed). The game
never hard-codes level content, so anything that can write this file (a
script, a spreadsheet export, the future editor) can make levels.

```json
{
  "format_version": 1,
  "id": "01_dawn",
  "name": "Dawn",
  "length": 691.0,
  "tunnel_radius": 4.0,
  "base_speed": 10.5,
  "speed_ramp": 0.2,
  "palette": [
    { "at": 0.0, "wall": "#5b6489", "void": "#0d1024", "accent": "#f3c98f" },
    { "at": 1.0, "wall": "#f5e5ca", "void": "#26355f", "accent": "#e0603f" }
  ],
  "holes": [
    { "s": 36.75, "length": 2.64, "angle": 0.0,   "width": 360.0 },
    { "s": 53.62, "length": 5.07, "angle": 156.8, "width": 205.7 }
  ]
}
```

| Field | Unit | Meaning |
|---|---|---|
| `format_version` | | Must be `1`. Bump it (and teach `LevelSerializer` to migrate) when the format changes. |
| `id` | | Unique, stable. Used for save data, so do not rename shipped levels. |
| `name` | | Shown to players. |
| `length` | m | The level is complete at this distance. For a 60 s level use `SpeedProfile.length_for_duration(60, base_speed, speed_ramp)`. |
| `tunnel_radius` | m | Inner radius. 4 m is tuned with the camera and jump heights. |
| `base_speed` | m/s | Forward speed at the start. |
| `speed_ramp` | fraction | Extra speed reached at the end (`0.2` = +20%), linear in progress. |
| `palette[]` | | Colour stops by progress `at` in [0, 1]: `wall` (tint of the dark shell: keep it dark and desaturated), `void` (seen through holes and at the far end; carries the level's mood), `accent` (hole lips, ripples, the lamp's tint, best-run marker). At least two stops. Interpolated in OKLab. |
| `holes[]` | | Rectangles on the tunnel surface. Order does not matter (they are sorted on load). |
| `holes[].s` | m | Where the hole starts along the tunnel. |
| `holes[].length` | m | How long it is along the tunnel. |
| `holes[].angle` | degrees | Centre of the hole around the tunnel. 0 is where the ball starts (the floor), positive is to the player's right. |
| `holes[].width` | degrees | Angular width, up to 360 (a full ring). A hole may cross 0°/360°. |

Holes may touch or overlap; a point is open if it is inside any hole.

## Checks

- **Structure** (`LevelSerializer.validate`): required fields, sane ranges,
  holes inside the tunnel. Run on every load; errors are logged.
- **Playability** (`LevelValidator.check`): every stretch where the whole
  circumference is open must be jumpable at the local speed with a safety
  margin, and must be followed by enough floor to land on.
- **Play-through** (`tests/test_autopilot.gd`): a bot plays every listed
  level to the end with real inputs. Use
  `godot --headless --script res://tools/trace_autopilot.gd -- <id>` to see
  where it struggles.

## Making levels today

`tools/generate_levels.gd` holds a spec per bundled level (seed, speed,
difficulty, palette, pattern weights) and writes the JSON with
`LevelGenerator`. Edit a spec and re-run:

```sh
godot --headless --script res://tools/generate_levels.gd
```

Generated files are ordinary level files: hand-edit them freely, but note
that re-running the generator overwrites them.

## The future level editor

Everything an editor needs already exists and is engine-node-free:

- **Model**: `LevelData`, `HoleData`, `PaletteStop`, editable in memory.
- **Load/save**: `LevelSerializer.load_file()` / `save_file()` (round-trip tested).
- **Live validation**: `LevelValidator.check()` is cheap enough to run on every edit.
- **Preview**: `TunnelMeshBuilder.build_chunk()` renders any stretch, and
  `TunnelView.set_level()` accepts an edited level directly.
- **Test play**: load the edited `LevelData` into `GameSession`; `Autopilot`
  can demonstrate that it is beatable.

A natural editor view is the tunnel **unrolled**: a 2D strip with `s`
running up the screen and angle across it (wrapping at the edges), where
holes are plain rectangles to drag and resize. That is exactly the
simulation's own coordinate system.
