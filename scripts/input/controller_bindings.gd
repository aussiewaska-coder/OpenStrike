extends RefCounted

## One portable custom layout. UI navigation stays available independently.
const PATH := "user://controller_bindings.cfg"
const ACTIONS := [
	["flight_left", "Roll left", 0, -1], ["flight_right", "Roll right", 0, 1],
	["flight_forward", "Pitch forward", 1, -1], ["flight_back", "Pitch back", 1, 1],
	["aim_left", "Look / yaw left", 2, -1], ["aim_right", "Look / yaw right", 2, 1],
	["aim_forward", "Look up / collective up", 3, -1], ["aim_back", "Look down / collective down", 3, 1],
	["rudder_left", "Left rudder", 4, 1], ["rudder_right", "Right rudder", 5, 1],
	["free_look", "Apache manual aim modifier", 0],
	["weapon_cannon", "Fire cannon", 7], ["weapon_rockets", "Fire missile / rockets", 9],
	["track_target", "Track target", 10], ["camera_travel_toggle", "Recenter / change view", 8],
	["weapon_cycle", "Cycle weapon / hold for settings", 2],
	["target_previous", "Previous target / jet view", 13], ["target_next", "Next target / jet view", 14],
	["camera_zoom_in", "Zoom in", 11], ["camera_zoom_out", "Zoom out", 12],
	["tactical_map", "Tactical map / close map", 3],
	["camera_orbit_left", "Apache orbit left", 5, 1], ["camera_orbit_right", "Apache orbit right", 4, 1],
	["throttle_up", "Throttle up (Home)", 5],
	["throttle_down", "Throttle down (Turbo)", -1],
]
const BUTTON_NAMES := ["A / Cross", "B / Circle", "X / Square", "Y / Triangle", "Back / Share", "Home / Guide", "Start / Options", "L3", "R3", "LB / L1", "RB / R1", "D-pad up", "D-pad down", "D-pad left", "D-pad right"]
const AXIS_NAMES := ["Left stick X", "Left stick Y", "Right stick X", "Right stick Y", "LT / L2", "RT / R2"]
var values: Dictionary = {}

func _init() -> void:
	reset()

func reset() -> void:
	values.clear()
	for row in ACTIONS:
		if row[2] == -1:
			values[row[0]] = {"type": "unassigned"}
			continue
		values[row[0]] = {"type": "axis", "index": row[2], "sign": row[3]} if row.size() == 4 else {"type": "button", "index": row[2]}

static func valid(binding: Variant) -> bool:
	if binding is Dictionary and binding == {"type": "unassigned"}:
		return true
	if not binding is Dictionary or not binding.get("index") is int:
		return false
	var index: int = binding.index
	if binding.get("type") == "button":
		return index >= 0 and index < JOY_BUTTON_MAX
	return binding.get("type") == "axis" and index >= 0 and index < JOY_AXIS_MAX and binding.get("sign") in [-1, 1]

static func label(binding: Dictionary) -> String:
	if binding.type == "unassigned":
		return "Unassigned · Detect button"
	var index: int = binding.index
	if binding.type == "button":
		return BUTTON_NAMES[index] if index < BUTTON_NAMES.size() else "Button %d" % index
	var name: String = AXIS_NAMES[index] if index < AXIS_NAMES.size() else "Axis %d" % index
	return "%s %s" % [name, "+" if binding.sign > 0 else "−"]

func shared(action: String, binding: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for row in ACTIONS:
		if row[0] != action and values[row[0]] == binding:
			result.append(row[1])
	return result

func save_to(path := PATH) -> Error:
	var config := ConfigFile.new()
	for action in values:
		config.set_value("bindings", action, values[action])
	return config.save(path)

func load_from(path := PATH) -> Error:
	reset()
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return error
	for action in values:
		var binding = config.get_value("bindings", action, values[action])
		if valid(binding):
			values[action] = binding.duplicate()
	return OK

func apply_input_map() -> void:
	for action in values:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.18)
		# Preserve keyboard bindings if the desktop build supplies them.
		for old in InputMap.action_get_events(action):
			if old is InputEventJoypadButton or old is InputEventJoypadMotion:
				InputMap.action_erase_event(action, old)
		var binding: Dictionary = values[action]
		if binding.type == "unassigned":
			continue
		var event: InputEvent
		if binding.type == "button":
			event = InputEventJoypadButton.new()
			event.button_index = binding.index
		else:
			event = InputEventJoypadMotion.new()
			event.axis = binding.index
			event.axis_value = binding.sign
		event.device = -1
		InputMap.action_add_event(action, event)
