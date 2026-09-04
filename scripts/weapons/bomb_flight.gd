extends RefCounted

## Free fall. A bomb is a shell with no muzzle velocity: it leaves at the
## carrier's speed and gravity and drag do the rest. It shares the projectile
## manager with shells and rockets, so it hits buildings through the same swept
## segment query and the same damage path.

const GRAVITY := 9.80665
## Draggier than a shell -- an iron bomb is a blunt shape -- but not by much at
## the speeds a drone releases at.
const DRAG_PER_SECOND := 0.12
## From 900 m it takes about 14 s to land; the envelope is generous so a bomb
## never expires in the air.
const MAX_FLIGHT_SECONDS := 40.0
const MAX_RANGE_METRES := 6000.0


func release_velocity(carrier_velocity: Vector3) -> Vector3:
	return carrier_velocity


## Trapezoidal like ballistics.advance, so bombs integrate the way everything
## else does and the hit query sees consistent segments.
func advance(point: Vector3, velocity: Vector3, delta: float, _age := 0.0) -> Array:
	var next_velocity := velocity * exp(-DRAG_PER_SECOND * delta)
	next_velocity.y -= GRAVITY * delta
	var next_point := point + (velocity + next_velocity) * 0.5 * delta
	return [next_point, next_velocity]


func envelope_seconds() -> float:
	return MAX_FLIGHT_SECONDS


func envelope_metres() -> float:
	return MAX_RANGE_METRES
