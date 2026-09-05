extends SceneTree
const BINDINGS := preload("res://scripts/input/controller_bindings.gd")
class Pad:
	extends "res://scripts/input/gamepad_input.gd"
	var buttons := {}
	func is_controller_ready() -> bool: return true
	func _read_button(index: int) -> bool: return buttons.get(index, false)
	func _read_axis(_index: int) -> float: return 0.0
func _init(): call_deferred("_run")
func _run():
	var pad := root.get_node("GamepadInput")
	var original_script = pad.get_script()
	pad.set_script(Pad)
	pad.active_device = 2
	var main = load("res://scripts/main.gd").new()
	main._flying_jet = true
	pad.action_pressed.connect(main._on_gamepad_action_pressed)
	pad.buttons = {5: true, 11: true}
	pad._process(0.016)
	assert(main._camera_zoom == 1.0 and pad.get_jet_throttle_axis() == 1.0, "Home+up must throttle without zoom")
	pad.buttons.erase(5)
	pad._process(0.016)
	assert(main._camera_zoom == 1.0 and pad.get_jet_throttle_axis() == 0.0, "releasing Home first must not create a zoom press")
	pad.buttons.clear()
	pad._process(0.016)
	pad.buttons[11] = true
	pad._process(0.016)
	assert(main._camera_zoom < 1.0 and pad.get_jet_throttle_axis() == 0.0, "plain up zooms only")
	pad.buttons.clear()
	pad._process(0.016)
	var zoom: float = main._camera_zoom
	pad.buttons = {5: true, 12: true}
	pad._process(0.016)
	assert(main._camera_zoom == zoom and pad.get_jet_throttle_axis() == -1.0, "Home+down closes throttle without zoom")
	pad.buttons.clear()
	pad._process(0.016)
	pad.buttons[12] = true
	pad._process(0.016)
	assert(main._camera_zoom > zoom and pad.get_jet_throttle_axis() == 0.0, "plain down zooms out")
	pad._settings_open = true
	pad.buttons = {5: true, 11: true}
	assert(pad.get_jet_throttle_axis() == 0.0, "menu D-pad must not change throttle")
	pad.action_pressed.disconnect(main._on_gamepad_action_pressed)
	main.free()
	pad.set_script(original_script)

	var path := "user://throttle_combo_migration_test.cfg"
	var legacy := ConfigFile.new()
	legacy.set_value("bindings", "throttle_up", {"type": "button", "index": 5})
	legacy.set_value("bindings", "throttle_down", {"type": "unassigned"})
	legacy.set_value("bindings", "weapon_cannon", {"type": "button", "index": 16})
	assert(legacy.save(path) == OK)
	var layout := BINDINGS.new()
	assert(layout.load_from(path) == OK)
	assert(layout.values.throttle_up.index == 11 and layout.values.throttle_down.index == 12)
	assert(layout.values.throttle_modifier.index == 5 and layout.values.weapon_cannon.index == 16, "migrate old defaults without losing custom controls")
	layout.values.throttle_up = {"type": "button", "index": 5}
	assert(layout.save_to(path) == OK)
	var reloaded := BINDINGS.new()
	assert(reloaded.load_from(path) == OK and reloaded.values.throttle_up.index == 5, "versioned custom layouts must not migrate repeatedly")
	DirAccess.remove_absolute(path)
	print("THROTTLE_ZOOM_COMBO_TEST_PASS")
	quit()
