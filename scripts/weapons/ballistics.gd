extends RefCounted

## Continuously computed impact point for the airframe's gun.
##
## The model is an AH-64D, so the round is the M230's 30 mm: roughly 805 m/s at
## the muzzle, losing speed exponentially while gravity does the rest. That is
## close enough to a real ballistic table across the couple of kilometres this
## sight is used at, and every figure is a knob for when a real weapon lands.

const GRAVITY := 9.80665

var muzzle_velocity := 805.0
var drag_per_second := 0.08
var maximum_range := 4000.0
var maximum_flight_seconds := 20.0
var step_seconds := 0.05


## Adopts a BallisticProfile so the sight and the live rounds cannot be tuned
## apart. Both read the one resource (spec section 14).
func adopt(profile: Resource) -> void:
	muzzle_velocity = profile.muzzle_velocity
	drag_per_second = profile.drag_per_second
	maximum_range = profile.maximum_range
	maximum_flight_seconds = profile.maximum_flight_seconds
	step_seconds = profile.simulation_step


## Muzzle velocity plus the airframe's own, which is what makes fire from a
## sideways orbit lead correctly (spec section 13).
func launch_velocity(direction: Vector3, inherited_velocity: Vector3) -> Vector3:
	return direction.normalized() * muzzle_velocity + inherited_velocity


## One integration step, trapezoidal like solve() below. Live rounds advance
## through this exact function, so a round cannot drift from the pipper.
## Returns [next_point, next_velocity].
##
## `age` is unused here and exists so that every projectile flight model shares
## one signature: a rocket's thrust depends on how long its motor has been
## burning, and a shell's does not.
func advance(point: Vector3, velocity: Vector3, delta: float, _age := 0.0) -> Array:
	var next_velocity := velocity * exp(-drag_per_second * delta)
	next_velocity.y -= GRAVITY * delta
	return [point + (velocity + next_velocity) * 0.5 * delta, next_velocity]


## Marches the round until it crosses the terrain, returning the impact point,
## slant range and time of flight. Returns an empty dictionary when nothing is
## hit inside the maximum range — the sight then has no firing solution to show.
func solve(
	origin: Vector3,
	direction: Vector3,
	ground_height: Callable,
	inherited_velocity := Vector3.ZERO,
	segment_query := Callable()
) -> Dictionary:
	if direction.is_zero_approx() or step_seconds <= 0.0:
		return {}
	var velocity := launch_velocity(direction, inherited_velocity)
	var point := origin
	var time := 0.0
	var travelled := 0.0
	var previous_gap: float = point.y - float(ground_height.call(point.x, point.z))
	while travelled < maximum_range and time < maximum_flight_seconds:
		var stepped := advance(point, velocity, step_seconds)
		var next_point: Vector3 = stepped[0]
		var next_velocity: Vector3 = stepped[1]
		# Buildings stand in front of the terrain, so when a world query is
		# supplied the sight must stop on the facade the rounds will stop on.
		if segment_query.is_valid():
			var blocked: RefCounted = segment_query.call(point, next_point)
			if blocked != null and blocked.hit:
				return {
					"point": blocked.position,
					"range": origin.distance_to(blocked.position),
					"time": time + step_seconds * float(blocked.t),
					"surface_type": int(blocked.surface_type),
					"object_type": int(blocked.object_type),
				}
		var gap: float = next_point.y - float(ground_height.call(next_point.x, next_point.z))
		time += step_seconds
		travelled += point.distance_to(next_point)
		if gap <= 0.0:
			# Interpolate the crossing, or the pipper jitters by a whole step as
			# the aircraft drifts.
			var span := previous_gap - gap
			var fraction: float = previous_gap / span if span > 0.0001 else 0.0
			var impact := point.lerp(next_point, fraction)
			return {
				"point": impact,
				"range": origin.distance_to(impact),
				"time": time - step_seconds * (1.0 - fraction),
			}
		point = next_point
		velocity = next_velocity
		previous_gap = gap
	return {}


## How long and how far this projectile may fly before the manager retires it.
## Read per round rather than per manager, because a rocket judged by the 30 mm
## shell's four kilometres would die with its motor still burning.
func envelope_seconds() -> float:
	return maximum_flight_seconds


func envelope_metres() -> float:
	return maximum_range
