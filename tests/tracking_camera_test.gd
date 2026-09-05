extends SceneTree
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Exercise production camera methods without starting streamed terrain.
	var main = load("res://scripts/main.gd").new()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 100, 0)
	camera.current = true
	main.camera = camera
	main.status_label = Label.new()
	main._camera_follow_enabled = true
	var contacts := [
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0,100,-3000)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(180,100,-3000)),
		TRACKER.contact(3, TRACKER.Kind.AIR_JET, Vector3(0,100,1000)),
	]
	main._tracker.update(contacts, camera.position, Vector3.FORWARD, Vector3.ZERO)
	main._track_looked_at_target()
	assert(main._tracker.locked_handle() == 1)
	contacts[0].position += Vector3(400, 200, 0)
	main._tracker.update(contacts, camera.position, Vector3.FORWARD, Vector3.ZERO)
	for frame in range(120):
		# Normal follow resets the basis each frame; tracking must keep its own
		# smoothing state and still converge on the moving contact.
		camera.basis = Basis.IDENTITY
		main._apply_target_tracking(1.0 / 60.0)
	assert((-camera.global_basis.z).dot((contacts[0].position - camera.position).normalized()) > 0.9999)
	var original_position: Vector3 = contacts[0].position
	contacts[0].position = Vector3(3000,100,0)
	main._tracker.update(contacts, camera.position, Vector3.FORWARD, Vector3.ZERO)
	for frame in range(120):
		main._apply_target_tracking(1.0 / 60.0)
	assert(main._tracker.boxed().any(func(c): return c.handle == 1), "HUD contact boxes must follow the tracked camera, not the old forward view")
	contacts[0].position = original_position
	main._tracker.update(contacts, camera.position, Vector3.FORWARD, Vector3.ZERO)
	camera.basis = Basis.IDENTITY
	main._track_looked_at_target()
	assert(main._tracker.locked_handle() == 2)
	main._on_gamepad_action_pressed(&"camera_travel_toggle")
	assert(not main._tracker.tracking_view and main._tracker.locked_handle() == 2)
	# A sky ray has no terrain/building hit. Tapping the airborne contact
	# must still work, even when the world query returns null.
	main._hit_query = load("res://scripts/world/world_hit_query.gd").new()
	var carrier := Node3D.new()
	root.add_child(carrier)
	main.jet_anchor = carrier
	main._flying_jet = true
	main._track_looked_at_target()
	main._lock_at_screen(camera.unproject_position(contacts[1].position))
	assert(main._tracker.locked_handle() == 2 and not main._tracker.tracking_view)
	contacts[1].position += Vector3(50,0,0)
	main._tracker.update(contacts, camera.position, Vector3.FORWARD, Vector3.ZERO)
	assert(main._orbit_target_point() == contacts[1].position, "weapon aim must follow the live contact after a tap, without camera tracking")
	main._tracker.clear_lock()
	assert(main._orbit_target_point() == null, "released locks must not leave a stale turret target")
	carrier.free()
	main.status_label.free()
	main.free()
	camera.free()
	print("TRACKING_CAMERA_TEST_PASS")
	quit()
