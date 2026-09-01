extends SceneTree

const FEEDBACK := preload("res://scripts/camera/arcade_camera_feedback.gd")


func _init() -> void:
	assert(is_zero_approx(FEEDBACK.speed_fov_offset(0.0, 118.0, 9.0)), "hover must keep the authored FOV")
	assert(FEEDBACK.speed_fov_offset(59.0, 118.0, 9.0) > 0.0, "speed must widen the lens")
	assert(is_equal_approx(FEEDBACK.speed_fov_offset(118.0, 118.0, 9.0), 9.0), "maximum speed must reach the FOV boost")
	assert(is_equal_approx(FEEDBACK.speed_fov_offset(200.0, 118.0, 9.0), 9.0), "FOV boost must clamp")

	var near := FEEDBACK.new()
	near.add_impact(30.0, true)
	var near_trauma: float = near.trauma
	var far := FEEDBACK.new()
	far.add_impact(1200.0, true)
	assert(near_trauma > far.trauma, "near explosions must shake harder")
	var rotation: Vector3 = near.update(1.0 / 60.0)
	assert(not rotation.is_zero_approx(), "impact trauma must produce camera rotation")
	for _step in range(180):
		near.update(1.0 / 60.0)
	assert(is_zero_approx(near.trauma), "shake must decay completely")
	print("ARCADE_CAMERA_FEEDBACK_TEST_PASS")
	quit()
