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


## Marches the round until it crosses the terrain, returning the impact point,
## slant range and time of flight. Returns an empty dictionary when nothing is
## hit inside the maximum range — the sight then has no firing solution to show.
func solve(origin: Vector3, direction: Vector3, ground_height: Callable) -> Dictionary:
	if direction.is_zero_approx() or step_seconds <= 0.0:
		return {}
	var velocity := direction.normalized() * muzzle_velocity
	var point := origin
	var time := 0.0
	var travelled := 0.0
	var previous_gap: float = point.y - float(ground_height.call(point.x, point.z))
	var decay := exp(-drag_per_second * step_seconds)
	while travelled < maximum_range and time < maximum_flight_seconds:
		var next_velocity := velocity * decay
		next_velocity.y -= GRAVITY * step_seconds
		var next_point := point + (velocity + next_velocity) * 0.5 * step_seconds
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
