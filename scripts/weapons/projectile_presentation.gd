extends RefCounted

## Model, camera and reticle must consume the same rendered point.
static func position_of(round_data: RefCounted) -> Vector3:
	return round_data.previous_position.lerp(round_data.position, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))

## Parallel-transport the previous up vector instead of switching axes at a
## pitch threshold. This remains continuous through vertical dives.
static func transported_up(forward: Vector3, previous_up: Vector3) -> Vector3:
	var up := previous_up - forward * previous_up.dot(forward)
	if up.length_squared() < 0.00001:
		var reference := Vector3.RIGHT if absf(forward.x) < 0.9 else Vector3.FORWARD
		up = reference - forward * reference.dot(forward)
	return up.normalized()
