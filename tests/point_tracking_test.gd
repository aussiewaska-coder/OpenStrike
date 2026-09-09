extends SceneTree
const TRACKER = preload("res://scripts/targeting/target_tracker.gd")
const WORLD_HIT = preload("res://scripts/world/world_hit_result.gd")
class WallQuery:
	extends RefCounted
	func query_segment(from: Vector3, to: Vector3):
		var hit = WORLD_HIT.new()
		hit.hit = true
		hit.position = from.lerp(to, 0.25)
		hit.object_type = WORLD_HIT.ObjectKind.BUILDING
		return hit
var failed := false
func _init(): call_deferred("_run")
func _run():
	var main = load("res://scripts/main.gd").new()
	var camera = Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.position = Vector3(0, 100, 0)
	main.camera = camera
	main.status_label = Label.new()
	main._camera_follow_enabled = true
	main._flying_jet = false
	# Terrain point through the centre of the view, selected through the same
	# action as the physical track-target button.
	camera.look_at(Vector3(0, 0, -1000))
	main._on_gamepad_action_pressed(&"track_target")
	_check(main._tracker.tracking_view and main._tracker.locked_handle() == TRACKER.FALLBACK_HANDLE, "track button must lock and track terrain when no contact is selected")
	if main._tracker.locked().is_empty():
		_cleanup(main,camera)
		return
	var point: Vector3 = main._tracker.locked_position()
	_check(point.distance_to(Vector3(0,0,-1000)) < 0.1, "ground lock must hit the centre ray's actual terrain point")
	for i in range(120):
		camera.position.x += 2.0
		main._tracker.update([], camera.position, -camera.basis.z, Vector3.ZERO)
		main._apply_target_tracking(1.0 / 60.0)
	_check(main._tracker.locked_position().is_equal_approx(point), "world lock must stay fixed as the aircraft moves")
	_check((-camera.basis.z).dot((point-camera.position).normalized()) > 0.999, "camera must follow the pinned world point")
	main._on_gamepad_action_pressed(&"camera_travel_toggle")
	_check(not main._tracker.tracking_view and main._tracker.locked_handle() == TRACKER.FALLBACK_HANDLE, "recenter must release point tracking while preserving weapon lock")
	main._manual_view_active = true
	camera.basis = Basis(Vector3.UP, PI)
	main._on_gamepad_action_pressed(&"camera_travel_toggle")
	_check(main._tracker.tracking_view and main._tracker.locked_position().is_equal_approx(point), "R3 after looking away must also resume a pinned world point")
	main._on_gamepad_action_pressed(&"camera_travel_toggle")
	_check(not main._tracker.tracking_view, "R3 while tracking the point retains the release action")
	# An unrelated jet at the side of the screen must not steal a point lock.
	main._tracker.clear_lock()
	camera.position = Vector3(0,100,0)
	camera.basis = Basis.IDENTITY
	var remote = TRACKER.contact(3, TRACKER.Kind.AIR_JET, Vector3(800,100,-2000))
	main._tracker.update([remote], camera.position, Vector3.FORWARD, Vector3.ZERO)
	main._track_looked_at_target()
	_check(main._tracker.locked_handle() == TRACKER.FALLBACK_HANDLE and main._tracker.tracking_view, "sky with no nearby bogie must pin a world point, not grab a peripheral aircraft")
	_check(main._tracker.locked_position().distance_to(camera.position) > 1000, "empty-sky point must lie ahead at a usable tracking distance")
	# A point lock must allow a subsequent press to acquire a real contact.
	var near = TRACKER.contact(4, TRACKER.Kind.AIR_JET, Vector3(0,100,-2000))
	main._tracker.update([near], camera.position, Vector3.FORWARD, Vector3.ZERO)
	main._track_looked_at_target()
	_check(main._tracker.locked_handle() == 4, "a bogie near the reticle must take priority on the next selection")
	main._tracker.clear_lock()
	main._tracker.update([], camera.position, Vector3.FORWARD, Vector3.ZERO)
	main._hit_query = WallQuery.new()
	main._track_looked_at_target()
	_check(main._tracker.locked().kind == TRACKER.Kind.BUILDING, "point tracking must recognise a building hit")
	_cleanup(main,camera)
func _cleanup(main, camera):
	main.status_label.free()
	main.free()
	camera.free()
	if not failed: print("POINT_TRACKING_TEST_PASS")
	quit(1 if failed else 0)
func _check(ok: bool, message: String):
	if not ok:
		failed = true
		push_error(message)
