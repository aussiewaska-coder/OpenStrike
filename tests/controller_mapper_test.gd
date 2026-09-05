extends SceneTree

const LAYOUT := preload("res://scripts/input/controller_bindings.gd")
class FakePad:
	extends "res://scripts/input/gamepad_input.gd"
	var axes := {}
	var buttons := {}
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		active_device = 2
		active_device_name = "Test controller"
		bindings_path = "user://controller_mapper_test.cfg"
		_register_input_actions()
		set_process(false)
	func is_controller_ready() -> bool:
		return active_device >= 0
	func _read_axis(index: int) -> float:
		return axes.get(index, 0.0)
	func _read_button(index: int) -> bool:
		return buttons.get(index, false)

var failed := false
func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _init() -> void:
	call_deferred("_run")

func _button(index: int, pressed: bool, device := 2) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = index
	event.pressed = pressed
	return event

func _axis(index: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 2
	event.axis = index
	event.axis_value = value
	return event

func _run() -> void:
	var old := root.get_node("GamepadInput")
	root.remove_child(old)
	var pad := FakePad.new()
	pad.name = "GamepadInput"
	root.add_child(pad)
	var panel = load("res://scripts/ui/settings_panel.gd").new()
	root.add_child(panel)
	panel.open_changed.connect(pad.set_settings_open)
	panel.open_panel()
	panel._select_page(4)
	await process_frame
	await process_frame
	var mapper = panel._mapper
	check(pad.mapper_active and paused, "controller page must suppress flight actions while keeping the menu paused")
	mapper._action.select(11) # Cannon.
	mapper._refresh()
	mapper.begin_capture()
	root.push_input(_button(JOY_BUTTON_A, true))
	check(mapper._pending.is_empty(), "the button that opens Detect must not become the binding")
	mapper._arm_at = 0
	root.push_input(_button(JOY_BUTTON_Y, true, 3))
	check(mapper._pending.is_empty(), "ignore other controllers during detection")
	root.push_input(_axis(JOY_AXIS_LEFT_X, 0.12))
	check(mapper._pending.is_empty(), "stick drift must not become a binding")
	root.push_input(_button(JOY_BUTTON_B, true))
	check(panel.visible and mapper._pending.get("index") == JOY_BUTTON_B, "B must be detected without closing Settings")
	mapper._diagram_selected({"type": "button", "index": JOY_BUTTON_Y})
	check(mapper._pending.get("index") == JOY_BUTTON_B, "touching the diagram during a held capture must not change the input whose release is awaited")
	root.push_input(_button(JOY_BUTTON_B, false))
	mapper._save()
	check(pad.bindings.values.weapon_cannon == {"type": "button", "index": JOY_BUTTON_B}, "saving must update the actual cannon binding")
	var reloaded := LAYOUT.new()
	check(reloaded.load_from(pad.bindings_path) == OK and reloaded.values.weapon_cannon.index == JOY_BUTTON_B, "custom binding must survive reloading from disk")
	pad.buttons[JOY_BUTTON_B] = true
	check(not pad.is_cannon_firing(), "mapped fire must remain suppressed in Settings")
	panel.close_panel()
	check(pad.is_cannon_firing(), "flight must use the newly mapped fire button")
	pad.buttons.clear()
	pad.buttons[JOY_BUTTON_LEFT_STICK] = true
	check(not pad.is_cannon_firing(), "the old fire button must no longer fire")
	pad.buttons.clear()
	pad.bindings.values.free_look = {"type": "button", "index": JOY_BUTTON_Y}
	pad.buttons[JOY_BUTTON_Y] = true
	pad.axes[JOY_AXIS_RIGHT_Y] = -1.0
	check(pad.is_free_look_held() and pad.get_jet_throttle_axis() > 0.99 and pad.get_jet_look_vector() == Vector2.ZERO, "custom throttle modifier must replace the hardcoded A button")
	pad.bindings.values.flight_right = {"type": "axis", "index": JOY_AXIS_RIGHT_X, "sign": -1}
	pad.axes[JOY_AXIS_RIGHT_X] = -1.0
	check(pad.get_flight_vector().x > 0.99, "flight must use a remapped and inverted stick direction")
	pad.bindings.values.rudder_left = {"type": "button", "index": JOY_BUTTON_Y}
	pad.bindings.values.rudder_right = {"type": "button", "index": JOY_BUTTON_B}
	check(pad.get_rudder_axis() < -0.99, "rudder must use custom input")
	pad.buttons[JOY_BUTTON_B] = true
	check(pad.is_vectoring_held(), "both remapped pedals must still engage vectoring")
	pad.axes.clear()
	pad.buttons.clear()
	panel.open_panel()
	mapper.begin_capture()
	mapper._arm_at = 0
	root.push_input(_axis(JOY_AXIS_RIGHT_Y, -0.9))
	check(mapper._pending == {"type": "axis", "index": JOY_AXIS_RIGHT_Y, "sign": -1}, "detect the direction of a moved stick")
	root.push_input(_axis(JOY_AXIS_RIGHT_Y, 0.0))
	mapper.cancel_capture()
	pad._left_trigger_rest = -1.0
	pad.axes[JOY_AXIS_TRIGGER_LEFT] = -1.0
	mapper.begin_capture()
	mapper._arm_at = 0
	root.push_input(_axis(JOY_AXIS_TRIGGER_LEFT, -1.0))
	check(mapper._pending.is_empty(), "signed trigger rest must not bind as a negative axis")
	root.push_input(_axis(JOY_AXIS_TRIGGER_LEFT, 0.9))
	check(mapper._pending == {"type": "axis", "index": JOY_AXIS_TRIGGER_LEFT, "sign": 1}, "signed trigger squeeze must bind positive pressure")
	root.push_input(_axis(JOY_AXIS_TRIGGER_LEFT, -1.0))
	mapper.cancel_capture()
	mapper._offer_binding({"type": "button", "index": JOY_BUTTON_Y})
	check(mapper._status.text.contains("Also used by"), "shared binding must be explained before saving")
	mapper.cancel_capture()
	check(pad.bindings.values.weapon_cannon.index == JOY_BUTTON_B, "cancel must preserve the previous binding")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = mapper._diagram._offset() + Vector2(115, 28) * mapper._diagram._scale_factor()
	mapper._diagram._gui_input(click)
	check(mapper._pending == {"type": "button", "index": JOY_BUTTON_LEFT_SHOULDER}, "the graphical shoulder control must preview its physical binding")
	mapper.cancel_capture()
	mapper.begin_capture()
	pad.active_device = -1
	pad.connection_changed.emit(false, -1, "")
	check(not mapper._listening and mapper._pending.is_empty(), "disconnect must cancel detection")
	pad.active_device = 2
	mapper._request_reset()
	mapper._save()
	check(pad.bindings.values == LAYOUT.new().values, "restore defaults must restore the entire layout")
	check(not LAYOUT.valid({"type": "button", "index": 900}), "invalid saved indices must not reach the input backend")
	var previous := pad.bindings.values.duplicate(true)
	pad.bindings_path = "user://missing_mapper_folder/bindings.cfg"
	check(pad.save_binding("weapon_cannon", {"type": "button", "index": JOY_BUTTON_B}) != OK and pad.bindings.values == previous, "save failure must preserve the active layout")
	pad.bindings_path = "user://controller_mapper_test.cfg"
	var partial := ConfigFile.new()
	partial.set_value("bindings", "weapon_cannon", {"type": "button", "index": 900})
	partial.set_value("bindings", "track_target", {"type": "button", "index": JOY_BUTTON_Y})
	partial.save(pad.bindings_path)
	reloaded.load_from(pad.bindings_path)
	check(reloaded.values.weapon_cannon.index == JOY_BUTTON_LEFT_STICK and reloaded.values.track_target.index == JOY_BUTTON_Y, "partial profiles must restore invalid entries to defaults and keep valid custom entries")
	for viewport_size in [Vector2i(640, 360), Vector2i(360, 640), Vector2i(1280, 720)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		await process_frame
		await process_frame
		check(panel._scroll.size.y >= 80, "controller page must retain a useful scroll area")
		for tab in panel._tabs:
			check(panel.get_global_rect().encloses(tab.get_global_rect()), "all five settings tabs must fit on narrow screens")
		check(mapper.size.x <= panel.size.x, "mapper must not overflow the screen horizontally")
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--visual-out=") and DisplayServer.get_name() != "headless":
				panel._scroll.scroll_vertical = 0
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s-%d.png" % [arg.trim_prefix("--visual-out="), viewport_size.x])
	panel.close_panel()
	panel.free()
	pad.free()
	root.add_child(old)
	old.bindings.apply_input_map()
	DirAccess.remove_absolute("user://controller_mapper_test.cfg")
	paused = false
	if not failed:
		print("CONTROLLER_MAPPER_TEST_PASS")
	quit(1 if failed else 0)
