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
