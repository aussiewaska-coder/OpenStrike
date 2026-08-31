extends SceneTree

const ORBIT_LOCK := preload("res://scripts/camera/orbit_lock.gd")


func _init() -> void:
	var lock := ORBIT_LOCK.new()
	# Engaging must not move the camera: everything is read back off where it
	# already is.
	lock.engage(Vector3(0.0, 50.0, 100.0), Vector3.ZERO)
	_assert_approx(lock.radius, 100.0, "radius comes from the current camera")
	_assert_approx(lock.height, 50.0, "height comes from the current camera")
	_assert_approx(lock.angle, 0.0, "heading matches the trailing convention")
	_assert_vector(lock.camera_position(), Vector3(0.0, 50.0, 100.0), "engage round trips")

	# A quarter turn with an effectively instant response lands a quarter of the
	# way around the circle, at the same radius and height.
	lock.advance(1.0, 1.0, PI * 0.5, 1000.0)
	_assert_approx(lock.angle, PI * 0.5, "sweep integrates the commanded rate")
	var swept := lock.camera_position()
	_assert_vector(swept, Vector3(100.0, 50.0, 0.0), "sweep stays on the circle")
	_assert_approx(Vector2(swept.x, swept.z).length(), 100.0, "radius is preserved")
	_assert_approx(swept.y, 50.0, "height is preserved")

	# The pivot is locked to the world, so it never trails the aircraft.
	_assert_vector(lock.pivot, Vector3.ZERO, "pivot stays where it was dropped")

	lock.release()
	if lock.active:
		push_error("release must clear the lock")
		quit(1)

	# A pivot directly under the camera cannot produce a zero-length radius.
	lock.engage(Vector3(0.0, 40.0, 0.0), Vector3.ZERO)
	if lock.radius <= 0.0:
		push_error("degenerate radius: got %f" % lock.radius)
		quit(1)
	print("CAMERA_ORBIT_LOCK_TEST_PASS")
	quit()


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 0.001:
		push_error("%s: expected %f, got %f" % [label, expected, actual])
		quit(1)


func _assert_vector(actual: Vector3, expected: Vector3, label: String) -> void:
	if not actual.is_equal_approx(expected):
		push_error("%s: expected %s, got %s" % [label, expected, actual])
		quit(1)
