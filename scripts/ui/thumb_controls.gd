extends Control
## The touch stand-in for a gamepad: a left stick for pitch and roll, a right
## stick for looking around, and a throttle pair you hold. Both sticks report
## through GamepadInput exactly like the physical sticks do, so the flight and
## camera code never learns which one moved.

const STICK := preload("res://scripts/ui/thumb_stick.gd")
const EDGE_INSET := 18.0
const THROTTLE_STEP := Vector2(150, 62)

var flight := STICK.new()
var look := STICK.new()
var throttle_up := Button.new()
var throttle_down := Button.new()
var look_button := Button.new()

var _thr_up := false
var _thr_down := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flight.caption = "PITCH / ROLL"
	look.caption = "LOOK"
	for stick in [flight, look]:
		add_child(stick)
		stick.vector_changed.connect(func(_vector: Vector2): _push())
	add_child(_throttle_button(throttle_up, "THROTTLE +", true))
	add_child(_throttle_button(throttle_down, "THROTTLE -", false))
	look_button.text = "LOOK"
	look_button.custom_minimum_size = THROTTLE_STEP
	look_button.focus_mode = Control.FOCUS_NONE
	look_button.add_theme_font_size_override("font_size", 18)
	look_button.button_down.connect(func(): _hold_look(true))
	look_button.button_up.connect(func(): _hold_look(false))
	add_child(look_button)
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(_layout)
	_layout()


func _throttle_button(button: Button, text: String, rising: bool) -> Button:
	button.text = text
	button.custom_minimum_size = THROTTLE_STEP
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.button_down.connect(func():
		if rising:
			_thr_up = true
		else:
			_thr_down = true
		_push())
	button.button_up.connect(func():
		if rising:
			_thr_up = false
		else:
			_thr_down = false
		_push())
	return button


func _layout() -> void:
	var reach := Vector2(minf(size.x * 0.3, 440.0), minf(size.y * 0.46, 320.0))
	flight.size = reach
	flight.position = Vector2(EDGE_INSET, size.y - reach.y - EDGE_INSET)
	look.size = reach
	look.position = Vector2(size.x - reach.x - EDGE_INSET, size.y - reach.y - EDGE_INSET)
	var stack := Vector2(size.x * 0.5 - THROTTLE_STEP.x * 0.5, size.y - THROTTLE_STEP.y * 2.0 - EDGE_INSET)
	throttle_up.position = stack
	throttle_down.position = stack + Vector2(0, THROTTLE_STEP.y + 8.0)
	look_button.position = stack - Vector2(0, THROTTLE_STEP.y + 8.0)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		return
	# A stick that went away mid-drag must not leave the aircraft banked.
	flight.release()
	look.release()
	_thr_up = false
	_thr_down = false
	_hold_look(false)
	_push()


## HOLD to look: while it is down the right stick turns the head instead of the
## helicopter's yaw and collective, which is what A does on a controller.
func _hold_look(held: bool) -> void:
	var pad := get_node_or_null("/root/GamepadInput")
	if pad != null and pad.has_method("set_thumb_free_look"):
		pad.set_thumb_free_look(held)


func _push() -> void:
	var pad := get_node_or_null("/root/GamepadInput")
	if pad == null or not pad.has_method("set_thumb_input"):
		return
	var throttle := 0.0
	if _thr_up:
		throttle += 1.0
	if _thr_down:
		throttle -= 1.0
	pad.set_thumb_input(flight.vector, look.vector, throttle)
