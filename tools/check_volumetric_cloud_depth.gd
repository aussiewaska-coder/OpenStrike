extends SceneTree

## Rendered regression: clouds obscure the sky but cannot cover nearby opaque
## aircraft/terrain. Run with a real Compatibility renderer, not --headless.
const CLOUDS := preload("res://scripts/world/cloud_deck.gd")
const WEATHER_NOISE := preload("res://assets/textures/cloud_noise.tres")
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.scaling_3d_scale = 0.75
	root.size = Vector2i(160, 90)
	root.content_scale_size = root.size
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.15, 0.45, 0.8)
	stage.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(-551, 1700, -551)
	camera.far = 40000.0
	stage.add_child(camera)
	camera.make_current()
	var clouds := CLOUDS.new()
	stage.add_child(clouds)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference-shader="):
			var shader := Shader.new()
			shader.code = FileAccess.get_file_as_string(arg.trim_prefix("--reference-shader="))
			clouds.material_override.shader = shader
	RenderingServer.global_shader_parameter_set("os_sun_dir", Vector3.UP)
	RenderingServer.global_shader_parameter_set("os_night", 0.0)
	var white := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var coverage := ImageTexture.create_from_image(white)
	RenderingServer.global_shader_parameter_set("os_cloud_noise", coverage)
	RenderingServer.global_shader_parameter_set("os_cloud_coverage", 1.0)
	var obstacle := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	obstacle.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.9, 0.05, 0.03)
	obstacle.material_override = material
	stage.add_child(obstacle)
	obstacle.position = camera.position + Vector3(0, 0, -1)
	clouds.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var baseline := root.get_texture().get_image()
	clouds.visible = true
	await process_frame
	await RenderingServer.frame_post_draw
	var cloudy := root.get_texture().get_image()
	var centre_before := baseline.get_pixel(80, 45)
	var centre_after := cloudy.get_pixel(80, 45)
	check(distance(centre_before, centre_after) < 0.03, "opaque foreground clips cloud integration")
	check(distance(baseline.get_pixel(15, 15), cloudy.get_pixel(15, 15)) > 0.08, "3D cloud extinction visibly obscures background")
	cloudy.save_png("/tmp/volumetric-cloud-depth.png")
	# An upward ray above the layer must not intersect the finite volume.
	var grey := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	grey.fill(Color(0.64, 0.64, 0.64))
	var sparse := ImageTexture.create_from_image(grey)
	RenderingServer.global_shader_parameter_set("os_cloud_noise", sparse)
	RenderingServer.global_shader_parameter_set("os_cloud_coverage", 0.5)
	camera.position.y = 2610.0
	clouds._process(0.0)
	clouds.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var clear_top := root.get_texture().get_image()
	clouds.visible = true
	await process_frame
	await RenderingServer.frame_post_draw
	var sparse_top := root.get_texture().get_image()
	check(distance(clear_top.get_pixel(80, 30), sparse_top.get_pixel(80, 30)) < 0.03, "upward rays above cloud tops remain clear")
	# At 3 km the low bank is below us; a developed storm tower must remain.
	camera.position = Vector3(-270, 3000, -270)
	clouds._process(0.0)
	RenderingServer.global_shader_parameter_set("os_cloud_noise", coverage)
	RenderingServer.global_shader_parameter_set("os_cloud_coverage", 0.65)
	await process_frame
	await RenderingServer.frame_post_draw
	var fair_high := root.get_texture().get_image()
	RenderingServer.global_shader_parameter_set("os_cloud_coverage", 1.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var storm_high := root.get_texture().get_image()
	check(distance(fair_high.get_pixel(80, 45), storm_high.get_pixel(80, 45)) > 0.08, "storm towers extend above the fair-weather bank")
	RenderingServer.global_shader_parameter_set("os_cloud_noise", WEATHER_NOISE)
	stage.free()
	await process_frame
	if not failed:
		print("VOLUMETRIC_CLOUD_DEPTH_TEST_PASS")
	call_deferred("_finish")

func _finish() -> void:
	await process_frame
	quit(1 if failed else 0)

func distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
