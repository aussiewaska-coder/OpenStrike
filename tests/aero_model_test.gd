extends SceneTree

var _test_failed := false

## The constants in aero_model.gd are derived from the envelope rather than
## chosen, and these are the derivations, asserted. If a coefficient is retuned
## and one of these fails, the retune broke a relationship the flight model
## depends on -- not merely a number someone liked.

const AERO := preload("res://scripts/jet/aero_model.gd")

## The Raptor, so every number below means what it did when it was written.
var aero = AERO.new()

const KNOT_MPS := 0.5144


func _init() -> void:
	_lift_curve()
	_drag_polar()
	_lift_is_perpendicular_to_flight()
	_thrust()
	_turn_limits()
	_envelope()
	if _test_failed:
		return
	print("AERO_MODEL_TEST_PASS")
	quit()


func _lift_curve() -> void:
	_assert_approx(aero.lift_coefficient(0.0), 0.0, "no lift coefficient at zero alpha")

	# It must rise monotonically to the stall: a dip would read as the aircraft
	# sagging as it pulls.
	var previous := -1.0
	var stall := deg_to_rad(aero.airframe.stall_alpha_degrees)
	for step in range(0, 241):
		var alpha := deg_to_rad(float(step) * 0.1)
		if alpha > stall:
			break
		var lift: float = aero.lift_coefficient(alpha)
		if lift < previous - 0.0001:
			_fail("lift coefficient dipped at %f degrees" % rad_to_deg(alpha))
		previous = lift

	_assert_approx(aero.lift_coefficient(stall), aero.airframe.cl_max(), "the stall angle is where lift peaks")

	# Past the stall it must fall away, or the model cannot express a stall at
	# all and the limiter is guarding nothing.
	if aero.lift_coefficient(stall + deg_to_rad(5.0)) >= aero.airframe.cl_max():
		_fail("lift must fall away past the stall angle")

	# Symmetric: pushing must work the same as pulling.
	_assert_approx(
		aero.lift_coefficient(-0.2),
		-aero.lift_coefficient(0.2),
		"the lift curve is symmetric about zero alpha"
	)


func _drag_polar() -> void:
	# Induced drag follows the square of the lift coefficient. This one term is
	# why hard turns cost speed, so it is worth pinning exactly.
	var at_one: float = aero.drag_coefficient(1.0, 100.0) - aero.drag_coefficient(0.0, 100.0)
	var at_two: float = aero.drag_coefficient(2.0, 100.0) - aero.drag_coefficient(0.0, 100.0)
	if absf(at_two - at_one * 4.0) > 0.0001:
		_fail("induced drag must go as the square of lift: %f then %f" % [at_one, at_two])

	# Wave drag is zero below the divergence speed and rising above it.
	_assert_approx(aero.wave_drag(aero.airframe.drag_divergence_mps), 0.0, "no wave drag below divergence")
	_assert_approx(aero.wave_drag(100.0), 0.0, "no wave drag in the cruise")
	if aero.wave_drag(260.0) <= aero.wave_drag(220.0):
		_fail("wave drag must rise with speed past divergence")

	# A hard turn must cost several times the level drag, or energy management
	# is not a thing the player has to think about.
	var level: float = aero.drag_acceleration(155.0, _trim_alpha(155.0))
	var hard: float = aero.drag_acceleration(155.0, deg_to_rad(aero.airframe.stall_alpha_degrees))
	if hard <= level * 3.0:
		_fail("a hard turn must cost over three times the level drag: %f against %f" % [hard, level])

	# And it must cost more than the engines can replace, or a sustained turn
	# is free and nothing is at stake.
	var afterburner: float = aero.thrust_acceleration(1.0, 1.0)
	if afterburner >= hard:
		_fail("a sustained 9G turn must lose speed even in afterburner")


func _lift_is_perpendicular_to_flight() -> void:
	var velocity := Vector3(100.0, -30.0, 10.0)
	var direction := aero.lift_direction(Vector3.UP, velocity)
	_assert_approx(
		direction.dot(velocity.normalized()),
		0.0,
		"lift must do no work along the flight path"
	)
	if direction.dot(Vector3.UP) <= 0.0:
		_fail("lift must still act toward the wing's upper side")
	_assert_approx(direction.length(), 1.0, "lift direction is normalized")


func _thrust() -> void:
	var idle: float = aero.thrust_acceleration(0.0, 0.0)
	var military: float = aero.thrust_acceleration(1.0, 0.0)
	var wet: float = aero.thrust_acceleration(1.0, 1.0)
	if idle <= 0.0:
		_fail("a jet engine still pushes with the throttle closed")
	if not (idle < military and military < wet):
		_fail("thrust must rise through idle, military and afterburner")

	# Engines spool rather than step: this is what makes the throttle command a
	# thrust rather than a speed.
	var setting := 0.0
	var previous := -1.0
	for _step in range(0, 200):
		setting = aero.spool(setting, 1.0, 1.6, 1.0 / 60.0)
		if setting < previous:
			_fail("spooling must be monotonic toward its command")
		previous = setting
	if setting <= 0.98:
		_fail("the engine must reach its commanded setting, got %f" % setting)
	_assert_approx(aero.spool(0.5, 0.5, 1.6, 0.016), 0.5, "a matched command does not move the engine")


func _turn_limits() -> void:
	# Corner speed is not a chosen number: it is where the wing's limit and the
	# airframe's limit cross. Everything about turning depends on this holding.
	_assert_approx(
		aero.aerodynamic_load_limit(aero.airframe.corner_speed_mps()),
		aero.airframe.load_limit_g,
		"the aerodynamic and load limits must meet at corner speed"
	)
	if aero.aerodynamic_load_limit(110.0) >= aero.airframe.load_limit_g:
		_fail("below corner speed the wing must run out of lift first")
	if aero.aerodynamic_load_limit(230.0) <= aero.airframe.load_limit_g:
		_fail("above corner speed the load limiter must bind first")

	# The load limiter caps pitch rate, and because n = v * omega / g that cap
	# falls as speed rises. Fast turns are therefore wide turns.
	var previous_rate := 1000.0
	var previous_radius := -1.0
	for speed in [110.0, 155.0, 200.0, 260.0]:
		var rate: float = aero.load_limited_pitch_rate(speed, 10.0)
		var radius: float = speed / rate
		if rate > previous_rate:
			_fail("pitch rate must not rise with speed, at %f m/s" % speed)
		if radius <= previous_radius:
			_fail("turn radius must grow with speed, at %f m/s" % speed)
		_assert_approx(
			aero.load_factor(speed, rate),
			aero.airframe.load_limit_g,
			"a limited pitch rate pulls exactly the limit at %f m/s" % speed
		)
		previous_rate = rate
		previous_radius = radius

	# A gentle command must pass through untouched.
	_assert_approx(
		aero.load_limited_pitch_rate(155.0, 0.1),
		0.1,
		"the limiter leaves a gentle command alone"
	)
	# And it must work symmetrically, or pushing behaves differently to pulling.
	_assert_approx(
		aero.load_limited_pitch_rate(260.0, -10.0),
		-aero.load_limited_pitch_rate(260.0, 10.0),
		"the load limiter is symmetric"
	)


func _envelope() -> void:
	# The mush point is derived from the lift curve, so retuning lift moves it
	# rather than leaving a stale constant behind.
	var mush: float = aero.mush_speed()
	if mush >= 90.0:
		_fail("the mush point must sit below the cruise envelope, got %f m/s" % mush)
	if mush <= 30.0:
		_fail("a mush point this low is unreachable and the degraded state is dead code")

	# Level flight must be possible across the whole stated envelope, and must
	# need more alpha the slower it is flown.
	var slow := _trim_alpha(90.0)
	var fast := _trim_alpha(260.0)
	if slow <= fast:
		_fail("slower flight must need more alpha")
	if slow >= deg_to_rad(aero.airframe.stall_alpha_degrees):
		_fail("the envelope floor must not itself be a stall")
	var altitude_falloff := aero.altitude_falloff(900.0, 6000.0)
	var launch_trim := aero.trim_alpha(175.0, altitude_falloff)
	_assert_approx(
		aero.lift_acceleration(175.0, launch_trim) * altitude_falloff,
		AERO.GRAVITY,
		"launch trim balances gravity at spawn altitude"
	)

	# Angle of attack is read off the body velocity; pitching the nose up
	# without changing the flight path must show as positive alpha.
	var angles: Vector2 = aero.alpha_beta(Vector3(100.0, -10.0, 0.0))
	if angles.x <= 0.0:
		_fail("velocity below the nose must read as positive alpha")
	var slipping: Vector2 = aero.alpha_beta(Vector3(100.0, 0.0, 10.0))
	if slipping.y <= 0.0:
		_fail("velocity out to the right must read as positive sideslip")
	_assert_approx(aero.alpha_beta(Vector3(100.0, 0.0, 0.0)).x, 0.0, "flying along the nose is zero alpha")

	# The ceiling is soft: thrust and lift fade rather than the aircraft
	# striking a limit.
	_assert_approx(aero.altitude_falloff(0.0, 6000.0), 1.0, "full performance on the deck")
	if aero.altitude_falloff(6000.0, 6000.0) >= aero.altitude_falloff(3000.0, 6000.0):
		_fail("performance must fall away with altitude")
	if aero.altitude_falloff(6000.0, 6000.0) <= 0.0:
		_fail("the ceiling must be soft, not a wall")


## The angle of attack that holds level flight at a given speed.
func _trim_alpha(speed: float) -> float:
	return aero.trim_alpha(speed)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 0.001:
		_fail("%s: expected %f, got %f" % [label, expected, actual])


func _fail(message: String) -> void:
	_test_failed = true
	push_error(message)
	quit(1)
