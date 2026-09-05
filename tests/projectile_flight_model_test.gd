extends SceneTree

var _test_failed := false

## A round advances through the flight model it carries, and is retired by that
## model's envelope rather than the gun's. Without the second half, a rocket
## would die at the 30 mm shell's 4 km no matter what its motor could do.

const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")
const CANNON_ROUND := preload("res://scripts/weapons/cannon_round.gd")
const PROJECTILE_MANAGER := preload("res://scripts/weapons/projectile_manager.gd")


## A flight model that ignores physics entirely and marches +X at 100 m/s, so
## its effect is unmistakable against real ballistics.
class StubFlight:
	extends RefCounted
	var advance_calls := 0
	var last_age := -1.0

	func advance(point: Vector3, velocity: Vector3, delta: float, age: float) -> Array:
		advance_calls += 1
		last_age = age
		return [point + Vector3(100.0 * delta, 0.0, 0.0), velocity]

	func envelope_seconds() -> float:
		return 0.25

	func envelope_metres() -> float:
		return 100000.0


func _init() -> void:
	_ballistics_keeps_its_shape()
	_round_uses_its_own_flight()
	_round_expires_on_its_own_envelope()
	if _test_failed:
		return
	print("PROJECTILE_FLIGHT_MODEL_TEST_PASS")
	quit()


## The gun's own model must be unchanged: the HUD pipper solves with this exact
## object, so a drift here puts the reticle somewhere the shells do not go.
func _ballistics_keeps_its_shape() -> void:
	var ballistics = BALLISTICS.new()
	var without_age: Array = ballistics.advance(Vector3.ZERO, Vector3(100.0, 0.0, 0.0), 0.02)
	var with_age: Array = ballistics.advance(Vector3.ZERO, Vector3(100.0, 0.0, 0.0), 0.02, 3.0)
	if not (without_age[0] as Vector3).is_equal_approx(with_age[0]):
		_fail("the age argument must not change ballistic flight")
	if not is_equal_approx(ballistics.envelope_seconds(), ballistics.maximum_flight_seconds):
		_fail("ballistics must report its own flight-seconds envelope")
	if not is_equal_approx(ballistics.envelope_metres(), ballistics.maximum_range):
		_fail("ballistics must report its own range envelope")


func _round_uses_its_own_flight() -> void:
	var manager = PROJECTILE_MANAGER.new()
	manager.ballistics = BALLISTICS.new()
	var flight := StubFlight.new()
	var round_data = CANNON_ROUND.new()
	round_data.initialise(1, Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO, false, null, "test")
	round_data.flight = flight
	manager.spawn(round_data)
	manager.step(0.1)
	if flight.advance_calls == 0:
		_fail("the manager must advance a round through the flight model it carries")
	if round_data.position.x <= 0.0:
		_fail("the stub flight marches +X, so the round must have moved, got %f" % round_data.position.x)
	if flight.last_age < 0.0:
		_fail("the flight model must receive the round's age")
	manager.free()


func _round_expires_on_its_own_envelope() -> void:
	var manager = PROJECTILE_MANAGER.new()
	manager.ballistics = BALLISTICS.new()
	var round_data = CANNON_ROUND.new()
	round_data.initialise(1, Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO, false, null, "test")
	round_data.flight = StubFlight.new()
	manager.spawn(round_data)
	# The stub's envelope is 0.25 s; the gun's is 20 s. Step past the former.
	for _i in range(40):
		manager.step(0.02)
	if not manager.active_rounds.is_empty():
		_fail("the round must retire on its own 0.25 s envelope, not the gun's 20 s")
	manager.free()


func _fail(message: String) -> void:
	_test_failed = true
	push_error(message)
	quit(1)
