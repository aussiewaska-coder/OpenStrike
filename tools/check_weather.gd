extends SceneTree

## Production weather at cloud crossings. Run with Compatibility, not headless:
## godot --path . --script tools/check_weather.gd -- --out=/tmp/openstrike-weather
const STAGE := preload("res://tests/fixtures/weather_stage.gd")
const STATE := preload("res://scripts/world/weather_state.gd")
var output := "/tmp/openstrike-weather"
var width := 800
var only_scenario := ""
var jitter_strength := 1.0
var reference_shader := ""
var render_scale := 1.0
var sunrise := false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--sunrise":
			sunrise = true
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		if arg.begins_with("--width="):
			width = maxi(160, int(arg.trim_prefix("--width=")))
		if arg.begins_with("--scenario="):
			only_scenario = arg.trim_prefix("--scenario=")
		if arg.begins_with("--jitter="):
			jitter_strength = float(arg.trim_prefix("--jitter="))
		if arg.begins_with("--reference-shader="):
			reference_shader = arg.trim_prefix("--reference-shader=")
		if arg.begins_with("--scale="):
			render_scale = clampf(float(arg.trim_prefix("--scale=")), 0.5, 1.0)
	call_deferred("_run")

func _run() -> void:
	root.scaling_3d_scale = render_scale
	root.size = Vector2i(width, roundi(width * 9.0 / 16.0))
	root.content_scale_size = Vector2i(width, roundi(width * 9.0 / 16.0))
	var stage := STAGE.new()
	root.add_child(stage)
	stage.weather.audio.set_volume(0.0, false)
	if not reference_shader.is_empty():
		var shader := Shader.new()
		shader.code = FileAccess.get_file_as_string(reference_shader)
		stage.clouds.material_override.shader = shader
	stage.clouds.material_override.set_shader_parameter("jitter_strength", jitter_strength)
	if stage.weather._noise_image == null:
		await stage.weather.CLOUD_NOISE.changed
	var origin := Vector2.ZERO
	var best := 0.0
	for x in 20:
		for y in 20:
			var at := Vector2(x * 300, y * 300)
			var density := STATE.cloud_density(stage.weather._noise_image, at, Vector2.ZERO, 1.0)
			if density > best:
				best = density
				origin = at
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(70000, 70000)
	ground.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain_imagery.gdshader")
	ground.material_override = material
	stage.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for index in 45:
		var building := MeshInstance3D.new()
		var box := BoxMesh.new()
		var height := rng.randf_range(80, 380)
		box.size = Vector3(rng.randf_range(45, 100), height, rng.randf_range(45, 100))
		building.mesh = box
		building.position = Vector3(origin.x + rng.randf_range(-2800, 2800), height * 0.5, origin.y - rng.randf_range(800, 8000))
		var facade := StandardMaterial3D.new()
		facade.albedo_color = Color(0.48, 0.54, 0.57)
		building.material_override = facade
		stage.add_child(building)
	for scenario in [
		{"name": "layers-clear", "preset": STATE.Preset.CLEAR, "altitude": 3000.0, "pitch": 0.22},
		{"name": "layers-storm", "preset": STATE.Preset.STORM, "altitude": 4600.0, "pitch": -0.12},
		{"name": "clear-below", "preset": STATE.Preset.CLEAR, "altitude": 800.0, "pitch": 0.12},
		{"name": "clear-base", "preset": STATE.Preset.CLEAR, "altitude": 1500.0, "pitch": 0.12},
		{"name": "clear-above", "preset": STATE.Preset.CLEAR, "altitude": 2700.0, "pitch": -0.22},
		{"name": "storm-below", "preset": STATE.Preset.STORM, "altitude": 800.0, "pitch": 0.12},
		{"name": "storm-inside", "preset": STATE.Preset.STORM, "altitude": 1800.0, "pitch": -0.05},
		{"name": "storm-above", "preset": STATE.Preset.STORM, "altitude": 2700.0, "pitch": -0.22},
		{"name": "night-lightning", "preset": STATE.Preset.STORM, "altitude": 800.0, "pitch": 0.12},
	]:
		if not only_scenario.is_empty() and scenario.name != only_scenario:
			continue
		stage.weather.set_preset(scenario.preset)
		stage.weather.current = STATE.target(scenario.preset)
		stage.camera.position = Vector3(origin.x, scenario.altitude, origin.y)
		stage.camera.look_at(stage.camera.position + Vector3(0, scenario.pitch, -1) * 10000)
		stage.day.mode = stage.day.Mode.NIGHT if scenario.name == "night-lightning" else stage.day.Mode.NOON
		if sunrise and scenario.name != "night-lightning":
			stage.day.mode = stage.day.Mode.SUNRISE
		stage.day.refresh()
		stage.weather._apply(1.0)
		stage.clouds._process(0.0)
		if scenario.name == "night-lightning":
			stage.weather._begin_lightning(1200.0)
			stage.weather._lightning(0.02)
		stage.weather._rain.preprocess = 1.4
		stage.weather._rain.restart()
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		assert(screenshot != null and not screenshot.is_empty())
		assert(screenshot.save_png("%s-%s.png" % [output, scenario.name]) == OK)
		print("WEATHER_RENDER ", scenario.name, " rain=", stage.weather.rain_intensity, " immersion=", stage.weather.cloud_immersion, " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	stage.free()
	print("WEATHER_RENDER_DONE")
	quit()
