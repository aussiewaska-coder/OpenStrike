extends RefCounted

# Chin-turret articulation. Aims at a world POINT rather than a direction, so
# the turret self-corrects as the airframe drifts underneath it - that is the
# stabilisation in spec section 9. The slew-rate cap is what stops it being
# perfect, which is what makes it read as mechanical.

enum AimSource { FORWARD, FREE_LOOK, TARGET }

var max_yaw_left := 85.0
var max_yaw_right := 85.0
var max_pitch_up := 11.0
var max_pitch_down := 60.0
var turret_yaw_speed := 115.0
var turret_pitch_speed := 90.0
var turret_response := 9.0
var gun_return_response := 3.2

var yaw_degrees := 0.0
var pitch_degrees := 0.0
var aim_source := AimSource.FORWARD
var at_limit := false
var desired_point := Vector3.ZERO
var has_desired_point := false

var _target_provider := Callable()
var _look_provider := Callable()


func set_target_provider(provider: Callable) -> void:
	_target_provider = provider


func set_look_provider(provider: Callable) -> void:
	_look_provider = provider


func resolve_desired_point() -> Variant:
	# Held A is direct manual aim and must override an old selected target.
	if _look_provider.is_valid():
		var look: Variant = _look_provider.call()
		if look is Vector3:
			aim_source = AimSource.FREE_LOOK
			return look
	if _target_provider.is_valid():
		var target: Variant = _target_provider.call()
		if target is Vector3:
			aim_source = AimSource.TARGET
			return target
	aim_source = AimSource.FORWARD
	return null


func update(delta: float, muzzle_origin: Vector3, hull_yaw_radians: float) -> void:
	var point: Variant = resolve_desired_point()
	has_desired_point = point is Vector3
	var desired := Vector2.ZERO
	if has_desired_point:
		desired_point = point
		desired = local_aim_for(muzzle_origin, desired_point, hull_yaw_radians)
	var clamped := clamp_aim(desired)
	at_limit = has_desired_point and not clamped.is_equal_approx(desired)
	var yaw_rate := turret_yaw_speed if has_desired_point else turret_yaw_speed * 0.6
	var pitch_rate := turret_pitch_speed if has_desired_point else turret_pitch_speed * 0.6
	var response := turret_response if has_desired_point else gun_return_response
	# Ease toward the solution, then hard-cap the traverse rate so the barrel is
	# always seen to travel rather than teleport.
	var weight := 1.0 - exp(-response * delta)
	var eased_yaw := lerpf(yaw_degrees, clamped.x, weight)
	var eased_pitch := lerpf(pitch_degrees, clamped.y, weight)
	yaw_degrees = move_toward(yaw_degrees, eased_yaw, yaw_rate * delta)
	pitch_degrees = move_toward(pitch_degrees, eased_pitch, pitch_rate * delta)


func clamp_aim(aim: Vector2) -> Vector2:
	return Vector2(
		clampf(aim.x, -max_yaw_left, max_yaw_right),
		clampf(aim.y, -max_pitch_down, max_pitch_up)
	)


func local_aim_for(muzzle_origin: Vector3, point: Vector3, hull_yaw_radians: float) -> Vector2:
	var to_target := point - muzzle_origin
	if to_target.is_zero_approx():
		return Vector2.ZERO
	# A yaw of theta about +Y maps the nose (+X) to (cos, 0, -sin).
	var world_yaw := atan2(-to_target.z, to_target.x)
	var local_yaw := wrapf(world_yaw - hull_yaw_radians, -PI, PI)
	var horizontal := Vector2(to_target.x, to_target.z).length()
	var local_pitch := atan2(to_target.y, horizontal)
	return Vector2(rad_to_deg(local_yaw), rad_to_deg(local_pitch))
