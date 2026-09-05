extends SceneTree
const JET := preload("res://scripts/jet/jet_controller.gd")
const MODEL := preload("res://3dassets/f-22_raptor_-_fighter_jet_-_free.glb")
func _init(): call_deferred("_run")
func _run():
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--visual-out="): output = arg.trim_prefix("--visual-out=")
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.07,0.09,0.13)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.65,0.73,0.9)
	world.environment.ambient_light_energy = 0.7
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-30,0)
	sun.light_energy = 1.6
	stage.add_child(sun)
	var jet := JET.new()
	var model: Node3D = MODEL.instantiate()
	model.name = "HeroJet"
	jet.add_child(model)
	stage.add_child(jet)
	jet.set_physics_process(false)
	await process_frame
	assert(jet._effects != null and jet._effects.ailerons.size() == 2)
	for plume in jet._effects.plumes: assert(not plume.visible, "military power must not show afterburner")
	var rest := jet._visual.transform
	jet.roll_input = 1.0
	jet._thrust_setting = 1.35
	for frame in range(60): jet._update_visual(1.0/60.0)
	assert(jet._visual.transform == rest, "effects must not jitter the physical airframe")
	for panel in jet._effects.ailerons:
		assert(panel.basis != panel.get_meta("rest"), "both ailerons must move")
	assert((jet._effects.ailerons[0].basis * Vector3.LEFT).z > 0.0, "right roll lowers left aileron")
	assert((jet._effects.ailerons[1].basis * Vector3.LEFT).z < 0.0, "right roll raises right aileron")
	for plume in jet._effects.plumes:
		assert(plume.visible and plume.position.x < -3.65, "burner extends rearward")
	for light in jet._effects.lights: assert(light.light_energy > 0.0)
	for frame in range(1000):
		assert(jet.EFFECTS.cockpit_vibration(frame / 60.0, 1.0, 1.0).length() < 0.15, "cockpit vibration stays subtle")
	if output != "" and DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		stage.add_child(camera)
		camera.position = Vector3(-18,14,18)
		camera.fov = 48
		camera.look_at(Vector3(1.5,0,0))
		camera.current = true
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(output + "-burner.png") == OK)
		print("VISUAL_SAVED ", output + "-burner.png")
		jet.airbrake = 1.0
		jet.roll_input = 0.0
		jet._thrust_setting = 0.8
		for frame in range(60): jet._update_visual(1.0/60.0)
		camera.position = Vector3(0,27,0.01)
		camera.look_at(Vector3(3,0,0), Vector3.RIGHT)
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(output + "-brake.png") == OK)
	jet._crashed = true
	jet._update_visual(1.0/60.0)
	for plume in jet._effects.plumes: assert(not plume.visible, "crash cuts flames")
	for light in jet._effects.lights: assert(not light.visible, "crash cuts lights")
	stage.free()
	print("JET_EFFECTS_TEST_PASS")
	quit()
