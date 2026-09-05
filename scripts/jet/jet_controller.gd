extends Node3D

## Fixed-wing flight.
##
## The aircraft has no direct control over its heading. The stick commands a
## roll rate and a pitch rate; rolling tilts the lift vector; the horizontal
## component of tilted lift supplies the main turning force. Throttle
## commands a target thrust, and airspeed is whatever thrust and drag settle on.
##
## That chain -- stick, roll, bank, lift tilt, turn, ease off, assist holds the
## bank -- is the difference between an aircraft and a spaceship, and it is why
## none of the code below contains a turn.
##
## The rudder joins that chain rather than bypassing it. It commands sideslip,
## and the aircraft rolls through the dihedral effect of the slip it produced,
## so stick and rudder together reach a steeper bank than either alone. Side
## force also bends the velocity toward the nose while retaining momentum.
##
## The structural difference from helicopter_controller.gd: that one keeps only
## rotation.y on the anchor and puts pitch and roll on the visual as decoration.
## This one cannot. Bank has to be real, because it is what produces the turn,
## so the anchor carries a full three-axis basis and the visual follows it
## without a second decorative attitude.
##
## Aerodynamic coefficients live in aero_model.gd with the reasoning for their
## numbers.

const AERO := preload("res://scripts/jet/aero_model.gd")
const ASSIST := preload("res://scripts/jet/flight_assist.gd")
const JET_VISUALS := preload("res://scripts/jet/jet_visuals.gd")
const FIXED_GUN_MOUNT := preload("res://scripts/weapons/fixed_gun_mount.gd")

const EFFECTS := preload("res://scripts/jet/jet_effects.gd")
var _effects: Node3D

const GRAVITY := 9.80665

signal crashed(point: Vector3)
signal respawned()
signal boundary_warning(urgency: float)

@export var terrain_path: NodePath = NodePath("../StreamedTerrain")
@export var world_edge_margin := 50.0

@export_group("Airframe")
## The GLB is ten times real scale, so the wingspan is measured and the model
## scaled to match rather than trusting a magic number that breaks if the asset
## is ever swapped.
@export var reference_wingspan_m := 13.56
## Hull half-height, for deciding when the aircraft has touched the ground.
@export var hull_clearance_m := 2.5

@export_group("Control")
## Deliberately below the fastest published fighter roll responses so a full
## revolution remains controllable on a thumbstick.
@export var maximum_roll_rate := 1.8          ## rad/s at full stick
@export var maximum_pitch_rate := 0.95        ## rad/s at full stick, before limits
@export var maximum_rudder_yaw_rate := 0.8    ## rad/s, exaggerated trigger authority
@export var maximum_rudder_sideslip_degrees := 28.0
## Roll per radian of sideslip. Rudder rolls the aircraft through the slip it
## creates rather than through a coupling constant, so stick and rudder together
## reach a steeper bank than either does alone.
@export var dihedral_roll_gain := 0.35
@export var sideslip_damping_gain := 2.4
@export var control_response := 7.0           ## how quickly commanded rates are reached

@export_group("Throttle")
## Dedicated up/down buttons move the throttle; releasing holds the setting.
@export var throttle_rate := 0.55
@export var starting_throttle := 0.62
## Past 1.0 is afterburner. The travel above military power is the detent.
@export var maximum_throttle := 1.35
@export var afterburner_travel := 0.35
## Engines spool. Afterburner lights faster than the core spools.
@export var spool_response := 1.6

@export_group("Envelope")
@export var minimum_display_speed := 90.0
@export var maximum_display_speed := 260.0
@export var service_ceiling_m := 6000.0
@export var respawn_clearance_m := 420.0
@export var respawn_delay_s := 2.2
## Where the assist starts flying the aircraft home. Not a wall.
@export var boundary_margin_m := 1200.0
@export var boundary_roll_gain := 1.8

@export_group("Cockpit")
## Where along the cockpit tub the seat sits, and how high in it the pilot's
## eyes are. Fractions rather than metres, so they survive the model being
## rescaled or replaced.
@export var cockpit_seat_fraction := 0.60
@export var cockpit_eye_height_fraction := 0.80
## The view sits a few degrees nose-down so the instrument panel is in frame
## below the HUD combiner, rather than only the sky ahead of it.
@export var cockpit_pitch_degrees := -8.0

var velocity := Vector3.ZERO
## 0 to 1 is idle to military power; above 1 is afterburner.
var throttle := 0.62
var alpha := 0.0
var beta := 0.0
var load_factor := 1.0
var bank := 0.0
var roll_input := 0.0
var pitch_input := 0.0
var rudder_input := 0.0
var throttle_input := 0.0
## L2 + R2 held: the nozzles own the nose, and the limiter moves out to the
## post-stall angle. Public so the HUD can say so.
var vectoring := false
var airbrake := 0.0
var _braking := false

var _terrain: Node
var _visual: Node3D
var _gun_mount: Node3D
var _hardpoints: Array[Node3D] = []
var _thrust_setting := 0.62
var _roll_rate := 0.0
var _pitch_rate := 0.0
var _yaw_rate := 0.0
var _world_limit := 1950.0
var _crashed := false
var _respawn_timer := 0.0
var _cockpit_local := Vector3(9.5, 1.05, 0.0)
var _boundary_urgency := 0.0
var _wings_level_requested := false


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path)
	_adopt_world_bounds(_terrain)
	throttle = starting_throttle
	_thrust_setting = starting_throttle
	call_deferred("_find_visual")


func set_terrain(node: Node) -> void:
	_terrain = node
	_adopt_world_bounds(node)


func _adopt_world_bounds(node: Node) -> void:
	if node != null and node.has_method("world_half_extent"):
		_world_limit = maxf(float(node.world_half_extent()) - world_edge_margin, 1.0)


## Put the aircraft into level flight at cruise, on its current heading. Used
## both on entering the aircraft and after a crash.
func launch(at_position: Vector3, heading_radians: float) -> void:
	var nose := Vector3(sin(heading_radians), 0.0, -cos(heading_radians))
	global_position = at_position
	var speed := (minimum_display_speed + maximum_display_speed) * 0.5
	var altitude := at_position.y - _sample_ground()
	var trim := AERO.trim_alpha(speed, AERO.altitude_falloff(altitude, service_ceiling_m))
	basis = _basis_from_nose(nose, Vector3.UP)
	basis = basis.rotated(basis.z, trim)
	velocity = nose * speed
	throttle = starting_throttle
	_thrust_setting = starting_throttle
	_roll_rate = 0.0
	_pitch_rate = 0.0
	_yaw_rate = 0.0
	alpha = trim
	beta = 0.0
	load_factor = 1.0
	bank = 0.0
	roll_input = 0.0
	pitch_input = 0.0
	rudder_input = 0.0
	throttle_input = 0.0
	vectoring = false
	airbrake = 0.0
	_braking = false
	_crashed = false
	_respawn_timer = 0.0
	_wings_level_requested = false
	if is_inside_tree():
		get_global_transform_interpolated()
		reset_physics_interpolation()


func is_crashed() -> bool:
	return _crashed


func _physics_process(delta: float) -> void:
	if _crashed:
		_update_visual(delta)
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	_read_controls(delta)
	_integrate(delta)
	_check_boundaries()
	_check_ground()
	_update_visual(delta)


## The stick commands rates; the assist decides which of them the aircraft is
## willing to fly.
func _read_controls(delta: float) -> void:
	var stick := Vector2.ZERO
	var rudder_axis := 0.0
	var throttle_axis := 0.0
	var boost_held := false
	var gamepad := get_node_or_null("/root/GamepadInput")
	if gamepad != null and gamepad.is_controller_ready():
		stick = gamepad.get_flight_vector()
		rudder_axis = gamepad.get_rudder_axis()
		throttle_axis = gamepad.get_jet_throttle_axis()
		boost_held = gamepad.is_vectoring_held()
	roll_input = stick.x
	pitch_input = pitch_input_from_stick(stick.y)
	rudder_input = rudder_axis
	throttle_input = throttle_axis

	throttle = clampf(throttle + throttle_axis * throttle_rate * delta, 0.0, maximum_throttle)
	_thrust_setting = AERO.spool(_thrust_setting, throttle, spool_response, delta)

	var speed := velocity.length()
	bank = bank_angle(basis)
	var level := absf(bank) < deg_to_rad(15.0 if _braking else 10.0) and absf(velocity.normalized().y) < 0.17
	_braking = boost_held and level and stick.length() < 0.12 and absf(rudder_axis) < 0.12
	vectoring = boost_held and not _braking
	airbrake = move_toward(airbrake, 1.0 if _braking else 0.0, delta * 3.0)

	var commanded_roll := ASSIST.commanded_roll_rate(
		roll_input,
		maximum_roll_rate,
		speed,
		bank,
		_roll_rate,
		vectoring
	)
	commanded_roll += ASSIST.dihedral_roll_rate(beta, dihedral_roll_gain)
	commanded_roll += _boundary_roll_command()
	if _wings_level_requested:
		if absf(roll_input) > 0.2:
			_wings_level_requested = false
		elif absf(bank) <= deg_to_rad(1.5):
			_wings_level_requested = false
		else:
			var recovery := ASSIST.wings_level_roll_rate(bank, maximum_roll_rate, speed)
			if is_zero_approx(recovery):
				_wings_level_requested = false
			else:
				commanded_roll = recovery
	var commanded_pitch := ASSIST.commanded_pitch_rate(
		pitch_input,
		maximum_pitch_rate,
		speed,
		bank,
		alpha,
		_roll_rate,
		clampf(_thrust_setting, 0.0, 1.0),
		vectoring
	)
	var commanded_yaw := ASSIST.level_turn_yaw_rate(bank, speed, _roll_rate)
	commanded_yaw += ASSIST.rudder_yaw_rate(
		rudder_input,
		deg_to_rad(maximum_rudder_sideslip_degrees),
		beta,
		sideslip_damping_gain,
		maximum_rudder_yaw_rate
	) * AERO.control_authority(speed)

	# Control surfaces move quickly but not instantly, which is what stops the
	# aircraft snapping between attitudes.
	var weight := 1.0 - exp(-control_response * delta)
	_roll_rate = lerpf(_roll_rate, commanded_roll, weight)
	_pitch_rate = lerpf(_pitch_rate, commanded_pitch, weight)
	_yaw_rate = lerpf(_yaw_rate, commanded_yaw, weight)

	basis = rotate_body(basis, _roll_rate, _pitch_rate, _yaw_rate, delta)


## Godot's stick vector is negative when pushed forward and positive when
## pulled back. Positive aircraft pitch raises the nose.
static func pitch_input_from_stick(stick_y: float) -> float:
	return stick_y


## Roll about the nose, pitch about the right wing, yaw about the aircraft's own
## up. Positive roll drops the right wing, positive pitch raises the nose, and
## positive yaw swings the nose right.
##
## Static so the flight test can fly the real rotation rather than a copy of it.
static func rotate_body(
	from_basis: Basis,
	roll_rate: float,
	pitch_rate: float,
	yaw_rate: float,
	delta: float
) -> Basis:
	var turned := from_basis
	turned = turned.rotated(from_basis.x, roll_rate * delta)
	turned = turned.rotated(from_basis.z, pitch_rate * delta)
	turned = turned.rotated(from_basis.y, -yaw_rate * delta)
	return turned.orthonormalized()


## Bank is the roll of the wings against a level horizon: positive is right wing
## down. It is read back off the basis rather than tracked, so it cannot drift
## away from what the aircraft is actually doing.
static func bank_angle(from_basis: Basis) -> float:
	var nose := from_basis.x
	var right := from_basis.z
	var level_right := nose.cross(Vector3.UP)
	if level_right.is_zero_approx():
		return 0.0
	level_right = level_right.normalized()
	var level_up := level_right.cross(nose).normalized()
	return atan2(-right.dot(level_up), right.dot(level_right))


static func heading_of(from_basis: Basis) -> float:
	var nose := from_basis.x
	nose.y = 0.0
	if nose.is_zero_approx():
		return 0.0
	nose = nose.normalized()
	return atan2(nose.x, -nose.z)


func _integrate(delta: float) -> void:
	var speed := velocity.length()
	var nose := basis.x
	var up := basis.y

	var body_velocity := basis.inverse() * velocity
	var angles := AERO.alpha_beta(body_velocity)
	alpha = angles.x
	beta = angles.y

	var ground_height := _sample_ground()
	var altitude := global_position.y - ground_height
	var falloff := AERO.altitude_falloff(altitude, service_ceiling_m)

	var dry := clampf(_thrust_setting, 0.0, 1.0)
	var wet := clampf((_thrust_setting - 1.0) / maxf(afterburner_travel, 0.001), 0.0, 1.0)
	var thrust := AERO.thrust_acceleration(dry, wet)

	var acceleration := AERO.flight_acceleration(nose, up, velocity, thrust, alpha, falloff)
	# Drag opposes travel without pitching the nose or changing the throttle.
	acceleration -= velocity.normalized() * airbrake * minf(35.0, 18.0 * pow(speed / 175.0, 2.0))
	velocity += acceleration * delta
	global_position += velocity * delta

	load_factor = AERO.lift_acceleration(speed, alpha) * falloff / GRAVITY


## Roll the assist adds to bring the aircraft back over the theatre. Zero
## anywhere inside the margin, so ordinary flying never feels it.
func _boundary_roll_command() -> float:
	var here := Vector2(global_position.x, global_position.z)
	var heading := _heading()
	var wanted := ASSIST.turn_back_bank(here, heading, _world_limit, boundary_margin_m)
	if is_zero_approx(wanted):
		return 0.0
	return (wanted - bank) * boundary_roll_gain


func _check_boundaries() -> void:
	var here := Vector2(global_position.x, global_position.z)
	var urgency := ASSIST.boundary_urgency(here, _world_limit, boundary_margin_m)
	if not is_equal_approx(urgency, _boundary_urgency):
		_boundary_urgency = urgency
		boundary_warning.emit(urgency)


func _check_ground() -> void:
	var ground_height := _sample_ground()
	if global_position.y - hull_clearance_m > ground_height:
		return
	_crashed = true
	_respawn_timer = respawn_delay_s
	global_position.y = ground_height + hull_clearance_m
	velocity = Vector3.ZERO
	crashed.emit(global_position)


func _respawn() -> void:
	var ground_height := _sample_ground()
	var point := Vector3(
		clampf(global_position.x, -_world_limit, _world_limit),
		ground_height + respawn_clearance_m,
		clampf(global_position.z, -_world_limit, _world_limit)
	)
	launch(point, _heading())
	respawned.emit()


func _heading() -> float:
	return heading_of(basis)


static func _basis_from_nose(nose: Vector3, up: Vector3) -> Basis:
	var forward := nose.normalized()
	var right := forward.cross(up)
	if right.is_zero_approx():
		right = Vector3.BACK
	right = right.normalized()
	var true_up := right.cross(forward).normalized()
	return Basis(forward, true_up, right)


func _sample_ground() -> float:
	if _terrain == null or not _terrain.has_method("sample_height_world"):
		return 0.0
	return _terrain.sample_height_world(global_position.x, global_position.z)


func altitude_above_ground() -> float:
	return global_position.y - _sample_ground()


func airspeed() -> float:
	return velocity.length()


func throttle_percent() -> float:
	return clampf(throttle, 0.0, 1.0) * 100.0


func afterburner_fraction() -> float:
	return clampf((throttle - 1.0) / maxf(afterburner_travel, 0.001), 0.0, 1.0)


func body_rates() -> Vector3:
	return Vector3(_roll_rate, _pitch_rate, _yaw_rate)


## Any deliberate roll-stick input cancels this one-shot recovery command.
func request_wings_level() -> bool:
	if _crashed or AERO.aerodynamic_load_limit(airspeed()) <= 1.05:
		_wings_level_requested = false
		return false
	_wings_level_requested = absf(bank_angle(basis)) > deg_to_rad(1.5)
	return _wings_level_requested


func wings_level_requested() -> bool:
	return _wings_level_requested


func _find_visual() -> void:
	_visual = get_node_or_null("HeroJet")
	if _visual == null:
		return
	_scale_to_reference()
	_stow_landing_gear()
	JET_VISUALS.clarify_canopy(_visual)
	_measure_cockpit()
	if _effects == null:
		_effects = EFFECTS.new()
		add_child(_effects)
		_effects.build(_visual)
	_attach_fixed_gun_mount()
	_attach_hardpoints()


## The GLB is ten times real scale. Measure the wingspan and scale to the real
## one, so swapping the asset cannot silently change the aircraft's size.
func _scale_to_reference() -> void:
	var bounds := _measure_bounds()
	if bounds.size.z <= 0.001:
		return
	var factor := reference_wingspan_m / bounds.size.z
	_visual.scale = Vector3.ONE * factor


## The model carries both a gear-up and a gear-down assembly, and renders them
## both unless told otherwise. This aircraft never lands, so the gear stays up.
func _stow_landing_gear() -> void:
	for child in _visual.find_children("*", "Node3D", true, false):
		var name_lower := String(child.name).to_lower()
		if name_lower.contains("landingon"):
			(child as Node3D).visible = false


func _attach_fixed_gun_mount() -> void:
	if _visual == null or _gun_mount != null:
		return
	var bounds := _measure_bounds()
	var local_muzzle := Vector3(
		bounds.end.x,
		bounds.get_center().y,
		bounds.get_center().z
	) if not bounds.size.is_zero_approx() else Vector3(9.5, 0.0, 0.0)
	_gun_mount = FIXED_GUN_MOUNT.new()
	_gun_mount.name = "FixedInternalGunMuzzle"
	add_child(_gun_mount)
	_gun_mount.position = _visual.transform * local_muzzle


## Two wing hardpoints, placed from the measured airframe rather than from magic
## numbers, so swapping the GLB cannot leave rockets launching out of the
## fuselage. Same reasoning as the gun muzzle above.
func _attach_hardpoints() -> void:
	if _visual == null or not _hardpoints.is_empty():
		return
	var bounds := _measure_bounds()
	if bounds.size.is_zero_approx():
		return
	var span := bounds.size.z
	var centre := bounds.get_center()
	for side in [-1.0, 1.0]:
		var mount := Node3D.new()
		mount.name = "Hardpoint%s" % ("Left" if side < 0.0 else "Right")
		add_child(mount)
		# Under the wing rather than through it, and outboard far enough that the
		# two trails read as two rather than as one thick one.
		mount.position = _visual.transform * Vector3(
			centre.x,
			centre.y - bounds.size.y * 0.15,
			side * span * 0.28
		)
		_hardpoints.append(mount)


func get_hardpoints() -> Array[Node3D]:
	return _hardpoints


func get_gun_mount() -> Node3D:
	return _gun_mount


func _measure_bounds() -> AABB:
	var bounds := AABB()
	var found := false
	if _visual == null:
		return bounds
	for child in _visual.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		var local: AABB = _visual.global_transform.affine_inverse() * (instance.global_transform * instance.get_aabb())
		bounds = local if not found else bounds.merge(local)
		found = true
	return bounds


## The Apache's GLB has no interior at all, which is why its cockpit camera
## floats out in front of the nose. This one carries a modelled cockpit tub,
## instrument glass and HUD combiner, so the pilot station is a real place
## inside the aircraft. Sit far enough back and high enough in the tub that the
## panel and the combiner are both in frame.
func _measure_cockpit() -> void:
	var tub := _find_named("cockpit")
	var bounds := _mesh_bounds(tub) if tub != null else _measure_bounds()
	if bounds.size.is_zero_approx():
		return
	_cockpit_local = Vector3(
		bounds.position.x + bounds.size.x * cockpit_seat_fraction,
		bounds.position.y + bounds.size.y * cockpit_eye_height_fraction,
		bounds.get_center().z
	)


## One node's bounds, in the visual's own units.
func _mesh_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		var local: AABB = _visual.global_transform.affine_inverse() * (instance.global_transform * instance.get_aabb())
		bounds = local if not found else bounds.merge(local)
		found = true
	if not found and node is MeshInstance3D:
		var self_instance := node as MeshInstance3D
		bounds = _visual.global_transform.affine_inverse() * (self_instance.global_transform * self_instance.get_aabb())
	return bounds


func _find_named(fragment: String) -> Node3D:
	for child in _visual.find_children("*", "Node3D", true, false):
		if String(child.name).to_lower().contains(fragment):
			return child as Node3D
	return null


## The pilot station, with the airframe's real orientation -- bank included.
## A jet cockpit whose horizon stays level is not a cockpit.
func get_cockpit_transform() -> Transform3D:
	if _visual == null:
		return global_transform
	var frame := _visual.global_transform
	var orientation := frame.basis.orthonormalized()
	# Tilt down about the right wing so the panel is in frame under the HUD.
	orientation = orientation.rotated(orientation.z, deg_to_rad(cockpit_pitch_degrees))
	return Transform3D(orientation, frame * _cockpit_local)


func get_interpolated_cockpit_transform() -> Transform3D:
	if _visual == null or not _visual.is_inside_tree():
		return get_cockpit_transform()
	var frame := _visual.get_global_transform_interpolated()
	var orientation := frame.basis.orthonormalized()
	orientation = orientation.rotated(orientation.z, deg_to_rad(cockpit_pitch_degrees))
	return Transform3D(orientation, frame * _cockpit_local)


func get_focus_position() -> Vector3:
	return _visual.global_position if _visual != null else global_position


func get_interpolated_focus_position() -> Vector3:
	var target: Node3D = _visual if _visual != null else self
	if not target.is_inside_tree():
		return target.global_position
	return target.get_global_transform_interpolated().origin


func get_interpolated_airframe_transform() -> Transform3D:
	var target: Node3D = _visual if _visual != null else self
	if not target.is_inside_tree():
		return target.global_transform
	return target.get_global_transform_interpolated()


func get_muzzle_transform() -> Transform3D:
	if _gun_mount != null:
		return _gun_mount.get_muzzle_transform()
	return _visual.global_transform if _visual != null else global_transform


## The airframe follows the physical anchor exactly. High-frequency synthetic
## buffet and vibration made both the external model and cockpit camera jitter.
func _update_visual(delta: float) -> void:
	if _visual == null:
		return
	_visual.position = Vector3.ZERO
	_visual.rotation = Vector3.ZERO
	if _effects != null:
		_effects.update(delta, roll_input, airbrake, engine_afterburner_fraction())


func engine_afterburner_fraction() -> float:
	return 0.0 if _crashed else clampf((_thrust_setting - 1.0) / maxf(afterburner_travel, 0.001), 0.0, 1.0)
