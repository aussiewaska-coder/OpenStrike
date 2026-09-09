extends RefCounted

## Ease head-turn speed, retaining the final glance after the stick settles.
## Braking is quicker than starting so fine adjustments stay controllable.
const TURN_RESPONSE := 14.0
const STOP_RESPONSE := 24.0
var velocity := Vector2.ZERO


func reset() -> void:
	velocity = Vector2.ZERO


## Return the average input over this frame, integrating the exponential
## exactly so a glance covers the same angle at different render rates.
func advance(input: Vector2, delta: float) -> Vector2:
	if delta <= 0.0:
		return Vector2.ZERO
	var target := input.limit_length()
	var response := STOP_RESPONSE if target.is_zero_approx() else TURN_RESPONSE
	var weight := 1.0 - exp(-response * delta)
	var average := target + (velocity - target) * weight / (response * delta)
	velocity = velocity.lerp(target, weight)
	if target.is_zero_approx() and velocity.length_squared() < 0.00000001:
		velocity = Vector2.ZERO
	return average


## Sub-degree pitch and roll only while turning; no displacement of the
## camera mount and no persistent vibration while holding a settled glance.
func bob_basis(time_seconds: float) -> Basis:
	var strength := velocity.length()
	var pitch := sin(time_seconds * TAU * 1.4) * deg_to_rad(0.28) * strength
	var roll := sin(time_seconds * TAU * 0.9) * deg_to_rad(0.18) * strength
	return Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
