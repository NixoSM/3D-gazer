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
`TunnelMeshBuilder` lays a grid on the chunk whose lines include every
hole edge, so each cell is entirely wall or entirely hole, then adds rim
faces wherever wall meets hole, through the shell thickness
`TunnelMath.WALL_THICKNESS` that the simulation also uses for falls. All
chunks share one `ShaderMaterial`;
per-frame inputs (ball position, ripples, fog colour, fade) are uniforms.

The Mobile renderer is used on device. Every shader is unshaded with
hand-written flat (cel) shading, so the look is the same on the Mobile and
Compatibility renderers (screenshots are rendered with Compatibility under
a software GPU).

## Where to add things

| You want to… | Touch |
|---|---|
| Tune how the ball feels | `resources/ball_tuning.tres` in the inspector |
| Add a level | A JSON file in `levels/` and its id in `levels/manifest.json` (see LEVEL_FORMAT.md) |
| Add a hole pattern | `tools/level_generator.gd`, then re-run `tools/generate_levels.gd` |
| Add a new obstacle type | `LevelData` + serializer (bump `format_version`), `BallSimulation`, the mesh builder or a new view, the validator, tests |
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
