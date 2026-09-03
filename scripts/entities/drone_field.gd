class_name DroneField
extends Node3D

## The raid, as the rest of the game sees it. Owns ten drones, gives each a
## mini-Raptor and an AABB that follows it every frame, picks their targets off
## the building index, and fires their bombs through the projectile manager --
## so a bomb hits a building through the same swept query and the same damage
## path as a shell.
##
## Mirrors launcher_field.gd. The AABB refresh is the one difference: launchers
## sit still and are indexed once; drones re-register every frame. Ten entities
## re-registering per frame is nothing, and it keeps one collision path where a
## second sphere index would drift.

const DRONE := preload("res://scripts/entities/drone.gd")
const ENTITY_HIT_INDEX := preload("res://scripts/entities/entity_hit_index.gd")
const BOMB_FLIGHT := preload("res://scripts/weapons/bomb_flight.gd")
const BOMB_PROFILE := preload("res://scripts/weapons/bomb_damage_profile.gd")
const JET_SCENE := preload("res://3dassets/f-22_raptor_-_fighter_jet_-_free.glb")

signal bomb_released(round_data: RefCounted)

## Launchers number from 1. Starting here keeps the two id spaces apart, so
## the impact handler can route by id without asking both fields.
const FIRST_ID := 100000
## About 40% of the Raptor's 13.56 -- clearly smaller, still an aircraft.
const DRONE_WINGSPAN_M := 5.5
## Spawn on the +X side, spread across this arc. Seaward for Surfers, where the
## launchers sit along a beach at x near zero.
const SPAWN_ARC_DEGREES := 120.0
const SPAWN_RADIUS_FRACTION := 0.85
## Half-extents of the collision box round each drone, in metres. Generous
## against a 5.5 m span: a drone that is hard to hit because its box is exact
## is not fun, and the rocket trail will hide the difference.
const HIT_HALF_EXTENTS := Vector3(4.0, 2.0, 4.0)

var projectile_manager: Node3D
var building_index: RefCounted
var hit_index := ENTITY_HIT_INDEX.new()

var _drones: Array = []
var _visuals: Dictionary = {}
var _city_centre := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _bomb_sequence := 0
var _bomb_profile: Resource


func _ready() -> void:
	_rng.randomize()
	_bomb_profile = BOMB_PROFILE.new()


func populate(count: int, half_extent: float, city_centre: Vector3) -> void:
	clear()
	_city_centre = city_centre
	if _bomb_profile == null:
		_bomb_profile = BOMB_PROFILE.new()
	var radius := half_extent * SPAWN_RADIUS_FRACTION
	var arc := deg_to_rad(SPAWN_ARC_DEGREES)
	for index in range(count):
		var fraction := (float(index) + 0.5) / float(maxi(count, 1))
		var angle := (fraction - 0.5) * arc
		var drone = DRONE.new()
		drone.id = FIRST_ID + index
		drone.position = city_centre + Vector3(cos(angle) * radius, DRONE.INBOUND_ALTITUDE, sin(angle) * radius)
		drone.heading = atan2(city_centre.x - drone.position.x, -(city_centre.z - drone.position.z))
		drone.speed = DRONE.DRONE_CRUISE_MPS
		drone.velocity = drone.nose() * drone.speed
		_drones.append(drone)
		_visuals[drone.id] = _spawn_visual(drone)
		_register(drone)


func clear() -> void:
	hit_index.clear()
	for visual in _visuals.values():
		if is_instance_valid(visual):
			visual.queue_free()
	_visuals.clear()
	_drones.clear()


func drone_count() -> int:
	var alive := 0
	for drone in _drones:
		if drone.state != DRONE.State.DESTROYED:
			alive += 1
	return alive


func drones() -> Array:
	return _drones


func query_segment(from: Vector3, to: Vector3) -> RefCounted:
	return hit_index.query_segment(from, to)


func destroy_drone(entity_id: int) -> Variant:
	for drone in _drones:
		if drone.id != entity_id or drone.state == DRONE.State.DESTROYED:
			continue
		var where: Vector3 = drone.position
		drone.destroy()
		hit_index.remove_entity(entity_id)
		return where
	return null


## Driven by main, so the raid pauses with the game and the player's position
## is the one the camera is already using this frame.
func update(delta: float, player_position: Vector3, player_nose: Vector3) -> void:
	for drone in _drones:
		if drone.state == DRONE.State.DESTROYED:
			# Falling wreckage: keep moving it and keep the visual on it.
			drone.update(delta, player_position, player_nose, _city_centre, _rng)
			_place_visual(drone)
			continue
		if drone.wants_target() and building_index != null:
			_assign_target(drone)
		if drone.update(delta, player_position, player_nose, _city_centre, _rng):
			_release_bomb(drone)
		_register(drone)
		_place_visual(drone)


## The tallest building within the drone's forward cone, so raids go for the
## skyline rather than a car park. Falls back to the tallest anywhere in range
## if nothing is ahead.
func _assign_target(drone) -> void:
	var here := Vector2(drone.position.x, drone.position.z)
	var candidates: Array = building_index.buildings_near(here, DRONE.ATTACK_ENTRY_RANGE)
	if candidates.is_empty():
		return
	var nose: Vector3 = drone.nose()
	var best: Dictionary = {}
	var best_height := -1.0
	var ahead_only := true
	for _pass_index in range(2):
		for entry in candidates:
			var to_target: Vector3 = entry["position"] - drone.position
			to_target.y = 0.0
			if ahead_only and to_target.normalized().dot(nose) < 0.5:
				continue
			if float(entry["height"]) > best_height:
				best_height = float(entry["height"])
				best = entry
		if not best.is_empty():
			break
		ahead_only = false
	if best.is_empty():
		return
	drone.assign_target(int(best["handle"]), best["position"])


func _release_bomb(drone) -> void:
	if projectile_manager == null:
		return
	var flight = BOMB_FLIGHT.new()
	_bomb_sequence += 1
	var round_data: RefCounted = projectile_manager.acquire_round()
	round_data.initialise(
		_bomb_sequence,
		drone.position,
		drone.velocity.normalized() if not drone.velocity.is_zero_approx() else Vector3.DOWN,
		flight.release_velocity(drone.velocity),
		false,
		_bomb_profile,
		"bomb"
	)
	round_data.flight = flight
	projectile_manager.spawn(round_data)
	bomb_released.emit(round_data)


func _register(drone) -> void:
	hit_index.add_entity(drone.id, AABB(drone.position - HIT_HALF_EXTENTS, HIT_HALF_EXTENTS * 2.0))


func _spawn_visual(drone) -> Node3D:
	var anchor := Node3D.new()
	anchor.name = "Drone_%d" % drone.id
	add_child(anchor)
	var model: Node3D = JET_SCENE.instantiate()
	anchor.add_child(model)
	# Same measure-and-scale the hero jet uses, so the GLB's native scale is
	# never a magic number here either.
	var bounds := _bounds_relative_to(anchor)
	if bounds.size.z > 0.001:
		model.scale = Vector3.ONE * (DRONE_WINGSPAN_M / bounds.size.z)
	for child in model.find_children("*", "Node3D", true, false):
		if String(child.name).to_lower().contains("landingon"):
			(child as Node3D).visible = false
	return anchor


func _place_visual(drone) -> void:
	var anchor: Node3D = _visuals.get(drone.id)
	if anchor == null or not is_instance_valid(anchor):
		return
	anchor.global_position = drone.position
	var nose: Vector3 = drone.velocity.normalized() if not drone.velocity.is_zero_approx() else drone.nose()
	var right: Vector3 = nose.cross(Vector3.UP)
	if right.is_zero_approx():
		right = Vector3.RIGHT
	right = right.normalized()
	var up: Vector3 = right.cross(nose).normalized()
	var attitude := Basis(nose, up, right).orthonormalized()
	anchor.global_basis = attitude.rotated(nose, drone.bank())


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
