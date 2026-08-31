extends RefCounted

## Idle drift and gust wobble for the airframe.
##
## Three sines at incommensurate rates, so the drift reads as unsettled air
## rather than a loop. A hovering aircraft wanders most; translating settles it,
## while a change of velocity rocks it.


static func phases(time: float, frequency: float) -> Vector3:
	return Vector3(
		sin(time * TAU * frequency),
		sin(time * TAU * frequency * 0.61 + 1.1),
		sin(time * TAU * frequency * 0.37 + 2.3)
	)


static func hover_weight(speed_fraction: float) -> float:
	return clampf(1.0 - clampf(speed_fraction, 0.0, 1.0) * 0.7, 0.0, 1.0)


## Vertical bob is the strongest axis; the horizontal wander is half of it.
static func position_offset(phase: Vector3, amplitude: float, weight: float) -> Vector3:
	return Vector3(phase.z * 0.5, phase.x, phase.y * 0.5) * amplitude * weight


## Returns pitch, bank and yaw in degrees.
static func sway_degrees(
	phase: Vector3,
	hover_degrees: float,
	weight: float,
	wobble_degrees: float,
	wobble: float
) -> Vector3:
	var amount := hover_degrees * weight + wobble_degrees * clampf(wobble, 0.0, 1.0)
	return Vector3(phase.x * amount, phase.y * amount * 0.6, phase.z * amount * 0.5)
