extends Node

## Weather owns the shared cloud field, local precipitation, and storm clock.
## Clouds and rain follow the active view, including the weapon camera.
const WEATHER := preload("res://scripts/world/weather_state.gd")
const CLOUD_NOISE := preload("res://assets/textures/cloud_noise.tres")
const RAIN_SHADER := preload("res://shaders/rain.gdshader")
const AUDIO := preload("res://scripts/audio/weather_audio.gd")

@export var camera_path: NodePath
@export var day_cycle_path: NodePath

var preset: int = WEATHER.Preset.CLEAR
var current: Dictionary = {}
var wind_offset := Vector2.ZERO
var rain_intensity := 0.0
var cloud_immersion := 0.0
var audio: Node

var _camera: Camera3D
var _day_cycle: Node
var _rain: CPUParticles3D
var _rain_material: ShaderMaterial
var _noise_image: Image
var _rng := RandomNumberGenerator.new()
var _lightning_timer := 0.0
var _flash_elapsed := -1.0
var _lightning_light: DirectionalLight3D
var _pending_thunder: Array[Dictionary] = []
var _applied_sun_multiplier := 1.0
var _applied_fog_multiplier := 1.0
var _previous_camera_id := 0
var _previous_position := Vector3.ZERO
var _camera_velocity := Vector3.ZERO


func _ready() -> void:
	# Main updates the follow camera at priority 0; weather samples it afterwards.
	process_priority = 10
	_camera = get_node_or_null(camera_path) as Camera3D
	_day_cycle = get_node_or_null(day_cycle_path)
	current = WEATHER.target(preset)
	_rng.randomize()
	_lightning_timer = WEATHER.lightning_delay(_rng)
	CLOUD_NOISE.changed.connect(_cache_cloud_noise)
	_cache_cloud_noise()
	_build_rain()
	audio = AUDIO.new()
	audio.name = "WeatherAudio"
	add_child(audio)
	_lightning_light = DirectionalLight3D.new()
	_lightning_light.name = "Lightning"
	_lightning_light.rotation_degrees = Vector3(-65.0, -30.0, 0.0)
	_lightning_light.light_color = Color(0.72, 0.82, 1.0)
	_lightning_light.light_energy = 0.0
	_lightning_light.shadow_enabled = false
	_lightning_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_lightning_light)
	_apply()


func _cache_cloud_noise() -> void:
	_noise_image = CLOUD_NOISE.get_image()


func set_preset(next: int) -> void:
	preset = clampi(next, WEATHER.Preset.CLEAR, WEATHER.Preset.STORM)


func cycle_preset() -> void:
	set_preset((preset + 1) % WEATHER.PRESET_NAMES.size())


func preset_name() -> String:
	return WEATHER.name_of(preset)


func _process(delta: float) -> void:
	current = WEATHER.step(current, WEATHER.target(preset), delta)
	# The shader samples world + offset, so negative offset moves clouds east.
	wind_offset.x -= float(current["wind_mps"]) * delta
	_apply(delta)
	_lightning(delta)


func _apply(delta := 0.0) -> void:
	var active := get_viewport().get_camera_3d()
	if active != null:
		_camera = active
	RenderingServer.global_shader_parameter_set("os_cloud_coverage", float(current["cloud_coverage"]))
	RenderingServer.global_shader_parameter_set("os_cloud_shadow", float(current["cloud_shadow"]))
	RenderingServer.global_shader_parameter_set("os_wet", float(current["wet"]))
	RenderingServer.global_shader_parameter_set("os_cloud_wind", wind_offset)
	var altitude := 0.0
	cloud_immersion = 0.0
	if is_instance_valid(_camera):
		var position := _camera.global_position
		altitude = position.y
		var density := WEATHER.cloud_density(_noise_image, Vector2(position.x, position.z), wind_offset, float(current["cloud_coverage"]))
		cloud_immersion = WEATHER.cloud_band(altitude) * density
		_update_camera_velocity(position, delta)
		_rain.global_position = position
	rain_intensity = WEATHER.rain_at_altitude(float(current["rain_rate"]), altitude) if is_instance_valid(_camera) else 0.0
	_rain.emitting = rain_intensity > 0.01
	# Hide surviving particles at the cloud top too, rather than leaving a tail
	# of rain in clear air. The bounded emitter remains allocated for transitions.
	_rain.visible = rain_intensity > 0.01
	_rain_material.set_shader_parameter("intensity", rain_intensity)
	var relative_velocity := Vector3(float(current["wind_mps"]), -24.0, 0.0) - _camera_velocity
	var speed := maxf(relative_velocity.length(), 1.0)
	_rain.direction = relative_velocity / speed
	_rain.speed_scale = clampf(speed / 24.0, 0.5, 30.0)
	_rain_material.set_shader_parameter("travel_direction", _rain.direction)
	_rain_material.set_shader_parameter("streak_length", clampf(speed * 0.008, 0.7, 2.8))
	if audio != null:
		audio.update_rain(delta, rain_intensity)
	if _day_cycle == null:
		return
	# Weather dims the world below the deck; sunlight returns above the tops.
	var above := WEATHER.above_clouds(altitude)
	var sun_multiplier := lerpf(float(current["sun_multiplier"]), 1.0, above)
	var fog_multiplier := lerpf(float(current["fog_multiplier"]), 1.0, above)
	if absf(sun_multiplier - _applied_sun_multiplier) > 0.005 or absf(fog_multiplier - _applied_fog_multiplier) > 0.01:
		_applied_sun_multiplier = sun_multiplier
		_applied_fog_multiplier = fog_multiplier
		_day_cycle.sun_multiplier = sun_multiplier
		_day_cycle.fog_multiplier = fog_multiplier
		_day_cycle.refresh()
	# Extinction now comes from the depth-clipped 3D volume, not uniform fog.
	_day_cycle.set_cloud_immersion(0.0)


func _update_camera_velocity(position: Vector3, delta: float) -> void:
	var changed := _previous_camera_id != _camera.get_instance_id()
	var displacement := position - _previous_position
	if changed or displacement.length() > maxf(200.0, delta * 1800.0):
		_camera_velocity = Vector3.ZERO
		_rain.restart()
	elif delta > 0.0:
		_camera_velocity = _camera_velocity.lerp((displacement / delta).limit_length(900.0), 1.0 - exp(-10.0 * delta))
	_previous_camera_id = _camera.get_instance_id()
	_previous_position = position


func _lightning(delta: float) -> void:
	# Thunder already in flight still arrives if the weather selection changes.
	for index in range(_pending_thunder.size() - 1, -1, -1):
		var event: Dictionary = _pending_thunder[index]
		event["remaining"] -= delta
		if event["remaining"] <= 0.0:
			audio.play_thunder(event["distance"], event["pitch"])
			_pending_thunder.remove_at(index)
	if _flash_elapsed >= 0.0:
		_flash_elapsed += delta
		if _flash_elapsed >= 0.34:
			_flash_elapsed = -1.0
	if preset == WEATHER.Preset.STORM and float(current["rain_rate"]) > 0.75:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_begin_lightning(_rng.randf_range(800.0, 2600.0))
	var strength := WEATHER.lightning_strength(_flash_elapsed)
	_lightning_light.light_energy = strength * 2.0
	_lightning_light.visible = strength > 0.0
	RenderingServer.global_shader_parameter_set("os_lightning", strength)


func _begin_lightning(distance_m: float) -> void:
	_flash_elapsed = 0.0
	_lightning_timer = WEATHER.lightning_delay(_rng)
	_lightning_light.rotation_degrees.y = _rng.randf_range(-180.0, 180.0)
	if _pending_thunder.size() < 4:
		_pending_thunder.append({"remaining": distance_m / WEATHER.SOUND_SPEED_MPS, "distance": distance_m, "pitch": _rng.randf_range(0.86, 1.06)})


func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rain.name = "Rain"
	_rain.emitting = false
	_rain.amount = 700
	_rain.lifetime = 1.4
	_rain.local_coords = true
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(24.0, 18.0, 24.0)
	_rain.direction = Vector3.DOWN
	_rain.spread = 2.0
	_rain.gravity = Vector3.ZERO
	_rain.initial_velocity_min = 22.0
	_rain.initial_velocity_max = 26.0
	_rain.visibility_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# CPU particles have no amount_ratio. A random, stable seed per particle
	# lets the shader thin rainfall without restarting the emitter every frame.
	var seeds := Gradient.new()
	seeds.colors = PackedColorArray([Color.BLACK, Color.WHITE])
	_rain.color_initial_ramp = seeds
	var streak := QuadMesh.new()
	streak.size = Vector2(0.045, 1.0)
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = RAIN_SHADER
	streak.material = _rain_material
	_rain.mesh = streak
	add_child(_rain)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("os_lightning", 0.0)
	if is_instance_valid(_day_cycle):
		_day_cycle.sun_multiplier = 1.0
		_day_cycle.fog_multiplier = 1.0
		_day_cycle.set_cloud_immersion(0.0)
		_day_cycle.refresh()
