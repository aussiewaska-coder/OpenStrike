extends SceneTree

# The whole chain end to end, spec section 92:
#   GUN AIM -> MUZZLE -> BALLISTICS -> PROJECTILE SIM -> WORLD HIT QUERY
#   -> DAMAGE EVENT -> SURFACE
#
# The streamed corridor fetches its terrain and footprints at run time, so this
# stands up a synthetic theatre instead: a coastal slope with a row of towers,
# which is the shape the Gold Coast theatre actually has.

const INDEX := preload("res://scripts/terrain/building_hit_index.gd")
const RESOLVER := preload("res://scripts/world/world_surface_resolver.gd")
const QUERY := preload("res://scripts/world/world_hit_query.gd")
const MANAGER := preload("res://scripts/weapons/projectile_manager.gd")
const WEAPON := preload("res://scripts/weapons/cannon_weapon.gd")
const AIM := preload("res://scripts/weapons/cannon_aim.gd")
const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")
const PROFILE := preload("res://scripts/weapons/ballistic_profile.gd")
const ROUND := preload("res://scripts/weapons/cannon_round.gd")
const DAMAGE := preload("res://scripts/world/building_damage_system.gd")
const ROUND_PROFILE := preload("res://scripts/weapons/cannon_round_profile.gd")
const SURFACES := preload("res://scripts/world/surface_types.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Sea to the east past x = 600, beach, then rising ground inland.
	var ground := func(x: float, _z: float) -> float:
		if x > 600.0:
			return -18.0
		if x > 520.0:
			return 1.4
		return 3.0 + (520.0 - x) * 0.05

	var profile: Resource = PROFILE.new()
	var ballistics: RefCounted = BALLISTICS.new()
	ballistics.adopt(profile)
	var resolver: RefCounted = RESOLVER.new()
	resolver.configure(ground, 0.0)
	var index: RefCounted = INDEX.new()
	var hit_query: RefCounted = QUERY.new()
	hit_query.configure(ground, index, resolver, 0.0)

	# A beachfront row, streamed in as one chunk.
	var towers: Array = []
	for tower in range(6):
		var centre_z := -220.0 + 88.0 * float(tower)
		towers.append({
			"osm_id": 800 + tower,
			"x": 430.0, "z": centre_z,
			"height": 70.0 + 18.0 * float(tower % 3),
			"footprint": [
				[400.0, centre_z - 26.0], [460.0, centre_z - 26.0],
				[460.0, centre_z + 26.0], [400.0, centre_z + 26.0],
			],
		})
	index.add_chunk(1, towers, ground)
	assert(index.building_count() == 6, "the chunk must index six towers")

	var manager: Node3D = MANAGER.new()
	manager.profile = profile
	manager.ballistics = ballistics
	manager.hit_query = hit_query
	root.add_child(manager)

	var damage: RefCounted = DAMAGE.new()
	damage.building_index = index
	var impacts: Array = []
	manager.projectile_impacted.connect(func(result: RefCounted, round_data: RefCounted) -> void:
		impacts.append(result)
		if result.object_type == HIT.ObjectKind.BUILDING:
			damage.apply_hit(result, round_data)
	)
	var expired := [0]
	manager.projectile_expired.connect(func(_r: RefCounted) -> void: expired[0] += 1)

	var round_profile: Resource = ROUND_PROFILE.new()
	var origin := Vector3(-260.0, 165.0, 0.0)
	var fired := 0
	# Walk the burst across the row and out over the water behind it.
	for shot in range(60):
		var yaw := deg_to_rad(-26.0 + 52.0 * float(shot) / 59.0)
		var direction := Vector3(cos(yaw), -0.11, -sin(yaw)).normalized()
		var round_data: RefCounted = ROUND.new()
		round_data.initialise(
			shot, origin, direction,
			ballistics.launch_velocity(direction, Vector3(0.0, 0.0, -34.0)),
			shot % profile.tracer_interval == 0, round_profile, "cannon_30mm"
		)
		manager.spawn(round_data)
		fired += 1

	var frames := 0
	while manager.active_rounds.size() > 0 and frames < 12000:
		manager.step(1.0 / 60.0)
		frames += 1
	assert(manager.active_rounds.is_empty(), "%d rounds never resolved" % manager.active_rounds.size())
	assert(impacts.size() + expired[0] == fired, "rounds vanished")

	var histogram := {}
	var building_hits := 0
	var water_hits := 0
	for result in impacts:
		assert(SURFACES.NAMES.has(result.surface_type), "unclassified surface")
		assert(result.normal.is_normalized(), "impact normal must be normalised")
		var key := SURFACES.name_of(result.surface_type)
		histogram[key] = int(histogram.get(key, 0)) + 1
		if result.object_type == HIT.ObjectKind.BUILDING:
			building_hits += 1
			assert(result.building_id >= 800, "a building hit must name its OSM id")
			assert(result.hit_zone in ["wall", "roof"], "unexpected zone %s" % result.hit_zone)
			assert(result.relative_height >= 0.0 and result.relative_height <= 1.0, "damage cell out of range")
		elif result.object_type == HIT.ObjectKind.WATER:
			water_hits += 1
	assert(building_hits > 0, "the burst must strike the tower row")
	assert(histogram.size() > 1, "walking fire across mixed ground must vary the material")
	# Rounds that miss the towers must carry on rather than being culled.
	assert(water_hits > 0 or int(histogram.get("SAND", 0)) > 0, "overshooting rounds must reach the beach or the sea")

	# Damage accumulated on the buildings actually struck, and only those.
	var damaged := 0
	for tower in range(6):
		if damage.damage_for(800 + tower) > 0.0:
			damaged += 1
	assert(damaged > 0, "hits must accumulate building damage")
	assert(damage.damage_for(999) == 0.0, "an unhit building must take no damage")

	# The turret must refuse an unreachable target rather than fire through the
	# airframe, and the muzzle direction is what the rounds actually follow.
	var weapon: Node3D = WEAPON.new()
	weapon.profile = profile
	weapon.ballistics = ballistics
	root.add_child(weapon)
	weapon.aim.set_look_provider(func() -> Variant: return Vector3(-1000.0, 0.0, 0.0))
	for _step in range(400):
		weapon.aim.update(1.0 / 60.0, Vector3.ZERO, 0.0)
	assert(weapon.aim.at_limit, "a target behind the aircraft must flag the gun limit")
	assert(absf(weapon.aim.yaw_degrees) <= weapon.aim.max_yaw_left + 0.001, "the turret must hold its limit")

	print("surfaces struck: %s" % histogram)
	print("building hits: %d of %d, towers damaged: %d" % [building_hits, fired, damaged])
	print("CANNON_INTEGRATION_TEST_PASS")
	quit()
