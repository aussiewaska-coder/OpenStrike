extends Node3D

# Material-driven impact presentation. The cannon reports an event; this decides
# what it looks like (spec section 26). Everything is pooled - nothing is
# instantiated or freed while the trigger is held.
#
# The project renders with GL Compatibility, where Decal nodes are unavailable,
# so persistent marks are normal-aligned quads and bursts are CPUParticles3D.

const SURFACES := preload("res://scripts/world/surface_types.gd")

enum Quality { PERFORMANCE, BALANCED, QUALITY }

@export var quality: Quality = Quality.BALANCED
@export var burst_pool_size := 24
@export var decal_pool_size := 96
@export var decals_per_cell := 12
@export var decal_cell_size := 60.0

# One row per surface. Tuning lives here rather than scattered through code.
const SURFACE_FX := {
	SURFACES.Surface.DIRT: {
		"primary": Color(0.35, 0.27, 0.19), "secondary": Color(0.47, 0.39, 0.28),
		"count": 26, "speed": 15.0, "spread": 38.0, "life": 1.05, "gravity": 1.0,
		"sparks": 0, "decal": Color(0.16, 0.12, 0.08, 0.72), "decal_radius": 1.05,
	},
	SURFACES.Surface.GRASS: {
		"primary": Color(0.29, 0.31, 0.16), "secondary": Color(0.4, 0.36, 0.22),
		"count": 20, "speed": 12.5, "spread": 34.0, "life": 0.85, "gravity": 1.1,
		"sparks": 0, "decal": Color(0.12, 0.13, 0.07, 0.66), "decal_radius": 0.9,
	},
	SURFACES.Surface.SAND: {
		"primary": Color(0.86, 0.79, 0.62), "secondary": Color(0.93, 0.88, 0.74),
		"count": 40, "speed": 17.5, "spread": 30.0, "life": 1.9, "gravity": 0.42,
		"sparks": 0, "decal": Color(0.55, 0.48, 0.35, 0.5), "decal_radius": 1.25,
	},
	SURFACES.Surface.ROCK: {
		"primary": Color(0.44, 0.42, 0.4), "secondary": Color(0.62, 0.6, 0.57),
		"count": 24, "speed": 19.0, "spread": 44.0, "life": 0.9, "gravity": 1.35,
		"sparks": 3, "decal": Color(0.2, 0.19, 0.18, 0.7), "decal_radius": 0.8,
	},
	SURFACES.Surface.ASPHALT: {
		"primary": Color(0.2, 0.2, 0.21), "secondary": Color(0.52, 0.52, 0.53),
		"count": 22, "speed": 18.0, "spread": 40.0, "life": 0.8, "gravity": 1.25,
		"sparks": 4, "decal": Color(0.08, 0.08, 0.09, 0.8), "decal_radius": 0.7,
	},
	SURFACES.Surface.CONCRETE: {
		"primary": Color(0.72, 0.7, 0.67), "secondary": Color(0.86, 0.85, 0.82),
		"count": 30, "speed": 21.0, "spread": 46.0, "life": 1.15, "gravity": 1.15,
		"sparks": 5, "decal": Color(0.24, 0.23, 0.22, 0.78), "decal_radius": 0.85,
	},
	SURFACES.Surface.GLASS: {
		"primary": Color(0.78, 0.87, 0.92), "secondary": Color(0.94, 0.97, 1.0),
		"count": 18, "speed": 24.0, "spread": 52.0, "life": 0.7, "gravity": 1.4,
		"sparks": 6, "decal": Color(0.4, 0.47, 0.5, 0.6), "decal_radius": 0.95,
	},
	SURFACES.Surface.METAL: {
		"primary": Color(0.9, 0.66, 0.32), "secondary": Color(1.0, 0.85, 0.5),
		"count": 8, "speed": 26.0, "spread": 55.0, "life": 0.5, "gravity": 1.2,
		"sparks": 14, "decal": Color(0.12, 0.11, 0.1, 0.75), "decal_radius": 0.5,
	},
	SURFACES.Surface.ROOF_TILE: {
		"primary": Color(0.53, 0.31, 0.24), "secondary": Color(0.68, 0.45, 0.34),
		"count": 24, "speed": 18.5, "spread": 42.0, "life": 0.95, "gravity": 1.2,
		"sparks": 2, "decal": Color(0.22, 0.13, 0.1, 0.74), "decal_radius": 0.8,
	},
	SURFACES.Surface.WATER: {
		"primary": Color(0.78, 0.86, 0.9), "secondary": Color(0.95, 0.98, 1.0),
		"count": 26, "speed": 22.0, "spread": 14.0, "life": 0.8, "gravity": 1.6,
		"sparks": 0, "decal": Color(1.0, 1.0, 1.0, 0.0), "decal_radius": 0.0,
	},
}

var _bursts: Array[CPUParticles3D] = []
var _sparks: Array[CPUParticles3D] = []
var _burst_cursor := 0
var _spark_cursor := 0
var _decals: Array[MeshInstance3D] = []
var _decal_cursor := 0
var _decal_cells: Dictionary = {}
var _decal_lifetime := 22.0


func _ready() -> void:
	_apply_quality()
	for index in range(burst_pool_size):
		_bursts.append(_make_emitter(false))
		_sparks.append(_make_emitter(true))
	for index in range(decal_pool_size):
		_decals.append(_make_decal())


func spawn_impact(hit_result: RefCounted, round_data: RefCounted) -> void:
	var surface := int(hit_result.surface_type)
	var settings: Dictionary = SURFACE_FX.get(surface, SURFACE_FX[SURFACES.Surface.DIRT])
	var normal: Vector3 = hit_result.normal
	var incident: Vector3 = hit_result.incident_direction()
	# Debris leaves along the surface normal biased by the incoming round, so a
	# grazing shot throws its plume downrange instead of straight up.
	var ejecta := (normal * 1.6 - incident).normalized()
	_emit_burst(hit_result.position, ejecta, settings)
	if int(settings["sparks"]) > 0 and quality != Quality.PERFORMANCE:
		_emit_sparks(hit_result.position, ejecta, settings)
	if float(settings["decal_radius"]) > 0.0:
		_place_decal(hit_result.position, normal, settings)


func _apply_quality() -> void:
	match quality:
		Quality.PERFORMANCE:
			burst_pool_size = 12
			decal_pool_size = 32
			decals_per_cell = 5
			_decal_lifetime = 8.0
		Quality.BALANCED:
			_decal_lifetime = 22.0
		Quality.QUALITY:
			burst_pool_size = 36
			decal_pool_size = 160
			decals_per_cell = 20
			_decal_lifetime = 45.0


func _particle_scale() -> float:
	match quality:
		Quality.PERFORMANCE:
			return 0.42
		Quality.QUALITY:
			return 1.35
		_:
			return 1.0


func _emit_burst(position: Vector3, direction: Vector3, settings: Dictionary) -> void:
	var emitter := _bursts[_burst_cursor]
	_burst_cursor = (_burst_cursor + 1) % _bursts.size()
	emitter.global_position = position
	emitter.look_at_from_position(position, position + direction, Vector3.UP)
	emitter.amount = maxi(int(int(settings["count"]) * _particle_scale()), 3)
	emitter.lifetime = float(settings["life"])
	emitter.initial_velocity_min = float(settings["speed"]) * 0.35
	emitter.initial_velocity_max = float(settings["speed"])
	emitter.spread = float(settings["spread"])
	emitter.gravity = Vector3.DOWN * 9.80665 * float(settings["gravity"])
	emitter.color = settings["primary"]
	emitter.scale_amount_min = 0.22
	emitter.scale_amount_max = 0.75
	emitter.restart()


func _emit_sparks(position: Vector3, direction: Vector3, settings: Dictionary) -> void:
	var emitter := _sparks[_spark_cursor]
	_spark_cursor = (_spark_cursor + 1) % _sparks.size()
	emitter.global_position = position
	emitter.look_at_from_position(position, position + direction, Vector3.UP)
	emitter.amount = maxi(int(int(settings["sparks"]) * _particle_scale()), 1)
	emitter.lifetime = 0.42
	emitter.initial_velocity_min = 18.0
	emitter.initial_velocity_max = 44.0
	emitter.spread = 62.0
	emitter.gravity = Vector3.DOWN * 22.0
	emitter.color = settings["secondary"]
	emitter.scale_amount_min = 0.06
	emitter.scale_amount_max = 0.16
	emitter.restart()


func _place_decal(position: Vector3, normal: Vector3, settings: Dictionary) -> void:
	var cell := Vector3i(
		int(floor(position.x / decal_cell_size)),
		0,
		int(floor(position.z / decal_cell_size))
	)
	var occupants: Array = _decal_cells.get(cell, [])
	# Hard cap per cell so sustained fire on one facade cannot carpet the world
	# with marks; the oldest in that cell is recycled first.
	if occupants.size() >= decals_per_cell:
		var oldest: MeshInstance3D = occupants.pop_front()
		oldest.visible = false
	var decal := _decals[_decal_cursor]
	_decal_cursor = (_decal_cursor + 1) % _decals.size()
	for existing_cell: Vector3i in _decal_cells.keys():
		_decal_cells[existing_cell].erase(decal)
	var radius := float(settings["decal_radius"])
	decal.visible = true
	decal.global_position = position + normal * 0.06
	decal.scale = Vector3(radius, radius, radius)
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.94 else Vector3.RIGHT
	decal.look_at_from_position(decal.global_position, decal.global_position - normal, up)
	var material := decal.material_override as StandardMaterial3D
	material.albedo_color = settings["decal"]
	occupants.append(decal)
	_decal_cells[cell] = occupants
	_fade_decal(decal)


func _fade_decal(decal: MeshInstance3D) -> void:
	var timer := get_tree().create_timer(_decal_lifetime)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(decal):
			decal.visible = false
	)


func _make_emitter(is_spark: bool) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.emitting = false
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.local_coords = false
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.5, 0.5) if not is_spark else Vector2(0.7, 0.12)
	emitter.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if is_spark:
		material.emission_enabled = true
		material.emission = Color(1.0, 0.72, 0.34)
		material.emission_energy_multiplier = 3.4
	emitter.material_override = material
	add_child(emitter)
	return emitter


func _make_decal() -> MeshInstance3D:
	var decal := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	decal.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	decal.material_override = material
	decal.visible = false
	add_child(decal)
	return decal
