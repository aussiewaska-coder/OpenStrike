extends Node

## Drifts the sky between weathers and tells every shader about it through
## the os_* globals. Rain is a particle box under the camera; lightning is
## a two-frame flash of the sun.

const WEATHER := preload("res://scripts/world/weather_state.gd")

@export var camera_path: NodePath
@export var day_cycle_path: NodePath

var preset: int = WEATHER.Preset.CLEAR
var current: Dictionary = {}
var wind_offset := Vector2.ZERO

var _camera: Camera3D
var _day_cycle: Node
var _rain: CPUParticles3D
var _rng := RandomNumberGenerator.new()
var _lightning_timer := 0.0
var _flash_frames := 0
var _applied_sun_multiplier := 1.0
var _applied_fog_multiplier := 1.0


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	_day_cycle = get_node_or_null(day_cycle_path)
	current = WEATHER.target(preset)
	_rng.randomize()
	_lightning_timer = WEATHER.lightning_delay(_rng)
	_build_rain()
	_apply()


func set_preset(next: int) -> void:
	preset = next


func cycle_preset() -> void:
	preset = (preset + 1) % WEATHER.PRESET_NAMES.size()


func preset_name() -> String:
	return WEATHER.name_of(preset)


func _process(delta: float) -> void:
	current = WEATHER.step(current, WEATHER.target(preset), delta)
	# Wind blows the field along +X (east); the sky's clouds and the ground's
	# shadows both read this offset.
	wind_offset.x += float(current["wind_mps"]) * delta
	_apply()
	_lightning(delta)


func _apply() -> void:
	RenderingServer.global_shader_parameter_set("os_cloud_coverage", float(current["cloud_coverage"]))
	RenderingServer.global_shader_parameter_set("os_cloud_shadow", float(current["cloud_shadow"]))
	RenderingServer.global_shader_parameter_set("os_wet", float(current["wet"]))
	RenderingServer.global_shader_parameter_set("os_cloud_wind", wind_offset)
	if _rain != null:
		var rate := float(current["rain_rate"])
		_rain.emitting = rate > 0.02
		if _camera != null:
			_rain.global_position = _camera.global_position + Vector3(0.0, 12.0, 0.0)
	if _day_cycle == null:
		return
	var sun_multiplier := float(current["sun_multiplier"])
	var fog_multiplier := float(current["fog_multiplier"])
	if absf(sun_multiplier - _applied_sun_multiplier) > 0.005 or absf(fog_multiplier - _applied_fog_multiplier) > 0.01:
		_applied_sun_multiplier = sun_multiplier
		_applied_fog_multiplier = fog_multiplier
		_day_cycle.sun_multiplier = sun_multiplier
		_day_cycle.fog_multiplier = fog_multiplier
		_day_cycle.refresh()


func _lightning(delta: float) -> void:
	if _flash_frames > 0:
		_flash_frames -= 1
		if _flash_frames == 0:
			_day_cycle.sun_multiplier = _applied_sun_multiplier
			_day_cycle.refresh()
		return
	if preset != WEATHER.Preset.STORM or _day_cycle == null:
		return
	_lightning_timer -= delta
	if _lightning_timer > 0.0:
		return
	_lightning_timer = WEATHER.lightning_delay(_rng)
	_flash_frames = 2
	_day_cycle.sun_multiplier = 6.0
	_day_cycle.refresh()


## A box of streaks that rides above the camera. CPU particles on purpose:
## GPU particles draw nothing on the Compatibility renderer.
func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.emitting = false
	_rain.amount = 700
	_rain.lifetime = 1.1
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(30.0, 4.0, 30.0)
	_rain.direction = Vector3(0.0, -1.0, 0.0)
	_rain.spread = 2.0
	_rain.gravity = Vector3(0.0, -30.0, 0.0)
	_rain.initial_velocity_min = 18.0
	_rain.initial_velocity_max = 24.0
	var streak := QuadMesh.new()
	streak.size = Vector2(0.03, 0.6)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.85, 0.9, 1.0, 0.35)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	streak.material = material
	_rain.mesh = streak
	add_child(_rain)
