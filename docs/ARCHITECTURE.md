# Architecture

## The one-way flow

```
 touch / accelerometer / keys                     level JSON
            │                                         │
      InputRouter ──► InputFrame             LevelSerializer ──► LevelData
                          │                                         │
                          ▼                                         ▼
                    GameSession ── steps at 120 Hz ──► BallSimulation
                          │                                 │
              signals: sim_event, run_failed,          state (s, angle, height…)
                      run_completed                         │
                          ▼                                 ▼
   Main (app flow)   EffectsDirector (juice)       WorldView (interpolated each frame)
        │                 │                         ├─ TunnelView  (mesh streaming + tunnel shader)
        ▼                 ▼                         ├─ BallView    (spin, squash, ball shader)
       UI          ToneSynth, Platform.haptic       └─ CameraRig   (roll locked to the ball)
```

Nothing to the right or below the simulation can change gameplay. That
is the property that makes the game safe to restyle and simple to test.

## Layers

| Layer | Folder | May depend on | Notes |
|---|---|---|---|
| Core | `src/core/` | nothing but Godot's base types | `RefCounted` classes and one `Resource`. No nodes, no scene tree, no autoloads. Unit-tested. |
| Input | `src/input/` | core, `Settings` | Produces `InputFrame`s only. |
| Gameplay | `src/gameplay/` | core, input | `GameSession` owns the fixed-step loop; `Autopilot` is a bot that produces `InputFrame`s. |
| Presentation | `src/presentation/`, `shaders/` | core, gameplay | Reads state, never writes it. |
| UI | `src/ui/` | presentation (for colours), `Settings` | Built in code with `UiStyle` helpers. |
| App | `src/app/` | everything | `Main` state machine, `Settings` and `Progress` autoloads. |
| Editor | `src/editor/` | everything (and `tools/level_generator.gd`) | The desktop level editor, a separate main scene for the `level_editor` feature tag. The game never depends on it. See LEVEL_EDITOR.md. |
| Platform | `src/platform/` | `Settings` | The only place that calls platform APIs. |

## Coordinates

The simulation lives in **tunnel-surface coordinates**: `s` metres along
the tunnel, `angle` radians around it (0 = where the ball starts), `height`
metres above the wall. In those coordinates the tunnel is a flat strip whose
edges are glued together, gravity is a constant "down", and holes are
plain rectangles. The 3D world only appears in `TunnelMath.point()`:

```
x =  r · sin(angle)      y = -r · cos(angle)      z = -s
```

so angle 0 is the bottom, angles grow to the player's right, and the ball
travels towards -Z. Shaders recover `(s, angle)` from world position the
same way, so the GPU and the simulation agree on everything (shadows,
ripples, the best-run marker) without extra data.

## The fixed step

`GameSession` accumulates frame time and steps `BallSimulation` at 120 Hz
(up to 8 steps a frame), then interpolates between the last two states for
rendering. One-shot gestures (taps, swipes) are handed to exactly one step.
The simulation itself is deterministic: the same `InputFrame` sequence
always produces the same run (see `test_simulation_is_deterministic`). Keep
it that way: no `randf()`, no wall-clock time, no reading nodes.

## Rendering the tunnel

The tunnel is **real geometry with the holes already cut out of it**.
Nothing is cut per pixel and nothing is ray-marched. (Until November 2026
holes were cut in the fragment shader with `discard` and the shell's
faces were ray-marched through a second tube; every recurring glitch,
see-through crescents, black spikes, stretched faces, lag over open void,
came from that, so it was replaced wholesale.)

- **`TunnelMesher`** builds one stretch ("chunk", 18 m) of floor from
  `LevelData.floor_distance()`, the very function the ball falls by. The
  unrolled wall is a grid of 192 columns by 0.125 m rows. Cells far from
  any edge, proved so on a coarse 1 m grid with a bound on how fast the
  field can change, become long plain strips. Cells near an edge are cut
  by marching squares, with a vertex where the field crosses zero on each
  grid edge. Every crossing is computed once per grid edge from the same
  two values, so cells and chunks meet exactly. Strips pick up every vertex
  that a neighbouring cell put on their sides, so there are no T-junctions
  (they opened one-pixel pinholes onto the void). Each contour segment is
  extruded straight out through the 0.8 m shell into a **cut face** that
  shares its top vertices with the floor, so a face can never come loose
  from its edge. Floor vertices carry their distance to the edge (UV.x),
  which the floor shader draws the outline from. Interpolated across a
  long strip that distance can be wildly off, so every cell within ink
  reach (0.6 m, the widest the outline ever gets) is cut finely, and every
  strip carries one constant distance just beyond that reach: perfectly
  flat, so neither fwidth() nor MSAA's extrapolation at a strip's sliver
  edges can find ink in it. (Strips used to start at 0.38 m and carry
  their real distances; a strip from one hole's corner to the next then
  drew a thin black line between them.)
- **`TunnelView`** keeps chunks from one behind the camera to 150 m ahead.
  New chunks are built on worker threads (`WorkerThreadPool`), with the
  two nearest built on the spot if a worker is late. The first ten chunks
  of a level stay built, so a retry never waits.
- **`tunnel_floor.gdshader`** colours the floor: palette colour by
  progress, rounded tiles, two-tone cel shading, contact shadow, echo
  waves, best-run marker, finish line, and the black outline, which is the
  floor within 0.25 m of an edge, drawn like an ink line (never thicker
  than about 1% of the screen height, never thinner than 1.5 pixels,
  never wider than 0.4 m).
  **`tunnel_wall.gdshader`** colours the cut faces: a darker wall tone, the
  tile seams carried down the face, a black line at the back of the shell.
  **`void_backdrop.gdshader`** is a sphere around the camera: flat void
  colour with blinking cartoon stars. There is no sky (on the Mobile
  renderer a realtime sky re-renders a radiance cubemap every frame).
- 4× MSAA smooths every edge, because every edge is a triangle edge.

Keep `HoleData.signed_distance`, `LevelData.floor_distance` and the editor
strip's copy (`shaders/holes.gdshaderinc`) in step. The game itself no
longer has a shader copy of the field.

### Checking the picture: the pixel oracle

`tools/visual_audit.tscn` renders about 200 views (approaching, beside,
under and over every kind of hole, and every 1.5 s of a bot's run through
each level) on the Mobile renderer, with every shader drawing a flat
**material ID** instead of its colour (`gazer_debug_ids`), MSAA off, and
the camera saved next to each frame. The floor's ID view computes the
outline exactly as the colour view does, and counts a pixel as outline
wherever the ink would darken it by more than 10%, so faint grey ink
shows up too. `tools/visual_oracle.py` then works out what every pixel
*should* be from the level file alone, by ray-casting the tunnel exactly
as the game defines it (floor, outline by the same ink rule, cut face,
back line or void), and fails on any group of wrong pixels, on any single
pinhole of void within 60 m, and on 4 or more pixels of **stray ink**
anywhere in a frame (outline drawn with nothing but floor for 4 pixels
around: thin, often dotted lines that no single cluster would flag). It
shares no code with the renderer. With `msaa` as the fourth argument the
audit keeps the game's 4x MSAA on, and the oracle accepts blended pixels
only where two materials really meet.

```sh
xvfb-run -a godot --rendering-driver vulkan --rendering-method mobile \
    --resolution 585x1266 res://tools/visual_audit.tscn -- /tmp/audit
python3 tools/visual_oracle.py /tmp/audit --report /tmp/audit_report
# the same with MSAA on, and a denser bot run (every 0.5 s):
... res://tools/visual_audit.tscn -- /tmp/audit_msaa 1.5 all msaa
... res://tools/visual_audit.tscn -- /tmp/audit_dense 0.5
```

The report has, for each failing frame, what was drawn, what should have
been and where they differ. In the cloud, the Mobile renderer runs on
Mesa's software Vulkan driver (lavapipe), so the pictures are the iPhone's
renderer, not an approximation. `tests/test_tunnel_mesher.gd` checks the
same promises on the geometry itself, without rendering: the floor covers
exactly the solid wall, it is watertight across cells and chunks, every
hole edge has a cut face, the edge distance the outline is drawn from is
the true one wherever ink can reach (and flat on every strip), and a
chunk stays within its budget.

The Mobile renderer is used on device. Every shader is unshaded with
hand-written flat (cel) shading.

## Where to add things

| You want to… | Touch |
|---|---|
| Tune how the ball feels | `resources/ball_tuning.tres` in the inspector |
| Add a level | Make it in the level editor (LEVEL_EDITOR.md); the JSON goes in `levels/` and its id in `levels/manifest.json` |
| Add a hole pattern | `tools/level_generator.gd`, then re-run `tools/generate_levels.gd` |
| Add a new obstacle type | `LevelData` + serializer (bump `format_version`), `BallSimulation`, `TunnelMesher` (or a new view) and the pixel oracle, the validator, the editor (`StripView` and `editor_strip.gdshader`), tests |
| Add a ball look | Duplicate `resources/balls/classic.tres`, edit it, apply with `BallView.apply_skin()` |
| Change sounds | `ToneSynth` (keep the `play_*` API) |
| Change haptics | `PlatformServices.HAPTIC_PATTERNS` |
| Add a screen | `src/ui/`, wire it in `Main` |
| Add something iOS- or Android-only | `src/platform/platform_services.gd` |

## Known trade-offs

- **UI is built in code**, not in `.tscn` files. It keeps the few screens
  compact and reviewable, and every element goes through `UiStyle`. If the
  UI grows (shop, settings pages), move screens to scenes with a Theme.
- **No physics engine.** The ball is simulated analytically on the strip.
  That is what makes it deterministic and testable, and what makes
  "gravity is always under the ball" trivial. New obstacles need their
  rules written in `BallSimulation`, not dropped in as colliders.
- **Echo ripples are capped at 6 at once** (a uniform array). Plenty for
  the game; raise `MAX_RIPPLES` in both the shader and `TunnelView` if not.
