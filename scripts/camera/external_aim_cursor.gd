class_name ExternalAimCursor
extends RefCounted

var cursor_edge := Vector2(0.58, 0.48)
var input_speed := 2.4
var catchup_response := 5.2
var return_response := 6.0
var maximum_yaw_radians := deg_to_rad(85.0)
var maximum_pitch_radians := deg_to_rad(55.0)

var cursor_offset := Vector2.ZERO
var camera_offset := Vector2.ZERO
var _vertical_fov_degrees := 60.0
var _aspect_ratio := 16.0 / 9.0
var _camera_engaged := false


func set_projection(vertical_fov_degrees: float, aspect_ratio: float) -> void:
	var old_cursor_angle := _cursor_angles(cursor_offset)
	_vertical_fov_degrees = vertical_fov_degrees
	_aspect_ratio = maxf(aspect_ratio, 0.001)
	# Zooming changes how many degrees the same pixel offset represents. Move the
	# difference into camera angle so zoom cannot drag the world target.
	camera_offset += old_cursor_angle - _cursor_angles(cursor_offset)
	_clamp_combined()


func update(input: Vector2, held: bool, delta: float) -> void:
	if not held:
		var return_weight := 1.0 - exp(-return_response * maxf(delta, 0.0))
		cursor_offset = cursor_offset.lerp(Vector2.ZERO, return_weight)
		camera_offset = camera_offset.lerp(Vector2.ZERO, return_weight)
		if cursor_offset.length_squared() < 0.000001 and camera_offset.length_squared() < 0.000001:
			_camera_engaged = false
		return
	if input.length_squared() > 0.0004:
		_move_cursor(-input * input_speed * maxf(delta, 0.0))
		return
	if not _camera_engaged:
		return
	# Transfer cursor angle into camera angle after the stick stops. Their sum
	# remains fixed, so the world target holds while the sight recentres.
	var transfer_weight := 1.0 - exp(-catchup_response * maxf(delta, 0.0))
	var next_cursor := cursor_offset.lerp(Vector2.ZERO, transfer_weight)
	camera_offset += _cursor_angles(cursor_offset) - _cursor_angles(next_cursor)
	cursor_offset = next_cursor
	_clamp_combined()


func combined_offset() -> Vector2:
	return camera_offset + _cursor_angles(cursor_offset)


func camera_basis() -> Basis:
	return Basis(Vector3.UP, camera_offset.x) * Basis(Vector3.RIGHT, -camera_offset.y)


func screen_position(viewport_size: Vector2) -> Vector2:
	return viewport_size * 0.5 + Vector2(
		cursor_offset.x * viewport_size.x * 0.5,
		cursor_offset.y * viewport_size.y * 0.5
	)


static func ray_direction(
	camera_basis: Basis,
	vertical_fov_degrees: float,
	aspect_ratio: float,
	screen_offset: Vector2
) -> Vector3:
	var half_height := tan(deg_to_rad(vertical_fov_degrees) * 0.5)
	var local := Vector3(
		screen_offset.x * half_height * maxf(aspect_ratio, 0.001),
		-screen_offset.y * half_height,
		-1.0
	).normalized()
	return (camera_basis * local).normalized()


func _move_cursor(delta_offset: Vector2) -> void:
	var desired_cursor := cursor_offset + delta_offset
	desired_cursor.x = clampf(desired_cursor.x, -1.0, 1.0)
	desired_cursor.y = clampf(desired_cursor.y, -1.0, 1.0)
	var clamped_cursor := Vector2(
		clampf(desired_cursor.x, -cursor_edge.x, cursor_edge.x),
		clampf(desired_cursor.y, -cursor_edge.y, cursor_edge.y)
	)
	if not desired_cursor.is_equal_approx(clamped_cursor):
		_camera_engaged = true
	camera_offset += _cursor_angles(desired_cursor) - _cursor_angles(clamped_cursor)
	cursor_offset = clamped_cursor
	_clamp_combined()


func _cursor_angles(offset: Vector2) -> Vector2:
	var half_height := tan(deg_to_rad(_vertical_fov_degrees) * 0.5)
	return Vector2(
		atan(offset.x * half_height * _aspect_ratio),
		atan(offset.y * half_height)
	)


func _clamp_camera() -> void:
	camera_offset.x = clampf(camera_offset.x, -maximum_yaw_radians, maximum_yaw_radians)
	camera_offset.y = clampf(camera_offset.y, -maximum_pitch_radians, maximum_pitch_radians)


func _clamp_combined() -> void:
	var cursor_angles := _cursor_angles(cursor_offset)
	var total := camera_offset + cursor_angles
	camera_offset.x += clampf(total.x, -maximum_yaw_radians, maximum_yaw_radians) - total.x
	camera_offset.y += clampf(total.y, -maximum_pitch_radians, maximum_pitch_radians) - total.y
	_clamp_camera()
