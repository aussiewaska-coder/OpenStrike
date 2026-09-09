extends SceneTree
func _init(): call_deferred("run")
func run():
	root.size = Vector2i(960, 540)
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.set_script(load("res://tests/fixtures/startup_main.gd"))
	root.add_child(main)
	main._jet_audio.set_volume(0.0, false)
	await process_frame
	await process_frame
	paused = false
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.get_node("UI/ControllerOverlay").hide()
	main.settings_panel.hide()
	main.gamepad_diagnostic.get_parent().hide()
	main._camera_follow_enabled = true
	main.jet_anchor.position = Vector3(0, 1000, 0)
	main.jet_anchor.velocity = Vector3(0, 0, -220)
	main.camera.position = Vector3(55, 1018, 72)
	main.camera.look_at(main.jet_anchor.position + Vector3(0, 0, -160))
	main.camera.make_current()
	main._enemy_combat.world_query = null
	main._update_enemy_combat(0)
	var source: Dictionary = main._enemy_combat._source(200001, false)
	source.position = Vector3(160, 1080, -650)
	source.nose = (main.jet_anchor.position - source.position).normalized()
	source.velocity = source.nose * 220
	source.visible = true
	main._enemy_combat._launch(source)
	main._threat_warning.update_warning(0.01, main._enemy_combat.warning_state(), main.camera, 100)
	main._countermeasures_button.pressed.emit()
	for i in 60: main._countermeasures.update(1.0 / 60)
	for child in main._enemy_combat.get_children():
		if child.get_script() == load("res://scripts/effects/missile_fx.gd"): child._process(0)
	await capture("defence", main)
	main._on_gamepad_action_pressed(&"camera_travel_toggle")
	main._threat_warning.update_warning(0.01, main._enemy_combat.warning_state(), main._threat_camera.camera, 100)
	await capture("incoming-view", main)
	for i in 4: main._on_hostile_missile_hit(main.jet_anchor.position)
	main._threat_warning.update_warning(0.01, {}, main._threat_camera.camera, 0)
	main._update_defensive_view(0)
	for site in main._wreck_fire._sites:
		site.smoke.preprocess = 1.0
		site.fire.preprocess = 0.5
	# Only the actual particles run while aircraft/cameras stay at the test pose.
	main.impact_fx.process_mode = Node.PROCESS_MODE_ALWAYS
	main._wreck_fire.process_mode = Node.PROCESS_MODE_ALWAYS
	await capture("hit-explosion", main)
	main._threat_warning._audio.stop()
	await create_timer(0.3).timeout
	main.free()
	print("DEFENSIVE_COMBAT_RENDER_DONE")
	quit()
func capture(name: String, main: Node3D):
	for frame in 3: await process_frame
	assert(root.get_visible_rect().encloses(main._countermeasures_button.get_global_rect()), "countermeasures button fits the phone viewport")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/openstrike-%s.png" % name)
