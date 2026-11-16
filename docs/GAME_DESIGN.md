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
| Tap while landing | **Echo**: repeat the last jump exactly. Accepted from 0.20 s before touchdown to 0.10 s after. Within 0.06 s of touchdown it is **perfect**. Taps register on touch-down, not release, because timing matters. The echo lands with a **hit-stop**: the world freezes for 0.14 s while the shockwave keeps spreading, so the player registers the hit. A swipe during the freeze replaces the echo's height (and ends the freeze at once); while a finger is still down the freeze waits for it, up to 0.30 s. The echo also **resets sideways momentum**: the ball takes off sideways at 4 m/s times the tilt held at that moment, so a tilt during the freeze acts at once instead of fighting the old drift. |

Tilt is the roll angle `atan2(x, |(y, z)|)` of the gravity vector, which
does not change when the player tips the phone towards themselves. Level is
**absolute**: a phone not rolled relative to gravity steers nowhere. Rolls
under 2.5° are ignored and the next 2.5° blend in smoothly, so the hand's
natural wobble never steers. A player who holds the phone at an angle can
store their own level in the pause menu ("use this angle").

(The first device build took the pose at the start of every attempt as
level. A retry begins right after a fall, usually mid-tilt, so the bias
stuck and the ball drifted by itself with the phone held straight.)

## Ground spin

Each level can make the tunnel **spin**: a steady sideways drift that
carries the ball around the tunnel unless the player leans against it.
Because the camera's roll is locked to the ball, the player sees the whole
tunnel turning. Spin is level data (`spin` keys in degrees per second along
the tunnel), so the future editor can paint it: two keys close together
snap it round, two far apart ease it in. In the simulation, rolling
resistance relaxes the ball's sideways speed towards the spin drift
instead of towards zero, and the air inside the tunnel turns with it.

The spin never changes direction on its own: only the level data turns it.
(An earlier build flipped it on every echo; Nicola dropped that after
playing it.) The floor pattern slides sideways with the spin, like a
conveyor, so the push can be seen, and a HUD marker under the pause button
shows it too: one to three chevrons pointing the way the ball is carried.

## Holes and failure

Holes are rectangles on the tunnel surface: a start and length along the
tunnel, a centre angle and an angular width (optionally twisted into a
slanted band), with rounded corners, cut through a shell 0.45 m thick.
Holes that come within 1.2 m of each other blend into one opening. The
ball keeps its footing until its centre is 0.06 m past an edge; then it
really drops, and the edges of the cut are solid. A ball that
drops near the far edge slams into that wall and bounces back (with a thud,
a shake and a haptic) instead of passing through it; a ball that comes down
on an edge from above can be popped back out. The run is lost once the
ball's centre sinks below the lip, or when it hits a wall side-on. A swipe
up to 0.07 s after rolling off an edge still jumps ("coyote time").

Falling plays out for under half a second, the screen fades into the void
colour, and the run restarts at once with an "attempt N, best X%" toast. A
thin dashed ring on the wall marks your best distance.

## Speed and length

Forward speed grows linearly with progress: `v = base · (1 + 0.2 · s/L)`.
Because speed depends on position, the run time is
`T = L / (0.2 · base) · ln(1.2)`, and levels are sized so that `T = 60 s`
(see `SpeedProfile`). Base speeds: Dawn 13.65 m/s, Tide 17.5, Ember 21.

Numbers alone did not make the faster levels *feel* faster on a phone, so
speed drives the presentation too:

- **Field of view** follows speed: 64° at 12 m/s plus 1.5° per m/s (Dawn
  starts at 67°, Ember ends near 86°), so more wall streams past the edges.
- The **floor pattern** repeats faster on faster levels (its scale follows
  3 m on Dawn down to about 2 m on Ember), so it streams past much quicker.
  (Cartoon speed lines were tried and rejected as silly.)
- A fine **camera rumble** above 15 m/s.

## Level patterns

Bundled levels are written as a **script of sections** (`tools/generate_levels.gd`)
that `tools/level_generator.gd` turns into plain level data. Each section
names a pattern, how many, an intensity and optionally a new spin. The seed
only varies details inside a pattern, so every level has a designed shape.
The generator follows a "safe path" around the tunnel that drifts at a speed
a player can follow, so the route spirals and the camera rotation becomes
part of play.

| Pattern | What the player does |
|---|---|
| gate | A wide hole with one gap: steer into the gap. |
| ring | A full ring: jump it. |
| echo run | Evenly spaced rings matched to the *maximum* jump: one long swipe, then echo through. Tuned to the maximum because any long swipe gives exactly that height, so it is reproducible. |
| pad run | An echo run whose landing strips are pads around a wandering path: every echo must land on target. |
| bridge | A narrow strip of floor that winds around the tunnel: one twisted hole, so its edges are clean diagonals. |
| corkscrew | A bridge that turns faster, enough to need a constant lean. |
| slalom | Gates whose gaps alternate either side of the path, on a beat. |
| funnel | Gates back to back whose gap narrows in even, blocky steps. |
| combo | A ring, then a gate just after the landing with its gap off to one side. |
| split | Two gaps on opposite sides: pick one. |

The three levels:

- **Dawn** teaches one idea at a time (lean, jump, echo), then introduces a
  gentle spin (8 to 12 °/s).
- **Tide** is about currents: the spin is on from the start and the tide
  turns (+15, −20, +28, −30 °/s), with pad runs and corkscrews.
- **Ember** is the test: 21 to 25 m/s, spin from 25 up to 50 °/s that snaps
  round in a quarter of a second, narrow bridges, combos and long pad runs,
  and almost no rest.

`LevelValidator` rejects any gap that cannot be jumped at the local speed.
Tests play every level to the end with `Autopilot`, both perfectly and with
a **0.2 s reaction delay** on its steering (roughly a person's). The delay
the bot can survive measures difficulty: Dawn still finishes at 0.45 s,
Tide fails from 0.4 s, Ember from 0.25 s.

## Feel ("juice") inventory

All of it lives in `EffectsDirector`, `BallView`, `CameraRig` and the shaders.

- Normal landing: a soft ripple, the ball squashes, a low thud, a light haptic.
- Echo: the hit-stop, then a bold ring that expands *over the cylinder*, wrapping around the
  tunnel to meet itself on the far side. The ball flashes in the accent colour, the FOV kicks, a
  glassy note plays (D-major pentatonic, one step higher per echo in the
  chain) and a medium haptic fires. A perfect echo adds a bell overtone, a
  brighter wave and a heavy haptic. (No streak counter or PERFECT popup:
  they were removed as noise.)
- Jump: stretch, plus a soft whoosh pitched by height.
- Fall: a falling tone, a small camera shake, a heavy haptic, then a fade.
  Hitting the wall of the cut on the way down adds a thud, a squash, a
  shake and a medium haptic.
- Finish: a huge ripple, a rising arpeggio, a success haptic, the results screen.

## Visual language

Old Flash-game cartoon: flat, bright, high-contrast colour, hard shading and
thick black outlines. No textures, no realistic lighting, no glow.

- **Tunnel**: one flat colour at a time, taken from the level palette by
  progress, with a two-tone floor pattern (default: big rounded tiles in a
  running bond; stripes, diamonds, plain and the old rings are the other
  choices, `TunnelView.pattern`). The pattern slides sideways with the
  ground spin. The half of the tunnel opposite the ball is a flat darker
  tone (cel shading), which keeps "down" obvious as the world turns.
  Distance fades smoothly into the void colour along the tunnel.
- **Holes**: show a flat, strongly contrasting void colour with a few
  blinking cartoon stars. Every edge of floor gets a thick black outline
  and, just inside it, a crisp lighter lip, like a cut-out cartoon
  platform. Corners are rounded and diagonal edges are straight, because
  holes are drawn from a distance field, not from grid geometry. A platform
  floating in the void is just the platform: no rims or circles around it.
- **Edges**: 4× MSAA on geometry; the hole edges are antialiased in the
  shader from the distance field, and the outline never gets thinner than
  two pixels, so far edges stay clean. Patterns fade out with distance
  before they shimmer. Tunnel chunks overlap by 0.3 m so their seams never
  open hairline cracks onto the void.
- **Ball** (default skin "Classic"): a white ball with a wide coloured
  stripe, like a striped pool ball, so rolling reads in every direction,
  with one hard shadow step, a solid white shine spot and a thick black
  outline. Looks are `BallSkin` resources (`resources/balls/`), so new
  balls are data, not code.
- **Effects**: echo ripples are bold accent rings with black edges; the
  shadow is a hard-edged blob; the finish line is chequered.
- **Type**: Lilita One everywhere, white with a thick dark outline.

## Ideas not built yet

- Ghost replays (the simulation is deterministic, so recording InputFrames is enough).
- Attract mode: the Autopilot playing behind the menu.
- Per-level music whose tempo matches the echo period.
- Collectibles on risky lines for players chasing mastery.
- A ball picker (skins are already data: `BallSkin`).
- The level editor (see [LEVEL_FORMAT.md](LEVEL_FORMAT.md)).
