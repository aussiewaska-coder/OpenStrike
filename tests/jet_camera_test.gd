extends SceneTree

const JET_CAMERA := preload("res://scripts/camera/jet_camera.gd")


func _init() -> void:
	assert(
		is_zero_approx(JET_CAMERA.routed_orbit_input(0.8, true, false)),
		"the F-22 throttle triggers must not also move the camera"
	)
	assert(
		is_zero_approx(JET_CAMERA.routed_orbit_input(-0.8, false, true)),
		"helicopter target orbit must own the triggers before the camera"
	)
	assert(
		is_equal_approx(JET_CAMERA.routed_orbit_input(0.65, false, false), 0.65),
		"free helicopter triggers must still sweep the camera"
	)
	assert(
		is_equal_approx(JET_CAMERA.trailing_distance(175.0, 90.0, 260.0, 42.0, 26.0), 55.0),
		"the jet chase distance must retain its speed response"
	)
	print("JET_CAMERA_TEST_PASS")
	quit()
