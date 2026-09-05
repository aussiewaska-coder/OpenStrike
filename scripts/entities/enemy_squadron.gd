extends Node3D

## A flight of enemy Raptors, spawned as a formation on a random bearing.
##
## Deliberately shaped like `drone_field.gd`, and for the same reasons: one hit
## index, one visual pool, one destruction path. The only real differences are
## that these are jets rather than drones, that they carry no weapons in this
## phase, and that they report themselves as `TargetTracker` contacts so the
## visor and the scope can see them without knowing what a squadron is.

const ENEMY := preload("res://scripts/entities/enemy_jet.gd")
const ENTITY_HIT_INDEX := preload("res://scripts/entities/entity_hit_index.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const JET_SCENE := preload("res://3dassets/f-22_raptor_-_fighter_jet_-_free.glb")

## Above drone_field.FIRST_ID (100000) so the two never share an entity id.
const FIRST_ID := 200000
const JET_WINGSPAN_M := 13.6
const HIT_HALF_EXTENTS := Vector3(8.0, 3.0, 8.0)

const SPAWN_RANGE_M := 16000.0
const SPAWN_ALTITUDE_MIN_M := 2000.0
const SPAWN_ALTITUDE_MAX_M := 6000.0
const FORMATION_SPACING_M := 300.0

var hit_index := ENTITY_HIT_INDEX.new()

var _jets: Array = []
var _visuals := {}
var _next_id := FIRST_ID


func jets() -> Array:
	return _jets


func jet_count() -> int:
	var alive := 0
	for jet in _jets:
		if jet.state != ENEMY.State.DESTROYED:
			alive += 1
	return alive


func _ready() -> void:
	# update() places the models at render-frame positions shared with the HUD.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func clear() -> void:
	for id in _visuals:
		var node: Node3D = _visuals[id]
		if is_instance_valid(node):
			node.queue_free()
	_visuals.clear()
	_jets.clear()
	hit_index.clear()


## `around` is the player. The squadron arrives on a random bearing at
## SPAWN_RANGE_M, which is outside the default scope range on purpose: it must
## be seen coming.
func spawn(count: int, around: Vector3) -> void:
	var bearing := randf() * TAU
	var lead := around + Vector3(sin(bearing), 0.0, -cos(bearing)) * SPAWN_RANGE_M
	lead.y = randf_range(SPAWN_ALTITUDE_MIN_M, SPAWN_ALTITUDE_MAX_M)
	# Across the line of approach, so the formation is line abreast to the
	# player rather than nose to tail.
	var across := Vector3(cos(bearing), 0.0, sin(bearing))
	for i in range(count):
		var jet = ENEMY.new()
		jet.id = _next_id
		_next_id += 1
		# The lead in the middle, wingmen stepped out either side.
		var slot := float(i) - float(count - 1) * 0.5
		jet.formation_offset = across * slot * FORMATION_SPACING_M
		jet.position = lead + jet.formation_offset
		jet.position.y = maxf(jet.position.y, ENEMY.MIN_ALTITUDE_M)
		jet.heading = atan2(around.x - jet.position.x, -(around.z - jet.position.z))
		jet.speed = ENEMY.ENEMY_CRUISE_MPS
		_jets.append(jet)
		_register(jet)
		_spawn_visual(jet)


func update(delta: float, player_position: Vector3, player_nose: Vector3) -> void:
	for jet in _jets:
		if jet.state == ENEMY.State.DESTROYED:
			continue
		jet.update(delta, player_position, player_nose)
		_register(jet)
		_place_visual(jet)


## What the tracker consumes. The squadron does not know what a visor is.
func contacts() -> Array:
	var out := []
	for jet in _jets:
		if jet.state == ENEMY.State.DESTROYED:
			continue
		out.append(TRACKER.contact(
			jet.id, TRACKER.Kind.AIR_JET, jet.position, jet.velocity, "RAPTOR"
		))
	return out


func query_segment(from: Vector3, to: Vector3) -> RefCounted:
	return hit_index.query_segment(from, to)


func destroy_jet(entity_id: int) -> Variant:
	for jet in _jets:
		if jet.id != entity_id:
			continue
		jet.state = ENEMY.State.DESTROYED
		hit_index.remove_entity(entity_id)
		if _visuals.has(entity_id):
			var node: Node3D = _visuals[entity_id]
			if is_instance_valid(node):
				node.queue_free()
			_visuals.erase(entity_id)
		return jet
	return null


func _register(jet) -> void:
	hit_index.add_entity(jet.id, AABB(jet.position - HIT_HALF_EXTENTS, HIT_HALF_EXTENTS * 2.0))


## The same anchor-and-measure the drone field uses, so the GLB's native scale
## is never a magic number here either.
func _spawn_visual(jet) -> Node3D:
	var anchor := Node3D.new()
	anchor.name = "EnemyJet_%d" % jet.id
	add_child(anchor)
	var model: Node3D = JET_SCENE.instantiate()
	anchor.add_child(model)
	var bounds := _bounds_relative_to(anchor)
	if bounds.size.z > 0.001:
		model.scale = Vector3.ONE * (JET_WINGSPAN_M / bounds.size.z)
	for child in model.find_children("*", "Node3D", true, false):
		if String(child.name).to_lower().contains("landingon"):
			(child as Node3D).visible = false
	_visuals[jet.id] = anchor
	_place_visual(jet)
	return anchor


func _place_visual(jet) -> void:
	var anchor: Node3D = _visuals.get(jet.id)
	if anchor == null or not is_instance_valid(anchor):
		return
	anchor.global_position = jet.position
	var nose: Vector3 = jet.velocity.normalized() if not jet.velocity.is_zero_approx() else jet.nose()
	var right: Vector3 = nose.cross(Vector3.UP)
	if right.is_zero_approx():
		right = Vector3.RIGHT
	right = right.normalized()
	var up: Vector3 = right.cross(nose).normalized()
	var attitude := Basis(nose, up, right).orthonormalized()
	anchor.global_basis = attitude.rotated(nose, jet.bank())


func _bounds_relative_to(root: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		var box := mesh.mesh.get_aabb()
		var transformed := root.global_transform.affine_inverse() * mesh.global_transform
		var world_box := transformed * box
		bounds = world_box if not found else bounds.merge(world_box)
		found = true
	return bounds
