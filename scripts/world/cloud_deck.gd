extends MeshInstance3D

## Depth-clipped volumetric clouds. One fullscreen pass integrates the same
## world-space volume from every active camera, including the weapon camera.
const DECK_SHADER := preload("res://shaders/cloud_deck.gdshader")
const WEATHER := preload("res://scripts/world/weather_state.gd")

@export var camera_path: NodePath
@export_range(16, 128, 8) var march_steps := 48
@export_range(0, 5) var shadow_steps := 0
@export var size_m := 16000.0

var _camera: Camera3D


func _ready() -> void:
	process_priority = 10
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh = quad
	var material := ShaderMaterial.new()
	material.shader = DECK_SHADER
	material.set_shader_parameter("cloud_base_m", WEATHER.CLOUD_ALTITUDE_M - WEATHER.CLOUD_HALF_DEPTH_M)
	material.set_shader_parameter("cloud_top_m", WEATHER.CLOUD_ALTITUDE_M + WEATHER.CLOUD_HALF_DEPTH_M)
	material.set_shader_parameter("max_distance_m", size_m * 0.5)
	# Draw after opaque geometry, before precipitation and other transparencies.
	material.render_priority = -100
	material_override = material
	configure_quality(march_steps, shadow_steps)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	ignore_occlusion_culling = true
	_process(0.0)


func _process(_delta: float) -> void:
	_camera = get_viewport().get_camera_3d()
	if is_instance_valid(_camera):
		global_position = _camera.global_position


func configure_quality(view_samples: int, light_samples: int) -> void:
	march_steps = clampi(view_samples, 16, 128)
	shadow_steps = clampi(light_samples, 0, 5)
	var material := material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("march_steps", march_steps)
		material.set_shader_parameter("shadow_steps", shadow_steps)
