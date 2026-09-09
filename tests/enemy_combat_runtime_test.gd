extends SceneTree
var failed := false
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.set_script(load("res://tests/fixtures/startup_main.gd"))
	root.add_child(main)
	# Engine-loop playback is covered by jet_audio_runtime_test.
	main._jet_audio.set_volume(0.0, false)
	await process_frame
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main._camera_follow_enabled = true
	main.jet_anchor.position = Vector3(0, 1000, 0)
	main.jet_anchor.velocity = Vector3.ZERO
	main.enemy_squadron.spawn(1, main.jet_anchor.position)
	var jet = main.enemy_squadron.jets()[0]
	jet.position = Vector3(0, 1000, -2400)
	jet.heading = PI
	jet.velocity = Vector3.BACK * 300
	jet.state = main.enemy_squadron.ENEMY.State.PURSUIT
	main._enemy_combat.world_query = null
	main._enemy_combat.grace_remaining = 0.0
	for i in 270: main._update_enemy_combat(1.0 / 60)
	check(main._enemy_combat.projectiles.active_rounds.size() == 1, "production enemies fire at the player")
	check(main._threat_warning.state.incoming == 1, "production warning receives missile proximity")
	check(main._enemy_combat.projectiles != main.projectile_manager, "hostile rounds have separate ownership")
	check(not main._projectile_camera.watching, "enemy launch cannot steal weapon camera")
	check(main._threat_warning._audio.playing, "active threat plays lock warning audio")
	var round_data: RefCounted = main._enemy_combat.projectiles.active_rounds[0]
	main.settings_panel.hide()
	main._update_targeting(0, main.jet_anchor, main.jet_anchor.global_basis.x, 0)
	main._tracker.select_contact(jet.id)
	var before_velocity: Vector3 = main.jet_anchor.velocity
	main._on_gamepad_action_pressed(&"camera_travel_toggle")
	check(main._threat_camera.watching and main._threat_camera.sequence == round_data.sequence and main._threat_camera.camera.current, "R3 looks at the closest incoming missile from the aircraft")
	check(main.jet_anchor.velocity == before_velocity, "incoming view does not change flight controls")
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	tap.position = Vector2(480, 270)
	main._unhandled_input(tap)
	check(main._tracker.locked_handle() == jet.id, "incoming view and screen taps preserve the existing weapon target")
	main._countermeasures_button.pressed.emit()
	check(main._countermeasures.charges == 7 and main._countermeasures.decoys.size() == 6, "on-screen countermeasures button deploys a real salvo during incoming view")
	main._on_gamepad_action_pressed(&"camera_travel_toggle")
	check(not main._threat_camera.watching and main.camera.current, "next R3 returns after cycling the single incoming missile")
	main.jet_anchor.velocity = Vector3(0, 0, -220)
	var hit: RefCounted = main.WORLD_HIT.new()
	hit.hit = true
	hit.object_type = main.WORLD_HIT.ObjectKind.ENTITY
	hit.object_id = main.ENEMY_COMBAT.PLAYER_ID
	hit.position = main.jet_anchor.position
	main._enemy_combat._impact(hit, round_data)
	check(main.jet_anchor.combat_hull == 75 and main.enemy_squadron.kills == 0, "missile damages player without awarding a hostile kill")
	main._on_hostile_missile_hit(hit.position)
	main._on_hostile_missile_hit(hit.position)
	check(not main.jet_anchor.is_crashed(), "three hits leave the aircraft flyable")
	main._on_hostile_missile_hit(hit.position)
	check(main.jet_anchor.is_crashed(), "fourth hit triggers recovery")
	check(main._threat_camera.wreck_view and main._threat_camera.camera.current and not main.jet_anchor.velocity.is_zero_approx(), "fatal hit shows a moving wreck from an external camera instead of a frozen cockpit")
	main._on_gamepad_action_pressed(&"camera_travel_toggle")
	check(main._threat_camera.camera.current, "R3 cannot interrupt the destruction view with a static cockpit")
	check(main._threat_warning._hit_flash > 0 and main._wreck_fire._sites.size() == 1, "hit flash and sustained aircraft fire make damage visible")
	var before_fall: Vector3 = main.jet_anchor.global_position
	main.jet_anchor._physics_process(0.2)
	check(main.jet_anchor.global_position.distance_to(before_fall) > 10, "destroyed aircraft continues falling during the explosion view")
	main._update_enemy_combat(0.1)
	check(main._enemy_combat.projectiles.active_rounds.is_empty(), "aircraft loss clears live threats")
	main.jet_anchor._respawn()
	check(main.jet_anchor.combat_hull == 100 and not main.jet_anchor.is_crashed(), "recovery restores combat hull")
	check(not main._threat_camera.watching and main._enemy_combat.grace_remaining >= 20 and main._countermeasures.charges == 8, "recovery returns aircraft view, countermeasures and a fresh grace period")
	var bomb = load("res://scripts/weapons/cannon_round.gd").new()
	bomb.weapon_source = "bomb"
	hit.object_type = main.WORLD_HIT.ObjectKind.TERRAIN
	hit.position = Vector3(0, 0, 0)
	main._on_projectile_impacted(hit, bomb)
	check(main._strike_fire._sites.size() == 1, "unguided bomb strikes leave a sustained ground fire")
	bomb.weapon_source = "guided_bomb"
	hit.object_type = main.WORLD_HIT.ObjectKind.BUILDING
	hit.position = Vector3(100, 50, 0)
	main._on_projectile_impacted(hit, bomb)
	check(main._strike_fire._sites.size() == 2 and main._strike_fire._sites[1].building, "guided building strike creates the larger plume")
	hit.object_type = main.WORLD_HIT.ObjectKind.WATER
	hit.position = Vector3(200, 0, 0)
	main._on_projectile_impacted(hit, bomb)
	check(main._strike_fire._sites.size() == 2, "water impacts do not create ground fires")
	for weapon in ["missile", "rocket"]:
		bomb.weapon_source = weapon
		hit.object_type = main.WORLD_HIT.ObjectKind.TERRAIN
		hit.position.x += 100.0
		main._on_projectile_impacted(hit, bomb)
	check(main._strike_fire._sites.size() == 4, "missile and rocket surface impacts share the sustained fire pool")
	hit.position.x += 100.0
	main._enemy_combat._impact(hit, bomb)
	check(main._strike_fire._sites.size() == 5, "hostile missile surface strikes also sustain smoke and flames")
	hit.object_type = main.WORLD_HIT.ObjectKind.BUILDING
	hit.position.x += 100.0
	hit.building_id = 991
	main._building_damage._accumulated[991] = main._building_damage.SMOKE_THRESHOLD
	bomb.weapon_source = "cannon"
	main._on_projectile_impacted(hit, bomb)
	check(main._strike_fire._sites.size() == 6 and main._strike_fire._sites[5].building, "severely damaged buildings burn even after cannon hits")
	Engine.time_scale = 1.0
	# Drain the dummy audio driver's pending playback before scene teardown.
	main._jet_audio.player.process_mode = Node.PROCESS_MODE_ALWAYS
	main._jet_audio.player.stream_paused = false
	main._jet_audio.player.stop()
	main._threat_warning._audio.process_mode = Node.PROCESS_MODE_ALWAYS
	main._threat_warning._audio.stream_paused = false
	main._threat_warning._audio.stop()
	await create_timer(0.3, true, false, true).timeout
	main.free()
	if not failed: print("ENEMY_COMBAT_RUNTIME_TEST_PASS")
	quit(1 if failed else 0)
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
