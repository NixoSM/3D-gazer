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
   accelerates, coasts and slows like a ball on a tilted plane, only
   quicker than real physics allows, so it can carve sharp lines.
3. **Rhythm is rewarded.** The echo turns jumping into a beat: swipe once,
   then tap on each landing. Good timing is felt in light, sound and touch.
4. **Colour is progress.** No progress bar. The tunnel's palette moves from
   start to finish and the next colour is always visible ahead.

## Controls

| Gesture | Effect |
|---|---|
| Tilt left/right | Lateral acceleration proportional to tilt, 30 m/s² at full tilt (`BallTuning.steering_acceleration`; a real ball rolling down a 32° slope manages ~13). Rolling resistance decays lateral speed exponentially (`2.4/s`), so releasing the tilt lets the ball coast briefly, then settle. Lateral speed is capped at 13 m/s; airborne, the ball keeps 70% of tilt authority. The ball was made this quick on purpose, to leave room for harder, flashier levels. |
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
the tunnel), painted in the editor's Spin panel as a direction, a starting
rate and how much it grows.

**Within a level the spin turns one way only and only ever speeds up**
(Nicola, November 2026): from a gentle 12 °/s near the end of the first
level to 160 °/s at the end of the last (the table under
[The seven levels](#the-seven-levels) has each level's range). The player learns
which way to lean and has to lean harder; an earlier version reversed it
mid-level, which read as a trick rather than a challenge. In the simulation, rolling
resistance relaxes the ball's sideways speed towards the spin drift
instead of towards zero, and the air inside the tunnel turns with it.

The spin never changes direction on its own: only the level data turns it.
(An earlier build flipped it on every echo; Nicola dropped that after
playing it.) The floor pattern is fixed to the wall like the holes (an
earlier build slid it with the spin, like a conveyor, which made the holes
seem to wander). A HUD marker under the pause button shows the spin: one to
three chevrons pointing the way the ball is carried.

## Holes and failure

Holes are rectangles on the tunnel surface: a start and length along the
tunnel, a centre angle and an angular width (optionally twisted into a
slanted band), with rounded corners, cut through a shell 0.8 m thick (chunky, by request).
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

Forward speed grows linearly with progress, `v = base · (1 + ramp · s/L)`,
times an optional **surge** factor painted along the level (speed keys,
see LEVEL_FORMAT.md): a factor that steps up over half a second feels like
a gear change. Mixtape steps up 4% at each of its four splices, Supernova
10% at the start of each of its five later acts (34 m/s at the start, 51
by the end). Levels are sized so that they last about a minute (Lemonade
58 s), whatever their speeds (`LevelData.duration()`).

Numbers alone did not make the faster levels *feel* faster on a phone, so
speed drives the presentation too:

- **Field of view** follows speed: 64° at 12 m/s plus 1.5° per m/s up to
  86° (about 27 m/s), then only 0.5° per m/s, up to 98° (Supernova's top
  speed). Past 27 m/s the full rate bent the edges of the screen into a
  fish-eye; the slower rate keeps the speed reading without that.
- The **floor pattern** repeats faster on faster levels (its scale follows
  speed), so it streams past much quicker. (Cartoon speed lines were tried
  and rejected as silly.)
- A fine **camera rumble** above 15 m/s.

## The seven levels

The levels are designed by hand. Each is a script in `tools/levels/`
written against a clock (`LevelBuilder`: "a ring at 12.7 s lasting 0.18 s",
"a gate at 0.3 s after the funnel, 40° right of where the ball is"), which
`tools/author_levels.gd` turns into the plain JSON the game and the editor
read. Writing on a clock keeps every pattern on the beat it was written
for, at any speed; the builder also knows the ball's physics (how long a
jump of each size is in the air, how far the spin carries an echo), so
landings are placed where a player's jump actually comes down.

| # | Level | Speed (m/s) | Spin (°/s) | The idea |
|---|---|---|---|---|
| 1 | **Lemonade** | 20 to 24 | none, then 12 to 16 | The first level: every mechanic introduced once, repeated once, then combined (lean, big and small jumps, steering in the air, echo, aimed echo, leaning against the spin). Short hints name each one the moment the layout asks for it. |
| 2 | **Bubblegum** | 23 to 28 | 15 to 28 | A clear step up and a tour of shapes: polka dots, a zigzag ribbon, floating hoops, a half-turn corkscrew, chevrons, hop-leap-hop. |
| 3 | **Hot Sauce** | 27 to 32 | 25 to 50 | As hard as Ember, the hardest of the old levels: the heat comes in waves, each hotter than the last, with two seconds to breathe between. |
| 4 | **Moon Bounce** | 25 to 30 | 15 to 35 | Gimmick: floating platforms. The tunnel crumbles into hoops, arcs and moonlets in a starry void: a forked highway, a spiral staircase that turns the world over, stepping stones, a broken ribbon, then it reassembles. |
| 5 | **Mixtape** | 28 to 36 | 32 to 56 | Mastery: five "tracks" (lean, jump sizes, echo, floating, a B-side), each its own colour and a notch faster, spliced by a ring. Side doors against the spin, half-height echo runs, an echo reshaped into a leap. |
| 6 | **Screwball** | 28 to 32 | 30 to 70 | Hard gimmick: every floor is a screw thread. Rifling, floating threads that turn with, faster than and against the current, stripped threads, a screw that turns faster than the ball can roll (bounce it: each full echo lands one thread round) and a four-thread nut. Wide threads, no pixel-perfect jumps: it asks you to read which way the floor moves. |
| 7 | **Supernova** | 34 to 51 | 50 to 160 | Maniacal: a star's life in six titled acts (Ignition, Corona, Solar wind, Red giant, Collapse, Supernova), each faster and spinning harder, with the colour flickering in bands and the void pulsing. Not meant to be finished on the first try. |

Some patterns appear in several levels: **gates** (a hole with one gap),
**rings** (jump), **echo runs** and **pad runs** (rings spaced for a full
jump, the landing strips plain or narrow pads), **ribbons and bridges**
(floor bands that wind round, made with twisted holes), **dots**, **chevrons**,
**zigzags**, **islands** of floor floating in the void, **threads** (several
bands winding round together), and **funnels**: two walls that close in
from either side and gather a player into one lane wherever they were.
Funnels open from just behind the ball (or from the edges of the road
before them) and close at 80 °/s at most, slower than the ball can cross,
so a funnel can never be met from behind. Spin-aware placement matters at
these spins: an echo drifts `spin · (T − (1 − e^(−kT))/k)` degrees in the
air, about half of `spin · T`, because the echo resets the ball's sideways
speed, and pads, debris and threads are placed with that.

**Difficulty is measured with the bot** (`tools/rate_levels.gd`). The
sweep plays each level with steering delays from 0 to 0.5 s: the longest
delay it still finishes with is the level's *reaction budget*. Then two
human-like profiles play it 24 times each (a reaction delay plus a wobbling
hand and swipes a little early, late or off in size, a different seed each
run): **steady** (0.25 s) and **shaky** (0.3 s, wobblier). The finish rate
is roughly how often a player of that kind gets through once they know the
level.

| Level | Reaction budget | Steady: finished (median reached) | Shaky: finished (median reached) |
|---|---|---|---|
| Lemonade | 0.45 s | 100% (100%) | 91% (100%) |
| Bubblegum | 0.50 s or more | 91% (100%) | 37% (75%) |
| Hot Sauce | 0.15 s | 29% (68%) | 8% (45%) |
| Moon Bounce | 0.30 s | 50% (100%) | 8% (60%) |
| Mixtape | 0.20 s | 12% (60%) | 0% (46%) |
| Screwball | 0.15 s | 25% (65%) | 0% (25%) |
| Supernova | 0.05 s | 0% (27%) | 0% (19%) |
| *Ember (old, for comparison)* | *0.20 s* | *37% (50%)* | *12% (37%)* |

(November 2026, 24 runs per profile. With 24 runs a rate is good to about
±10 points, so Mixtape and Screwball are about as hard as each other for a
steady player; Screwball is the harder one for a shaky player. The sweep
is not monotonic on every level: a bot that reacts later sometimes takes
a different line and gets further. The sweep stops at 0.5 s, so it cannot
tell the two easiest levels apart; the profiles can.)

Tests play every level to the end with `Autopilot`, perfectly and with
each level's reaction delay from that table (`tests/test_autopilot.gd`).
`LevelValidator` rejects any gap that cannot be jumped at the local speed.
(The bot steers with fixed, person-like gains in m/s², so a quicker ball
does not make it a better player. These ratings are a bot's: they rank the
levels well but are not a person's numbers. Only playing on the phone
says how they feel.)

## Feel ("juice") inventory

All of it lives in `EffectsDirector`, `BallView`, `CameraRig` and the shaders.

- Normal landing: deliberately sober. The ball squashes, a soft thud, a
  light haptic, nothing on the floor.
- Echo: the hit-stop, then a wave spreads *over the cylinder* and lights up
  whole floor tiles as it reaches them (accent colour, black seams),
  wrapping around the tunnel to meet itself on the far side. The ball flashes in the accent colour, the FOV kicks, a
  glassy note plays (D-major pentatonic, one step higher per echo in the
  chain) and a medium haptic fires. A perfect echo adds a bell overtone, a
  brighter wave and a heavy haptic. (No streak counter or PERFECT popup:
  they were removed as noise.)
- Jump: stretch, plus a soft whoosh pitched by height.
- Fall: a falling tone, a small camera shake, a heavy haptic, then a fade.
  Hitting the wall of the cut on the way down adds a thud, a squash, a
  shake and a medium haptic.
- Finish: a huge tile wave, a rising arpeggio, a success haptic, the results screen.

## Visual language

Old Flash-game cartoon: flat, bright, high-contrast colour, hard shading and
thick black outlines. No textures, no realistic lighting, no glow.

- **Tunnel**: one flat colour at a time, taken from the level palette by
  progress, with big rounded tiles in a running bond, fixed to the wall.
  The half of the tunnel opposite the ball is a flat darker tone (cel
  shading), which keeps "down" obvious as the world turns. Distance fades
  smoothly into the void colour along the tunnel.
- **Holes**: show a flat, strongly contrasting void colour with a few
  blinking cartoon stars. Every edge of floor gets a thick black outline,
  like a cut-out cartoon platform, drawn like an ink line: a quarter metre
  of floor, but never thicker than about 1% of the screen (close to the
  camera it would be a black wedge) and never thinner than 1.5 pixels.
  Through a hole you see the cut faces of the shell (0.8 m thick), in a
  darker tone of the wall with the tile seams carried down them and a black
  line at the back, so every tile reads as a solid block. Corners are
  rounded and diagonal edges are straight: the holes are cut into the
  geometry from the same distance field the ball falls by. A platform
  floating in the void is just the platform: no rims or circles around it.
- **Edges**: every edge is a real triangle edge, smoothed by 4× MSAA.
  Patterns fade out with distance before they shimmer. The tunnel is
  watertight by construction and checked pixel by pixel against a ray-cast
  of the level (see ARCHITECTURE.md, "Checking the picture").
- **Ball** (default skin "Classic"): a white ball with a wide coloured
  stripe, like a striped pool ball, so rolling reads in every direction,
  with one hard shadow step, a solid white shine spot and a thick black
  outline. Looks are `BallSkin` resources (`resources/balls/`), so new
  balls are data, not code.
- **Effects**: echoes light up floor tiles; the
  shadow is a hard-edged blob; the finish line is chequered.
- **Type**: Lilita One everywhere, white with a thick dark outline.

## Ideas not built yet

- Ghost replays (the simulation is deterministic, so recording InputFrames is enough).
- Attract mode: the Autopilot playing behind the menu.
- Per-level music whose tempo matches the echo period.
- Collectibles on risky lines for players chasing mastery.
- A ball picker (skins are already data: `BallSkin`).
- The level editor (see [LEVEL_FORMAT.md](LEVEL_FORMAT.md)).
