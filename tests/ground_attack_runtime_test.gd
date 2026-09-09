extends SceneTree
const QUERY := preload("res://scripts/world/world_hit_query.gd")
class Terrain extends Node:
	func sample_mesh_height(_x: float, _z: float) -> float: return 2.0
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.set_script(load("res://tests/fixtures/startup_main.gd"))
	root.add_child(main)
	# Engine-loop playback is covered by jet_audio_runtime_test.
	main._jet_audio.set_volume(0.0, false)
	await process_frame
	await process_frame
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main.projectile_manager.clear()
	var terrain := Terrain.new()
	root.add_child(terrain)
	main.launcher_field.clear()
	main.launcher_field._spawn_launcher(Vector2(0, -1800), terrain, "CITY CENTRAL 1")
	main.launcher_field._spawn_launcher(Vector2(35, -1800), terrain, "CITY CENTRAL 2")
	var target: Dictionary = main.launcher_field.launcher_positions()[0]
	main.jet_anchor.position = Vector3(target.position.x, 1000, target.position.z + 1600)
	main.jet_anchor.basis = Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT)
	main.jet_anchor.velocity = Vector3(0, 0, -220)
	main._camera_follow_enabled = true
	main._update_targeting(0.0, main.jet_anchor, Vector3.FORWARD, 0.0)
	main._tracker.select_contact(target.id)
	main._begin_locked_view_tracking()
	main._weapons.current = main.WEAPON_SELECTION.Weapon.GUIDED_BOMB
	main._update_rockets(0.7)
	check(main._missile_launcher.is_ready(), "production guided bomb can acquire a nearby ground site")
	main._missile_view_button.pressed.emit()
	check(main._projectile_camera.enabled and not main._projectile_camera.watching, "on-screen button arms view before launch")
	main._missile_launcher.update(0.01, true)
	check(main.projectile_manager.active_rounds.size() == 1 and main._projectile_camera.watching, "a bomb launch enters the armed weapon view")
	check(not main._helmet.visible and not main.attack_reticle.visible, "aircraft aiming overlays are hidden during weapon view")
	check(main._projectile_hud.visible and main._projectile_hud.status_text() == "GUIDED BOMB  •  COORDINATE LOCK", "production weapon view shows its own live lock banner")
	check(not main.status_label.visible and not main._weapon_label.visible, "aircraft status does not overlap the weapon lock banner")
	check(main._tracker.locked_handle() == target.id and main._tracker.tracking_view, "weapon view preserves the aircraft's target tracking")
	var round_data: RefCounted = main.projectile_manager.active_rounds[0]
	var hit = main.WORLD_HIT.new()
	hit.hit = true
	hit.object_type = main.WORLD_HIT.ObjectKind.ENTITY
	hit.object_id = target.id
	hit.position = target.position
	main._hit_query = QUERY.new()
	main._hit_query.entity_index = main.launcher_field
	main._on_projectile_impacted(hit, round_data)
	check(main.launcher_field.launcher_count() == 0, "bomb impact and nearby blast can destroy clustered ground targets")
	check(main._tracker.locked().is_empty(), "ground destruction retires the selected contact")
	main._projectile_camera.update(1.0, [])
	main._update_missile_view_ui()
	check(main.camera.current and main._helmet.visible, "after impact the original camera and HUD return")
	check(not main._projectile_hud.visible and main.status_label.visible and main._weapon_label.visible, "weapon HUD clears and aircraft status returns after impact")
	main._projectile_camera.on_launch(round_data)
	main._on_gamepad_action_pressed(&"camera_travel_toggle")
	check(not main._projectile_camera.watching and main.camera.current, "R3 can also exit weapon view immediately")
	main.projectile_manager.clear()
	Engine.time_scale = 1.0
	# Drain the dummy audio driver's pending playback before scene teardown.
	main._jet_audio.player.process_mode = Node.PROCESS_MODE_ALWAYS
	main._jet_audio.player.stream_paused = false
	main._jet_audio.player.stop()
	main._threat_warning._audio.process_mode = Node.PROCESS_MODE_ALWAYS
	main._threat_warning._audio.stream_paused = false
	main._threat_warning._audio.stop()
	await create_timer(0.3, true, false, true).timeout
	main.free()
	terrain.free()
	if not failed:
		print("GROUND_ATTACK_RUNTIME_TEST_PASS")
	quit(1 if failed else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
