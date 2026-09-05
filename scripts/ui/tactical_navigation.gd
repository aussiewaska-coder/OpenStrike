extends RefCounted

const MAX_WAYPOINTS := 12
const ARRIVAL_RADIUS_M := 250.0
var points: Array[Vector3] = []
var completed := 0

func add(point: Vector3) -> bool:
	if not point.is_finite() or points.size() >= MAX_WAYPOINTS:
		return false
	points.append(point)
	return true

func advance(position: Vector3) -> bool:
	if points.is_empty():
		return false
	var delta := Vector2(points[0].x - position.x, points[0].z - position.z)
	if delta.length() > ARRIVAL_RADIUS_M:
		return false
	skip()
	return true

func skip() -> void:
	if not points.is_empty():
		points.pop_front()
		completed += 1

func clear() -> void:
	points.clear()
	completed = 0

static func bearing(from: Vector3, to: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(to.x - from.x, from.z - to.z)), 360.0)
