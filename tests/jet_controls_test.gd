extends SceneTree

## Flies the aircraft, rather than checking its coefficients.
##
## Every step below goes through the same statics the controller uses --
## AERO.flight_acceleration for the forces and JET.rotate_body for the
## attitude -- so this is the real flight model, not a copy of it that can
## silently drift out of agreement.
##
## What it is really asserting is that nothing here contains a turn. The
## aircraft turns because banking tilts the lift vector, and if that chain ever
## breaks these fail even though every individual coefficient still passes.
##
## Every one of these caught a real departure while the model was being built,
## which is why they check emergent behaviour over seconds of flight rather
## than the value of any single function.

const AERO := preload("res://scripts/jet/aero_model.gd")
const ASSIST := preload("res://scripts/jet/flight_assist.gd")
const JET := preload("res://scripts/jet/jet_controller.gd")

const STEP := 1.0 / 60.0
const CRUISE := 175.0
const MAX_ROLL_RATE := 1.8
const MAX_PITCH_RATE := 0.95
const CONTROL_RESPONSE := 7.0
const SIDESLIP_GAIN := 1.4
const RUDDER_RATE := 0.28
const RUDDER_SIDESLIP := 14.0
const RUDDER_ROLL_RATE := 0.06
const ROLL_IN_SECONDS := 0.75


## The state of one aircraft, flown forward.
class Flight:
	var basis := Basis.IDENTITY
	var velocity := Vector3.ZERO
	var position := Vector3.ZERO
	var alpha := 0.0
	var beta := 0.0
	var roll_rate := 0.0
	var pitch_rate := 0.0
	var yaw_rate := 0.0
	## Heading accumulates unwrapped, because a hard turn passes 180 degrees
	## and a wrapped reading makes a right turn look like a left one.
	var turned := 0.0
	var previous_heading := 0.0
	var peak_load := 0.0
	var worst_alpha := 0.0
	var peak_bank := 0.0


func _init() -> void:
	assert(JET.pitch_input_from_stick(-1.0) < 0.0, "pushing the left stick up must lower the nose")
	assert(JET.pitch_input_from_stick(1.0) > 0.0, "pulling the left stick down must raise the nose")
	_pitch_responds()
	_level_flight_stays_level()
	_full_roll_is_available()
	_rudder_creates_a_recoverable_sideslip()
	_bank_produces_a_turn()
	_a_hard_turn_costs_speed()
	_controls_recover_after_a_hard_turn()
	_the_bank_is_held()
	_throttle_sets_speed_not_thrust()
	_it_cannot_be_departed()
	print("JET_CONTROLS_TEST_PASS")
	quit()


func _pitch_responds() -> void:
	var pull := _fly(1.0, 0.0, 1.0, 1.0)
	var push := _fly(1.0, 0.0, -1.0, 1.0)
	var pull_nose := rad_to_deg(asin(clampf(pull.basis.x.y, -1.0, 1.0)))
	var push_nose := rad_to_deg(asin(clampf(push.basis.x.y, -1.0, 1.0)))
	var pull_path := rad_to_deg(asin(clampf(pull.velocity.normalized().y, -1.0, 1.0)))
	var push_path := rad_to_deg(asin(clampf(push.velocity.normalized().y, -1.0, 1.0)))
	if pull_nose < 20.0 or pull_path < 8.0:
		_fail("a one-second pull must produce a clear climb, nose %.1f path %.1f" % [pull_nose, pull_path])
	if push_nose > -18.0 or push_path > -8.0:
		_fail("a one-second push must produce a clear descent, nose %.1f path %.1f" % [push_nose, push_path])


## The angle of attack that holds level flight at a given speed.
func _trim_alpha(speed: float) -> float:
	return AERO.trim_alpha(speed)


## Level, wings level, and trimmed. Starting with the velocity exactly along the
## nose would mean zero angle of attack and therefore zero lift, and the
## aircraft would drop out of the sky before any test had begun.
func _start(speed: float) -> Flight:
	var flight := Flight.new()
	var trim := _trim_alpha(speed)
	# Nose along -Z, wings level: the attitude launch() produces at zero heading.
	flight.basis = Basis(Vector3(0.0, 0.0, -1.0), Vector3.UP, Vector3.RIGHT)
	flight.basis = flight.basis.rotated(flight.basis.z, trim)
	flight.velocity = Vector3(0.0, 0.0, -speed)
	flight.alpha = trim
	flight.previous_heading = JET.heading_of(flight.basis)
	return flight


## One physics step, mirroring jet_controller._read_controls and ._integrate.
func _step(
	flight: Flight,
	roll_stick: float,
	pitch_stick: float,
	throttle: float,
	rudder_stick := 0.0
) -> void:
	var speed := flight.velocity.length()
	var bank: float = JET.bank_angle(flight.basis)

	var commanded_roll: float = ASSIST.commanded_roll_rate(
		roll_stick, MAX_ROLL_RATE, speed, bank, flight.roll_rate
	)
	commanded_roll += ASSIST.rudder_roll_rate(rudder_stick, RUDDER_ROLL_RATE)
	var commanded_pitch: float = ASSIST.commanded_pitch_rate(
		pitch_stick, MAX_PITCH_RATE, speed, bank, flight.alpha
	)
	var commanded_yaw: float = ASSIST.level_turn_yaw_rate(bank, speed)
	commanded_yaw += ASSIST.rudder_yaw_rate(
		rudder_stick,
		deg_to_rad(RUDDER_SIDESLIP),
		flight.beta,
		SIDESLIP_GAIN,
		RUDDER_RATE
	)

	var weight := 1.0 - exp(-CONTROL_RESPONSE * STEP)
	flight.roll_rate = lerpf(flight.roll_rate, commanded_roll, weight)
	flight.pitch_rate = lerpf(flight.pitch_rate, commanded_pitch, weight)
	flight.yaw_rate = lerpf(flight.yaw_rate, commanded_yaw, weight)
	flight.basis = JET.rotate_body(
		flight.basis, flight.roll_rate, flight.pitch_rate, flight.yaw_rate, STEP
	)

	var angles: Vector2 = AERO.alpha_beta(flight.basis.inverse() * flight.velocity)
	flight.alpha = angles.x
	flight.beta = angles.y

	var dry := clampf(throttle, 0.0, 1.0)
	var wet := clampf((throttle - 1.0) / 0.35, 0.0, 1.0)
	var thrust: float = AERO.thrust_acceleration(dry, wet)
	flight.velocity += AERO.flight_acceleration(
		flight.basis.x, flight.basis.y, flight.velocity, thrust, flight.alpha, 1.0
	) * STEP
	flight.position += flight.velocity * STEP

	var heading: float = JET.heading_of(flight.basis)
	flight.turned += wrapf(heading - flight.previous_heading, -PI, PI)
	flight.previous_heading = heading
	flight.peak_load = maxf(flight.peak_load, AERO.lift_acceleration(speed, flight.alpha) / AERO.GRAVITY)
	flight.worst_alpha = maxf(flight.worst_alpha, flight.alpha)
	flight.peak_bank = maxf(flight.peak_bank, absf(bank))


func _fly(seconds: float, roll_stick: float, pitch_stick: float, throttle: float, start_speed := CRUISE) -> Flight:
	var flight := _start(start_speed)
	for _step_index in range(int(seconds / STEP)):
		_step(flight, roll_stick, pitch_stick, throttle)
	return flight


func _fly_banked_turn(seconds: float, pitch_stick: float, throttle: float) -> Flight:
	var flight := _start(CRUISE)
	var roll_in_steps := int(ROLL_IN_SECONDS / STEP)
	for step_index in range(int(seconds / STEP)):
		_step(flight, 1.0 if step_index < roll_in_steps else 0.0, pitch_stick, throttle)
	return flight


## Trimmed and hands off, the aircraft must hold its height and its wings. If it
## does not, every other assertion here is measuring a falling aircraft.
func _level_flight_stays_level() -> void:
	var flight := _fly(12.0, 0.0, 0.0, 1.0)
	if absf(flight.position.y) > 60.0:
		_fail("hands off, the aircraft wandered %.1f m in height" % flight.position.y)
	if absf(JET.bank_angle(flight.basis)) > deg_to_rad(1.0):
		_fail("hands off, the aircraft rolled to %.2f degrees" % rad_to_deg(JET.bank_angle(flight.basis)))
	if absf(flight.turned) > deg_to_rad(2.0):
		_fail("hands off, the aircraft turned %.2f degrees" % rad_to_deg(flight.turned))


func _full_roll_is_available() -> void:
	var flight := _start(CRUISE)
	var reached_inverted := false
	var completed_roll := false
	for _step_index in range(int(5.0 / STEP)):
		_step(flight, 1.0, 0.0, 1.0)
		var up_dot := flight.basis.y.dot(Vector3.UP)
		if up_dot < -0.8:
			reached_inverted = true
		elif reached_inverted and up_dot > 0.8:
			completed_roll = true
			break
	if not reached_inverted:
		_fail("full lateral stick never rolled the aircraft inverted")
	if not completed_roll:
		_fail("full lateral stick could not complete a 360-degree roll")


func _rudder_creates_a_recoverable_sideslip() -> void:
	var flight := _start(CRUISE)
	var initial_nose := JET.heading_of(flight.basis)
	var initial_path := atan2(flight.velocity.x, -flight.velocity.z)
	for _step_index in range(int(1.5 / STEP)):
		_step(flight, 0.0, 0.0, 1.0, 1.0)

	var nose_change := absf(wrapf(JET.heading_of(flight.basis) - initial_nose, -PI, PI))
	var path_heading := atan2(flight.velocity.x, -flight.velocity.z)
	var path_change := absf(wrapf(path_heading - initial_path, -PI, PI))
	var slip_with_rudder := absf(flight.beta)
	var coupled_bank := absf(JET.bank_angle(flight.basis))
	if nose_change < deg_to_rad(5.0):
		_fail("full rudder barely yawed the nose, got %.1f degrees" % rad_to_deg(nose_change))
	if slip_with_rudder < deg_to_rad(5.0):
		_fail("rudder steered without producing realistic sideslip, beta %.1f" % rad_to_deg(slip_with_rudder))
	if path_change >= nose_change * 0.6:
		_fail("rudder flat-turned the flight path %.1f degrees for %.1f degrees of yaw" % [
			rad_to_deg(path_change), rad_to_deg(nose_change)
		])
	if coupled_bank < deg_to_rad(2.0):
		_fail("rudder produced no lateral roll coupling, bank %.1f" % rad_to_deg(coupled_bank))

	for _step_index in range(int(3.0 / STEP)):
		_step(flight, 0.0, 0.0, 1.0)
	if absf(flight.beta) >= slip_with_rudder * 0.4:
		_fail("released rudder did not let directional stability remove the sideslip")


## The heart of it. Roll the aircraft and pull, and the heading must come round
## -- with no code anywhere that turns the aircraft.
func _bank_produces_a_turn() -> void:
	var straight := _fly(6.0, 0.0, 0.0, 1.0)
	var turning := _fly_banked_turn(6.0, 0.6, 1.0)

	if absf(straight.turned) > deg_to_rad(2.0):
		_fail("flying straight turned %.1f degrees" % rad_to_deg(straight.turned))
	if absf(turning.turned) < deg_to_rad(45.0):
		_fail("banking and pulling only turned %.1f degrees" % rad_to_deg(turning.turned))

	# Right stick banks right, which must turn RIGHT. A sign error here still
	# produces a turn, and would still pass a test that only measured its size.
	# The model did exactly that until the sideslip term was clamped.
	if turning.turned <= 0.0:
		_fail("a right bank must turn right, got %.1f degrees" % rad_to_deg(turning.turned))
	if absf(turning.beta) > deg_to_rad(5.0):
		_fail("a coordinated turn must not fly sideways, got %.1f degrees sideslip" % rad_to_deg(turning.beta))

	var bank: float = JET.bank_angle(turning.basis)
	if bank <= deg_to_rad(45.0):
		_fail("a full right stick must establish a steep right bank, got %.1f" % rad_to_deg(bank))
## Induced drag is what makes energy a resource. A hard turn must cost speed
## even at full throttle, or there is nothing to manage.
func _a_hard_turn_costs_speed() -> void:
	var straight := _fly(8.0, 0.0, 0.0, 1.0)
	var turning := _fly_banked_turn(8.0, 1.0, 1.0)
	var straight_speed := straight.velocity.length()
	var turning_speed := turning.velocity.length()

	if turning_speed >= straight_speed:
		_fail("a hard turn must cost speed: %.1f turning against %.1f straight" % [turning_speed, straight_speed])
	if turning_speed >= CRUISE:
		_fail("a sustained hard turn must bleed below where it started, got %.1f" % turning_speed)
	if turning_speed < 125.0:
		_fail("an eight-second hard turn dumped out of the arcade envelope, got %.1f" % turning_speed)
	if turning.peak_load <= 3.0:
		_fail("a full pull must actually load the airframe, peaked at %.1f G" % turning.peak_load)
	if turning.peak_load > AERO.LOAD_LIMIT_G + 0.5:
		_fail("the load limiter let the airframe reach %.1f G" % turning.peak_load)


## A maximum turn must not leave the aircraft trapped behind its assists. Full
## opposite roll and nose-down stick are recovery commands and must remain
## immediately authoritative even after the manoeuvre has bled energy.
func _controls_recover_after_a_hard_turn() -> void:
	var flight := _fly_banked_turn(8.0, 1.0, 1.0)

	var speed_before := flight.velocity.length()
	var bank_before := JET.bank_angle(flight.basis)
	var path_before := asin(clampf(flight.velocity.normalized().y, -1.0, 1.0))
	for _step_index in range(int(1.0 / STEP)):
		_step(flight, -1.0, -1.0, 1.0)

	var bank_after := JET.bank_angle(flight.basis)
	var path_after := asin(clampf(flight.velocity.normalized().y, -1.0, 1.0))
	var bank_recovery := bank_before - bank_after
	var path_recovery := path_before - path_after
	if bank_recovery < deg_to_rad(70.0):
		_fail("opposite stick after a hard turn removed only %.1f degrees of bank at %.1f m/s" % [
			rad_to_deg(bank_recovery), speed_before
		])
	if path_recovery < deg_to_rad(3.5):
		_fail("nose-down stick after a hard turn changed the path only %.1f degrees at %.1f m/s" % [
			rad_to_deg(path_recovery), speed_before
		])
	if flight.pitch_rate > -0.5:
		_fail("nose-down recovery achieved only %.1f degrees/s of pitch rate" % rad_to_deg(flight.pitch_rate))


## Release the stick mid-turn and the aircraft must keep its bank and keep
## turning. Rolling upright here is what would make it a spaceship.
func _the_bank_is_held() -> void:
	var flight := _start(CRUISE)
	var roll_in := int(ROLL_IN_SECONDS / STEP)
	var established := 0.0
	for step_index in range(int(8.0 / STEP)):
		if step_index == roll_in:
			established = JET.bank_angle(flight.basis)
		# Roll into a bank, then release lateral stick and hold it.
		_step(flight, 1.0 if step_index < roll_in else 0.0, 0.0, 1.0)

	var final_bank: float = JET.bank_angle(flight.basis)
	if established <= deg_to_rad(30.0):
		_fail("roll-in should establish a bank, got %.1f" % rad_to_deg(established))
	if final_bank <= deg_to_rad(25.0):
		_fail("the aircraft rolled itself upright: %.1f degrees left of %.1f" % [
			rad_to_deg(final_bank), rad_to_deg(established)
		])
	# It must still be turning seven seconds after the stick was released.
	if absf(flight.turned) < deg_to_rad(15.0):
		_fail("a held bank must keep the aircraft turning, got %.1f" % rad_to_deg(flight.turned))
	if flight.turned <= 0.0:
		_fail("a held right bank must keep turning right")


## Throttle commands thrust, and speed is what thrust and drag settle on. So
## more throttle must mean more speed, but not instantly.
func _throttle_sets_speed_not_thrust() -> void:
	var idle := _fly(25.0, 0.0, 0.0, 0.0).velocity.length()
	var military := _fly(25.0, 0.0, 0.0, 1.0).velocity.length()
	var afterburner := _fly(25.0, 0.0, 0.0, 1.35).velocity.length()

	if not (idle < military and military < afterburner):
		_fail("speed must follow throttle: %.1f idle, %.1f military, %.1f afterburner" % [
			idle, military, afterburner
		])
	if idle >= CRUISE:
		_fail("closing the throttle must lose speed, got %.1f" % idle)
	if afterburner > AERO.CORNER_SPEED_MPS * 2.0:
		_fail("afterburner reached %.1f m/s, faster than the envelope allows" % afterburner)


## The promise that there is no departure: hold the stick fully back from a slow
## start for half a minute, and the aircraft must mush and sink without ever
## losing control. Before the limiter learned to push rather than merely refuse,
## this reached ninety degrees of angle of attack.
func _it_cannot_be_departed() -> void:
	var flight := _start(120.0)
	for _step_index in range(int(30.0 / STEP)):
		_step(flight, 0.0, 1.0, 1.0)

	var stall := deg_to_rad(AERO.STALL_ALPHA_DEGREES)
	# A small overshoot is the one-frame lag between measuring alpha and acting
	# on it. A large one means the limiter is not holding.
	if flight.worst_alpha > stall + deg_to_rad(2.0):
		_fail("full back stick reached %.1f degrees alpha against a %.1f degree stall" % [
			rad_to_deg(flight.worst_alpha), AERO.STALL_ALPHA_DEGREES
		])
	if flight.worst_alpha < deg_to_rad(4.0):
		_fail("full back stick barely moved the angle of attack, so nothing was tested")
	# It must end up genuinely degraded -- slow and sinking -- rather than
	# either departing or shrugging the manoeuvre off.
	var final_speed := flight.velocity.length()
	if final_speed > 110.0:
		_fail("a sustained maximum pull should bleed the aircraft right down, got %.1f" % final_speed)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
