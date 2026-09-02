extends SceneTree

## The assist is what makes the aircraft flyable on a thumbstick, and one of its
## behaviours matters more than all the others: with the stick centred the
## aircraft holds its bank and flies a level turn. It does not roll upright.
## Rolling upright on release removes the pilot's job -- set a bank, ease off,
## let it fly -- and is what makes a flight model feel like a spaceship.

const ASSIST := preload("res://scripts/jet/flight_assist.gd")
const AERO := preload("res://scripts/jet/aero_model.gd")

const CRUISE := 155.0


func _init() -> void:
	_bank_hold()
	_bank_ceiling()
	_turn_geometry()
	_alpha_limiter()
	_sideslip()
	_boundary()
	print("FLIGHT_ASSIST_TEST_PASS")
	quit()


func _bank_hold() -> void:
	# Wings level with the stick centred: nothing is commanded at all. This is
	# the whole of "hold what you have".
	_assert_approx(
		ASSIST.commanded_pitch_rate(0.0, 0.95, CRUISE, 0.0, 0.0),
		0.0,
		"level flight with the stick centred commands no pitch"
	)
	_assert_approx(
		ASSIST.level_turn_yaw_rate(0.0, CRUISE),
		0.0,
		"level flight with the stick centred commands no yaw"
	)

	# Banked with the stick centred: the assist sustains the turn rather than
	# undoing it. A non-zero pitch rate here IS the bank hold.
	var held: float = ASSIST.commanded_pitch_rate(0.0, 0.95, CRUISE, deg_to_rad(45.0), 0.0)
	if held <= 0.0:
		_fail("a held bank must sustain a level turn, got %f" % held)

	# Steeper bank, more back pressure needed to hold it.
	var steeper: float = ASSIST.commanded_pitch_rate(0.0, 0.95, CRUISE, deg_to_rad(60.0), 0.0)
	if steeper <= held:
		_fail("a steeper bank must need more back pressure")

	# Symmetric: a left bank holds exactly as a right one does.
	_assert_approx(
		ASSIST.level_turn_pitch_rate(deg_to_rad(-45.0), CRUISE),
		ASSIST.level_turn_pitch_rate(deg_to_rad(45.0), CRUISE),
		"the bank hold is symmetric"
	)
	_assert_approx(
		ASSIST.level_turn_yaw_rate(deg_to_rad(-45.0), CRUISE),
		-ASSIST.level_turn_yaw_rate(deg_to_rad(45.0), CRUISE),
		"coordinated yaw reverses with the bank"
	)

	# Roll authority is the stick's alone: centred means no roll, so the bank
	# stays exactly where the pilot left it.
	_assert_approx(
		ASSIST.commanded_roll_rate(0.0, 1.8, CRUISE, 0.0, 0.0),
		0.0,
		"a centred stick commands no roll, which is what holds the bank"
	)
	_assert_approx(
		ASSIST.commanded_roll_rate(1.0, 1.8, 70.0, 0.0, 0.0),
		1.8,
		"low speed must not suppress the pilot's roll-rate command"
	)
	_assert_approx(
		ASSIST.commanded_pitch_rate(-1.0, 0.95, 79.0, deg_to_rad(66.0), deg_to_rad(18.0)),
		-0.95,
		"a hard-turn hold must not cancel the pilot's nose-down recovery"
	)


## The bank ceiling. Without it a rate-commanded roll goes straight past
## inverted, and the level-turn hold then loops the aircraft over the top rather
## than turning it -- which is exactly what the model did before this existed.
func _bank_ceiling() -> void:
	# The ceiling is the steepest bank the wing can hold a level turn at, so it
	# must tighten as the aircraft slows and never exceed the hard limit.
	var ceiling := deg_to_rad(ASSIST.MAX_COMMAND_BANK_DEGREES)
	_assert_approx(ASSIST.sustainable_bank(CRUISE), ceiling, "corner speed reaches the hard bank limit")
	_assert_approx(ASSIST.sustainable_bank(260.0), ceiling, "high speed reaches the hard bank limit")
	var slow: float = ASSIST.sustainable_bank(90.0)
	if slow >= ceiling:
		_fail("the ceiling must tighten at low speed, got %.1f degrees" % rad_to_deg(slow))
	if ASSIST.sustainable_bank(70.0) >= slow:
		_fail("the ceiling must keep tightening as the aircraft slows further")

	# At the ceiling, the level turn it implies must be one the wing can fly.
	for speed in [90.0, 110.0, 155.0, 260.0]:
		var bank: float = ASSIST.sustainable_bank(speed)
		var rate: float = ASSIST.level_turn_pitch_rate(bank, speed)
		var load: float = AERO.load_factor(speed, rate)
		var available: float = minf(AERO.LOAD_LIMIT_G, AERO.aerodynamic_load_limit(speed))
		if load > available + 0.1:
			_fail("holding the ceiling bank at %.0f m/s needs %.1f G but only %.1f is available" % [
				speed, load, available
			])

	# Well inside the ceiling the limiter must not touch the stick at all.
	_assert_approx(
		ASSIST.bank_limited_roll_rate(1.0, 0.0, 0.0, CRUISE),
		1.0,
		"the bank limiter leaves ordinary rolling alone"
	)
	# Rolling away from the ceiling is always free, because that is the recovery.
	_assert_approx(
		ASSIST.bank_limited_roll_rate(-1.0, deg_to_rad(85.0), 0.0, CRUISE),
		-1.0,
		"rolling away from the ceiling is never restricted"
	)
	# Rolling further into it is eased, then reversed.
	var eased: float = ASSIST.bank_limited_roll_rate(1.0, deg_to_rad(72.0), 0.0, CRUISE)
	if not (eased > 0.0 and eased < 1.0):
		_fail("roll into the ceiling must be eased off, got %f" % eased)
	var reversed_rate: float = ASSIST.bank_limited_roll_rate(1.0, deg_to_rad(88.0), 0.0, CRUISE)
	if reversed_rate >= 0.0:
		_fail("past the ceiling the assist must roll back, got %f" % reversed_rate)

	# The lead term is the difference between catching the bank and chasing it:
	# a fast roll must start easing earlier than a stationary one.
	var without: float = ASSIST.bank_limited_roll_rate(1.0, deg_to_rad(60.0), 0.0, CRUISE)
	var with_rate: float = ASSIST.bank_limited_roll_rate(1.0, deg_to_rad(60.0), 1.5, CRUISE)
	if with_rate >= without:
		_fail("a fast roll must be eased off earlier than a slow one")


func _turn_geometry() -> void:
	# The body rates that sustain a level turn must resolve to the familiar
	# g * tan(bank) / v heading rate. If they do not, the aircraft either climbs
	# or descends through every turn it flies.
	for degrees in [20.0, 45.0, 60.0, 75.0]:
		var bank := deg_to_rad(degrees)
		var pitch: float = ASSIST.level_turn_pitch_rate(bank, CRUISE)
		var yaw: float = ASSIST.level_turn_yaw_rate(bank, CRUISE)
		var resultant := sqrt(pitch * pitch + yaw * yaw)
		_assert_approx(
			resultant,
			absf(ASSIST.turn_rate(bank, CRUISE)),
			"body rates at %.0f degrees must resolve to the turn rate" % degrees
		)

	# Steeper turns faster; faster flight turns slower at the same bank.
	if ASSIST.turn_rate(deg_to_rad(60.0), CRUISE) <= ASSIST.turn_rate(deg_to_rad(30.0), CRUISE):
		_fail("a steeper bank must turn faster")
	if ASSIST.turn_rate(deg_to_rad(45.0), 260.0) >= ASSIST.turn_rate(deg_to_rad(45.0), CRUISE):
		_fail("the same bank must turn more slowly at higher speed")

	# Standing still commands nothing, rather than dividing by zero.
	_assert_approx(ASSIST.level_turn_pitch_rate(deg_to_rad(45.0), 0.0), 0.0, "no turn at a standstill")


func _alpha_limiter() -> void:
	var stall := deg_to_rad(AERO.STALL_ALPHA_DEGREES)

	# Well away from the stall the limiter is not in the loop at all.
	_assert_approx(
		ASSIST.alpha_limited_pitch_rate(1.0, 0.0),
		1.0,
		"the limiter leaves ordinary flying alone"
	)
	# At the stall it refuses outright.
	_assert_approx(
		ASSIST.alpha_limited_pitch_rate(1.0, stall),
		0.0,
		"the limiter refuses nose-up at the stall angle"
	)
	# And PAST the stall it actively pushes, whatever the stick is asking.
	# Refusing alone is not enough: angle of attack also grows when the flight
	# path falls away beneath a held nose, and no refusal reaches that. Without
	# this the aircraft departed to ninety degrees of alpha.
	var pushing: float = ASSIST.alpha_limited_pitch_rate(1.0, stall + deg_to_rad(4.0))
	if pushing >= 0.0:
		_fail("past the stall the assist must push the nose down, got %f" % pushing)
	if ASSIST.alpha_limited_pitch_rate(1.0, stall + deg_to_rad(8.0)) >= pushing:
		_fail("the further past the stall, the harder the assist must push")
	# And eases off progressively on the way there.
	var near: float = ASSIST.alpha_limited_pitch_rate(1.0, stall * 0.9)
	if not (near > 0.0 and near < 1.0):
		_fail("the limiter must ease off progressively, got %f" % near)

	# Pushing is never limited: unloading is always the way out.
	_assert_approx(
		ASSIST.alpha_limited_pitch_rate(-1.0, stall),
		-1.0,
		"nose-down is never refused, because it is the recovery"
	)

	# The commanded rate, whatever the stick asks, must never let alpha through
	# the stall. This is the promise that there is no departure.
	for stick in [0.5, 1.0, 2.0]:
		var at_stall: float = ASSIST.commanded_pitch_rate(stick, 0.95, CRUISE, 0.0, stall)
		if at_stall > 0.0001:
			_fail("full stick at the stall angle still commanded %f" % at_stall)


func _sideslip() -> void:
	# Sideslip is washed out, not left to the pilot: an uncoordinated jet at
	# these speeds reads as broken rather than as skilled flying.
	_assert_approx(ASSIST.sideslip_damping(0.0, 1.4), 0.0, "no correction when coordinated")
	# Positive beta means the velocity is to the aircraft's right, so the nose
	# must yaw right (positive) to meet it. The opposite sign increases the slip.
	if ASSIST.sideslip_damping(0.2, 1.4) <= 0.0:
		_fail("positive sideslip must yaw the nose right toward the velocity")
	_assert_approx(
		ASSIST.sideslip_damping(-0.2, 0.8),
		-ASSIST.sideslip_damping(0.2, 0.8),
		"sideslip damping is symmetric"
	)

	# It must stay a correction. Unclamped, a gain on an angle in radians
	# reaches 1.5 rad/s during a hard roll -- twenty times the coordination
	# term it is added to -- and swings the nose the wrong way. That single
	# missing clamp made a right bank turn the aircraft left.
	for slip in [0.5, 1.0, 1.5]:
		var correction: float = ASSIST.sideslip_damping(slip, 0.8)
		if absf(correction) > ASSIST.MAX_SIDESLIP_RATE + 0.0001:
			_fail("sideslip correction reached %f rad/s at %f rad of slip" % [correction, slip])
	# The clamp must actually bite well before the slip angles a hard roll
	# produces: unclamped, 1 radian of apparent slip commands 0.8 rad/s.
	var clamped: float = absf(ASSIST.sideslip_damping(1.0, 0.8))
	if not is_equal_approx(clamped, ASSIST.MAX_SIDESLIP_RATE):
		_fail("a large slip must clamp to the ceiling, got %f" % clamped)
	if ASSIST.MAX_SIDESLIP_RATE >= 0.5:
		_fail("a wash-out this strong is a control input, not a correction")


func _boundary() -> void:
	var half_extent := 18000.0
	var margin := 1200.0
	var safe := half_extent - margin

	# Nothing at all inside the margin. Ordinary flying must never feel a hand
	# on the stick, or the theatre feels smaller than it is.
	_assert_approx(
		ASSIST.boundary_urgency(Vector2.ZERO, half_extent, margin),
		0.0,
		"no turn-back at the centre of the theatre"
	)
	_assert_approx(
		ASSIST.boundary_urgency(Vector2(safe - 1.0, 0.0), half_extent, margin),
		0.0,
		"no turn-back just inside the margin"
	)
	_assert_approx(
		ASSIST.turn_back_bank(Vector2(safe - 1.0, 0.0), 0.0, half_extent, margin),
		0.0,
		"no bank commanded just inside the margin"
	)

	# Outside it, urgency rises and then saturates.
	var near_edge: float = ASSIST.boundary_urgency(Vector2(safe + 300.0, 0.0), half_extent, margin)
	var far_out: float = ASSIST.boundary_urgency(Vector2(safe + 3000.0, 0.0), half_extent, margin)
	if not (near_edge > 0.0 and near_edge < far_out):
		_fail("turn-back urgency must rise with distance past the margin")
	_assert_approx(far_out, 1.0, "urgency saturates rather than growing without bound")

	# It must corner on the largest axis, not the diagonal distance, or the
	# corners of a square theatre behave differently to its edges.
	_assert_approx(
		ASSIST.boundary_urgency(Vector2(0.0, safe + 300.0), half_extent, margin),
		near_edge,
		"the boundary behaves the same on every axis"
	)

	# Flying out over the eastern edge, the assist must roll toward home; flying
	# back in already, it must not fight the pilot.
	var outbound: float = ASSIST.turn_back_bank(
		Vector2(safe + 600.0, 0.0), deg_to_rad(90.0), half_extent, margin
	)
	if is_zero_approx(outbound):
		_fail("heading out of the theatre must command a turn back")
	var inbound: float = ASSIST.turn_back_bank(
		Vector2(safe + 600.0, 0.0), deg_to_rad(-90.0), half_extent, margin
	)
	if absf(inbound) >= absf(outbound):
		_fail("already heading home must command less than heading away")

	# And it must stay a nudge rather than becoming a wall.
	if absf(outbound) > deg_to_rad(ASSIST.MAX_TURN_BACK_BANK_DEGREES) + 0.0001:
		_fail("the turn-back must stay bounded, got %f degrees" % rad_to_deg(outbound))


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 0.001:
		_fail("%s: expected %f, got %f" % [label, expected, actual])


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
