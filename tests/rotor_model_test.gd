extends SceneTree

## The numbers here are the researched ones, not invented: effective
## translational lift at 16-20 kt, gains stopping around 45 kt, transverse flow
## at 12-15 kt arriving before ETL, and vortex ring state needing a 300 ft/min
## descent and being impossible above translational lift.

const ROTOR := preload("res://scripts/helicopter/rotor_model.gd")
const GAIN := 0.17


func _init() -> void:
	# Hover gets no translational lift; the plateau gets all of it.
	_assert_approx(ROTOR.translational_lift(0.0, GAIN), 1.0, "a hover has no translational lift")
	_assert_approx(ROTOR.translational_lift(30.0, GAIN), 1.0 + GAIN, "gains stop at the plateau")
	_assert_approx(
		ROTOR.translational_lift(ROTOR.ETL_PLATEAU_MPS, GAIN),
		1.0 + GAIN,
		"45 kt is the plateau"
	)

	# It must rise monotonically -- a dip would read as the aircraft sagging as
	# it accelerates.
	var previous := 0.0
	for step in range(0, 400):
		var speed := float(step) * 0.1
		var lift: float = ROTOR.translational_lift(speed, GAIN)
		if lift < previous - 0.0001:
			push_error("translational lift dipped at %f m/s" % speed)
			quit(1)
		previous = lift

	# The 16-20 kt band must be the steepest part of the curve: that jump is
	# what a pilot feels as the aircraft climbing through ETL.
	var band_gain: float = ROTOR.translational_lift(ROTOR.ETL_END_MPS, GAIN) - ROTOR.translational_lift(ROTOR.ETL_START_MPS, GAIN)
	var pre_gain: float = ROTOR.translational_lift(ROTOR.ETL_START_MPS, GAIN) - 1.0
	var post_gain: float = ROTOR.translational_lift(ROTOR.ETL_PLATEAU_MPS, GAIN) - ROTOR.translational_lift(ROTOR.ETL_END_MPS, GAIN)
	if band_gain <= pre_gain or band_gain <= post_gain:
		push_error("the ETL band must dominate: pre %f band %f post %f" % [pre_gain, band_gain, post_gain])
		quit(1)

	# Ground effect: strongest on the deck, gone by a rotor diameter up.
	_assert_approx(ROTOR.ground_effect(0.0, 14.63, 0.12), 1.12, "full cushion on the surface")
	_assert_approx(ROTOR.ground_effect(14.63, 14.63, 0.12), 1.0, "no cushion a rotor diameter up")
	_assert_approx(ROTOR.ground_effect(100.0, 14.63, 0.12), 1.0, "no cushion in the cruise")

	# Vortex ring state needs a real descent, and cannot happen above
	# translational lift no matter how hard the aircraft is dropping.
	_assert_approx(ROTOR.vortex_ring(0.5, 0.0, 0.35), 1.0, "a gentle descent is safe")
	_assert_approx(ROTOR.vortex_ring(6.0, 20.0, 0.35), 1.0, "flying forward escapes vortex ring state")
	var settling: float = ROTOR.vortex_ring(6.0, 0.0, 0.35)
	if settling >= 1.0:
		push_error("a vertical drop below ETL must lose lift, got %f" % settling)
		quit(1)
	if ROTOR.vortex_ring(6.0, 5.0, 0.35) <= settling:
		push_error("some forward speed must ease vortex ring state")
		quit(1)

	# Transverse flow lives in its own band and, crucially, ends before ETL
	# begins -- mistaking it for ETL is the classic error.
	_assert_approx(ROTOR.transverse_flow(0.0), 0.0, "no shudder in a hover")
	_assert_approx(ROTOR.transverse_flow(20.0), 0.0, "no shudder in the cruise")
	if ROTOR.TRANSVERSE_END_MPS >= ROTOR.ETL_START_MPS:
		push_error("transverse flow must precede effective translational lift")
		quit(1)
	var middle := (ROTOR.TRANSVERSE_START_MPS + ROTOR.TRANSVERSE_END_MPS) * 0.5
	if ROTOR.transverse_flow(middle) <= 0.9:
		push_error("the shudder must peak mid-band, got %f" % ROTOR.transverse_flow(middle))
		quit(1)

	# Torque scales with collective: that is what makes the pedals move whenever
	# the collective does.
	_assert_approx(ROTOR.torque_yaw_degrees(0.0, 40.0), 0.0, "no collective, no torque")
	_assert_approx(ROTOR.torque_yaw_degrees(1.0, 40.0), 40.0, "full collective, full torque")
	_assert_approx(ROTOR.torque_yaw_degrees(0.5, 40.0), 20.0, "torque follows collective")

	# The disc normal is the whole model: level means no horizontal force at all,
	# and tilt is the only source of one.
	var nose := Vector3.RIGHT
	var right := Vector3.BACK
	_assert_vector(ROTOR.disc_normal(nose, right, 0.0, 0.0), Vector3.UP, "a level disc lifts straight up")
	var pitched: Vector3 = ROTOR.disc_normal(nose, right, 20.0, 0.0)
	if pitched.dot(nose) <= 0.0:
		push_error("pitching forward must push the aircraft forward")
		quit(1)
	if not is_equal_approx(pitched.length(), 1.0):
		push_error("the disc normal must stay a unit vector, got %f" % pitched.length())
		quit(1)
	var rolled: Vector3 = ROTOR.disc_normal(nose, right, 0.0, 20.0)
	if rolled.dot(right) <= 0.0:
		push_error("rolling right must push the aircraft right")
		quit(1)
	print("ROTOR_MODEL_TEST_PASS")
	quit()


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 0.001:
		push_error("%s: expected %f, got %f" % [label, expected, actual])
		quit(1)


func _assert_vector(actual: Vector3, expected: Vector3, label: String) -> void:
	if not actual.is_equal_approx(expected):
		push_error("%s: expected %s, got %s" % [label, expected, actual])
		quit(1)
