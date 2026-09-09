extends SceneTree
const FLIGHT := preload("res://scripts/weapons/missile_flight.gd")
const LAUNCHER := preload("res://scripts/weapons/missile_launcher.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const WEAPONS := preload("res://scripts/weapons/weapon_selection.gd")
const MANAGER := preload("res://scripts/weapons/projectile_manager.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")

var target_position := Vector3(350, 1000, -3000)
var target_velocity := Vector3(100, 0, 0)
var selected := 7
var alive := true
var failed := false

func _init() -> void:
	call_deferred("_run")

func contact_for(handle: int) -> Dictionary:
	return TRACKER.contact(7, TRACKER.Kind.AIR_JET, target_position, target_velocity) if alive and handle == 7 else {}

func _flight(seeker: int) -> RefCounted:
	var flight := FLIGHT.new()
	flight.seeker = seeker
	flight.target_handle = 7
	flight.target_provider = contact_for
	flight.radar_lock_provider = func(): return selected
	return flight

func _run() -> void:
	for seeker in [FLIGHT.Seeker.HEAT, FLIGHT.Seeker.RADAR]:
		for dt in [1.0 / 60.0, 1.0 / 120.0]:
			_intercept(seeker, dt)
	_guidance_loss()
	_loft_and_burnout()
	_launcher_gates_fire()
	_surface_before_fuse()
	if not failed:
		print("MISSILE_TEST_PASS")
	quit(1 if failed else 0)

func _intercept(seeker: int, dt: float) -> void:
	alive = true
	selected = 7
	target_position = Vector3(350, 1000, -3000)
	var flight := _flight(seeker)
	var position := Vector3(0,1000,0)
	var velocity: Vector3 = flight.launch_velocity(Vector3.FORWARD, Vector3(0,0,-175))
	var hit := false
	var age := 0.0
	var closest := INF
	while age < 18.0:
		target_position += target_velocity * dt
		var step: Array = flight.advance(position, velocity, dt, age)
		if flight.proximity_hit(position, step[0], age) != null:
			hit = true
			break
		position = step[0]
		velocity = step[1]
		closest = minf(closest, position.distance_to(target_position))
		check(position.is_finite() and velocity.is_finite(), "flight must stay finite")
		age += dt
	print("MISSILE intercept seeker=%d dt=%.4f age=%.2f miss=%.1f" % [seeker, dt, age, closest])
	check(hit, "both seekers must intercept a crossing target through a bounded curved path")

func _guidance_loss() -> void:
	target_position = Vector3(0,1000,-3000)
	selected = 8
	for seeker in [FLIGHT.Seeker.HEAT, FLIGHT.Seeker.RADAR]:
		var flight := _flight(seeker)
		for frame in range(60):
			flight.advance(Vector3(0,1000,0), Vector3(0,0,-300), 1.0/60, 1.0)
		check(flight._guidance_lost == (seeker == FLIGHT.Seeker.RADAR), "only radar missiles depend on the aircraft retaining their target lock")
	selected = 7
	alive = false
	var lost := _flight(FLIGHT.Seeker.HEAT)
	for frame in range(60):
		lost.advance(Vector3(0,1000,0), Vector3(0,0,-300), 1.0/60, 1.0)
	check(lost._guidance_lost and lost.proximity_hit(Vector3.ZERO, Vector3.FORWARD, 2.0) == null, "a destroyed target must not remain a ghost fuse")
	alive = true

func _loft_and_burnout() -> void:
	target_position = Vector3(0,1000,-6000)
	target_velocity = Vector3.ZERO
	selected = 7
	var altitudes := []
	for seeker in [FLIGHT.Seeker.HEAT, FLIGHT.Seeker.RADAR]:
		var flight := _flight(seeker)
		var point := Vector3(0,1000,0)
		var velocity := Vector3(0,0,-200)
		for frame in range(180):
			var step: Array = flight.advance(point, velocity, 1.0/60.0, frame/60.0)
			point = step[0]
			velocity = step[1]
		altitudes.append(point.y)
		check(not flight.is_boosting(0.1) and flight.is_boosting(1.0) and not flight.is_boosting(7.0), "motor must ignite after separation and stop at burnout")
	check(altitudes[1] > altitudes[0] + 60.0, "long radar shots must visibly loft above direct heat-seeker pursuit")
	target_velocity = Vector3(100,0,0)

func _launcher_gates_fire() -> void:
	var tracker := TRACKER.new()
	tracker.update([contact_for(7)], Vector3(0,1000,0), Vector3.FORWARD, Vector3.ZERO)
	var manager := MANAGER.new()
	root.add_child(manager)
	manager.set_physics_process(false)
	var carrier := Node3D.new()
	root.add_child(carrier)
	carrier.position = Vector3(0,1000,0)
	carrier.basis = Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT)
	var hardpoint := Node3D.new()
	carrier.add_child(hardpoint)
	var launcher := LAUNCHER.new()
	root.add_child(launcher)
	launcher.carrier = carrier
	launcher.projectile_manager = manager
	launcher.hardpoints = [hardpoint]
	launcher.tracker = tracker
	launcher.selection = WEAPONS.new()
	launcher.selection.current = WEAPONS.Weapon.HEAT
	launcher.update(1.0, true)
	check(manager.active_rounds.is_empty(), "no lock must mean no missile launch")
	tracker.lock_at(carrier.position, Vector3.FORWARD, null, TRACKER.Kind.GROUND_POINT, "")
	launcher.update(0.1, false)
	check(not launcher.seeker_state().ready and launcher.seeker_state().progress > 0.0, "the reticle shows acquisition without authorizing a shot")
	launcher.update(0.01, true)
	check(manager.active_rounds.is_empty(), "seeker acquisition must precede firing")
	launcher.update(1.0, false)
	check(launcher.seeker_state().ready, "completed acquisition authorizes the HUD fire cue")
	launcher.update(0.01, true)
	check(manager.active_rounds.size() == 1, "an acquired target and fresh press must launch")
	check(not launcher.seeker_state().ready and launcher.status == "COOLDOWN", "firing removes the ready cue during cooldown")
	launcher.update(2.0, true)
	check(manager.active_rounds.size() == 1, "holding L1 must not dump the magazine")
	for shot in 3:
		launcher.update(0.7, false)
		launcher.update(0.01, true)
	check(launcher.remaining == 0 and not launcher.seeker_state().ready and launcher.status == "RELOADING", "empty magazines cannot display FIRE")
	launcher.update(LAUNCHER.RELOAD_SECONDS + 0.1, false)
	launcher.update(0.01, false)
	check(launcher.remaining == LAUNCHER.CAPACITY and launcher.seeker_state().ready, "reloading restores missile availability")
	tracker.clear_lock()
	check(not launcher.seeker_state().ready, "a retired target immediately removes the FIRE cue")
	launcher.update(0.01, false)
	check(launcher.seeker_state().progress == 0.0, "lost contacts clear the acquisition ring")
	launcher.free()
	carrier.free()
	manager.free()

class Wall:
	extends RefCounted
	func query_segment(from: Vector3, to: Vector3) -> RefCounted:
		var hit := HIT.new()
		hit.hit = true
		hit.t = 0.1
		hit.position = from.lerp(to, 0.1)
		hit.object_type = HIT.ObjectKind.BUILDING
		return hit

func _surface_before_fuse() -> void:
	var manager := MANAGER.new()
	root.add_child(manager)
	manager.set_physics_process(false)
	manager.hit_query = Wall.new()
	var round_data: RefCounted = manager.acquire_round()
	round_data.initialise(1, Vector3(0,1000,0), Vector3.FORWARD, Vector3(0,0,-300), false, null, "missile")
	round_data.flight = _flight(FLIGHT.Seeker.HEAT)
	round_data.age = 1.0
	target_position = Vector3(0,1000,-2)
	var kinds := []
	manager.projectile_impacted.connect(func(hit, _round): kinds.append(hit.object_type))
	manager.spawn(round_data)
	manager.step(0.02)
	check(kinds.size() == 1 and kinds[0] == HIT.ObjectKind.BUILDING, "a nearer wall must stop a missile before target proximity")
	manager.free()

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
