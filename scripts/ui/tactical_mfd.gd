extends Control

signal open_changed(is_open: bool)
signal contact_selected(handle: int)
signal waypoint_requested(position: Vector2)
signal route_skip_requested
signal route_clear_requested
const CANVAS := preload("res://scripts/ui/tactical_map_canvas.gd")
const SETTINGS := preload("res://scripts/ui/settings_panel.gd")
const RANGES := [1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 40000.0]
var map: Control
var _close: Button
var _status: Label
var _range_buttons: Array[Button] = []
var _style_buttons: Array[Button] = []
var _waypoint: Button
var _rail: ScrollContainer
var _margin: MarginContainer
var _header: Label
var pause_flight := true

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 30
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var styling := SETTINGS.new()
	theme = styling._menu_theme()
	styling.free()
	var background := ColorRect.new()
	background.color = Color(0.014, 0.028, 0.031)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	_margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	_header = Label.new()
	_header.text = "TACTICAL / MFD"
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_theme_color_override("font_color", Color(0.40, 0.91, 0.73))
	header.add_child(_header)
	_close = _button("Close · Y", close_panel)
	header.add_child(_close)
	var ranges := HBoxContainer.new()
	ranges.add_theme_constant_override("separation", 4)
	layout.add_child(ranges)
	for metres in RANGES:
		var button := _button("%d km" % int(metres / 1000), func(): map.set_range(metres))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ranges.add_child(button)
		_range_buttons.append(button)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	layout.add_child(body)
	map = CANVAS.new()
	body.add_child(map)
	map.contact_selected.connect(func(handle: int): contact_selected.emit(handle))
	map.waypoint_requested.connect(func(point: Vector2): waypoint_requested.emit(point))
	map.range_changed.connect(_range_changed)
	_rail = ScrollContainer.new()
	_rail.custom_minimum_size.x = 116
	_rail.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rail.follow_focus = true
	body.add_child(_rail)
	var buttons := VBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_theme_constant_override("separation", 6)
	_rail.add_child(buttons)
	for style in ["Satellite", "Simple", "Terrain"]:
		var index := _style_buttons.size()
		var button := _button(style, _set_style.bind(index))
		button.toggle_mode = true
		buttons.add_child(button)
		_style_buttons.append(button)
	buttons.add_child(_button("Ownship", func(): map.recenter()))
	_waypoint = _button("Add WP", _toggle_waypoint)
	_waypoint.toggle_mode = true
	buttons.add_child(_waypoint)
	buttons.add_child(_button("Next WP", func(): route_skip_requested.emit()))
	buttons.add_child(_button("Clear route", func(): route_clear_requested.emit()))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.57, 0.76, 0.71))
	layout.add_child(_status)
	resized.connect(_resize_layout)
	_resize_layout()
	_set_style(1)
	_range_changed(map.range_m)
	_status.text = "Pinch / wheel: zoom · Drag: pan · Tap contact: select · Add WP: plot route"

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(callback)
	return button

func _resize_layout() -> void:
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 8 if size.x < 760 or size.y < 460 else 20)
	_rail.custom_minimum_size.x = 98 if size.x < 500 else 116
	for button in _range_buttons:
		button.add_theme_font_size_override("font_size", 11 if size.x < 500 else 15)
		# Compact range keys must fit alongside each other even on portrait phones.
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.07, 0.13, 0.15)
		normal.border_color = Color(0.19, 0.35, 0.34)
		normal.set_border_width_all(1)
		normal.content_margin_left = 4
		normal.content_margin_right = 4
		button.add_theme_stylebox_override("normal", normal)

func _set_style(index: int) -> void:
	map.map_style = index
	map._update_shader()
	map.queue_redraw()
	for i in range(_style_buttons.size()):
		_style_buttons[i].set_pressed_no_signal(i == index)

func _range_changed(metres: float) -> void:
	for i in range(_range_buttons.size()):
		_range_buttons[i].set_pressed_no_signal(is_equal_approx(metres, RANGES[i]))

func _toggle_waypoint() -> void:
	map.add_waypoint = not map.add_waypoint
	_waypoint.set_pressed_no_signal(map.add_waypoint)
	_status.text = "WAYPOINT MODE · Tap the map to append a waypoint. Next WP skips the current leg." if map.add_waypoint else "TARGET MODE · Tap a contact to select it. Drag to pan; pinch to zoom."

func show_message(message: String) -> void:
	_status.text = message

func open_panel() -> void:
	if visible:
		return
	get_parent().move_child(self, -1)
	visible = true
	map.recenter()
	map.cancel_gesture()
	_header.text = "TACTICAL / PAUSED" if pause_flight else "TACTICAL / LIVE"
	_close.grab_focus()
	open_changed.emit(true)

func close_panel() -> void:
	if not visible:
		return
	visible = false
	map.cancel_gesture()
	# Release shared detail references so terrain eviction can reclaim memory.
	map.set_layers({})
	open_changed.emit(false)

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
