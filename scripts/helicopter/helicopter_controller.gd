extends Node3D

const FLIGHT_MATH := preload("res://scripts/helicopter/flight_math.gd")

@export var terrain_path: NodePath = NodePath("../Terrain")
@export_group("Playful Flight Feel")
@export var acceleration := 68.0
@export var braking := 26.0
@export var drag := 10.0
@export var max_speed := 118.0
@export var terrain_clearance := 90.0
@export var min_terrain_clearance := 35.0
@export var max_terrain_clearance := 360.0
@export var climb_speed := 72.0
@export var altitude_response := 2.8
@export var terrain_height_response := 0.9
@export var terrain_height_deadband := 0.3
@export var maximum_terrain_follow_speed := 12.0
@export var yaw_speed_degrees := 82.0
@export var yaw_acceleration_degrees := 210.0
@export var yaw_braking_degrees := 125.0

@export_group("Visual Lean")
@export var forward_pitch_degrees := 13.0
@export var backward_pitch_degrees := 9.0
@export var strafe_bank_degrees := 15.0
@export var turn_bank_degrees := 11.0
@export var maximum_bank_degrees := 22.0
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
		velocity = velocity.move_toward(Vector3.ZERO, drag * delta)
		_yaw_velocity_degrees = move_toward(_yaw_velocity_degrees, 0.0, yaw_braking_degrees * delta)
		_update_visual(Vector2.ZERO, 0.0, delta)
		return
	var flight := GamepadInput.get_flight_vector()
	var right_stick := GamepadInput.get_aim_vector()
	var planar_input := get_planar_control(flight)
	if planar_input.length_squared() > 0.001:
		velocity += planar_input * acceleration * delta
	else:
		velocity = velocity.move_toward(Vector3.ZERO, braking * delta)
	velocity = velocity.move_toward(Vector3.ZERO, drag * delta)
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed
	position += velocity * delta
	position.x = clampf(position.x, -1950.0, 1950.0)
	position.z = clampf(position.z, -1950.0, 1950.0)
	var target_yaw_velocity := -right_stick.x * yaw_speed_degrees
	var yaw_change_rate := yaw_acceleration_degrees if absf(right_stick.x) > 0.01 else yaw_braking_degrees
	_yaw_velocity_degrees = move_toward(
		_yaw_velocity_degrees,
		target_yaw_velocity,
		yaw_change_rate * delta
	)
	rotation.y += deg_to_rad(_yaw_velocity_degrees) * delta
	_commanded_clearance = clampf(
		_commanded_clearance - right_stick.y * climb_speed * delta,
		min_terrain_clearance,
		max_terrain_clearance
	)
	if _terrain != null and _terrain.has_method("sample_height_world"):
		var raw_ground_height: float = _terrain.sample_height_world(position.x, position.z)
		_update_smoothed_ground_height(raw_ground_height, delta)
		var target_height := _smoothed_ground_height + _commanded_clearance
		position.y = lerpf(position.y, target_height, 1.0 - exp(-altitude_response * delta))
	_update_visual(flight, right_stick.x, delta)


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


func _update_visual(flight: Vector2, yaw_input: float, delta: float) -> void:
	if _visual == null:
		return
	var forward_amount := -flight.y
	var pitch_limit := forward_pitch_degrees if forward_amount >= 0.0 else backward_pitch_degrees
	# The helicopter faces local +X: Z is its pitch axis and X is its roll axis.
	var target_pitch := -forward_amount * pitch_limit
	var turn_amount := yaw_input
	if yaw_speed_degrees > 0.0:
		turn_amount = -_yaw_velocity_degrees / yaw_speed_degrees
	var target_bank := clampf(
		flight.x * strafe_bank_degrees + turn_amount * turn_bank_degrees,
		-maximum_bank_degrees,
		maximum_bank_degrees
	)
	var lean_weight := 1.0 - exp(-lean_response * delta)
	_visual.rotation.z = lerpf(_visual.rotation.z, deg_to_rad(target_pitch), lean_weight)
	_visual.rotation.x = lerpf(_visual.rotation.x, deg_to_rad(target_bank), lean_weight)
