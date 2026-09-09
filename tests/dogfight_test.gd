extends SceneTree

const SQUADRON := preload("res://scripts/entities/enemy_squadron.gd")
const ENEMY := preload("res://scripts/entities/enemy_jet.gd")
const FLIGHT := preload("res://scripts/weapons/missile_flight.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const MANAGER := preload("res://scripts/weapons/projectile_manager.gd")
const QUERY := preload("res://scripts/world/world_hit_query.gd")
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_wave_lifecycle()
	_missile_warning_and_terrain()
	_pursues_the_players_actual_tail()
	for manoeuvre in ENEMY.Manoeuvre.values():
		for seeker in FLIGHT.Seeker.values():
			for dt in [1.0 / 60.0, 1.0 / 120.0]:
				_intercept_evader(manoeuvre, seeker, dt)
	if not failed:
		print("DOGFIGHT_TEST_PASS")
	quit(1 if failed else 0)

func _wave_lifecycle() -> void:
	seed(427)
	var squadron := SQUADRON.new()
	root.add_child(squadron)
	var player := Vector3(0, 1200, 0)
	squadron.advance_encounters(19.0, player, Vector3.FORWARD)
	check(squadron.jet_count() == 0, "first flight gives the pilot a settling period")
	squadron.advance_encounters(1.1, player, Vector3.FORWARD)
	check(squadron.jet_count() >= 1 and squadron.jet_count() <= 2, "encounters contain one or two aircraft")
	var first_count := squadron.jet_count()
	for jet in squadron.jets():
		check(jet.position.distance_to(player) < 7500.0, "encounters appear inside default radar range")
		check((jet.position - player).dot(Vector3.FORWARD) > 0.0, "incoming flights start in the forward hemisphere")
	squadron.advance_encounters(100.0, player, Vector3.FORWARD)
	check(squadron.jet_count() == first_count, "a live wave cannot stack more aircraft")
	for jet in squadron.jets().duplicate():
		var id: int = jet.id
		squadron.destroy_jet(id)
		check(squadron.destroy_jet(id) == null, "duplicate impacts cannot award another kill")
	check(squadron.kills == first_count and squadron.jets().is_empty(), "kills retire contact and AI storage")
	squadron.advance_encounters(29.0, player, Vector3.FORWARD)
	check(squadron.jet_count() == 0, "a cleared wave earns a breather")
	squadron.advance_encounters(17.0, player, Vector3.FORWARD)
	check(squadron.jet_count() > 0 and squadron.waves == 2, "a new wave follows destruction")
	for jet in squadron.jets():
		jet.state = ENEMY.State.EGRESS
	squadron.update(21.0, player, Vector3.FORWARD)
	check(squadron.jet_count() == 0 and squadron.contacts().is_empty(), "departed aircraft cannot block future encounters")
	check(squadron.kills == first_count, "departures are not kills")
	squadron.advance_encounters(46.0, player, Vector3.FORWARD)
	check(squadron.waves == 3, "departure also permits a new wave")
	squadron.clear()
	check(squadron.kills == 0 and squadron.waves == 0 and squadron.jets().is_empty(), "theatre reset clears encounter state")
	squadron.free()

func _missile_warning_and_terrain() -> void:
	var squadron := SQUADRON.new()
	root.add_child(squadron)
	squadron.ground_height = func(_point): return 2400.0
	squadron.spawn(1, Vector3(0, 1000, 0), Vector3.FORWARD)
	var jet = squadron.jets()[0]
	check(jet.position.y >= 2650.0, "spawn clearance follows local terrain")
	jet.position = Vector3(0, 3000, -3000)
	jet.heading = PI
	var player := Vector3(0, 3000, 0)
	var flight := FLIGHT.new()
	flight.target_handle = jet.id + 1
	var round_data := {"weapon_source": "missile", "flight": flight, "position": player, "velocity": Vector3(0, 0, -500)}
	squadron.update(0.01, player, Vector3.BACK, [round_data])
	check(jet.state != ENEMY.State.EVADE, "another aircraft's missile does not trigger this pilot")
	flight.target_handle = jet.id
	round_data.velocity = Vector3(0, 0, 500)
	squadron.update(0.01, player, Vector3.BACK, [round_data])
	check(jet.state != ENEMY.State.EVADE, "a receding missile does not trigger a break")
	round_data.velocity = Vector3(0, 0, -500)
	squadron.update(0.01, player, Vector3.BACK, [round_data])
	check(jet.state == ENEMY.State.EVADE, "a closing targeted missile triggers evasion beyond the gun cone")
	jet.manoeuvre = ENEMY.Manoeuvre.CLIMB
	squadron.update(0.1, player, Vector3.BACK, [round_data])
	check(jet.velocity.y > 0.0, "climbing breaks add vertical separation")
	jet.manoeuvre = ENEMY.Manoeuvre.BREAK
	for frame in 120:
		squadron.update(1.0 / 60.0, Vector3.ZERO, Vector3.BACK, [round_data])
	check(jet.position.y >= 2650.0, "evasion respects terrain clearance")
	squadron.free()

func _pursues_the_players_actual_tail() -> void:
	var jet := ENEMY.new()
	jet.position = Vector3(0, 1200, -2000)
	jet.heading = PI
	jet.update(0.1, Vector3(0, 1200, 0), Vector3.RIGHT)
	check(jet.nose().x < 0.0, "a right-facing player's six is to the left, independent of approach bearing")

func _intercept_evader(manoeuvre: int, seeker: int, dt: float) -> void:
	var squadron := SQUADRON.new()
	root.add_child(squadron)
	var player := Vector3(0, 3000, 0)
	squadron.spawn(1, player)
	var jet = squadron.jets()[0]
	jet.configure(427)
	jet.position = Vector3(0, 3000, -1200)
	jet.heading = 0.0
	jet.manoeuvre = manoeuvre
	var tracker := TRACKER.new()
	tracker.update(squadron.contacts(), player, Vector3.FORWARD, Vector3.ZERO)
	tracker.select_contact(jet.id)
	var manager := MANAGER.new()
	root.add_child(manager)
	manager.set_physics_process(false)
	manager.hit_query = QUERY.new()
	manager.hit_query.additional_entity_indices.append(squadron)
	manager.projectile_impacted.connect(func(hit, _round):
		squadron.destroy_jet(hit.object_id)
		tracker.remove_contact(hit.object_id)
	)
	var flight := FLIGHT.new()
	flight.seeker = seeker
	flight.target_handle = jet.id
	flight.target_provider = tracker.contact_for
	flight.radar_lock_provider = tracker.locked_handle
	var round_data: RefCounted = manager.acquire_round()
	round_data.initialise(1, player, Vector3.FORWARD, flight.launch_velocity(Vector3.FORWARD, Vector3(0, 0, -200)), false, null, "missile")
	round_data.flight = flight
	manager.spawn(round_data)
	var evaded := false
	for frame in int(20.0 / dt):
		squadron.update(dt, player, Vector3.BACK, manager.active_rounds)
		evaded = evaded or jet.state == ENEMY.State.EVADE
		tracker.update(squadron.contacts(), player, Vector3.FORWARD, Vector3.ZERO)
		manager.step(dt)
		if squadron.jet_count() == 0 or manager.active_rounds.is_empty():
			break
	check(evaded, "a live guided missile must provoke an evasive manoeuvre")
	check(squadron.kills == 1, "a good missile shot can defeat manoeuvre %d with seeker %d at dt %.4f" % [manoeuvre, seeker, dt])
	check(tracker.locked().is_empty(), "a missile kill clears the target lock")
	manager.free()
	squadron.free()

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
