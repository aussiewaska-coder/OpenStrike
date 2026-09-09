extends "res://scripts/ui/radar_scope.gd"

## A heading-up moving map behind the same live contacts as the HUD scope.
## Draw the phosphor halo into the display itself: mobile Compatibility does
## not need full-screen bloom to keep the instrument luminous at night.
const MAP_SHADER = preload("res://shaders/tactical_map.gdshader")
const PHOSPHOR := Color(0.3, 1.0, 0.66)
var display_range := 10000.0
var _map_material: ShaderMaterial
var _height_source: Image
var _height_texture: ImageTexture
var _world_size := 50000.0

func _ready() -> void:
	super._ready()
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(256, 208)
	scale = Vector2(2, 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := ColorRect.new()
	backdrop.size = size
	backdrop.show_behind_parent = true
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_material = ShaderMaterial.new()
	_map_material.shader = MAP_SHADER
	backdrop.material = _map_material
	add_child(backdrop)
	_update_map()

func range_m() -> float:
	return display_range

func scope_centre() -> Vector2:
	return size * 0.5

func set_contacts(position: Vector3, heading: float, contacts: Array, locked: int) -> void:
	super.set_contacts(position, heading, contacts, locked)
	_update_map()

func set_layers(layers: Dictionary) -> void:
	_world_size = maxf(float(layers.get("world_size_m", 50000.0)), 1.0)
	var source: Image = layers.get("height")
	if source != _height_source:
		_height_source = source
		_height_texture = ImageTexture.create_from_image(source) if source != null and not source.is_empty() else null
	_map_material.set_shader_parameter("elevation", _height_texture)
	_map_material.set_shader_parameter("has_elevation", _height_texture != null)
	var metadata: Dictionary = layers.get("metadata", {})
	_map_material.set_shader_parameter("elevation_min", float(metadata.get("elevation_min_m", 0.0)))
	_map_material.set_shader_parameter("elevation_max", float(metadata.get("elevation_max_m", 1000.0)))
	if _height_source != null:
		_map_material.set_shader_parameter("elevation_texel", Vector2.ONE / Vector2(_height_source.get_size()))
	_update_map()

func _update_map() -> void:
	if _map_material == null:
		return
	_map_material.set_shader_parameter("centre_uv", Vector2(_player_position.x, _player_position.z) / _world_size + Vector2.ONE * 0.5)
	_map_material.set_shader_parameter("span_uv", size * display_range / SCOPE_RADIUS_PX / _world_size)
	_map_material.set_shader_parameter("map_heading", _heading)

func _glow_line(a: Vector2, b: Vector2, colour: Color, width := 1.0) -> void:
	draw_line(a, b, Color(colour, 0.06), width + 5.0, true)
	draw_line(a, b, Color(colour, 0.16), width + 2.5, true)
	draw_line(a, b, colour, width, true)

func _draw() -> void:
	var centre := scope_centre()
	for fraction in [0.5, 1.0]:
		var radius: float = SCOPE_RADIUS_PX * fraction
		draw_arc(centre, radius, 0, TAU, 80, Color(PHOSPHOR, 0.08), 5, true)
		draw_arc(centre, radius, 0, TAU, 80, Color(PHOSPHOR, 0.6), 0.8, true)
	for angle in range(0, 360, 30):
		var direction := Vector2(sin(deg_to_rad(angle) - _heading), -cos(deg_to_rad(angle) - _heading))
		_glow_line(centre + direction * 84, centre + direction * 90, Color(PHOSPHOR, 0.7))
	var north := centre + Vector2.UP.rotated(-_heading) * 78
	draw_string(ThemeDB.fallback_font, north + Vector2(-3, 3), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, PHOSPHOR)
	_draw_sweep(centre)
	var sweep_direction := Vector2(sin(_sweep * TAU), -cos(_sweep * TAU))
	_glow_line(centre, centre + sweep_direction * 89, Color(PHOSPHOR, 0.8))
	for c in _contacts:
		var offset: Vector3 = c.position - _player_position
		var at := centre + blip_offset(offset, _heading, range_m(), SCOPE_RADIUS_PX)
		var colour := colour_for_kind(int(c.kind))
		draw_circle(at, 7, Color(colour, 0.09))
		draw_circle(at, 5, Color(colour, 0.18))
	_draw_contacts(centre)
	# Ownship remains nose-up even while the map and north marker rotate.
	_glow_line(centre + Vector2(-7, 5), centre + Vector2(0, -7), PHOSPHOR, 1.5)
	_glow_line(centre + Vector2(0, -7), centre + Vector2(7, 5), PHOSPHOR, 1.5)
	_glow_line(centre + Vector2(0, -2), centre + Vector2(0, 8), PHOSPHOR)
	draw_rect(Rect2(0, 0, size.x, 14), Color(0.005, 0.018, 0.013))
	draw_rect(Rect2(0, size.y - 14, size.x, 14), Color(0.005, 0.018, 0.013))
	draw_string(ThemeDB.fallback_font, Vector2(6, 10), "TSD / RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, PHOSPHOR)
	draw_string(ThemeDB.fallback_font, Vector2(174, 10), "HDG %03d" % int(fposmod(rad_to_deg(_heading), 360)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, PHOSPHOR)
	draw_string(ThemeDB.fallback_font, Vector2(6, size.y - 4), "HDG UP", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, PHOSPHOR)
	draw_string(ThemeDB.fallback_font, Vector2(170, size.y - 4), "RNG %d KM" % int(range_m() / 1000), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, PHOSPHOR)
	for y in range(16, int(size.y) - 14, 3):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0.01, 0.006, 0.13))
	draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), Color(PHOSPHOR, 0.45), false, 1)
