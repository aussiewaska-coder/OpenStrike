extends SceneTree

func _init() -> void: call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(960, 540)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.46, 0.63, 0.75)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2500, 2500)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.3, 0.18)
	ground.material_override = material
	scene.add_child(ground)
	var building := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(42, 65, 42)
	building.mesh = box
	building.position = Vector3(85, 32.5, 0)
	scene.add_child(building)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(280, 230, 420)
	camera.look_at(Vector3(0, 90, 0))
	var fires = load("res://scripts/effects/strike_fire.gd").new()
	scene.add_child(fires)
	fires.ignite(Vector3(-100, 0, 0))
	fires.ignite(Vector3(85, 66, 0), true)
	for site in fires._sites:
		site.smoke.preprocess = 10.0
		site.fire.preprocess = 2.0
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var warning = load("res://scripts/ui/threat_warning.gd").new()
	layer.add_child(warning)
	var trails = load("res://scripts/effects/trail_renderer.gd").new()
	scene.add_child(trails)
	trails.begin_trail(1)
	for i in 60:
		trails.age_trails(float(i) / 60)
		trails.push_point(1, Vector3(-230 + i * 5, 220 - i, -50))
	trails.end_trail(1)
	trails.set_process(false)
	trails._rebuild()
	warning.update_warning(0.01, {"incoming": 1, "locks": 2, "distance": 680.0, "position": Vector3(-200, 200, -50)}, camera, 100)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/openstrike-enemy-combat.png")
	warning.update_warning(0.01, {}, camera, 100)
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/openstrike-strike-fires.png")
	scene.free()
	layer.free()
	print("ENEMY_COMBAT_RENDER_DONE")
	quit()
