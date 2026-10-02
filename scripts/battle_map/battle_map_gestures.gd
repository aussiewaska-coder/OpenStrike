extends RefCounted

## Turns raw pointer events into battle map camera moves: one finger drags the
## ground, a pinch zooms, two fingers together lean and swing the map, and a
## double tap flies the camera onto what was under it. Mouse equivalents do the
## same for desktop and for the headless checks.
##
## It only ever *asks* the view to move. It selects nothing and draws nothing:
## taps are reported out for whoever owns contacts and waypoints.

signal tapped(point: Vector2)
signal double_tapped(point: Vector2)

const TAP_SECONDS := 0.45
const TAP_SLOP_PIXELS := 12.0
const DOUBLE_TAP_SECONDS := 0.40
const DOUBLE_TAP_SLOP_PIXELS := 64.0
const DRAG_START_PIXELS := 8.0
## Radians of map per pixel of finger travel. Held gestures move the map under
## the finger, so these only ever apply to leaning and swinging.
const LEAN_PER_PIXEL := 0.0055
const SWING_PER_PIXEL := 0.005
## Recent gesture rate is kept as a rad/s estimate so a flick releases into a
## glide; multiplied by this to land on a sensible spin-down speed.
const FLING_RATE := 30.0
const WHEEL_IN := 0.8
const WHEEL_OUT := 1.25
## Android synthesises mouse events alongside its own touches. Without this the
## same press pans the map twice over, once per event stream.
const MOUSE_BLOCK_MILLISECONDS := 500

var view: RefCounted
var engaged := false
var _touches := {}
var _anchors := {}
var _press_point := Vector2.ZERO
var _press_seconds := 0.0
var _moved := false
var _spread := 0.0
var _twist := 0.0
var _pinch_point := Vector2.ZERO
var _pinch_world := Vector2.ZERO
var _lean_point := Vector2.ZERO
var _velocity := Vector2.ZERO
var _swing := 0.0
var _lean := 0.0
var _previous_tap := Vector2.INF
var _previous_tap_seconds := -10.0
var _sample_point := Vector2.ZERO
var _sample_seconds := 0.0
var _mouse_button := &""
var _mouse_point := Vector2.ZERO
var _mouse_world := Vector2.ZERO
var _mouse_moved := false
var _mouse_double := false
var _block_mouse_until := 0


func setup(target: RefCounted) -> void:
	view = target


## Returns true when the event belonged to the map and must not fall through.
func feed(event: InputEvent, now_milliseconds := 0) -> bool:
	var now := float(now_milliseconds) * 0.001
	if event is InputEventScreenTouch:
		return _touch(event, now)
	if event is InputEventScreenDrag:
		return _drag(event, now)
	if event is InputEventMouseButton and now_milliseconds >= _block_mouse_until:
		return _mouse_button_event(event, now)
	if event is InputEventMouseMotion and now_milliseconds >= _block_mouse_until:
		return _mouse_motion(event, now)
	return false


func cancel() -> void:
	_touches.clear()
	_anchors.clear()
	_mouse_button = &""
	_mouse_double = false
	_moved = true
	engaged = false
	_velocity = Vector2.ZERO


func _touch(event: InputEventScreenTouch, now: float) -> bool:
	_block_mouse_until = int(now * 1000.0) + MOUSE_BLOCK_MILLISECONDS
	engaged = true
	if event.pressed:
		if _touches.is_empty():
			_press_point = event.position
			_press_seconds = now
			_moved = false
			_start_sampling(event.position, now)
		_touches[event.index] = event.position
		_anchors[event.index] = view.unproject(event.position)
		if _touches.size() == 2:
			_begin_pinch()
		return true
	if not _touches.has(event.index):
		return true
	var was_alone := _touches.size() == 1
	var travelled := event.position.distance_to(_press_point)
	_touches.erase(event.index)
	_anchors.erase(event.index)
	if was_alone and not _moved and travelled < TAP_SLOP_PIXELS and now - _press_seconds < TAP_SECONDS:
		_report_tap(event.position, now)
	if _touches.size() == 1:
		# A finger lifted out of a pinch: the survivor picks up dragging from
		# exactly where it is, so the map does not jump under it.
		var remaining: int = _touches.keys()[0]
		_press_point = _touches[remaining]
		_anchors[remaining] = view.unproject(_press_point)
		_moved = true
	if _touches.is_empty():
		engaged = false
		if _moved:
			view.fling(_velocity, _swing, _lean)
		_velocity = Vector2.ZERO
		_swing = 0.0
		_lean = 0.0
	return true


func _drag(event: InputEventScreenDrag, now: float) -> bool:
	if not _touches.has(event.index):
		return false
	_block_mouse_until = int(now * 1000.0) + MOUSE_BLOCK_MILLISECONDS
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		_pinch()
		_moved = true
		return true
	if event.position.distance_to(_press_point) > DRAG_START_PIXELS:
		_moved = true
	if not _moved:
		return true
	view.drag(_anchors[event.index], event.position)
	_track_velocity(event.position, now)
	return true


func _begin_pinch() -> void:
	var points: Array = _touches.values()
	_spread = points[0].distance_to(points[1])
	_twist = (points[1] - points[0]).angle()
	_pinch_point = (points[0] + points[1]) * 0.5
	_pinch_world = view.unproject(_pinch_point)
	_lean_point = _pinch_point
	_velocity = Vector2.ZERO
	_swing = 0.0
	_lean = 0.0


## Zoom from the finger separation, swing from the angle between them, lean from
## how far the pair travelled down the screen. The grabbed ground is re-pinned
## after each one, so the three never accumulate into a drift.
func _pinch() -> void:
	var points: Array = _touches.values()
	var distance: float = points[0].distance_to(points[1])
	var angle: float = (points[1] - points[0]).angle()
	var middle: Vector2 = (points[0] + points[1]) * 0.5
	if _spread > 10.0 and distance > 10.0:
		view.set_range(view.range_m * _spread / distance, _pinch_point)
	var twist := _shortest_angle(_twist, angle)
	if absf(twist) > 0.0001:
		view.rotate_by(-twist)
		_swing = lerpf(_swing, -twist * FLING_RATE, 0.4)
	# Against the previous sample, not the press: a held pair must not keep
	# tilting harder every frame. `_pinch_point` stays put as the anchor, which
	# is why sliding the fingers vertically tilts instead of also panning.
	var travelled: float = middle.y - _lean_point.y
	if absf(travelled) > 0.5:
		view.tilt_by(-travelled * LEAN_PER_PIXEL)
		_lean = lerpf(_lean, -travelled * LEAN_PER_PIXEL * FLING_RATE, 0.4)
	view.pin_world(_pinch_world, _pinch_point)
	_spread = distance
	_twist = angle
	_lean_point = middle


func _report_tap(point: Vector2, now: float) -> void:
	if now - _previous_tap_seconds < DOUBLE_TAP_SECONDS and point.distance_to(_previous_tap) < DOUBLE_TAP_SLOP_PIXELS:
		_previous_tap = Vector2.INF
		double_tapped.emit(point)
		return
	_previous_tap = point
	_previous_tap_seconds = now
	tapped.emit(point)


func _start_sampling(point: Vector2, now: float) -> void:
	_velocity = Vector2.ZERO
	_sample_point = point
	_sample_seconds = now


## A low-pass on the last few drags, which is what a fling is thrown with.
## Measuring between samples rather than since the press keeps a long pause
## before release from killing the throw.
func _track_velocity(point: Vector2, now: float) -> void:
	var elapsed := now - _sample_seconds
	if elapsed > 0.001:
		_velocity = _velocity.lerp((point - _sample_point) / elapsed, 0.4)
	_sample_point = point
	_sample_seconds = now


func _mouse_button_event(event: InputEventMouseButton, now: float) -> bool:
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		view.set_range(view.range_m * (WHEEL_IN if event.button_index == MOUSE_BUTTON_WHEEL_UP else WHEEL_OUT), event.position)
		return true
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if _mouse_button != &"pan":
				_mouse_button = &"look"
		elif _mouse_button == &"look":
			_mouse_button = &""
		return true
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if event.pressed:
		_mouse_button = &"pan"
		_mouse_point = event.position
		_mouse_world = view.unproject(event.position)
		_mouse_moved = false
		_mouse_double = event.double_click
		engaged = true
		_start_sampling(event.position, now)
		if event.double_click:
			_previous_tap = Vector2.INF
			double_tapped.emit(event.position)
		return true
	var was_pan := _mouse_button == &"pan"
	var was_double := _mouse_double
	_mouse_button = &""
	_mouse_double = false
	engaged = false
	# The second press of a double click must not also select on its release, or
	# flying the camera onto a contact would drop a waypoint under it as well.
	if was_pan and not _mouse_moved and not was_double:
		_report_tap(event.position, now)
	elif was_pan:
		view.fling(_velocity, 0.0, 0.0)
	_velocity = Vector2.ZERO
	return true


func _mouse_motion(event: InputEventMouseMotion, now: float) -> bool:
	if _mouse_button == &"pan":
		if event.position.distance_to(_mouse_point) > DRAG_START_PIXELS:
			_mouse_moved = true
		if not _mouse_moved:
			return true
		view.drag(_mouse_world, event.position)
		_track_velocity(event.position, now)
		return true
	if _mouse_button == &"look":
		view.tilt_by(-event.relative.y * LEAN_PER_PIXEL)
		view.rotate_by(-event.relative.x * SWING_PER_PIXEL)
		return true
	return false


static func _shortest_angle(from: float, to: float) -> float:
	return fposmod(to - from + PI, TAU) - PI
