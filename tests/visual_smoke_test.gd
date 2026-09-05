extends SceneTree

## Run with a real Compatibility renderer and --visual-out=/tmp/... to export
## the three lighting states. The normal headless suite checks scene wiring.
const JET := preload("res://scripts/jet/jet_controller.gd")
const JET_SCENE := preload("res://3dassets/f-22_raptor_-_fighter_jet_-_free.glb")
const DAY := preload("res://scripts/world/day_cycle.gd")
const SKY := preload("res://scripts/world/sky_state.gd")
const FLARE := preload("res://scripts/world/lens_flare.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--visual-out="):
			output = arg.trim_prefix("--visual-out=")
	var stage := Node3D.new()
	root.add_child(stage)
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	var environment: WorldEnvironment = scene.get_node("WorldEnvironment").duplicate()
	stage.add_child(environment)
	var sun: DirectionalLight3D = scene.get_node("Sun").duplicate()
	stage.add_child(sun)
	scene.free()
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20000.0, 20000.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.36, 0.31)
	ground.material_override = material
	stage.add_child(ground)
	var jet := JET.new()
	var model: Node3D = JET_SCENE.instantiate()
	model.name = "HeroJet"
	jet.add_child(model)
	stage.add_child(jet)
	jet.set_physics_process(false)
	jet.launch(Vector3(0.0, 12.0, 0.0), deg_to_rad(30.0))
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.far = 30000.0
	camera.fov = 48.0
	stage.add_child(camera)
	camera.position = Vector3(35.0, 25.0, 40.0)
	camera.look_at(jet.position)
	camera.current = true
	var day := DAY.new()
	day.sun_path = NodePath("../Sun")
	day.environment_path = NodePath("../WorldEnvironment")
	stage.add_child(day)
	day.set_process(false)
	var flare := FLARE.new()
	flare.camera_path = NodePath("../Camera")
	flare.sun_path = NodePath("../Sun")
	stage.add_child(flare)
	await process_frame
	jet.reset_physics_interpolation()
	for state in [{"name": "noon", "elevation": 60.0}, {"name": "dusk", "elevation": 3.0}, {"name": "night", "elevation": -30.0}]:
		day.elevation_deg = state.elevation
		day.azimuth_deg = 240.0
		day._apply(SKY.for_elevation(state.elevation))
		assert(sun.light_energy > 0.0, "each lighting state must leave a usable light")
		assert(jet.get_node_or_null("HeroJet") != null, "the production aircraft must be present")
		if output != "" and DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			assert(screenshot != null and not screenshot.is_empty())
			var path := "%s-%s.png" % [output, state.name]
			assert(screenshot.save_png(path) == OK)
			print("VISUAL_SAVED ", path)
	stage.free()
	print("VISUAL_SMOKE_TEST_PASS")
	quit()
