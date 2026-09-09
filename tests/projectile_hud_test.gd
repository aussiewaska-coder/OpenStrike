extends SceneTree
const HUD := preload("res://scripts/ui/projectile_hud.gd")
const VIEW := preload("res://scripts/camera/projectile_camera.gd")
const ROUND := preload("res://scripts/weapons/cannon_round.gd")
const AIR := preload("res://scripts/weapons/missile_flight.gd")
const GROUND := preload("res://scripts/weapons/guided_ground_flight.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
var selected := 7
var alive := true
var target_point := Vector3(350, 1000, -3000)
var failed := false

func _init() -> void:
	call_deferred("_run")

func _contact(_handle: int) -> Dictionary:
	return TRACKER.contact(7, TRACKER.Kind.AIR_JET, target_point, Vector3(100, 0, 0), "BANDIT 1") if alive else {}

func _run() -> void:
	root.size = Vector2i(960, 540)
	var view := VIEW.new()
	root.add_child(view)
	var hud := HUD.new()
	root.add_child(hud)
	var round_data := ROUND.new()
	round_data.initialise(1, Vector3(0, 1000, 0), Vector3.FORWARD, Vector3(0, 0, -250), false, null, "missile")
	var air := AIR.new()
	air.seeker = AIR.Seeker.RADAR
	air.target_handle = 7
	air.target_provider = _contact
	air.radar_lock_provider = func(): return selected
	round_data.flight = air
	view.enabled = true
	view.on_launch(round_data)
	hud.set_state(view.camera, view.tracking_state())
	check(hud.visible and hud.status_text() == "RADAR MISSILE  •  LOCKED", "the banner identifies the watched weapon and live seeker lock")
	var missile_marker: Dictionary = hud.marker(round_data.position)
	check(not missile_marker.edge and missile_marker.position.distance_to(view.camera.unproject_position(round_data.position)) < 0.01, "missile reticle is projected using the active weapon camera")
	check(not hud.marker(target_point).edge, "a target ahead is kept in view")
	selected = 8
	view.update(1.0 / 60.0, [round_data])
	hud.set_state(view.camera, view.tracking_state())
	check(hud.status_text() == "RADAR MISSILE  •  LOCK LOST" and not view.tracking_state().locked, "changing radar target immediately removes the lock indication")
	air.seeker = AIR.Seeker.HEAT
	view.update(1.0 / 60.0, [round_data])
	check(view.tracking_state().locked, "heat seekers retain their independent target")
	alive = false
	view.update(1.0 / 60.0, [round_data])
	check(view.tracking_state().status == "TARGET LOST" and view.tracking_state().target_position == null, "destroyed targets remove the target reticle and lock")
	var ground := GROUND.new()
	ground.target_position = Vector3(500, 2, -2200)
	ground.target_name = "CITY CENTRAL 1"
	round_data.flight = ground
	view.update(1.0 / 60.0, [round_data])
	hud.set_state(view.camera, view.tracking_state())
	check(hud.status_text() == "GUIDED BOMB  •  COORDINATE LOCK" and view.tracking_state().target_name == "CITY CENTRAL 1", "bombs describe coordinate guidance even after aircraft selection changes")
	ground.powered = true
	view.update(1.0 / 60.0, [round_data])
	check(view.tracking_state().weapon == "GROUND MISSILE", "ground missiles have their own weapon label")
	for point in [Vector3(10000, 1000, 0), Vector3(0, 1000, 10000), Vector3(0, 20000, -100)]:
		var m: Dictionary = hud.marker(point)
		check(m.edge and Rect2(Vector2.ZERO, hud.size).has_point(m.position), "offscreen and rear targets get an onscreen direction cue")
	view.finish(1, ground.target_position, true)
	hud.set_state(view.camera, view.tracking_state())
	check(hud.status_text() == "GROUND MISSILE  •  IMPACT" and view.tracking_state().projectile_position == null, "impact removes the missile reticle and reports impact")
	view.update(1.0, [])
	hud.set_state(view.camera, view.tracking_state())
	check(not hud.visible, "weapon HUD clears when the camera returns")
	# Follow a crossing target at two frame rates, including the terminal turn.
	for dt in [1.0 / 60.0, 1.0 / 120.0]:
		alive = true
		selected = 7
		target_point = Vector3(350, 1000, -3000)
		air = AIR.new()
		air.target_handle = 7
		air.target_provider = _contact
		round_data.flight = air
		round_data.position = Vector3(0, 1000, 0)
		round_data.previous_position = round_data.position
		round_data.velocity = Vector3(0, 0, -250)
		view.on_launch(round_data)
		var age := 0.0
		var visible_frames := 0
		var total_frames := 0
		var max_rotation := 0.0
		while age < 12.0:
			target_point += Vector3(100, 0, 0) * dt
			var step: Array = air.advance(round_data.position, round_data.velocity, dt, age)
			if air.proximity_hit(round_data.position, step[0], age) != null:
				break
			round_data.position = step[0]
			round_data.previous_position = step[0]
			round_data.velocity = step[1]
			var before := view.camera.global_basis.get_rotation_quaternion()
			view.update(dt, [round_data])
			hud.set_state(view.camera, view.tracking_state())
			max_rotation = maxf(max_rotation, before.angle_to(view.camera.global_basis.get_rotation_quaternion()))
			if not hud.marker(target_point).edge and not hud.marker(round_data.position).edge:
				visible_frames += 1
			total_frames += 1
			age += dt
		print("CAMERA_CONTEXT dt=%.4f visible=%d/%d rotation=%.3f" % [dt, visible_frames, total_frames, rad_to_deg(max_rotation)])
		check(visible_frames == total_frames, "target-aware panning keeps the missile and crossing target onscreen throughout pursuit")
		check(max_rotation <= 1.6 * dt + 0.002, "camera pan stays within its angular speed limit")
		view.stop()
	hud.free()
	view.free()
	if not failed:
		print("PROJECTILE_HUD_TEST_PASS")
	quit(1 if failed else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
