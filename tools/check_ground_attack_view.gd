extends SceneTree
class Terrain extends Node:
	func sample_mesh_height(_x: float, _z: float) -> float: return 2.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(960, 540)
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.set_script(load("res://tests/fixtures/startup_main.gd"))
	root.add_child(main)
	await process_frame
	await process_frame
	paused = false
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.get_node("UI/ControllerOverlay").hide()
	main.settings_panel.hide()
	main._camera_follow_enabled = true
	var terrain := Terrain.new()
	root.add_child(terrain)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(18000, 18000)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.23, 0.11)
	ground.material_override = material
	ground.position.y = 2.0
	root.add_child(ground)
	main.launcher_field.clear()
	for index in 4:
		main.launcher_field._spawn_launcher(Vector2((index % 2) * 60.0, -1800.0 - (index / 2) * 60.0), terrain, "CITY CENTRAL %d" % (index + 1))
	var target: Dictionary = main.launcher_field.launcher_positions()[0]
	main.jet_anchor.position = Vector3(0, 900, 0)
	main.jet_anchor.basis = Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT)
	main.jet_anchor.velocity = Vector3(0, 0, -220)
	main.camera.position = main.jet_anchor.position
	main.camera.look_at(target.position)
	main.camera.make_current()
	main.jet_anchor.hide()
	main._update_targeting(0.0, main.jet_anchor, Vector3.FORWARD, 0.0)
	main._tracker.select_contact(target.id)
	main._weapons.current = main.WEAPON_SELECTION.Weapon.GUIDED_BOMB
	main._update_rockets(0.7)
	main._update_targeting(0.0, main.jet_anchor, Vector3.FORWARD, 0.0)
	main.status_label.text = "CITY CENTRAL • FOUR GROUND TARGETS"
	main._mission_label.text = "GUIDED GROUND ATTACK"
	main._radar.visible = true
	main._toggle_missile_view()
	await _capture("ready", main)
	main._missile_launcher.update(0.01, true)
	main._update_rockets(0.0)
	var round_data: RefCounted = main.projectile_manager.active_rounds[0]
	round_data.position = target.position + Vector3(0, 110, 160)
	round_data.previous_position = round_data.position
	round_data.velocity = (target.position - round_data.position).normalized() * 250.0
	main._missile_fx._process(0.0)
	for frame in 120:
		main._projectile_camera.update(1.0 / 60.0, main.projectile_manager.active_rounds)
	main._update_missile_view_ui()
	await _capture("following", main)
	main._toggle_missile_view()
	await _capture("returned", main)
	main.free()
	terrain.free()
	ground.free()
	print("GROUND_ATTACK_RENDER_DONE")
	quit()

func _capture(name: String, main: Node3D) -> void:
	for frame in 3:
		await process_frame
	assert(root.get_visible_rect().encloses(main._missile_view_button.get_global_rect()), "the missile-view toggle must fit a phone viewport")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/openstrike-ground-%s.png" % name)
