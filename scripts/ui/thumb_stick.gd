extends Control
## One on-screen thumb stick: turns a thumb drag inside this corner pad into the
## same -1..1 vector a gamepad stick reports, so nothing downstream has to know
## the difference. The base jumps to wherever the thumb actually lands, because
## making a phone user hit a small fixed circle before they can move is why most
## touch flight controls get switched off.

signal vector_changed(vector: Vector2)

## How far the thumb travels for full deflection.
const TRAVEL := 96.0
const KNOB_RADIUS := 38.0
const DEAD_ZONE := 0.14
const MOUSE_POINTER := -2

const IDLE_RING := Color(0.62, 0.86, 0.94, 0.16)
const ACTIVE_RING := Color(0.62, 0.9, 1.0, 0.5)
const KNOB := Color(0.62, 0.9, 1.0, 0.34)

var caption := "STICK"
var vector := Vector2.ZERO
var _pointer_id := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _mouse_block_until := 0


func _ready() -> void:
	# The corner rectangle is a hit test in `_input`, not a GUI claim: nothing
	# here may swallow a tap, because a second finger in the same corner is a
	# tap-to-lock target.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_mode = Control.FOCUS_NONE


## Grabbed through `_input` rather than `_gui_input` so the stick keeps the
## finger after it slides off the corner, and consumes the event so the tap to
## lock a ground target in main.gd does not fire underneath a stick gesture.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var now := Time.get_ticks_msec()
	if event is InputEventScreenTouch:
		_mouse_block_until = now + 500
		if event.pressed:
			if _pointer_id < 0 and _owns(event.position):
				_begin(event.index, event.position)
				get_viewport().set_input_as_handled()
		elif event.index == _pointer_id:
			_end()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag:
		if event.index == _pointer_id:
			_mouse_block_until = now + 500
			_update(event.position)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if now < _mouse_block_until:
			return
		if event.pressed:
			if _pointer_id < 0 and event.button_index == MOUSE_BUTTON_LEFT and _owns(event.position):
				_begin(MOUSE_POINTER, event.position)
				get_viewport().set_input_as_handled()
		elif _pointer_id == MOUSE_POINTER:
			_end()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _pointer_id == MOUSE_POINTER:
		_update(event.position)
		get_viewport().set_input_as_handled()


func _owns(point: Vector2) -> bool:
	return get_global_rect().has_point(point)


func release() -> void:
	_end()


func _begin(pointer: int, point: Vector2) -> void:
	_pointer_id = pointer
	_origin = point
	_update(point)


func _end() -> void:
	_pointer_id = -1
	_update(_origin)


## Screen offsets map straight onto the pad's axes: right is +x and pushing the
## thumb up is -y, exactly like tilting a physical stick.
func _update(point: Vector2) -> void:
	var offset := point - _origin
	var magnitude := offset.length()
	if magnitude > TRAVEL:
		offset = offset * TRAVEL / magnitude
		magnitude = TRAVEL
	_knob = offset
	if magnitude <= DEAD_ZONE * TRAVEL:
		_set_vector(Vector2.ZERO)
		queue_redraw()
		return
	var travel := offset / TRAVEL
	var remapped := (travel.length() - DEAD_ZONE) / (1.0 - DEAD_ZONE)
	_set_vector(travel.normalized() * clampf(remapped, 0.0, 1.0))
	queue_redraw()


func _set_vector(value: Vector2) -> void:
	if value == vector:
		return
	vector = value
	vector_changed.emit(vector)


func _draw() -> void:
	var idle := _pointer_id < 0
	var base := _origin - global_position if not idle else size * 0.5
	var ring := ACTIVE_RING if not idle else IDLE_RING
	draw_arc(base, TRAVEL, 0.0, TAU, 48, ring, 3.0, true)
	draw_line(base - Vector2(14, 0), base + Vector2(14, 0), ring, 2.0)
	draw_line(base + Vector2(0, -14), base + Vector2(0, 14), ring, 2.0)
	draw_circle(base + _knob, KNOB_RADIUS, KNOB)
	draw_string(
		get_theme_default_font(),
		base + Vector2(-size.x * 0.5, TRAVEL + 34.0),
		caption,
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x,
		20,
		ring
	)
