extends SceneTree

## The gesture layer on its own: the same synthetic events Android and a desktop
## mouse deliver, fed straight into the module with a real camera behind it. No
## scene, no renderer, no phone -- but every number here is what a finger does
## to the map.

const GESTURES := preload("res://scripts/battle_map/battle_map_gestures.gd")
const VIEW := preload("res://scripts/battle_map/battle_map_view.gd")

var failed := false
var taps: Array = []
var doubles: Array = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _camera() -> VIEW:
	var view: VIEW = VIEW.new()
	view.viewport_size = Vector2(900, 600)
	view.range_m = 10000.0
	return view


func _pad() -> GESTURES:
	var gestures: GESTURES = GESTURES.new()
	taps.clear()
	doubles.clear()
	gestures.tapped.connect(_on_tapped)
	gestures.double_tapped.connect(_on_double_tapped)
	return gestures


func _on_tapped(point: Vector2) -> void:
	taps.append(point)


func _on_double_tapped(point: Vector2) -> void:
	doubles.append(point)


func _touch(index: int, point: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	return event


func _drag(index: int, point: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	return event


func _button(button: int, point: Vector2, pressed: bool, double := false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.global_position = point
	event.pressed = pressed
	event.double_click = double
	return event


func _motion(point: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	return event


func _run() -> void:
	_check_one_finger_drag()
	_check_pinch_zooms_about_the_fingers()
	_check_two_finger_tilt()
	_check_two_finger_rotate()
	_check_taps()
	_check_fling()
	_check_mouse()
	_check_touch_outranks_synthesised_mouse()
	if not failed:
		print("BATTLE_MAP_GESTURES_TEST_PASS")
	quit(1 if failed else 0)


func _check_one_finger_drag() -> void:
	var view := _camera()
	var pad := _pad()
	pad.setup(view)
	var grab := view.unproject(Vector2(300, 200))
	check(pad.feed(_touch(0, Vector2(300, 200), true), 0), "a touch press must be consumed")
	check(pad.engaged, "a finger on the map must count as engaged so the stick stands down")
	check(pad.feed(_drag(0, Vector2(320, 212)), 16), "a touch drag must be consumed")
	check(pad.feed(_drag(0, Vector2(400, 260)), 32), "a touch drag must be consumed")
	check(
		view.project(grab).distance_to(Vector2(400, 260)) < 0.01,
		"the ground a finger grabbed must stay under it"
	)
	check(taps.is_empty(), "a drag must never read as a tap")
	pad.feed(_touch(0, Vector2(400, 260), false), 48)
	check(not pad.engaged, "lifting every finger must release the map")
	check(doubles.is_empty(), "a drag may not double tap either")


func _check_pinch_zooms_about_the_fingers() -> void:
	var view := _camera()
	var pad := _pad()
	pad.setup(view)
	var anchor := view.unproject(Vector2(450, 300))
	pad.feed(_touch(0, Vector2(300, 300), true), 0)
	pad.feed(_touch(1, Vector2(600, 300), true), 8)
	pad.feed(_drag(0, Vector2(150, 300)), 24)
	pad.feed(_drag(1, Vector2(750, 300)), 24)
	check(is_equal_approx(view.range_m, 5000.0), "spreading the fingers 2:1 must halve the view")
	check(view.unproject(Vector2(450, 300)).distance_to(anchor) < 0.01, "a pinch must keep the ground between the fingers still")
	check(view.tilt == 0.0, "a purely horizontal pinch must not tilt the map")
	pad.feed(_touch(0, Vector2(150, 300), false), 32)
	pad.feed(_touch(1, Vector2(750, 300), false), 32)
	check(taps.is_empty() and doubles.is_empty(), "a pinch is not a tap")


func _check_two_finger_tilt() -> void:
	var view := _camera()
	var pad := _pad()
	pad.setup(view)
	view.tilt = 0.5
	var anchor := view.unproject(Vector2(450, 300))
	pad.feed(_touch(0, Vector2(300, 300), true), 0)
	pad.feed(_touch(1, Vector2(600, 300), true), 8)
	pad.feed(_drag(0, Vector2(300, 240)), 24)
	pad.feed(_drag(1, Vector2(600, 240)), 24)
	# Two samples of -60 px would be -120 if the travel were measured from the
	# press instead of from the previous sample; that is the bug this pins out.
	check(is_equal_approx(view.tilt, 0.5 + 60.0 * GESTURES.LEAN_PER_PIXEL), "dragging the pair up must lean the map back")
	check(is_equal_approx(view.range_m, 10000.0), "a vertical pair drag must not zoom")
	check(view.unproject(Vector2(450, 300)).distance_to(anchor) < 0.01, "tilting must not slide the map out from under the fingers")
	pad.feed(_drag(0, Vector2(290, 240)), 40)
	pad.feed(_drag(1, Vector2(610, 240)), 40)
	check(is_equal_approx(view.tilt, 0.5 + 60.0 * GESTURES.LEAN_PER_PIXEL), "a held pair must stop leaning once it stops travelling")
	pad.feed(_touch(0, Vector2(290, 240), false), 48)
	pad.feed(_touch(1, Vector2(610, 240), false), 48)


func _check_two_finger_rotate() -> void:
	var view := _camera()
	var pad := _pad()
	pad.setup(view)
	view.tilt = 0.5
	var anchor := view.unproject(Vector2(450, 300))
	pad.feed(_touch(0, Vector2(300, 300), true), 0)
	pad.feed(_touch(1, Vector2(600, 300), true), 8)
	# Same separation, same midpoint, only the angle moved: 0.5 rad clockwise.
	pad.feed(_drag(0, Vector2(318.36, 228.09)), 24)
	pad.feed(_drag(1, Vector2(581.64, 371.91)), 24)
	check(fposmod(view.bearing + 0.5, TAU) < 0.01, "turning the fingers clockwise must swing the ground with them")
	check(absf(view.tilt - 0.5) < 0.001, "a pure rotation must not tilt")
	check(is_equal_approx(view.range_m, 10000.0), "a rotation at constant spread must not zoom")
	check(view.unproject(Vector2(450, 300)).distance_to(anchor) < 0.01, "the map must spin about the fingers, not about nowhere")
	pad.feed(_touch(0, Vector2(318.36, 228.09), false), 32)
	pad.feed(_touch(1, Vector2(581.64, 371.91), false), 32)


func _check_taps() -> void:
	var view := _camera()
	var pad := _pad()
	pad.setup(view)
	var before := view.centre
	pad.feed(_touch(0, Vector2(700, 120), true), 0)
	pad.feed(_touch(0, Vector2(700, 120), false), 40)
	check(taps.size() == 1 and taps[0] == Vector2(700, 120), "a short press must report a tap where it landed")
	check(view.centre == before, "a tap must not move the camera")
	pad.feed(_touch(0, Vector2(704, 124), true), 120)
	pad.feed(_touch(0, Vector2(704, 124), false), 160)
	check(doubles.size() == 1 and taps.size() == 1, "a second tap in place must upgrade to a double tap, not select twice")
	pad.feed(_touch(0, Vector2(200, 500), true), 300)
	pad.feed(_touch(0, Vector2(200, 500), false), 340)
	check(taps.size() == 2, "a far second tap is two single taps")
	# A press held past the tap window is a look, not a selection.
	pad.feed(_touch(0, Vector2(120, 120), true), 1000)
	pad.feed(_touch(0, Vector2(120, 120), false), 1000 + int(GESTURES.TAP_SECONDS * 1000.0) + 60)
	check(taps.size() == 2 and doubles.size() == 1, "a long press must not select anything")


func _check_fling() -> void:
	var view := _camera()
	var pad := _pad()
	pad.setup(view)
	var start := view.centre
	pad.feed(_touch(0, Vector2(300, 300), true), 0)
	for step in range(8):
		pad.feed(_drag(0, Vector2(300.0 + 10.0 * (step + 1), 300)), 16 * (step + 1))
	pad.feed(_touch(0, Vector2(380, 300), false), 144)
	check(view.tick(1.0 / 60.0), "a released flick must keep the map moving on its own")
	var seconds := 0.0
	while seconds < 3.0:
		view.tick(1.0 / 60.0)
		seconds += 1.0 / 60.0
	check(view.centre.x < start.x - 100.0, "the map must coast in the direction the finger was going")
	check(not view.tick(1.0 / 60.0), "a fling must come to rest by itself")
	check(view.centre.x < start.x, "a fling may never pull the map back past its release point")


func _check_mouse() -> void:
	var view := _camera()
	var pad := _pad()
	pad.setup(view)
	var grab := view.unproject(Vector2(200, 200))
	pad.feed(_button(MOUSE_BUTTON_LEFT, Vector2(200, 200), true), 0)
	check(pad.feed(_motion(Vector2(260, 240), Vector2(60, 40)), 16), "a left drag must be consumed")
	check(view.project(grab).distance_to(Vector2(260, 240)) < 0.01, "the left button must drag the ground it started on")
	pad.feed(_button(MOUSE_BUTTON_LEFT, Vector2(260, 240), false), 32)
	check(taps.is_empty(), "a mouse drag must not select")
	pad.feed(_button(MOUSE_BUTTON_LEFT, Vector2(500, 400), true), 600)
	pad.feed(_button(MOUSE_BUTTON_LEFT, Vector2(500, 400), false), 640)
	check(taps.size() == 1 and taps[0] == Vector2(500, 400), "a mouse click without travel is a tap")
	pad.feed(_button(MOUSE_BUTTON_LEFT, Vector2(508, 404), true, true), 700)
	check(doubles.size() == 1, "a reported double click must fly the camera, not select twice")
	pad.feed(_button(MOUSE_BUTTON_LEFT, Vector2(508, 404), false), 720)
	var anchor := view.unproject(Vector2(640, 160))
	var widest := view.range_m
	pad.feed(_button(MOUSE_BUTTON_WHEEL_UP, Vector2(640, 160), true), 800)
	check(view.range_m < widest, "the wheel must zoom in")
	check(view.unproject(Vector2(640, 160)).distance_to(anchor) < 0.01, "the wheel must zoom about the cursor")
	var tilt := view.tilt
	var bearing := view.bearing
	pad.feed(_button(MOUSE_BUTTON_RIGHT, Vector2(450, 300), true), 900)
	check(pad.feed(_motion(Vector2(430, 200), Vector2(-20, -100)), 916), "the right button must be consumed too")
	check(view.tilt > tilt, "pulling the right button up must lean the map back")
	check(view.bearing > bearing, "pulling the right button left must swing the ground with it")
	check(taps.size() == 1, "the right button never selects")
	pad.feed(_button(MOUSE_BUTTON_RIGHT, Vector2(430, 200), false), 932)
	check(view.tilt <= VIEW.TILT_MAX and view.tilt >= 0.0, "a mouse lean must stay inside the camera limits")


func _check_touch_outranks_synthesised_mouse() -> void:
	var view := _camera()
	var pad := _pad()
	pad.setup(view)
	var before := view.centre
	pad.feed(_touch(0, Vector2(300, 300), true), 1000)
	var grab := view.unproject(Vector2(300, 300))
	# Android fires a mouse event beside the touch it came from. Panning twice
	# over is the bug this block exists to stop.
	check(not pad.feed(_button(MOUSE_BUTTON_LEFT, Vector2(240, 260), true), 1010), "a synthesised press beside a touch must be ignored")
	check(pad.feed(_drag(0, Vector2(240, 260)), 1020), "the touch itself must still pan")
	check(view.project(grab).distance_to(Vector2(240, 260)) < 0.01, "the map must move once, not twice")
	pad.feed(_touch(0, Vector2(240, 260), false), 1040)
	check(view.centre != before, "the touch must have moved the camera")
	check(pad.feed(_button(MOUSE_BUTTON_LEFT, Vector2(700, 500), true), 2000), "the mouse must come back after the block window")
	pad.feed(_button(MOUSE_BUTTON_LEFT, Vector2(700, 500), false), 2040)
