extends RefCounted

## Camera response to speed and bank, for the fixed-wing aircraft.
##
## The helicopter's camera sits on a level horizon and treats bank as
## decoration, which is right for an aircraft that banks a few degrees. A jet
## rolls past ninety, and a camera that stays upright through that turns the
## most dramatic thing the aircraft does into something happening to a model in
## front of a fixed backdrop.
##
## The lag is the whole trick. The camera follows the airframe's roll, but a
## beat behind, so a snap roll throws the horizon and it catches up afterwards.


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


## The triggers move the fixed-wing throttle. They must never also enter the
## helicopter's camera sweep, and a helicopter orbit command likewise owns
## them before the camera does.
static func routed_orbit_input(
	raw_input: float,
	fixed_wing_active: bool,
	aircraft_is_orbiting: bool
) -> float:
	return 0.0 if fixed_wing_active or aircraft_is_orbiting else raw_input


## The camera's up vector, lagging the airframe's. Returns the new lagged up
## after delta, and this is what produces both the horizon bank and the sense
## that the camera is a chase plane rather than a rigid mount.
static func lagged_up(
	current_up: Vector3,
	airframe_up: Vector3,
	response: float,
	delta: float
) -> Vector3:
	var weight := 1.0 - exp(-response * delta)
	var blended := current_up.lerp(airframe_up, weight)
	if blended.is_zero_approx():
		return airframe_up
	return blended.normalized()


## How much of the airframe's bank the camera adopts at all. Taking all of it
## is disorienting on a phone screen; taking none of it is a spaceship.
static func bank_blend(airframe_up: Vector3, blend: float) -> Vector3:
	var mixed := Vector3.UP.lerp(airframe_up, clampf(blend, 0.0, 1.0))
	if mixed.is_zero_approx():
		return Vector3.UP
	return mixed.normalized()
