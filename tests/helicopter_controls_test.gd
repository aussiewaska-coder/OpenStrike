extends SceneTree

const FLIGHT_MATH := preload("res://scripts/helicopter/flight_math.gd")


func _init() -> void:
	_assert_vector(FLIGHT_MATH.get_planar_control(Basis.IDENTITY, Vector2(0.0, -1.0)), Vector3.RIGHT, "forward follows +X nose")
	_assert_vector(FLIGHT_MATH.get_planar_control(Basis.IDENTITY, Vector2(0.0, 1.0)), Vector3.LEFT, "backward opposes nose")
	_assert_vector(FLIGHT_MATH.get_planar_control(Basis.IDENTITY, Vector2(1.0, 0.0)), Vector3.BACK, "left-stick right strafes right")
	var yawed_basis := Basis(Vector3.UP, -PI * 0.5)
	_assert_vector(FLIGHT_MATH.get_planar_control(yawed_basis, Vector2(0.0, -1.0)), Vector3.BACK, "forward rotates with helicopter")
	_assert_vector(FLIGHT_MATH.get_planar_control(yawed_basis, Vector2(1.0, 0.0)), Vector3.LEFT, "strafe rotates with helicopter")
	print("HELICOPTER_CONTROLS_TEST_PASS")
	quit()


func _assert_vector(actual: Vector3, expected: Vector3, label: String) -> void:
	if not actual.is_equal_approx(expected):
		push_error("%s: expected %s, got %s" % [label, expected, actual])
		quit(1)
