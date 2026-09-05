extends Control

signal contact_selected(handle: int)
signal waypoint_requested(position: Vector2)
signal range_changed(metres: float)
const MAP_SHADER := preload("res://shaders/tactical_map.gdshader")
const RADAR := preload("res://scripts/ui/radar_scope.gd")
const GREEN := Color(0.40, 0.91, 0.73)
const CYAN := Color(0.38, 0.92, 1.0)
var range_m := 10000.0
var centre := Vector2.ZERO
var follow_player := true
var add_waypoint := false
var map_style := 1
var player := Vector3.ZERO
var heading := 0.0
var contacts: Array = []
var locked := -1
var route: RefCounted
var layers := {}
var _height_source: Image
var _height_texture: ImageTexture
var _material: ShaderMaterial
var _sweep := 0.0
var _touches := {}
var _touch_start := Vector2.ZERO
var _gesture_moved := false
var _mouse_down := false
var _mouse_start := Vector2.ZERO
var _mouse_moved := false
var _mouse_block_until := 0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(100, 100)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.show_behind_parent = true
	_material = ShaderMaterial.new()
	_material.shader = MAP_SHADER
	backdrop.material = _material
	add_child(backdrop)
	resized.connect(_update_shader)
	_update_shader()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_sweep = fposmod(_sweep + delta * TAU / 3.5, TAU)
	queue_redraw()

func pixels_per_metre() -> float:
	return maxf(minf(size.x, size.y), 1.0) / (range_m * 2.0)

func world_to_screen(world: Vector2) -> Vector2:
	return size * 0.5 + (world - centre) * pixels_per_metre()

func screen_to_world(point: Vector2) -> Vector2:
	return centre + (point - size * 0.5) / pixels_per_metre()

func set_range(metres: float, anchor := Vector2(-1, -1)) -> void:
	var at := size * 0.5 if anchor.x < 0 else anchor
	var world := screen_to_world(at)
	range_m = clampf(metres, 500.0, 80000.0)
	centre += world - screen_to_world(at)
	_update_shader()
	range_changed.emit(range_m)
	queue_redraw()

func recenter() -> void:
	follow_player = true
	centre = Vector2(player.x, player.z)
	_update_shader()
	queue_redraw()

func set_state(position: Vector3, yaw: float, items: Array, lock_handle: int, navigation: RefCounted) -> void:
	player = position
	heading = yaw
	contacts = items
	locked = lock_handle
	route = navigation
	if follow_player:
		centre = Vector2(player.x, player.z)
	_update_shader()
	queue_redraw()

func set_layers(data: Dictionary) -> void:
	layers = data
	var source: Image = layers.get("height")
	if source != _height_source:
		_height_source = source
		_height_texture = ImageTexture.create_from_image(source) if source != null and not source.is_empty() else null
	_update_shader()
	queue_redraw()

func _update_shader() -> void:
	if _material == null:
		return
	var world_size := maxf(float(layers.get("world_size_m", 50000)), 1.0)
	_material.set_shader_parameter("centre_uv", centre / world_size + Vector2.ONE * 0.5)
	_material.set_shader_parameter("span_uv", size / pixels_per_metre() / world_size)
	_material.set_shader_parameter("map_style", map_style)
	_material.set_shader_parameter("has_aerial", layers.get("aerial") != null)
	_material.set_shader_parameter("aerial", layers.get("aerial"))
	_material.set_shader_parameter("has_elevation", _height_texture != null)
	_material.set_shader_parameter("elevation", _height_texture)
	var metadata: Dictionary = layers.get("metadata", {})
	_material.set_shader_parameter("elevation_min", float(metadata.get("elevation_min_m", 0.0)))
	_material.set_shader_parameter("elevation_max", float(metadata.get("elevation_max_m", 1000.0)))
	if _height_source != null:
		_material.set_shader_parameter("elevation_texel", Vector2.ONE / Vector2(_height_source.get_size()))

func contact_at(point: Vector2) -> int:
	var nearest := -1
	var distance := 24.0
	for contact in contacts:
		var world: Vector3 = contact.position
		var at := world_to_screen(Vector2(world.x, world.z))
		if not Rect2(Vector2.ZERO, size).has_point(at):
			continue
		var separation := at.distance_to(point)
		if separation < distance:
			distance = separation
			nearest = int(contact.handle)
	return nearest

func select_at(point: Vector2) -> void:
	if add_waypoint:
		waypoint_requested.emit(screen_to_world(point))
	else:
		var handle := contact_at(point)
		if handle >= 0:
			contact_selected.emit(handle)

func _pan(relative: Vector2) -> void:
	follow_player = false
	centre -= relative / pixels_per_metre()
	_update_shader()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_mouse_block_until = Time.get_ticks_msec() + 500
		if event.pressed:
			if _touches.is_empty():
				_touch_start = event.position
				_gesture_moved = false
			_touches[event.index] = event.position
			if _touches.size() > 1:
				_gesture_moved = true
		else:
			if _touches.has(event.index) and _touches.size() == 1 and not _gesture_moved and event.position.distance_to(_touch_start) < 10:
				select_at(event.position)
			_touches.erase(event.index)
		accept_event()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_mouse_block_until = Time.get_ticks_msec() + 500
		if _touches.size() >= 2:
			var before: Array = _touches.values()
			var previous_distance: float = before[0].distance_to(before[1])
			_touches[event.index] = event.position
			var after: Array = _touches.values()
			var distance: float = after[0].distance_to(after[1])
			if previous_distance > 10 and distance > 10:
				follow_player = false
				set_range(range_m * previous_distance / distance, (after[0] + after[1]) * 0.5)
		else:
			_touches[event.index] = event.position
			if event.position.distance_to(_touch_start) > 8:
				_gesture_moved = true
			if _gesture_moved:
				_pan(event.relative)
		accept_event()
	elif event is InputEventMouseButton and Time.get_ticks_msec() >= _mouse_block_until:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			follow_player = false
			set_range(range_m * (0.8 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.25), event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_down = true
				_mouse_start = event.position
				_mouse_moved = false
			else:
				if _mouse_down and not _mouse_moved:
					select_at(event.position)
				_mouse_down = false
		accept_event()
	elif event is InputEventMouseMotion and _mouse_down:
		if event.position.distance_to(_mouse_start) > 8:
			_mouse_moved = true
		if _mouse_moved:
			_pan(event.relative)
		accept_event()

func cancel_gesture() -> void:
	_touches.clear()
	_mouse_down = false
	_gesture_moved = true

func _text(at: Vector2, text: String, colour := GREEN, font_size := 13) -> void:
	draw_string_outline(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color(0.01, 0.035, 0.04, 0.9))
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)

func _draw() -> void:
	if _material == null:
		return
	if map_style == 0:
		for tile in layers.get("details", []):
			var bounds: Rect2 = tile.bounds
			var rect := Rect2(world_to_screen(bounds.position), bounds.size * pixels_per_metre())
			if rect.intersects(Rect2(Vector2.ZERO, size)):
				draw_texture_rect(tile.texture, rect, false, Color(0.72, 0.88, 0.81))
	var origin := world_to_screen(Vector2(player.x, player.z))
	var step := pow(10.0, floor(log(range_m) / log(10.0)))
	var corner := screen_to_world(Vector2.ZERO)
	var end := screen_to_world(size)
	for x in range(int(floor(corner.x / step)), int(ceil(end.x / step)) + 1):
		var at := world_to_screen(Vector2(x * step, 0)).x
		draw_line(Vector2(at, 0), Vector2(at, size.y), Color(GREEN, 0.10), 1)
	for z in range(int(floor(corner.y / step)), int(ceil(end.y / step)) + 1):
		var at := world_to_screen(Vector2(0, z * step)).y
		draw_line(Vector2(0, at), Vector2(size.x, at), Color(GREEN, 0.10), 1)
	for fraction in [0.5, 1.0]:
		draw_arc(origin, range_m * pixels_per_metre() * fraction, 0, TAU, 96, Color(GREEN, 0.24), 1, true)
	for index in range(12):
		var angle := _sweep - float(index) * 0.025
		draw_line(origin, origin + Vector2(sin(angle), -cos(angle)) * range_m * pixels_per_metre(), Color(GREEN, 0.23 * (1.0 - float(index) / 12.0)), 2, true)
	if route != null:
		var previous := origin
		for index in range(route.points.size()):
			var point: Vector3 = route.points[index]
			var at := world_to_screen(Vector2(point.x, point.z))
			draw_dashed_line(previous, at, Color(CYAN, 0.75), 1.5, 7)
			draw_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)), CYAN, false, 2)
			_text(at + Vector2(10, -10), "WP %02d" % [route.completed + index + 1], CYAN)
			previous = at
	for contact in contacts:
		var world: Vector3 = contact.position
		var at := world_to_screen(Vector2(world.x, world.z))
		if not Rect2(Vector2.ZERO, size).grow(20).has_point(at):
			continue
		var offset := Vector2(world.x - player.x, world.z - player.z)
		var bearing := atan2(offset.x, -offset.y)
		var glow := 1.0 - clampf(fposmod(_sweep - bearing, TAU) / 1.2, 0, 1)
		var colour := RADAR.colour_for_kind(int(contact.kind))
		colour.a = 0.82 + glow * 0.18
		draw_circle(at, 7, Color(0.015, 0.025, 0.03, 0.85))
		draw_circle(at, 4.5, colour)
		if glow > 0:
			draw_arc(at, 7 + (1.0 - glow) * 7, 0, TAU, 24, Color(colour, glow * 0.5), 1, true)
		if int(contact.handle) == locked:
			draw_rect(Rect2(at - Vector2(11, 11), Vector2(22, 22)), Color(1, 0.78, 0.32), false, 2)
		var label := String(contact.get("name", "CONTACT"))
		var width := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(at + Vector2(8, -10), Vector2(width + 5, 19)), Color(0.015, 0.025, 0.03, 0.78))
		_text(at + Vector2(10, 5), label, colour.lerp(Color.WHITE, 0.60), 12)
	var nose := Vector2(sin(heading), -cos(heading))
	var side := Vector2(-nose.y, nose.x)
	draw_colored_polygon(PackedVector2Array([origin + nose * 12, origin - nose * 8 + side * 7, origin - nose * 4, origin - nose * 8 - side * 7]), CYAN)
	_text(origin + Vector2(13, 20), "OWN", CYAN, 12)
	_text(Vector2(12, 23), "N ↑  /  NORTH UP", GREEN)
	_text(Vector2(12, size.y - 14), "RANGE %.1f km   GRID %.0f m" % [range_m / 1000, step], GREEN, 12)
	if map_style == 0 and layers.get("aerial") == null:
		_text(Vector2(12, 44), "AERIAL NOT LOADED · TACTICAL GRID", Color(1, 0.78, 0.32), 12)
	elif map_style != 0 and _height_texture == null:
		_text(Vector2(12, 44), "ELEVATION NOT LOADED · TACTICAL GRID", Color(1, 0.78, 0.32), 12)
	for y in range(0, int(size.y), 4):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0.02, 0.02, 0.065), 1)
	draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), Color(GREEN, 0.35), false, 2)
