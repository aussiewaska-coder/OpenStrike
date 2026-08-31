extends SceneTree

const ZOOM_PROFILE := preload("res://scripts/camera/zoom_profile.gd")

const TACTICAL_DISTANCE := 110.0
const TACTICAL_HEIGHT := 150.0


func _init() -> void:
	var profile := ZOOM_PROFILE.new()

	# Above the attack range nothing about the established framing changes.
	_assert_approx(profile.height_multiplier(1.0), 1.0, "neutral zoom is unscaled")
	_assert_approx(profile.distance_multiplier(1.0), 1.0, "neutral distance is unscaled")
	_assert_approx(profile.fov(1.0), 42.0, "neutral zoom keeps the base field of view")
	_assert_approx(profile.height_multiplier(0.68), 0.68, "old close limit is unbiased")
	_assert_approx(profile.fov(0.68), 42.0, "old close limit keeps the base field of view")

	# At full attack zoom the camera sits close and low, with a wide lens.
	_assert_approx(profile.distance_multiplier(0.17) * TACTICAL_DISTANCE, 18.7, "attack distance")
	_assert_approx(profile.height_multiplier(0.17) * TACTICAL_HEIGHT, 8.925, "attack height")
	_assert_approx(profile.fov(0.17), 78.0, "attack field of view")

	# Height must fall away faster than distance, or the close-up is just a
	# smaller top-down view rather than an attack run.
	var distance_ratio := profile.distance_multiplier(0.17) / profile.distance_multiplier(0.68)
	var height_ratio := profile.height_multiplier(0.17) / profile.height_multiplier(0.68)
	if height_ratio >= distance_ratio:
		push_error("height must compress harder than distance: %f vs %f" % [height_ratio, distance_ratio])
		quit(1)

	# Stepping is proportional and stays inside the range at both ends.
	_assert_approx(profile.step(0.68, 0.8, true, 1.45), 0.544, "a press in scales by the ratio")
	_assert_approx(profile.step(0.544, 0.8, false, 1.45), 0.68, "a press out is the inverse")
	_assert_approx(profile.step(0.17, 0.8, true, 1.45), 0.17, "cannot zoom past the attack limit")
	_assert_approx(profile.step(1.45, 0.8, false, 1.45), 1.45, "cannot zoom past the far limit")
	print("CAMERA_ZOOM_PROFILE_TEST_PASS")
	quit()


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 0.001:
		push_error("%s: expected %f, got %f" % [label, expected, actual])
		quit(1)
