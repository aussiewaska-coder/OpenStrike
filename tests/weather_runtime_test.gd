extends SceneTree

const STAGE := preload("res://tests/fixtures/weather_stage.gd")
const STATE := preload("res://scripts/world/weather_state.gd")
var failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := STAGE.new()
	root.add_child(stage)
	if stage.weather._noise_image == null:
		await stage.weather.CLOUD_NOISE.changed
	# Let the audio backend initialize before rapidly exercising play/stop.
	await create_timer(0.5).timeout
	var weather: Node = stage.weather
	weather.audio.set_volume(0.7, false)
	weather.set_preset(STATE.Preset.RAIN)
	weather.current = STATE.target(STATE.Preset.RAIN)
	weather._apply(1.0)
	check(is_equal_approx(weather.rain_intensity, 0.6) and weather._rain.emitting, "rain below clouds uses preset density")
	check(weather.audio.rain_player.playing, "rain is audible below the clouds")
	weather.set_preset(STATE.Preset.STORM)
	weather.current = STATE.target(STATE.Preset.STORM)
	weather._apply(1.0)
	check(weather.rain_intensity == 1.0, "storm rain is denser than ordinary rain")
	var image := Image.create(8, 8, false, Image.FORMAT_RF)
	image.fill(Color.WHITE)
	weather._noise_image = image
	stage.camera.position.y = 1800.0
	weather._apply(0.1)
	stage.clouds._process(0.1)
	check(weather.cloud_immersion == 1.0, "weather still tracks the shared coverage at the camera")
	check(stage.day.cloud_immersion == 0.0, "volumetric extinction replaces uniform cloud fog")
	check(stage.clouds.mesh is QuadMesh and stage.clouds.get_child_count() == 0, "one volume pass replaces cloud slices")
	check(stage.clouds.material_override.get_shader_parameter("march_steps") == 48, "mobile view sample budget is applied")
	check(stage.clouds.material_override.get_shader_parameter("shadow_steps") == 0, "economy clouds use inexpensive height lighting")
	image.fill(Color.BLACK)
	weather._apply(0.1)
	check(weather.cloud_immersion == 0.0 and stage.environment.fog_density < 0.001, "cloud holes restore visibility")
	stage.camera.position.y = 2600.0
	weather._apply(3.0)
	stage.clouds._process(0.1)
	check(weather.rain_intensity == 0.0 and not weather._rain.visible and not weather._rain.emitting, "no lingering rain above cloud tops")
	check(not weather.audio.rain_player.playing, "rain audio fades out above clouds")
	check(is_equal_approx(stage.day.sun_multiplier, 1.0) and is_equal_approx(stage.environment.fog_density, 0.0001), "sunlight and baseline haze return above clouds")
	var remote := Camera3D.new()
	stage.add_child(remote)
	remote.position = Vector3(25000, 600, 0)
	remote.make_current()
	weather._apply(0.016)
	stage.clouds._process(0.016)
	check(weather.rain_intensity == 1.0 and weather._rain.global_position.is_equal_approx(remote.global_position), "precipitation follows the active weapon camera")
	check(weather._camera_velocity == Vector3.ZERO, "camera switches do not create false rain velocity")
	check(is_equal_approx(stage.clouds.global_position.x, remote.global_position.x), "clouds also follow the active camera")
	remote.position.z -= 30.0
	weather._apply(0.1)
	check(weather._rain.direction.z > 0.8, "rain streams past a moving camera")
	var sun_energy := stage.sun.light_energy
	weather._begin_lightning(343.0)
	weather._lightning(0.02)
	check(weather._lightning_light.light_energy > 0.0, "lightning uses its own light")
	check(is_equal_approx(stage.sun.light_energy, sun_energy), "lightning cannot corrupt the day-cycle sun")
	check(not weather.audio.thunder_player.playing, "thunder does not arrive with the flash")
	weather._lightning(0.4)
	check(weather._lightning_light.light_energy == 0.0, "a long frame ends lightning without leaving a stuck flash")
	weather._lightning(0.6)
	check(weather.audio.thunder_player.playing and weather._pending_thunder.is_empty(), "thunder arrives after distance divided by sound speed")
	weather.audio.set_volume(0.0, false)
	check(not weather.audio.rain_player.playing and not weather.audio.thunder_player.playing, "weather mute silences both sounds immediately")
	weather.audio.play_thunder(800.0, 1.0)
	check(not weather.audio.thunder_player.playing, "delayed thunder respects mute")
	weather.audio.set_volume(0.7, false)
	weather.audio.update_rain(1.0, 1.0)
	weather.audio._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(weather.audio.rain_player.stream_paused, "backgrounding the application pauses weather sound")
	weather.audio._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not weather.audio.rain_player.stream_paused, "foregrounding resumes weather sound when flight runs")
	paused = true
	check(not weather.can_process() and not weather.audio.rain_player.can_process(), "flight pause freezes storm timers and audio")
	paused = false
	weather.audio.set_volume(0.0, false)
	stage.free()
	# Allow the audio mixer to release stopped Vorbis playback before exit.
	await create_timer(0.15).timeout
	if not failed:
		print("WEATHER_RUNTIME_TEST_PASS")
	quit(1 if failed else 0)


func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
