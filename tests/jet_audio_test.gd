extends SceneTree
const AUDIO := preload("res://scripts/audio/jet_audio.gd")
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var buses := AudioServer.bus_count
	var sound := AUDIO.new()
	root.add_child(sound)
	sound.set_volume(0.7, false)
	check(sound.player.stream.get_length() > 23.9 and sound.player.stream.loop, "the supplied recording loads as a repeating 24-second engine loop")
	sound.update_state(1.0, true, 0.0, 0.0, false, false)
	check(sound.player.playing and sound.player.volume_db > -40.0, "a live engine is audible at idle")
	var idle_pitch: float = sound.player.pitch_scale
	var idle_volume: float = sound.player.volume_db
	sound.update_state(1.0 / 60.0, true, 1.0, 1.0, false, false)
	check(sound.player.pitch_scale > idle_pitch and sound.player.pitch_scale < idle_pitch + 0.04, "a power change raises pitch smoothly")
	for frame in 180:
		sound.update_state(1.0 / 60.0, true, 1.0, 1.0, false, false)
	check(sound.player.pitch_scale > 1.15 and sound.player.volume_db > idle_volume + 12.0, "full power and afterburner produce a stronger engine sound")
	var exterior_volume: float = sound.player.volume_db
	for frame in 120:
		sound.update_state(1.0 / 60.0, true, 1.0, 1.0, true, false)
	check(sound._filter.cutoff_hz < 4000 and sound.player.volume_db < exterior_volume - 3.0, "cockpit audio is filtered and quieter")
	paused = true
	check(sound.player.stream_paused, "pausing flight also pauses engine playback")
	paused = false
	check(not sound.player.stream_paused, "resuming flight restores engine playback")
	sound.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	sound.update_state(0.1, true, 0.7, 0.0, false, false)
	check(sound.player.stream_paused, "Android backgrounding silences engine playback")
	sound.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not sound.player.stream_paused, "foregrounding resumes playback when flight is active")
	for frame in 120:
		sound.update_state(1.0 / 60.0, true, 0.7, 0.0, false, true)
	check(not sound.player.playing, "missile view fades out the aircraft engine")
	sound.update_state(0.1, true, 0.7, 0.0, false, false)
	check(sound.player.playing, "returning to aircraft view brings the engine back")
	for frame in 120:
		sound.update_state(1.0 / 60.0, false, 0.0, 0.0, false, false)
	check(not sound.player.playing, "inactive or crashed jets become silent")
	sound.set_volume(0.0, false)
	sound.update_state(1.0, true, 1.0, 1.0, false, false)
	check(not sound.player.playing, "engine-volume OFF remains silent at full power")
	# Scene teardown must also release playback from a paused aircraft bus.
	sound.set_volume(0.7, false)
	sound.update_state(0.1, true, 0.7, 0.0, false, false)
	sound.process_mode = Node.PROCESS_MODE_DISABLED
	sound.player.process_mode = Node.PROCESS_MODE_ALWAYS
	sound.player.stream_paused = false
	sound.player.stop()
	await create_timer(0.3, true, false, true).timeout
	sound.free()
	check(AudioServer.bus_count == buses, "removing the scene releases its audio bus")
	if not failed:
		print("JET_AUDIO_TEST_PASS")
	quit(1 if failed else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
