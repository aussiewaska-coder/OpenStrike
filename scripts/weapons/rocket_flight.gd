extends RefCounted

## Powered flight for an unguided rocket, in two phases.
##
## Boost: the motor pushes along the rocket's own heading and dominates gravity,
## so the rocket flies nearly straight and gains speed fast. Coast: the motor is
## out and the rocket is a shell -- gravity and drag, the same terms
## ballistics.gd already uses.
##
## The visible point of modelling it at all is the transition. A salvo climbs
## away hard, then noticeably droops when the motors quit, and that droop is
## what makes a salvo legible as rockets rather than as very fast bullets.

const GRAVITY := 9.80665

## Short, like a real folding-fin aerial rocket. A long burn would flatten the
## trajectory into a laser and take the droop away with it.
const MOTOR_BURN_SECONDS := 1.6
## Along the heading, in m/s^2. Roughly 12 g, which takes a rocket ejected at
## 25 m/s to a few hundred by burnout.
const MOTOR_ACCELERATION := 118.0
## Off the rail before the motor lights. Deliberately small: the motor is what
## makes a rocket quick, and a big rail impulse reads as a railgun.
const EJECTION_SPEED := 25.0
## Slightly slicker than the 30 mm shell -- a fin-stabilised rocket is a better
## shape than a spinning slug.
const DRAG_PER_SECOND := 0.055
## Its own envelope. Borrowing the gun's four kilometres would have retired a
## rocket with its motor still burning.
const MAX_FLIGHT_SECONDS := 26.0
const MAX_RANGE_METRES := 7000.0


func is_boosting(age: float) -> bool:
	return age < MOTOR_BURN_SECONDS


## Thrust along the current heading, then gravity and drag on everything.
func advance(point: Vector3, velocity: Vector3, delta: float, age := 0.0) -> Array:
	var next_velocity := velocity * exp(-DRAG_PER_SECOND * delta)
	if is_boosting(age) and not velocity.is_zero_approx():
		next_velocity += velocity.normalized() * MOTOR_ACCELERATION * delta
	next_velocity.y -= GRAVITY * delta
	# Trapezoidal, matching ballistics.advance, so rockets and shells integrate
	# the same way and a fast rocket cannot out-run its own hit query.
	var next_point := point + (velocity + next_velocity) * 0.5 * delta
	return [next_point, next_velocity]


func launch_velocity(direction: Vector3, inherited_velocity: Vector3) -> Vector3:
	return direction.normalized() * EJECTION_SPEED + inherited_velocity


func envelope_seconds() -> float:
	return MAX_FLIGHT_SECONDS


func envelope_metres() -> float:
	return MAX_RANGE_METRES
