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

	# B opens the throttle and A closes it, with no modifier and no zoom.
	pad.buttons = {1: true}
	pad._process(0.016)
	assert(main._camera_zoom == 1.0 and pad.get_jet_throttle_axis() == 1.0, "B must throttle up on its own")
	pad.buttons.clear()
	pad._process(0.016)
	assert(pad.get_jet_throttle_axis() == 0.0, "releasing B holds the throttle")
	pad.buttons = {0: true}
	pad._process(0.016)
	assert(main._camera_zoom == 1.0 and pad.get_jet_throttle_axis() == -1.0, "A must throttle down on its own")
	pad.buttons = {0: true, 1: true}
	pad._process(0.016)
	assert(pad.get_jet_throttle_axis() == 0.0, "opposing buttons cancel")
	pad.buttons.clear()
	pad._process(0.016)

	# The D-pad is plain zoom again, with nothing to hold down first.
	pad.buttons[11] = true
	pad._process(0.016)
	assert(main._camera_zoom < 1.0 and pad.get_jet_throttle_axis() == 0.0, "D-pad up zooms only")
	pad.buttons.clear()
	pad._process(0.016)
	var zoom: float = main._camera_zoom
	pad.buttons[12] = true
	pad._process(0.016)
	assert(main._camera_zoom > zoom and pad.get_jet_throttle_axis() == 0.0, "D-pad down zooms out only")
	pad.buttons.clear()
	pad._process(0.016)

	pad._settings_open = true
	pad.buttons = {1: true}
	assert(pad.get_jet_throttle_axis() == 0.0, "menu input must not change throttle")
	pad._settings_open = false
	pad._tactical_open = true
	assert(pad.get_jet_throttle_axis() == 0.0, "map input must not change throttle")
	pad._tactical_open = false
	pad.action_pressed.disconnect(main._on_gamepad_action_pressed)
	main.free()
	pad.set_script(original_script)

	# A layout saved before either throttle change migrates all the way to B/A.
	var path := "user://throttle_combo_migration_test.cfg"
	var legacy := ConfigFile.new()
	legacy.set_value("bindings", "throttle_up", {"type": "button", "index": 5})
	legacy.set_value("bindings", "throttle_down", {"type": "unassigned"})
	legacy.set_value("bindings", "weapon_cannon", {"type": "button", "index": 16})
	assert(legacy.save(path) == OK)
	var layout := BINDINGS.new()
	assert(layout.load_from(path) == OK)
	assert(layout.values.throttle_up.index == 1 and layout.values.throttle_down.index == 0)
	assert(layout.values.weapon_cannon.index == 16, "migrate defaults without losing custom controls")
	assert(not layout.values.has("throttle_modifier"), "the throttle modifier is gone")

	# So does a layout left on the D-pad by the intermediate version.
	var dpad := ConfigFile.new()
	dpad.set_value("layout", "version", 2)
	dpad.set_value("bindings", "throttle_up", {"type": "button", "index": 11})
	dpad.set_value("bindings", "throttle_down", {"type": "button", "index": 12})
	assert(dpad.save(path) == OK)
	var moved := BINDINGS.new()
	assert(moved.load_from(path) == OK)
	assert(moved.values.throttle_up.index == 1 and moved.values.throttle_down.index == 0, "the shared D-pad layout moves to B/A")

	layout.values.throttle_up = {"type": "button", "index": 5}
	assert(layout.save_to(path) == OK)
	var reloaded := BINDINGS.new()
	assert(reloaded.load_from(path) == OK and reloaded.values.throttle_up.index == 5, "versioned custom layouts must not migrate repeatedly")
	DirAccess.remove_absolute(path)
	print("THROTTLE_ZOOM_COMBO_TEST_PASS")
	quit()
