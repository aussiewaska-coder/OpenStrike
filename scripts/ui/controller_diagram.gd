extends Control

signal input_selected(binding: Dictionary)
const BINDINGS := preload("res://scripts/input/controller_bindings.gd")
const ACCENT := Color(0.40, 0.88, 0.79)
const BUTTONS := [
	[9, "L1", Vector2(115, 28)], [10, "R1", Vector2(365, 28)],
	[5, "Home", Vector2(240, 55)],
	[4, "Share", Vector2(203, 100)], [6, "Start", Vector2(277, 100)],
	[3, "Y / △", Vector2(372, 83)], [1, "B / ○", Vector2(407, 117)],
	[0, "A / ×", Vector2(372, 151)], [2, "X / □", Vector2(337, 117)],
	[11, "↑", Vector2(185, 156)], [12, "↓", Vector2(185, 208)],
	[13, "←", Vector2(159, 182)], [14, "→", Vector2(211, 182)],
	[7, "L3", Vector2(57, 205)], [8, "R3", Vector2(422, 205)],
]
var highlighted: Dictionary = {}
var _live_buttons: Dictionary = {}
var _live_axes: Dictionary = {}

func _ready() -> void:
	custom_minimum_size.y = 230
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)

func _scale_factor() -> float:
	return minf(size.x / 480.0, size.y / 240.0)

func _offset() -> Vector2:
	return (size - Vector2(480, 240) * _scale_factor()) * 0.5

func show_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_live_buttons[event.button_index] = event.pressed
	elif event is InputEventJoypadMotion:
		_live_axes[event.axis] = event.axis_value
	queue_redraw()

func clear_live() -> void:
	_live_buttons.clear()
	_live_axes.clear()
	queue_redraw()

func _text(at: Vector2, text: String, colour: Color, font_size := 13) -> void:
	var width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(ThemeDB.fallback_font, at + Vector2(-width * 0.5, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)

func _draw() -> void:
	if size.x <= 0:
		return
	draw_set_transform(_offset(), 0, Vector2.ONE * _scale_factor())
	var hull := PackedVector2Array([Vector2(78, 53), Vector2(158, 50), Vector2(195, 68), Vector2(285, 68), Vector2(322, 50), Vector2(402, 53), Vector2(450, 212), Vector2(408, 230), Vector2(349, 195), Vector2(132, 195), Vector2(72, 230), Vector2(30, 212), Vector2(78, 53)])
	draw_colored_polygon(hull, Color(0.07, 0.12, 0.16))
	draw_polyline(hull, Color(0.25, 0.39, 0.43), 2, true)
	for row in BUTTONS:
		var chosen: bool = highlighted.get("type") == "button" and highlighted.get("index") == row[0]
		var on: bool = _live_buttons.get(row[0], false)
		draw_circle(row[2], 20, Color(0.10, 0.31, 0.30) if on or chosen else Color(0.10, 0.17, 0.21))
		draw_arc(row[2], 20, 0, TAU, 32, ACCENT if on or chosen else Color(0.32, 0.45, 0.49), 1.5, true)
		_text(row[2], row[1], ACCENT if on or chosen else Color(0.86, 0.93, 0.94), 11 if row[0] in [4, 6] else 13)
	for index in range(2):
		var centre := Vector2(108, 118) if index == 0 else Vector2(290, 182)
		var axis := index * 2
		draw_circle(centre, 32, Color(0.035, 0.07, 0.09))
		draw_arc(centre, 32, 0, TAU, 40, Color(0.32, 0.45, 0.49), 1.5, true)
		var motion := Vector2(_live_axes.get(axis, 0.0), _live_axes.get(axis + 1, 0.0))
		draw_circle(centre + motion.limit_length() * 15, 12, Color(0.21, 0.38, 0.40))
		if highlighted.get("type") == "axis" and highlighted.get("index") in [axis, axis + 1]:
			var direction := Vector2.RIGHT if highlighted.index == axis else Vector2.DOWN
			draw_circle(centre + direction * float(highlighted.sign) * 24, 5, ACCENT)
		_text(centre + Vector2(0, -42), "LEFT STICK" if index == 0 else "RIGHT STICK", Color(0.57, 0.67, 0.73), 10)
	for index in range(2):
		var at := Vector2(55, 25) if index == 0 else Vector2(425, 25)
		var chosen: bool = (highlighted.get("type") == "axis" and highlighted.get("index") == index + 4) or float(_live_axes.get(index + 4, 0.0)) > 0.15
		draw_rect(Rect2(at - Vector2(22, 18), Vector2(44, 36)), Color(0.10, 0.31, 0.30) if chosen else Color(0.10, 0.17, 0.21))
		_text(at, "L2" if index == 0 else "R2", ACCENT if chosen else Color.WHITE)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var at: Vector2 = (event.position - _offset()) / _scale_factor()
	for row in BUTTONS:
		if at.distance_to(row[2]) <= 22:
			input_selected.emit({"type": "button", "index": row[0]})
			accept_event()
			return
	for index in range(2):
		var trigger := Vector2(55, 25) if index == 0 else Vector2(425, 25)
		if at.distance_to(trigger) < 26:
			input_selected.emit({"type": "axis", "index": index + 4, "sign": 1})
			accept_event()
			return
		var centre := Vector2(108, 118) if index == 0 else Vector2(290, 182)
		var direction: Vector2 = at - centre
		if direction.length() <= 34:
			var horizontal := absf(direction.x) > absf(direction.y)
			input_selected.emit({"type": "axis", "index": index * 2 + (0 if horizontal else 1), "sign": 1 if (direction.x if horizontal else direction.y) >= 0 else -1})
			accept_event()
			return
