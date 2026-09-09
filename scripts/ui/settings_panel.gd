extends Control

## A modal, controller-navigable menu. Header and section tabs stay in view;
## only the selected section scrolls.
signal theatre_chosen(region_id: String)
signal flight_mode_toggled
signal aircraft_switched
signal cache_cleared
signal quality_cycled
signal time_cycled
signal weather_cycled
signal input_monitor_toggled(enabled: bool)
signal raid_restarted
signal open_changed(is_open: bool)
signal engine_volume_cycled
signal weather_volume_cycled

const ACCENT := Color(0.40, 0.88, 0.79)
const INK := Color(0.90, 0.94, 0.96)
const MUTED := Color(0.57, 0.67, 0.73)
const SECTIONS := ["Flight", "World", "Display", "Storage", "Controller"]

var _mapper: Control
var _navigation: GridContainer
var _theatre_box: VBoxContainer
var _mode_button: Button
var _aircraft_button: Button
var _cache_label: Label
var _quality_button: Button
var _time_button: Button
var _weather_button: Button
var _stats_label: Label
var _engine_volume_button: Button
var _weather_volume_button: Button
var _monitor_button: CheckButton
var _region_label: Label
var _resume_button: Button
var _scroll: ScrollContainer
var _margin: MarginContainer
var _title: Label
var _hint: Label
var _tabs: Array[Button] = []
var _pages: Array[VBoxContainer] = []
var _grids: Array[GridContainer] = []
var _selected_page := 0
var _theatre_signature := 0


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 20
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _menu_theme()
	var background := ColorRect.new()
	background.color = Color(0.025, 0.04, 0.055, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	_margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	layout.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	_title = _label("Settings", INK, 30)
	titles.add_child(_title)
	titles.add_child(_label("FLIGHT PAUSED", ACCENT, 13))
	_resume_button = _button("Resume  ·  B", close_panel)
	_resume_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_resume_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_resume_button.custom_minimum_size.x = 152
	_resume_button.add_theme_stylebox_override("normal", _style(Color(0.08, 0.23, 0.23), ACCENT))
	header.add_child(_resume_button)

	_navigation = GridContainer.new()
	_navigation.columns = 5
	_navigation.add_theme_constant_override("h_separation", 8)
	_navigation.add_theme_constant_override("v_separation", 8)
	layout.add_child(_navigation)
	for index in range(SECTIONS.size()):
		var tab := _button(SECTIONS[index], _select_page.bind(index))
		tab.toggle_mode = true
		tab.alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_navigation.add_child(tab)
		_tabs.append(tab)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.add_theme_constant_override("scrollbar_h_separation", 10)
	layout.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	for section in SECTIONS:
		var page := VBoxContainer.new()
		page.name = section
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 14)
		content.add_child(page)
		_pages.append(page)

	var flight := _grid(_pages[0])
	var aircraft := _card(flight, "Aircraft", "Select to switch aircraft.")
	_aircraft_button = _button("F-22 RAPTOR", func(): aircraft_switched.emit())
	aircraft.add_child(_aircraft_button)
	var controls := _card(flight, "Flight controls", "The F-22 uses fly-by-wire. The Apache offers two control modes.")
	_mode_button = _button("FLY-BY-WIRE", func(): flight_mode_toggled.emit())
	controls.add_child(_mode_button)
	var mission := _card(flight, "Mission", "Start a fresh raid in the current theatre.")
	mission.add_child(_button("Restart raid", func(): raid_restarted.emit()))
	var status := _card(flight, "Current flight")
	_stats_label = _label("", MUTED)
	status.add_child(_stats_label)
	var sound := _card(flight, "Audio", "Select to cycle off, 40%, 70% and 100% volume.")
	_engine_volume_button = _button("ENGINE SOUND: 70%", func(): engine_volume_cycled.emit())
	sound.add_child(_engine_volume_button)
	_weather_volume_button = _button("WEATHER SOUND: 70%", func(): weather_volume_cycled.emit())
	sound.add_child(_weather_volume_button)

	var location := _card(_pages[1], "Theatre", "Choose where to fly. Selecting a theatre returns you to the game.")
	_region_label = _label("", ACCENT)
	location.add_child(_region_label)
	_theatre_box = VBoxContainer.new()
	_theatre_box.add_theme_constant_override("separation", 8)
	location.add_child(_theatre_box)

	var display := _grid(_pages[2])
	var graphics := _card(display, "Graphics detail", "Select to cycle performance, balanced and quality.")
	_quality_button = _button("BALANCED", func(): quality_cycled.emit())
	graphics.add_child(_quality_button)
	var time := _card(display, "Time of day", "Change the light and sky.")
	_time_button = _button("AFTERNOON", func(): time_cycled.emit())
	time.add_child(_time_button)
	var weather := _card(display, "Weather", "Cycle clear, overcast, rain and storm. Storm adds towering clouds.")
	_weather_button = _button("CLEAR", func(): weather_cycled.emit())
	weather.add_child(_weather_button)
	var hud := _card(display, "HUD", "Show controller readings while flying.")
	_monitor_button = CheckButton.new()
	_monitor_button.text = "Input monitor"
	_monitor_button.custom_minimum_size.y = 56
	_monitor_button.toggled.connect(func(on: bool): input_monitor_toggled.emit(on))
	hud.add_child(_monitor_button)

	var cache := _card(_pages[3], "Downloaded maps", "Imagery and elevation stay available offline. Clearing the cache frees space; areas will download again when you fly there.")
	_cache_label = _label("", ACCENT, 24)
	cache.add_child(_cache_label)
	cache.add_child(_button("Clear map cache", func(): cache_cleared.emit()))
	var info := _card(_pages[3], "Location & map credits")
	info.add_child(_label("Foreground location only. Coordinates are not saved.\nMap © OpenStreetMap contributors. Aerial © State of Queensland.", MUTED, 16))
	_mapper = preload("res://scripts/ui/controller_mapper.gd").new()
	_pages[4].add_child(_mapper)
	_mapper.focus_layout_changed.connect(_refresh_focus_chain)
	_hint = _label("D-pad  Navigate     A  Select     B  Resume", MUTED, 15)
	layout.add_child(_hint)
	resized.connect(_resize_layout)
	_resize_layout()
	_select_page(0, false)


func _style(fill: Color, border: Color = Color(0.15, 0.22, 0.27)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _menu_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 20
	for control in ["Button", "CheckButton"]:
		result.set_color("font_color", control, INK)
		result.set_color("font_hover_color", control, Color.WHITE)
		result.set_color("font_pressed_color", control, ACCENT)
		result.set_color("font_disabled_color", control, MUTED)
		result.set_stylebox("normal", control, _style(Color(0.09, 0.14, 0.18)))
		result.set_stylebox("hover", control, _style(Color(0.13, 0.22, 0.26), ACCENT))
		result.set_stylebox("pressed", control, _style(Color(0.07, 0.24, 0.23), ACCENT))
		result.set_stylebox("disabled", control, _style(Color(0.065, 0.09, 0.115)))
		var focus := _style(Color(0, 0, 0, 0), ACCENT)
		focus.set_border_width_all(2)
		result.set_stylebox("focus", control, focus)
	return result


func _label(text: String, colour: Color = INK, font_size := 18) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 56
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	return button


func _grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	parent.add_child(grid)
	_grids.append(grid)
	return grid


func _card(parent: Control, heading: String, detail := "") -> VBoxContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _style(Color(0.045, 0.072, 0.095)))
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	column.add_child(_label(heading, INK, 22))
	if not detail.is_empty():
		column.add_child(_label(detail, MUTED, 17))
	return column


func _resize_layout() -> void:
	var compact := size.x < 760 or size.y < 460
	_navigation.columns = 3 if size.x < 600 else 5
	for tab in _tabs:
		tab.add_theme_font_size_override("font_size", 15 if compact else 20)
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_%s" % side, 12 if compact else 28)
	for grid in _grids:
		grid.columns = 1 if size.x < 760 else 2
	_title.add_theme_font_size_override("font_size", 24 if compact else 30)
	_hint.visible = size.y >= 400


func _select_page(index: int, focus_tab := true) -> void:
	_selected_page = index
	for i in range(_pages.size()):
		_pages[i].visible = i == index
		_tabs[i].set_pressed_no_signal(i == index)
	_scroll.scroll_vertical = 0
	_refresh_focus_chain()
	if focus_tab and visible:
		_tabs[index].grab_focus()


func _refresh_focus_chain() -> void:
	if not is_inside_tree():
		return
	var buttons: Array[Control] = [_resume_button]
	buttons.append_array(_tabs)
	for child in _pages[_selected_page].find_children("*", "BaseButton", true, false):
		if not child.disabled and child.is_visible_in_tree():
			buttons.append(child)
	for index in range(buttons.size()):
		var button := buttons[index]
		var previous := button.get_path_to(buttons[posmod(index - 1, buttons.size())])
		var next := button.get_path_to(buttons[(index + 1) % buttons.size()])
		button.focus_previous = previous
		button.focus_next = next
		button.focus_neighbor_top = previous
		button.focus_neighbor_bottom = next
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)
	for index in range(_tabs.size()):
		_tabs[index].focus_neighbor_left = _tabs[index].get_path_to(_tabs[posmod(index - 1, _tabs.size())])
		_tabs[index].focus_neighbor_right = _tabs[index].get_path_to(_tabs[(index + 1) % _tabs.size()])
		_tabs[index].focus_neighbor_top = _tabs[index].get_path_to(_resume_button)
		_tabs[index].focus_neighbor_bottom = _tabs[index].get_path_to(buttons[1 + _tabs.size()] if buttons.size() > 1 + _tabs.size() else _resume_button)
	_resume_button.focus_neighbor_bottom = _resume_button.get_path_to(_tabs[_selected_page])
	if buttons.size() > 1 + _tabs.size():
		var first := buttons[1 + _tabs.size()]
		first.focus_neighbor_top = first.get_path_to(_tabs[_selected_page])


func populate_theatres(regions: Array, selected_id: String) -> void:
	var signature := hash([regions, selected_id])
	if signature == _theatre_signature:
		return
	_theatre_signature = signature
	for child in _theatre_box.get_children():
		_theatre_box.remove_child(child)
		child.queue_free()
	for region in regions:
		var id := String(region.get("id", ""))
		var text := String(region.get("display_name", id))
		if id == selected_id:
			text += "  ·  ACTIVE"
		text += "\n" + String(region.get("subtitle", ""))
		var button := _button(text, func(): theatre_chosen.emit(id))
		button.custom_minimum_size.y = 76
		button.add_theme_font_size_override("font_size", 18)
		_theatre_box.add_child(button)
	_refresh_focus_chain()


func set_flight_mode_text(text: String) -> void:
	_mode_button.text = text.trim_prefix("CONTROLS: ")
	_mode_button.disabled = text.contains("FLY-BY-WIRE")
	_refresh_focus_chain()


func set_aircraft_text(text: String) -> void:
	_aircraft_button.text = text.trim_prefix("AIRCRAFT: ")


func set_quality_text(text: String) -> void:
	_quality_button.text = text.trim_prefix("GRAPHICS: ")


func set_time_text(text: String) -> void:
	_time_button.text = text.trim_prefix("TIME: ")


func set_weather_text(text: String) -> void:
	_weather_button.text = text.trim_prefix("WEATHER: ")


func set_cache_report(files: int, bytes: int) -> void:
	_cache_label.text = "%.1f MB  ·  %d files" % [float(bytes) / 1048576.0, files]


func set_region_text(text: String) -> void:
	_region_label.text = text.trim_prefix("REGION: ")


func set_status(text: String) -> void:
	_stats_label.text = text


func set_engine_volume_text(text: String) -> void:
	_engine_volume_button.text = text


func set_weather_volume_text(text: String) -> void:
	_weather_volume_button.text = text


func open_panel() -> void:
	if visible:
		return
	# Input hit testing follows tree order, independently of drawing z_index.
	get_parent().move_child(self, -1)
	visible = true
	_refresh_focus_chain()
	_resume_button.grab_focus()
	open_changed.emit(true)


func close_panel() -> void:
	if not visible:
		return
	visible = false
	open_changed.emit(false)


func toggle_panel() -> bool:
	if visible:
		close_panel()
	else:
		open_panel()
	return visible


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if _mapper.is_visible_in_tree() and _mapper.cancel_pending():
			get_viewport().set_input_as_handled()
			return
		close_panel()
		get_viewport().set_input_as_handled()
