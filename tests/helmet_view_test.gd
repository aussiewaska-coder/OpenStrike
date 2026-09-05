extends SceneTree

const PROJECTION := preload("res://scripts/ui/hud_projection.gd")

class DrawProbe:
	extends "res://scripts/ui/helmet_hud.gd"
	var instruments_drawn := 0
	var contacts_drawn := 0
	func _draw_horizon() -> void:
		instruments_drawn += 1
	func _draw_ladder() -> void:
		instruments_drawn += 1
	func _draw_flight_path_marker() -> void:
		instruments_drawn += 1
	func _draw_boresight() -> void:
		instruments_drawn += 1
	func _draw_tapes() -> void:
		instruments_drawn += 1
	func _draw_visor() -> void:
		instruments_drawn += 1
	func _draw_boxes() -> void:
		contacts_drawn += 1
	func _draw_lock() -> void:
		contacts_drawn += 1

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 900, 0)
	for attitude in [Basis.IDENTITY, Basis(Vector3.FORWARD, deg_to_rad(40.0)), Basis(Vector3.RIGHT, deg_to_rad(25.0))]:
		camera.basis = attitude
		for point in PROJECTION.horizon_points(attitude, camera.position):
			check(not camera.is_position_behind(point), "horizon reference must project in front of the camera at normal flight attitudes")
	camera.basis = Basis.IDENTITY
	var arc := PROJECTION.pitch_arc(camera.basis, 20.0, -20.0, 20.0, 8)
	var left := camera.unproject_position(PROJECTION.far_point(camera.position, arc[0]))
	var centre := camera.unproject_position(PROJECTION.far_point(camera.position, arc[4]))
	var right := camera.unproject_position(PROJECTION.far_point(camera.position, arc[8]))
	check(left.y < centre.y and is_equal_approx(left.y, right.y), "spherical climb bars must curve symmetrically above their centre")
	camera.basis = Basis(Vector3.BACK, deg_to_rad(40.0))
	var banked_left := camera.unproject_position(PROJECTION.far_point(camera.position, arc[0]))
	var banked_right := camera.unproject_position(PROJECTION.far_point(camera.position, arc[8]))
	check(absf(banked_right.y - banked_left.y) > 20.0, "ladder must rotate with a bank rather than falling back to horizontal")
	for pitch in [-90.0, -45.0, 0.0, 45.0, 90.0]:
		for point in PROJECTION.pitch_arc(Basis(Vector3.RIGHT, deg_to_rad(pitch)), pitch, -11.0, 11.0):
			check(point.is_finite() and is_equal_approx(point.length(), 1.0), "attitude sphere must stay finite at vertical attitudes")
	check(is_equal_approx(PROJECTION.visor_alpha(Vector2(480, 270), Vector2(960, 540)), 1.0), "central attitude cues must remain readable")
	check(is_zero_approx(PROJECTION.visor_alpha(Vector2(10, 270), Vector2(960, 540))), "attitude cues must fade before peripheral tapes")
	var main = load("res://scripts/main.gd").new()
	var helmet := DrawProbe.new()
	main._helmet = helmet
	helmet._camera = camera
	main._flying_jet = true
	for view in range(main.JET_CAMERA.Mode.size()):
		main._jet_view = view
		main._apply_view_chrome()
		helmet.instruments_drawn = 0
		helmet.contacts_drawn = 0
		helmet._draw()
		check((helmet.instruments_drawn > 0) == (view == main.JET_CAMERA.Mode.COCKPIT), "helmet ladder and instruments must only draw in cockpit view")
		check(helmet.contacts_drawn == 2, "external views must retain target and lock cues")
	main._flying_jet = false
	for view in [main.View.CHASE, main.View.ORBIT, main.View.COCKPIT]:
		main._view = view
		main._apply_view_chrome()
		helmet.instruments_drawn = 0
		helmet._draw()
		check((helmet.instruments_drawn > 0) == (view == main.View.COCKPIT), "Apache views must use the same cockpit-only instrument rule")
	helmet.free()
	main.free()
	camera.free()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--visual-out=") and DisplayServer.get_name() != "headless":
			await _render_views(arg.trim_prefix("--visual-out="))
	if not failed:
		print("HELMET_VIEW_TEST_PASS")
	quit(1 if failed else 0)


func _render_views(output: String) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	stage.add_child(scene.get_node("WorldEnvironment").duplicate())
	stage.add_child(scene.get_node("Sun").duplicate())
	scene.free()
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100000, 100000)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.27, 0.23)
	ground.material_override = material
	stage.add_child(ground)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 900, 0)
	camera.far = 60000.0
	camera.fov = 60.0
	camera.current = true
	var helmet := preload("res://scripts/ui/helmet_hud.gd").new()
	root.add_child(helmet)
	for state in [{"name": "level", "bank": 0.0, "cockpit": true}, {"name": "banked", "bank": 40.0, "cockpit": true}, {"name": "external", "bank": 0.0, "cockpit": false}]:
		camera.basis = Basis(Vector3.BACK, deg_to_rad(state.bank)) * Basis(Vector3.RIGHT, deg_to_rad(8.0))
		helmet.set_cockpit_view(state.cockpit)
		helmet.set_state(camera, Vector3(0, 30, -180), [{"handle": 1, "position": Vector3(150, 950, -3000)}], {}, 0.0, {"speed_mps": 180.0, "altitude_m": 900.0, "heading_degrees": 28.0, "g_load": 1.2, "mach": 0.53})
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("%s-%s.png" % [output, state.name]) == OK, "HUD visual capture must save")
		helmet.queue_redraw()
	helmet.free()
	stage.free()
