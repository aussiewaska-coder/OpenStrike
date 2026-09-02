extends Node3D

## Logical muzzle for an internal, fixed-forward gun. It deliberately creates
## no geometry and ignores the shared helicopter turret's aim commands.


func apply_aim(_yaw_degrees: float, _pitch_degrees: float) -> void:
	pass


func kick() -> void:
	pass


func get_muzzle_transform() -> Transform3D:
	return global_transform


func get_muzzle_direction() -> Vector3:
	return global_basis.x.normalized()
