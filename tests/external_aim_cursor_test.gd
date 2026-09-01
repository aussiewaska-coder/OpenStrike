extends SceneTree

const CURSOR := preload("res://scripts/camera/external_aim_cursor.gd")


func _init() -> void:
	var aim := CURSOR.new()
	for _frame in range(6):
		aim.update(Vector2(-0.45, 0.0), true, 1.0 / 60.0)
	assert(absf(aim.cursor_offset.x) > 0.05, "R1 stick must move the target cursor")
	assert(aim.camera_offset.is_zero_approx(), "camera must stay fixed inside the aim window")
	var inside_cursor := aim.cursor_offset
	for _frame in range(30):
		aim.update(Vector2.ZERO, true, 1.0 / 60.0)
	assert(aim.camera_offset.is_zero_approx(), "stopping inside the aim window must not move the camera")
	assert(aim.cursor_offset.distance_to(inside_cursor) < 0.001, "inside target must hold its screen offset")

	for _frame in range(90):
		aim.update(Vector2(-1.0, 0.0), true, 1.0 / 60.0)
	assert(absf(aim.cursor_offset.x) <= aim.cursor_edge.x + 0.001, "cursor must stay inside its screen window")
	assert(aim.camera_offset.x > 0.1, "edge overflow must drag the camera")

	var world_aim_before := aim.combined_offset()
	for _frame in range(90):
		aim.update(Vector2.ZERO, true, 1.0 / 60.0)
	assert(aim.cursor_offset.length() < 0.02, "stopped stick must let the camera catch up to centre")
	assert(aim.combined_offset().distance_to(world_aim_before) < 0.01, "camera catch-up must preserve the world target")

	var forward := CURSOR.ray_direction(Basis.IDENTITY, 60.0, 16.0 / 9.0, Vector2.ZERO)
	assert(forward.is_equal_approx(Vector3.FORWARD), "centred target must project down camera forward")
	var right := CURSOR.ray_direction(Basis.IDENTITY, 60.0, 16.0 / 9.0, Vector2(0.5, 0.0))
	assert(right.x > 0.0 and right.z < 0.0, "right target must project right of camera forward")
	print("EXTERNAL_AIM_CURSOR_TEST_PASS")
	quit()
