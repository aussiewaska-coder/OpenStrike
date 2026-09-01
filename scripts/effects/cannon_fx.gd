extends Node3D

# Muzzle flash, muzzle smoke and the tracer stream. Every tracer is a real
# simulated round - this only draws the ones flagged by tracer_interval, along
# the path that round actually took (spec sections 36-42).

@export var tracer_pool_size := 48
@export var flash_pool_size := 6
@export var minimum_tracer_length := 6.0
@export var maximum_tracer_length := 42.0
@export var tracer_thickness := 0.16
@export var tracer_colour := Color(1.0, 0.71, 0.26)
@export var enable_muzzle_light := false

var projectile_manager: Node3D
var gun_mount: Node3D
var weapon: Node3D

var _tracers: Array[MeshInstance3D] = []
var _flashes: Array[MeshInstance3D] = []
var _flash_life: Array[float] = []
var _flash_cursor := 0
var _muzzle_light: OmniLight3D
var _muzzle_smoke: CPUParticles3D
var _camera: Camera3D


func _ready() -> void:
	for index in range(tracer_pool_size):
		_tracers.append(_make_tracer())
	for index in range(flash_pool_size):
		_flashes.append(_make_flash())
		_flash_life.append(0.0)
	_muzzle_smoke = _make_smoke()
	if enable_muzzle_light:
		_muzzle_light = OmniLight3D.new()
		_muzzle_light.light_color = Color(1.0, 0.78, 0.42)
		_muzzle_light.omni_range = 26.0
		_muzzle_light.light_energy = 0.0
		_muzzle_light.shadow_enabled = false
		add_child(_muzzle_light)


func _process(delta: float) -> void:
	_camera = get_viewport().get_camera_3d()
	_update_tracers()
	_update_flashes(delta)
	_update_smoke()


func on_round_fired(_round_data: RefCounted) -> void:
	if gun_mount == null:
		return
	var muzzle: Transform3D = gun_mount.get_muzzle_transform()
	var flash := _flashes[_flash_cursor]
	# Very short life: at 625 RPM the player should perceive a flicker, not a
	# sustained flame.
	_flash_life[_flash_cursor] = 0.045
	_flash_cursor = (_flash_cursor + 1) % _flashes.size()
	flash.visible = true
	flash.global_transform = muzzle
	flash.scale = Vector3.ONE * randf_range(1.5, 2.4)
	if _muzzle_light != null:
		_muzzle_light.global_position = muzzle.origin
		_muzzle_light.light_energy = 3.2


func _update_tracers() -> void:
	var index := 0
	if projectile_manager != null:
		for round_data in projectile_manager.active_rounds:
			if not round_data.is_tracer or index >= _tracers.size():
				continue
			_draw_tracer(_tracers[index], round_data)
			index += 1
	for hidden in range(index, _tracers.size()):
		_tracers[hidden].visible = false


func _draw_tracer(tracer: MeshInstance3D, round_data: RefCounted) -> void:
	var travel: Vector3 = round_data.position - round_data.previous_position
	if travel.is_zero_approx():
		tracer.visible = false
		return
	var forward := travel.normalized()
	# Clamped so a frame hitch does not stretch one round into a long streak.
	var length := clampf(travel.length(), minimum_tracer_length, maximum_tracer_length)
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	# A physically sized round is sub-pixel at range, so thickness alone is
	# exaggerated with distance. The simulation stays untouched.
	var thickness := tracer_thickness
	if _camera != null:
		thickness *= clampf(_camera.global_position.distance_to(round_data.position) / 220.0, 1.0, 5.5)
	tracer.visible = true
	tracer.global_transform = Transform3D(
		Basis(forward * length, up * thickness, right * thickness),
		round_data.position - forward * length * 0.5
	)


func _update_flashes(delta: float) -> void:
	for index in range(_flashes.size()):
		if _flash_life[index] <= 0.0:
			continue
		_flash_life[index] -= delta
		if _flash_life[index] <= 0.0:
			_flashes[index].visible = false
	if _muzzle_light != null:
		_muzzle_light.light_energy = move_toward(_muzzle_light.light_energy, 0.0, 42.0 * delta)


func _update_smoke() -> void:
	if _muzzle_smoke == null or gun_mount == null or weapon == null:
		return
	var muzzle: Transform3D = gun_mount.get_muzzle_transform()
	_muzzle_smoke.global_position = muzzle.origin + muzzle.basis.x * 0.8
	# Rate-dependent: a two-round tap emits almost nothing, a long burst builds
	# a visible haze under the nose that then dissipates on its own.
	var firing: bool = weapon.is_firing
	_muzzle_smoke.emitting = firing
	if firing:
		var build: float = clampf(weapon.continuous_fire_time / 2.4, 0.0, 1.0)
		_muzzle_smoke.amount_ratio = lerpf(0.12, 1.0, build)


func firing_intensity() -> float:
	if weapon == null or not weapon.is_firing:
		return 0.0
	return clampf(weapon.continuous_fire_time / 1.2, 0.25, 1.0)


func _make_tracer() -> MeshInstance3D:
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	tracer.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tracer_colour
	material.emission_enabled = true
	material.emission = tracer_colour
	material.emission_energy_multiplier = 4.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tracer.material_override = material
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer.visible = false
	add_child(tracer)
	return tracer


func _make_flash() -> MeshInstance3D:
	var flash := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.4, 1.4)
	flash.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.83, 0.45, 0.9)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.78, 0.36)
	material.emission_energy_multiplier = 6.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash.material_override = material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.visible = false
	add_child(flash)
	return flash


func _make_smoke() -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.emitting = false
	smoke.amount = 40
	smoke.lifetime = 1.9
	smoke.local_coords = false
	smoke.spread = 16.0
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 7.0
	smoke.gravity = Vector3.UP * 0.6
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 2.4
	smoke.color = Color(0.55, 0.53, 0.5, 0.32)
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	smoke.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke.material_override = material
	add_child(smoke)
	return smoke
