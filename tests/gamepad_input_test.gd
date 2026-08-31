extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service: Node = root.get_node_or_null("GamepadInput")
	if service == null:
		service = load("res://scripts/input/gamepad_input.gd").new()
		root.add_child(service)
	await process_frame
	_assert_axis(&"flight_left", JoyAxis.JOY_AXIS_LEFT_X, -1.0)
	_assert_axis(&"flight_right", JoyAxis.JOY_AXIS_LEFT_X, 1.0)
	_assert_axis(&"flight_forward", JoyAxis.JOY_AXIS_LEFT_Y, -1.0)
	_assert_axis(&"flight_back", JoyAxis.JOY_AXIS_LEFT_Y, 1.0)
	_assert_axis(&"aim_left", JoyAxis.JOY_AXIS_RIGHT_X, -1.0)
	_assert_axis(&"aim_right", JoyAxis.JOY_AXIS_RIGHT_X, 1.0)
	_assert_axis(&"camera_orbit_left", JoyAxis.JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_assert_axis(&"camera_orbit_right", JoyAxis.JOY_AXIS_TRIGGER_LEFT, 1.0)
	_assert_button(&"weapon_cannon", JoyButton.JOY_BUTTON_RIGHT_SHOULDER)
	_assert_button(&"weapon_rockets", JoyButton.JOY_BUTTON_LEFT_SHOULDER)
	_assert_button(&"camera_travel_toggle", JoyButton.JOY_BUTTON_RIGHT_STICK)
	_assert_button(&"context_extract", JoyButton.JOY_BUTTON_LEFT_STICK)
	_assert_button(&"target_previous", JoyButton.JOY_BUTTON_DPAD_LEFT)
	_assert_button(&"target_next", JoyButton.JOY_BUTTON_DPAD_RIGHT)
	_assert_button(&"camera_zoom_in", JoyButton.JOY_BUTTON_DPAD_UP)
	_assert_button(&"camera_zoom_out", JoyButton.JOY_BUTTON_DPAD_DOWN)
	assert(service.apply_response_curve(Vector2(0.1, 0.0)) == Vector2.ZERO)
	assert(service.apply_response_curve(Vector2.RIGHT).is_equal_approx(Vector2.RIGHT))
	print("GAMEPAD_INPUT_TEST_PASS")
	quit()


func _assert_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.axis == axis and is_equal_approx(event.axis_value, value):
			assert(event.device == -1, "%s must accept every controller device" % action)
			return
	assert(false, "Missing axis mapping for %s" % action)


func _assert_button(action: StringName, button: JoyButton) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button:
			assert(event.device == -1, "%s must accept every controller device" % action)
			return
	assert(false, "Missing button mapping for %s" % action)
