extends SceneTree
## The thumb sticks must reach GamepadInput as the same -1..1 vectors a physical
## pad reports, and must stop reporting the moment a menu is open. Headless has
## neither a touchscreen nor a controller, which is exactly the case the sticks
## exist for.

const STICK := preload("res://scripts/ui/thumb_stick.gd")
const JET := preload("res://scripts/jet/jet_controller.gd")
const STICK_SIZE := Vector2(420, 300)
const CENTRE := Vector2(200, 150)


func _init() -> void:
	call_deferred("run")


func _touch(pointer: int, point: Vector2, pressed: bool) -> InputEvent:
	var event: InputEvent = InputEventScreenTouch.new()
	event.index = pointer
	event.position = point
	event.pressed = pressed
	return event


func _drag(pointer: int, point: Vector2) -> InputEvent:
	var event: InputEvent = InputEventScreenDrag.new()
	event.index = pointer
	event.position = point
	return event


func run() -> void:
	var pad: Node = root.get_node("GamepadInput")
	var failures: Array[String] = []
	pad.set_thumb_controls(false)
	if pad.has_flight_input():
		failures.append("a pad-less session with the sticks off must have no flight input")
	pad.set_thumb_controls(true)
	if not pad.has_flight_input():
		failures.append("thumb controls must count as flight input")
	if pad.requires_controller_attention():
		failures.append("thumb controls must replace the connect-a-controller prompt")

	var stick: Control = STICK.new()
	stick.size = STICK_SIZE
	root.add_child(stick)
	await process_frame
	stick._input(_touch(0, CENTRE, true))
	stick._input(_drag(0, CENTRE + Vector2(96, 0)))
	if stick.vector.x < 0.99:
		failures.append("a full right drag should read ~1.0 on x, got %.3f" % stick.vector.x)
	if absf(stick.vector.y) > 0.001:
		failures.append("a horizontal drag leaked into pitch: %.3f" % stick.vector.y)
	stick._input(_touch(0, CENTRE + Vector2(96, 0), false))
	if stick.vector != Vector2.ZERO:
		failures.append("releasing the thumb must centre the stick")
	stick._input(_touch(1, CENTRE, true))
	stick._input(_drag(1, CENTRE + Vector2(0, -10)))
	if stick.vector != Vector2.ZERO:
		failures.append("10 px of travel is inside the dead zone, got %.3f" % stick.vector.y)
	# Dragging off the corner keeps the grab, which is the whole point of reading
	# input through _input rather than the control's own rectangle.
	stick._input(_drag(1, Vector2(2000, 150)))
	if stick.vector.x < 0.99:
		failures.append("the stick lost the finger once it left the corner")
	stick._input(_touch(1, Vector2(2000, 150), false))
	stick.queue_free()

	pad.set_thumb_input(Vector2(0.0, -0.6), Vector2(0.4, 0.0), 0.5)
	# The sticks report raw deflection; GamepadInput owns the shared dead
	# zone and response curve, exactly as it does for a pad.
	var flight: Vector2 = pad.get_flight_vector()
	var aim: Vector2 = pad.get_aim_vector()
	if absf(aim.y) > 0.001:
		failures.append("a horizontal thumb drag leaked into the look pitch")
	if flight.y > -0.2:
		failures.append("the thumb did not reach the pitch axis: %.3f" % flight.y)
	if aim.x < 0.2:
		failures.append("the thumb did not reach the look axis: %.3f" % aim.x)
	if not is_equal_approx(pad.get_jet_throttle_axis(), 0.5):
		failures.append("the thumb did not reach the throttle: %.3f" % pad.get_jet_throttle_axis())
	pad.set_settings_open(true)
	if pad.get_flight_vector() != Vector2.ZERO or pad.get_jet_throttle_axis() != 0.0:
		failures.append("sticks must go quiet while a menu is open")
	pad.set_settings_open(false)

	# HOLD LOOK must route the right stick to the camera instead of the
	# helicopter's yaw and collective, exactly like A on a pad.
	pad.set_thumb_free_look(true)
	if not pad.is_free_look_held():
		failures.append("the thumb LOOK hold did not engage manual aim")
	if pad.get_flight_yaw_collective_vector() != Vector2.ZERO:
		failures.append("the right stick must stop flying while LOOK is held")
	pad.set_thumb_free_look(false)
	if pad.is_free_look_held():
		failures.append("releasing LOOK must hand the right stick back to flight")

	# End to end: a thumb held over must actually move the control surfaces,
	# through the same has_flight_input() gate a controller is read behind.
	var jet = JET.new()
	root.add_child(jet)
	jet.set_physics_process(false)
	jet._world_limit = 100000.0
	jet.minimum_display_speed = 175.0
	jet.maximum_display_speed = 175.0
	jet.launch(Vector3(0, 900, 0), 0.0)
	var throttle_before: float = jet.throttle
	pad.set_thumb_controls(true)
	pad.set_thumb_input(Vector2(0.9, 0.0), Vector2.ZERO, 0.5)
	jet._read_controls(1.0 / 60.0)
	if jet.roll_input < 0.8:
		failures.append("a right-hand thumb drag did not command roll: %.3f" % jet.roll_input)
	if not jet.throttle > throttle_before:
		failures.append("holding the thumb throttle did not spool the engine")
	pad.set_thumb_input(Vector2.ZERO, Vector2.ZERO, 0.0)
	jet._read_controls(1.0 / 60.0)
	if not is_zero_approx(jet.roll_input):
		failures.append("a released thumb must centre the stick, got %.3f" % jet.roll_input)
	jet.free()

	pad.set_thumb_controls(false)
	if pad.get_flight_vector() != Vector2.ZERO or pad.get_aim_vector() != Vector2.ZERO:
		failures.append("turning the sticks off must clear their input")

	for note in failures:
		print("THUMB_STICK_TEST_FAIL: " + note)
	if not failures.is_empty():
		quit(1)
		return
	print("THUMB_STICK_TEST_PASS")
	quit(0)
