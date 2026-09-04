extends SceneTree

## The on-screen stick has to produce exactly what a thumbstick produces, in the
## same units and with the same signs, or the flight model would need to learn
## about touch -- and it must not. Screen y is down and the gamepad's LEFT_Y is
## down-positive, and `pitch_input = stick.y` raises the nose, so a downward
## drag is stick-back is nose-up with no sign flips anywhere.

const TOUCH := preload("res://scripts/ui/touch_controls.gd")
const GAMEPAD := preload("res://scripts/input/gamepad_input.gd")

var _failed := false


func _init() -> void:
	_centre_is_neutral()
	_full_deflection_is_unit()
	_drag_beyond_the_ring_is_clamped()
	_down_is_nose_up_and_right_is_roll_right()
	_touch_mode_satisfies_the_flight_code()
	_a_real_controller_wins()
	if _failed:
		return
	print("TOUCH_CONTROLS_TEST_PASS")
	quit()


func _centre_is_neutral() -> void:
	var stick: Vector2 = TOUCH.stick_vector(Vector2(100.0, 100.0), Vector2(100.0, 100.0), 80.0)
	if not stick.is_zero_approx():
		_fail("a thumb that has not moved commands nothing, got %v" % stick)


func _full_deflection_is_unit() -> void:
	var stick: Vector2 = TOUCH.stick_vector(Vector2(100.0, 100.0), Vector2(180.0, 100.0), 80.0)
	if not is_equal_approx(stick.x, 1.0):
		_fail("the edge of the ring is full deflection, got %f" % stick.x)


func _drag_beyond_the_ring_is_clamped() -> void:
	var stick: Vector2 = TOUCH.stick_vector(Vector2(100.0, 100.0), Vector2(900.0, 900.0), 80.0)
	if stick.length() > 1.0 + 1e-5:
		_fail("dragging off the ring must not exceed full deflection, got %f" % stick.length())
	if not is_equal_approx(stick.length(), 1.0):
		_fail("but it must still be full deflection, got %f" % stick.length())


## The sign convention is the whole reason this is tested.
func _down_is_nose_up_and_right_is_roll_right() -> void:
	var down: Vector2 = TOUCH.stick_vector(Vector2(100.0, 100.0), Vector2(100.0, 160.0), 80.0)
	if down.y <= 0.0:
		_fail("dragging down the screen is stick-back, which is positive y, got %f" % down.y)
	var right: Vector2 = TOUCH.stick_vector(Vector2(100.0, 100.0), Vector2(160.0, 100.0), 80.0)
	if right.x <= 0.0:
		_fail("dragging right is positive roll, got %f" % right.x)


## The flight code asks `is_controller_ready()` before it reads anything at all.
## Touch mode has to answer yes or the stick is never read.
func _touch_mode_satisfies_the_flight_code() -> void:
	var pad = GAMEPAD.new()
	if pad.is_controller_ready():
		_fail("no device and no touch mode is not ready")
	pad.touch_mode = true
	if not pad.is_controller_ready():
		_fail("touch mode must read as ready or the flight code never asks for the stick")
	pad.virtual_flight = Vector2(0.5, -0.25)
	if not pad.get_raw_flight_vector().is_equal_approx(Vector2(0.5, -0.25)):
		_fail("the virtual stick must come back as the raw flight vector, got %v" % pad.get_raw_flight_vector())
	pad.free()


func _a_real_controller_wins() -> void:
	var pad = GAMEPAD.new()
	if pad.has_real_controller():
		_fail("there is no gamepad attached to a headless test")
	pad.touch_mode = true
	if pad.has_real_controller():
		_fail("touch mode must not masquerade as real hardware: the overlay depends on the difference")
	pad.free()


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
