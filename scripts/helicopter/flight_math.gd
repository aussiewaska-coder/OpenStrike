extends RefCounted


static func get_planar_control(vehicle_basis: Basis, flight: Vector2) -> Vector3:
	# The Apache GLB's visible nose points along local +X.
	var nose_direction := vehicle_basis.x
	nose_direction.y = 0.0
	nose_direction = nose_direction.normalized()
	var right_direction := Vector3(-nose_direction.z, 0.0, nose_direction.x)
	var planar_input := nose_direction * -flight.y + right_direction * flight.x
	if planar_input.length_squared() > 1.0:
		planar_input = planar_input.normalized()
	return planar_input


## Drives the current velocity toward the commanded one. A drone's stick asks
## for a speed, not a push: a centred stick brakes hard and holds, so stopping
## uses a higher rate than accelerating.
static func approach_velocity(
	velocity: Vector3,
	target_velocity: Vector3,
	acceleration: float,
	braking: float,
	delta: float
) -> Vector3:
	var rate := acceleration if target_velocity.length_squared() > 0.001 else braking
	return velocity.move_toward(target_velocity, rate * delta)


## Splits a world velocity into the aircraft's own forward and lateral speeds,
## which is what the airframe tilts against.
static func get_body_velocity(vehicle_basis: Basis, velocity: Vector3) -> Vector2:
	var nose_direction := vehicle_basis.x
	nose_direction.y = 0.0
	if nose_direction.is_zero_approx():
		return Vector2.ZERO
	nose_direction = nose_direction.normalized()
	var right_direction := Vector3(-nose_direction.z, 0.0, nose_direction.x)
	return Vector2(velocity.dot(nose_direction), velocity.dot(right_direction))
