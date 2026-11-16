# Gazer

*A tunnel that turns around you.*

You are a striped cartoon ball rolling down a bright, flat-coloured tunnel. Tilt the phone and the
ball rolls across the wall as if you had tilted the floor; the camera turns
with it, so wherever the ball is on the circumference, *down* is always
under it and it is the world that rotates. Swipe up to jump (a bigger
swipe means a higher jump). Tap the moment you land and the ball **echoes**
the same jump, sending a bold ring across the wall that wraps all the way
around the tunnel and meets itself on the far side. Chain echoes and the
notes climb a scale.

Each level is about a minute long. The ball speeds up by 20% from start to
finish, and the tunnel's colour moves through a palette (sunrise yellows to
violet, sea greens to deep blue, lava yellow to red), so the colour around
you tells you how far you are and the colour ahead shows what is coming.
The look is a deliberate throwback to Flash games: flat colours, hard
shading, thick black outlines.

![Screenshots](docs/media/screens.jpg)

## Status

| | |
|---|---|
| Engine | Godot 4.5 (GDScript), Mobile renderer |
| Platforms | iOS first. Android is an export preset away (see [docs/ANDROID.md](docs/ANDROID.md)) |
| Content | 3 levels: Dawn, Tide, Ember |
| Tests | 23 headless tests, including a bot that finishes every level |

**What has been verified and what hasn't.** All code was written and run on
Linux: the unit tests, the level validator and an autopilot that plays every
level to the end all pass, and the screenshots and the gameplay video were
rendered by the real game with a software GPU. What has **not** been
verified is anything that needs an iPhone: the iOS build, Metal rendering,
the accelerometer's sign and feel, haptics, and 120 Hz. The first device
run may need the "invert tilt" toggle (pause menu) or a sensitivity tweak.
See [docs/BUILDING_IOS.md](docs/BUILDING_IOS.md).

## Quick start

1. Install [Godot 4.5](https://godotengine.org/download) (standard build, not .NET).
2. Open this folder in Godot (Import → `project.godot`) and press **F5**.
3. Desktop controls: **A/D** or **←/→** tilt, **W/↑** small jump, **Space**
   big jump, **E/Shift** or **click** echo, **Esc** pause. Mouse drags
   behave like touch swipes.

Run the tests:

```sh
godot --headless --import                      # first time only: builds the class cache
godot --headless --script res://tests/run_tests.gd
```

Watch the bot play a level (or record it with `--write-movie demo.avi`):

```sh
godot res://scenes/main.tscn -- --autoplay --level=2
```

To build for an iPhone, follow [docs/BUILDING_IOS.md](docs/BUILDING_IOS.md).

## How the code is organised

```
src/
  core/          Pure game rules: no nodes, no rendering, fully unit-tested
    level_data.gd, hole_data.gd, palette_stop.gd   what a level *is*
    level_serializer.gd                            JSON <-> LevelData (read and write)
    level_validator.gd                             "is this level beatable?"
    ball_simulation.gd                             the rules, stepped at 120 Hz
    ball_tuning.gd                                 every feel number, as a Resource
    input_frame.gd                                 device-independent player intent
    speed_profile.gd, tunnel_math.gd               shared maths
  input/         Touch, accelerometer, keyboard -> InputFrame
  gameplay/      GameSession (runs a level), Autopilot (bot)
  presentation/  Tunnel mesh streaming, camera, ball, shaders' inputs, effects, sound
  ui/            Menu, HUD, pause, results (built in code, see ui_style.gd)
  app/           Main state machine, settings and progress autoloads
  platform/      The only code that touches platform APIs (haptics, screen)
shaders/         Tunnel, ball and sky shaders
levels/          Level JSON files + manifest.json (play order)
resources/       ball_tuning.tres (feel), balls/*.tres (ball looks)
tools/           Level generator, screenshot capture, autopilot trace
tests/           Headless test runner and tests
docs/            Design, architecture, level format, build guides
```

The one rule that keeps this maintainable: **data flows one way**.
`InputFrame → BallSimulation → events → presentation`. The simulation
never knows how it is drawn, and nothing visual can change gameplay. Read
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before making structural
changes.

## Further reading

- [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md): mechanics, numbers, feel and the visual language
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): layers, data flow, where to add things
- [docs/LEVEL_FORMAT.md](docs/LEVEL_FORMAT.md): the level JSON, and how a future editor plugs in
- [docs/BUILDING_IOS.md](docs/BUILDING_IOS.md): Xcode, signing, TestFlight
- [docs/ANDROID.md](docs/ANDROID.md): what porting involves
- [CONTRIBUTING.md](CONTRIBUTING.md): conventions and workflow

## Why Godot (and not Swift)

The brief asks for two things that pull against each other: best-practice iOS
*and* a future Android version. A native Swift/RealityKit game would be the
most Apple-idiomatic, but the Android version would be a full rewrite (and
SceneKit, the simpler Apple option, is being wound down by Apple). Godot
gives one codebase that exports a native Xcode project for iOS and an
APK/AAB for Android, is MIT-licensed with no runtime fees, and stores scenes
and resources as text, which keeps reviews readable and makes a level editor
straightforward. The iOS-specific good manners (safe areas, home-indicator
gesture deferral, ambient audio session, haptics, pausing when backgrounded,
keeping the screen awake) are handled in project settings and in
`src/platform/`.

## Licences

Code: choose a licence before publishing (none is set yet). Font: Lilita One,
SIL Open Font License 1.1 (see `assets/fonts/`).
All sounds are synthesised in code; there are no third-party audio assets.
