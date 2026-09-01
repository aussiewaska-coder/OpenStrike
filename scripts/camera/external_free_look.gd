class_name ExternalFreeLook
extends RefCounted


## Rotates the authored look ray while leaving the chase camera boom in place.
## ExternalAimCursor calls this only after sight overflow engages camera drag.
## Rebuilding from the base target each frame prevents accumulated spin.
static func look_target(
	camera_position: Vector3,
	base_target: Vector3,
	look_basis: Basis
) -> Vector3:
	var base_direction := base_target - camera_position
	if base_direction.is_zero_approx():
		return base_target
	var base_camera := Basis.looking_at(base_direction.normalized(), Vector3.UP)
	var aimed_direction := -(base_camera * look_basis).z.normalized()
	return camera_position + aimed_direction * base_direction.length()
