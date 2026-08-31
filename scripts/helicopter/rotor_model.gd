extends RefCounted

## Rotor aerodynamics, as coefficients on rotor thrust.
##
## The model is balance-of-forces, not blade element: each frame the rotor
## produces one thrust vector along the disc normal, and gravity and drag do the
## rest. Blade element is what full simulators use and is far too expensive to
## run per frame in a game.
##
## The consequence, and the point of the whole thing: the aircraft has no way to
## move horizontally except by tilting the disc. Speed is a result of attitude,
## never a commanded value.
##
## Speeds below are in metres per second; the sources quote knots, converted at
## 0.5144 m/s per knot.

const KNOT_MPS := 0.5144

## Effective translational lift. The rotor stops recirculating its own downwash
## as it outruns it: gains start at the first knot, land hard between 16 and
## 20 kt where the aircraft noticeably climbs, and stop growing around 45 kt as
## induced drag cancels them.
const ETL_START_MPS := 8.23
const ETL_END_MPS := 10.29
const ETL_PLATEAU_MPS := 23.15

## Transverse flow effect: a lift imbalance across the disc, felt as a rotor
## shudder at 12-15 kt. It arrives just before effective translational lift, and
## is routinely mistaken for it.
const TRANSVERSE_START_MPS := 6.17
const TRANSVERSE_END_MPS := 7.72

## Vortex ring state: descending into your own downwash. It needs a vertical
## descent of about 300 ft/min and cannot happen above translational lift, which
## is why flying forward is the escape.
const VORTEX_ONSET_MPS := 1.5


## Multiplier on rotor thrust from translational lift.
static func translational_lift(speed_mps: float, gain: float) -> float:
	var early := clampf(speed_mps / ETL_START_MPS, 0.0, 1.0) * 0.35
	var effective := smoothstep(ETL_START_MPS, ETL_END_MPS, speed_mps) * 0.45
	var late := smoothstep(ETL_END_MPS, ETL_PLATEAU_MPS, speed_mps) * 0.20
	return 1.0 + gain * clampf(early + effective + late, 0.0, 1.0)


## Multiplier on rotor thrust from ground effect. The cushion is strongest on
## the surface and gone by roughly one rotor diameter up.
static func ground_effect(height_above_ground: float, rotor_diameter: float, gain: float) -> float:
	if rotor_diameter <= 0.0:
		return 1.0
	var ratio := clampf(height_above_ground / rotor_diameter, 0.0, 1.0)
	var falloff := 1.0 - ratio
	return 1.0 + gain * falloff * falloff


## Multiplier on rotor thrust from vortex ring state. Returns 1.0 whenever the
## aircraft is not descending hard, and always above translational lift.
static func vortex_ring(descent_rate_mps: float, horizontal_speed_mps: float, loss: float) -> float:
	if descent_rate_mps <= VORTEX_ONSET_MPS or horizontal_speed_mps >= ETL_END_MPS:
		return 1.0
	var descent_weight := clampf((descent_rate_mps - VORTEX_ONSET_MPS) / VORTEX_ONSET_MPS, 0.0, 1.0)
	var speed_weight := 1.0 - clampf(horizontal_speed_mps / ETL_END_MPS, 0.0, 1.0)
	return 1.0 - loss * descent_weight * speed_weight


## Rotor shudder, 0 to 1, across the transverse flow band only.
static func transverse_flow(speed_mps: float) -> float:
	if speed_mps <= TRANSVERSE_START_MPS or speed_mps >= TRANSVERSE_END_MPS:
		return 0.0
	var position := (speed_mps - TRANSVERSE_START_MPS) / (TRANSVERSE_END_MPS - TRANSVERSE_START_MPS)
	return sin(position * PI)


## Yaw the fuselage takes from main rotor torque, in degrees per second. Pulling
## collective yaws the nose; letting it down yaws it back. This is what forces
## the pedals to move whenever the collective does.
static func torque_yaw_degrees(collective: float, torque_degrees: float) -> float:
	return clampf(collective, 0.0, 1.0) * torque_degrees


## The disc normal, which thrust acts along. Tilting it is the only way the
## aircraft moves horizontally: a positive pitch tips the disc toward the nose
## and drives the aircraft forward, a positive roll tips it toward the right.
static func disc_normal(
	nose: Vector3,
	right: Vector3,
	pitch_degrees: float,
	roll_degrees: float
) -> Vector3:
	var forward_tilt := sin(deg_to_rad(pitch_degrees))
	var lateral_tilt := sin(deg_to_rad(roll_degrees))
	var vertical := sqrt(maxf(1.0 - forward_tilt * forward_tilt - lateral_tilt * lateral_tilt, 0.0))
	var normal := nose * forward_tilt + right * lateral_tilt + Vector3.UP * vertical
	return normal.normalized() if not normal.is_zero_approx() else Vector3.UP
