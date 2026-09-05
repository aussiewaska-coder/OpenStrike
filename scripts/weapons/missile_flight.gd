extends RefCounted

## Game-scale seekers and powered lead pursuit. Surface hits are resolved by
## ProjectileManager before the proximity fuse, so buildings still stop shots.
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")
enum Seeker {HEAT, RADAR}
const IGNITION_DELAY := 0.18
const ARMING_TIME := 0.45
const FUSE_RADIUS := 14.0
const GRAVITY := 9.80665

var seeker: int = Seeker.HEAT
var target_handle := -1
var target_provider := Callable()
var radar_lock_provider := Callable()
var _seeker_lost_time := 0.0
var _guidance_lost := false
var _last_target := {}

func target() -> Dictionary:
	return target_provider.call(target_handle) if target_provider.is_valid() else {}

func launch_velocity(direction: Vector3, inherited: Vector3) -> Vector3:
	return inherited + direction.normalized() * 35.0 + Vector3.DOWN * 8.0

func is_boosting(age: float) -> bool:
	return age >= IGNITION_DELAY and age < (6.0 if seeker == Seeker.RADAR else 3.8)

func advance(point: Vector3, velocity: Vector3, delta: float, age := 0.0) -> Array:
	var next := velocity * exp(-0.018 * delta)
	var c := target()
	var valid := not c.is_empty() and TRACKER.is_airborne(c)
	if seeker == Seeker.RADAR:
		valid = valid and radar_lock_provider.is_valid() and int(radar_lock_provider.call()) == target_handle
	if valid and velocity.length_squared() > 1.0:
		var offset: Vector3 = c.position - point
		valid = velocity.normalized().angle_to(offset.normalized()) < deg_to_rad(80.0)
	_seeker_lost_time = 0.0 if valid else _seeker_lost_time + delta
	if _seeker_lost_time > 0.65:
		_guidance_lost = true
	_last_target = c if valid and not _guidance_lost else {}
	if age >= IGNITION_DELAY and not _last_target.is_empty():
		var offset: Vector3 = c.position - point
		var lead_time := clampf(offset.length() / maxf(velocity.length(), 250.0), 0.0, 4.0)
		var aim: Vector3 = c.position + c.velocity * lead_time
		# The longer-range weapon climbs gently before pitching down into its
		# terminal lead. No random weaving: curvature follows a moving target.
		if seeker == Seeker.RADAR:
			aim.y += minf(offset.length() * 0.12, 650.0) * smoothstep(1200.0, 4000.0, offset.length())
		var wanted := (aim - point).normalized()
		var heading := next.normalized()
		var angle := heading.angle_to(wanted)
		var max_rate := minf(2.2, 28.0 * GRAVITY / maxf(next.length(), 100.0))
		if angle > 0.00001:
			heading = heading.slerp(wanted, minf(1.0, max_rate * delta / angle)).normalized()
		next = heading * next.length()
	if is_boosting(age):
		next += next.normalized() * (155.0 if seeker == Seeker.RADAR else 190.0) * delta
	next.y -= GRAVITY * delta
	next = next.limit_length(950.0)
	return [point + (velocity + next) * 0.5 * delta, next]

func proximity_hit(from: Vector3, to: Vector3, age: float) -> RefCounted:
	if age < ARMING_TIME or _last_target.is_empty():
		return null
	var segment := to - from
	var point: Vector3 = _last_target.position
	var t := clampf((point - from).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
	var closest := from + segment * t
	if closest.distance_to(point) > FUSE_RADIUS:
		return null
	var hit := HIT.new()
	hit.hit = true
	hit.position = closest
	hit.t = t
	hit.object_type = HIT.ObjectKind.ENTITY
	hit.object_id = target_handle
	hit.incident_velocity = segment
	return hit

func envelope_seconds() -> float:
	return 32.0 if seeker == Seeker.RADAR else 20.0

func envelope_metres() -> float:
	return 22000.0 if seeker == Seeker.RADAR else 10000.0
