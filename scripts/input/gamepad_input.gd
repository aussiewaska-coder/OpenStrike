extends Node

signal connection_changed(connected: bool, device_id: int, device_name: String)
signal controller_attention_changed(required: bool, title: String, detail: String)
signal action_pressed(action: StringName)
## Carries how long the button was down, which is what lets one button mean two
## things. Emitted for every action in BUTTON_ACTIONS, not just X.
signal action_released(action: StringName, held_seconds: float)

const DEAD_ZONE := 0.18
const RESPONSE_EXPONENT := 1.0
const TRIGGER_DEAD_ZONE := 0.04

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
## Tap cycles the weapon; holding the same button opens settings. X was the only
## button left, and settings is not something anyone reaches for mid-fight.
const ACTION_WEAPON_CYCLE := &"weapon_cycle"
## How long X must be held to mean settings rather than a weapon change.
const SETTINGS_HOLD_SECONDS := 0.45
## B is the only face button the existing scheme leaves free.
const ACTION_SWITCH_AIRCRAFT := &"switch_aircraft"
## On the helicopter R1 retains manual aim. On the F-22 it modifies the right
## stick into a persistent throttle control.
const ACTION_FREE_LOOK := &"free_look"
const ACTION_CAMERA_ORBIT_LEFT := &"camera_orbit_left"
const ACTION_CAMERA_ORBIT_RIGHT := &"camera_orbit_right"
const ACTION_RUDDER_LEFT := &"rudder_left"
const ACTION_RUDDER_RIGHT := &"rudder_right"

const BUTTON_ACTIONS: Array[StringName] = [
	ACTION_CAMERA_TRAVEL_TOGGLE,
	ACTION_CONTEXT,
	ACTION_TARGET_PREVIOUS,
	ACTION_TARGET_NEXT,
	ACTION_ZOOM_IN,
	ACTION_ZOOM_OUT,
	ACTION_WEAPON_CYCLE,
]

var active_device := -1
var active_device_name := ""
var active_device_guid := ""
var _had_controller := false
var _paused_for_controller := false
## When each button went down, so the release can report how long it was held.
var _hold_started: Dictionary = {}
var _left_trigger_rest := 0.0
var _right_trigger_rest := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_input_actions()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_select_initial_controller()


func _process(_delta: float) -> void:
	if active_device < 0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for action in BUTTON_ACTIONS:
		if Input.is_action_just_pressed(action):
			_hold_started[action] = now
			action_pressed.emit(action)
		elif Input.is_action_just_released(action):
			# Missing start means the press predates this poll loop; treating it
			# as instantaneous makes it a tap, which is the harmless reading.
			var started: float = _hold_started.get(action, now)
			_hold_started.erase(action)
			action_released.emit(action, now - started)


## A press is a hold once it passes the threshold. Static so the decision can be
## tested without a controller attached.
static func is_hold(held_seconds: float) -> bool:
	return held_seconds >= SETTINGS_HOLD_SECONDS


func is_controller_ready() -> bool:
	return active_device >= 0 and active_device in Input.get_connected_joypads()


func get_flight_vector() -> Vector2:
	if not is_controller_ready():
		return Vector2.ZERO
	return apply_response_curve(apply_circular_deadzone(get_raw_flight_vector()))


func get_aim_vector() -> Vector2:
	if not is_controller_ready():
		return Vector2.ZERO
	return apply_response_curve(apply_circular_deadzone(get_raw_aim_vector()))


func get_raw_flight_vector() -> Vector2:
	if not is_controller_ready():
		return Vector2.ZERO
	return Vector2(
		Input.get_joy_axis(active_device, JoyAxis.JOY_AXIS_LEFT_X),
		Input.get_joy_axis(active_device, JoyAxis.JOY_AXIS_LEFT_Y)
	)


func get_raw_aim_vector() -> Vector2:
	if not is_controller_ready():
		return Vector2.ZERO
	return Vector2(
		Input.get_joy_axis(active_device, JoyAxis.JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(active_device, JoyAxis.JOY_AXIS_RIGHT_Y)
	)


## Raw trigger values are exposed in telemetry because Android controller
## drivers legitimately report either 0 or -1 at rest.
func get_raw_trigger_vector() -> Vector2:
	if not is_controller_ready():
		return Vector2.ZERO
	return Vector2(
		Input.get_joy_axis(active_device, JoyAxis.JOY_AXIS_TRIGGER_LEFT),
		Input.get_joy_axis(active_device, JoyAxis.JOY_AXIS_TRIGGER_RIGHT)
	)


func get_flight_yaw_collective_vector() -> Vector2:
	return route_aim_input_to_flight(get_aim_vector(), is_free_look_held())


static func route_aim_input_to_flight(aim_input: Vector2, free_look_held: bool) -> Vector2:
	return Vector2.ZERO if free_look_held else aim_input


func is_free_look_held() -> bool:
	return is_controller_ready() and Input.is_joy_button_pressed(
		active_device,
		JoyButton.JOY_BUTTON_RIGHT_SHOULDER
	)


## R1 turns right-stick vertical motion into a rate that moves the persistent
## throttle from its current position. Stick up opens it; stick down closes it.
func get_jet_throttle_axis() -> float:
	return jet_throttle_axis(get_aim_vector(), is_free_look_held())


## The same R1 that claims the right stick for throttle also hands the nose to
## the vectoring nozzles on the LEFT stick. The two never collide because they
## read different sticks, which is why this is the same button rather than one
## of the none that were left.
func is_vectoring_held() -> bool:
	return is_free_look_held()


func get_jet_look_vector() -> Vector2:
	return jet_look_vector(get_aim_vector(), is_free_look_held())


static func jet_throttle_axis(aim_input: Vector2, modifier_held: bool) -> float:
	return clampf(-aim_input.y, -1.0, 1.0) if modifier_held else 0.0


static func jet_look_vector(aim_input: Vector2, modifier_held: bool) -> Vector2:
	return Vector2.ZERO if modifier_held else aim_input


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


## Positive yaws right. L2 is left rudder and R2 is right rudder.
func get_rudder_axis() -> float:
	if not is_controller_ready():
		return 0.0
	var raw := get_raw_trigger_vector()
	var left_strength := normalized_trigger(raw.x, _left_trigger_rest)
	var right_strength := normalized_trigger(raw.y, _right_trigger_rest)
	return clampf(right_strength - left_strength, -1.0, 1.0)


## Supports both Android's 0..1 trigger range and drivers that expose triggers
## as centred axes with -1 at rest. The resting value is sampled per device.
static func normalized_trigger(raw_value: float, rest_value: float) -> float:
	var strength := 0.0
	if rest_value < -0.5:
		strength = (raw_value - rest_value) / maxf(1.0 - rest_value, 0.001)
	else:
		strength = raw_value - rest_value
	strength = clampf(strength, 0.0, 1.0)
	if strength <= TRIGGER_DEAD_ZONE:
		return 0.0
	return (strength - TRIGGER_DEAD_ZONE) / (1.0 - TRIGGER_DEAD_ZONE)


func requires_controller_attention() -> bool:
	return not is_controller_ready() and (OS.get_name() == "Android" or _had_controller)


func get_diagnostic_text() -> String:
	if not is_controller_ready():
		return "GAMEPAD: NOT CONNECTED"
	var flight := get_flight_vector()
	var aim := get_aim_vector()
	var raw_flight := get_raw_flight_vector()
	var raw_aim := get_raw_aim_vector()
	var raw_triggers := get_raw_trigger_vector()
	return "GAMEPAD: %s\nLEFT  RAW %+.2f %+.2f  OUT %+.2f %+.2f\nRIGHT RAW %+.2f %+.2f  OUT %+.2f %+.2f\nL2/R2 RAW %+.2f %+.2f  RUDDER %+.2f" % [
		active_device_name,
		raw_flight.x,
		raw_flight.y,
		flight.x,
		flight.y,
		raw_aim.x,
		raw_aim.y,
		aim.x,
		aim.y,
		raw_triggers.x,
		raw_triggers.y,
		get_rudder_axis(),
	]


func apply_response_curve(value: Vector2) -> Vector2:
	var magnitude := clampf(value.length(), 0.0, 1.0)
	if is_zero_approx(magnitude):
		return Vector2.ZERO
	return value.normalized() * pow(magnitude, RESPONSE_EXPONENT)


static func apply_circular_deadzone(value: Vector2) -> Vector2:
	var magnitude := value.length()
	if magnitude <= DEAD_ZONE:
		return Vector2.ZERO
	var remapped := (magnitude - DEAD_ZONE) / (1.0 - DEAD_ZONE)
	return value.normalized() * clampf(remapped, 0.0, 1.0)


static func controller_preference_score(device_name: String) -> int:
	var lowered := device_name.to_lower()
	if lowered.contains("virtual"):
		return -100
	if lowered.contains("dualsense") or lowered.contains("dualshock") \
		or lowered.contains("wireless controller") or lowered.contains("sony"):
		return 100
	return 0


func _select_initial_controller() -> void:
	var connected := Input.get_connected_joypads()
	if connected.is_empty():
		_clear_controller(false)
		return
	var preferred := int(connected[0])
	var preferred_score := controller_preference_score(Input.get_joy_name(preferred))
	for candidate_value in connected:
		var candidate := int(candidate_value)
		var score := controller_preference_score(Input.get_joy_name(candidate))
		if score > preferred_score:
			preferred = candidate
			preferred_score = score
	_set_active_controller(preferred)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_select_initial_controller()
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
	_left_trigger_rest = Input.get_joy_axis(device, JoyAxis.JOY_AXIS_TRIGGER_LEFT)
	_right_trigger_rest = Input.get_joy_axis(device, JoyAxis.JOY_AXIS_TRIGGER_RIGHT)
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
	_add_axis_action(ACTION_RUDDER_LEFT, JoyAxis.JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_axis_action(ACTION_RUDDER_RIGHT, JoyAxis.JOY_AXIS_TRIGGER_RIGHT, 1.0)
	# Y and B are deliberately unbound. Flight mode and switch-aircraft live in
	# the settings panel now, and both buttons are reserved for the lock-on
	# controls in the next phase.
	# X taps to cycle weapons and holds to open settings. The settings action
	# keeps its constant for main.gd but no longer has a button of its own; the
	# on-screen SETTINGS button calls the panel directly, so a mistimed hold can
	# never lock anyone out of it.
	_add_button_action(ACTION_WEAPON_CYCLE, JoyButton.JOY_BUTTON_X)
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
