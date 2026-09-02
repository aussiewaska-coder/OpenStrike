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
	var moved := JET_CAMERA.updated_look(Vector2.ZERO, Vector2(0.5, -0.25), 2.0, 6.0, 0.5)
	assert(moved.is_equal_approx(Vector2(-0.5, 0.25)), "right stick must move the jet camera look")
	var returned := JET_CAMERA.updated_look(moved, Vector2.ZERO, 2.0, 6.0, 0.5)
	assert(returned.length() < moved.length(), "released right stick must return the jet view")
	var focus := Vector3(10.0, 20.0, 30.0)
	var behind := focus + Vector3(0.0, 4.0, 20.0)
	var orbited := JET_CAMERA.orbited_position(focus, behind, Basis(Vector3.UP, PI * 0.5))
	assert(is_equal_approx(orbited.distance_to(focus), behind.distance_to(focus)), "look orbit must preserve camera distance")
	print("JET_CAMERA_TEST_PASS")
	quit()
