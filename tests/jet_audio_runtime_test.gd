extends SceneTree
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.set_script(load("res://tests/fixtures/startup_main.gd"))
	root.add_child(main)
	await process_frame
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var original_level: float = main._jet_audio.level
	main._jet_audio.set_volume(0.7, false)
	main._update_jet_audio(1.0)
	check(main._jet_audio.player.playing, "production startup connects the flying jet to engine playback")
	main.jet_anchor._thrust_setting = 0.2
	main._update_jet_audio(2.0)
	var low: float = main._jet_audio.player.pitch_scale
	main.jet_anchor._thrust_setting = 1.0
	main._update_jet_audio(2.0)
	check(main._jet_audio.player.pitch_scale > low + 0.2, "production audio reads actual spooled engine power")
	main._flying_jet = false
	main._update_jet_audio(3.0)
	check(not main._jet_audio.player.playing, "switching to the helicopter removes jet engine audio")
	main._flying_jet = true
	main.jet_anchor._crashed = true
	main._update_jet_audio(1.0)
	check(not main._jet_audio.player.playing, "a crashed jet cannot restart its engine loop")
	main.jet_anchor._crashed = false
	main._update_jet_audio(1.0)
	main._projectile_camera.watching = true
	main._update_jet_audio(3.0)
	check(not main._jet_audio.player.playing, "production missile view silences the remote aircraft engine")
	main._projectile_camera.watching = false
	# Exercise the real settings button and restore the prior user preference.
	main.settings_panel._engine_volume_button.pressed.emit()
	check(main._jet_audio.level == 1.0 and main.settings_panel._engine_volume_button.text == "ENGINE SOUND: 100%", "the settings button changes the volume and label")
	main.settings_panel._engine_volume_button.pressed.emit()
	main._update_jet_audio(1.0)
	check(main._jet_audio.level == 0.0 and not main._jet_audio.player.playing, "the settings button can mute the engine")
	main._jet_audio.set_volume(original_level)
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
		print("JET_AUDIO_RUNTIME_TEST_PASS")
	quit(1 if failed else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
