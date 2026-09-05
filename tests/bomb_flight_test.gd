extends SceneTree

var _test_failed := false

## A bomb is a shell with no muzzle: it leaves at the carrier's speed and falls.
## Nothing here thrusts, which is the whole difference from a rocket.

const BOMB := preload("res://scripts/weapons/bomb_flight.gd")
const PROFILE := preload("res://scripts/weapons/bomb_damage_profile.gd")


func _init() -> void:
	var flight = BOMB.new()
	var carried := Vector3(0.0, 0.0, -95.0)
	var released: Vector3 = flight.release_velocity(carried)
	if not released.is_equal_approx(carried):
		_fail("a bomb leaves at exactly the carrier's velocity, got %v" % released)

	var stepped: Array = flight.advance(Vector3(0.0, 600.0, 0.0), carried, 0.05, 0.0)
	var after: Vector3 = stepped[1]
	if after.y >= 0.0:
		_fail("a bomb must fall, got vy %f" % after.y)
	if after.dot(carried.normalized()) > carried.length() + 0.001:
		_fail("a bomb must not accelerate forward, got vz %f" % after.z)
	if absf(after.z) > absf(carried.z) + 0.001:
		_fail("drag must not add speed")

	if flight.envelope_seconds() < 30.0:
		_fail("a bomb from 900 m needs over thirty seconds to land, got %f" % flight.envelope_seconds())
	if flight.envelope_metres() < 3000.0:
		_fail("a bomb released at speed travels well past a kilometre")

	var profile = PROFILE.new()
	if float(profile.structural_damage) * 1.35 < 420.0:
		_fail("one roof strike must reach the smoke threshold, got %f" % (profile.structural_damage * 1.35))
	if float(profile.structural_damage) >= 420.0:
		_fail("a facade strike alone must NOT reach the smoke threshold, or every bomb smokes")

	if _test_failed:
		return
	print("BOMB_FLIGHT_TEST_PASS")
	quit()


func _fail(message: String) -> void:
	_test_failed = true
	push_error(message)
	quit(1)
