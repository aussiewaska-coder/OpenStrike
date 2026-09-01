extends SceneTree

const INDEX := preload("res://scripts/entities/entity_hit_index.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")
const SURFACES := preload("res://scripts/world/surface_types.gd")


func _init() -> void:
	var index := INDEX.new()
	index.add_entity(41, AABB(Vector3(10.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0)))
	index.add_entity(99, AABB(Vector3(16.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0)))
	var hit: RefCounted = index.query_segment(Vector3.ZERO, Vector3(20.0, 0.0, 0.0))
	assert(hit != null and hit.hit, "the projectile segment must strike the launcher bounds")
	assert(hit.object_type == HIT.ObjectKind.ENTITY, "launcher hits must use the entity path")
	assert(hit.object_id == 41, "the nearest launcher must win")
	assert(hit.surface_type == SURFACES.Surface.METAL, "launcher impacts must spark as metal")
	assert(hit.position.is_equal_approx(Vector3(10.0, 0.0, 0.0)), "impact must land on the near face")
	assert(hit.normal.is_equal_approx(Vector3.LEFT), "impact normal must face the incoming round")
	index.remove_entity(41)
	var second: RefCounted = index.query_segment(Vector3.ZERO, Vector3(20.0, 0.0, 0.0))
	assert(second != null and second.object_id == 99, "destroyed launchers must leave collision immediately")
	print("ENTITY_HIT_INDEX_TEST_PASS")
	quit()
