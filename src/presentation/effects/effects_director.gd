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
		E.ECHO_HIT:
			_echo(event, accent)
		E.JUMPED:
			if event.echo:
				_echo_takeoff(event)
			else:
				var fraction := inverse_lerp(session.tuning.min_jump_height, session.tuning.max_jump_height, event.height)
				synth.play_jump(fraction)
				world.ball.kick(0.6 + fraction * 0.6)
		E.LANDED:
			# Tiny dips (teetering on an edge) are not landings worth a thud.
			# A plain landing is sober: a squash, a soft thud, a tap of haptic.
			# The wave on the floor belongs to the echo alone.
			if not event.echo and event.height > 2.5:
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


## The echo: the signature moment. It lands on the hit-stop, so the wave
## spreads while the world holds still. Strength grows with the chain, and
## perfect timing gets a brighter wave, a bell overtone and a firmer haptic.
func _echo(event: BallSimulation.SimEvent, accent: Color) -> void:
	var chain_boost := minf(event.chain * 0.12, 0.6)
	var strength := 0.75 + chain_boost + (0.35 if event.perfect else 0.0)
	world.tunnel.add_ripple(event.s, event.angle, world.now(), strength)
	world.ball.kick(-1.8)
	world.ball.flash(0.9 if event.perfect else 0.55, accent)
	world.camera.punch(2.0 + chain_boost * 3.0 + (1.5 if event.perfect else 0.0))
	synth.play_land(1.0)
	synth.play_echo(event.chain, event.perfect)
	Platform.haptic(Platform.Haptic.HEAVY if event.perfect else Platform.Haptic.MEDIUM)


## End of the hit-stop: the ball takes off again.
func _echo_takeoff(event: BallSimulation.SimEvent) -> void:
	world.ball.kick(0.9)
