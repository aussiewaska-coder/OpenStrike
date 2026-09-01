class_name EntityHitIndex
extends RefCounted

const HIT := preload("res://scripts/world/world_hit_result.gd")
const SURFACES := preload("res://scripts/world/surface_types.gd")

var _entities: Dictionary = {}


func add_entity(entity_id: int, bounds: AABB, surface_type: int = SURFACES.Surface.METAL) -> void:
	_entities[entity_id] = {"bounds": bounds, "surface_type": surface_type}


func remove_entity(entity_id: int) -> void:
	_entities.erase(entity_id)


func clear() -> void:
	_entities.clear()


func entity_count() -> int:
	return _entities.size()


func query_segment(from: Vector3, to: Vector3) -> RefCounted:
	var nearest: RefCounted = null
	for entity_id: int in _entities:
		var candidate := _intersect_entity(entity_id, _entities[entity_id], from, to)
		if candidate != null and (nearest == null or candidate.t < nearest.t):
			nearest = candidate
	return nearest


func _intersect_entity(entity_id: int, entity: Dictionary, from: Vector3, to: Vector3) -> RefCounted:
	var bounds: AABB = entity["bounds"]
	var direction := to - from
	var near_t := 0.0
	var far_t := 1.0
	var hit_normal := Vector3.ZERO
	for axis in range(3):
		var origin_axis: float = from[axis]
		var direction_axis: float = direction[axis]
		var minimum: float = bounds.position[axis]
		var maximum: float = bounds.end[axis]
		if absf(direction_axis) < 0.0000001:
			if origin_axis < minimum or origin_axis > maximum:
				return null
			continue
		var first := (minimum - origin_axis) / direction_axis
		var second := (maximum - origin_axis) / direction_axis
		var first_normal := Vector3.ZERO
		first_normal[axis] = -signf(direction_axis)
		if first > second:
			var swap := first
			first = second
			second = swap
		if first > near_t:
			near_t = first
			hit_normal = first_normal
		far_t = minf(far_t, second)
		if near_t > far_t:
			return null
	if near_t < 0.0 or near_t > 1.0:
		return null
	if hit_normal.is_zero_approx():
		hit_normal = -direction.normalized()
	var result: RefCounted = HIT.new()
	result.hit = true
	result.t = near_t
	result.position = from.lerp(to, near_t)
	result.normal = hit_normal
	result.distance = from.distance_to(result.position)
	result.object_type = HIT.ObjectKind.ENTITY
	result.object_id = entity_id
	result.surface_type = int(entity["surface_type"])
	return result
