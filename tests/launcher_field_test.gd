extends SceneTree

const FIELD := preload("res://scripts/entities/launcher_field.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")
const LAYOUT := preload("res://scripts/entities/launcher_layout.gd")


class FakeTerrain extends Node:
	func sample_mesh_height(_world_x: float, _world_z: float) -> float:
		return 2.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var terrain := FakeTerrain.new()
	root.add_child(terrain)
	var field := FIELD.new()
	root.add_child(field)
	field.populate("au_qld_surfers", terrain)
	assert(field.launcher_count() == 6, "six clusters must each contain one ground target")
	assert(field.hit_index.entity_count() == 6, "every target must have projectile collision")
	var markers := field.find_children("ArcadeTargetRing", "MeshInstance3D", true, false)
	assert(markers.size() == 6, "every target must have one arcade target ring")
	var marker_bounds: AABB = (markers[0] as MeshInstance3D).get_aabb()
	assert(marker_bounds.size.y < marker_bounds.size.x * 0.2, "target rings must lie flat on the beach")

	var first: Vector3 = field.launcher_positions()[0].position
	var hit: RefCounted = field.query_segment(
		first + Vector3.UP * 100.0,
		first + Vector3.DOWN * 100.0
	)
	assert(hit != null and hit.object_type == HIT.ObjectKind.ENTITY, "a cannon segment must hit the launcher")
	var explosion_position: Variant = field.destroy_launcher(hit.object_id)
	assert(explosion_position is Vector3, "a destroyed launcher must return its explosion origin")
	assert(field.launcher_count() == 5, "one hit must remove exactly one launcher")
	assert(field.hit_index.entity_count() == 5, "destroyed launchers must stop blocking projectiles")

	field.clear()
	field.queue_free()
	terrain.queue_free()
	print("LAUNCHER_FIELD_TEST_PASS")
	quit()
