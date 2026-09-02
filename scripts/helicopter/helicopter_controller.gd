extends Node3D

## Rotor-driven flight.
##
## The aircraft has no direct control over its velocity. The cyclic tilts the
## rotor disc, thrust acts along the disc normal, and the horizontal component
## of that thrust is the only thing that accelerates the aircraft. Collective
## sets thrust magnitude, which also produces the torque the pedals have to
## cancel. All four axes therefore have to move together, which is what flying a
## helicopter actually is.
##
## Aerodynamic coefficients live in rotor_model.gd with the sources for their
## numbers.

const ROTOR := preload("res://scripts/helicopter/rotor_model.gd")
const FLIGHT_MATH := preload("res://scripts/helicopter/flight_math.gd")
const TARGET_ORBIT := preload("res://scripts/helicopter/target_orbit.gd")
const AIRFRAME_MOTION := preload("res://scripts/helicopter/airframe_motion.gd")
const GUN_MOUNT := preload("res://scripts/weapons/gun_mount.gd")

const GRAVITY := 9.80665

## Two flight models. Arcade is the game one: the stick sets a speed and the
## aircraft holds its height over the terrain. Rotor is the real one, where the
## cyclic tilts the disc and nothing else moves the aircraft. Arcade is the
## default because it is the one you can pick up and fly.
enum FlightMode {ARCADE, ROTOR}

@export var flight_mode: FlightMode = FlightMode.ARCADE

@export var terrain_path: NodePath = NodePath("../StreamedTerrain")
## Kept clear of the very edge so the aircraft never sits on the boundary where
## the terrain mesh ends.
@export var world_edge_margin := 50.0

@export_group("Rotor")
## Thrust at full collective, as a multiple of gravity. At 2.0 the aircraft
## hovers at half collective, which puts the hover in the middle of the travel.
@export var maximum_thrust_g := 2.0
## Collective is a position, not a spring: the stick moves it and it stays.
@export var collective_rate := 0.55
@export var starting_collective := 0.5
@export var rotor_diameter := 14.63
@export var translational_lift_gain := 0.17
@export var ground_effect_gain := 0.12
@export var vortex_ring_loss := 0.35

@export_group("Cyclic")
@export var maximum_cyclic_degrees := 22.0
@export var cyclic_response := 3.2

@export_group("Anti-torque")
@export var yaw_speed_degrees := 82.0
@export var yaw_acceleration_degrees := 210.0
@export var yaw_braking_degrees := 125.0
## Yaw the fuselage takes at full collective. The pedals must hold this off.
@export var torque_yaw_degrees := 26.0

@export_group("Arcade Flight")
@export var acceleration := 68.0
@export var braking := 26.0
@export var drag := 10.0
@export var max_speed := 118.0
@export var terrain_clearance := 90.0
@export var max_terrain_clearance := 360.0
@export var climb_speed := 72.0
@export var altitude_response := 2.8
@export var forward_pitch_degrees := 13.0
@export var strafe_bank_degrees := 15.0
@export var turn_bank_degrees := 11.0

@export_group("Airframe")
## Quadratic drag, which is what sets the cruise speed against rotor thrust.
@export var drag_coefficient := 0.0014
@export var min_terrain_clearance := 25.0
@export var terrain_height_response := 0.9
@export var terrain_height_deadband := 0.3
@export var maximum_terrain_follow_speed := 12.0
@export var shudder_degrees := 0.7
@export var shudder_frequency := 11.0

@export_group("Target Orbit")
## Flying a circle around a picked point, nose held on it. The radius is
## whatever distance the aircraft was at when the trigger came in, so taking an
## orbit never yanks the aircraft onto a fixed circle.
@export var orbit_speed := 40.0
@export var orbit_radial_gain := 0.5
@export var orbit_yaw_response := 4.0
@export var orbit_tilt_gain := 0.9
## The left stick closes and widens the orbit while the triggers sweep it.
@export var orbit_radius_rate := 80.0
@export var minimum_orbit_radius := 100.0
@export var maximum_orbit_radius := 4000.0
## How far the commanded radius may lead the one being flown.
@export var orbit_radius_lead := 120.0

@export_group("Airframe Motion")
@export var hover_bob_metres := 0.6
@export var hover_bob_frequency := 0.35
@export var hover_sway_degrees := 1.2
@export var move_wobble_degrees := 2.5
@export var wobble_response := 3.0
@export var lean_response := 4.8

var velocity := Vector3.ZERO
var collective := 0.5
var pitch_degrees := 0.0
var roll_degrees := 0.0
var _terrain: Node
var _visual: Node3D
var _gun_mount: Node3D
var _yaw_velocity_degrees := 0.0
var _smoothed_ground_height := 0.0
var _ground_height_initialized := false
var _world_limit := 1950.0
var _shudder := 0.0
var _bob_time := 0.0
var _wobble := 0.0
var _previous_velocity := Vector3.ZERO
var _commanded_clearance := 90.0
var _cockpit_local := Vector3(2.6, 1.1, 0.0)
var orbit_target := Vector3.ZERO
var has_orbit_target := false
var _orbit_radius := 0.0


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path)
	_adopt_world_bounds(_terrain)
	collective = starting_collective
	_commanded_clearance = terrain_clearance
	call_deferred("_find_visual")


func set_orbit_target(point: Vector3) -> void:
	orbit_target = point
	has_orbit_target = true
	_orbit_radius = clampf(
		TARGET_ORBIT.radius_to(position, point),
		minimum_orbit_radius,
		maximum_orbit_radius
	)


## Stick forward closes the circle, back widens it.
func _adjust_orbit_radius(stick_forward: float, delta: float) -> void:
	_orbit_radius = TARGET_ORBIT.adjust_radius(
		_orbit_radius,
		stick_forward,
		orbit_radius_rate,
		delta,
		minimum_orbit_radius,
		maximum_orbit_radius
	)
	_orbit_radius = maxf(
		TARGET_ORBIT.leash_radius(
			_orbit_radius,
			TARGET_ORBIT.radius_to(position, orbit_target),
			orbit_radius_lead
		),
		minimum_orbit_radius
	)


func orbit_radius() -> float:
	return _orbit_radius


func clear_orbit_target() -> void:
	has_orbit_target = false


## The triggers fly the aircraft round the target when one is picked; with no
## target they stay with the camera.
func orbit_input() -> float:
	if not has_orbit_target or not GamepadInput.is_controller_ready():
		return 0.0
	return GamepadInput.get_camera_orbit_axis()


func _orbit_velocity(direction: float) -> Vector3:
	return TARGET_ORBIT.desired_velocity(
		position,
		orbit_target,
		_orbit_radius,
		direction,
		orbit_speed,
		orbit_radial_gain
	)


func _hold_nose_on_target(delta: float) -> void:
	rotation.y = lerp_angle(
		rotation.y,
		TARGET_ORBIT.heading_to(position, orbit_target),
		1.0 - exp(-orbit_yaw_response * delta)
	)
	_yaw_velocity_degrees = 0.0


func set_flight_mode(mode: FlightMode) -> void:
	flight_mode = mode
	# Entering rotor flight from arcade must not inherit a velocity the rotor
	# never produced, or the aircraft leaps.
	velocity = Vector3.ZERO
	pitch_degrees = 0.0
	roll_degrees = 0.0
	collective = starting_collective
	_commanded_clearance = maxf(position.y - _smoothed_ground_height, min_terrain_clearance)


func _physics_process(delta: float) -> void:
	if flight_mode == FlightMode.ARCADE:
		_arcade_step(delta)
	else:
		_rotor_step(delta)
	position.x = clampf(position.x, -_world_limit, _world_limit)
	position.z = clampf(position.z, -_world_limit, _world_limit)
	_update_visual(delta)


## The game model: the stick commands a speed and the aircraft rides the terrain
## at a commanded clearance. Forgiving, and what most of the game was built on.
func _arcade_step(delta: float) -> void:
	var flight := Vector2.ZERO
	var right_stick := Vector2.ZERO
	if GamepadInput.is_controller_ready():
		flight = GamepadInput.get_flight_vector()
		right_stick = GamepadInput.get_flight_yaw_collective_vector()
	var sweep := orbit_input()
	if not is_zero_approx(sweep):
		_adjust_orbit_radius(flight.y, delta)
		velocity = velocity.move_toward(_orbit_velocity(sweep), acceleration * delta)
		velocity.y = 0.0
		position += velocity * delta
		_hold_nose_on_target(delta)
		_apply_arcade_altitude(right_stick, delta)
		pitch_degrees = lerpf(pitch_degrees, forward_pitch_degrees * 0.5, 1.0 - exp(-lean_response * delta))
		roll_degrees = lerpf(roll_degrees, -sweep * strafe_bank_degrees, 1.0 - exp(-lean_response * delta))
		_shudder = 0.0
		return
	var planar_input := FLIGHT_MATH.get_planar_control(basis, flight)
	if planar_input.length_squared() > 0.001:
		velocity += planar_input * acceleration * delta
	else:
		velocity = velocity.move_toward(Vector3.ZERO, braking * delta)
	velocity = velocity.move_toward(Vector3.ZERO, drag * delta)
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed
	velocity.y = 0.0
	position += velocity * delta
	var target_yaw_velocity := -right_stick.x * yaw_speed_degrees
	var yaw_change_rate := yaw_acceleration_degrees if absf(right_stick.x) > 0.01 else yaw_braking_degrees
	_yaw_velocity_degrees = move_toward(_yaw_velocity_degrees, target_yaw_velocity, yaw_change_rate * delta)
	rotation.y += deg_to_rad(_yaw_velocity_degrees) * delta
	_apply_arcade_altitude(right_stick, delta)
	# The lean is decoration in this mode, driven by the stick rather than by
	# any force, which is exactly what makes it forgiving.
	pitch_degrees = lerpf(pitch_degrees, -flight.y * forward_pitch_degrees, 1.0 - exp(-lean_response * delta))
	var turn_amount := -_yaw_velocity_degrees / maxf(yaw_speed_degrees, 1.0)
	roll_degrees = lerpf(
		roll_degrees,
		flight.x * strafe_bank_degrees + turn_amount * turn_bank_degrees,
		1.0 - exp(-lean_response * delta)
	)
	_shudder = 0.0


func _apply_arcade_altitude(right_stick: Vector2, delta: float) -> void:
	_commanded_clearance = clampf(
		_commanded_clearance - right_stick.y * climb_speed * delta,
		min_terrain_clearance,
		max_terrain_clearance
	)
	var ground_height := _sample_ground(delta)
	position.y = lerpf(
		position.y,
		ground_height + _commanded_clearance,
		1.0 - exp(-altitude_response * delta)
	)


func _rotor_step(delta: float) -> void:
	var cyclic := Vector2.ZERO
	var pedals_collective := Vector2.ZERO
	if GamepadInput.is_controller_ready():
		cyclic = GamepadInput.get_flight_vector()
		pedals_collective = GamepadInput.get_flight_yaw_collective_vector()

	# Collective holds where it is put, so releasing the stick does not drop the
	# aircraft out of the sky.
	collective = clampf(collective - pedals_collective.y * collective_rate * delta, 0.0, 1.0)

	# The cyclic commands an attitude, and the attitude commands the motion.
	var target_pitch := -cyclic.y * maximum_cyclic_degrees
	var target_roll := cyclic.x * maximum_cyclic_degrees
	var sweep := orbit_input()
	if not is_zero_approx(sweep):
		_adjust_orbit_radius(cyclic.y, delta)
		# The rotor model has no way to be given a velocity, so the orbit is
		# flown by tilting toward the velocity it wants.
		var wanted := _orbit_velocity(sweep)
		var error := wanted - velocity
		error.y = 0.0
		var body_nose := basis.x
		body_nose.y = 0.0
		body_nose = body_nose.normalized() if not body_nose.is_zero_approx() else Vector3.RIGHT
		var body_right := Vector3(-body_nose.z, 0.0, body_nose.x)
		target_pitch = clampf(error.dot(body_nose) * orbit_tilt_gain, -maximum_cyclic_degrees, maximum_cyclic_degrees)
		target_roll = clampf(error.dot(body_right) * orbit_tilt_gain, -maximum_cyclic_degrees, maximum_cyclic_degrees)
	var cyclic_weight := 1.0 - exp(-cyclic_response * delta)
	pitch_degrees = lerpf(pitch_degrees, target_pitch, cyclic_weight)
	roll_degrees = lerpf(roll_degrees, target_roll, cyclic_weight)

	var nose := basis.x
	nose.y = 0.0
	nose = nose.normalized() if not nose.is_zero_approx() else Vector3.RIGHT
	var right := Vector3(-nose.z, 0.0, nose.x)

	var ground_height := _sample_ground(delta)
	var height_above_ground := position.y - ground_height
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var descent_rate := maxf(-velocity.y, 0.0)

	var lift := ROTOR.translational_lift(horizontal_speed, translational_lift_gain)
	lift *= ROTOR.ground_effect(height_above_ground, rotor_diameter, ground_effect_gain)
	lift *= ROTOR.vortex_ring(descent_rate, horizontal_speed, vortex_ring_loss)
	_shudder = ROTOR.transverse_flow(horizontal_speed)

	var thrust := collective * maximum_thrust_g * GRAVITY * lift
	var normal := ROTOR.disc_normal(nose, right, pitch_degrees, roll_degrees)
	var acceleration := normal * thrust + Vector3.DOWN * GRAVITY
	acceleration -= velocity * velocity.length() * drag_coefficient
	velocity += acceleration * delta
	position += velocity * delta

	# Torque is a standing yaw the pedals have to cancel: every collective change
	# is also a pedal change.
	if not is_zero_approx(orbit_input()):
		_hold_nose_on_target(delta)
	var commanded_yaw := -pedals_collective.x * yaw_speed_degrees
	var target_yaw_velocity: float = commanded_yaw + ROTOR.torque_yaw_degrees(collective, torque_yaw_degrees)
	var yaw_change_rate := yaw_acceleration_degrees if absf(pedals_collective.x) > 0.01 else yaw_braking_degrees
	_yaw_velocity_degrees = move_toward(_yaw_velocity_degrees, target_yaw_velocity, yaw_change_rate * delta)
	rotation.y += deg_to_rad(_yaw_velocity_degrees) * delta

	# The hard floor: the rotor model may fly you into a hill, and this is what
	# stops it ending the session.
	var floor_height := ground_height + min_terrain_clearance
	if position.y < floor_height:
		position.y = floor_height
		velocity.y = maxf(velocity.y, 0.0)


func reset_altitude_smoothing() -> void:
	_ground_height_initialized = false


## Height above the aircraft is smoothed so the floor and the ground-effect
## cushion do not chatter over broken terrain.
func _sample_ground(delta: float) -> float:
	if _terrain == null or not _terrain.has_method("sample_height_world"):
		return 0.0
	var raw_height: float = _terrain.sample_height_world(position.x, position.z)
	if not _ground_height_initialized:
		_smoothed_ground_height = raw_height
		_ground_height_initialized = true
		return _smoothed_ground_height
	var difference := raw_height - _smoothed_ground_height
	if absf(difference) <= terrain_height_deadband:
		return _smoothed_ground_height
	var filtered_target := raw_height - signf(difference) * terrain_height_deadband
	var response_weight := 1.0 - exp(-terrain_height_response * delta)
	var response_height := lerpf(_smoothed_ground_height, filtered_target, response_weight)
	_smoothed_ground_height = move_toward(
		_smoothed_ground_height,
		response_height,
		maximum_terrain_follow_speed * delta
	)
	return _smoothed_ground_height


func _find_visual() -> void:
	_visual = get_node_or_null("HeroHelicopter")
	_measure_cockpit()
	_attach_gun_mount()


## The AH-64D GLB is three merged static meshes with no bones and no separate
## cannon geometry, so the M230 assembly is built and hung under the airframe.
func _attach_gun_mount() -> void:
	if _visual == null or _gun_mount != null:
		return
	_gun_mount = GUN_MOUNT.new()
	_gun_mount.name = "GunMount"
	_visual.add_child(_gun_mount)


func get_gun_mount() -> Node3D:
	return _gun_mount


## The airframe GLB is not to scale -- it renders about 31 m long -- so a
## cockpit offset written in metres puts the camera inside the fuselage. Measure
## the mesh and sit just ahead of its nose instead.
func _measure_cockpit() -> void:
	if _visual == null:
		return
	var bounds := AABB()
	var found := false
	for child in _visual.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		var local: AABB = _visual.global_transform.affine_inverse() * (instance.global_transform * instance.get_aabb())
		bounds = local if not found else bounds.merge(local)
		found = true
	if not found or bounds.size.is_zero_approx():
		return
	var centre := bounds.get_center()
	_cockpit_local = Vector3(
		bounds.position.x + bounds.size.x * 1.02,
		centre.y + bounds.size.y * 0.18,
		centre.z
	)


## Where the pilot sits, in world space, with the airframe's orientation.
func get_cockpit_transform() -> Transform3D:
	if _visual == null:
		return global_transform
	var frame := _visual.global_transform
	var orientation := frame.basis.orthonormalized()
	return Transform3D(orientation, frame * _cockpit_local)


## The airframe shows its real attitude now: the tilt on screen is the tilt
## producing the motion, not an animation played over it.
func _update_visual(delta: float) -> void:
	if _visual == null:
		return
	_bob_time += delta
	var speed_fraction := clampf(velocity.length() / 60.0, 0.0, 1.0)
	var weight := AIRFRAME_MOTION.hover_weight(speed_fraction)
	var velocity_change := (velocity - _previous_velocity).length() / maxf(delta, 0.0001)
	_previous_velocity = velocity
	var target_wobble := clampf(velocity_change / GRAVITY, 0.0, 1.0)
	_wobble = lerpf(_wobble, target_wobble, 1.0 - exp(-wobble_response * delta))
	var phase := AIRFRAME_MOTION.phases(_bob_time, hover_bob_frequency)
	var sway := AIRFRAME_MOTION.sway_degrees(
		phase,
		hover_sway_degrees,
		weight,
		move_wobble_degrees,
		_wobble
	)
	# Transverse flow shudder, felt just below effective translational lift.
	var shudder := sin(_bob_time * TAU * shudder_frequency) * shudder_degrees * _shudder
	_visual.position = AIRFRAME_MOTION.position_offset(phase, hover_bob_metres, weight)
	_visual.rotation.z = deg_to_rad(-pitch_degrees + sway.x)
	_visual.rotation.x = deg_to_rad(roll_degrees + sway.y + shudder)
	_visual.rotation.y = deg_to_rad(sway.z)


## The camera and the gunsight both track the visual rather than the anchor, so
## the airframe's drift carries them with it.
func get_focus_position() -> Vector3:
	return _visual.global_position if _visual != null else global_position


func get_interpolated_focus_position() -> Vector3:
	var target: Node3D = _visual if _visual != null else self
	if not target.is_inside_tree():
		return target.global_position
	return target.get_global_transform_interpolated().origin


## The gun fires along the airframe's nose, which is its local +X.
func get_muzzle_transform() -> Transform3D:
	# Local +X is the firing direction throughout. Once the chin turret exists
	# the sight follows the barrel; until then it follows the airframe.
	if _gun_mount != null:
		return _gun_mount.get_muzzle_transform()
	return _visual.global_transform if _visual != null else global_transform


func set_terrain(node: Node) -> void:
	_terrain = node
	_adopt_world_bounds(node)


## The flyable box is the theatre's, not a constant: the packaged theatre is
## 12 km across and the streamed corridor 50 km, and a fixed limit fenced the
## aircraft into the smaller one no matter which was loaded.
func _adopt_world_bounds(node: Node) -> void:
	if node != null and node.has_method("world_half_extent"):
		_world_limit = maxf(float(node.world_half_extent()) - world_edge_margin, 1.0)
