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
##
## What the flight control system does NOT do is invent authority the aircraft
## has not got. Commanded rates are scaled by dynamic pressure, because a
## control surface is only worth the air going over it -- and that, not any
## limiter, is why a real aeroplane cannot pull a tidy loop once it has run out
## of speed. Pitch keeps a floor the other axes do not, because the nozzles
## vector on thrust rather than airspeed.

const AERO := preload("res://scripts/jet/aero_model.gd")

## The aircraft's aerodynamics. The owner replaces this when it knows which
## airframe it is; the Raptor is the default so nothing has to.
var aero = AERO.new()

const GRAVITY := 9.80665

## How close to the stall the limiter starts easing off nose-up commands, as a
## fraction of the stall angle.
const ALPHA_LIMIT_BAND := 0.65
## How hard the assist pushes once the stall angle is reached. Refusing nose-up
## is not enough on its own: angle of attack also grows when the flight path
## falls away beneath a held nose, and no refusal can reach that. Without an
## active push the aircraft reached 90 degrees of alpha and departed.
const ALPHA_RECOVERY_GAIN := 20.0

## Automatic turn coordination belongs to a settled bank, and what it must not
## fight is a roll in progress -- so it fades on ROLL RATE, not on bank angle.
##
## Fading on bank was measurably wrong: coordination was down to a quarter at 75
## degrees and gone at 80, which meant the hardest turns in the aircraft's range
## were the only uncoordinated ones. A held 85-degree bank is a turn and wants
## coordinating; an axial roll through the same angle does not, and only the
## roll rate tells the two apart.
const COORDINATION_FADE_START_RATE := 0.35   ## rad/s of roll where it starts easing off
const COORDINATION_OFF_RATE := 1.10          ## rad/s of roll where it is fully gone

## Sideslip correction is a wash-out, never a primary control. Unclamped, a gain
## on an angle in radians reaches 1.5 rad/s during a hard roll -- twenty times
## the coordination term it is added to -- which swings the nose the wrong way
## and departs the aircraft. This is the clamp that stops that.
const MAX_SIDESLIP_RATE := 0.12

## Dihedral effect: a slipping aircraft rolls away from the slip, because the
## into-wind wing meets the air at a higher angle and lifts. This is the real
## mechanism by which rudder rolls an aeroplane, and the model had none of it --
## rudder carried a flat 0.12 rad/s of roll, under a fifteenth of aileron
## authority and unconnected to the slip it was creating. Sign follows the slip:
## right rudder makes beta negative and this returns a right roll.
const DIHEDRAL_ROLL_GAIN := 0.35
## Rudder-driven roll is a secondary control and must never overrun the stick.
const MAX_DIHEDRAL_ROLL_RATE := 0.45

## What the nozzles are worth on the rate axes while L2 + R2 are held. Deliberately
## short of double: the point of vectoring is where the nose can be pointed,
## not how fast it snaps there.
const VECTORED_RATE_GAIN := 1.7

## The level-turn hold fades out as soon as the pilot makes a deliberate pitch
## command. It must never cancel a recovery input after an energy-bleeding turn.
const PITCH_HOLD_OVERRIDE_STICK := 0.35

## R3 recovery is a command, not a permanent self-levelling mode. It only has
## authority once the wing has enough dynamic pressure to sustain more than 1 G.
const WINGS_LEVEL_GAIN := 2.4

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
func sustainable_bank(speed_mps: float) -> float:
	var available: float = minf(aero.airframe.load_limit_g, aero.aerodynamic_load_limit(speed_mps))
	if available <= 1.05:
		return 0.0
	return acos(1.0 / available)


## Coordination is for a bank being held, not a bank being changed. Rolling
## fast means aerobatics, and the coordinator must keep its hands off those.
func coordination_weight(roll_rate: float) -> float:
	var span := maxf(COORDINATION_OFF_RATE - COORDINATION_FADE_START_RATE, 0.001)
	return 1.0 - clampf((absf(roll_rate) - COORDINATION_FADE_START_RATE) / span, 0.0, 1.0)


## Body pitch rate that holds a level turn at the current bank. Wings level it
## is zero, which is what makes "stick centred" mean "hold what you have"
## rather than "return to level".
##
## For a coordinated level turn the load factor is 1/cos(bank), and the body
## rates that sustain it are q = (g/v) * sin^2(bank)/cos(bank) about pitch and
## r = (g/v) * sin(bank) about yaw. Their resultant is the familiar
## g * tan(bank) / v turn rate.
func level_turn_pitch_rate(
	bank_radians: float,
	speed_mps: float,
	roll_rate := 0.0
) -> float:
	if speed_mps < 1.0:
		return 0.0
	var limit := sustainable_bank(speed_mps)
	var bank := clampf(bank_radians, -limit, limit)
	var cosine := maxf(cos(bank), 0.01)
	return (GRAVITY / speed_mps) * (sin(bank) * sin(bank)) / cosine \
		* coordination_weight(roll_rate)


## Body yaw rate that keeps the turn coordinated, so the aircraft turns with the
## nose on the flight path instead of skidding through it.
func level_turn_yaw_rate(
	bank_radians: float,
	speed_mps: float,
	roll_rate := 0.0
) -> float:
	if speed_mps < 1.0:
		return 0.0
	var limit := sustainable_bank(speed_mps)
	var bank := clampf(bank_radians, -limit, limit)
	return (GRAVITY / speed_mps) * sin(bank) * coordination_weight(roll_rate)


## Rate the aircraft's heading actually sweeps at a given bank.
func turn_rate(bank_radians: float, speed_mps: float) -> float:
	if speed_mps < 1.0:
		return 0.0
	var limit := sustainable_bank(speed_mps)
	var bank := clampf(bank_radians, -limit, limit)
	return GRAVITY * tan(bank) / speed_mps


## Nose-up commands are eased off as the angle of attack approaches the stall,
## refused at it, and past it the assist pushes regardless of the stick. Nose
## down is never limited: unloading is always the way out.
## The ceiling is a parameter rather than the stall angle itself, because
## holding both rudder triggers hands the nose to the nozzles in the post-stall
## range. Everything below is unchanged; only where the wall sits moves.
func alpha_limited_pitch_rate(
	commanded: float,
	alpha_radians: float,
	ceiling_radians := -1.0
) -> float:
	# Negative means "the wing's own stall angle", which is an instance value
	# and so cannot be written as a default argument.
	if ceiling_radians < 0.0:
		ceiling_radians = deg_to_rad(aero.airframe.stall_alpha_degrees)
	if alpha_radians >= ceiling_radians:
		return minf(commanded, -(alpha_radians - ceiling_radians) * ALPHA_RECOVERY_GAIN)
	if commanded <= 0.0:
		return commanded
	var band := ceiling_radians * ALPHA_LIMIT_BAND
	var margin := ceiling_radians - alpha_radians
	if margin >= band:
		return commanded
	return commanded * clampf(margin / band, 0.0, 1.0)


## Where the limiter holds the nose. Vectoring trades the wing's limit for the
## nozzles': the aircraft will point far off its flight path, and pay for it in
## separation drag rather than in a departure.
func alpha_ceiling(vectoring: bool) -> float:
	return deg_to_rad(
		aero.airframe.post_stall_alpha_degrees if vectoring else aero.airframe.stall_alpha_degrees
	)


## Sideslip is washed out rather than left to the pilot: an uncoordinated jet at
## these speeds simply reads as broken. Clamped, for the reason recorded on
## MAX_SIDESLIP_RATE.
func sideslip_damping(beta_radians: float, gain: float) -> float:
	return clampf(beta_radians * gain, -MAX_SIDESLIP_RATE, MAX_SIDESLIP_RATE)


## Rudder creates a yawing moment and therefore sideslip. Directional stability
## then opposes that slip, so held rudder settles at an offset instead of
## rotating the aircraft like a flat-steering vehicle.
## On release the bounded wash-out lets the path catch up to the nose instead
## of snapping the aircraft back toward its old track.
func rudder_yaw_rate(
	input: float,
	maximum_sideslip_radians: float,
	beta_radians: float,
	damping_gain: float,
	maximum_rate: float
) -> float:
	var shaped_input := rudder_input_response(input)
	if is_zero_approx(shaped_input):
		return sideslip_damping(beta_radians, damping_gain)
	var target_beta := -shaped_input * maximum_sideslip_radians
	return clampf(
		(beta_radians - target_beta) * damping_gain,
		-maximum_rate,
		maximum_rate
	)


## Dihedral effect. The aircraft rolls because it is slipping, not because the
## pedal is pressed -- so this reads the sideslip the rudder has actually
## produced, and the roll builds and decays with the slip instead of appearing
## and vanishing with the trigger.
##
## That indirection is the whole point: aileron sets the bank, rudder adds slip,
## and slip rolls the aircraft further into the bank. Combining the two is what
## gives a steeper bank than either alone.
func dihedral_roll_rate(beta_radians: float, gain := DIHEDRAL_ROLL_GAIN) -> float:
	return clampf(-beta_radians * gain, -MAX_DIHEDRAL_ROLL_RATE, MAX_DIHEDRAL_ROLL_RATE)


## Triggers have little physical travel compared with pedals, so the curve has
## to do the work a pedal's travel would. A 0.35 power made a five-percent press
## command ten degrees of sideslip, which is why the rudder felt like a switch;
## 0.7 keeps the trigger usable without giving the whole slip range away in the
## first millimetre.
func rudder_input_response(input: float) -> float:
	return signf(input) * pow(absf(clampf(input, -1.0, 1.0)), 0.7)


## Shortest body-axis roll back to a level horizon. Below flying speed the
## surfaces cannot honour the command, so the pilot must recover airspeed first.
func wings_level_roll_rate(
	bank_radians: float,
	maximum_rate: float,
	speed_mps: float
) -> float:
	if aero.aerodynamic_load_limit(speed_mps) <= 1.05:
		return 0.0
	var bank := wrapf(bank_radians, -PI, PI)
	return clampf(-bank * WINGS_LEVEL_GAIN, -maximum_rate, maximum_rate)


## How far outside the safe area the aircraft is, 0 inside and rising to 1 well
## beyond. The margin is where the warning starts, not where a wall is.
func boundary_urgency(
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
func turn_back_bank(
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


## Roll rate is the pilot's direct body-axis command. There is deliberately no
## bank-angle limiter: fighter roll control must remain available through
## knife-edge, inverted flight, and a complete 360-degree roll.
##
## What it is NOT available at is any airspeed. Ailerons are aerodynamic, and
## the Raptor's nozzles vector in pitch only, so roll is the axis that goes
## properly slack when the aircraft runs out of speed.
func commanded_roll_rate(
	stick: float,
	maximum_rate: float,
	speed_mps: float,
	_bank_radians: float,
	_roll_rate: float,
	vectoring := false
) -> float:
	var boost := VECTORED_RATE_GAIN if vectoring else 1.0
	return stick * maximum_rate * aero.control_authority(speed_mps) * boost


## Pitch rate the stick asks for, put through every limit in turn. The automatic
## level-turn hold exists only near stick centre and fades completely before a
## deliberate pilot command, so it can never cancel an unload or recovery.
##
## The pilot's term is scaled by pitch authority, so a slow aircraft has a slack
## stick rather than a full-rate one. The hold is not scaled: it is a trim term
## the aircraft owes its own bank, and it is already small at low speed.
func commanded_pitch_rate(
	stick: float,
	maximum_rate: float,
	speed_mps: float,
	bank_radians: float,
	alpha_radians: float,
	roll_rate := 0.0,
	thrust_fraction := 1.0,
	vectoring := false
) -> float:
	var hold := level_turn_pitch_rate(bank_radians, speed_mps, roll_rate)
	var boost := VECTORED_RATE_GAIN if vectoring else 1.0
	var pilot := stick * maximum_rate \
		* aero.pitch_authority(speed_mps, thrust_fraction) * boost
	var hold_weight := 1.0 - clampf(absf(stick) / PITCH_HOLD_OVERRIDE_STICK, 0.0, 1.0)
	var limited := alpha_limited_pitch_rate(
		hold * hold_weight + pilot, alpha_radians, alpha_ceiling(vectoring)
	)
	return aero.load_limited_pitch_rate(speed_mps, limited)
