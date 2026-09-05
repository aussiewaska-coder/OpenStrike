extends SceneTree

const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const NAV := preload("res://scripts/ui/tactical_navigation.gd")
const WAYPOINT := preload("res://scripts/ui/waypoint_hud.gd")
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _init() -> void:
	call_deferred("_run")

func _touch(index: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--visual-out=") and DisplayServer.get_name() != "headless":
			await _render(arg.trim_prefix("--visual-out="))
			if not failed:
				print("TACTICAL_MFD_TEST_PASS")
			quit(1 if failed else 0)
			return
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.set_script(load("res://tests/fixtures/startup_main.gd"))
	root.add_child(main)
	await process_frame
	await process_frame
	var pad := root.get_node("GamepadInput")
	var mfd = main._tactical_mfd
	main._on_gamepad_action_pressed(pad.ACTION_TACTICAL_MAP)
	await process_frame
	check(mfd.visible and paused and pad._tactical_open, "Y must open the production tactical map and pause flight")
	check(not pad.is_cannon_firing() and pad.get_flight_vector() == Vector2.ZERO, "map interaction must suppress flight controls and weapons")
	var rotation: float = mfd.map._sweep
	mfd.map._process(0.5)
	check(not is_equal_approx(rotation, mfd.map._sweep), "radar sweep must animate while flight is paused")
	var zoom: float = main._camera_zoom
	var view: int = main._jet_view
	main._on_gamepad_action_pressed(pad.ACTION_ZOOM_IN)
	main._on_gamepad_action_pressed(pad.ACTION_TARGET_NEXT)
	main._on_gamepad_action_released(pad.ACTION_WEAPON_CYCLE, 0.5)
	check(main._camera_zoom == zoom and main._jet_view == view and not main.settings_panel.visible, "MFD controls must not alter the flight camera or open Settings")
	main._on_gamepad_action_pressed(pad.ACTION_TACTICAL_MAP)
	check(not mfd.visible and not paused, "Y must close the map and resume flight")
	check(mfd.map.layers.is_empty() and mfd.map._height_texture == null, "closing the map must release its references to streamed textures")
	main._toggle_tactical_map()
	pad._paused_for_controller = true
	mfd.close_panel()
	check(paused, "closing the map must preserve the controller disconnect pause")
	pad._paused_for_controller = false
	pad.set_tactical_open(false)
	main._toggle_tactical_map()
	pad._paused_for_controller = true
	pad._set_active_controller(0)
	check(paused, "controller reconnect must preserve the open map's pause")
	pad.active_device = -1
	pad._had_controller = false
	var origin: Vector3 = main._vehicle().global_position
	var contacts := [TRACKER.contact(77, TRACKER.Kind.AIR_JET, origin + Vector3(2000, 0, -3000), Vector3.ZERO, "BANDIT 01"), TRACKER.contact(78, TRACKER.Kind.GROUND_LAUNCHER, origin + Vector3(-1500, -900, 1000), Vector3.ZERO, "SAM 02")]
	main._tracker.update(contacts, origin, Vector3.FORWARD, Vector3.ZERO)
	main._tracker.tracking_view = true
	main._sync_tactical_state()
	mfd.map.recenter()
	for range_m in [500.0, 10000.0, 80000.0]:
		mfd.map.set_range(range_m)
		var world := Vector2(2345, -3210)
		check(mfd.map.screen_to_world(mfd.map.world_to_screen(world)).distance_to(world) < 0.05, "map picking must invert projection at every range")
	mfd.map.set_range(5000)
	var contact_point: Vector3 = contacts[0].position
	mfd.map.select_at(mfd.map.world_to_screen(Vector2(contact_point.x, contact_point.z)))
	check(main._tracker.locked_handle() == 77 and main._has_target_point and not main._tracker.tracking_view, "touching a contact must set the real weapon lock without forcing camera tracking")
	main._tracker.remove_contact(77)
	main._select_map_contact(77)
	check(main._tracker.locked_handle() == -1, "a destroyed contact must not be selectable from a stale map snapshot")
	main._tracker.update([TRACKER.contact(90, TRACKER.Kind.AIR_JET, origin + Vector3(60000, 0, 0))], origin, Vector3.FORWARD, Vector3.ZERO)
	check(not main._tracker.select_contact(90), "map selection must respect the normal weapon lock break range")
	var anchor := Vector2(90, 100)
	var anchored: Vector2 = mfd.map.screen_to_world(anchor)
	mfd.map.set_range(2500, anchor)
	check(mfd.map.screen_to_world(anchor).distance_to(anchored) < 0.05, "touch zoom must preserve the point under its anchor")
	mfd.map.set_range(1)
	check(mfd.map.range_m == 500, "zoom must have a safe minimum")
	mfd.map.set_range(999999)
	check(mfd.map.range_m == 80000, "zoom must have a safe maximum")
	mfd.map.set_range(5000)
	mfd.map.recenter()
	mfd._toggle_waypoint()
	var tap: Vector2 = mfd.map.size * Vector2(0.65, 0.35)
	var desired: Vector2 = mfd.map.screen_to_world(tap)
	mfd.map._gui_input(_touch(0, true, tap))
	mfd.map._gui_input(_touch(0, false, tap))
	check(main._navigation.points.size() == 1, "a touch tap in waypoint mode must append exactly one waypoint")
	check(Vector2(main._navigation.points[0].x, main._navigation.points[0].z).distance_to(desired) < 0.05, "waypoint must use the selected world coordinate")
	mfd.map._gui_input(_touch(0, true, Vector2(60, 70)))
	mfd.map._gui_input(_touch(1, true, Vector2(160, 70)))
	var before: float = mfd.map.range_m
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(260, 70)
	drag.relative = Vector2(100, 0)
	mfd.map._gui_input(drag)
	mfd.map._gui_input(_touch(0, false, Vector2(60, 70)))
	mfd.map._gui_input(_touch(1, false, Vector2(260, 70)))
	check(mfd.map.range_m < before and main._navigation.points.size() == 1, "pinching must zoom without creating accidental waypoints")
	mfd.map._gui_input(_touch(0, true, Vector2(90, 90)))
	drag.index = 0
	drag.position = Vector2(130, 120)
	drag.relative = Vector2(40, 30)
	var centre: Vector2 = mfd.map.centre
	mfd.map._gui_input(drag)
	mfd.map._gui_input(_touch(0, false, drag.position))
	check(not mfd.map.follow_player and mfd.map.centre != centre and main._navigation.points.size() == 1, "dragging must pan rather than select")
	mfd.map.recenter()
	check(mfd.map.follow_player and mfd.map.centre.distance_to(Vector2(origin.x, origin.z)) < 0.05, "Ownship must restore player following")
	main._add_map_waypoint(Vector2(1000000, 1000000))
	check(main._navigation.points.size() == 1, "waypoints outside the theatre must be rejected")
	main._sync_tactical_state()
	for mode in range(main.JET_CAMERA.Mode.size()):
		main._jet_view = mode
		main._apply_view_chrome()
		check(main._waypoint_hud.visible and not main._waypoint_hud.route.points.is_empty(), "waypoint guidance must remain enabled in cockpit and every external view")
	var route := NAV.new()
	route.add(Vector3(1000, 0, 0))
	route.add(Vector3(2000, 0, 0))
	check(not route.advance(Vector3.ZERO), "route must not skip distant waypoints")
	check(route.advance(Vector3(950, 1000, 0)) and route.points[0].x == 2000 and route.completed == 1, "passing over a waypoint must advance to the next leg independent of altitude")
	check(is_equal_approx(NAV.bearing(Vector3.ZERO, Vector3(100, 0, 0)), 90), "HUD bearings must use north-up compass degrees")
	var edge := WAYPOINT.edge_position(Vector3(0, 0, 100), Vector2(640, 360))
	check(edge.is_finite() and Rect2(Vector2.ZERO, Vector2(640, 360)).has_point(edge), "a waypoint directly behind must have a finite on-screen direction cue")
	check(edge.y <= 260, "waypoint edge arrows must leave room above the persistent navigation readout")
	for viewport_size in [Vector2i(640, 360), Vector2i(360, 640), Vector2i(1280, 720)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		await process_frame
		await process_frame
		check(mfd.get_global_rect().encloses(mfd._close.get_global_rect()), "Close must stay visible at every viewport size")
		for button in mfd._range_buttons:
			check(mfd.get_global_rect().encloses(button.get_global_rect()), "all fixed range keys must fit on screen")
		check(mfd.map.size.x >= 100 and mfd.map.size.y >= 100 and mfd.get_global_rect().encloses(mfd.map.get_global_rect()), "the touchscreen map must retain a usable area")
	mfd.close_panel()
	main.free()
	paused = false
	if not failed:
		print("TACTICAL_MFD_TEST_PASS")
	quit(1 if failed else 0)

func _render(output: String) -> void:
	var mfd := preload("res://scripts/ui/tactical_mfd.gd").new()
	root.add_child(mfd)
	var height := Image.create(128, 128, false, Image.FORMAT_RF)
	var aerial := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in range(128):
		for x in range(128):
			var h := maxf(0, sin(float(x) * 0.035) * cos(float(y) * 0.022))
			height.set_pixel(x, y, Color(h, 0, 0))
			aerial.set_pixel(x, y, Color(0.11 + h * 0.15, 0.20 + h * 0.18, 0.13 + h * 0.04))
	# Optional local aerial capture; no network is needed for visual tests.
	var image_path := "user://map_cache/aerial_qld_153p395545_-28p026101_153p426089_-27p999152_2048.jpg"
	if FileAccess.file_exists(image_path):
		var cached := Image.load_from_file(image_path)
		if cached != null:
			aerial = cached
	mfd.map.set_layers({"world_size_m": 12000.0, "height": height, "aerial": ImageTexture.create_from_image(aerial), "metadata": {"elevation_min_m": -10.0, "elevation_max_m": 1400.0}})
	var route := NAV.new()
	route.add(Vector3(900, 0, -1400))
	route.add(Vector3(2300, 0, -3200))
	mfd.map.set_state(Vector3.ZERO, 0.45, [TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(-1600, 900, -1700), Vector3.ZERO, "BANDIT 01"), TRACKER.contact(2, TRACKER.Kind.GROUND_LAUNCHER, Vector3(1600, 0, 1800), Vector3.ZERO, "SAM 02")], 1, route)
	mfd.open_panel()
	mfd.map.set_range(5000)
	for viewport_size in [Vector2i(1280, 720), Vector2i(640, 360), Vector2i(360, 640)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		await process_frame
		await process_frame
		for style in range(3):
			mfd._set_style(style)
			await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("%s-%d-%d.png" % [output, viewport_size.x, style]) == OK, "MFD visual capture must save")
	mfd.free()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 900, 0)
	camera.current = true
	var hud := WAYPOINT.new()
	root.add_child(hud)
	route.clear()
	route.add(Vector3(300, 0, -3000))
	root.content_scale_size = Vector2i(960, 540)
	root.size = Vector2i(960, 540)
	for angle in [0.0, PI]:
		camera.rotation.y = angle
		hud.set_state(camera, camera.position, route)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("%s-guidance-%d.png" % [output, int(angle)]) == OK, "waypoint HUD visual capture must save")
	hud.free()
	camera.free()
