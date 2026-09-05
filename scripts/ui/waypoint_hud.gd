extends Control
const CYAN := Color(0.38, 0.92, 1.0)
const NAV := preload("res://scripts/ui/tactical_navigation.gd")
var camera: Camera3D
var position_world := Vector3.ZERO
var route: RefCounted

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func set_state(view: Camera3D, position: Vector3, navigation: RefCounted) -> void:
	camera = view
	position_world = position
	route = navigation
	queue_redraw()

static func edge_position(local: Vector3, viewport_size: Vector2) -> Vector2:
	var direction := Vector2(local.x, -local.y)
	if direction.length_squared() < 0.001:
		direction = Vector2.DOWN
	direction = direction.normalized()
	# Leave the lower centre free for the persistent range/bearing readout.
	var half := (viewport_size * 0.5 - Vector2(48, 60 if direction.y < 0 else 105)).max(Vector2(20, 20))
	var distance := minf(half.x / maxf(absf(direction.x), 0.0001), half.y / maxf(absf(direction.y), 0.0001))
	return viewport_size * 0.5 + direction * distance

func _draw() -> void:
	if camera == null or route == null or route.points.is_empty():
		return
	var waypoint: Vector3 = route.points[0]
	var local: Vector3 = camera.global_basis.inverse() * (waypoint - camera.global_position)
	var at := camera.unproject_position(waypoint) if local.z < -0.01 else Vector2(-1000, -1000)
	var inside := Rect2(Vector2(48, 60), (size - Vector2(96, 165)).max(Vector2.ONE)).has_point(at)
	if not inside:
		at = edge_position(local, size)
		var outward := (at - size * 0.5).normalized()
		var side := Vector2(-outward.y, outward.x)
		draw_polyline(PackedVector2Array([at - outward * 12 + side * 8, at, at - outward * 12 - side * 8]), CYAN, 2, true)
	else:
		draw_rect(Rect2(at - Vector2(8, 8), Vector2(16, 16)), CYAN, false, 2)
	var distance := Vector2(waypoint.x - position_world.x, waypoint.z - position_world.z).length()
	var label := "WP %02d  ·  %.1f km  ·  %03d°" % [route.completed + 1, distance / 1000, roundi(NAV.bearing(position_world, waypoint)) % 360]
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var baseline := Vector2((size.x - width) * 0.5, size.y - 48)
	draw_style_box(_backing(), Rect2(baseline + Vector2(-10, -23), Vector2(width + 20, 32)))
	draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, CYAN)
	draw_string_outline(font, at + Vector2(13, -10), "WP %02d" % [route.completed + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 2, Color(0.01, 0.05, 0.07, 0.85))
	draw_string(font, at + Vector2(13, -10), "WP %02d" % [route.completed + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CYAN)

func _backing() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.015, 0.06, 0.075, 0.78)
	box.set_corner_radius_all(4)
	return box
