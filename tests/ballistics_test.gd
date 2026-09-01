extends SceneTree

const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")


func _init() -> void:
	var gun := BALLISTICS.new()
	var flat := func(_x: float, _z: float) -> float: return 0.0

	# A level shot from 100 m falls onto the ground down range.
	var level: Dictionary = gun.solve(Vector3(0.0, 100.0, 0.0), Vector3.RIGHT, flat)
	if level.is_empty():
		push_error("a level shot over flat ground must find the ground")
		quit(1)
	var impact: Vector3 = level["point"]
	if absf(impact.y) > 1.0:
		push_error("impact should sit on the ground, got y = %f" % impact.y)
		quit(1)
	if impact.x <= 0.0:
		push_error("the round must travel along the nose, got x = %f" % impact.x)
		quit(1)

	# Drag makes the flight slower than an undragged round covering the same
	# range, which is the whole reason the sight computes a time of flight.
	var drag_free_time: float = float(level["range"]) / gun.muzzle_velocity
	if float(level["time"]) <= drag_free_time:
		push_error("drag must lengthen the time of flight: %f vs %f" % [level["time"], drag_free_time])
		quit(1)

	# Firing from higher up reaches further and takes longer.
	var low: Dictionary = gun.solve(Vector3(0.0, 40.0, 0.0), Vector3.RIGHT, flat)
	if float(level["range"]) <= float(low["range"]):
		push_error("a higher shot must reach further")
		quit(1)
	if float(level["time"]) <= float(low["time"]):
		push_error("a higher shot must fly longer")
		quit(1)

	# High enough and the round outruns the sight's maximum range before it
	# lands, which must read as no solution rather than a capped one.
	var beyond: Dictionary = gun.solve(Vector3(0.0, 400.0, 0.0), Vector3.RIGHT, flat)
	if not beyond.is_empty():
		push_error("a shot past the maximum range must have no firing solution")
		quit(1)

	# A steep shot hits close, so the pipper walks back toward the aircraft as
	# the nose drops.
	var steep: Dictionary = gun.solve(Vector3(0.0, 100.0, 0.0), Vector3(1.0, -1.0, 0.0), flat)
	if float(steep["range"]) >= float(level["range"]):
		push_error("a diving shot must hit nearer than a level one")
		quit(1)

	# Rising ground brings the impact nearer still.
	var slope := func(x: float, _z: float) -> float: return maxf(0.0, x * 0.2)
	var uphill: Dictionary = gun.solve(Vector3(0.0, 100.0, 0.0), Vector3.RIGHT, slope)
	if float(uphill["range"]) >= float(level["range"]):
		push_error("rising ground must shorten the range")
		quit(1)

	# Nothing to hit: the sight must show no solution rather than a wrong one.
	var sky: Dictionary = gun.solve(Vector3(0.0, 100.0, 0.0), Vector3.UP, flat)
	if not sky.is_empty():
		push_error("a shot into the sky must have no firing solution")
		quit(1)

	# Rounds inherit the airframe's velocity, and the sight must account for it
	# or a sideways orbit would shoot where the aircraft used to be.
	var profile: Resource = load("res://scripts/weapons/ballistic_profile.gd").new()
	var shared := BALLISTICS.new()
	shared.adopt(profile)
	assert(is_equal_approx(shared.muzzle_velocity, profile.muzzle_velocity), "adopt must take the profile")
	assert(is_equal_approx(shared.step_seconds, profile.simulation_step), "adopt must take the step")
	var still_launch := shared.launch_velocity(Vector3.RIGHT, Vector3.ZERO)
	assert(is_equal_approx(still_launch.length(), shared.muzzle_velocity), "muzzle speed at rest")
	var moving_launch := shared.launch_velocity(Vector3.RIGHT, Vector3(0.0, 0.0, -50.0))
	assert(is_equal_approx(moving_launch.z, -50.0), "carrier velocity must be added")

	# advance() is the step both the sight and the live rounds integrate through.
	var stepped: Array = shared.advance(Vector3.ZERO, Vector3.RIGHT * 805.0, 1.0)
	var slowed: Vector3 = stepped[1]
	assert(slowed.length() < 805.0, "drag must bleed speed")
	assert(slowed.y < 0.0, "gravity must pull the round down")
	var vacuum := BALLISTICS.new()
	vacuum.drag_per_second = 0.0
	var no_drag: Array = vacuum.advance(Vector3.ZERO, Vector3.RIGHT * 805.0, 0.5)
	assert(is_equal_approx((no_drag[1] as Vector3).x, 805.0), "no drag must preserve forward speed")

	var carried_level := shared.solve(Vector3(0.0, 120.0, 0.0), Vector3.RIGHT, flat)
	var led := shared.solve(Vector3(0.0, 120.0, 0.0), Vector3.RIGHT, flat, Vector3(0.0, 0.0, -60.0))
	assert(not carried_level.is_empty() and not led.is_empty(), "both shots must solve")
	assert(absf((led["point"] as Vector3).z) > 5.0, "inherited velocity must displace the impact")

	# A world query must be able to stop the solution short of the ground.
	var wall := func(from: Vector3, to: Vector3) -> RefCounted:
		if maxf(from.x, to.x) < 200.0:
			return null
		var result: RefCounted = load("res://scripts/world/world_hit_result.gd").new()
		result.hit = true
		result.t = 0.0
		result.position = Vector3(200.0, from.y, from.z)
		result.normal = Vector3.LEFT
		return result
	var stopped := shared.solve(Vector3(0.0, 120.0, 0.0), Vector3.RIGHT, flat, Vector3.ZERO, wall)
	assert(not stopped.is_empty(), "the blocked shot must solve")
	assert(absf((stopped["point"] as Vector3).x - 200.0) < 20.0, "the solution must stop at the obstacle")
	assert((stopped["point"] as Vector3).x < (carried_level["point"] as Vector3).x, "the obstacle must shorten the range")

	print("BALLISTICS_TEST_PASS")
	quit()
