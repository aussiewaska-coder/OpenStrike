extends Control

## Pre-flight splash: theatre, enemies, start mode (airborne or a specific
## runway), then START. An overlay only -- flight boots behind it exactly as
## before, and the region loads when START is pressed.

signal theatre_chosen(region_id: String)
signal hostiles_toggled
signal start_mode_changed(airborne: bool, runway: Dictionary)
signal start_requested

const RUNWAYS := preload("res://scripts/world/runways.gd")

const INK := Color(0.90, 0.94, 0.96)
const ACCENT := Color(0.40, 0.88, 0.79)
const MUTED := Color(0.57, 0.67, 0.73)

var _regions: Array = []
var _selected_id := ""
var _hostiles := false
var _airborne := true
var _runway := {}
var _loading := false

var _theatre_box: VBoxContainer
var _hostiles_button: Button
var _airborne_button: Button
var _runway_button: Button
var _runway_box: VBoxContainer
var _start_button: Button
var _status_label: Label


func _ready() -> void:
	visible = false
	# The boot tree is paused until a controller connects; like the settings
	# panel, the splash must stay interactive through that.
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 30
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color(0.02, 0.035, 0.05, 0.96)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	# ScrollContainer needs a full-width child or narrow phones clip it.
	column.custom_minimum_size.x = 200
	scroll.add_child(column)
	column.add_child(_label("OPENSTRIKE", INK, 40))
	column.add_child(_label("Mission setup — the region loads when you start.", ACCENT, 18))
	column.add_child(_label("Theatre", INK, 22))
	_theatre_box = VBoxContainer.new()
	_theatre_box.add_theme_constant_override("separation", 8)
	column.add_child(_theatre_box)
	column.add_child(_label("Enemies", INK, 22))
	_hostiles_button = _button("HOSTILES: OFF", func(): hostiles_toggled.emit())
	column.add_child(_hostiles_button)
	column.add_child(_label("Start", INK, 22))
	_airborne_button = _button("START AIRBORNE", func(): start_mode_changed.emit(true, {}))
	column.add_child(_airborne_button)
	_runway_button = _button("START ON RUNWAY", func(): start_mode_changed.emit(false, _runway))
	column.add_child(_runway_button)
	_runway_box = VBoxContainer.new()
	_runway_box.add_theme_constant_override("separation", 8)
	column.add_child(_runway_box)
	_status_label = _label("", MUTED, 16)
	column.add_child(_status_label)
	_start_button = _button("START", func(): start_requested.emit())
	_start_button.custom_minimum_size.y = 72
	_start_button.add_theme_font_size_override("font_size", 26)
	layout.add_child(_start_button)


func show_panel(regions: Array, selected_id: String, hostiles: bool, airborne: bool, runway: Dictionary) -> void:
	_regions = regions
	_selected_id = selected_id
	_hostiles = hostiles
	_airborne = airborne
	_runway = runway
	_loading = false
	_rebuild()
	visible = true
	_start_button.grab_focus()


func set_loading(message: String) -> void:
	_loading = true
	_status_label.text = message
	_start_button.disabled = true


func hide_panel() -> void:
	visible = false


func _rebuild() -> void:
	for child in _theatre_box.get_children():
		_theatre_box.remove_child(child)
		child.queue_free()
	for region in _regions:
		var id := String(region.get("id", ""))
		var text := String(region.get("display_name", id))
		if id == _selected_id:
			text += "  ·  ACTIVE"
		text += "\n" + String(region.get("subtitle", ""))
		_theatre_box.add_child(_button(text, func(): theatre_chosen.emit(id)))
	_hostiles_button.text = "HOSTILES: %s" % ("ON" if _hostiles else "OFF")
	_airborne_button.text = "START AIRBORNE  ·  ACTIVE" if _airborne else "START AIRBORNE"
	_runway_button.text = "START ON RUNWAY  ·  ACTIVE" if not _airborne else "START ON RUNWAY"
	for child in _runway_box.get_children():
		_runway_box.remove_child(child)
		child.queue_free()
	var strips := RUNWAYS.for_region(_selected_id)
	_runway_button.visible = not strips.is_empty()
	_runway_box.visible = not strips.is_empty() and not _airborne
	for strip in strips:
		var label := "%s %s · %.1f KM" % [strip.get("airport", ""), strip.get("id", ""), float(strip.get("length_m", 0.0)) / 1000.0]
		if String(strip.get("id", "")) == String(_runway.get("id", "")) and not _airborne:
			label += "  ·  ACTIVE"
		_runway_box.add_child(_button(label, func(): start_mode_changed.emit(false, strip)))
	if strips.is_empty():
		_status_label.text = "No authored runway in this theatre — airborne only."
	elif _pending_empty():
		_status_label.text = "Waiting for location…"
	else:
		_status_label.text = ""
	_start_button.disabled = _loading or _pending_empty()


func _pending_empty() -> bool:
	return _selected_id.is_empty()


func _label(text: String, colour: Color, font_size: int) -> Label:
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
