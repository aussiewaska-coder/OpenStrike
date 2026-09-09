extends SceneTree
const FLIGHT := preload("res://scripts/weapons/guided_ground_flight.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const LAUNCHER := preload("res://scripts/weapons/missile_launcher.gd")
const WEAPONS := preload("res://scripts/weapons/weapon_selection.gd")
const MANAGER := preload("res://scripts/weapons/projectile_manager.gd")
const QUERY := preload("res://scripts/world/world_hit_query.gd")
const INDEX := preload("res://scripts/entities/entity_hit_index.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")
class Carrier extends Node3D:
	var velocity := Vector3(0, 0, -220)
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_envelopes()
	for powered in [false, true]:
		for dt in [1.0 / 60.0, 1.0 / 120.0]:
			_intercept(powered, dt, false)
		_intercept(powered, 1.0 / 60.0, true)
	if not failed:
		print("GUIDED_GROUND_TEST_PASS")
	quit(1 if failed else 0)

func _envelopes() -> void:
	var origin := Vector3(0, 900, 0)
	var target := TRACKER.contact(1, TRACKER.Kind.GROUND_LAUNCHER, Vector3(0, 10, -2000))
	check(FLIGHT.launch_problem(target, origin, Vector3.FORWARD, Vector3(0, 0, -200), false).is_empty(), "a bomb inside its altitude-dependent envelope can acquire")
	target.position.z = -3000.0
	check(FLIGHT.launch_problem(target, origin, Vector3.FORWARD, Vector3(0, 0, -200), false) == "OUT OF RANGE", "low altitude reduces bomb reach below its hard maximum")
	check(FLIGHT.launch_problem(target, Vector3(0, 2000, 0), Vector3.FORWARD, Vector3(0, 0, -200), false).is_empty(), "additional altitude gives the bomb more reach")
	target.position.z = -4100.0
	check(FLIGHT.launch_problem(target, Vector3(0, 3000, 0), Vector3.FORWARD, Vector3(0, 0, -200), false) == "OUT OF RANGE", "bombs have a hard four-kilometre horizontal limit")
	target.position.z = -8100.0
	check(FLIGHT.launch_problem(target, origin, Vector3.FORWARD, Vector3.ZERO, true) == "OUT OF RANGE", "ground missiles have an eight-kilometre limit")
	target.position.z = -1000.0
	check(FLIGHT.launch_problem(target, origin, Vector3.BACK, Vector3(0, 0, -200), false) == "TURN TOWARD TARGET", "bombs cannot be dropped on targets behind the aircraft")
	check(FLIGHT.launch_problem(target, origin, Vector3.FORWARD, Vector3.ZERO, false) == "TOO SLOW", "bomb release needs forward energy")
	check(FLIGHT.launch_problem(target, Vector3(0, 100, 0), Vector3.FORWARD, Vector3(0, 0, -200), false) == "TOO LOW", "bomb release needs safe separation height")
	target.kind = TRACKER.Kind.AIR_JET
	check(FLIGHT.launch_problem(target, origin, Vector3.FORWARD, Vector3(0, 0, -200), true) == "SELECT GROUND TARGET", "ground weapons reject airborne contacts")
	var bomb := FLIGHT.new()
	check(not bomb.is_boosting(1.0), "a guided bomb has no rocket motor")
	check(bomb.launch_velocity(Vector3.FORWARD, Vector3(0, 0, -200)).z == -200.0, "bombs inherit speed without a forward muzzle impulse")

func _intercept(powered: bool, dt: float, wall: bool) -> void:
	var carrier := Carrier.new()
	root.add_child(carrier)
	carrier.position = Vector3(0, 1000, 0)
	carrier.basis = Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT)
	var hardpoint := Node3D.new()
	carrier.add_child(hardpoint)
	var target := TRACKER.contact(7, TRACKER.Kind.GROUND_LAUNCHER, Vector3(200, 12, -6500 if powered else -2000))
	var tracker := TRACKER.new()
	tracker.update([target], carrier.position, Vector3.FORWARD, Vector3.ZERO)
	tracker.select_contact(7)
	var manager := MANAGER.new()
	root.add_child(manager)
	manager.set_physics_process(false)
	var index := INDEX.new()
	index.add_entity(7, AABB(target.position - Vector3(10, 10, 10), Vector3(20, 20, 20)))
	if wall:
		index.add_entity(99, AABB(Vector3(-3000, 0, -600), Vector3(6000, 2500, 20)))
	var query := QUERY.new()
	query.configure(func(_x, _z): return 2.0, null, null, 0.0)
	query.entity_index = index
	manager.hit_query = query
	var hits := []
	manager.projectile_impacted.connect(func(hit, _round): hits.append(hit))
	var launcher := LAUNCHER.new()
	root.add_child(launcher)
	launcher.carrier = carrier
	launcher.hardpoints = [hardpoint]
	launcher.tracker = tracker
	launcher.projectile_manager = manager
	launcher.selection = WEAPONS.new()
	launcher.selection.current = WEAPONS.Weapon.GROUND_MISSILE if powered else WEAPONS.Weapon.GUIDED_BOMB
	launcher.update(0.2, true)
	check(manager.active_rounds.is_empty(), "ground weapons require acquisition before firing")
	launcher.update(0.7, false)
	launcher.update(0.01, true)
	check(manager.active_rounds.size() == 1, "ground launch uses the production hardpoint and manager")
	if manager.active_rounds.is_empty():
		launcher.free()
		carrier.free()
		manager.free()
		return
	var round_data: RefCounted = manager.active_rounds[0]
	check(round_data.damage_profile != null, "ground weapons carry structural damage")
	check(round_data.weapon_source == ("missile" if powered else "guided_bomb"), "bombs and missiles have distinct visual and blast sources")
	var aim: Vector3 = round_data.flight.target_position
	tracker.clear_lock()
	tracker.track_point(Vector3(5000, 0, 0), TRACKER.Kind.GROUND_POINT, "OTHER")
	check(round_data.flight.target_position == aim, "changing selection after release cannot retarget the weapon")
	for frame in int(30.0 / dt):
		manager.step(dt)
		if manager.active_rounds.is_empty():
			break
	check(hits.size() == 1, "guided ground weapons must reach a physical impact")
	if not hits.is_empty():
		print("GROUND_IMPACT powered=%s dt=%.4f wall=%s id=%d miss=%.1f" % [powered, dt, wall, hits[0].object_id, hits[0].position.distance_to(target.position)])
		check(hits[0].object_id == (99 if wall else 7), "a nearer obstacle stops the shot; unobstructed guidance hits the selected site")
	launcher.free()
	carrier.free()
	manager.free()

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
