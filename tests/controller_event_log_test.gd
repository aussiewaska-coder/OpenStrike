extends SceneTree
func _init(): call_deferred("_run")
func _run():
	var pad := root.get_node("GamepadInput")
	pad.active_device = 2
	pad._button_events.clear()
	# Synthetic sequence validates transport only; button 16 is not a claimed
	# mapping for the user's Turbo button.
	for index in [4,5,6,16,5]:
		for pressed in [true,false]:
			var event := InputEventJoypadButton.new()
			event.device = 2
			event.button_index = index
			event.pressed = pressed
			pad._input(event)
	var report: Dictionary = pad.controller_input_report()
	assert(report.controller_button_events.size() == 10, "quick taps between telemetry samples must survive")
	assert(report.controller_button_events[6].button == 16)
	assert(report.controller_button_events[8].button == 5)
	var unrelated := InputEventJoypadButton.new()
	unrelated.device = 3
	pad._input(unrelated)
	assert(pad._button_events.size() == 10, "ignore other pads")
	for i in range(50):
		unrelated.device = 2
		pad._input(unrelated)
	assert(pad._button_events.size() == 32, "event history must be bounded")
	print("CONTROLLER_EVENT_LOG_TEST_PASS")
	quit()
