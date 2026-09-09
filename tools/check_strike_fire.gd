extends SceneTree

## Actual sustained-fire renderer at successive ages, without aircraft assets.
const FIRES := preload("res://scripts/effects/strike_fire.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(640, 360)
	root.content_scale_size = root.size
	root.scaling_3d_scale = 0.75
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.48, 0.65, 0.8)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.7
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000, 3000)
	ground.mesh = plane
	var land := StandardMaterial3D.new()
	land.albedo_color = Color(0.22, 0.24, 0.18)
	ground.material_override = land
	stage.add_child(ground)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(480, 500, 1000)
	camera.look_at(Vector3(0, 280, 0))
	camera.far = 4000
	camera.make_current()
	var fires := FIRES.new()
	fires.set_process(false)
	stage.add_child(fires)
	fires._rng.seed = 4721
	for point in [Vector3(-100, 0, 0), Vector3(100, 0, 0)]:
		var wreck := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(25, 8, 15)
		wreck.mesh = box
		wreck.position = point + Vector3.UP * 4
		var charred := StandardMaterial3D.new()
		charred.albedo_color = Color(0.035, 0.03, 0.025)
		wreck.material_override = charred
		stage.add_child(wreck)
		fires.ignite(point, point.x > 0)
	# Preprocess the production emitters at known simulation ages. This avoids
	# shader-compilation stalls making the CPU and particle clocks diverge.
	var previous_age := 0.0
	for age in [3.0, 15.0, 40.0]:
		fires._process(age - previous_age)
		previous_age = age
		for index in fires._sites.size():
			for key in ["fire", "smoke"]:
				var emitter: CPUParticles3D = fires._sites[index][key]
				emitter.use_fixed_seed = true
				emitter.seed = 47 + index * 13
				emitter.preprocess = minf(age, emitter.lifetime)
				emitter.restart()
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "/tmp/openstrike-strike-fire-%02ds.png" % int(age)
		assert(root.get_texture().get_image().save_png(path) == OK)
		print("STRIKE_FIRE_RENDER ", path, " simulated_age=", age)
		if age == 15.0:
			var overview := camera.transform
			camera.position = Vector3(220, 65, 170)
			camera.look_at(Vector3(100, 35, 0))
			for frame in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/openstrike-strike-fire-close.png")
			camera.transform = overview

	fires.clear()
	var blast := preload("res://scripts/effects/impact_fx_manager.gd").new()
	stage.add_child(blast)
	blast.set_process(false)
	camera.position = Vector3(220, 150, 330)
	camera.look_at(Vector3(0, 30, 0))
	blast.spawn_explosion(Vector3.ZERO)
	blast._process(0.32)
	for emitter in blast._bursts:
		if emitter.emitting:
			emitter.preprocess = 0.32
			emitter.restart()
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/openstrike-shockwave.png")
	stage.free()
	await process_frame
	print("STRIKE_FIRE_RENDER_DONE")
	quit()
