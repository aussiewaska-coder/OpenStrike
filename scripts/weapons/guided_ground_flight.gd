extends RefCounted

## Arcade coordinate guidance: finite steering and energy, no target teleport.
## WorldHitQuery owns collision, so terrain and buildings can stop the weapon.
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")
const BOMB_RANGE_M := 4000.0
const MISSILE_RANGE_M := 8000.0
const GRAVITY := 9.80665
var powered := false
var target_handle := -1
var target_position := Vector3.ZERO
var target_name := "GROUND TARGET"
var target_provider := Callable()

func tracking_state(_point: Vector3, _velocity: Vector3) -> Dictionary:
	return {
		"weapon": "GROUND MISSILE" if powered else "GUIDED BOMB",
		"target_position": target_position, "target_name": target_name,
		"locked": true, "status": "COORDINATE LOCK",
	}

static func ground_contact(c: Dictionary) -> bool:
	return int(c.get("kind", -1)) in [TRACKER.Kind.GROUND_LAUNCHER, TRACKER.Kind.BUILDING, TRACKER.Kind.GROUND_POINT]

static func launch_problem(c: Dictionary, origin: Vector3, forward: Vector3, velocity: Vector3, missile: bool) -> String:
	if not ground_contact(c):
		return "SELECT GROUND TARGET"
	var offset: Vector3 = c.position - origin
	var height := -offset.y
	var horizontal := Vector3(offset.x, 0.0, offset.z)
	if height < (40.0 if missile else 150.0):
		return "TOO LOW"
	if horizontal.length() < 150.0:
		return "TOO CLOSE"
	var reach := MISSILE_RANGE_M if missile else minf(BOMB_RANGE_M, height * 2.5)
	if horizontal.length() > reach or offset.length() > (9000.0 if missile else 5000.0):
		return "OUT OF RANGE"
	if not missile and velocity.length() < 80.0:
		return "TOO SLOW"
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	if flat_forward.is_zero_approx() or flat_forward.angle_to(horizontal) > deg_to_rad(65.0 if missile else 45.0):
		return "TURN TOWARD TARGET"
	return ""

func launch_velocity(direction: Vector3, inherited: Vector3) -> Vector3:
	return inherited + direction.normalized() * (40.0 if powered else 0.0) + Vector3.DOWN * 12.0

func is_boosting(age: float) -> bool:
	return powered and age >= 0.2 and age < 7.0

func advance(point: Vector3, velocity: Vector3, delta: float, age := 0.0) -> Array:
	var next := velocity * exp(-0.015 * delta) + Vector3.DOWN * GRAVITY * delta
	if age >= 0.2 and next.length_squared() > 1.0:
		var wanted := (target_position - point).normalized()
		var heading := next.normalized()
		var angle := heading.angle_to(wanted)
		if angle > 0.00001:
			heading = heading.slerp(wanted, minf(1.0, (1.6 if powered else 0.7) * delta / angle)).normalized()
		next = heading * next.length()
	if is_boosting(age):
		next += next.normalized() * 110.0 * delta
	next = next.limit_length(700.0 if powered else 350.0)
	return [point + (velocity + next) * 0.5 * delta, next]

func proximity_hit(from: Vector3, to: Vector3, age: float) -> RefCounted:
	if age < 0.5 or target_handle < 0 or not target_provider.is_valid():
		return null
	var c: Dictionary = target_provider.call(target_handle)
	if c.is_empty() or int(c.get("kind", -1)) != TRACKER.Kind.GROUND_LAUNCHER:
		return null
	var segment := to - from
	var t := clampf((target_position - from).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
	var closest := from + segment * t
	if closest.distance_to(target_position) > 8.0:
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
	return 30.0

func envelope_metres() -> float:
	return 12000.0 if powered else 6500.0
