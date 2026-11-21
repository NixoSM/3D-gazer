extends SceneTree
## Drives the real main scene with synthetic touches through the edge cases
## of the app flow: a finger still down when the ball falls, a touch on the
## pause button, the app going to the background mid-touch.
##
##   godot --headless --script res://tools/stress_flow.gd

var main: Node
var jumps := 0
var smashes := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	main.session.sim_event.connect(func(e: BallSimulation.SimEvent) -> void:
		if e.type == BallSimulation.EventType.JUMPED and not e.bounce:
			jumps += 1
		if e.type == BallSimulation.EventType.SMASH_COILED or e.type == BallSimulation.EventType.SMASH_HIT:
			smashes += 1)
	var size: Vector2 = root.get_visible_rect().size
	var mid := size * 0.5
	print("viewport ", size)

	# 1. Finger still on the glass when the ball falls.
	main._play_level(0)
	await _frames(10)
	_touch(0, mid, true)
	await _frames(2)
	_drag(0, mid + Vector2(0, -size.y * 0.3))
	await _frames(3)
	print("1. swipe before the fall -> jumps %d" % jumps)
	var hole: HoleData = main.session.level.holes[0]
	main.session.simulation.place(hole.s_start + hole.length * 0.5, hole.angle_center)
	await _frames(30)
	print("   fell: state=%s" % main.State.keys()[main.state])
	_touch(0, mid + Vector2(0, -size.y * 0.3), false)  # lift while the run is over
	await _wait_for_state(main.State.PLAYING)
	await _frames(20)
	jumps = 0
	_swipe_up(mid, size)
	await _frames(10)
	print("   next run, a full swipe up -> jumps %d %s" % [jumps, "(OK)" if jumps == 1 else "(BUG: swipe lost)"])
	await _frames(60)

	# 2. A tap on the pause button, then resume and swipe.
	main._begin_run()
	await _frames(10)
	var pause_button := _find_button(main.hud, "pause")
	var at := pause_button.get_global_rect().get_center()
	_touch(0, at, true)
	await _frames(2)
	_touch(0, at, false)
	await _frames(3)
	var g: GestureRecognizer = main.input_router.gestures
	print("2. tapped pause at %s: state=%s, recognizer finger=%d holding=%s" % [at, main.State.keys()[main.state], g._active_index, g.is_holding()])
	main._resume()
	await _frames(3)
	jumps = 0
	_swipe_up(mid, size)
	await _frames(10)
	print("   after resume, a full swipe up -> jumps %d %s" % [jumps, "(OK)" if jumps == 1 else "(BUG)"])
	await _frames(60)

	# 3. The app goes to the background while a finger rests on the screen.
	main._begin_run()
	await _frames(10)
	_touch(0, mid, true)
	await _frames(2)
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	_touch(0, mid, false)  # iOS cancels the touch while we are away
	await _frames(2)
	main._resume()
	await _frames(3)
	print("3. back from the background: recognizer finger=%d holding=%s %s" % [g._active_index, g.is_holding(), "(BUG: stuck finger)" if g.is_holding() else "(OK)"])
	jumps = 0
	smashes = 0
	_swipe_up(mid, size)
	await _frames(10)
	print("   first swipe up after it -> jumps %d smashes %d %s" % [jumps, smashes, "(OK)" if jumps == 1 else "(BUG)"])

	# 4. A swipe down queued in the same frame as the pause: does it fire on resume?
	await _frames(60)
	main._begin_run()
	await _frames(10)
	main.session.simulation.step(1.0 / 120.0, InputFrame.new(0.0, 1.0))
	await _frames(4)
	smashes = 0
	main.input_router.gestures.smashed = true
	main._pause()
	await _frames(5)
	main._resume()
	await _frames(5)
	print("4. swipe down queued at the moment of pausing, fired on resume: %s" % ("yes (BUG)" if smashes > 0 else "no (OK)"))

	# 5. The HUD's pause button pressed while a fall fades out.
	var hole2: HoleData = main.session.level.holes[0]
	main.session.simulation.place(hole2.s_start + hole2.length * 0.5, hole2.angle_center)
	await _frames(30)
	var before: String = main.State.keys()[main.state]
	main.hud.pause_pressed.emit()
	await _frames(2)
	print("5. pause pressed during %s -> state %s, tree paused %s %s" % [before, main.State.keys()[main.state], paused, "(OK)" if main.state != main.State.PAUSED else "(BUG)"])
	if paused:
		main._resume()
	quit()


func _swipe_up(mid: Vector2, size: Vector2) -> void:
	_touch(0, mid, true)
	await _frames(2)
	_drag(0, mid + Vector2(0, -size.y * 0.3))
	await _frames(2)
	_touch(0, mid + Vector2(0, -size.y * 0.3), false)


func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = position
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, position: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = position
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait_for_state(state: int) -> void:
	for i in 2000:
		if main.state == state:
			return
		await process_frame


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text.to_lower() == text:
			return child
		var found := _find_button(child, text)
		if found:
			return found
	return null
