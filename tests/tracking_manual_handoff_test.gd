extends SceneTree
const CAMERA := preload("res://scripts/camera/jet_camera.gd")
class Pad:
	extends "res://scripts/input/gamepad_input.gd"
	var look := Vector2.ZERO
	func get_jet_look_vector() -> Vector2:
		return look
	func get_aim_vector() -> Vector2:
		return look
	func is_free_look_held() -> bool:
		return true
class Aircraft:
	extends Node3D
	var velocity := Vector3(0, 0, -180)
	var minimum_display_speed := 90.0
	var maximum_display_speed := 260.0
	var load_factor := 1.0
	func airspeed() -> float:
		return velocity.length()
	func get_interpolated_focus_position() -> Vector3:
		return global_position
	func get_interpolated_airframe_transform() -> Transform3D:
		return global_transform
	func get_interpolated_cockpit_transform() -> Transform3D:
		return global_transform
var failed := false
func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var pad := root.get_node("GamepadInput")
	var original_script = pad.get_script()
	pad.set_script(Pad)
	var main = load("res://scripts/main.gd").new()
	var camera := Camera3D.new()
	var jet := Aircraft.new()
	root.add_child(camera)
	root.add_child(jet)
	jet.position = Vector3(0, 3000, 0)
	jet.basis = Basis(Vector3.RIGHT, deg_to_rad(30.0))
	main.camera = camera
	main.jet_anchor = jet
	main.status_label = Label.new()
	main._flying_jet = true
	var fixed_target := jet.position + Vector3(-1800, 700, 900)
	var view_tracker = main._tracker
	view_tracker.update([view_tracker.contact(321, view_tracker.Kind.AIR_JET, fixed_target)], camera.position, Vector3.FORWARD, Vector3.ZERO)
	view_tracker.select_contact(321)
	main._begin_locked_view_tracking()
	for switch in range(CAMERA.Mode.size() * 2):
		main._cycle_jet_view(1)
		main._apply_target_tracking(0.5)
		check(view_tracker.tracking_view and view_tracker.locked_handle() == 321, "view selection preserves the tracked target")
		check((-camera.global_basis.z).dot((fixed_target - camera.position).normalized()) > 0.999, "every selected camera stays aimed at the tracked target")
	view_tracker.stop_view_tracking()
	for mode in range(CAMERA.Mode.size()):
		for look_angles in [Vector2(65, 15), Vector2(165, 70), Vector2(85, -35)]:
			main._jet_view = mode
			main._free_look = Vector2(0.2, -0.1)
			main._snap_follow_camera()
			var reference := Basis.looking_at(jet.basis.x, jet.basis.y)
			var target_direction := reference * (Basis(Vector3.UP, deg_to_rad(look_angles.x)) * Basis(Vector3.RIGHT, deg_to_rad(look_angles.y))) * Vector3.FORWARD
			var tracker = main._tracker
			tracker.update([tracker.contact(123, tracker.Kind.AIR_JET, camera.position + target_direction * 3000)], camera.position, target_direction, Vector3.ZERO)
			tracker.cycle_view_lock([123], camera.position, target_direction)
			main._tracking_basis = camera.basis
			for frame in range(100):
				main._apply_target_tracking(1.0 / 60.0)
			var displayed := camera.basis
			var radius := camera.position.distance_to(jet.position)
			pad.look = Vector2(0.05, 0) if look_angles.x == 85 else Vector2(0.4, -0.2)
			main._update_free_look(1.0 / 60.0)
			main._update_jet_camera(1.0 / 60.0)
			main._apply_target_tracking(1.0 / 60.0)
			var jump := rad_to_deg(displayed.get_rotation_quaternion().angle_to(camera.basis.get_rotation_quaternion()))
			print("HANDOFF mode=%d target=%s first_step=%.2f degrees" % [mode, look_angles, jump])
			check(jump < 4.0, "manual tracking release must continue from the displayed orientation, including beyond normal look limits")
			check(not tracker.tracking_view and tracker.locked_handle() == 123, "manual takeover must retain weapon lock while releasing view tracking")
			var handed_off := camera.basis
			for frame in range(15):
				main._update_free_look(1.0 / 60.0)
				main._update_jet_camera(1.0 / 60.0)
			check(handed_off.get_rotation_quaternion().angle_to(camera.basis.get_rotation_quaternion()) > deg_to_rad(3), "continued stick motion must keep turning the released view")
			pad.look = Vector2.ZERO
			var released := camera.basis
			for frame in range(30):
				main._update_free_look(1.0 / 60.0)
				main._update_jet_camera(1.0 / 60.0)
			check(released.get_rotation_quaternion().angle_to(camera.basis.get_rotation_quaternion()) < deg_to_rad(7.0), "neutral stick must brake within a short glance instead of returning to the old angle")
			var settled := camera.basis
			for frame in range(60):
				main._update_free_look(1.0 / 60.0)
				main._update_jet_camera(1.0 / 60.0)
			check(settled.get_rotation_quaternion().angle_to(camera.basis.get_rotation_quaternion()) < deg_to_rad(0.1), "settled manual look must hold its new direction")
			if mode != CAMERA.Mode.COCKPIT:
				check(absf(camera.position.distance_to(jet.position) - radius) < 0.05, "manual tracking takeover must preserve external camera distance")
			main._on_gamepad_action_pressed(&"camera_travel_toggle")
			check(tracker.tracking_view and tracker.locked_handle() == 123 and not main._manual_view_active and not main._view_returning, "R3 after a manual glance must resume the same target")
			check(camera.basis.is_equal_approx(main._tracking_basis), "resumed tracking starts at the displayed pose")
			for frame in range(100):
				main._apply_target_tracking(1.0 / 60.0)
			check((-camera.basis.z).dot((tracker.locked_position() - camera.position).normalized()) > 0.999, "resumed tracking must converge on the retained target")
			main._on_gamepad_action_pressed(&"camera_travel_toggle")
			check(main._view_returning and not tracker.tracking_view and not main._manual_view_active, "R3 while tracking keeps the existing smooth recenter action")
			for frame in range(20):
				main._update_free_look(1.0 / 60.0)
				main._update_jet_camera(1.0 / 60.0)
			var returning := camera.basis
			pad.look = Vector2(0.1, 0)
			main._update_free_look(1.0 / 60.0)
			main._update_jet_camera(1.0 / 60.0)
			check(main._manual_view_active and not main._view_returning and returning.get_rotation_quaternion().angle_to(camera.basis.get_rotation_quaternion()) < deg_to_rad(2), "interrupting recenter must also start from its currently displayed pose")
			pad.look = Vector2.ZERO
			main._on_gamepad_action_pressed(&"camera_travel_toggle")
			check(tracker.tracking_view and not main._view_returning, "R3 after interrupting a tracked-view return resumes that target")
			main._on_gamepad_action_pressed(&"camera_travel_toggle")
			var previous := camera.basis
			var maximum_step := 0.0
			for frame in range(120):
				main._update_free_look(1.0 / 60.0)
				main._update_jet_camera(1.0 / 60.0)
				maximum_step = maxf(maximum_step, previous.get_rotation_quaternion().angle_to(camera.basis.get_rotation_quaternion()))
				previous = camera.basis
			check(maximum_step < deg_to_rad(8) and not main._view_returning and main._free_look.is_zero_approx(), "recenter after takeover must complete smoothly")
	# A destroyed/out-of-range target must not be resurrected by R3.
	main._begin_manual_view()
	main._tracker.remove_contact(123)
	main._on_gamepad_action_pressed(&"camera_travel_toggle")
	check(main._view_returning and not main._tracker.tracking_view and main._tracker.locked().is_empty(), "without a live target R3 falls back to recentering")
	main._flying_jet = false
	main.helicopter_anchor = jet
	for mode in [main.View.COCKPIT, main.View.CHASE, main.View.ORBIT]:
		main._view = mode
		main._free_look = Vector2.ZERO
		main._snap_follow_camera()
		if mode == main.View.COCKPIT:
			main._update_cockpit_camera()
		var target_direction := Vector3(-0.7, 0.25, -1).normalized()
		var tracker = main._tracker
		tracker.update([tracker.contact(123, tracker.Kind.AIR_JET, camera.position + target_direction * 3000)], camera.position, target_direction, Vector3.ZERO)
		tracker.cycle_view_lock([123], camera.position, target_direction)
		main._tracking_basis = camera.basis
		for frame in range(100):
			main._apply_target_tracking(1.0 / 60.0)
		var displayed := camera.basis
		pad.look = Vector2(0.4, 0.1)
		main._update_free_look(1.0 / 60.0)
		if mode == main.View.COCKPIT:
			main._update_cockpit_camera()
		else:
			main._apply_follow_camera(1.0 / 60.0)
		check(displayed.get_rotation_quaternion().angle_to(camera.basis.get_rotation_quaternion()) < deg_to_rad(4) and not tracker.tracking_view, "Apache cockpit and external aim must also continue from the tracked pose")
		pad.look = Vector2.ZERO
		main._on_gamepad_action_pressed(&"camera_travel_toggle")
		check(tracker.tracking_view and tracker.locked_handle() == 123 and not main._manual_view_active, "Apache R3 also resumes the target after a manual glance")
		main._on_gamepad_action_pressed(&"camera_travel_toggle")
		check(not tracker.tracking_view and tracker.locked_handle() == 123, "Apache R3 while tracking retains its existing release action")
		main._snap_follow_camera()
		check(not main._manual_view_active, "explicit view changes must clear manual takeover state")
	main.status_label.free()
	main.free()
	jet.free()
	camera.free()
	pad.set_script(original_script)
	paused = false
	if not failed:
		print("TRACKING_MANUAL_HANDOFF_TEST_PASS")
	quit(1 if failed else 0)
