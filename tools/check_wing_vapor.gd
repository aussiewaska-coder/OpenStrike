extends SceneTree
const JET := preload("res://scripts/jet/jet_controller.gd")
const AIRFRAME := preload("res://scripts/jet/airframe.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(960, 540)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.19, 0.32, 0.45)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-35, -45, 0)
	var jet := JET.new()
	jet.airframe = AIRFRAME.lightning()
	var tag := ""
	if "--f117" in OS.get_cmdline_user_args():
		jet.airframe = AIRFRAME.nighthawk()
		tag = "-f117"
	var model: Node3D = load(jet.airframe.scene_path).instantiate()
	model.name = "HeroJet"
	jet.add_child(model)
	root.add_child(jet)
	jet.set_physics_process(false)
	await process_frame
	jet._vapor.set_process(false)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.fov = 48
	camera.position = Vector3(-22, 15, 22)
	camera.look_at(Vector3(-3, 0, 0))
	print("VAPOR_RENDER_TIPS ", jet._vapor.tips)
	jet._vapor.moisture = 1.0
	for state in ["cruise", "high-g", "wake"]:
		jet._vapor.clear()
		jet._vapor.set_flight(220, 7 if state != "cruise" else 1, 0.3)
		var frames := 240 if state == "wake" else 120
		for frame in frames:
			var t := float(frame - frames + 1) / 60.0
			# Finish at origin with old wingtip vapor still behind the aircraft.
			jet.transform = Transform3D(Basis(Vector3.RIGHT, -0.3 * t), Vector3(t * 220, -t * t * 4, t * t * 8))
			jet._vapor.advance(1.0 / 60.0, jet.transform)
		if state == "wake":
			camera.position = Vector3(-100, 42, 90)
			camera.look_at(Vector3(-70, 0, 0))
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/openstrike-vapor-%s%s.png" % [state, tag])
	jet.free()
	camera.free()
	sun.free()
	environment.free()
	print("WING_VAPOR_RENDER_DONE")
	quit()
