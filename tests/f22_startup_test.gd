extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.set_script(load("res://tests/fixtures/startup_main.gd"))
	root.add_child(main)
	await process_frame
	await process_frame
	assert(main._flying_jet and main._vehicle() == main.jet_anchor, "startup must select the F-22")
	assert(main.jet_anchor.visible and main.jet_anchor.process_mode != Node.PROCESS_MODE_DISABLED, "startup jet must be visible and active")
	assert(not main.helicopter_anchor.visible and main.helicopter_anchor.process_mode == Node.PROCESS_MODE_DISABLED, "the Apache must be parked at startup")
	assert(main._jet_view == main.JET_CAMERA.Mode.COCKPIT and main._free_look.is_zero_approx(), "startup must use forward FPV")
	assert(main.jet_anchor.airspeed() > 90.0 and main.jet_anchor.global_position.y > 800.0, "startup jet must launch safely at cruise")
	main._update_jet_camera(0.0, true)
	var cockpit: Transform3D = main.jet_anchor.get_interpolated_cockpit_transform()
	assert(main.camera.global_position.distance_to(cockpit.origin) < 0.01, "startup camera must be in the cockpit")
	assert((-main.camera.global_basis.z).dot(cockpit.basis.x) > 0.999, "startup camera must look forward")
	main._toggle_settings()
	assert(paused and main.settings_panel.visible, "production settings wiring must pause flight")
	main.settings_panel.close_panel()
	assert(not paused, "production Resume must unpause flight")
	main.free()
	print("F22_STARTUP_TEST_PASS")
	quit()
