extends RefCounted

## Flying a circle around a point on the ground, nose held on it.
##
## The aircraft is steered, not teleported: this returns the horizontal velocity
## and heading it should be carrying, and each flight model applies them its own
## way -- arcade by taking the velocity, the rotor model by tilting the disc
## toward it.

const MINIMUM_RADIUS := 15.0


## Horizontal distance from the aircraft to the point it is circling.
static func radius_to(position: Vector3, target: Vector3) -> float:
	return maxf(Vector2(position.x - target.x, position.z - target.z).length(), MINIMUM_RADIUS)


## The velocity that carries the aircraft around the circle. `direction` is the
## trigger axis: positive sweeps one way, negative the other. The radial term
## pulls the aircraft back onto the circle so the orbit does not spiral.
static func desired_velocity(
	position: Vector3,
	target: Vector3,
	radius: float,
	direction: float,
	speed: float,
	radial_gain: float
) -> Vector3:
	var offset := Vector3(position.x - target.x, 0.0, position.z - target.z)
	if offset.is_zero_approx():
		return Vector3.ZERO
	var outward := offset.normalized()
	# Tangent, taken by rotating the outward vector a quarter turn about up.
	var tangent := Vector3(-outward.z, 0.0, outward.x)
	var radial_error := radius - offset.length()
	return tangent * direction * speed + outward * radial_error * radial_gain


## Closing or widening the orbit. The left stick works the radius while the
## triggers work the sweep, so the aircraft can be walked in toward a target
## without letting go of the circle.
static func adjust_radius(
	radius: float,
	input: float,
	rate: float,
	delta: float,
	minimum: float,
	maximum: float
) -> float:
	return clampf(radius + input * rate * delta, minimum, maximum)


## Keeps the commanded radius within reach of the one the aircraft is actually
## flying. Without this the command runs away from the airframe -- the stick
## reads 100 m while the aircraft is still 235 m out -- and letting go leaves a
## long unexplained drift inward.
static func leash_radius(commanded: float, actual: float, lead: float) -> float:
	return clampf(commanded, actual - lead, actual + lead)


## The heading that points the nose at the target, in radians, in the same
## convention as the airframe's own yaw.
static func heading_to(position: Vector3, target: Vector3) -> float:
	var to_target := Vector3(target.x - position.x, 0.0, target.z - position.z)
	if to_target.is_zero_approx():
		return 0.0
	# The airframe's nose is its local +X.
	return atan2(-to_target.z, to_target.x)
