extends Node3D

const FLIGHT_MATH := preload("res://scripts/helicopter/flight_math.gd")

@export var terrain_path: NodePath = NodePath("../Terrain")
@export_group("Playful Flight Feel")
@export var acceleration := 68.0
@export var braking := 110.0
@export var max_speed := 118.0
@export var terrain_clearance := 90.0
@export var min_terrain_clearance := 35.0
@export var max_terrain_clearance := 360.0
@export var ascent_speed := 72.0
@export var descent_speed := 48.0
@export var altitude_response := 2.8
@export var terrain_height_response := 0.9
@export var terrain_height_deadband := 0.3
@export var maximum_terrain_follow_speed := 12.0
@export var yaw_speed_degrees := 110.0
@export var yaw_acceleration_degrees := 210.0
@export var yaw_braking_degrees := 125.0

@export_group("Visual Lean")
@export var max_tilt_degrees := 30.0
@export var turn_bank_degrees := 11.0
@export var maximum_bank_degrees := 34.0
@export var lean_response := 4.8

var velocity := Vector3.ZERO
var _terrain: Node
var _visual: Node3D
var _commanded_clearance := 90.0
var _yaw_velocity_degrees := 0.0
var _smoothed_ground_height := 0.0
var _ground_height_initialized := false


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path)
	_commanded_clearance = terrain_clearance
	call_deferred("_find_visual")


func _physics_process(delta: float) -> void:
	if not GamepadInput.is_controller_ready():
		velocity = velocity.move_toward(Vector3.ZERO, braking * delta)
		_yaw_velocity_degrees = move_toward(_yaw_velocity_degrees, 0.0, yaw_braking_degrees * delta)
		_update_visual(delta)
		return
	# DJI Mode 2: the left stick is throttle and yaw, the right stick is the
	# cyclic that translates the aircraft.
	var collective_yaw := GamepadInput.get_collective_yaw()
	var cyclic := GamepadInput.get_cyclic()
	var planar_input := get_planar_control(cyclic)
	# The stick commands a speed rather than a push. Centring it brakes hard to a
	# stop and holds, the way a drone in position hold does, instead of coasting.
	velocity = FLIGHT_MATH.approach_velocity(
		velocity,
		planar_input * max_speed,
		acceleration,
		braking,
		delta
	)
	position += velocity * delta
	position.x = clampf(position.x, -1950.0, 1950.0)
	position.z = clampf(position.z, -1950.0, 1950.0)
	var target_yaw_velocity := -collective_yaw.x * yaw_speed_degrees
	var yaw_change_rate := yaw_acceleration_degrees if absf(collective_yaw.x) > 0.01 else yaw_braking_degrees
	_yaw_velocity_degrees = move_toward(
		_yaw_velocity_degrees,
		target_yaw_velocity,
		yaw_change_rate * delta
	)
	rotation.y += deg_to_rad(_yaw_velocity_degrees) * delta
	# A drone climbs faster than it sinks, so the throttle is asymmetric.
	var throttle_speed := ascent_speed if collective_yaw.y < 0.0 else descent_speed
	_commanded_clearance = clampf(
		_commanded_clearance - collective_yaw.y * throttle_speed * delta,
		min_terrain_clearance,
		max_terrain_clearance
	)
	if _terrain != null and _terrain.has_method("sample_height_world"):
		var raw_ground_height: float = _terrain.sample_height_world(position.x, position.z)
		_update_smoothed_ground_height(raw_ground_height, delta)
		var target_height := _smoothed_ground_height + _commanded_clearance
		position.y = lerpf(position.y, target_height, 1.0 - exp(-altitude_response * delta))
	_update_visual(delta)


func get_planar_control(flight: Vector2) -> Vector3:
	return FLIGHT_MATH.get_planar_control(basis, flight)


func reset_altitude_smoothing() -> void:
	_ground_height_initialized = false


func _update_smoothed_ground_height(raw_height: float, delta: float) -> void:
	if not _ground_height_initialized:
		_smoothed_ground_height = raw_height
		_ground_height_initialized = true
		return
	var difference := raw_height - _smoothed_ground_height
	if absf(difference) <= terrain_height_deadband:
		return
	var filtered_target := raw_height - signf(difference) * terrain_height_deadband
	var response_weight := 1.0 - exp(-terrain_height_response * delta)
	var response_height := lerpf(_smoothed_ground_height, filtered_target, response_weight)
	_smoothed_ground_height = move_toward(
		_smoothed_ground_height,
		response_height,
		maximum_terrain_follow_speed * delta
	)


func _find_visual() -> void:
	_visual = get_node_or_null("HeroHelicopter")


## The tilt is the movement, not a decoration on top of it: it comes from the
## velocity the aircraft is actually carrying, so braking shows the nose-up flare
## a drone makes when it stops itself.
func _update_visual(delta: float) -> void:
	if _visual == null:
		return
	var body_velocity := FLIGHT_MATH.get_body_velocity(basis, velocity)
	var forward_amount := 0.0
	var lateral_amount := 0.0
	if max_speed > 0.0:
		forward_amount = clampf(body_velocity.x / max_speed, -1.0, 1.0)
		lateral_amount = clampf(body_velocity.y / max_speed, -1.0, 1.0)
	# The helicopter faces local +X: Z is its pitch axis and X is its roll axis.
	var target_pitch := -forward_amount * max_tilt_degrees
	var turn_amount := 0.0
	if yaw_speed_degrees > 0.0:
		turn_amount = -_yaw_velocity_degrees / yaw_speed_degrees
	var target_bank := clampf(
		lateral_amount * max_tilt_degrees + turn_amount * turn_bank_degrees,
		-maximum_bank_degrees,
		maximum_bank_degrees
	)
	var lean_weight := 1.0 - exp(-lean_response * delta)
	_visual.rotation.z = lerpf(_visual.rotation.z, deg_to_rad(target_pitch), lean_weight)
	_visual.rotation.x = lerpf(_visual.rotation.x, deg_to_rad(target_bank), lean_weight)


## Lets the active theatre swap the height source. Packaged and streamed
## terrain both expose sample_height_world(), so terrain-following works
## against either without knowing which is loaded.
func set_terrain(node: Node) -> void:
	_terrain = node
