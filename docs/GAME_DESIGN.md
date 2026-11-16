# Game design

This document records what the game is and *why* it is that way, so that
changes can be judged against intent. Numbers live in
`resources/ball_tuning.tres` (feel) and in each level file (content); the
values quoted here are the defaults at the time of writing.

## Pillars

1. **Down is always under the ball.** The camera's roll is locked to the
   ball's angle around the tunnel, so gravity always looks perpendicular to
   the floor and the world turns around you. This is the game's identity;
   never smooth or lag the roll.
2. **Physical, readable motion.** Tilt is a slope, not a joystick. The ball
   accelerates, coasts and slows like a real ball on a tilted plane.
3. **Rhythm is rewarded.** The echo turns jumping into a beat: swipe once,
   then tap on each landing. Good timing is felt in light, sound and touch.
4. **Colour is progress.** No progress bar. The tunnel's palette moves from
   start to finish and the next colour is always visible ahead.

## Controls

| Gesture | Effect |
|---|---|
| Tilt left/right | Lateral acceleration `5/7 · g · sin(tilt)`, the acceleration of a solid sphere rolling down a slope. Rolling resistance decays lateral speed exponentially (`1.15/s`), so releasing the tilt lets the ball coast. 32° of phone tilt is full tilt; airborne, the ball keeps 45% of tilt authority. |
| Swipe up | Jump. Height scales with swipe length: 3.5% of the screen height is the minimum swipe (0.7 m), 28% is a full swipe (3.4 m). Long swipes fire as soon as they reach full length; others fire on release. |
| Tap while landing | **Echo**: repeat the last jump exactly. Accepted from 0.20 s before touchdown to 0.10 s after. Within 0.06 s of touchdown it is **perfect**. Taps register on touch-down, not release, because timing matters. |

Tilt is measured relative to how the phone is held when the run starts (or
resumes), as the roll angle `atan2(x, |(y, z)|)` of the gravity vector,
which does not change when the player tips the phone towards themselves.

## Holes and failure

Holes are rectangles on the tunnel surface: a start and length along the
tunnel, a centre angle and an angular width. The ball falls when the point
under its centre is more than 0.22 m inside a hole (a small mercy at the
edges). Falling plays out for under half a second, the screen fades into the
void colour, and the run restarts at once with an "attempt N, best X%"
toast. A thin dashed ring on the wall marks your best distance.

## Speed and length

Forward speed grows linearly with progress: `v = base · (1 + 0.2 · s/L)`.
Because speed depends on position, the run time is
`T = L / (0.2 · base) · ln(1.2)`, and levels are sized so that `T = 60 s`
(see `SpeedProfile`). Camera FOV widens by 9° over the level to sell the
extra speed.

## Level patterns

Bundled levels are generated from patterns (`tools/level_generator.gd`),
then saved as plain data. The generator follows a "safe path" around the
tunnel that drifts at a speed a player can comfortably follow, so the route
spirals and the camera rotation becomes part of play.

| Pattern | What the player does |
|---|---|
| gate | A wide hole with one gap: steer into the gap. |
| ring | A full ring: jump it. |
| echo run | 3 to 6 evenly spaced rings matched to the *maximum* jump: one long swipe, then echo through. Tuned to the maximum because any long swipe gives exactly that height, so it is reproducible. |
| bridge | A narrow strip of floor that winds around the tunnel. |
| split | Two gaps a quarter turn either side: pick one. |

Difficulty ramps within each level, with a breather every 9 to 14 seconds,
and across levels (Dawn 0.35, Tide 0.6, Ember 0.85). `LevelValidator`
rejects any gap that cannot be jumped at the local speed, and a test plays
every level to the end with `Autopilot`.

## Feel ("juice") inventory

All of it lives in `EffectsDirector`, `BallView`, `CameraRig` and the shaders.

- Normal landing: a soft ripple, the ball squashes, a low thud, a light haptic.
- Echo: a ripple that expands *over the cylinder*. Each tile lights up as
  the wave passes it, the wave wraps around the tunnel and meets itself on
  the far side. The ball flashes in the accent colour, the FOV kicks, a
  glassy note plays (D-major pentatonic, one step higher per echo in the
  chain) and a medium haptic fires. A perfect echo adds a bell overtone, a
  brighter wave and a heavy haptic. The HUD shows `×N` from the second echo.
- Jump: stretch, plus a soft whoosh pitched by height.
- Fall: a falling tone, a small camera shake, a heavy haptic, then a fade.
- Finish: a huge ripple, a rising arpeggio, a success haptic, the results screen.

## Visual language

The aim is "glazed ceramic at different times of day", not neon on a grid.

- **Tunnel**: tiles in a running bond (alternate rings offset by half a
  tile), each with a slight tonal variation and a soft glaze highlight. The
  side of the tunnel opposite the ball is darker, which reinforces which way
  is down as the world turns.
- **Holes**: cut through a 0.45 m thick shell. The cut shows a bright glazed
  lip and then the darker ceramic body, and beyond it the void.
- **Void**: a deep colour per palette stop, with sparse twinkling motes so
  holes read as depth, and a glow straight ahead that the tunnel's fog fades
  into: a light at the end of the tunnel that the player is always gazing at.
- **Ball**: matte bone-white ceramic with two ink seams at right angles, so
  rolling in either direction is visible. Its rim picks up the tunnel colour.
- **Type**: Instrument Serif italic for names and numbers, Geist Mono in
  spaced capitals for labels. No panels or buttons with borders; text sits
  on the scene over a soft scrim.

## Ideas not built yet

- Ghost replays (the simulation is deterministic, so recording InputFrames is enough).
- Attract mode: the Autopilot playing behind the menu.
- Per-level music whose tempo matches the echo period.
- Collectibles on risky lines (tile "glints") for players chasing mastery.
- The level editor (see [LEVEL_FORMAT.md](LEVEL_FORMAT.md)).
