extends SceneTree

const CAMERA := preload("res://scripts/camera/jet_camera.gd")

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
	var main = load("res://scripts/main.gd").new()
	var camera := Camera3D.new()
	var jet := Aircraft.new()
	root.add_child(camera)
	root.add_child(jet)
	jet.position = Vector3(0, 3000, 0)
	main.camera = camera
	main.status_label = Label.new()
	main.jet_anchor = jet
	main._flying_jet = true
	for mode in [CAMERA.Mode.PURSUIT, CAMERA.Mode.TRACK]:
		for moving in [false, true]:
			main._jet_view = mode
			main._free_look = Vector2.ZERO
			main._update_jet_camera(0.0, true)
			var radius := camera.position.distance_to(jet.position)
			var minimum := radius
			var maximum := radius
			var minimum_framing := 1.0
			for frame in range(360):
				if moving:
					jet.position += jet.velocity / 60.0
				main._free_look = CAMERA.updated_external_look(main._free_look, Vector2(-0.5, 0), main.free_look_speed, 0.0, 1.0 / 60.0)
				main._update_jet_camera(1.0 / 60.0)
				var actual := camera.position.distance_to(jet.position)
				minimum = minf(minimum, actual)
				maximum = maxf(maximum, actual)
				minimum_framing = minf(minimum_framing, (-camera.basis.z).dot((jet.position - camera.position).normalized()))
			print("Orbit mode=%d moving=%s radius=%.3f range=%.3f..%.3f framing=%.3f" % [mode, moving, radius, minimum, maximum, minimum_framing])
			check(maximum - minimum < 0.05, "360 look must hold distance to the displayed aircraft, including during flight")
			check(minimum_framing > 0.99, "360 look must keep the aircraft framed throughout the orbit")
		# Pitch input must work relative to the flight heading, including when
		# travelling along world X. Diagonal sweeps must not stretch the boom.
		jet.velocity = Vector3(180, 0, 0)
		main._free_look = Vector2.ZERO
		main._update_jet_camera(0.0, true)
		var pitch_radius := camera.position.distance_to(jet.position)
		var highest := camera.position.y
		var lowest := highest
		for frame in range(240):
			jet.position += jet.velocity / 60.0
			main._free_look = CAMERA.updated_external_look(main._free_look, Vector2(0.2, 0.5 if frame < 120 else -0.5), main.free_look_speed, 0.0, 1.0 / 60.0)
			main._update_jet_camera(1.0 / 60.0)
			check(absf(camera.position.distance_to(jet.position) - pitch_radius) < 0.05, "diagonal orbit must preserve radius")
			highest = maxf(highest, camera.position.y)
			lowest = minf(lowest, camera.position.y)
		check(highest - lowest > pitch_radius, "pitch must orbit vertically regardless of flight heading")
		jet.velocity = Vector3(0, 0, -180)
	# Terrain avoidance lifts the camera along the sphere where possible.
	var low_focus := Vector3(0, 12, 0)
	var safe := CAMERA.clear_orbit_position(low_focus, low_focus + Vector3(0, -16, 12), 6.0)
	check(safe.y >= 6.0 and absf(safe.distance_to(low_focus) - 20.0) < 0.001, "terrain clearance should preserve available orbit radius")
	main._jet_view = CAMERA.Mode.COCKPIT
	main._free_look = Vector2.ZERO
	jet.load_factor = 9.0
	for time in [0.0, 0.3, 0.9, 1.7]:
		main._cockpit_bob_time = time
		main._update_jet_camera(1.0 / 60.0)
		check(camera.global_position.is_equal_approx(jet.global_position), "first-person camera must remain on its mount")
		check(camera.global_basis.is_equal_approx(Basis.looking_at(jet.basis.x, jet.basis.y)), "neutral nose camera must face forward without head bob, including under load")
	jet.load_factor = 1.0
	main._free_look_motion.velocity = Vector2.RIGHT
	main._cockpit_bob_time = 0.3
	main._update_jet_camera(1.0 / 60.0)
	var neutral := Basis.looking_at(jet.basis.x, jet.basis.y)
	var bob_angle := neutral.get_rotation_quaternion().angle_to(camera.basis.get_rotation_quaternion())
	check(bob_angle > deg_to_rad(0.01) and bob_angle < deg_to_rad(0.4), "moving freelook must add only a subtle rotational head bob")
	check(camera.position.is_equal_approx(jet.position), "head bob must preserve cockpit mount clearance")
	main._free_look = Vector2(0.6, 0.1)
	main._update_jet_camera(0.0, true)
	var local_look := Basis.looking_at(jet.basis.x, jet.basis.y).inverse() * camera.basis
	var upright := Basis.looking_at(-local_look.z, Vector3.UP)
	check(absf(upright.x.dot(local_look.y)) > 0.02, "turning the cockpit head must allow gentle neck tilt")
	# Tracking keeps the target centred while using the banked pilot's frame.
	jet.basis = Basis(Vector3.RIGHT, deg_to_rad(30.0))
	var reference := Basis.looking_at(jet.basis.x, jet.basis.y)
	var target_direction := reference * Vector3(-0.8, 0.1, -1).normalized()
	var tracker = main._tracker
	var contact = tracker.contact(123, tracker.Kind.AIR_JET, jet.position + target_direction * 3000.0)
	tracker.update([contact], camera.position, target_direction, Vector3.ZERO)
	tracker.cycle_view_lock([123], camera.position, target_direction)
	main._tracking_basis = camera.basis
	for frame in range(120):
		main._update_jet_camera(1.0 / 60.0)
		main._apply_target_tracking(1.0 / 60.0)
	check((-camera.basis.z).dot(target_direction) > 0.9999, "head tilt must not move tracking off target")
	var tracked_local := reference.inverse() * camera.basis
	var tracked_upright := Basis.looking_at(-tracked_local.z, Vector3.UP)
	var roll := atan2(tracked_upright.x.dot(tracked_local.y), tracked_upright.y.dot(tracked_local.y))
	check(absf(roll) > deg_to_rad(1.0) and absf(roll) <= deg_to_rad(6.1), "tracked head tilt must stay gentle relative to the airframe")
	for yaw in [-PI, -2.0, -1.0, 0.0, 1.0, 2.0, PI]:
		check(absf(CAMERA.head_tilt(yaw)) <= deg_to_rad(6.0), "neck roll must stay bounded")
		check(is_equal_approx(CAMERA.head_tilt(yaw), -CAMERA.head_tilt(-yaw)), "left and right glances must mirror")
	var overhead := reference * Vector3(-0.05, 1, -0.05).normalized()
	var overhead_basis := CAMERA.tracking_basis(overhead, reference, camera.basis, true)
	var held_basis := overhead_basis
	for frame in range(240):
		held_basis = CAMERA.tracking_basis(overhead, reference, held_basis, true)
	check(held_basis.is_finite() and held_basis.y.dot(overhead_basis.y) > 0.9999, "holding an overhead target must not accumulate neck roll")
	# A deliberate view change must own the next camera update. The retained
	# weapon target must not turn the new view back toward the old contact.
	for from_mode in range(CAMERA.Mode.size()):
		for step in [-1, 1]:
			main._jet_view = from_mode
			main._free_look = Vector2(0.4, 0.2)
			tracker.stop_view_tracking()
			tracker.cycle_view_lock([123], camera.position, target_direction)
			check(tracker.tracking_view, "view-change fixture must begin tracking")
			main._cycle_jet_view(step)
			check(not tracker.tracking_view, "switching camera views must release camera tracking")
			check(tracker.locked_handle() == 123, "switching views must retain weapon selection")
			check(main._free_look.is_zero_approx(), "switching views must clear the previous look angle")
			var selected_basis: Basis = camera.basis
			for frame in range(60):
				main._update_jet_camera(1.0 / 60.0)
				main._apply_target_tracking(1.0 / 60.0)
			check((-camera.basis.z).dot(-selected_basis.z) > 0.9999, "old target must not pull the new camera view away")
			if main._jet_view == CAMERA.Mode.COCKPIT:
				check((-camera.basis.z).dot(jet.basis.x) > 0.9999, "returning to FPV must look straight down the nose")
	for mode in [CAMERA.Mode.COCKPIT, CAMERA.Mode.PURSUIT, CAMERA.Mode.TRACK]:
		main._jet_view = mode
		tracker.stop_view_tracking()
		main._free_look = Vector2(0.9, 0.3)
		main._update_jet_camera(0.0, true)
		var start_look: Vector2 = main._free_look
		var previous_forward := -camera.basis.z
		main._on_gamepad_action_pressed(&"camera_travel_toggle")
		check(main._free_look.is_equal_approx(start_look), "R3 must begin a return without instantly clearing the head angle")
		var largest_step := 0.0
		for frame in range(120):
			main._update_free_look(1.0 / 60.0)
			main._update_jet_camera(1.0 / 60.0)
			largest_step = maxf(largest_step, previous_forward.angle_to(-camera.basis.z))
			previous_forward = -camera.basis.z
		check(largest_step < deg_to_rad(8.0), "R3 return must turn smoothly without a single-frame jump")
		check(main._free_look.is_zero_approx(), "R3 return must finish looking forward")
		if mode == CAMERA.Mode.COCKPIT:
			check((-camera.basis.z).dot(jet.basis.x) > 0.9999, "R3 must finish aligned with the aircraft nose")
		# Releasing a tracked view starts from what the pilot actually sees,
		# even though the manual look angles were already zero while tracking.
		tracker.cycle_view_lock([123], camera.position, contact.position - camera.position)
		main._tracking_basis = camera.basis
		for frame in range(120):
			main._apply_target_tracking(1.0 / 60.0)
		previous_forward = -camera.basis.z
		main._on_gamepad_action_pressed(&"camera_travel_toggle")
		check(not tracker.tracking_view and tracker.locked_handle() == 123, "R3 must release camera tracking while retaining weapon lock")
		largest_step = 0.0
		for frame in range(120):
			if frame == 15:
				main._on_gamepad_action_pressed(&"camera_travel_toggle")
			main._update_free_look(1.0 / 60.0)
			main._update_jet_camera(1.0 / 60.0)
			largest_step = maxf(largest_step, previous_forward.angle_to(-camera.basis.z))
			previous_forward = -camera.basis.z
		check(largest_step < deg_to_rad(8.0), "leaving target tracking must ease from the displayed view")
		check(not main._view_returning, "repeated R3 must not restart the return or trigger recovery")
		if mode == CAMERA.Mode.COCKPIT:
			check((-camera.basis.z).dot(jet.basis.x) > 0.9999, "leaving tracking must finish looking straight ahead")
	main._free_look = Vector2(0.6, 0.2)
	main._begin_view_return()
	main._advance_view_return(0.2, Vector2.ZERO)
	var interrupted_look: Vector2 = main._free_look
	check(not main._advance_view_return(0.1, Vector2.RIGHT), "new manual look must take over the return")
	check(not main._view_returning and main._free_look.is_equal_approx(interrupted_look), "manual takeover must retain the current return angle")
	main.status_label.free()
	main.free()
	camera.free()
	jet.free()
	if not failed:
		print("CAMERA_LOOK_MOTION_TEST_PASS")
	quit(1 if failed else 0)
