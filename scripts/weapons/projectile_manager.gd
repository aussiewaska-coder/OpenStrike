extends Node3D

# Fixed-step integration of every live round. No RigidBody3D, no physics
# server: at 625 RPM with ~2 s flight times there are around twenty of these
# alive, and each one advances through the same Ballistics.advance() the HUD
# pipper uses (spec sections 15, 16, 67).

signal projectile_impacted(hit_result: RefCounted, round_data: RefCounted)
signal projectile_expired(round_data: RefCounted)

const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")
const CANNON_ROUND := preload("res://scripts/weapons/cannon_round.gd")

var profile: Resource
var hit_query: RefCounted = null
## The same Ballistics instance the attack reticle solves with.
var ballistics: RefCounted = null

var active_rounds: Array[RefCounted] = []

var _accumulator := 0.0
var _pool: Array[RefCounted] = []


func _ready() -> void:
	if profile == null:
		profile = load("res://scripts/weapons/ballistic_profile.gd").new()
	if ballistics == null:
		ballistics = BALLISTICS.new()
		ballistics.adopt(profile)


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if active_rounds.is_empty():
		_accumulator = 0.0
		return
	var fixed_step: float = ballistics.step_seconds
	_accumulator += delta
	# Bound catch-up so a frame hitch cannot burn the whole trajectory at once.
	var maximum_steps := 8
	while _accumulator >= fixed_step and maximum_steps > 0:
		_accumulator -= fixed_step
		maximum_steps -= 1
		_advance_all(fixed_step)
	if maximum_steps == 0:
		_accumulator = 0.0


func spawn(round_data: RefCounted) -> void:
	active_rounds.append(round_data)


func acquire_round() -> RefCounted:
	if _pool.is_empty():
		return CANNON_ROUND.new()
	return _pool.pop_back()


func clear() -> void:
	for round_data in active_rounds:
		_pool.append(round_data)
	active_rounds.clear()
	_accumulator = 0.0


func _advance_all(fixed_step: float) -> void:
	var survivors: Array[RefCounted] = []
	for round_data in active_rounds:
		if _advance_round(round_data, fixed_step):
			survivors.append(round_data)
		else:
			_pool.append(round_data)
	active_rounds = survivors


func _advance_round(round_data: RefCounted, fixed_step: float) -> bool:
	# Each round flies through the model it carries. A shell has none and takes
	# the shared ballistics; a rocket brings a motor. The manager stays the one
	# place that owns pooling and the swept hit query.
	var flight: RefCounted = round_data.flight if round_data.flight != null else ballistics
	var stepped: Array = flight.advance(
		round_data.position, round_data.velocity, fixed_step, round_data.age
	)
	var next_position: Vector3 = stepped[0]
	round_data.previous_position = round_data.position
	round_data.velocity = stepped[1]
	if hit_query != null:
		# Continuous segment intersection, so an 805 m/s round cannot tunnel
		# through a 16 m thick facade between steps.
		var result: RefCounted = hit_query.query_segment(round_data.position, next_position)
		if result != null and result.hit:
			round_data.position = result.position
			projectile_impacted.emit(result, round_data)
			return false
	round_data.distance += round_data.position.distance_to(next_position)
	round_data.position = next_position
	round_data.age += fixed_step
	if round_data.age >= flight.envelope_seconds() or round_data.distance >= flight.envelope_metres():
		projectile_expired.emit(round_data)
		return false
	return true
