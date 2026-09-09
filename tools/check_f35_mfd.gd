extends SceneTree
const JET = preload("res://scripts/jet/jet_controller.gd")
const AIRFRAME = preload("res://scripts/jet/airframe.gd")
const TRACKER = preload("res://scripts/targeting/target_tracker.gd")
func _init(): call_deferred("run")
func run():
	var telemetry = root.get_node_or_null("Telemetry")
	if telemetry: telemetry.free()
	root.size = Vector2i(960, 540)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.48, 0.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	stage.add_child(sun)
	var jet = JET.new()
	jet.airframe = AIRFRAME.lightning()
	var model = load(jet.airframe.scene_path).instantiate()
	model.name = "HeroJet"
	jet.add_child(model)
	stage.add_child(jet)
	jet.set_physics_process(false)
	await process_frame
	var camera := Camera3D.new()
	camera.near = 0.03
	camera.fov = 78
	stage.add_child(camera)
	var seat: Transform3D = jet.get_cockpit_transform()
	camera.global_position = seat.origin
	camera.look_at(seat.origin + seat.basis.x, seat.basis.y)
	var display = jet.cockpit_mfd
	var contacts := [
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(4000, 0, -2000), Vector3.ZERO, "BANDIT"),
		TRACKER.contact(2, TRACKER.Kind.GROUND_LAUNCHER, Vector3(-1000, 0, 3000), Vector3.ZERO, "SAM"),
		TRACKER.contact(3, TRACKER.Kind.BUILDING, Vector3(2000, 0, 1500), Vector3.ZERO, "CITY")]
	# A repeatable terrain fixture keeps this visual check independent of HTTP.
	var height := Image.create(64, 64, false, Image.FORMAT_RF)
	for y in 64:
		for x in 64:
			var h := maxf(0, sin(float(x) / 12) * cos(float(y) / 9) * 0.5 + 0.25)
			height.set_pixel(x, y, Color(h, h, h))
	display.set_layers({"height": height, "world_size_m": 18000, "metadata": {"elevation_min_m": 0, "elevation_max_m": 1200}})
	display.set_active(true)
	for variant in ["day", "night", "east"]:
		if variant != "day":
			env.environment.background_color = Color(0.012, 0.022, 0.045)
			env.environment.ambient_light_energy = 0.05
			sun.light_energy = 0.02
		display.set_state(Vector3.ZERO, PI * 0.5 if variant == "east" else 0.0, contacts, 1, 10000)
		display.scope._sweep = 0.14
		display.scope.set_process(false)
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/f35-mfd-%s.png" % variant)
		display.viewport.get_texture().get_image().save_png("/tmp/f35-scope-%s.png" % variant)
	print("F35_MFD_RENDER_DONE")
	stage.free()
	quit()
