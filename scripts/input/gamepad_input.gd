extends Node

signal connection_changed(connected: bool, device_id: int, device_name: String)
signal controller_attention_changed(required: bool, title: String, detail: String)
signal action_pressed(action: StringName)

const DEAD_ZONE := 0.18
const RESPONSE_EXPONENT := 1.15

const ACTION_FLIGHT_LEFT := &"flight_left"
const ACTION_FLIGHT_RIGHT := &"flight_right"
const ACTION_FLIGHT_FORWARD := &"flight_forward"
const ACTION_FLIGHT_BACK := &"flight_back"
const ACTION_AIM_LEFT := &"aim_left"
const ACTION_AIM_RIGHT := &"aim_right"
const ACTION_AIM_FORWARD := &"aim_forward"
const ACTION_AIM_BACK := &"aim_back"
const ACTION_CANNON := &"weapon_cannon"
const ACTION_ROCKETS := &"weapon_rockets"
const ACTION_CAMERA_TRAVEL_TOGGLE := &"camera_travel_toggle"
const ACTION_CONTEXT := &"context_extract"
const ACTION_TARGET_PREVIOUS := &"target_previous"
const ACTION_TARGET_NEXT := &"target_next"
const ACTION_ZOOM_IN := &"camera_zoom_in"
const ACTION_ZOOM_OUT := &"camera_zoom_out"
## The on-screen buttons cannot be reached with a controller, so the two things
## they do are bound to the face buttons instead of making the panel navigable.
const ACTION_FLIGHT_MODE := &"flight_mode_toggle"
const ACTION_SETTINGS := &"settings_panel"
## Held, not pressed: the right stick looks around while R1 is down and the view
## returns when it is let go.
const ACTION_FREE_LOOK := &"free_look"
const ACTION_CAMERA_ORBIT_LEFT := &"camera_orbit_left"
const ACTION_CAMERA_ORBIT_RIGHT := &"camera_orbit_right"

const BUTTON_ACTIONS: Array[StringName] = [
	ACTION_CAMERA_TRAVEL_TOGGLE,
	ACTION_CONTEXT,
	ACTION_TARGET_PREVIOUS,
	ACTION_TARGET_NEXT,
	ACTION_ZOOM_IN,
	ACTION_ZOOM_OUT,
	ACTION_FLIGHT_MODE,
	ACTION_SETTINGS,
]

var active_device := -1
var active_device_name := ""
var active_device_guid := ""
var _had_controller := false
var _paused_for_controller := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_input_actions()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_select_initial_controller()


func _process(_delta: float) -> void:
	if active_device < 0:
		return
	for action in BUTTON_ACTIONS:
		if Input.is_action_just_pressed(action):
			action_pressed.emit(action)


func is_controller_ready() -> bool:
	return active_device >= 0 and active_device in Input.get_connected_joypads()


func get_flight_vector() -> Vector2:
	if not is_controller_ready():
		return Vector2.ZERO
	return apply_response_curve(Input.get_vector(
		ACTION_FLIGHT_LEFT,
		ACTION_FLIGHT_RIGHT,
		ACTION_FLIGHT_FORWARD,
		ACTION_FLIGHT_BACK,
		DEAD_ZONE
	))


func get_aim_vector() -> Vector2:
	if not is_controller_ready():
		return Vector2.ZERO
	return apply_response_curve(Input.get_vector(
		ACTION_AIM_LEFT,
		ACTION_AIM_RIGHT,
		ACTION_AIM_FORWARD,
		ACTION_AIM_BACK,
		DEAD_ZONE
	))


func get_flight_yaw_collective_vector() -> Vector2:
	return route_aim_input_to_flight(get_aim_vector(), is_free_look_held())


static func route_aim_input_to_flight(aim_input: Vector2, free_look_held: bool) -> Vector2:
	return Vector2.ZERO if free_look_held else aim_input


func is_free_look_held() -> bool:
	return is_controller_ready() and Input.is_action_pressed(ACTION_FREE_LOOK)


func is_cannon_firing() -> bool:
	return is_controller_ready() and Input.is_action_pressed(ACTION_CANNON)


func is_rockets_firing() -> bool:
	return is_controller_ready() and Input.is_action_pressed(ACTION_ROCKETS)


func is_context_held() -> bool:
	return is_controller_ready() and Input.is_action_pressed(ACTION_CONTEXT)


func get_camera_orbit_axis() -> float:
	if not is_controller_ready():
		return 0.0
	var left_strength := Input.get_action_strength(ACTION_CAMERA_ORBIT_LEFT)
	var right_strength := Input.get_action_strength(ACTION_CAMERA_ORBIT_RIGHT)
	return clampf(right_strength - left_strength, -1.0, 1.0)


func requires_controller_attention() -> bool:
	return not is_controller_ready() and (OS.get_name() == "Android" or _had_controller)


func get_diagnostic_text() -> String:
	if not is_controller_ready():
		return "GAMEPAD: NOT CONNECTED"
	var flight := get_flight_vector()
	var aim := get_aim_vector()
	var orbit := get_camera_orbit_axis()
	return "GAMEPAD: %s\nSTRAFE/DRIVE %+.2f %+.2f\nYAW/LIFT     %+.2f %+.2f\nL2/R2 CAMERA %+.2f\nL1 %s   R1 %s   L3 %s" % [
		active_device_name,
		flight.x,
		flight.y,
		aim.x,
		aim.y,
		orbit,
		"ON" if is_rockets_firing() else "--",
		"ON" if is_cannon_firing() else "--",
		"ON" if is_context_held() else "--",
	]


func apply_response_curve(value: Vector2) -> Vector2:
	var magnitude := value.length()
	if magnitude <= DEAD_ZONE:
		return Vector2.ZERO
	var remapped := (magnitude - DEAD_ZONE) / (1.0 - DEAD_ZONE)
	remapped = pow(clampf(remapped, 0.0, 1.0), RESPONSE_EXPONENT)
	return value.normalized() * remapped


func _select_initial_controller() -> void:
	var connected := Input.get_connected_joypads()
	if connected.is_empty():
		_clear_controller(false)
		return
	_set_active_controller(int(connected[0]))


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_set_active_controller(device)
		return
	if device != active_device:
		return
	var remaining := Input.get_connected_joypads()
	if not remaining.is_empty():
		_set_active_controller(int(remaining[0]))
	else:
		_clear_controller(true)


func _set_active_controller(device: int) -> void:
	active_device = device
	active_device_name = Input.get_joy_name(device)
	active_device_guid = Input.get_joy_guid(device)
	_had_controller = true
	if _paused_for_controller:
		get_tree().paused = false
		_paused_for_controller = false
	connection_changed.emit(true, active_device, active_device_name)
	controller_attention_changed.emit(false, "", "")


func _clear_controller(disconnected_during_play: bool) -> void:
	active_device = -1
	active_device_name = ""
	active_device_guid = ""
	connection_changed.emit(false, -1, "")
	var must_pause := OS.get_name() == "Android" or disconnected_during_play or _had_controller
	if must_pause:
		_paused_for_controller = true
		get_tree().paused = true
		var title := "CONTROLLER DISCONNECTED" if disconnected_during_play or _had_controller else "CONNECT CONTROLLER"
		controller_attention_changed.emit(
			true,
			title,
			"Connect or wake a Bluetooth gamepad. Play resumes automatically when Android reports it."
		)
	else:
		controller_attention_changed.emit(false, "", "")


func _register_input_actions() -> void:
	_add_axis_action(ACTION_FLIGHT_LEFT, JoyAxis.JOY_AXIS_LEFT_X, -1.0)
	_add_axis_action(ACTION_FLIGHT_RIGHT, JoyAxis.JOY_AXIS_LEFT_X, 1.0)
	_add_axis_action(ACTION_FLIGHT_FORWARD, JoyAxis.JOY_AXIS_LEFT_Y, -1.0)
	_add_axis_action(ACTION_FLIGHT_BACK, JoyAxis.JOY_AXIS_LEFT_Y, 1.0)
	_add_axis_action(ACTION_AIM_LEFT, JoyAxis.JOY_AXIS_RIGHT_X, -1.0)
	_add_axis_action(ACTION_AIM_RIGHT, JoyAxis.JOY_AXIS_RIGHT_X, 1.0)
	_add_axis_action(ACTION_AIM_FORWARD, JoyAxis.JOY_AXIS_RIGHT_Y, -1.0)
	_add_axis_action(ACTION_AIM_BACK, JoyAxis.JOY_AXIS_RIGHT_Y, 1.0)
	_add_axis_action(ACTION_CAMERA_ORBIT_LEFT, JoyAxis.JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_axis_action(ACTION_CAMERA_ORBIT_RIGHT, JoyAxis.JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_button_action(ACTION_FLIGHT_MODE, JoyButton.JOY_BUTTON_Y)
	_add_button_action(ACTION_SETTINGS, JoyButton.JOY_BUTTON_X)
	_add_button_action(ACTION_FREE_LOOK, JoyButton.JOY_BUTTON_RIGHT_SHOULDER)
	# The cannon moves off R1, which is now free look. Nothing fires yet, so
	# this costs nothing today.
	# L3: the only button reachable without releasing either stick, so the gun
	# fires while the player is still flying and holding R1 to aim.
	_add_button_action(ACTION_CANNON, JoyButton.JOY_BUTTON_LEFT_STICK)
	_add_button_action(ACTION_ROCKETS, JoyButton.JOY_BUTTON_LEFT_SHOULDER)
	_add_button_action(ACTION_CAMERA_TRAVEL_TOGGLE, JoyButton.JOY_BUTTON_RIGHT_STICK)
	# Displaced from L3 by the cannon; A is the slot the cannon vacated.
	_add_button_action(ACTION_CONTEXT, JoyButton.JOY_BUTTON_A)
	_add_button_action(ACTION_TARGET_PREVIOUS, JoyButton.JOY_BUTTON_DPAD_LEFT)
	_add_button_action(ACTION_TARGET_NEXT, JoyButton.JOY_BUTTON_DPAD_RIGHT)
	_add_button_action(ACTION_ZOOM_IN, JoyButton.JOY_BUTTON_DPAD_UP)
	_add_button_action(ACTION_ZOOM_OUT, JoyButton.JOY_BUTTON_DPAD_DOWN)


func _add_axis_action(action: StringName, axis: JoyAxis, axis_value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEAD_ZONE)
	else:
		InputMap.action_set_deadzone(action, DEAD_ZONE)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadMotion and existing.axis == axis and is_equal_approx(existing.axis_value, axis_value):
			return
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis
	event.axis_value = axis_value
	InputMap.action_add_event(action, event)


func _add_button_action(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEAD_ZONE)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton and existing.button_index == button:
			return
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	InputMap.action_add_event(action, event)
