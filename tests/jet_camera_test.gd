extends SceneTree

const JET_CAMERA := preload("res://scripts/camera/jet_camera.gd")


func _init() -> void:
	assert(
		is_zero_approx(JET_CAMERA.routed_orbit_input(0.8, true, false)),
		"the F-22 throttle triggers must not also move the camera"
	)
	assert(
		is_zero_approx(JET_CAMERA.routed_orbit_input(-0.8, false, true)),
		"helicopter target orbit must own the triggers before the camera"
	)
	assert(
		is_equal_approx(JET_CAMERA.routed_orbit_input(0.65, false, false), 0.65),
		"free helicopter triggers must still sweep the camera"
	)
	assert(
		is_equal_approx(JET_CAMERA.trailing_distance(175.0, 90.0, 260.0, 42.0, 26.0), 55.0),
		"the jet chase distance must retain its speed response"
	)
	var moved := JET_CAMERA.updated_look(Vector2.ZERO, Vector2(0.5, -0.25), 2.0, 6.0, 0.5)
	assert(moved.is_equal_approx(Vector2(-0.5, 0.25)), "right stick must move the jet camera look")
	# The cockpit view HOLDS. A head does not spring back to the panel when you
	# stop turning it, and a view that does makes checking six impossible.
	var returned := JET_CAMERA.updated_look(moved, Vector2.ZERO, 2.0, 6.0, 0.5)
	assert(returned.is_equal_approx(moved), "released right stick must hold the cockpit view")
	assert(JET_CAMERA.is_look_displaced(moved), "a turned head must be reported as displaced")
	assert(
		not JET_CAMERA.is_look_displaced(Vector2.ZERO),
		"a centred view must not claim the recentre button"
	)
	var wrapped := JET_CAMERA.updated_external_look(
		Vector2(0.9, 0.0), Vector2(-1.0, 0.0), 2.0, 6.0, 0.2
	)
	assert(wrapped.x < -0.6, "external yaw must wrap through 180 degrees for continuous orbit")
	assert(absf(wrapped.y) <= 1.0, "external orbit pitch must remain bounded")
	var held_orbit := JET_CAMERA.updated_external_look(
		wrapped, Vector2.ZERO, 2.0, 6.0, 1.0
	)
	assert(held_orbit.is_equal_approx(wrapped), "released external stick must hold the current orbit")
	var focus := Vector3(10.0, 20.0, 30.0)
	var behind := focus + Vector3(0.0, 4.0, 20.0)
	var orbited := JET_CAMERA.orbited_position(focus, behind, Basis(Vector3.UP, PI * 0.5))
	assert(is_equal_approx(orbited.distance_to(focus), behind.distance_to(focus)), "look orbit must preserve camera distance")
	# A sphere: orbiting moves the camera and must not change the radius. It used
	# to stretch the pursuit boom 1.65x as the look grew, which is what made the
	# 360 read as warped rather than as a camera going round a fixed object.
	var boom := focus + Vector3(0.0, 3.0, 20.0)
	for look_amount in [0.0, 0.35, 0.75, 1.0]:
		var sphere := JET_CAMERA.external_orbit_position(
			JET_CAMERA.Mode.PURSUIT,
			focus,
			boom,
			Basis(Vector3.UP, PI * 0.5),
			Vector2(look_amount, 0.0)
		)
		assert(
			is_equal_approx(sphere.distance_to(focus), boom.distance_to(focus)),
			"orbit radius must not change with look amount"
		)
	assert(JET_CAMERA.Mode.size() == 4, "the F-22 must expose cockpit plus three external views")
	var direction := JET_CAMERA.flight_direction(Vector3(20.0, 100.0, -100.0), Vector3.RIGHT, 35.0)
	assert(direction.y > 0.3, "pursuit direction must follow a real climb")
	assert(direction.y <= sin(deg_to_rad(35.0)) + 0.001, "camera pitch must remain arcade-readable")
	var follow := JET_CAMERA.desired_position(JET_CAMERA.Mode.PURSUIT, focus, direction, 50.0, 12.0)
	var track := JET_CAMERA.desired_position(JET_CAMERA.Mode.TRACK, focus, direction, 50.0, 12.0)
	var isometric := JET_CAMERA.desired_position(JET_CAMERA.Mode.ISOMETRIC, focus, direction, 50.0, 12.0)
	assert(follow.distance_to(focus) < 30.0, "pursuit must be a close aircraft view")
	assert(track.distance_to(focus) > follow.distance_to(focus), "tracking view must frame more of the aircraft's path")
	assert(isometric.x > focus.x and isometric.z > focus.z, "isometric view must keep a fixed world diagonal")
	var pursuit_look := JET_CAMERA.look_target(
		JET_CAMERA.Mode.PURSUIT, focus, Vector3(0.0, 20.0, -180.0), direction, 50.0
	)
	assert(pursuit_look.z < focus.z, "pursuit composition must look ahead of the aircraft")
	# The cockpit's default lens is also its tightest: it opens up as the player
	# zooms OUT past neutral and never narrows, because the seat cannot move
	# forward and zooming in would only push the view through the canopy.
	var cockpit_fov := JET_CAMERA.field_of_view(JET_CAMERA.Mode.COCKPIT, 1.0, 0.5, 1.45)
	assert(cockpit_fov >= 68.0 and cockpit_fov <= 72.0, "cockpit needs a natural human-scale perspective")
	assert(
		is_equal_approx(
			JET_CAMERA.field_of_view(JET_CAMERA.Mode.COCKPIT, 0.17, 0.5, 1.45),
			cockpit_fov
		),
		"zooming in must not narrow the cockpit past its default"
	)
	var cockpit_wide := JET_CAMERA.field_of_view(JET_CAMERA.Mode.COCKPIT, 1.45, 0.5, 1.45)
	assert(cockpit_wide > cockpit_fov + 20.0, "zooming out must open the cockpit view up")
	assert(cockpit_wide <= 102.0, "the cockpit must not open into a fisheye")

	# Head bob: low frequency and sub-degree, and it must grow with G rather
	# than run as constant noise. The previous buffet attempt was torn out for
	# making the cockpit jitter, so amplitude is asserted, not just presence.
	var unloaded := JET_CAMERA.head_bob(0.3, 1.0, 0.0)
	assert(unloaded.is_zero_approx(), "an unloaded aircraft sitting still must not bob")
	var pulling := JET_CAMERA.head_bob(0.3, 6.0, 0.8)
	assert(not pulling.is_zero_approx(), "a hard pull must be felt in the seat")
	for sample in [0.0, 0.13, 0.37, 0.61, 0.9, 1.4, 2.2]:
		var bob := JET_CAMERA.head_bob(sample, 9.0, 1.0)
		assert(absf(bob.x) <= 0.3, "head bob pitch must stay sub-degree, got %f" % bob.x)
		assert(absf(bob.y) <= 0.2, "head bob roll must stay sub-degree, got %f" % bob.y)
	assert(
		JET_CAMERA.field_of_view(JET_CAMERA.Mode.PURSUIT, 1.0, 0.5, 1.45)
		> JET_CAMERA.field_of_view(JET_CAMERA.Mode.TRACK, 1.0, 0.5, 1.45),
		"pursuit must be wider and faster-looking than tracking"
	)
	var banked_up := Vector3.RIGHT
	assert(
		JET_CAMERA.camera_up(JET_CAMERA.Mode.COCKPIT, banked_up).is_equal_approx(banked_up),
		"cockpit must inherit full aircraft bank"
	)
	var pursuit_up := JET_CAMERA.camera_up(JET_CAMERA.Mode.PURSUIT, banked_up)
	assert(pursuit_up.y > pursuit_up.x, "external pursuit must show bank without rolling the horizon over")
	assert(
		JET_CAMERA.aim_response(JET_CAMERA.Mode.PURSUIT)
		> JET_CAMERA.position_response(JET_CAMERA.Mode.PURSUIT),
		"the aim spring must settle before the camera body"
	)
	assert(not JET_CAMERA.allows_free_look(JET_CAMERA.Mode.ISOMETRIC), "ground lock must not orbit with right-stick look")
	print("JET_CAMERA_TEST_PASS")
	quit()
