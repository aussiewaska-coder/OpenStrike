extends SceneTree

var _test_failed := false

## The field is what makes drones real to the rest of the game: an AABB that
## follows each one so rounds can hit it, a target picked off the building
## index, a bomb fired through the projectile manager. The visuals are not
## asserted; headless cannot see them.

const FIELD := preload("res://scripts/entities/drone_field.gd")
const DRONE := preload("res://scripts/entities/drone.gd")
const PROJECTILE_MANAGER := preload("res://scripts/weapons/projectile_manager.gd")
const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")
const BUILDING_INDEX := preload("res://scripts/terrain/building_hit_index.gd")
const HIT_QUERY := preload("res://scripts/world/world_hit_query.gd")

const STEP := 1.0 / 60.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_spawns_at_the_edge_with_unique_ids()
	_bounds_follow_the_drone()
	_a_segment_through_a_drone_hits_it()
	_destroy_removes_it_from_the_index()
	_picks_a_target_and_bombs_it()
	_the_hit_query_sees_both_fields()
	if _test_failed:
		return
	print("DRONE_FIELD_TEST_PASS")
	quit()


func _build() -> Node3D:
	var field = FIELD.new()
	root.add_child(field)
	var manager = PROJECTILE_MANAGER.new()
	field.add_child(manager)
	manager.ballistics = BALLISTICS.new()
	field.projectile_manager = manager
	field.building_index = BUILDING_INDEX.new()
	return field


func _far() -> Vector3:
	return Vector3(0.0, 800.0, 20000.0)


func _spawns_at_the_edge_with_unique_ids() -> void:
	var field := _build()
	field.populate(10, 5000.0, Vector3.ZERO)
	if field.drone_count() != 10:
		_fail("ten drones must spawn, got %d" % field.drone_count())
	var ids := {}
	for drone in field.drones():
		if drone.position.length() < 3500.0:
			_fail("drones spawn at the theatre edge, one is at %v" % drone.position)
		if drone.position.x <= 0.0:
			_fail("drones spawn on the +X side, one is at %v" % drone.position)
		ids[drone.id] = true
		if drone.id < FIELD.FIRST_ID:
			_fail("drone ids must not collide with launcher ids, got %d" % drone.id)
	if ids.size() != 10:
		_fail("drone ids must be unique")
	field.free()


func _bounds_follow_the_drone() -> void:
	var field := _build()
	field.populate(1, 5000.0, Vector3.ZERO)
	var drone = field.drones()[0]
	var before: Vector3 = drone.position
	for _i in range(60):
		field.update(STEP, _far(), Vector3(0.0, 0.0, -1.0))
	# A segment through where it WAS must miss; through where it IS must hit.
	var stale: RefCounted = field.query_segment(before + Vector3(0.0, 0.0, -50.0), before + Vector3(0.0, 0.0, 50.0))
	var fresh: RefCounted = field.query_segment(drone.position + Vector3(0.0, 0.0, -50.0), drone.position + Vector3(0.0, 0.0, 50.0))
	if stale != null and stale.hit:
		_fail("the AABB must move with the drone, a stale segment still hit")
	if fresh == null or not fresh.hit:
		_fail("a segment through the drone's current position must hit")
	field.free()


func _a_segment_through_a_drone_hits_it() -> void:
	var field := _build()
	field.populate(1, 5000.0, Vector3.ZERO)
	field.update(STEP, _far(), Vector3(0.0, 0.0, -1.0))
	var drone = field.drones()[0]
	var hit: RefCounted = field.query_segment(drone.position + Vector3(-40.0, 0.0, 0.0), drone.position + Vector3(40.0, 0.0, 0.0))
	if hit == null or not hit.hit:
		_fail("a segment through a drone must hit it")
	if hit.object_id != drone.id:
		_fail("the hit must carry the drone's id, got %d" % hit.object_id)
	field.free()


func _destroy_removes_it_from_the_index() -> void:
	var field := _build()
	field.populate(1, 5000.0, Vector3.ZERO)
	field.update(STEP, _far(), Vector3(0.0, 0.0, -1.0))
	var drone = field.drones()[0]
	var where: Variant = field.destroy_drone(drone.id)
	if not (where is Vector3):
		_fail("destroying a live drone returns where it was")
	if field.destroy_drone(drone.id) != null:
		_fail("destroying it twice returns null")
	var after: RefCounted = field.query_segment(drone.position + Vector3(-40.0, 0.0, 0.0), drone.position + Vector3(40.0, 0.0, 0.0))
	if after != null and after.hit:
		_fail("a destroyed drone must leave the hit index")
	if drone.state != DRONE.State.DESTROYED:
		_fail("the drone must know it is destroyed")
	field.free()


func _picks_a_target_and_bombs_it() -> void:
	var field := _build()
	var flat := func(_x: float, _z: float) -> float: return 0.0
	field.building_index.add_chunk(0, [{
		"osm_id": 1, "x": 0.0, "z": 0.0, "height": 120.0,
		"footprint": [[-15.0, -15.0], [15.0, -15.0], [15.0, 15.0], [-15.0, 15.0]],
	}], flat)
	field.populate(1, 5000.0, Vector3.ZERO)
	var drone = field.drones()[0]
	# Put it just inside entry range so it picks a target immediately.
	drone.position = Vector3(DRONE.ATTACK_ENTRY_RANGE - 100.0, DRONE.INBOUND_ALTITUDE, 0.0)
	drone.heading = atan2(-1.0, 0.0)
	var bombs := [0]
	field.bomb_released.connect(func(_r) -> void: bombs[0] += 1)
	var elapsed := 0.0
	while elapsed < 60.0 and bombs[0] == 0:
		field.update(STEP, _far(), Vector3(0.0, 0.0, -1.0))
		elapsed += STEP
	if bombs[0] == 0:
		_fail("an unthreatened drone inside entry range must pick the tower and bomb it")
	var bomb: RefCounted = field.projectile_manager.active_rounds[0]
	if bomb.weapon_source != "bomb":
		_fail("the released projectile must be a bomb, got '%s'" % bomb.weapon_source)
	if bomb.flight == null:
		_fail("a bomb must carry its own flight model")
	if bomb.damage_profile == null or float(bomb.damage_profile.structural_damage) < 300.0:
		_fail("a bomb must carry a heavy damage profile")
	field.free()


func _the_hit_query_sees_both_fields() -> void:
	var field := _build()
	field.populate(1, 5000.0, Vector3.ZERO)
	field.update(STEP, _far(), Vector3(0.0, 0.0, -1.0))
	var drone = field.drones()[0]
	var query = HIT_QUERY.new()
	query.configure(func(_x: float, _z: float) -> float: return -1000.0, null, null, -2000.0)
	query.secondary_entity_index = field
	var hit: RefCounted = query.query_segment(drone.position + Vector3(-40.0, 0.0, 0.0), drone.position + Vector3(40.0, 0.0, 0.0))
	if hit == null or not hit.hit or hit.object_id != drone.id:
		_fail("the world hit query must find drones through its second entity source")
	field.free()


func _fail(message: String) -> void:
	_test_failed = true
	push_error(message)
	quit(1)
