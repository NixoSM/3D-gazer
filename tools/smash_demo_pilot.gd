class_name SmashDemoPilot
extends Autopilot
## Plays the smash for recordings (main.gd's --smash-demo switch, on a level
## stripped of holes): a full jump, then smashes from the top of every arc,
## a few in a row, then a breather. It weaves gently so the ball's roll and
## the bounce's re-aim show.

const CHAIN := 3
const REST := 0.55

var _rest := 0.4
var _smashes := 0
var _clock := 0.0


func decide(sim: BallSimulation) -> InputFrame:
	var dt := 1.0 / STEP_RATE
	_clock += dt
	var frame := InputFrame.new(sin(_clock * 1.7) * 0.55)
	match sim.phase:
		BallSimulation.Phase.ROLLING:
			_rest -= dt
			if _rest <= 0.0:
				frame.jump_strength = 1.0
				_smashes = 0
		BallSimulation.Phase.AIRBORNE:
			var at_top := sim.vertical_speed <= 0.5 and sim.height > sim.last_jump_height * 0.85
			if at_top and sim.smash_stage == 0 and _smashes < CHAIN:
				frame.smash = true
				_smashes += 1
				_rest = REST
	return frame
