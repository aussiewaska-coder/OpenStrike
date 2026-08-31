extends SceneTree

const ORBIT := preload("res://scripts/helicopter/target_orbit.gd")
const GROUND_RAY := preload("res://scripts/terrain/ground_ray.gd")


func _init() -> void:
	var target := Vector3.ZERO

	# The orbit radius is whatever distance the aircraft is already at, so
	# picking a target never yanks it onto a fixed circle.
	var position := Vector3(300.0, 120.0, 0.0)
	_assert_approx(ORBIT.radius_to(position, target), 300.0, "radius is the current distance")

	# On the circle with no radial error, the velocity is purely tangential:
	# perpendicular to the line back to the target.
	var velocity: Vector3 = ORBIT.desired_velocity(position, target, 300.0, 1.0, 40.0, 0.5)
	var outward := Vector3(1.0, 0.0, 0.0)
	if absf(velocity.dot(outward)) > 0.001:
		push_error("a settled orbit must not drift in or out, got %f" % velocity.dot(outward))
		quit(1)
	_assert_approx(velocity.length(), 40.0, "orbit speed is held")

	# Reversing the trigger reverses the sweep.
	var reversed: Vector3 = ORBIT.desired_velocity(position, target, 300.0, -1.0, 40.0, 0.5)
	if velocity.normalized().dot(reversed.normalized()) > -0.999:
		push_error("the other trigger must sweep the other way")
		quit(1)

	# Too far out, the velocity leans back toward the circle rather than
	# spiralling away.
	var wide: Vector3 = ORBIT.desired_velocity(Vector3(400.0, 120.0, 0.0), target, 300.0, 1.0, 40.0, 0.5)
	if wide.dot(outward) >= 0.0:
		push_error("an aircraft outside the circle must be pulled inward")
		quit(1)
	var tight: Vector3 = ORBIT.desired_velocity(Vector3(200.0, 120.0, 0.0), target, 300.0, 1.0, 40.0, 0.5)
	if tight.dot(outward) <= 0.0:
		push_error("an aircraft inside the circle must be pushed outward")
		quit(1)

	# The nose points at the target: the airframe faces its local +X, so a
	# target due -X of the aircraft is a half turn away.
	_assert_approx(ORBIT.heading_to(Vector3(-100.0, 0.0, 0.0), target), 0.0, "target ahead needs no turn")
	_assert_approx(absf(ORBIT.heading_to(Vector3(100.0, 0.0, 0.0), target)), PI, "target behind is a half turn")

	# A ray into the ground finds it, and refines well past the march step.
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var hit: Dictionary = GROUND_RAY.intersect(Vector3(0.0, 500.0, 0.0), Vector3.DOWN, flat)
	if hit.is_empty():
		push_error("a ray straight down must find the ground")
		quit(1)
	var point: Vector3 = hit["point"]
	if absf(point.y) > 0.1:
		push_error("the hit must be refined onto the surface, got y = %f" % point.y)
		quit(1)

	# An angled ray lands down range, not underneath.
	var angled: Dictionary = GROUND_RAY.intersect(Vector3(0.0, 100.0, 0.0), Vector3(1.0, -1.0, 0.0), flat)
	if angled.is_empty() or absf(float(angled["point"].x) - 100.0) > 1.0:
		push_error("a 45 degree ray from 100 m must land 100 m away, got %s" % angled)
		quit(1)

	# A ray into the sky finds nothing rather than inventing a target.
	if not GROUND_RAY.intersect(Vector3(0.0, 100.0, 0.0), Vector3.UP, flat).is_empty():
		push_error("a ray into the sky must not hit the ground")
		quit(1)

	# Rising ground is hit on the way up, not at the flat height.
	var slope := func(x: float, _z: float) -> float: return maxf(0.0, x * 0.5)
	var uphill: Dictionary = GROUND_RAY.intersect(Vector3(0.0, 100.0, 0.0), Vector3(1.0, -0.2, 0.0), flat)
	var uphill_slope: Dictionary = GROUND_RAY.intersect(Vector3(0.0, 100.0, 0.0), Vector3(1.0, -0.2, 0.0), slope)
	if uphill_slope.is_empty() or float(uphill_slope["distance"]) >= float(uphill["distance"]):
		push_error("rising ground must be hit sooner than flat")
		quit(1)
	print("TARGET_ORBIT_TEST_PASS")
	quit()


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 0.01:
		push_error("%s: expected %f, got %f" % [label, expected, actual])
		quit(1)
