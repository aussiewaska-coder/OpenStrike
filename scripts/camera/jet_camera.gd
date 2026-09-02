extends RefCounted

## Horizon-stable fixed-wing cameras. Follow and track align behind the flight
## path, while isometric keeps a fixed world-space ground angle.

enum Mode {FOLLOW, TRACK, ISOMETRIC}


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


static func travel_direction(velocity: Vector3, nose: Vector3) -> Vector3:
	var direction := velocity
	direction.y = 0.0
	if direction.length_squared() < 1.0:
		direction = nose
		direction.y = 0.0
	if direction.is_zero_approx():
		return Vector3.FORWARD
	return direction.normalized()


static func desired_position(
	mode: int,
	focus: Vector3,
	direction: Vector3,
	base_distance: float,
	base_height: float
) -> Vector3:
	match mode:
		Mode.TRACK:
			return focus - direction * base_distance * 1.65 + Vector3.UP * base_height * 1.8
		Mode.ISOMETRIC:
			var diagonal := Vector3(1.0, 0.0, 1.0).normalized()
			return focus + diagonal * base_distance * 2.0 \
				+ Vector3.UP * maxf(base_height * 5.5, base_distance * 1.2)
		_:
			return focus - direction * base_distance + Vector3.UP * base_height


static func allows_free_look(mode: int) -> bool:
	return mode != Mode.ISOMETRIC
