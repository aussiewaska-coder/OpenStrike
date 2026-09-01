extends RefCounted

## What the airframe does that the aerodynamics do not.
##
## None of this changes where the aircraft goes. It changes what the aircraft
## looks like it is doing on the way, which is most of the difference between a
## flight model that is correct and one that is convincing.
##
## Three sines at incommensurate rates, as in airframe_motion.gd, so nothing
## reads as a loop.

const AERO := preload("res://scripts/jet/aero_model.gd")

## Buffet is a real warning, not decoration: it is the disturbed air off a wing
## near its limit striking the tail, and a pilot feels it before the stall.
const BUFFET_FREQUENCY := 17.0
## The band below the stall angle where buffet has begun.
const BUFFET_BAND := 0.30

## Airframe vibration follows dynamic pressure, so it is a high-speed thing.
const VIBRATION_FREQUENCY := 31.0
const VIBRATION_ONSET_MPS := 170.0

## How fast the wallow after a hard manoeuvre dies away.
const OSCILLATION_FREQUENCY := 1.35
const OSCILLATION_DECAY := 1.9


static func phases(time: float, frequency: float) -> Vector3:
	return Vector3(
		sin(time * TAU * frequency),
		sin(time * TAU * frequency * 0.61 + 1.1),
		sin(time * TAU * frequency * 0.37 + 2.3)
	)


## Buffet, 0 to 1. It comes from two places that feel the same from the cockpit:
## approaching the stall angle, and running out of speed.
static func buffet(alpha_radians: float, speed_mps: float) -> float:
	var stall := deg_to_rad(AERO.STALL_ALPHA_DEGREES)
	var band := stall * BUFFET_BAND
	var from_alpha := clampf((absf(alpha_radians) - (stall - band)) / band, 0.0, 1.0)
	var from_speed := AERO.mush_fraction(speed_mps)
	return clampf(maxf(from_alpha, from_speed), 0.0, 1.0)


## Airframe vibration, 0 to 1, growing with dynamic pressure once the aircraft
## is genuinely moving.
static func vibration(speed_mps: float, top_speed_mps: float) -> float:
	if speed_mps <= VIBRATION_ONSET_MPS or top_speed_mps <= VIBRATION_ONSET_MPS:
		return 0.0
	var span := top_speed_mps - VIBRATION_ONSET_MPS
	var over := (speed_mps - VIBRATION_ONSET_MPS) / span
	return clampf(over * over, 0.0, 1.0)


## The wallow left behind by a hard manoeuvre: a decaying oscillation whose
## amplitude is set by how much load the aircraft just pulled.
static func oscillation(time_since: float, amplitude: float) -> float:
	if amplitude <= 0.0:
		return 0.0
	return sin(time_since * TAU * OSCILLATION_FREQUENCY) * amplitude * exp(-OSCILLATION_DECAY * time_since)


## How much wallow a manoeuvre earns, from the load factor it pulled. Gentle
## flying earns none at all, which is what keeps the effect meaningful.
static func oscillation_amplitude(load_factor: float, degrees_at_limit: float) -> float:
	var over := clampf((absf(load_factor) - 3.0) / (AERO.LOAD_LIMIT_G - 3.0), 0.0, 1.0)
	return over * degrees_at_limit


## Buffet shake and high-speed vibration, combined into pitch, bank and yaw
## degrees. Buffet is slow and mostly in pitch; vibration is fast and small.
static func shake_degrees(
	time: float,
	buffet_amount: float,
	buffet_degrees: float,
	vibration_amount: float,
	vibration_degrees: float
) -> Vector3:
	var slow := phases(time, BUFFET_FREQUENCY) * buffet_amount * buffet_degrees
	var fast := phases(time, VIBRATION_FREQUENCY) * vibration_amount * vibration_degrees
	var total := slow + fast
	return Vector3(total.x, total.y * 0.5, total.z * 0.35)
