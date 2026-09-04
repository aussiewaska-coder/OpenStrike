extends Control

## Flying without a gamepad.
##
## Two thumbs, and neither the flight model nor the camera is told about either.
## The left half of the screen is a stick: put a thumb down anywhere and the
## stick's centre is planted there, so there is no fixed pad to find by feel.
## The right half is the view: drag to swing the external camera the whole way
## round, which is also the only way to see that the visor's symbology is welded
## to the world rather than to the glass.
##
## Both halves write into GamepadInput's virtual vectors, in exactly the units
## and signs a real thumbstick produces. Screen y is down, the gamepad's LEFT_Y
## is down-positive, and `pitch_input = stick.y` raises the nose -- so a
## downward drag is stick-back is nose-up, with no sign flips anywhere.
##
## A quick tap on the right half is not a drag: it falls through as the target
## lock, so pressing a jet still locks it.
##
## Drawn, not themed, like the rest of this HUD.

signal view_pressed
signal tap_to_lock(position: Vector2)

const STICK_RADIUS_PX := 92.0
const KNOB_RADIUS_PX := 26.0
## How far a look-drag must travel to command full deflection.
const LOOK_RADIUS_PX := 140.0
## Under this much movement a press is a tap, not a drag.
const TAP_SLOP_PX := 18.0
## Where the stick region ends. Leaves the larger half for looking, because
## looking is the thing you do continuously.
const LEFT_FRACTION := 0.42
const GREEN := Color(0.45, 1.0, 0.6)

var _left_index := -1
var _left_origin := Vector2.ZERO
var _left_point := Vector2.ZERO
var _right_index := -1
var _right_origin := Vector2.ZERO
var _right_point := Vector2.ZERO
var _right_travel := 0.0

var _view_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_view_button = Button.new()
	_view_button.text = "VIEW"
	_view_button.focus_mode = Control.FOCUS_NONE
	_view_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_view_button.position = Vector2(24.0, -64.0)
	_view_button.custom_minimum_size = Vector2(96.0, 44.0)
	_view_button.pressed.connect(func() -> void: view_pressed.emit())
	add_child(_view_button)
	set_process(true)


## The stick's deflection, in thumbstick units. Clamped to the ring so a thumb
## dragged off the edge of the phone is full deflection, not more.
static func stick_vector(centre: Vector2, point: Vector2, radius: float) -> Vector2:
	var delta := (point - centre) / maxf(radius, 1.0)
	if delta.length() > 1.0:
		delta = delta.normalized()
	return delta


func _is_left(position: Vector2) -> bool:
	return position.x < size.x * LEFT_FRACTION


func _process(_delta: float) -> void:
	var gamepad := get_node_or_null("/root/GamepadInput")
	if gamepad == null:
		return
	# A real pad always wins, and takes the on-screen stick off the glass.
	var real: bool = gamepad.has_real_controller()
	if visible == real:
		visible = not real
		gamepad.set_touch_mode(not real)
		if real:
			_release_all(gamepad)
	if not visible:
		return
	gamepad.virtual_flight = (
		stick_vector(_left_origin, _left_point, STICK_RADIUS_PX) if _left_index != -1
		else Vector2.ZERO
	)
	gamepad.virtual_aim = (
		stick_vector(_right_origin, _right_point, LOOK_RADIUS_PX) if _right_index != -1
		else Vector2.ZERO
	)


func _release_all(gamepad) -> void:
	_left_index = -1
	_right_index = -1
	gamepad.virtual_flight = Vector2.ZERO
	gamepad.virtual_aim = Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.index, touch.position)
		else:
			_release(touch.index, touch.position)
		accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_move(drag.index, drag.position)
		accept_event()
	# Mouse fallback so the same control can be driven on a desktop build.
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT:
			if click.pressed:
				_press(0, click.position)
			else:
				_release(0, click.position)
			accept_event()
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move(0, (event as InputEventMouseMotion).position)
			accept_event()


func _press(index: int, position: Vector2) -> void:
	if _is_left(position):
		if _left_index != -1:
			return
		_left_index = index
		_left_origin = position
		_left_point = position
	else:
		if _right_index != -1:
			return
		_right_index = index
		_right_origin = position
		_right_point = position
		_right_travel = 0.0
	queue_redraw()


func _move(index: int, position: Vector2) -> void:
	if index == _left_index:
		_left_point = position
	elif index == _right_index:
		_right_travel += _right_point.distance_to(position)
		_right_point = position
	queue_redraw()


func _release(index: int, position: Vector2) -> void:
	if index == _left_index:
		_left_index = -1
	elif index == _right_index:
		_right_index = -1
		# A press that never really moved was a tap, and a tap is a lock.
		if _right_travel <= TAP_SLOP_PX:
			tap_to_lock.emit(position)
	queue_redraw()


func _draw() -> void:
	var idle := Color(GREEN, 0.22)
	if _left_index == -1:
		# A hint where the thumb belongs, so the stick is findable cold.
		var hint := Vector2(size.x * 0.16, size.y * 0.72)
		draw_arc(hint, STICK_RADIUS_PX * 0.55, 0.0, TAU, 32, idle, 1.5)
		draw_arc(hint, KNOB_RADIUS_PX * 0.5, 0.0, TAU, 20, idle, 1.5)
	else:
		draw_arc(_left_origin, STICK_RADIUS_PX, 0.0, TAU, 40, Color(GREEN, 0.45), 2.0)
		var knob := _left_origin + stick_vector(_left_origin, _left_point, STICK_RADIUS_PX) * STICK_RADIUS_PX
		draw_arc(knob, KNOB_RADIUS_PX, 0.0, TAU, 24, Color(GREEN, 0.8), 2.5)
		draw_line(_left_origin, knob, Color(GREEN, 0.35), 1.5)
	if _right_index != -1 and _right_travel > TAP_SLOP_PX:
		# Only while actually looking: a line from where the drag began, so the
		# swing has a visible origin.
		draw_line(_right_origin, _right_point, Color(GREEN, 0.35), 1.5)
		draw_arc(_right_origin, 14.0, 0.0, TAU, 20, Color(GREEN, 0.4), 1.5)
