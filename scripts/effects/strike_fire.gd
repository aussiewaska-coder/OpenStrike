extends Node3D

## Fixed pool of sustained emitters, independent of the short impact burst pool.
const MATERIALS := preload("res://scripts/effects/effect_materials.gd")
const MAX_FIRES := 16
const SMOKE_SHADER := preload("res://shaders/strike_smoke.gdshader")
var _sites: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var wind_mps := 6.0

func _init() -> void:
	_rng.randomize()

func ignite(point: Vector3, building := false) -> Dictionary:
	var site := {}
	for existing in _sites:
		if Vector3(existing.point).distance_to(point) < 22.0:
			site = existing
			break
	if site.is_empty():
		if _sites.size() < MAX_FIRES:
			site = {"smoke": _emitter(false), "fire": _emitter(true), "age": 0.0, "point": point, "building": false, "phase": _rng.randf_range(0.0, TAU), "variation": _rng.randf_range(0.9, 1.1)}
			_sites.append(site)
		else:
			site = _sites[0]
			for candidate in _sites:
				if candidate.age > site.age:
					site = candidate
			site.building = false
		site.erase("wreck_velocity")
		site.erase("ground_height")
	var relocate: bool = Vector3(site.point).distance_to(point) >= 22.0
	site.building = building or site.building
	site.point = point
	site.age = 0.0
	site.duration = 100.0 if site.building else 60.0
	var scale_factor: float = (2.6 if site.building else 1.0) * site.variation
	site.scale_factor = scale_factor
	for key in ["smoke", "fire"]:
		var emitter: CPUParticles3D = site[key]
		var smoke: bool = key == "smoke"
		emitter.global_position = point + Vector3.UP * 1.5
		emitter.emission_sphere_radius = (8.0 if smoke else 5.0) * scale_factor
		emitter.initial_velocity_min = (9.0 if smoke else 3.0) * sqrt(scale_factor)
		emitter.initial_velocity_max = (17.0 if smoke else 8.0) * sqrt(scale_factor)
		emitter.scale_amount_min = (36.0 if smoke else 12.0) * scale_factor
		emitter.scale_amount_max = (64.0 if smoke else 22.0) * scale_factor
		if relocate:
			emitter.restart()
		if smoke:
			emitter.material_override.set_shader_parameter("source_height", point.y)
		emitter.emitting = true
	return site

## A live moving source keeps one emitter; emitted smoke stays behind it.
func follow_source(point: Vector3) -> void:
	if _sites.is_empty():
		ignite(point)
	var site := _sites[0]
	site.point = point
	site.fire.global_position = point + Vector3.UP * 1.5
	site.smoke.global_position = point + Vector3.UP * 1.5

func ignite_wreck(point: Vector3, velocity: Vector3, ground_height: Callable) -> Dictionary:
	var site := ignite(point)
	site.wreck_velocity = velocity
	site.ground_height = ground_height
	return site

func _process(delta: float) -> void:
	for site in _sites:
		if site.has("wreck_velocity"):
			var velocity: Vector3 = site.wreck_velocity
			velocity.y -= 9.8 * delta
			var point: Vector3 = site.point + velocity * delta
			var floor_y := float(site.ground_height.call(point))
			if point.y <= floor_y:
				point.y = floor_y
				site.erase("wreck_velocity")
				site.erase("ground_height")
			else:
				site.wreck_velocity = velocity
			site.point = point
			site.fire.global_position = point + Vector3.UP * 1.5
			site.smoke.global_position = point + Vector3.UP * 1.5
		site.age += delta
		site.fire.emitting = site.age < site.duration * 0.7
		site.smoke.emitting = site.age < site.duration
		var buildup := smoothstep(0.0, 12.0, site.age)
		var cooling := 1.0 - smoothstep(site.duration * 0.55, site.duration, site.age)
		var phase: float = site.phase
		var smoke: CPUParticles3D = site.smoke
		smoke.material_override.set_shader_parameter("source_height", site.point.y)
		smoke.gravity = Vector3(wind_mps * 0.06 + sin(site.age * 0.17 + phase) * 0.30, 0.9 + buildup * 0.8, 0.25 + cos(site.age * 0.13 + phase) * 0.4)
		smoke.direction = Vector3(wind_mps * 0.02, 1.0, 0.0).normalized()
		site.fire.direction = Vector3(wind_mps * 0.04, 1.0, 0.0).normalized()
		smoke.initial_velocity_min = (7.0 + buildup * 5.0) * sqrt(site.scale_factor)
		smoke.initial_velocity_max = (14.0 + buildup * 9.0) * sqrt(site.scale_factor)
		smoke.color = Color(1, 1, 1, lerpf(0.45, 1.0, cooling))
		site.fire.color = Color(1, 1, 1, cooling * (0.8 + 0.2 * sin(site.age * 6.7 + phase)))

func clear() -> void:
	for site in _sites:
		site.fire.queue_free()
		site.smoke.queue_free()
	_sites.clear()

func _emitter(fire: bool) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.emitting = false
	emitter.local_coords = false
	emitter.amount = 24 if fire else 56
	emitter.lifetime = 2.6 if fire else 24.0
	emitter.direction = Vector3.UP
	emitter.spread = 24.0 if fire else 10.0
	emitter.gravity = Vector3(0.8, 0.8, 0.3) if fire else Vector3(0.5, 1.2, 0.2)
	emitter.fixed_fps = 20
	emitter.lifetime_randomness = 0.25
	emitter.randomness = 0.35
	emitter.angle_min = -25.0 if fire else -180.0
	emitter.angle_max = 25.0 if fire else 180.0
	emitter.angular_velocity_min = -18.0
	emitter.angular_velocity_max = 22.0
	emitter.radial_accel_min = 0.0
	emitter.radial_accel_max = 0.4 if fire else 0.18
	emitter.tangential_accel_min = -0.12
	emitter.tangential_accel_max = 0.15
	emitter.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, 1.7) if fire else Vector2.ONE
	emitter.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = MATERIALS.soft_disc() if fire else MATERIALS.smoke_billow()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.emission_enabled = fire
	material.emission = Color(1.0, 0.22, 0.015)
	material.emission_energy_multiplier = 1.8
	if fire:
		emitter.material_override = material
	else:
		var smoke_material := ShaderMaterial.new()
		smoke_material.shader = SMOKE_SHADER
		smoke_material.set_shader_parameter("billow_texture", MATERIALS.smoke_billow())
		smoke_material.set_shader_parameter("diffuse_texture", MATERIALS.soft_disc())
		emitter.material_override = smoke_material
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0, 0.12, 0.55, 1])
	ramp.colors = PackedColorArray([Color(1, 0.8, 0.15, 0), Color(1, 0.55, 0.04, 0.95), Color(0.7, 0.12, 0.015, 0.7), Color(0.2, 0.04, 0.01, 0)]) if fire else PackedColorArray([Color(0.09, 0.085, 0.08, 0), Color(0.07, 0.065, 0.06, 0.94), Color(0.29, 0.29, 0.29, 0.35), Color(0.36, 0.35, 0.34, 0)])
	emitter.color_ramp = ramp
	var growth := Curve.new()
	growth.max_value = 2.2
	growth.add_point(Vector2(0, 0.5 if fire else 0.55))
	growth.add_point(Vector2(0.45, 0.8 if fire else 1.25))
	growth.add_point(Vector2(1, 0.15 if fire else 2.1))
	emitter.scale_amount_curve = growth
	add_child(emitter)
	return emitter
