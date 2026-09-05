extends Control

## A strip along the bottom of the cockpit view marked in degrees of relative
## bearing, centred on the nose. Each drone is a tick at its bearing; the
## closest carries its range. Outside the tape a contact clamps to the end with
## an arrow, so "turn hard left" is still readable.
##
## Cockpit only. The external views have the scope alone; a chase camera does
## not earn a HUD tape.

const TAPE_HALF_WIDTH_DEGREES := 60.0
const TAPE_HEIGHT_PX := 26.0
const BOTTOM_MARGIN_PX := 18.0
## Stops short of the scope in the bottom-right corner so the two never overlap.
const RIGHT_RESERVE_PX := 260.0
const LEFT_MARGIN_PX := 24.0
const COLOUR := Color(0.45, 1.0, 0.6, 0.85)

var _contacts: Array = []
var _player_position := Vector3.ZERO
var _heading := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func relative_bearing(world_offset: Vector3, heading: float) -> float:
	var absolute := atan2(world_offset.x, -world_offset.z)
	return wrapf(absolute - heading, -PI, PI)


static func tick_x(relative_bearing_radians: float, half_width_degrees: float, half_width_px: float) -> float:
	var fraction := rad_to_deg(relative_bearing_radians) / maxf(half_width_degrees, 0.001)
	return clampf(fraction, -1.0, 1.0) * half_width_px


static func is_clamped(relative_bearing_radians: float, half_width_degrees: float) -> bool:
	return absf(rad_to_deg(relative_bearing_radians)) > half_width_degrees


func set_contacts(player_position: Vector3, heading: float, drones: Array) -> void:
	_player_position = player_position
	_heading = heading
	_contacts = drones
	queue_redraw()


func _draw() -> void:
	var left := LEFT_MARGIN_PX
	var right := size.x - RIGHT_RESERVE_PX
	if right <= left + 40.0:
		return
	var centre_x := (left + right) * 0.5
	var half_px := (right - left) * 0.5
	var y := size.y - BOTTOM_MARGIN_PX - TAPE_HEIGHT_PX * 0.5
	draw_line(Vector2(left, y), Vector2(right, y), COLOUR * Color(1.0, 1.0, 1.0, 0.5), 1.0)
	# Graduations every 15 degrees, the nose marked.
	var step := 15.0
	var mark := -TAPE_HALF_WIDTH_DEGREES
	while mark <= TAPE_HALF_WIDTH_DEGREES + 0.001:
		var x := centre_x + tick_x(deg_to_rad(mark), TAPE_HALF_WIDTH_DEGREES, half_px)
		var tall := is_zero_approx(mark)
		draw_line(Vector2(x, y - (8.0 if tall else 4.0)), Vector2(x, y + (8.0 if tall else 4.0)), COLOUR, 1.5 if tall else 1.0)
		mark += step
	var closest = null
	var closest_range := INF
	for drone in _contacts:
		var offset: Vector3 = drone.position - _player_position
		var bearing := relative_bearing(offset, _heading)
		var x := centre_x + tick_x(bearing, TAPE_HALF_WIDTH_DEGREES, half_px)
		if is_clamped(bearing, TAPE_HALF_WIDTH_DEGREES):
			var direction := signf(bearing)
			draw_polyline(PackedVector2Array([
				Vector2(x - direction * 8.0, y - 6.0), Vector2(x, y), Vector2(x - direction * 8.0, y + 6.0)
			]), COLOUR, 1.5)
		else:
			draw_polyline(PackedVector2Array([
				Vector2(x - 5.0, y - 9.0), Vector2(x, y - 2.0), Vector2(x + 5.0, y - 9.0)
			]), COLOUR, 1.5)
		var range_m := offset.length()
		if range_m < closest_range:
			closest_range = range_m
			closest = Vector2(x, y)
	if closest != null:
		draw_string(
			get_theme_default_font(), (closest as Vector2) + Vector2(-16.0, -14.0),
			"%dM" % int(closest_range), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOUR
		)
