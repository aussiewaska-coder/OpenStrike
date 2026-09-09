extends Control

## Weapon-camera projections must use its camera, not the aircraft's visor.
const MISSILE_COLOR := Color(0.55, 0.95, 1.0)
const LOCK_COLOR := Color(1.0, 0.25, 0.2)
const LOST_COLOR := Color(1.0, 0.73, 0.24)
var _camera: Camera3D
var _state := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

func set_state(camera: Camera3D, state: Dictionary) -> void:
	_camera = camera
	_state = state
	visible = not state.is_empty()
	queue_redraw()

func status_text() -> String:
	return "%s  •  %s" % [_state.get("weapon", "MISSILE"), _state.get("status", "NO SEEKER LOCK")]

func marker(point: Vector3) -> Dictionary:
	if not is_instance_valid(_camera):
		return {}
	var screen := _camera.unproject_position(point)
	var centre := size * 0.5
	var behind := _camera.is_position_behind(point)
	var bounds := Rect2(Vector2(36, 128), Vector2(maxf(size.x - 72, 1), maxf(size.y - 174, 1)))
	if not behind and bounds.has_point(screen):
		return {"position": screen, "edge": false}
	# Use camera-space direction behind the camera: unprojection reverses it.
	var local := _camera.global_transform.affine_inverse() * point
	var direction := Vector2(local.x, -local.y) if behind else screen - centre
	if direction.length_squared() < 0.001:
		direction = Vector2.DOWN
	direction = direction.normalized()
	var tx := (bounds.end.x - centre.x if direction.x >= 0 else bounds.position.x - centre.x) / direction.x if absf(direction.x) > 0.0001 else INF
	var ty := (bounds.end.y - centre.y if direction.y >= 0 else bounds.position.y - centre.y) / direction.y if absf(direction.y) > 0.0001 else INF
	return {"position": centre + direction * minf(tx, ty), "edge": true, "direction": direction}

func _draw() -> void:
	if _state.is_empty() or not is_instance_valid(_camera):
		return
	var font := ThemeDB.fallback_font
	var color := LOCK_COLOR if _state.get("locked", false) else LOST_COLOR
	if _state.get("status") == "IMPACT":
		color = MISSILE_COLOR
	var width := maxf(size.x - 340.0, 240.0)
	var panel := Rect2(24, 18, width, 76)
	draw_style_box(_panel_style(), panel)
	draw_rect(Rect2(panel.position, Vector2(3, panel.size.y)), color)
	draw_string(font, Vector2(38, 46), status_text(), HORIZONTAL_ALIGNMENT_LEFT, width - 28, 20, color)
	var range_text := "%.2f KM" % (float(_state.get("range_m", 0.0)) / 1000.0)
	draw_string(font, Vector2(38, 75), "%s  •  %s" % [_state.get("target_name", "NO TARGET"), range_text], HORIZONTAL_ALIGNMENT_LEFT, width - 28, 17, Color.WHITE)
	var projectile: Variant = _state.get("projectile_position")
	if projectile is Vector3:
		var m := marker(projectile)
		_draw_marker(m, MISSILE_COLOR, false)
	var target: Variant = _state.get("target_position")
	if target is Vector3:
		var m := marker(target)
		_draw_marker(m, color, true)
		var label_at: Vector2 = m.position + Vector2(20, 5)
		label_at.x = clampf(label_at.x, 16, size.x - 170)
		draw_string(font, label_at, range_text, HORIZONTAL_ALIGNMENT_LEFT, 155, 16, color)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.025, 0.035, 0.82)
	style.set_corner_radius_all(5)
	return style

func _draw_marker(m: Dictionary, color: Color, target: bool) -> void:
	if m.is_empty():
		return
	var at: Vector2 = m.position
	var points := PackedVector2Array()
	if m.edge:
		var direction: Vector2 = m.direction
		var side := direction.orthogonal()
		points = PackedVector2Array([at - direction * 13 + side * 9, at, at - direction * 13 - side * 9])
	elif target:
		points = PackedVector2Array([at + Vector2(0, -13), at + Vector2(13, 0), at + Vector2(0, 13), at + Vector2(-13, 0), at + Vector2(0, -13)])
	else:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var tip: Vector2 = at + corner * 24
			var bracket := PackedVector2Array([tip - Vector2(corner.x * 10, 0), tip, tip - Vector2(0, corner.y * 10)])
			draw_polyline(bracket, Color(0, 0, 0, 0.8), 4, true)
			draw_polyline(bracket, color, 2, true)
		return
	draw_polyline(points, Color(0, 0, 0, 0.8), 5, true)
	draw_polyline(points, color, 2, true)
