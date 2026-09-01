extends SceneTree

# The sight and the rounds must land in the same place (spec sections 61, 81).
# They share one Ballistics instance and one BallisticProfile; this is the test
# that fails the moment someone gives them separate trajectories.

const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")
const PROFILE := preload("res://scripts/weapons/ballistic_profile.gd")
const QUERY := preload("res://scripts/world/world_hit_query.gd")
const RESOLVER := preload("res://scripts/world/world_surface_resolver.gd")
const INDEX := preload("res://scripts/terrain/building_hit_index.gd")
const MANAGER := preload("res://scripts/weapons/projectile_manager.gd")
const CANNON_ROUND := preload("res://scripts/weapons/cannon_round.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile: Resource = PROFILE.new()
	var ballistics: RefCounted = BALLISTICS.new()
	ballistics.adopt(profile)
	assert(is_equal_approx(ballistics.muzzle_velocity, 805.0), "the M230 profile must survive adoption")
	assert(is_equal_approx(ballistics.step_seconds, profile.simulation_step), "the step must come from the profile")

	var ground := func(x: float, z: float) -> float:
		return 12.0 + sin(x * 0.01) * 6.0 + cos(z * 0.008) * 4.0
	var resolver: RefCounted = RESOLVER.new()
	resolver.configure(ground, -1000.0)
	var index: RefCounted = INDEX.new()
	var hit_query: RefCounted = QUERY.new()
	hit_query.configure(ground, index, resolver, -1000.0)

	var origin := Vector3(0.0, 220.0, 0.0)
	var direction := Vector3(1.0, -0.14, 0.0).normalized()

	for carrier in [Vector3.ZERO, Vector3(0.0, 0.0, -46.0), Vector3(28.0, 4.0, 12.0)]:
		var predicted: Dictionary = ballistics.solve(origin, direction, ground, carrier, hit_query.query_segment)
		assert(not predicted.is_empty(), "the sight must find a solution for carrier %s" % carrier)

		var manager: Node3D = MANAGER.new()
		manager.profile = profile
		manager.ballistics = ballistics
		manager.hit_query = hit_query
		root.add_child(manager)
		# Lambdas capture locals by value; an Array is a reference.
		var recorded := [Vector3.INF]
		manager.projectile_impacted.connect(func(result: RefCounted, _r: RefCounted) -> void:
			recorded[0] = result.position
		)
		manager.projectile_expired.connect(func(_r: RefCounted) -> void:
			assert(false, "the round expired instead of striking the ground")
		)
		var round_data: RefCounted = CANNON_ROUND.new()
		round_data.initialise(
			1, origin, direction, ballistics.launch_velocity(direction, carrier), true, null, "test"
		)
		manager.spawn(round_data)
		# A frame time that is not a multiple of the fixed step, so the
		# accumulator is genuinely exercised.
		var frames := 0
		while recorded[0] == Vector3.INF and frames < 6000:
			manager.step(1.0 / 61.0)
			frames += 1
		var impact: Vector3 = recorded[0]
		assert(impact != Vector3.INF, "the live round must land for carrier %s" % carrier)

		var error: float = (predicted["point"] as Vector3).distance_to(impact)
		assert(error < 0.05, "sight and round disagree by %f m for carrier %s" % [error, carrier])
		manager.queue_free()

	# Carrier velocity must actually change the solution, or the agreement above
	# would be trivially true.
	var still: Dictionary = ballistics.solve(origin, direction, ground, Vector3.ZERO, hit_query.query_segment)
	var moving: Dictionary = ballistics.solve(origin, direction, ground, Vector3(0.0, 0.0, -60.0), hit_query.query_segment)
	var drift: float = (still["point"] as Vector3).distance_to(moving["point"])
	assert(drift > 5.0, "flying sideways must move the impact point, moved %f m" % drift)

	# A building in the way must pull the pipper onto the facade, not leave it
	# on the ground behind (spec section 90).
	index.add_chunk(0, [{
		"osm_id": 5, "x": 300.0, "z": 0.0, "height": 160.0,
		"footprint": [[280.0, -30.0], [320.0, -30.0], [320.0, 30.0], [280.0, 30.0]],
	}], ground)
	var blocked: Dictionary = ballistics.solve(origin, direction, ground, Vector3.ZERO, hit_query.query_segment)
	assert(not blocked.is_empty(), "the blocked shot must still solve")
	assert((blocked["point"] as Vector3).x < 321.0, "the pipper must stop on the tower")
	assert(int(blocked.get("object_type", 0)) != 0, "a building solution must report its object type")

	print("PIPPER_AGREEMENT_TEST_PASS")
	quit()
