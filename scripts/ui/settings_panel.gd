extends Control

## Everything that is not flying: theatre choice, control mode, map cache.
##
## Built in code rather than laid out in the scene so the theatre list follows
## the catalog -- adding a region to catalog.json puts a button here without
## touching the scene.

signal theatre_chosen(region_id: String)
signal flight_mode_toggled
signal cache_cleared
signal quality_cycled

const PANEL_WIDTH := 520.0

var _theatre_box: VBoxContainer
var _mode_button: Button
var _cache_label: Label
var _quality_button: Button
var _stats_label: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.06, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	centre.add_child(frame)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 22)
	frame.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_heading("SETTINGS"))
	column.add_child(_heading("THEATRE"))
	_theatre_box = VBoxContainer.new()
	_theatre_box.add_theme_constant_override("separation", 4)
	column.add_child(_theatre_box)

	column.add_child(_heading("CONTROLS"))
	_mode_button = Button.new()
	_mode_button.pressed.connect(func(): flight_mode_toggled.emit())
	column.add_child(_mode_button)

	column.add_child(_heading("GRAPHICS"))
	_quality_button = Button.new()
	_quality_button.pressed.connect(func(): quality_cycled.emit())
	column.add_child(_quality_button)

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


func set_quality_text(text: String) -> void:
	_quality_button.text = text


func set_cache_report(files: int, bytes: int) -> void:
	_cache_label.text = "%.1f MB across %d files. Imagery and elevation are kept so flown ground works offline; nothing prunes it." % [
		float(bytes) / 1048576.0, files
	]


func set_status(text: String) -> void:
	_stats_label.text = text


func open_panel() -> void:
	visible = true


func close_panel() -> void:
	visible = false


func toggle_panel() -> bool:
	visible = not visible
	return visible
