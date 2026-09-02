extends RefCounted

## The fly-by-wire layer between the stick and the aerodynamics.
##
## A real Raptor's pilot never commands a control surface; they command a load
## factor and a roll rate, and the flight control system works out what the
## surfaces must do and refuses anything that would depart the aircraft. That is
## exactly the relationship this file models, and it is what makes the aircraft
## flyable on a thumbstick.
##
## The single most important behaviour here: with the stick centred the
## aircraft HOLDS ITS BANK and flies a level turn. It does not roll upright.
## Rolling upright on release is what makes a flight model feel like a
## spaceship, because it removes the pilot's job of setting a bank and then
## easing off.
##
## Three of the limits below exist because the model departed without them, and
## each failure is recorded where the limit is defined. They are not defensive
## padding; they are the flight control system.

const AERO := preload("res://scripts/jet/aero_model.gd")

const GRAVITY := 9.80665

## How close to the stall the limiter starts easing off nose-up commands, as a
## fraction of the stall angle.
const ALPHA_LIMIT_BAND := 0.65
## How hard the assist pushes once the stall angle is reached. Refusing nose-up
## is not enough on its own: angle of attack also grows when the flight path
## falls away beneath a held nose, and no refusal can reach that. Without an
## active push the aircraft reached 90 degrees of alpha and departed.
const ALPHA_RECOVERY_GAIN := 20.0

## The steepest bank the assist will command. Rolling is rate commanded, so
## without a ceiling a full stick rolls straight past inverted in well under a
## second and the level-turn hold then loops the aircraft over the top.
const MAX_COMMAND_BANK_DEGREES := 80.0
const BANK_LIMIT_BAND_DEGREES := 18.0
const BANK_RECOVERY_GAIN := 4.0
## Roll rate is high enough that a limiter reacting to present bank alone always
## overshoots. Easing on where the bank will shortly be fixes that.
const BANK_LEAD_S := 0.2

## Sideslip correction is a wash-out, never a primary control. Unclamped, a gain
## on an angle in radians reaches 1.5 rad/s during a hard roll -- twenty times
## the coordination term it is added to -- which swings the nose the wrong way
## and departs the aircraft. This is the clamp that stops that.
const MAX_SIDESLIP_RATE := 0.20

## The turn-back only exists to stop the player leaving the theatre. It is not a
## wall: a hard clamp at 260 m/s stops the aircraft dead and reads as a bug.
const TURN_BACK_RAMP_M := 900.0
const MAX_TURN_BACK_BANK_DEGREES := 55.0


## The steepest bank whose level turn the wing can actually hold at this speed.
##
## A level turn at bank b needs a load factor of 1/cos(b), so the ceiling is
## acos(1/n) for whichever limit binds -- the wing's below corner speed, the
## airframe's above it. Clamping the hold to this is what stops the assist
## commanding a pitch rate the aircraft cannot fly: at a fixed 82 degrees the
## hold demanded over 7 G, the wing could not deliver it, and the aircraft
## looped instead of turning.
static func sustainable_bank(speed_mps: float) -> float:
	var ceiling := deg_to_rad(MAX_COMMAND_BANK_DEGREES)
	var available: float = minf(AERO.LOAD_LIMIT_G, AERO.aerodynamic_load_limit(speed_mps))
	if available <= 1.05:
		return 0.0
	return minf(acos(1.0 / available), ceiling)


## Body pitch rate that holds a level turn at the current bank. Wings level it
## is zero, which is what makes "stick centred" mean "hold what you have"
## rather than "return to level".
##
## For a coordinated level turn the load factor is 1/cos(bank), and the body
## rates that sustain it are q = (g/v) * sin^2(bank)/cos(bank) about pitch and
## r = (g/v) * sin(bank) about yaw. Their resultant is the familiar
## g * tan(bank) / v turn rate.
static func level_turn_pitch_rate(bank_radians: float, speed_mps: float) -> float:
	if speed_mps < 1.0:
		return 0.0
	var limit := sustainable_bank(speed_mps)
	var bank := clampf(bank_radians, -limit, limit)
	var cosine := maxf(cos(bank), 0.01)
	return (GRAVITY / speed_mps) * (sin(bank) * sin(bank)) / cosine


## Body yaw rate that keeps the turn coordinated, so the aircraft turns with the
## nose on the flight path instead of skidding through it.
static func level_turn_yaw_rate(bank_radians: float, speed_mps: float) -> float:
	if speed_mps < 1.0:
		return 0.0
	var limit := sustainable_bank(speed_mps)
	var bank := clampf(bank_radians, -limit, limit)
	return (GRAVITY / speed_mps) * sin(bank)


## Rate the aircraft's heading actually sweeps at a given bank.
static func turn_rate(bank_radians: float, speed_mps: float) -> float:
	if speed_mps < 1.0:
		return 0.0
	var limit := sustainable_bank(speed_mps)
	var bank := clampf(bank_radians, -limit, limit)
	return GRAVITY * tan(bank) / speed_mps


## Nose-up commands are eased off as the angle of attack approaches the stall,
## refused at it, and past it the assist pushes regardless of the stick. Nose
## down is never limited: unloading is always the way out.
static func alpha_limited_pitch_rate(commanded: float, alpha_radians: float) -> float:
	var stall := deg_to_rad(AERO.STALL_ALPHA_DEGREES)
	if alpha_radians >= stall:
		return minf(commanded, -(alpha_radians - stall) * ALPHA_RECOVERY_GAIN)
	if commanded <= 0.0:
		return commanded
	var band := stall * ALPHA_LIMIT_BAND
	var margin := stall - alpha_radians
	if margin >= band:
		return commanded
	return commanded * clampf(margin / band, 0.0, 1.0)


## Roll into the bank ceiling is eased off and then reversed; rolling away from
## it is never restricted, because that is the recovery. The ceiling tightens as
## the aircraft slows, so running out of speed quietly takes the steepest turns
## away rather than letting the pilot fly into a departure.
static func bank_limited_roll_rate(
	commanded: float,
	bank_radians: float,
	roll_rate: float,
	speed_mps: float
) -> float:
	var ceiling := sustainable_bank(speed_mps)
	var projected := bank_radians + roll_rate * BANK_LEAD_S
	var side := signf(projected)
	if side == 0.0 or signf(commanded) != side:
		return commanded
	var band: float = minf(deg_to_rad(BANK_LIMIT_BAND_DEGREES), maxf(ceiling * 0.4, 0.0001))
	var margin := ceiling - absf(projected)
	if margin >= band:
		return commanded
	if margin <= 0.0:
		return -side * minf(-margin, band) * BANK_RECOVERY_GAIN
	return commanded * (margin / band)


## Sideslip is washed out rather than left to the pilot: an uncoordinated jet at
## these speeds simply reads as broken. Clamped, for the reason recorded on
## MAX_SIDESLIP_RATE.
static func sideslip_damping(beta_radians: float, gain: float) -> float:
	return clampf(beta_radians * gain, -MAX_SIDESLIP_RATE, MAX_SIDESLIP_RATE)


## How far outside the safe area the aircraft is, 0 inside and rising to 1 well
## beyond. The margin is where the warning starts, not where a wall is.
static func boundary_urgency(
	horizontal_position: Vector2,
	half_extent: float,
	margin: float
) -> float:
	var safe := maxf(half_extent - margin, 1.0)
	var distance := maxf(absf(horizontal_position.x), absf(horizontal_position.y))
	if distance <= safe:
		return 0.0
	return clampf((distance - safe) / TURN_BACK_RAMP_M, 0.0, 1.0)


## Bank the assist adds to bring the aircraft home, in radians. Zero inside the
## margin, so ordinary flying never feels a hand on the stick.
static func turn_back_bank(
	horizontal_position: Vector2,
	heading_radians: float,
	half_extent: float,
	margin: float
) -> float:
	var urgency := boundary_urgency(horizontal_position, half_extent, margin)
	if urgency <= 0.0:
		return 0.0
	# The way home is straight at the theatre's centre.
	var home := -horizontal_position
	if home.is_zero_approx():
		return 0.0
	var wanted := atan2(home.x, -home.y)
	var error := wrapf(wanted - heading_radians, -PI, PI)
	var direction := signf(error) if not is_zero_approx(error) else 0.0
	var strength := clampf(absf(error) / (PI * 0.5), 0.0, 1.0)
	return direction * strength * urgency * deg_to_rad(MAX_TURN_BACK_BANK_DEGREES)


## Roll rate the pilot's stick asks for, after the aircraft's own bank ceiling.
static func commanded_roll_rate(
	stick: float,
	maximum_rate: float,
	speed_mps: float,
	bank_radians: float,
	roll_rate: float
) -> float:
	var pilot := stick * maximum_rate * AERO.roll_authority(speed_mps)
	return bank_limited_roll_rate(pilot, bank_radians, roll_rate, speed_mps)


## Pitch rate the stick asks for, put through every limit in turn: the pilot's
## command on top of the bank hold, then the wing's angle-of-attack ceiling,
## then the airframe's load ceiling. With the stick centred what survives is the
## level-turn hold.
static func commanded_pitch_rate(
	stick: float,
	maximum_rate: float,
	speed_mps: float,
	bank_radians: float,
	alpha_radians: float
) -> float:
	var hold := level_turn_pitch_rate(bank_radians, speed_mps)
	var pilot := stick * maximum_rate * AERO.pitch_authority(speed_mps)
	var limited := alpha_limited_pitch_rate(hold + pilot, alpha_radians)
	return AERO.load_limited_pitch_rate(speed_mps, limited)
