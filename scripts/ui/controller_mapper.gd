extends VBoxContainer

signal focus_layout_changed
const BINDINGS := preload("res://scripts/input/controller_bindings.gd")
const DIAGRAM := preload("res://scripts/ui/controller_diagram.gd")
var _grid: GridContainer
var _pad: Node
var _device: Label
var _diagram: Control
var _action: OptionButton
var _current: Label
var _status: Label
var _detect: Button
var _apply: Button
var _cancel: Button
var _reset: Button
var _pending: Dictionary = {}
var _listening := false
var _release_guard := false
var _arm_at := 0
var _neutral: Dictionary = {}
var _reset_pending := false

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	_pad = get_node("/root/GamepadInput")
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 14)
	add_child(_grid)
	var visual := VBoxContainer.new()
	visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visual.add_theme_constant_override("separation", 12)
	_grid.add_child(visual)
	var editor := VBoxContainer.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.add_theme_constant_override("separation", 12)
	_grid.add_child(editor)
	resized.connect(_resize_layout)
	_device = _label("")
	visual.add_child(_device)
	_diagram = DIAGRAM.new()
	_diagram.input_selected.connect(_diagram_selected)
	visual.add_child(_diagram)
	visual.add_child(_label("Choose an action, then Detect input or tap a control in the diagram. Stick edges select a direction."))
	_action = OptionButton.new()
	_action.custom_minimum_size.y = 56
	_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action.fit_to_longest_item = false
	for row in BINDINGS.ACTIONS:
		_action.add_item(row[1])
	_action.item_selected.connect(func(_index: int): cancel_capture(); _refresh())
	editor.add_child(_action)
	_current = _label("")
	editor.add_child(_current)
	_detect = _button("Detect input", begin_capture)
	editor.add_child(_detect)
	_status = _label("Custom layout is saved on this device. Menu navigation uses the standard D-pad, A and B.")
	editor.add_child(_status)
	_apply = _button("Save binding", _save)
	editor.add_child(_apply)
	_cancel = _button("Cancel detection", cancel_capture)
	editor.add_child(_cancel)
	_reset = _button("Restore default layout", _request_reset)
	editor.add_child(_reset)
	_pad.raw_controller_input.connect(_on_raw_input)
	_pad.connection_changed.connect(_connection_changed)
	visibility_changed.connect(_visibility_changed)
	cancel_capture()
	_refresh()

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 56
	button.pressed.connect(callback)
	return button

func selected_action() -> String:
	return BINDINGS.ACTIONS[_action.selected][0]

func _refresh() -> void:
	_device.text = ("Connected: " + _pad.active_device_name) if _pad.is_controller_ready() else "No controller connected · connect a Bluetooth or USB controller to detect input."
	_current.text = "Assigned: " + BINDINGS.label(_pad.bindings.values[selected_action()])
	_diagram.highlighted = _pad.bindings.values[selected_action()].duplicate()
	_diagram.queue_redraw()
	_detect.disabled = not _pad.is_controller_ready() or _listening
	_apply.visible = not _pending.is_empty() or _reset_pending
	_cancel.visible = _listening or not _pending.is_empty() or _reset_pending
	_action.disabled = _listening or _release_guard
	_reset.disabled = _listening
	focus_layout_changed.emit()

func _visibility_changed() -> void:
	_pad.mapper_active = is_visible_in_tree()
	if not is_visible_in_tree():
		cancel_capture()
	else:
		_refresh()

func _exit_tree() -> void:
	if is_instance_valid(_pad):
		_pad.mapper_active = false

func begin_capture() -> void:
	if not _pad.is_controller_ready():
		return
	_pending.clear()
	_reset_pending = false
	_listening = true
	_release_guard = false
	_arm_at = Time.get_ticks_msec() + 250
	_neutral.clear()
	for axis in range(JOY_AXIS_MAX):
		_neutral[axis] = _axis_is_neutral(axis, _pad._read_axis(axis))
	_status.text = "Release the controls, then press a button, squeeze a trigger or move a stick. Escape or the Cancel button stops detection."
	_refresh()
	_cancel.grab_focus()

func _axis_is_neutral(axis: int, value: float) -> bool:
	if axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		var rest: float = _pad._left_trigger_rest if axis == JOY_AXIS_TRIGGER_LEFT else _pad._right_trigger_rest
		return _pad.normalized_trigger(value, rest) < 0.15
	return absf(value) < 0.25

func _on_raw_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or event.device != _pad.active_device:
		return
	var display_event := event
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		display_event = event.duplicate()
		var rest: float = _pad._left_trigger_rest if event.axis == JOY_AXIS_TRIGGER_LEFT else _pad._right_trigger_rest
		display_event.axis_value = _pad.normalized_trigger(event.axis_value, rest)
	_diagram.show_input(display_event)
	if _release_guard:
		get_viewport().set_input_as_handled()
		if (event is InputEventJoypadButton and not event.pressed and _pending.get("type") == "button" and event.button_index == _pending.get("index")) or (event is InputEventJoypadMotion and _pending.get("type") == "axis" and event.axis == _pending.get("index") and _axis_is_neutral(event.axis, event.axis_value)):
			_release_guard = false
			_refresh()
			_apply.grab_focus()
		return
	if not _listening:
		return
	get_viewport().set_input_as_handled()
	if Time.get_ticks_msec() < _arm_at:
		return
	var binding := {}
	if event is InputEventJoypadButton and event.pressed:
		binding = {"type": "button", "index": event.button_index}
	elif event is InputEventJoypadMotion:
		if _axis_is_neutral(event.axis, event.axis_value):
			_neutral[event.axis] = true
			return
		if not _neutral.get(event.axis, false):
			return
		if event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
			var rest: float = _pad._left_trigger_rest if event.axis == JOY_AXIS_TRIGGER_LEFT else _pad._right_trigger_rest
			if _pad.normalized_trigger(event.axis_value, rest) < 0.65:
				return
			binding = {"type": "axis", "index": event.axis, "sign": 1}
		elif absf(event.axis_value) >= 0.65:
			binding = {"type": "axis", "index": event.axis, "sign": 1 if event.axis_value > 0 else -1}
	if not binding.is_empty():
		_release_guard = true
		_offer_binding(binding)

func _diagram_selected(binding: Dictionary) -> void:
	# Finish releasing a captured physical input before selecting another one.
	if not _release_guard:
		_offer_binding(binding)


func _offer_binding(binding: Dictionary) -> void:
	if not BINDINGS.valid(binding):
		return
	_listening = false
	_reset_pending = false
	_pending = binding.duplicate()
	var shared: PackedStringArray = _pad.bindings.shared(selected_action(), binding)
	_status.text = "Detected: %s → %s.\n" % [BINDINGS.label(binding), _action.get_item_text(_action.selected)]
	if not shared.is_empty():
		_status.text += "Also used by: %s. Saving keeps both actions on this input; select another input to avoid sharing." % ", ".join(shared)
	else:
		_status.text += "Save to apply this binding, or cancel to keep your current layout."
	_apply.text = "Save shared binding" if not shared.is_empty() else "Save binding"
	_refresh()
	_diagram.highlighted = binding.duplicate()
	_diagram.queue_redraw()
	if not _release_guard:
		_apply.grab_focus()

func _save() -> void:
	if _release_guard:
		return
	var error: Error = _pad.restore_bindings() if _reset_pending else _pad.save_binding(selected_action(), _pending)
	if error != OK:
		_status.text = "Could not save the layout. Your previous bindings are still active."
		return
	cancel_capture()
	_status.text = "Layout saved. Applies to flight now and after restarting the app."
	_detect.grab_focus()

func _request_reset() -> void:
	cancel_capture()
	_reset_pending = true
	_status.text = "Restore the standard controller layout? This replaces your saved custom bindings."
	_apply.text = "Restore defaults"
	_refresh()
	_apply.grab_focus()

func cancel_capture() -> void:
	_listening = false
	_release_guard = false
	_pending.clear()
	_reset_pending = false
	_status.text = "Custom layout is saved on this device. Menu navigation uses the standard D-pad, A and B."
	_refresh()

func _connection_changed(_connected: bool, _id: int, _name: String) -> void:
	cancel_capture()
	_diagram.clear_live()
	_refresh()

func cancel_pending() -> bool:
	if _listening or not _pending.is_empty() or _reset_pending:
		cancel_capture()
		_detect.grab_focus()
		return true
	return false


func _resize_layout() -> void:
	_grid.columns = 2 if size.x >= 560 else 1
	var diagram_width := (size.x - 24.0) * 0.5 if _grid.columns == 2 else size.x
	_diagram.custom_minimum_size.y = clampf(diagram_width * 0.5, 120.0, 230.0)
