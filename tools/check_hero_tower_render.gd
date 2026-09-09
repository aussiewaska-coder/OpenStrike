extends SceneTree

## Run with a real Compatibility renderer (xvfb/softpipe works); headless
## cannot validate pixels. Images go to /tmp for before/after inspection.
var images: Dictionary = {}
var models: Array[Node3D] = []

func _init(): call_deferred("run")
func run():
	root.size = Vector2i(800, 600)
	var stage = Node3D.new()
	root.add_child(stage)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.22,0.32,0.45)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.38
	stage.add_child(env)
	var sun = DirectionalLight3D.new()
	stage.add_child(sun)
	sun.rotation_degrees = Vector3(-35,-30,0)
	sun.light_energy = 0.9
	var camera = Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(150,210,520)
	camera.look_at(Vector3(0,155,0))
	camera.far = 3000
	camera.fov = 45
	for i in 3:
		var name = ["q1","soul","ocean"][i]
		var model = load("res://assets/models/%s_tower.glb" % name).instantiate()
		stage.add_child(model)
		models.append(model)
		model.position.x = (i-1)*150
	for variant in ["baseline", "fixed-day", "fixed-night-unlit", "fixed-night"]:
		if variant == "fixed-day":
			for model in stage.get_children():
				if model is Node3D: load("res://scripts/entities/hero_towers.gd").prepare_model(model)
		if variant.begins_with("fixed-night"):
			sun.light_energy = 0.08
			sun.light_color = Color(0.55,0.65,0.95)
			env.environment.ambient_light_energy = 0.10
			RenderingServer.global_shader_parameter_set("os_night", 1.0 if variant == "fixed-night" else 0.0)
		else:
			RenderingServer.global_shader_parameter_set("os_night", 0.0)
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		var shot = root.get_texture().get_image()
		images[variant] = shot
		shot.save_png("/tmp/towers-%s.png" % variant)
	var failed = false
	var day: Image = images["fixed-day"]
	var scale_to_image = Vector2(day.get_size()) / root.get_visible_rect().size
	for model in models:
		var bounds = Rect2()
		var first = true
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			for point in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var pixel = camera.unproject_position(mi.to_global(point)) * scale_to_image
				if first:
					bounds = Rect2(pixel, Vector2.ZERO)
					first = false
				else: bounds = bounds.expand(pixel)
		var brightened = 0
		var lit_windows = 0
		for y in range(maxi(0, int(bounds.position.y)), mini(day.get_height(), int(bounds.end.y) + 1)):
			for x in range(maxi(0, int(bounds.position.x)), mini(day.get_width(), int(bounds.end.x) + 1)):
				if day.get_pixel(x,y).get_luminance() - images["baseline"].get_pixel(x,y).get_luminance() > 0.04:
					brightened += 1
				if images["fixed-night"].get_pixel(x,y).get_luminance() - images["fixed-night-unlit"].get_pixel(x,y).get_luminance() > 0.08:
					lit_windows += 1
		print("%s: brighter facade pixels=%d, night window pixels=%d" % [model.name, brightened, lit_windows])
		if brightened < 100 or lit_windows < 20:
			push_error("%s still lacks visible day/night facades" % model.name)
			failed = true
	if not failed: print("TOWER_RENDER_TEST_PASS")
	quit(1 if failed else 0)
