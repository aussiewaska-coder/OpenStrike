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
	_coordination_envelope()
	_turn_geometry()
	_alpha_limiter()
	_sideslip()
	_thrust_vectoring()
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
	# Roll authority falls with dynamic pressure, because ailerons are
	# aerodynamic and the Raptor's nozzles vector in pitch only. Full stick at
	# 70 m/s must still roll -- the pilot is never locked out -- but it cannot
	# roll at the cruise rate, which is what let the aircraft pinwheel through
	# the vertical at speeds where a real one would have gone slack.
	var slow_roll: float = ASSIST.commanded_roll_rate(1.0, 1.8, 70.0, 0.0, 0.0)
	if slow_roll <= 0.0:
		_fail("the pilot must keep a roll command at low speed, got %f" % slow_roll)
	if slow_roll >= 1.8 * 0.5:
		_fail("roll authority must fall away with dynamic pressure, got %f of 1.8" % slow_roll)
	_assert_approx(
		ASSIST.commanded_roll_rate(1.0, 1.8, AERO.CORNER_SPEED_MPS, 0.0, 0.0),
		1.8,
		"full roll authority is available from corner speed upward"
	)

	# Nose-down recovery is never cancelled by the hold, and thrust vectoring
	# keeps more of it than the wing alone would have.
	var recovery: float = ASSIST.commanded_pitch_rate(
		-1.0, 0.95, 79.0, deg_to_rad(66.0), deg_to_rad(18.0), 0.0, 1.0
	)
	if recovery >= -0.3:
		_fail("a hard-turn hold must not cancel the pilot's nose-down recovery, got %f" % recovery)
	var unvectored: float = ASSIST.commanded_pitch_rate(
		-1.0, 0.95, 79.0, deg_to_rad(66.0), deg_to_rad(18.0), 0.0, 0.0
	)
	if recovery >= unvectored:
		_fail("thrust vectoring must add pitch authority the wing has lost")


## Ordinary banked turns receive pitch/yaw coordination. That assist must fade
## away before knife-edge while direct roll authority remains untouched.
func _coordination_envelope() -> void:
	# The envelope is now bounded by the airframe's own load limit rather than
	# by an arbitrary bank ceiling: at and above corner speed the 9 G limiter is
	# what binds, so the steepest coordinated bank is acos(1/9).
	var ceiling := acos(1.0 / AERO.LOAD_LIMIT_G)
	_assert_approx(ASSIST.sustainable_bank(CRUISE), ceiling, "corner speed reaches the load limit")
	_assert_approx(ASSIST.sustainable_bank(260.0), ceiling, "high speed reaches the load limit")
	var slow: float = ASSIST.sustainable_bank(90.0)
	if slow >= ceiling:
		_fail("the coordinated-turn envelope must tighten at low speed, got %.1f degrees" % rad_to_deg(slow))
	if ASSIST.sustainable_bank(70.0) >= slow:
		_fail("the coordination envelope must keep tightening as the aircraft slows further")

	# Inside the envelope, the level-turn assist must ask for a load the wing can fly.
	for speed in [90.0, 110.0, 155.0, 260.0]:
		var bank: float = minf(ASSIST.sustainable_bank(speed), deg_to_rad(55.0))
		var rate: float = ASSIST.level_turn_pitch_rate(bank, speed)
		var load: float = AERO.load_factor(speed, rate)
		var available: float = minf(AERO.LOAD_LIMIT_G, AERO.aerodynamic_load_limit(speed))
		if load > available + 0.1:
			_fail("coordinated bank at %.0f m/s needs %.1f G but only %.1f is available" % [
				speed, load, available
			])

	# Coordination now keys on roll rate, not bank angle. A settled bank is a
	# turn and gets coordinated however steep it is; a roll in progress does
	# not, so the coordinator cannot fight an aileron roll. Keying on bank made
	# the hardest turns the only uncoordinated ones.
	_assert_approx(
		ASSIST.coordination_weight(0.0),
		1.0,
		"a settled bank gets full turn coordination"
	)
	_assert_approx(
		ASSIST.coordination_weight(1.8),
		0.0,
		"a full-stick roll gets no level-turn assist"
	)
	_assert_approx(
		ASSIST.coordination_weight(-1.8),
		0.0,
		"the fade does not care which way the roll goes"
	)
	if ASSIST.level_turn_yaw_rate(deg_to_rad(80.0), CRUISE) <= 0.0:
		_fail("a held 80-degree bank is a turn and must still be coordinated")
	_assert_approx(
		ASSIST.commanded_roll_rate(1.0, 1.8, CRUISE, deg_to_rad(135.0), 1.8),
		1.8,
		"inverted flight must retain full roll authority"
	)


func _turn_geometry() -> void:
	# The body rates that sustain a level turn must resolve to the familiar
	# g * tan(bank) / v heading rate. If they do not, the aircraft either climbs
	# or descends through every turn it flies.
	for degrees in [20.0, 45.0, 60.0]:
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

	_assert_approx(
		ASSIST.rudder_yaw_rate(1.0, deg_to_rad(14.0), 0.0, 1.4, 0.28),
		0.28,
		"rudder creates a yawing moment in still air"
	)
	if ASSIST.rudder_yaw_rate(1.0, deg_to_rad(14.0), -0.2, 1.4, 0.28) >= 0.1:
		_fail("directional stability must oppose rudder-created sideslip")
	# The trigger curve must still reach useful authority early, but not so
	# early that a five-percent press is worth ten degrees of sideslip. At the
	# old 0.35 power it was, and that is what made the rudder read as a switch.
	if ASSIST.rudder_input_response(0.25) < 0.3:
		_fail("quarter trigger must reach useful rudder authority")
	if ASSIST.rudder_input_response(0.05) > 0.25:
		_fail("a five-percent press must not command a quarter of full rudder, got %f"
			% ASSIST.rudder_input_response(0.05))

	# Dihedral effect: the aircraft rolls because it is slipping. Right rudder
	# drives beta negative, and that must produce a right (positive) roll, so
	# stick and rudder reinforce instead of fighting.
	if ASSIST.dihedral_roll_rate(-0.3) <= 0.0:
		_fail("a left slip must roll the aircraft right")
	_assert_approx(
		ASSIST.dihedral_roll_rate(0.3),
		-ASSIST.dihedral_roll_rate(-0.3),
		"dihedral roll reverses with the slip"
	)
	_assert_approx(ASSIST.dihedral_roll_rate(0.0), 0.0, "no slip, no dihedral roll")
	# Secondary control: it must never overrun the stick.
	for slip in [0.5, 1.0, 1.5]:
		if absf(ASSIST.dihedral_roll_rate(slip)) > ASSIST.MAX_DIHEDRAL_ROLL_RATE + 0.0001:
			_fail("dihedral roll reached %f rad/s at %f rad of slip"
				% [ASSIST.dihedral_roll_rate(slip), slip])
	if ASSIST.MAX_DIHEDRAL_ROLL_RATE >= 1.8 * 0.5:
		_fail("rudder-driven roll this strong is a primary control, not a coupling")
	if ASSIST.wings_level_roll_rate(deg_to_rad(45.0), 1.8, CRUISE) >= 0.0:
		_fail("R3 recovery must roll a right bank back toward the horizon")
	if ASSIST.wings_level_roll_rate(deg_to_rad(-45.0), 1.8, CRUISE) <= 0.0:
		_fail("R3 recovery must roll a left bank back toward the horizon")
	_assert_approx(
		ASSIST.wings_level_roll_rate(deg_to_rad(45.0), 1.8, 20.0),
		0.0,
		"R3 cannot create aerodynamic roll authority below flying speed"
	)


## R1 hands the nose to the nozzles. The limiter does not go away -- it moves --
## so the aircraft points far off its flight path and pays in drag, never in a
## departure.
func _thrust_vectoring() -> void:
	var stall := deg_to_rad(AERO.STALL_ALPHA_DEGREES)
	var post := deg_to_rad(AERO.POST_STALL_ALPHA_DEGREES)
	_assert_approx(ASSIST.alpha_ceiling(false), stall, "the wing's limit applies by default")
	_assert_approx(ASSIST.alpha_ceiling(true), post, "R1 raises the limit to the nozzles'")
	if post <= stall:
		_fail("the post-stall ceiling must sit above the wing's stall")

	# Past the wing's stall the limiter must still refuse more nose-up, or the
	# aircraft would simply tumble instead of holding an angle.
	var beyond: float = ASSIST.alpha_limited_pitch_rate(1.0, post + 0.05, post)
	if beyond > 0.0:
		_fail("the post-stall limiter must still push the nose back down, got %f" % beyond)

	# Ordinary flight is untouched: 40 degrees is refused without R1 and
	# available with it.
	var refused: float = ASSIST.alpha_limited_pitch_rate(1.0, deg_to_rad(40.0), stall)
	if refused > 0.0:
		_fail("40 degrees of alpha must be refused without vectoring, got %f" % refused)
	var allowed: float = ASSIST.alpha_limited_pitch_rate(1.0, deg_to_rad(40.0), post)
	if allowed <= 0.0:
		_fail("40 degrees of alpha must be reachable with vectoring, got %f" % allowed)

	# The rate boost is real but short of doubling: vectoring is about where the
	# nose can be put, not how fast it snaps there.
	var normal: float = ASSIST.commanded_roll_rate(1.0, 1.8, CRUISE, 0.0, 0.0, false)
	var boosted: float = ASSIST.commanded_roll_rate(1.0, 1.8, CRUISE, 0.0, 0.0, true)
	if boosted <= normal:
		_fail("R1 must add roll rate")
	if boosted > normal * 2.0:
		_fail("vectoring must not double the roll rate, got %f against %f" % [boosted, normal])

	# There must still be lift to turn with out there, or the post-stall
	# envelope is a ballistic arc rather than a manoeuvre.
	var post_stall_lift: float = AERO.lift_coefficient(post)
	if post_stall_lift < 0.8:
		_fail("a vectored aircraft needs residual vortex lift, got Cl %f" % post_stall_lift)
	if post_stall_lift >= AERO.CL_MAX:
		_fail("post-stall lift must still be below the peak")

	# And it must be expensive. Separated drag is what stops R1 being free.
	var clean: float = AERO.drag_acceleration(CRUISE, deg_to_rad(8.0))
	var vectored: float = AERO.drag_acceleration(CRUISE, post)
	if vectored < clean * 3.0:
		_fail("post-stall drag must dominate, got %f against %f" % [vectored, clean])


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
