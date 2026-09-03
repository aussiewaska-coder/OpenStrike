extends RefCounted

# Nearest-hit resolution across every world representation. Buildings are
# tested before terrain so a round can never punch through a tower and strike
# the hill behind it (spec sections 17, 80).

const SURFACES := preload("res://scripts/world/surface_types.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")

var building_index: RefCounted = null
var entity_index: Object = null
## Drones. A second source rather than a list, because there are exactly two
## and a list would need every caller to know the order.
var secondary_entity_index: Object = null
var surface_resolver: RefCounted = null
var sea_level := 0.0
var refine_iterations := 14

var _height_sampler := Callable()


func configure(height_sampler: Callable, index: RefCounted, resolver: RefCounted, sea_level_m: float) -> void:
	_height_sampler = height_sampler
	building_index = index
	surface_resolver = resolver
	sea_level = sea_level_m


func query_segment(from: Vector3, to: Vector3) -> RefCounted:
	var nearest: RefCounted = null
	if building_index != null:
		nearest = building_index.query_segment(from, to)
	for index in [entity_index, secondary_entity_index]:
		if index == null:
			continue
		var entity: RefCounted = index.query_segment(from, to)
		if entity != null and (nearest == null or entity.t < nearest.t):
			nearest = entity
	# Roads are not yet a distinct mesh; when the world compiler emits them they
	# slot in here, between buildings and water.
	var water := _query_water(from, to)
	if water != null and (nearest == null or water.t < nearest.t):
		nearest = water
	var terrain := _query_terrain(from, to)
	if terrain != null and (nearest == null or terrain.t < nearest.t):
		nearest = terrain
	if nearest != null:
		nearest.incident_velocity = to - from
	return nearest


func ground_height(world_x: float, world_z: float) -> float:
	if not _height_sampler.is_valid():
		return 0.0
	return float(_height_sampler.call(world_x, world_z))


func terrain_normal(world_x: float, world_z: float, spacing: float = 2.0) -> Vector3:
	# Four-tap slope estimate. Impact dust, decals and sparks all orient off
	# this, so a bullet striking a dune face throws debris along the dune.
	var left := ground_height(world_x - spacing, world_z)
	var right := ground_height(world_x + spacing, world_z)
	var back := ground_height(world_x, world_z - spacing)
	var forward := ground_height(world_x, world_z + spacing)
	var normal := Vector3(left - right, 2.0 * spacing, back - forward)
	return normal.normalized() if not normal.is_zero_approx() else Vector3.UP


func _query_terrain(from: Vector3, to: Vector3) -> RefCounted:
	if not _height_sampler.is_valid():
		return null
	var from_clearance := from.y - ground_height(from.x, from.z)
	var to_clearance := to.y - ground_height(to.x, to.z)
	if from_clearance <= 0.0:
		# The round started underground; treat the segment start as the impact
		# rather than reporting a miss and letting it tunnel onward.
		return _terrain_result(from, 0.0, from, to)
	if to_clearance > 0.0:
		return null
	var near := 0.0
	var far := 1.0
	for _iteration in range(refine_iterations):
		var middle := (near + far) * 0.5
		var point := from.lerp(to, middle)
		if point.y - ground_height(point.x, point.z) > 0.0:
			near = middle
		else:
			far = middle
	return _terrain_result(from.lerp(to, far), far, from, to)


func _terrain_result(position: Vector3, t: float, from: Vector3, to: Vector3) -> RefCounted:
	var result: RefCounted = HIT.new()
	result.hit = true
	result.t = t
	result.position = position
	result.normal = terrain_normal(position.x, position.z)
	result.distance = from.distance_to(position)
	result.object_type = HIT.ObjectKind.TERRAIN
	result.surface_type = (
		surface_resolver.resolve(position.x, position.z)
		if surface_resolver != null
		else SURFACES.Surface.DIRT
	)
	result.incident_velocity = to - from
	return result


func _query_water(from: Vector3, to: Vector3) -> RefCounted:
	var height_delta := to.y - from.y
	if absf(height_delta) < 0.0000001:
		return null
	var t := (sea_level - from.y) / height_delta
	if t < 0.0 or t > 1.0 or height_delta > 0.0:
		return null
	var position := from.lerp(to, t)
	# Water only exists where the ground is actually below sea level, so a round
	# crossing the sea-level plane over a hilltop is not a splash.
	if ground_height(position.x, position.z) >= sea_level:
		return null
	var result: RefCounted = HIT.new()
	result.hit = true
	result.t = t
	result.position = position
	result.normal = Vector3.UP
	result.distance = from.distance_to(position)
	result.object_type = HIT.ObjectKind.WATER
	result.surface_type = SURFACES.Surface.WATER
	result.incident_velocity = to - from
	return result
