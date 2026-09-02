extends SceneTree

const FIXED_GUN_MOUNT := preload("res://scripts/weapons/fixed_gun_mount.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var gun: Node3D = FIXED_GUN_MOUNT.new()
	root.add_child(gun)
	await process_frame
	gun.basis = Basis(Vector3.UP, 0.4)
	var before := gun.global_basis
	gun.apply_aim(50.0, -20.0)
	gun.kick()
	assert(gun.global_basis.is_equal_approx(before), "fixed gun must ignore traversing aim")
	assert(gun.find_children("*", "MeshInstance3D", true, false).is_empty(), "fixed gun must have no visible model")
	assert(gun.get_muzzle_direction().is_equal_approx(gun.global_basis.x.normalized()), "fixed gun must fire along the nose")
	print("FIXED_GUN_MOUNT_TEST_PASS")
	quit()
