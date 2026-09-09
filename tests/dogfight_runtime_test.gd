extends SceneTree

var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.set_script(load("res://tests/fixtures/startup_main.gd"))
	root.add_child(main)
	# Engine-loop playback is covered by jet_audio_runtime_test.
	main._jet_audio.set_volume(0.0, false)
	await process_frame
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var carrier: Node3D = main.jet_anchor
	var nose: Vector3 = carrier.global_basis.x
	var heading := atan2(nose.x, -nose.z)
	main.enemy_squadron.clear()
	main.enemy_squadron._next_encounter_in = 0.0
	main._update_targeting(0.01, carrier, nose, heading)
	check(main.enemy_squadron.jet_count() >= 1 and main.enemy_squadron.jet_count() <= 2, "production targeting starts an enemy encounter")
	var jet = main.enemy_squadron.jets()[0]
	jet.position = carrier.global_position + nose * 1800.0
	main._update_targeting(0.0, carrier, nose, heading)
	check(main._tracker.select_contact(jet.id), "spawned enemies reach the production tracker")
	main._weapons.current = main.WEAPON_SELECTION.Weapon.HEAT
	main._update_rockets(0.5)
	main._update_targeting(0.0, carrier, nose, heading)
	check(main._helmet._seeker.get("ready", false), "production HUD receives acquired missile state")
	main._missile_launcher.update(0.01, true)
	check(main.projectile_manager.active_rounds.size() == 1, "production hardpoints launch a locked missile")
	var round_data: RefCounted = main.projectile_manager.active_rounds[0]
	var hit = main.WORLD_HIT.new()
	hit.hit = true
	hit.object_type = main.WORLD_HIT.ObjectKind.ENTITY
	hit.object_id = jet.id
	hit.position = jet.position
	hit.incident_velocity = round_data.velocity
	main._on_projectile_impacted(hit, round_data)
	check(main.enemy_squadron.kills == 1, "production impact routing awards a jet kill")
	check(main._strike_fire._sites.size() == 1 and main._strike_fire._sites[0].has("wreck_velocity"), "destroyed aircraft leave falling fire and smoke")
	check(main._tracker.contact_for(jet.id).is_empty() and main._tracker.locked().is_empty(), "impact clears the contact and lock immediately")
	main._on_projectile_impacted(hit, round_data)
	check(main.enemy_squadron.kills == 1, "duplicate production impacts cannot award another kill")
	main._update_targeting(0.0, carrier, nose, heading)
	main._update_rockets(0.01)
	check(main._helmet._locked.is_empty() and not main._helmet._seeker.get("ready", false), "destroyed targets clear the rendered lock and fire cue")
	check(main._weapon_label.text.contains("KILLS 1"), "the flight HUD reports the kill count")
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
	if not failed:
		print("DOGFIGHT_RUNTIME_TEST_PASS")
	quit(1 if failed else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
