extends SceneTree

const FLIGHT_MATH := preload("res://scripts/helicopter/flight_math.gd")


func _init() -> void:
	_assert_vector(FLIGHT_MATH.get_planar_control(Basis.IDENTITY, Vector2(0.0, -1.0)), Vector3.RIGHT, "forward follows +X nose")
	_assert_vector(FLIGHT_MATH.get_planar_control(Basis.IDENTITY, Vector2(0.0, 1.0)), Vector3.LEFT, "backward opposes nose")
	_assert_vector(FLIGHT_MATH.get_planar_control(Basis.IDENTITY, Vector2(1.0, 0.0)), Vector3.BACK, "left-stick right strafes right")
	var yawed_basis := Basis(Vector3.UP, -PI * 0.5)
	_assert_vector(FLIGHT_MATH.get_planar_control(yawed_basis, Vector2(0.0, -1.0)), Vector3.BACK, "forward rotates with helicopter")
	_assert_vector(FLIGHT_MATH.get_planar_control(yawed_basis, Vector2(1.0, 0.0)), Vector3.LEFT, "strafe rotates with helicopter")

	# The stick commands a speed: velocity climbs toward it at the acceleration
	# rate and never overshoots it.
	_assert_vector(
		FLIGHT_MATH.approach_velocity(Vector3.ZERO, Vector3.RIGHT * 118.0, 68.0, 110.0, 1.0),
		Vector3.RIGHT * 68.0,
		"accelerates toward the commanded speed"
	)
	_assert_vector(
		FLIGHT_MATH.approach_velocity(Vector3.RIGHT * 10.0, Vector3.RIGHT * 11.0, 68.0, 110.0, 1.0),
		Vector3.RIGHT * 11.0,
		"never overshoots the commanded speed"
	)
	# Centring the stick brakes at the higher rate and stops dead rather than
	# coasting on, the way a drone in position hold does.
	_assert_vector(
		FLIGHT_MATH.approach_velocity(Vector3.RIGHT * 50.0, Vector3.ZERO, 68.0, 110.0, 1.0),
		Vector3.ZERO,
		"a centred stick stops the aircraft"
	)
	_assert_vector(
		FLIGHT_MATH.approach_velocity(Vector3.RIGHT * 118.0, Vector3.ZERO, 68.0, 110.0, 0.1),
		Vector3.RIGHT * 107.0,
		"braking is harder than acceleration"
	)

	# The airframe tilts against its own forward and lateral speed, so the tilt
	# survives a yaw and reads as real movement.
	_assert_vector2(
		FLIGHT_MATH.get_body_velocity(Basis.IDENTITY, Vector3.RIGHT * 10.0),
		Vector2(10.0, 0.0),
		"velocity along the nose is forward speed"
	)
	_assert_vector2(
		FLIGHT_MATH.get_body_velocity(Basis.IDENTITY, Vector3.BACK * 10.0),
		Vector2(0.0, 10.0),
		"velocity across the nose is lateral speed"
	)
	_assert_vector2(
		FLIGHT_MATH.get_body_velocity(yawed_basis, Vector3.BACK * 10.0),
		Vector2(10.0, 0.0),
		"body velocity rotates with the helicopter"
	)
	print("HELICOPTER_CONTROLS_TEST_PASS")
	quit()


func _assert_vector(actual: Vector3, expected: Vector3, label: String) -> void:
	if not actual.is_equal_approx(expected):
		push_error("%s: expected %s, got %s" % [label, expected, actual])
		quit(1)


func _assert_vector2(actual: Vector2, expected: Vector2, label: String) -> void:
	if not actual.is_equal_approx(expected):
		push_error("%s: expected %s, got %s" % [label, expected, actual])
		quit(1)
