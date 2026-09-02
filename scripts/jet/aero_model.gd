extends RefCounted

## Fixed-wing aerodynamics, as accelerations rather than forces.
##
## The model is a lift curve and a drag polar, not a panel method: each frame
## the wing produces one lift acceleration perpendicular to airflow toward the
## body's upper side and one drag acceleration back along the velocity, and
## gravity and thrust do the rest.
##
## The consequence, and the point of the whole thing: the aircraft has no way to
## turn except by banking, because the horizontal component of the lift vector
## is the only sideways force there is. Heading is a result of attitude, never
## a commanded value.
##
## Everything here divides through by mass, so 0.5 * air density * wing area /
## mass folds into the single AERO_AUTHORITY below. That leaves one number to
## tune per axis instead of four, and it is why these return m/s^2 directly.
##
## The speed envelope is deliberately compressed -- roughly 90 to 260 m/s
## against the real aircraft's 600 -- because at true speed the 36 km theatre is
## a sixty-second dash and the terrain cannot stream ahead of the aircraft. The
## drag constants are compressed to match, so they are game-feel numbers rather
## than F-22 numbers. What is preserved is the shape: which limit binds where,
## and what each manoeuvre costs in energy.

const GRAVITY := 9.80665

## Lift curve. The slope is per radian, and the stall angle is where the
## limiter holds the aircraft: real Raptors reach far higher angles on thrust
## vectoring, which this model does not have.
const CL_SLOPE := 4.6
const STALL_ALPHA_DEGREES := 24.0
const CL_MAX := CL_SLOPE * 0.41887902  ## CL_SLOPE * deg_to_rad(24)
## How far past the stall the lift has fallen away to nothing.
const CL_DECAY_DEGREES := 20.0

## Drag polar. CD0 is parasite drag, K is the induced-drag factor, and CD_WAVE
## is the compressibility rise that actually sets a real aircraft's top speed --
## reproduced here at our compressed scale so the last of the speed is hard won.
const CD0 := 0.067962
const K_INDUCED := 0.055
const CD_WAVE := 0.076438
const DRAG_DIVERGENCE_MPS := 180.0

## 0.5 * air density * wing area / mass, folded. Derived, not chosen: it is the
## value that puts the crossing of the two turn limits exactly at corner speed.
const AERO_AUTHORITY := 0.00190657

## Thrust as a multiple of gravity. Close to the real aircraft's thrust to
## weight, which is the one place the compression was not needed.
const THRUST_MILITARY_G := 0.55
const THRUST_AFTERBURNER_G := 1.10
## Idle is not zero: a jet engine still pushes with the throttle closed.
const THRUST_IDLE_G := 0.05

const LOAD_LIMIT_G := 9.0

## Best turn rate, and the speed the whole model is pinned to. Below it the
## wing runs out of lift first; above it the load limiter binds first. That
## crossing is what corner speed means.
const CORNER_SPEED_MPS := 155.0


## Lift coefficient. Linear to the stall angle, then falling away -- the model
## can express a stall even though the limiter is what stops the aircraft
## reaching one.
static func lift_coefficient(alpha_radians: float) -> float:
	var stall := deg_to_rad(STALL_ALPHA_DEGREES)
	var magnitude := absf(alpha_radians)
	if magnitude <= stall:
		return CL_SLOPE * alpha_radians
	var over := magnitude - stall
	var decay := maxf(1.0 - over / deg_to_rad(CL_DECAY_DEGREES), 0.0)
	return signf(alpha_radians) * CL_MAX * decay


## Compressibility drag, zero until the divergence speed and quadratic after.
static func wave_drag(speed_mps: float) -> float:
	if speed_mps <= DRAG_DIVERGENCE_MPS:
		return 0.0
	var over := (speed_mps - DRAG_DIVERGENCE_MPS) / DRAG_DIVERGENCE_MPS
	return over * over


## Drag coefficient. The induced term is the important one: it goes as the
## square of the lift coefficient, which is why hard turns cost speed.
static func drag_coefficient(lift_c: float, speed_mps: float) -> float:
	return CD0 + K_INDUCED * lift_c * lift_c + CD_WAVE * wave_drag(speed_mps)


## Lift acceleration magnitude, in m/s^2.
static func lift_acceleration(speed_mps: float, alpha_radians: float) -> float:
	var lift_c := lift_coefficient(alpha_radians)
	return AERO_AUTHORITY * speed_mps * speed_mps * lift_c


## Small positive angle of attack needed to balance gravity in level flight.
## Launch uses this same equilibrium as the flight tests, so the live aircraft
## does not begin with zero lift while the tests begin already trimmed.
static func trim_alpha(speed_mps: float, falloff: float = 1.0) -> float:
	var lift_scale := AERO_AUTHORITY * speed_mps * speed_mps * CL_SLOPE * maxf(falloff, 0.001)
	return clampf(GRAVITY / maxf(lift_scale, 0.001), 0.0, deg_to_rad(STALL_ALPHA_DEGREES))


## Drag acceleration back along the velocity, in m/s^2.
static func drag_acceleration(speed_mps: float, alpha_radians: float) -> float:
	var lift_c := lift_coefficient(alpha_radians)
	var drag_c := drag_coefficient(lift_c, speed_mps)
	return AERO_AUTHORITY * speed_mps * speed_mps * drag_c


## Thrust acceleration in m/s^2. The throttle runs 0 to 1 for idle to military
## power, and past 1 into afterburner.
static func thrust_acceleration(throttle: float, afterburner: float) -> float:
	var dry := lerpf(THRUST_IDLE_G, THRUST_MILITARY_G, clampf(throttle, 0.0, 1.0))
	var wet := lerpf(dry, THRUST_AFTERBURNER_G, clampf(afterburner, 0.0, 1.0))
	return wet * GRAVITY


## Engines spool; they do not step. Returns the new thrust setting after delta.
## This is what makes the throttle command a target thrust rather than a speed.
static func spool(current: float, commanded: float, response: float, delta: float) -> float:
	return lerpf(current, commanded, 1.0 - exp(-response * delta))


## The most G the wing can generate at this speed, whatever the pilot asks for.
static func aerodynamic_load_limit(speed_mps: float) -> float:
	return AERO_AUTHORITY * speed_mps * speed_mps * CL_MAX / GRAVITY


## Pitch rate capped so the load factor stays inside the limit. Because
## n = v * omega / g, the same stick gives a lower rate the faster you go, which
## is why a fast turn is a wide one.
static func load_limited_pitch_rate(speed_mps: float, commanded: float) -> float:
	if speed_mps < 1.0:
		return commanded
	var cap := LOAD_LIMIT_G * GRAVITY / speed_mps
	return signf(commanded) * minf(absf(commanded), cap)


## The load factor a given pitch rate is actually pulling.
static func load_factor(speed_mps: float, pitch_rate: float) -> float:
	return absf(speed_mps * pitch_rate) / GRAVITY


## The slowest the aircraft can hold level flight: below this the wing cannot
## carry its own weight at any angle and the nose mushes. Derived from the lift
## curve rather than chosen, so retuning lift moves it automatically.
static func mush_speed() -> float:
	return sqrt(GRAVITY / (AERO_AUTHORITY * CL_MAX))


## Angle of attack and sideslip, from the velocity expressed in body axes.
## The airframe's nose is local +X, its up +Y and its right wing +Z.
static func alpha_beta(velocity_body: Vector3) -> Vector2:
	if absf(velocity_body.x) < 0.01 and velocity_body.length_squared() < 0.01:
		return Vector2.ZERO
	var alpha := atan2(-velocity_body.y, absf(velocity_body.x))
	var beta := atan2(velocity_body.z, absf(velocity_body.x))
	return Vector2(alpha, beta)


## Lift is normal to the airflow, toward the wing's upper side. Applying it
## directly along body-up gives it a rearward component at positive angle of
## attack, making lift itself destroy energy on top of induced drag.
static func lift_direction(body_up: Vector3, velocity: Vector3) -> Vector3:
	if velocity.length_squared() < 0.0001:
		return body_up.normalized()
	var airflow := velocity.normalized()
	var perpendicular := body_up - airflow * body_up.dot(airflow)
	if perpendicular.length_squared() < 0.0001:
		return body_up.normalized()
	return perpendicular.normalized()


## The whole force balance, as one acceleration in world space.
##
## This is the model: thrust along the nose, lift normal to airflow toward the
## body's upper side, drag back along the velocity, and gravity. Nothing here
## knows what a turn is. Turning happens because banking tilts the wing and with
## it the lift vector.
static func flight_acceleration(
	nose: Vector3,
	up: Vector3,
	velocity: Vector3,
	thrust: float,
	alpha_radians: float,
	falloff: float
) -> Vector3:
	var speed := velocity.length()
	var lift := lift_acceleration(speed, alpha_radians) * falloff
	var drag := drag_acceleration(speed, alpha_radians)
	var acceleration := (
		nose * (thrust * falloff)
		+ lift_direction(up, velocity) * lift
		+ Vector3.DOWN * GRAVITY
	)
	if speed > 0.01:
		acceleration -= velocity.normalized() * drag
	return acceleration


## Thrust and lift both fall away as the air thins. Soft, so the aircraft runs
## out of climb rather than striking a ceiling.
static func altitude_falloff(altitude_m: float, ceiling_m: float) -> float:
	if ceiling_m <= 0.0:
		return 1.0
	var ratio := clampf(altitude_m / ceiling_m, 0.0, 1.0)
	return 1.0 - ratio * ratio * 0.85
