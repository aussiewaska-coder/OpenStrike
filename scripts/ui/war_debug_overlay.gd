extends PanelContainer

## §37's panel on the screen. It is a window on to `war_report`, and nothing else: the text it
## shows is the same text the telemetry socket carries, so a developer reading the overlay and a
## shell reading the port cannot be told two different stories about the same tick.

const GREEN := Color(0.40, 0.91, 0.73)
## The campaign moves on an eight second tick and the panel is read at a glance, so a refresh
## faster than that is only the same number flickering.
const REFRESH_SECONDS := 0.5

var _label: Label
var _read: Callable
var _elapsed := 0.0


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 32
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = Vector2(560, 0)
	add_theme_stylebox_override("panel", _backdrop())
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", _mono())
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", GREEN)
	_label.text = "WAR OVERLAY: no report seated"
	add_child(_label)


## Seat the overlay on a source of text -- in practice `war_report.text` bound to a report. The
## overlay never reaches into the war itself, which is what keeps it from becoming a second reader
## with a second opinion. Nothing is painted while the panel is hidden: a source that is only
## asked for when somebody can see it cannot be quietly costing the flight.
func read_from(source: Callable) -> void:
	_read = source
	if visible:
		_refresh()


func _visibility_changed() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	_label.text = String(_read.call()) if _read.is_valid() else "WAR OVERLAY: no report seated"


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed < REFRESH_SECONDS:
		return
	_elapsed = 0.0
	_refresh()


func _mono() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["monospace", "DejaVu Sans Mono", "Courier New"])
	return font


## A dark plate with no border, because a debug panel that costs a scene node and a shader each is
## a debug panel nobody leaves on while flying.
func _backdrop() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.014, 0.028, 0.031, 0.86)
	box.set_content_margin_all(10)
	return box
