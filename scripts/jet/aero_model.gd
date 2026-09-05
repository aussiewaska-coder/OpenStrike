extends RefCounted

## Fixed-wing aerodynamics, as accelerations rather than forces.
##
## The model is a lift curve and a drag polar, not a panel method: each frame
## the wing produces one lift acceleration perpendicular to airflow toward the
## body's upper side and one drag acceleration back along the velocity, and
## gravity and thrust do the rest.
##
## The consequence, and the point of the whole thing: the aircraft has no way to
## make its main turns by banking: tilted lift bends the flight path. Side
## force resists sideslip, letting rudder change the track as well as the nose.
## Heading is a result of attitude and forces, never a commanded value.
##
## Everything here divides through by mass, so 0.5 * air density * wing area /
## mass folds into the single AERO_AUTHORITY below. That leaves one number to
## tune per axis instead of four, and it is why these return m/s^2 directly.
##
## The speed envelope is deliberately compressed -- roughly 90 to 260 m/s
## against the real aircraft's 600 -- because at true speed the 50 km theatre is
## a sixty-second dash and the terrain cannot stream ahead of the aircraft. The
## drag constants are compressed to match, so they are game-feel numbers rather
## than F-22 numbers. What is preserved is the shape: which limit binds where,
## and what each manoeuvre costs in energy.

const GRAVITY := 9.80665

## Which aircraft these aerodynamics are for. The coefficients that used to be
## constants here live on it now; the reasoning for each one stayed behind, in
## the comments below.
var airframe: Airframe


func _init(profile: Airframe = Airframe.raptor()) -> void:
	airframe = profile

## Lift curve. The slope is per radian, and the stall angle is where the
## limiter holds the aircraft. The Raptor reaches these angles because it has
## leading-edge vortex lift and pitch-vectoring nozzles to hold the nose there;
## THRUST_VECTOR_AUTHORITY below is the other half of the same aircraft.
## How far past the stall the lift has fallen away to nothing. Wide, because a
## slender delta with leading-edge vortices does not lose its lift at the stall
## the way a straight wing does -- it keeps well over half of it deep into the
## post-stall range, and that residue is the only thing a vectored aircraft has
## to turn with. At 20 degrees of decay the lift reached exactly zero at 52,
## which made the post-stall envelope below a ballistic arc rather than a
## manoeuvre.

## The angle the vectoring nozzles will hold the nose at while the pilot asks
## for it. Past the wing's own stall by a long way: this is the post-stall
## pointing envelope, not a flyable one, and separation drag makes it expensive.

## Drag polar. CD0 is parasite drag, K is the induced-drag factor, and CD_WAVE
## is the compressibility rise that actually sets a real aircraft's top speed --
## reproduced here at our compressed scale so the last of the speed is hard won.

## Separated flow past the stall. Without this the drag polar has a hole in it:
## once CL has decayed to nothing the induced term vanishes too, leaving a fully
## stalled wing CHEAPER than a flying one -- 0.068 against 0.272 at the stall.
## That hole is what let the aircraft fly serene 60-second loops at 63 m/s. A
## real separated wing is a flat plate and costs about this much.
## Where separation is complete and the flat-plate value is fully paid.

## 0.5 * air density * wing area / mass, folded. Derived, not chosen: it is the
## value that puts the crossing of the two turn limits exactly at corner speed.
## Side area resists cross-body airflow. This changes the flight path while
## the nose is yawed, so directional stability settles onto a new track after
## rudder release. A game-tuned coefficient, not measured F-22 derivatives.

## Thrust as a multiple of gravity. Close to the real aircraft's thrust to
## weight, which is the one place the compression was not needed.
## Idle is not zero: a jet engine still pushes with the throttle closed.


## Best turn rate, and the speed the whole model is pinned to. Below it the
## wing runs out of lift first; above it the load limiter binds first. That
## crossing is what corner speed means. Derived from AERO_AUTHORITY and CL_MAX
## rather than chosen: it is where aerodynamic_load_limit() reaches 9 G, so
## raising the stall angle moves it down here automatically.

## Control authority. Aerodynamic surfaces make moments proportional to dynamic
## pressure, so a slow aircraft has slack controls -- and that, not any limiter,
## is why a real aeroplane cannot pull a tidy loop once it has run out of speed.
## Holding these rates constant is what produced the backflip: at 63 m/s the
## aircraft still had 100% of its cruise pitch rate.
## The nozzles do not care how fast the aircraft is going, only how hard the
## engines are pushing, so pitch keeps authority the wing has already lost.
## The Raptor's nozzles are two-dimensional: they vector in pitch alone, which
## is why roll gets no such floor and goes slack with everything else.


## Lift coefficient. Linear to the stall angle, then falling away -- the model
## can express a stall even though the limiter is what stops the aircraft
## reaching one.
func lift_coefficient(alpha_radians: float) -> float:
	var stall := deg_to_rad(airframe.stall_alpha_degrees)
	var magnitude := absf(alpha_radians)
	if magnitude <= stall:
		return airframe.cl_slope * alpha_radians
	var over := magnitude - stall
	var decay := maxf(1.0 - over / deg_to_rad(airframe.cl_decay_degrees), 0.0)
	return signf(alpha_radians) * airframe.cl_max() * decay


## Compressibility drag, zero until the divergence speed and quadratic after.
func wave_drag(speed_mps: float) -> float:
	if speed_mps <= airframe.drag_divergence_mps:
		return 0.0
	var over := (speed_mps - airframe.drag_divergence_mps) / airframe.drag_divergence_mps
	return over * over


## How separated the flow is, 0 while the wing is flying and 1 once it is a
## flat plate. Quadratic so the first few degrees past the stall are cheap and
## the deep stall is ruinous.
func separation(alpha_radians: float) -> float:
	var onset := deg_to_rad(airframe.stall_alpha_degrees)
	var full := deg_to_rad(airframe.cd_stall_full_degrees)
	var fraction := clampf((absf(alpha_radians) - onset) / maxf(full - onset, 0.001), 0.0, 1.0)
	return fraction * fraction


## Drag coefficient. The induced term is the important one: it goes as the
## square of the lift coefficient, which is why hard turns cost speed. The
## separated term takes over where the induced one gives up, so that past the
## stall the aircraft is paying more for its drag rather than less.
func drag_coefficient(lift_c: float, speed_mps: float, alpha_radians := 0.0) -> float:
	return (
		airframe.cd0
		+ airframe.k_induced * lift_c * lift_c
		+ airframe.cd_wave * wave_drag(speed_mps)
		+ airframe.cd_stalled * separation(alpha_radians)
	)


## Fraction of full control authority the surfaces have at this speed. Moments
## go as dynamic pressure, so authority goes as the square of the speed ratio,
## flat at 1.0 from corner speed upward.
func control_authority(speed_mps: float) -> float:
	var ratio := speed_mps / airframe.corner_speed_mps()
	return clampf(ratio * ratio, airframe.control_authority_floor, 1.0)


## Pitch authority, which the nozzles hold up after the tailplane has gone
## slack. Vectoring is worth what the engines are pushing, so it follows the
## throttle rather than the airspeed.
func pitch_authority(speed_mps: float, thrust_fraction: float) -> float:
	var vectored := airframe.thrust_vector_authority * clampf(thrust_fraction, 0.0, 1.0)
	return clampf(maxf(control_authority(speed_mps), vectored), 0.0, 1.0)


## Lift acceleration magnitude, in m/s^2.
func lift_acceleration(speed_mps: float, alpha_radians: float) -> float:
	var lift_c := lift_coefficient(alpha_radians)
	return airframe.aero_authority * speed_mps * speed_mps * lift_c


## Small positive angle of attack needed to balance gravity in level flight.
## Launch uses this same equilibrium as the flight tests, so the live aircraft
## does not begin with zero lift while the tests begin already trimmed.
func trim_alpha(speed_mps: float, falloff: float = 1.0) -> float:
	var lift_scale := airframe.aero_authority * speed_mps * speed_mps * airframe.cl_slope * maxf(falloff, 0.001)
	return clampf(GRAVITY / maxf(lift_scale, 0.001), 0.0, deg_to_rad(airframe.stall_alpha_degrees))


## Drag acceleration back along the velocity, in m/s^2.
func drag_acceleration(speed_mps: float, alpha_radians: float) -> float:
	var lift_c := lift_coefficient(alpha_radians)
	var drag_c := drag_coefficient(lift_c, speed_mps, alpha_radians)
	return airframe.aero_authority * speed_mps * speed_mps * drag_c


## Thrust acceleration in m/s^2. The throttle runs 0 to 1 for idle to military
## power, and past 1 into afterburner.
func thrust_acceleration(throttle: float, afterburner: float) -> float:
	var dry := lerpf(airframe.thrust_idle_g, airframe.thrust_military_g, clampf(throttle, 0.0, 1.0))
	var wet := lerpf(dry, airframe.thrust_afterburner_g, clampf(afterburner, 0.0, 1.0))
	return wet * GRAVITY


## Engines spool; they do not step. Returns the new thrust setting after delta.
## This is what makes the throttle command a target thrust rather than a speed.
func spool(current: float, commanded: float, response: float, delta: float) -> float:
	return lerpf(current, commanded, 1.0 - exp(-response * delta))


## The most G the wing can generate at this speed, whatever the pilot asks for.
func aerodynamic_load_limit(speed_mps: float) -> float:
	return airframe.aero_authority * speed_mps * speed_mps * airframe.cl_max() / GRAVITY


## Pitch rate capped so the load factor stays inside the limit. Because
## n = v * omega / g, the same stick gives a lower rate the faster you go, which
## is why a fast turn is a wide one.
func load_limited_pitch_rate(speed_mps: float, commanded: float) -> float:
	if speed_mps < 1.0:
		return commanded
	var cap := airframe.load_limit_g * GRAVITY / speed_mps
	return signf(commanded) * minf(absf(commanded), cap)


## The load factor a given pitch rate is actually pulling.
func load_factor(speed_mps: float, pitch_rate: float) -> float:
	return absf(speed_mps * pitch_rate) / GRAVITY


## The slowest the aircraft can hold level flight: below this the wing cannot
## carry its own weight at any angle and the nose mushes. Derived from the lift
## curve rather than chosen, so retuning lift moves it automatically.
func mush_speed() -> float:
	return sqrt(GRAVITY / (airframe.aero_authority * airframe.cl_max()))


## Angle of attack and sideslip, from the velocity expressed in body axes.
## The airframe's nose is local +X, its up +Y and its right wing +Z.
func alpha_beta(velocity_body: Vector3) -> Vector2:
	if absf(velocity_body.x) < 0.01 and velocity_body.length_squared() < 0.01:
		return Vector2.ZERO
	var alpha := atan2(-velocity_body.y, absf(velocity_body.x))
	var beta := atan2(velocity_body.z, absf(velocity_body.x))
	return Vector2(alpha, beta)


## Lift is normal to the airflow, toward the wing's upper side. Applying it
## directly along body-up gives it a rearward component at positive angle of
## attack, making lift itself destroy energy on top of induced drag.
func lift_direction(body_up: Vector3, velocity: Vector3) -> Vector3:
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
## body's upper side, drag back along the velocity, side force opposing slip,
## and gravity. Nothing here
## knows what a turn is. Turning happens because banking tilts the wing and with
## it the lift vector.
func flight_acceleration(
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
		var right := nose.cross(up).normalized()
		var side_speed := velocity.dot(right)
		acceleration -= right * (airframe.aero_authority * airframe.side_force_coefficient * speed * side_speed * falloff)
	return acceleration


## Thrust and lift both fall away as the air thins. Soft, so the aircraft runs
## out of climb rather than striking a ceiling.
func altitude_falloff(altitude_m: float, ceiling_m: float) -> float:
	if ceiling_m <= 0.0:
		return 1.0
	var ratio := clampf(altitude_m / ceiling_m, 0.0, 1.0)
	return 1.0 - ratio * ratio * 0.85
