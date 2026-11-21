class_name EffectsDirector
extends Node
## Turns simulation events into feel: ripples, sound, haptics, camera, flash.
##
## This is the single place to tune "juice". Nothing here changes gameplay,
## so it is safe to experiment with.

@export var session: GameSession
@export var world: WorldView
@export var synth: ToneSynth

const E := BallSimulation.EventType


func _ready() -> void:
	session.sim_event.connect(_on_event)


func _on_event(event: BallSimulation.SimEvent) -> void:
	var accent := world.palette.accent_at(session.level.progress_at(event.s))
	match event.type:
		E.SMASH_COILED:
			_smash_coil()
		E.SMASH_DIVED:
			_smash_dive()
		E.SMASH_HIT:
			_smash_hit(event, accent)
		E.JUMPED:
			if event.bounce:
				_bounce(event)
			else:
				var fraction := inverse_lerp(session.tuning.min_jump_height, session.tuning.max_jump_height, event.height)
				synth.play_jump(fraction)
				world.ball.kick(0.6 + fraction * 0.6)
		E.LANDED:
			# Tiny dips (teetering on an edge) are not landings worth a thud.
			# A plain landing is sober: a squash, a soft thud, a tap of haptic.
			# The wave on the floor belongs to the smash alone.
			if not event.bounce and event.height > 2.5:
				world.ball.kick(-0.8)
				synth.play_land(0.35)
				Platform.haptic(Platform.Haptic.LIGHT)
		E.CHAIN_BROKEN:
			pass
		E.FELL:
			synth.play_fall()
			world.camera.shake(0.6)
			Platform.haptic(Platform.Haptic.HEAVY)
		E.BUMPED:
			# The ball hit the wall of a hole on its way down.
			var hit := clampf(event.height / 12.0, 0.2, 1.0)
			synth.play_land(hit)
			world.ball.kick(-1.0 - hit)
			world.camera.shake(0.3 + 0.5 * hit)
			Platform.haptic(Platform.Haptic.MEDIUM)
		E.FINISHED:
			world.tunnel.add_ripple(event.s, event.angle, world.now(), 1.6)
			world.camera.punch(6.0)
			synth.play_finish()
			Platform.haptic(Platform.Haptic.SUCCESS)


## Swipe down accepted: the ball coils and flips. Instant confirmation, so
## the input never feels lost during the (short) wind-up.
func _smash_coil() -> void:
	world.ball.kick(-0.9)
	world.ball.flip(26.0)
	world.camera.snap_fov(-1.5)
	synth.play_coil()
	Platform.haptic(Platform.Haptic.LIGHT)


func _smash_dive() -> void:
	world.ball.kick(2.2)
	synth.play_dive()


## The impact: the signature moment. It lands on the hit-stop, so while the
## world holds still the ball is pressed flat, the camera is knocked down and
## shaken, the floor tiles light up in a double wave and the boom plays.
## Power grows with the drop and the chain; from the top of the arc it is
## a notch bigger again.
func _smash_hit(event: BallSimulation.SimEvent, accent: Color) -> void:
	var drop := clampf(event.height / session.tuning.max_jump_height, 0.0, 1.0)
	var chain_boost := minf(event.chain * 0.08, 0.4)
	var power := clampf(0.35 + drop * 0.55 + chain_boost * 0.5 + (0.15 if event.perfect else 0.0), 0.0, 1.0)
	var now := world.now()
	world.tunnel.add_ripple(event.s, event.angle, now, 0.9 + power * 0.6)
	# The aftershock: a second wave a beat behind the first.
	world.tunnel.add_ripple(event.s, event.angle, now + 0.09, 0.45 + power * 0.4)
	world.ball.kick(-2.6 - power * 1.6)
	world.ball.flash(0.6 + power * 0.4, Color.WHITE)
	world.camera.dip(2.5 + power * 4.5)
	world.camera.shake(0.45 + power * 0.9)
	world.camera.snap_fov(-2.0 - power * 3.0)
	synth.play_land(1.0)
	synth.play_smash(event.chain, power, event.perfect)
	Platform.haptic(Platform.Haptic.HEAVY if power > 0.45 else Platform.Haptic.MEDIUM)


## End of the hit-stop: the ball springs back up.
func _bounce(event: BallSimulation.SimEvent) -> void:
	var fraction := inverse_lerp(session.tuning.min_jump_height, session.tuning.max_jump_height, event.height)
	world.ball.kick(1.8 + fraction)
	world.camera.punch(2.5 + fraction * 2.5 + (1.5 if event.perfect else 0.0))
	synth.play_bounce(fraction)
