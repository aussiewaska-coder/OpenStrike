extends SceneTree

var _test_failed := false

## Evasion is what makes a drone worth chasing. These pin the rules: it breaks
## AWAY from the player's nose and never toward it, it dashes, it jinks, and it
## aborts an attack run rather than pressing through the guns.

const DRONE := preload("res://scripts/entities/drone.gd")

const STEP := 1.0 / 60.0


func _init() -> void:
	_flies_toward_the_city()
	_threat_needs_range_cone_and_closure()
	_breaks_away_from_the_nose()
	_dashes_when_threatened()
	_jinks_reverse()
	_aborts_the_run_when_threatened()
	_resumes_after_the_threat_clears()
	_releases_a_bomb_at_range()
	if _test_failed:
		return
	print("DRONE_TEST_PASS")
	quit()


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return rng


## A drone at the +X edge, heading west toward a city at the origin.
func _inbound() -> RefCounted:
	var drone = DRONE.new()
	drone.position = Vector3(6000.0, DRONE.INBOUND_ALTITUDE, 0.0)
	drone.heading = atan2(-1.0, 0.0)  # nose along -X
	drone.speed = DRONE.DRONE_CRUISE_MPS
	drone.velocity = drone.nose() * drone.speed
	return drone


func _far_player() -> Vector3:
	return Vector3(0.0, 800.0, 20000.0)


func _flies_toward_the_city() -> void:
	var drone := _inbound()
	var start: float = drone.position.x
	for _i in range(120):
		drone.update(STEP, _far_player(), Vector3(0.0, 0.0, -1.0), Vector3.ZERO, _rng())
	if drone.position.x >= start:
		_fail("an inbound drone must close on the city, x went %f -> %f" % [start, drone.position.x])
	if drone.state != DRONE.State.INBOUND:
		_fail("unthreatened and far from the city, the drone stays INBOUND")


func _threat_needs_range_cone_and_closure() -> void:
	var drone := _inbound()
	# Player 800 m behind, nose on the drone, and closing.
	var behind: Vector3 = drone.position + Vector3(800.0, 0.0, 0.0)
	var nose_on := Vector3(-1.0, 0.0, 0.0)
	drone.update(STEP, behind + Vector3(10.0, 0.0, 0.0), nose_on, Vector3.ZERO, _rng())
	if not drone.is_threatened(behind, nose_on):
		_fail("in range, in the cone and closing must be a threat")
	# Same range, nose pointed 90 degrees away: not a threat.
	if drone.is_threatened(behind, Vector3(0.0, 0.0, 1.0)):
		_fail("a player not pointing at the drone is not a threat")
	# Nose on but far away: not a threat.
	if drone.is_threatened(drone.position + Vector3(5000.0, 0.0, 0.0), nose_on):
		_fail("a player outside threat range is not a threat")


func _breaks_away_from_the_nose() -> void:
	var drone := _inbound()
	# Player behind and slightly to the drone's LEFT (-Z), nose on it. The
	# drone must break RIGHT (+Z), increasing the angle off the nose.
	var player: Vector3 = drone.position + Vector3(800.0, 0.0, -60.0)
	var nose: Vector3 = (drone.position - player).normalized()
	drone.update(STEP, player + Vector3(5.0, 0.0, 0.0), nose, Vector3.ZERO, _rng())
	var before_z: float = drone.position.z
	for _i in range(60):
		drone.update(STEP, player, nose, Vector3.ZERO, _rng())
	if drone.state != DRONE.State.EVADING:
		_fail("a threatened drone must be EVADING")
	if drone.position.z <= before_z:
		_fail("the drone must break AWAY from the nose (+Z here), z went %f -> %f" % [before_z, drone.position.z])


func _dashes_when_threatened() -> void:
	var drone := _inbound()
	var player: Vector3 = drone.position + Vector3(800.0, 0.0, 0.0)
	var nose := Vector3(-1.0, 0.0, 0.0)
	drone.update(STEP, player + Vector3(5.0, 0.0, 0.0), nose, Vector3.ZERO, _rng())
	drone.update(STEP, player, nose, Vector3.ZERO, _rng())
	if drone.speed <= DRONE.DRONE_CRUISE_MPS:
		_fail("a threatened drone must dash, speed %f" % drone.speed)
	if drone.speed > DRONE.DRONE_DASH_MPS + 0.001:
		_fail("dash must not exceed the dash speed")


func _jinks_reverse() -> void:
	var drone := _inbound()
	var player: Vector3 = drone.position + Vector3(800.0, 0.0, 0.0)
	var nose := Vector3(-1.0, 0.0, 0.0)
	drone.update(STEP, player + Vector3(5.0, 0.0, 0.0), nose, Vector3.ZERO, _rng())
	drone.update(STEP, player, nose, Vector3.ZERO, _rng())
	var first_sign: float = drone.break_sign
	# Run just past one jink interval.
	var elapsed := 0.0
	while elapsed < DRONE.JINK_INTERVAL + 0.1:
		drone.update(STEP, player, nose, Vector3.ZERO, _rng())
		elapsed += STEP
	if drone.break_sign == first_sign:
		_fail("the break direction must reverse after a jink interval")


func _aborts_the_run_when_threatened() -> void:
	var drone := _inbound()
	drone.assign_target(5, Vector3(0.0, 60.0, 0.0))
	if drone.state != DRONE.State.ATTACK_RUN:
		_fail("assigning a target starts an attack run")
	var player: Vector3 = drone.position + Vector3(800.0, 0.0, 0.0)
	var nose := Vector3(-1.0, 0.0, 0.0)
	drone.update(STEP, player + Vector3(5.0, 0.0, 0.0), nose, Vector3.ZERO, _rng())
	drone.update(STEP, player, nose, Vector3.ZERO, _rng())
	if drone.state != DRONE.State.EVADING:
		_fail("a threatened drone must abort its run, state %d" % drone.state)
	if drone.target_handle != -1:
		_fail("aborting must drop the target")


func _resumes_after_the_threat_clears() -> void:
	var drone := _inbound()
	var player: Vector3 = drone.position + Vector3(800.0, 0.0, 0.0)
	var nose := Vector3(-1.0, 0.0, 0.0)
	drone.update(STEP, player + Vector3(5.0, 0.0, 0.0), nose, Vector3.ZERO, _rng())
	drone.update(STEP, player, nose, Vector3.ZERO, _rng())
	# Threat gone; wait out the evade timer.
	var elapsed := 0.0
	while elapsed < DRONE.EVADE_SECONDS + 0.5:
		drone.update(STEP, _far_player(), Vector3(0.0, 0.0, -1.0), Vector3.ZERO, _rng())
		elapsed += STEP
	if drone.state != DRONE.State.INBOUND:
		_fail("once the threat clears the drone goes back to INBOUND, state %d" % drone.state)
	if drone.speed > DRONE.DRONE_CRUISE_MPS + 0.001:
		_fail("cruise resumes after the dash")


func _releases_a_bomb_at_range() -> void:
	var drone := _inbound()
	drone.position = Vector3(DRONE.BOMB_RELEASE_RANGE + 400.0, 300.0, 0.0)
	drone.assign_target(5, Vector3(0.0, 60.0, 0.0))
	var released := false
	for _i in range(600):
		if drone.update(STEP, _far_player(), Vector3(0.0, 0.0, -1.0), Vector3.ZERO, _rng()):
			released = true
			break
	if not released:
		_fail("an unthreatened attack run must release a bomb")
	if drone.state != DRONE.State.EGRESS:
		_fail("after release the drone egresses, state %d" % drone.state)
	if drone.position.distance_to(Vector3(0.0, 60.0, 0.0)) > DRONE.BOMB_RELEASE_RANGE + 60.0:
		_fail("release must happen near the release range")


func _fail(message: String) -> void:
	_test_failed = true
	push_error(message)
	quit(1)
