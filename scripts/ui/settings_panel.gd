extends Control

## Everything that is not flying: theatre choice, control mode, map cache.
##
## Built in code rather than laid out in the scene so the theatre list follows
## the catalog -- adding a region to catalog.json puts a button here without
## touching the scene.

signal theatre_chosen(region_id: String)
signal flight_mode_toggled
signal aircraft_switched
signal cache_cleared
signal quality_cycled
signal time_cycled
signal weather_cycled
signal input_monitor_toggled(enabled: bool)
signal raid_restarted

const PANEL_WIDTH := 520.0

var _theatre_box: VBoxContainer
var _mode_button: Button
var _aircraft_button: Button
var _cache_label: Label
var _quality_button: Button
var _time_button: Button
var _weather_button: Button
var _stats_label: Label
var _monitor_button: CheckButton
var _region_label: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.06, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Filling the screen with a margin, rather than centring a box that grows
	# with the theatre list: the list ran off the bottom of the viewport and took
	# the close button with it.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	add_child(margin)

	var frame := PanelContainer.new()
	margin.add_child(frame)

	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_%s" % side, 18)
	frame.add_child(inner)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	inner.add_child(layout)

	# A fixed header, so the way out is always on screen no matter how long the
	# list below grows.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	layout.add_child(header)
	var title := Label.new()
	title.text = "SETTINGS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_top := Button.new()
	close_top.text = "CLOSE  (X)"
	close_top.pressed.connect(close_panel)
	header.add_child(close_top)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)

	column.add_child(_heading("THEATRE"))
	_theatre_box = VBoxContainer.new()
	_theatre_box.add_theme_constant_override("separation", 4)
	column.add_child(_theatre_box)

	column.add_child(_heading("AIRCRAFT"))
	_aircraft_button = Button.new()
	_aircraft_button.pressed.connect(func(): aircraft_switched.emit())
	column.add_child(_aircraft_button)

	column.add_child(_heading("CONTROLS"))
	_mode_button = Button.new()
	_mode_button.pressed.connect(func(): flight_mode_toggled.emit())
	column.add_child(_mode_button)

	column.add_child(_heading("RAID"))
	var restart := Button.new()
	restart.text = "RESTART RAID"
	restart.pressed.connect(func(): raid_restarted.emit())
	column.add_child(restart)

	column.add_child(_heading("HUD"))
	_monitor_button = CheckButton.new()
	_monitor_button.text = "INPUT MONITOR OVERLAY"
	_monitor_button.toggled.connect(func(on: bool): input_monitor_toggled.emit(on))
	column.add_child(_monitor_button)

	column.add_child(_heading("GRAPHICS"))
	_quality_button = Button.new()
	_quality_button.pressed.connect(func(): quality_cycled.emit())
	column.add_child(_quality_button)
	_time_button = Button.new()
	_time_button.pressed.connect(func(): time_cycled.emit())
	column.add_child(_time_button)
	_weather_button = Button.new()
	_weather_button.pressed.connect(func(): weather_cycled.emit())
	column.add_child(_weather_button)

	column.add_child(_heading("MAP CACHE"))
	_cache_label = Label.new()
	_cache_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_cache_label)
	var clear := Button.new()
	clear.text = "CLEAR MAP CACHE"
	clear.pressed.connect(func(): cache_cleared.emit())
	column.add_child(clear)

	column.add_child(_heading("STATUS"))
	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_stats_label)

	column.add_child(_heading("THEATRE INFO"))
	_region_label = Label.new()
	_region_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_region_label)
	var privacy := Label.new()
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.text = "Foreground location only. Coordinates are not saved.\nMap © OpenStreetMap contributors. Aerial © State of Queensland."
	column.add_child(privacy)

	var close := Button.new()
	close.text = "CLOSE"
	close.pressed.connect(close_panel)
	column.add_child(close)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


## One button per installed theatre, so the catalog drives the list.
func populate_theatres(regions: Array, selected_id: String) -> void:
	for child in _theatre_box.get_children():
		child.queue_free()
	for region in regions:
		var id := String(region.get("id", ""))
		var button := Button.new()
		var marker := "> " if id == selected_id else "  "
		button.text = "%s%s -- %s" % [marker, region.get("display_name", id), region.get("subtitle", "")]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(func(): theatre_chosen.emit(id))
		_theatre_box.add_child(button)


func set_flight_mode_text(text: String) -> void:
	_mode_button.text = text


func set_aircraft_text(text: String) -> void:
	_aircraft_button.text = text


func set_quality_text(text: String) -> void:
	_quality_button.text = text


func set_time_text(text: String) -> void:
	_time_button.text = text


func set_weather_text(text: String) -> void:
	_weather_button.text = text


func set_cache_report(files: int, bytes: int) -> void:
	_cache_label.text = "%.1f MB across %d files. Imagery and elevation are kept so flown ground works offline; nothing prunes it." % [
		float(bytes) / 1048576.0, files
	]


func set_region_text(text: String) -> void:
	_region_label.text = text


func set_status(text: String) -> void:
	_stats_label.text = text


func open_panel() -> void:
	visible = true


func close_panel() -> void:
	visible = false


func toggle_panel() -> bool:
	visible = not visible
	return visible
