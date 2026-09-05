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
	_assert_axis(&"rudder_left", JoyAxis.JOY_AXIS_TRIGGER_LEFT, 1.0)
	_assert_axis(&"rudder_right", JoyAxis.JOY_AXIS_TRIGGER_RIGHT, 1.0)
	# The panel's buttons are unreachable with a controller, so their actions
	# have to exist on the pad.
	# B stays available for menu cancellation. Y opens the tactical map. Nothing of OURS may claim them. Godot's
	# own ui_* actions bind B to ui_cancel and Y to ui_select by default; those
	# are the engine's, never fire in flight, and are not what this guards.
	for button in [JoyButton.JOY_BUTTON_B]:
		for action in InputMap.get_actions():
			if String(action).begins_with("ui_"):
				continue
			for event in InputMap.action_get_events(action):
				if event is InputEventJoypadButton and event.button_index == button:
					assert(false, "%s must stay unbound, %s claims it" % [button, action])
	# X taps to cycle weapons and holds for settings, so the settings action is
	# no longer bound to a button -- main.gd raises it from the hold, and the
	# on-screen SETTINGS button still emits it.
	_assert_button(&"tactical_map", JoyButton.JOY_BUTTON_Y)
	_assert_button(&"weapon_cycle", JoyButton.JOY_BUTTON_X)
	_assert_button(&"free_look", JoyButton.JOY_BUTTON_A)
	_assert_button(&"track_target", JoyButton.JOY_BUTTON_RIGHT_SHOULDER)
	_assert_button(&"weapon_cannon", JoyButton.JOY_BUTTON_LEFT_STICK)
	_assert_button(&"weapon_rockets", JoyButton.JOY_BUTTON_LEFT_SHOULDER)
	_assert_button(&"camera_travel_toggle", JoyButton.JOY_BUTTON_RIGHT_STICK)
	_assert_button(&"context_extract", JoyButton.JOY_BUTTON_A)
	_assert_button(&"target_previous", JoyButton.JOY_BUTTON_DPAD_LEFT)
	_assert_button(&"target_next", JoyButton.JOY_BUTTON_DPAD_RIGHT)
	_assert_button(&"camera_zoom_in", JoyButton.JOY_BUTTON_DPAD_UP)
	_assert_button(&"camera_zoom_out", JoyButton.JOY_BUTTON_DPAD_DOWN)
	assert(
		service.apply_response_curve(Vector2(0.1, 0.0)).is_equal_approx(Vector2(0.1, 0.0)),
		"post-deadzone response must not apply a second deadzone"
	)
	assert(service.apply_circular_deadzone(Vector2(0.1, 0.0)) == Vector2.ZERO)
	var half_stick: Vector2 = service.apply_circular_deadzone(Vector2(0.5, 0.0))
	assert(half_stick.x > 0.38 and half_stick.x < 0.40, "half stick must survive the single deadzone")
	assert(
		service.controller_preference_score("DualSense Wireless Controller") \
		> service.controller_preference_score("Virtual Gamepad"),
		"physical PlayStation controller must win over Android virtual devices"
	)
	assert(service.apply_response_curve(Vector2.RIGHT).is_equal_approx(Vector2.RIGHT))
	assert(
		service.route_aim_input_to_flight(Vector2(0.75, -0.5), true) == Vector2.ZERO,
		"free look must own the right stick instead of also steering the aircraft"
	)
	assert(
		service.route_aim_input_to_flight(Vector2(0.75, -0.5), false).is_equal_approx(Vector2(0.75, -0.5)),
		"right-stick flight controls must resume when free look is released"
	)
	_assert_button(&"throttle_modifier", JoyButton.JOY_BUTTON_GUIDE)
	_assert_button(&"throttle_up", JoyButton.JOY_BUTTON_DPAD_UP)
	_assert_button(&"throttle_down", JoyButton.JOY_BUTTON_DPAD_DOWN)
	assert(service.normalized_trigger(0.0, 0.0) == 0.0)
	assert(service.normalized_trigger(-1.0, -1.0) == 0.0)
	assert(service.normalized_trigger(1.0, 0.0) == 1.0)
	assert(service.normalized_trigger(1.0, -1.0) == 1.0)

	# X carries two jobs separated by time: a tap cycles weapons, a hold opens
	# settings. The discrimination is a pure function of how long the button was
	# down, so it is testable without a controller attached.
	assert(
		service.is_hold(service.SETTINGS_HOLD_SECONDS + 0.05),
		"a press past the threshold must count as a hold"
	)
	assert(
		not service.is_hold(service.SETTINGS_HOLD_SECONDS - 0.05),
		"a press short of the threshold must count as a tap"
	)
	assert(not service.is_hold(0.0), "an instant release must be a tap")
	assert(
		service.SETTINGS_HOLD_SECONDS <= 0.6,
		"the hold threshold must stay short enough to cycle weapons quickly"
	)
	assert(
		service.SETTINGS_HOLD_SECONDS >= 0.3,
		"a threshold this short would open settings on an ordinary tap"
	)

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
