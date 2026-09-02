extends SceneTree

## The rocket's whole character is in two phases: it accelerates hard and flies
## fairly straight while the motor burns, then droops once it is out. If the
## droop is not visible in a salvo, the model may as well be a shell.

const ROCKET := preload("res://scripts/weapons/rocket_flight.gd")


func _init() -> void:
	_boost_accelerates()
	_motor_cuts_out()
	_coast_falls()
	_launch_inherits_the_aircraft()
	_envelope_is_its_own()
	print("ROCKET_FLIGHT_TEST_PASS")
	quit()


func _boost_accelerates() -> void:
	var flight = ROCKET.new()
	if not flight.is_boosting(0.0):
		_fail("the motor must be lit at launch")
	var start := Vector3(120.0, 0.0, 0.0)
	var stepped: Array = flight.advance(Vector3.ZERO, start, 0.05, 0.0)
	var gained: float = (stepped[1] as Vector3).x - start.x
	if gained <= 0.0:
		_fail("the motor must add speed along the heading, gained %f" % gained)


func _motor_cuts_out() -> void:
	var flight = ROCKET.new()
	if flight.is_boosting(ROCKET.MOTOR_BURN_SECONDS + 0.01):
		_fail("the motor must cut out at the end of its burn")
	var fast := Vector3(300.0, 0.0, 0.0)
	var boosting: Array = flight.advance(Vector3.ZERO, fast, 0.05, 0.0)
	var coasting: Array = flight.advance(Vector3.ZERO, fast, 0.05, ROCKET.MOTOR_BURN_SECONDS + 1.0)
	if (boosting[1] as Vector3).x <= (coasting[1] as Vector3).x:
		_fail("a burning motor must leave the rocket faster than a dead one")


## Coasting is ballistic: gravity wins and the nose drops. This is the droop.
func _coast_falls() -> void:
	var flight = ROCKET.new()
	var level := Vector3(250.0, 0.0, 0.0)
	var stepped: Array = flight.advance(
		Vector3.ZERO, level, 0.05, ROCKET.MOTOR_BURN_SECONDS + 1.0
	)
	if (stepped[1] as Vector3).y >= 0.0:
		_fail("a coasting rocket must fall, got vy %f" % (stepped[1] as Vector3).y)


func _launch_inherits_the_aircraft() -> void:
	var flight = ROCKET.new()
	var carried := Vector3(0.0, 0.0, -175.0)
	var launched: Vector3 = flight.launch_velocity(Vector3(0.0, 0.0, -1.0), carried)
	if launched.length() <= carried.length():
		_fail("a rocket must leave faster than the aircraft carrying it")
	# Ejection alone is small: the motor, not the rail, is what makes it quick.
	if launched.length() > carried.length() + 60.0:
		_fail("the ejection impulse must be modest, got %f" % (launched.length() - carried.length()))


func _envelope_is_its_own() -> void:
	var flight = ROCKET.new()
	if flight.envelope_seconds() <= 0.0 or flight.envelope_metres() <= 0.0:
		_fail("a rocket must declare a positive envelope")
	if flight.envelope_metres() <= 4000.0:
		_fail("the rocket must outrange the 30 mm shell it no longer borrows limits from")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
