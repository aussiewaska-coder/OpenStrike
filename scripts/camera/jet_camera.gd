extends RefCounted

## Authored fixed-wing views. External cameras follow a bounded 3D flight path
## and use separate body/aim springs; cockpit inherits the airframe directly.

enum Mode {COCKPIT, PURSUIT, TRACK, ISOMETRIC}


## The camera falls back as the aircraft accelerates, which reads as the
## aircraft pulling away from the viewer.
static func trailing_distance(
	speed_mps: float,
	minimum_speed: float,
	maximum_speed: float,
	base_distance: float,
	distance_gain: float
) -> float:
	var span := maxf(maximum_speed - minimum_speed, 1.0)
	var fraction := clampf((speed_mps - minimum_speed) / span, 0.0, 1.0)
	return base_distance + fraction * distance_gain


## Fixed-wing triggers are rudder pedals. They must never also enter the
## helicopter's camera sweep, and a helicopter orbit command likewise owns
## them before the camera does.
static func routed_orbit_input(
	raw_input: float,
	fixed_wing_active: bool,
	aircraft_is_orbiting: bool
) -> float:
	return 0.0 if fixed_wing_active or aircraft_is_orbiting else raw_input


## Right-stick look is always available in the jet. Releasing the spring stick
## eases the view back behind the aircraft.
static func updated_look(
	current: Vector2,
	input: Vector2,
	speed: float,
	return_response: float,
	delta: float
) -> Vector2:
	if not input.is_zero_approx():
		return Vector2(
			clampf(current.x - input.x * speed * delta, -1.0, 1.0),
			clampf(current.y - input.y * speed * delta, -1.0, 1.0)
		)
	return current.lerp(Vector2.ZERO, 1.0 - exp(-return_response * delta))


static func orbited_position(focus: Vector3, camera_position: Vector3, look_basis: Basis) -> Vector3:
	return focus + look_basis * (camera_position - focus)


static func flight_direction(
	velocity: Vector3,
	nose: Vector3,
	maximum_pitch_degrees := 35.0
) -> Vector3:
	var direction := velocity if velocity.length_squared() >= 1.0 else nose
	if direction.is_zero_approx():
		return Vector3.FORWARD
	direction = direction.normalized()
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.is_zero_approx():
		horizontal = Vector3(nose.x, 0.0, nose.z)
	if horizontal.is_zero_approx():
		horizontal = Vector3.FORWARD
	horizontal = horizontal.normalized()
	var pitch := clampf(
		asin(clampf(direction.y, -1.0, 1.0)),
		-deg_to_rad(maximum_pitch_degrees),
		deg_to_rad(maximum_pitch_degrees)
	)
	return horizontal * cos(pitch) + Vector3.UP * sin(pitch)


static func desired_position(
	mode: int,
	focus: Vector3,
	direction: Vector3,
	base_distance: float,
	base_height: float
) -> Vector3:
	match mode:
		Mode.TRACK:
			return focus - direction * base_distance * 1.65 + Vector3.UP * base_height * 2.0
		Mode.ISOMETRIC:
			var diagonal := Vector3(1.0, 0.0, 1.0).normalized()
			return focus + diagonal * base_distance * 2.0 \
				+ Vector3.UP * maxf(base_height * 5.5, base_distance * 1.2)
		_:
			return focus - direction * base_distance + Vector3.UP * base_height


## Framing leads the velocity instead of pinning the aircraft to dead centre.
## The lead is bounded so a speed spike cannot throw the target across screen.
static func look_target(
	mode: int,
	focus: Vector3,
	velocity: Vector3,
	direction: Vector3,
	base_distance: float
) -> Vector3:
	if mode == Mode.ISOMETRIC:
		var ground_direction := Vector3(direction.x, 0.0, direction.z).normalized()
		return focus + ground_direction * maxf(18.0, base_distance * 0.3)
	if mode == Mode.COCKPIT:
		return focus + direction * 100.0
	var lead_seconds := 0.24 if mode == Mode.TRACK else 0.14
	var maximum_lead := 45.0 if mode == Mode.TRACK else 24.0
	var lead := velocity * lead_seconds
	if lead.length() > maximum_lead:
		lead = lead.normalized() * maximum_lead
	if lead.length_squared() < 1.0:
		lead = direction * minf(maximum_lead, base_distance * 0.3)
	return focus + lead


## Each view has its own lens. Pursuit is wide for speed and peripheral
## awareness; tracking and tactical progressively compress the scene.
static func field_of_view(mode: int, zoom: float, speed_fraction: float) -> float:
	var base := 68.0
	var speed_gain := 8.0
	match mode:
		Mode.COCKPIT:
			base = 82.0
			speed_gain = 2.0
		Mode.TRACK:
			base = 60.0
			speed_gain = 5.0
		Mode.ISOMETRIC:
			base = 52.0
			speed_gain = 0.0
	var zoom_bias := clampf((1.0 - zoom) * 10.0, -5.0, 8.0)
	return clampf(base + zoom_bias + clampf(speed_fraction, 0.0, 1.0) * speed_gain, 45.0, 92.0)


## External views receive only a hint of airframe roll. Full roll is reserved
## for cockpit, while tactical remains locked to the world horizon.
static func camera_up(mode: int, airframe_up: Vector3) -> Vector3:
	var aircraft_up := airframe_up.normalized() if not airframe_up.is_zero_approx() else Vector3.UP
	if mode == Mode.COCKPIT:
		return aircraft_up
	var roll_weight := 0.22 if mode == Mode.PURSUIT else 0.1
	if mode == Mode.ISOMETRIC:
		roll_weight = 0.0
	var blended := Vector3.UP.lerp(aircraft_up, roll_weight)
	return blended.normalized() if not blended.is_zero_approx() else Vector3.UP


static func position_response(mode: int) -> float:
	match mode:
		Mode.TRACK:
			return 4.5
		Mode.ISOMETRIC:
			return 5.5
		_:
			return 7.0


static func aim_response(mode: int) -> float:
	match mode:
		Mode.TRACK:
			return 7.5
		Mode.ISOMETRIC:
			return 8.0
		_:
			return 12.0


static func allows_free_look(mode: int) -> bool:
	return mode != Mode.ISOMETRIC
