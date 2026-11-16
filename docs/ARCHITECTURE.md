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

`TunnelView` keeps geometry only around the camera: 18 m chunks (plus a
0.3 m overlap each side, which hides the seams) from one chunk behind to
150 m ahead, at most two new ones built a frame.
`TunnelMeshBuilder` builds a plain tube (rows fully inside a ring hole are
left out). Holes are cut **per pixel** in `tunnel.gdshader` from a signed
distance field: each hole is a rounded box on the unrolled wall (sheared
when it is twisted), and holes are combined with a smooth minimum, so
touching holes merge without seams and every corner is rounded. The very
same field is `LevelData.floor_distance()`, which the simulation uses to
drop the ball and to collide it with the edge of the cut (via the field's
gradient). Keep `HoleData.signed_distance`, `LevelData.floor_distance` and
the shader's copies in step. The black outline is the band of floor within
0.2 m of an edge (never under two pixels wide), so it only exists where
there is floor. Hole parameters go to the shader in one float texture;
each chunk gets the index range of the holes that can reach it as
instance uniforms. The shell's thickness is drawn by a second tube at the
shell's outer radius (`tunnel_shell.gdshader`): a pixel of it seen through
a hole is a cut face when the view ray, sphere-traced through the shell
from where it crossed the inner surface (inside a hole) to the outer one,
meets solid shell on the way; a bisection finds where. Otherwise it is void.
Steps are as long as the hole field allows, and rays beyond 22 m get a
coarse look, because this shader is the game's most expensive part on
views over open void (`tools/perf_probe.tscn` compares views). Both shaders share the
field through `shaders/holes.gdshaderinc`. All chunks share one `ShaderMaterial`; per-frame inputs
(ball position, ripples, fog colour, fade) are uniforms.

The Mobile renderer is used on device. Every shader is unshaded with
hand-written flat (cel) shading, so the look is the same on the Mobile and
Compatibility renderers (screenshots are rendered with Compatibility under
a software GPU).

## Where to add things

| You want to… | Touch |
|---|---|
| Tune how the ball feels | `resources/ball_tuning.tres` in the inspector |
| Add a level | Make it in the level editor (LEVEL_EDITOR.md); the JSON goes in `levels/` and its id in `levels/manifest.json` |
| Add a hole pattern | `tools/level_generator.gd`, then re-run `tools/generate_levels.gd` |
| Add a new obstacle type | `LevelData` + serializer (bump `format_version`), `BallSimulation`, the mesh builder or a new view, the validator, the editor (`StripView` and `editor_strip.gdshader`), tests |
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
