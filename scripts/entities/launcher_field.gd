class_name LauncherField
extends Node3D

const LAUNCHER_SCENE := preload("res://assets/models/mk4b_launcher.glb")
const ENTITY_HIT_INDEX := preload("res://scripts/entities/entity_hit_index.gd")
const LAYOUT := preload("res://scripts/entities/launcher_layout.gd")

const MODEL_SCALE := 6.0
const BEACH_HEADING_DEGREES := 90.0
const TARGET_RING_COLOUR := Color(1.0, 0.32, 0.06, 0.82)

var hit_index := ENTITY_HIT_INDEX.new()
var _launchers: Dictionary = {}
var _next_id := 1
var _marker_time := 0.0
var _target_ring_material: StandardMaterial3D


func _ready() -> void:
	_target_ring_material = StandardMaterial3D.new()
	_target_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_target_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_target_ring_material.albedo_color = TARGET_RING_COLOUR
	_target_ring_material.emission_enabled = true
	_target_ring_material.emission = Color(1.0, 0.18, 0.025)
	_target_ring_material.emission_energy_multiplier = 2.2
	set_process(false)


func _process(delta: float) -> void:
	_marker_time += delta
	var pulse := 1.0 + sin(_marker_time * 3.8) * 0.055
	for launcher: Dictionary in _launchers.values():
		var marker: MeshInstance3D = launcher["marker"]
		if is_instance_valid(marker):
			marker.scale = Vector3(pulse, 1.0, pulse)


func populate(region_id: String, terrain: Node) -> void:
	clear()
	if terrain == null:
		return
	for beach_position in LAYOUT.positions_for(region_id):
		_spawn_launcher(beach_position, terrain)


func clear() -> void:
	hit_index.clear()
	for launcher: Dictionary in _launchers.values():
		var node: Node3D = launcher["node"]
		if is_instance_valid(node):
			node.queue_free()
	_launchers.clear()
	set_process(false)


func launcher_count() -> int:
	return _launchers.size()


## The SAM sites, as positions. Added so the target tracker can see them
## without the launcher field learning what a target tracker is.
func launcher_positions() -> Array:
	var out := []
	for entity_id in _launchers:
		var launcher: Dictionary = _launchers[entity_id]
		var node: Node3D = launcher["node"]
		if not is_instance_valid(node):
			continue
		out.append({"id": int(entity_id), "position": node.global_position})
	return out


func query_segment(from: Vector3, to: Vector3) -> RefCounted:
	return hit_index.query_segment(from, to)


func destroy_launcher(entity_id: int) -> Variant:
	if not _launchers.has(entity_id):
		return null
	var launcher: Dictionary = _launchers[entity_id]
	var node: Node3D = launcher["node"]
	var explosion_position: Vector3 = launcher["bounds"].get_center()
	hit_index.remove_entity(entity_id)
	_launchers.erase(entity_id)
	if _launchers.is_empty():
		set_process(false)
	if is_instance_valid(node):
		node.visible = false
		node.queue_free()
	return explosion_position


func _spawn_launcher(beach_position: Vector2, terrain: Node) -> void:
	var target := Node3D.new()
	target.name = "Launcher_%02d" % _next_id
	target.rotation_degrees.y = BEACH_HEADING_DEGREES
	add_child(target)

	var visual: Node3D = LAUNCHER_SCENE.instantiate()
	visual.scale = Vector3.ONE * MODEL_SCALE
	target.add_child(visual)
	var initial_bounds := _bounds_relative_to(target)
	visual.position.y -= initial_bounds.position.y

	var ground_height := 0.0
	if terrain.has_method("sample_mesh_height"):
		ground_height = float(terrain.sample_mesh_height(beach_position.x, beach_position.y))
	elif terrain.has_method("sample_height_world"):
		ground_height = float(terrain.sample_height_world(beach_position.x, beach_position.y))
	target.position = Vector3(beach_position.x, ground_height, beach_position.y)

	var local_bounds := _bounds_relative_to(target)
	var world_bounds: AABB = target.global_transform * local_bounds
	var marker := _add_target_ring(target, local_bounds)
	var entity_id := _next_id
	_next_id += 1
	hit_index.add_entity(entity_id, world_bounds)
	_launchers[entity_id] = {"node": target, "bounds": world_bounds, "marker": marker}
	set_process(true)


func _add_target_ring(target: Node3D, bounds: AABB) -> MeshInstance3D:
	var ring_mesh := TorusMesh.new()
	var radius := maxf(bounds.size.x, bounds.size.z) * 0.55 + 1.8
	ring_mesh.inner_radius = radius
	ring_mesh.outer_radius = radius + 0.42
	ring_mesh.rings = 8
	ring_mesh.ring_segments = 32
	var ring := MeshInstance3D.new()
	ring.name = "ArcadeTargetRing"
	ring.mesh = ring_mesh
	ring.material_override = _target_ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(bounds.get_center().x, 0.18, bounds.get_center().z)
	target.add_child(ring)
	return ring


func _bounds_relative_to(root: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		var relative := root.global_transform.affine_inverse() * instance.global_transform
		var transformed: AABB = relative * instance.get_aabb()
		bounds = transformed if not found else bounds.merge(transformed)
		found = true
	return bounds
