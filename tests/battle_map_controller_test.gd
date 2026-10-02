extends SceneTree

## The controller's half of the battle map: what a stick means while the map is
## open, which buttons the map is allowed to see, and what R3 does to the camera.
## The production panel is driven so these cover the real routing rather than a
## stand-in that could pass while the shipped map stays dead.

var failed := false


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.set_script(load("res://tests/fixtures/startup_main.gd"))
	root.add_child(main)
	await process_frame
	await process_frame
	var pad = root.get_node("GamepadInput")
	var panel = main._tactical_mfd
	var map = panel.map
	_check_sticks_belong_to_the_aircraft(pad)
	main._on_gamepad_action_pressed(pad.ACTION_TACTICAL_MAP)
	await process_frame
	check(panel.visible and pad._tactical_open, "Y must open the battle map")
	_check_sticks_belong_to_the_map(pad)
	_check_map_motion(pad, map)
	_check_travel_reset(pad, main, map)
	_check_button_gate(pad)
	main._on_gamepad_action_pressed(pad.ACTION_TACTICAL_MAP)
	check(not panel.visible and not pad._tactical_open, "Y must close it again")
	pad.active_device = -1
	pad.set_thumb_controls(false)
	if not failed:
		print("BATTLE_MAP_CONTROLLER_TEST_PASS")
	quit(1 if failed else 0)


func _check_sticks_belong_to_the_aircraft(pad) -> void:
	pad.set_thumb_controls(true)
	pad.set_thumb_input(Vector2(1, 0), Vector2(0, 1), 0.0)
	check(pad.get_flight_vector() != Vector2.ZERO, "flight must read the stick while the map is closed")
	check(pad.get_map_pan_vector() == Vector2.ZERO, "the map must not read the stick while the aircraft is being flown")
	check(pad.get_map_look_vector() == Vector2.ZERO, "likewise the map's rotate and lean")
	check(pad.get_map_zoom_axis() == 0.0, "and the map's zoom")


func _check_sticks_belong_to_the_map(pad) -> void:
	check(pad.get_map_pan_vector().x > 0.9, "the left stick must reach the camera once the map owns it")
	check(pad.get_map_look_vector().y > 0.9, "the right stick must reach the camera once the map owns it")
	check(pad.get_flight_vector() == Vector2.ZERO, "opening the map must hand the sticks over, not share them")


func _check_map_motion(pad, map) -> void:
	map.recenter()
	map.follow_player = false
	map.bearing = 0.0
	map.tilt = 0.0
	pad.set_thumb_input(Vector2(1, 0), Vector2.ZERO, 0.0)
	var centre: Vector2 = map.centre
	map._process(0.1)
	var moved: Vector2 = map.centre - centre
	check(moved.x > 500.0 and absf(moved.y) < 100.0, "pushing the left stick right must look east")
	pad.set_thumb_input(Vector2(-1, 0), Vector2.ZERO, 0.0)
	centre = map.centre
	map._process(0.1)
	check(map.centre.x < centre.x, "the stick must pan back the way it came")
	pad.set_thumb_input(Vector2.ZERO, Vector2(1, 0), 0.0)
	var bearing: float = map.bearing
	map._process(0.1)
	check(fposmod(map.bearing - bearing, TAU) < PI, "the right stick must turn the camera right")
	check(is_equal_approx(map.tilt, 0.0), "a horizontal look must not tilt")
	pad.set_thumb_input(Vector2.ZERO, Vector2(0, -1), 0.0)
	map._process(0.5)
	check(map.tilt > 0.0 and map.tilt <= 1.0472, "pushing the right stick up must lean the map into perspective")
	pad.set_thumb_input(Vector2.ZERO, Vector2(0, 1), 0.0)
	var tilt: float = map.tilt
	map._process(0.5)
	check(map.tilt < tilt, "pulling it back down must flatten the map toward overhead")
	map._process(2.0)
	check(map.tilt == 0.0, "and stop at overhead rather than inverting past it")
	pad.set_thumb_input(Vector2.ZERO, Vector2.ZERO, 0.0)
	centre = map.centre
	map._process(0.1)
	check(map.centre == centre, "a released stick must leave the map alone")


func _check_travel_reset(pad, main, map) -> void:
	map.bearing = 1.2
	map.tilt = 0.8
	map.follow_player = false
	var zoom: float = main._camera_zoom
	var view: int = main._jet_view
	main._on_gamepad_action_pressed(pad.ACTION_CAMERA_TRAVEL_TOGGLE)
	var seconds := 0.0
	while seconds < 1.6:
		map._process(1.0 / 60.0)
		seconds += 1.0 / 60.0
	check(cos(map.bearing) > 0.9999, "R3 must bring the map back to north-up")
	check(map.tilt >= 0.0 and map.tilt < 0.001, "and back to overhead")
	check(map.follow_player, "R3 must give the camera back to the ownship")
	check(main._camera_zoom == zoom and main._jet_view == view, "the map's reset must not touch the flight camera")


func _check_button_gate(pad) -> void:
	# A pad cannot be attached headless, so what is asserted here is the poll's
	# bookkeeping: the map keeps the two buttons it can act on and forgets the
	# rest, so a weapon or a target cannot fire through the open panel.
	pad.active_device = 0
	pad.set_tactical_open(true)
	pad._process(0.016)
	check(pad._pressed_actions.has(pad.ACTION_TACTICAL_MAP), "the button that closes the map must stay live")
	check(pad._pressed_actions.has(pad.ACTION_CAMERA_TRAVEL_TOGGLE), "so must the button that resets the view")
	for blocked in [pad.ACTION_WEAPON_CYCLE, pad.ACTION_TRACK_TARGET, pad.ACTION_TARGET_NEXT, pad.ACTION_CONTEXT]:
		check(not pad._pressed_actions.has(blocked), "%s must be dropped while the map owns the screen" % blocked)
	pad.set_tactical_open(false)
	pad._process(0.016)
	check(pad._pressed_actions.size() == pad.BUTTON_ACTIONS.size(), "closing the map must give every button back")
