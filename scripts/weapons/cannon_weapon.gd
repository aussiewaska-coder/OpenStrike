extends Node3D

# Trigger, ammunition and rate of fire for the 30 mm chin gun. Physical button
# mapping stays in the input layer: this asks GamepadInput.is_cannon_firing()
# and nothing else, so the cannon survives a remap (spec section 4).

signal round_fired(round_data: RefCounted)
signal firing_started
signal firing_stopped
signal ammo_changed(current: int, maximum: int)
signal ammo_empty

const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")
const CANNON_AIM := preload("res://scripts/weapons/cannon_aim.gd")

@export var profile: Resource
@export var round_profile: Resource

var aim: RefCounted
var ballistics: RefCounted
var gun_mount: Node3D
var projectile_manager: Node3D
var carrier: Node3D
## (world_x, world_z) -> terrain height, for the pipper's ground march.
var ground_height := Callable()
var hit_query: RefCounted = null

var ammo_remaining := 0
var is_firing := false
var continuous_fire_time := 0.0
var rounds_in_current_burst := 0
var time_since_last_shot := 999.0

var _shot_accumulator := 0.0
var _sequence := 0
var _tracer_counter := 0


func _ready() -> void:
	if profile == null:
		profile = load("res://scripts/weapons/ballistic_profile.gd").new()
	if round_profile == null:
		round_profile = load("res://scripts/weapons/cannon_round_profile.gd").new()
	aim = CANNON_AIM.new()
	if ballistics == null:
		ballistics = BALLISTICS.new()
		ballistics.adopt(profile)
	ammo_remaining = profile.ammo_capacity
	ammo_changed.emit(ammo_remaining, profile.ammo_capacity)


func _physics_process(delta: float) -> void:
	_update_aim(delta)
	_update_trigger(delta)


func _update_aim(delta: float) -> void:
	if gun_mount == null or carrier == null:
		return
	aim.update(delta, gun_mount.get_muzzle_transform().origin, carrier.global_rotation.y)
	gun_mount.apply_aim(aim.yaw_degrees, aim.pitch_degrees)


func _update_trigger(delta: float) -> void:
	time_since_last_shot += delta
	var wants_fire := _trigger_held() and ammo_remaining > 0
	if wants_fire and not is_firing:
		is_firing = true
		rounds_in_current_burst = 0
		continuous_fire_time = 0.0
		# Prime the accumulator so the first round leaves on the same frame the
		# trigger is pulled rather than one shot interval later.
		_shot_accumulator = profile.shot_interval()
		firing_started.emit()
	elif not wants_fire and is_firing:
		is_firing = false
		continuous_fire_time = 0.0
		firing_stopped.emit()
	if not is_firing:
		return
	continuous_fire_time += delta
	_shot_accumulator += delta
	var interval: float = profile.shot_interval()
	var fired_this_frame := 0
	while _shot_accumulator >= interval and fired_this_frame < profile.maximum_rounds_per_frame:
		_shot_accumulator -= interval
		fired_this_frame += 1
		_fire_round()
		if ammo_remaining <= 0:
			is_firing = false
			ammo_empty.emit()
			firing_stopped.emit()
			return
	if fired_this_frame >= profile.maximum_rounds_per_frame:
		# Drop the backlog: a long hitch must not produce a burst the gun could
		# never physically have fired.
		_shot_accumulator = 0.0


func _trigger_held() -> bool:
	var input := get_node_or_null("/root/GamepadInput")
	return input != null and input.is_cannon_firing()


func _fire_round() -> void:
	if projectile_manager == null or gun_mount == null:
		return
	var muzzle: Transform3D = gun_mount.get_muzzle_transform()
	var direction := apply_dispersion(muzzle.basis.x.normalized(), current_dispersion_mrad())
	var inherited: Vector3 = carrier.velocity if carrier != null and "velocity" in carrier else Vector3.ZERO
	_sequence += 1
	_tracer_counter += 1
	var tracer: bool = profile.tracer_interval > 0 and _tracer_counter % profile.tracer_interval == 0
	var round_data: RefCounted = projectile_manager.acquire_round()
	round_data.initialise(
		_sequence,
		muzzle.origin,
		direction,
		ballistics.launch_velocity(direction, inherited),
		tracer,
		round_profile,
		"cannon_30mm"
	)
	round_data.spawn_time = continuous_fire_time
	projectile_manager.spawn(round_data)
	ammo_remaining -= 1
	rounds_in_current_burst += 1
	time_since_last_shot = 0.0
	gun_mount.kick()
	round_fired.emit(round_data)
	ammo_changed.emit(ammo_remaining, profile.ammo_capacity)


func current_dispersion_mrad() -> float:
	var spread: float = profile.base_dispersion_mrad
	if carrier != null and "velocity" in carrier:
		var speed: float = carrier.velocity.length()
		spread += profile.movement_dispersion_multiplier * (speed / 60.0)
	# Sustained fire walks off slightly; a short burst stays tight.
	spread += profile.high_rate_dispersion_multiplier * minf(continuous_fire_time, 3.0)
	if aim != null and aim.at_limit:
		spread *= profile.turret_limit_dispersion_multiplier
	return spread


func apply_dispersion(direction: Vector3, mrad: float) -> Vector3:
	if mrad <= 0.0:
		return direction
	var spread := mrad / 1000.0
	var up := direction.cross(Vector3.UP)
	if up.is_zero_approx():
		up = direction.cross(Vector3.RIGHT)
	up = up.normalized()
	var right := direction.cross(up).normalized()
	var angle := randf() * TAU
	# sqrt keeps the sample uniform across the cone's area instead of clustering
	# every round near the centre.
	var radius := sqrt(randf()) * spread
	return (direction + up * cos(angle) * radius + right * sin(angle) * radius).normalized()


func predict_impact() -> Dictionary:
	# The pipper. Same profile, same integrator, same collision as live rounds.
	var muzzle: Transform3D = gun_mount.get_muzzle_transform()
	var inherited: Vector3 = carrier.velocity if carrier != null and "velocity" in carrier else Vector3.ZERO
	if not ground_height.is_valid():
		return {}
	return ballistics.solve(
		muzzle.origin,
		muzzle.basis.x.normalized(),
		ground_height,
		inherited,
		hit_query.query_segment if hit_query != null else Callable()
	)
