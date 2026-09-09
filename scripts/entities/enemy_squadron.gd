extends Node3D

## A flight of enemy Raptors, spawned as a formation on a random bearing.
##
## Deliberately shaped like `drone_field.gd`, and for the same reasons: one hit
## index, one visual pool, one destruction path. The only real differences are
## that these are jets rather than drones, with weapons owned by EnemyCombat,
## and that they report themselves as `TargetTracker` contacts so the
## visor and the scope can see them without knowing what a squadron is.

const ENEMY := preload("res://scripts/entities/enemy_jet.gd")
const ENTITY_HIT_INDEX := preload("res://scripts/entities/entity_hit_index.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const JET_SCENE := preload("res://assets/models/f-22_raptor_-_fighter_jet_-_free.glb")
const VAPOR := preload("res://scripts/jet/wing_vapor.gd")

## Above drone_field.FIRST_ID (100000) so the two never share an entity id.
const FIRST_ID := 200000
const JET_WINGSPAN_M := 13.6
const HIT_HALF_EXTENTS := Vector3(8.0, 3.0, 8.0)

const SPAWN_RANGE_M := 16000.0
const SPAWN_ALTITUDE_MIN_M := 2000.0
const SPAWN_ALTITUDE_MAX_M := 6000.0
const FORMATION_SPACING_M := 300.0
const FIRST_ENCOUNTER_SECONDS := 20.0
const MISSILE_WARNING_RANGE_M := 4500.0

var hit_index := ENTITY_HIT_INDEX.new()

var _jets: Array = []
var _visuals := {}
var _next_id := FIRST_ID
var _next_encounter_in := FIRST_ENCOUNTER_SECONDS
var kills := 0
var waves := 0
var ground_height := Callable()


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
	_next_encounter_in = FIRST_ENCOUNTER_SECONDS
	kills = 0
	waves = 0


## Give the pilot time to settle, then keep a small fight within radar range.
## Countdown only between waves, so a quick kill still earns a short breather.
func advance_encounters(delta: float, around: Vector3, forward: Vector3) -> void:
	if jet_count() > 0:
		return
	_next_encounter_in -= delta
	if _next_encounter_in <= 0.0:
		spawn(randi_range(1, 2), around, forward)
		waves += 1
		_next_encounter_in = randf_range(30.0, 45.0)


## A forward direction requests a nearby dogfight encounter. Without one,
## retain the distant, all-bearing formation spawn used by scenario tools.
func spawn(count: int, around: Vector3, forward := Vector3.ZERO) -> void:
	var bearing := randf() * TAU
	var distance := SPAWN_RANGE_M
	if not forward.is_zero_approx():
		bearing = atan2(forward.x, -forward.z) + randf_range(-0.9, 0.9)
		distance = randf_range(4500.0, 6500.0)
	var lead := around + Vector3(sin(bearing), 0.0, -cos(bearing)) * distance
	lead.y = randf_range(SPAWN_ALTITUDE_MIN_M, SPAWN_ALTITUDE_MAX_M)
	if not forward.is_zero_approx():
		lead.y = maxf(around.y + randf_range(-300.0, 600.0), ENEMY.MIN_ALTITUDE_M)
	# Across the line of approach, so the formation is line abreast to the
	# player rather than nose to tail.
	var across := Vector3(cos(bearing), 0.0, sin(bearing))
	for i in range(count):
		var jet = ENEMY.new()
		jet.configure(randi())
		jet.id = _next_id
		_next_id += 1
		# The lead in the middle, wingmen stepped out either side.
		var slot := float(i) - float(count - 1) * 0.5
		jet.formation_offset = across * slot * FORMATION_SPACING_M
		jet.position = lead + jet.formation_offset
		jet.position.y = maxf(jet.position.y, _terrain_floor(jet.position))
		jet.heading = atan2(around.x - jet.position.x, -(around.z - jet.position.z))
		jet.speed = ENEMY.ENEMY_CRUISE_MPS
		_jets.append(jet)
		_register(jet)
		_spawn_visual(jet)


func update(delta: float, player_position: Vector3, player_nose: Vector3, rounds: Array = []) -> void:
	for jet in _jets.duplicate():
		if jet.state == ENEMY.State.DESTROYED:
			continue
		var floor_m := maxf(_terrain_floor(jet.position), _terrain_floor(jet.position + jet.nose() * jet.speed * 3.0))
		var previous_velocity: Vector3 = jet.velocity
		jet.update(delta, player_position, player_nose, _incoming_missile(jet, rounds), floor_m)
		if jet.has_departed():
			_remove_jet(jet)
			continue
		_register(jet)
		_place_visual(jet)
		var vapor: Node3D = _visuals[jet.id].get_node("WingVapor")
		# Enemy flight is kinematic; curvature supplies its visual load estimate.
		var acceleration: float = (jet.velocity - previous_velocity).length() / maxf(delta, 0.001) if previous_velocity.length() > 1 else 0.0
		var load_g := sqrt(1.0 + pow(acceleration / 9.80665, 2))
		vapor.set_flight(jet.speed, load_g, deg_to_rad(4 + load_g * 1.5))


func _terrain_floor(point: Vector3) -> float:
	return maxf(ENEMY.MIN_ALTITUDE_M, float(ground_height.call(point)) + 250.0) if ground_height.is_valid() else ENEMY.MIN_ALTITUDE_M


func _incoming_missile(jet, rounds: Array) -> Variant:
	var nearest: Variant = null
	var nearest_distance := MISSILE_WARNING_RANGE_M
	for round_data in rounds:
		if round_data.weapon_source != "missile" or round_data.flight == null or round_data.flight.target_handle != jet.id:
			continue
		var offset: Vector3 = jet.position - round_data.position
		if offset.length() < nearest_distance and (round_data.velocity - jet.velocity).dot(offset) > 0.0:
			nearest = round_data.position
			nearest_distance = offset.length()
	return nearest


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
		kills += 1
		_remove_jet(jet)
		return jet
	return null


func _remove_jet(jet) -> void:
	hit_index.remove_entity(jet.id)
	_jets.erase(jet)
	if _visuals.has(jet.id):
		var node: Node3D = _visuals[jet.id]
		if is_instance_valid(node):
			node.queue_free()
		_visuals.erase(jet.id)


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
	var vapor := VAPOR.new()
	vapor.name = "WingVapor"
	anchor.add_child(vapor)
	vapor.build(model)
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
