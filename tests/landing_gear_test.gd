extends SceneTree

const JET := preload("res://scripts/jet/jet_controller.gd")
const RUNWAYS := preload("res://scripts/world/runways.gd")

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

class Ground:
	extends Node
	var h := 50.0
	func sample_height_world(_x: float, _z: float) -> float: return h
	func world_half_extent() -> float: return 100000.0

var _failures := []


func check(cond: bool, message: String) -> void:
	if not cond:
		_failures.append(message)
		push_error("landing: " + message)


func _init(): call_deferred("_run")


func _run():
	var old := root.get_node("GamepadInput")
	root.remove_child(old)
	var pad := Pad.new()
	pad.name = "GamepadInput"
	root.add_child(pad)
	var ground := Ground.new()
	root.add_child(ground)
	var jet := JET.new()
	root.add_child(jet)
	jet.set_physics_process(false)
	jet.set_terrain(ground)
	jet.launch(Vector3(0, 1000, 0), 0.0)

	# Gear lever below the limit.
	jet.velocity = Vector3(0, 0, -80)
	jet.toggle_gear()
	check(jet.gear_down, "gear deploys below blowout speed")
	jet.toggle_gear()
	check(not jet.gear_down, "gear stows again")

	# Gear overspeed destroys and jams.
	jet.velocity = Vector3(0, 0, -200)
	jet.toggle_gear()
	check(jet.gear_damaged and not jet.gear_down, "overspeed gear deployment jams up")
	jet.velocity = Vector3(0, 0, -40)
	jet.toggle_gear()
	check(not jet.gear_down, "jammed gear stays up")

	# Flaps mirror the gear.
	jet.launch(Vector3(0, 1000, 0), 0.0)
	jet.velocity = Vector3(0, 0, -100)
	jet.toggle_flaps()
	check(jet.flaps_down, "flaps deploy below placard")
	var clean_vr := jet.rotation_speed_mps()
	jet.toggle_flaps()
	check(jet.rotation_speed_mps() > clean_vr, "flaps lower rotation speed")
	jet.velocity = Vector3(0, 0, -250)
	jet.toggle_flaps()
	jet.toggle_flaps()
	check(jet.flaps_damaged and not jet.flaps_down, "flap overspeed jams up")

	# Gentle gear-down contact is a touchdown, not a crash.
	jet.launch(Vector3(0, 1000, 0), 0.0)
	jet.velocity = Vector3(0, 0, -80)
	jet.toggle_gear()
	jet.global_position = Vector3(0, 50.0 + jet.hull_clearance_m - 0.05, 0)
	jet.velocity = Vector3(0, -3.0, -80)
	var touched := [false]
	jet.touched_down.connect(func(): touched[0] = true)
	jet._check_ground()
	check(jet.rolling and not jet.is_crashed(), "gentle gear-down contact rolls")
	check(touched[0], "touchdown emits")

	# Crash cases stay crashes.
	for case in ["gear_up", "hard", "banked", "water"]:
		jet.launch(Vector3(0, 1000, 0), 0.0)
		jet.velocity = Vector3(0, 0, -80)
		if case != "gear_up":
			jet.toggle_gear()
		jet.global_position = Vector3(0, 50.0 + jet.hull_clearance_m - 0.05, 0)
		jet.velocity = Vector3(0, -3.0, -80)
		if case == "hard":
			jet.velocity.y = -12.0
		if case == "banked":
			jet.basis = jet.basis.rotated(jet.basis.x, deg_to_rad(30.0))
		if case == "water":
			ground.h = 0.0
			jet.global_position = Vector3(0, jet.hull_clearance_m - 0.05, 0)
		jet._check_ground()
		check(jet.is_crashed() and not jet.rolling, "contact stays a crash: " + case)
		ground.h = 50.0

	# Ground roll: throttle builds speed, brakes stop, rotation lifts off.
	jet.launch_rolling(Vector3(0, 52.5, 0), 0.0)
	check(jet.rolling and jet.gear_down, "runway start lines up rolling with gear down")
	pad.buttons[1] = true
	for frame in range(1200):
		jet._roll(1.0 / 60.0)
		if jet.is_crashed():
			break
	check(not jet.is_crashed(), "takeoff roll stays on the strip")
	check(jet.velocity.length() > 60.0, "full throttle accelerates the roll")
	pad.buttons.clear()
	pad.pedals = true
	var entry := jet.velocity.length()
	for frame in range(300):
		jet._roll(1.0 / 60.0)
	check(jet.velocity.length() < entry - 20.0, "brakes shed rollout speed")
	pad.pedals = false
	pad.buttons[1] = true
	for frame in range(600):
		jet._roll(1.0 / 60.0)
		if not jet.rolling:
			break
	pad.stick = Vector2(0, 1.0)
	var off := [false]
	jet.lifted_off.connect(func(): off[0] = true)
	for frame in range(600):
		jet._roll(1.0 / 60.0)
		if not jet.rolling:
			break
	check(not jet.rolling and off[0], "pulling back past rotation speed lifts off")

	# Runway database.
	check(RUNWAYS.for_region("au_nsw_sydney_harbour").size() == 3, "Sydney has three runways")
	check(RUNWAYS.for_region("au_gold_coast_tweed_corridor").size() == 1, "Gold Coast has one runway")
	check(RUNWAYS.for_region("nowhere").is_empty(), "unknown theatres have no runways")
	var strip := RUNWAYS.default_runway("au_nsw_sydney_harbour")
	check(String(strip.get("id", "")) == "16R", "longest Sydney runway is the default")
	var thr: Vector2 = RUNWAYS.threshold_latlon(strip)
	check(thr.x > float(strip.get("center_lat", 0.0)), "16R threshold sits north of centre for a 160 takeoff")

	jet.free()
	pad.free()
	ground.free()
	root.add_child(old)
	if _failures.is_empty():
		print("LANDING_GEAR_TEST_PASS")
	else:
		push_error("LANDING FAILURES: %d" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
