extends SceneTree
const JET := preload("res://scripts/jet/jet_controller.gd")
class Pad:
	extends "res://scripts/input/gamepad_input.gd"
	var buttons := {}
	var stick := Vector2.ZERO
	var pedals := false
	func _ready():
		active_device = 2
		set_process(false)
	func is_controller_ready() -> bool: return true
	func _read_button(index: int) -> bool: return buttons.get(index, false)
	func get_flight_vector() -> Vector2: return stick
	func get_rudder_axis() -> float: return 0.0
	func is_vectoring_held() -> bool: return pedals

func _init(): call_deferred("_run")
func _run():
	var old := root.get_node("GamepadInput")
	root.remove_child(old)
	var pad := Pad.new()
	pad.name = "GamepadInput"
	root.add_child(pad)
	var jet := JET.new()
	root.add_child(jet)
	jet.set_physics_process(false)
	jet._world_limit = 100000.0
	jet.launch(Vector3(0, 1000, 0), 0.0)
	pad.buttons[5] = true
	assert(pad.get_jet_throttle_axis() == 0.0, "Home alone leaves throttle unchanged")
	pad.buttons[11] = true
	jet._read_controls(0.5)
	var opened := jet.throttle
	assert(opened > 0.85, "Home plus up opens throttle")
	pad.buttons.clear()
	jet._read_controls(0.5)
	assert(jet.throttle == opened, "release holds throttle")
	pad.buttons[12] = true
	assert(pad.get_jet_throttle_axis() == 0.0, "D-pad alone leaves throttle unchanged")
	pad.buttons[5] = true
	jet._read_controls(0.5)
	assert(jet.throttle < opened - 0.2, "Home plus down closes throttle")
	pad.buttons[11] = true
	assert(pad.get_jet_throttle_axis() == 0.0, "opposing buttons cancel")
	pad._settings_open = true
	pad.buttons.erase(12)
	assert(pad.get_jet_throttle_axis() == 0.0)
	pad._settings_open = false
	pad.buttons.clear()
	var speeds: Array[float] = []
	for braking in [false, true]:
		jet.launch(Vector3(0, 1000, 0), 0.0)
		pad.pedals = braking
		for frame in range(180):
			jet._read_controls(1.0/60.0)
			jet._integrate(1.0/60.0)
		speeds.append(jet.velocity.length())
		assert(absf(jet.bank) < 0.01, "brake must not roll the aircraft")
	assert(speeds[1] < speeds[0] - 20.0, "level-flight brakes noticeably shed speed")
	assert(jet.airbrake > 0.99 and not jet.vectoring)
	pad.stick = Vector2(0.4, 0.6)
	jet._read_controls(1.0/60.0)
	assert(jet.vectoring, "manoeuvring immediately restores vectoring")
	for frame in range(30): jet._read_controls(1.0/60.0)
	assert(jet.airbrake == 0.0, "brake stows during turn")
	jet.free()
	pad.free()
	root.add_child(old)
	print("JET_BRAKE_THROTTLE_TEST_PASS")
	quit()
