extends SceneTree

const EXTERNAL_FREE_LOOK := preload("res://scripts/camera/external_free_look.gd")


func _init() -> void:
	var focus := Vector3.ZERO
	var follow_position := Vector3(0.0, 50.0, 100.0)
	var held_aim := Basis(Vector3.UP, deg_to_rad(25.0))
	var first_frame: Vector3 = EXTERNAL_FREE_LOOK.look_target(
		follow_position,
		focus,
		held_aim
	)
	var second_frame: Vector3 = EXTERNAL_FREE_LOOK.look_target(
		follow_position,
		focus,
		held_aim
	)
	if not second_frame.is_equal_approx(first_frame):
		push_error("held external aim accumulated another rotation: %s -> %s" % [first_frame, second_frame])
		quit(1)
		return
	var base_direction: Vector3 = (focus - follow_position).normalized()
	var aim_direction: Vector3 = (first_frame - follow_position).normalized()
	if aim_direction.is_equal_approx(base_direction):
		push_error("held external aim still points at the helicopter")
		quit(1)
		return
	print("EXTERNAL_FREE_LOOK_TEST_PASS")
	quit()
