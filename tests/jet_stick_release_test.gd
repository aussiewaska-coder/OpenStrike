extends SceneTree

const JET := preload("res://scripts/jet/jet_controller.gd")
const GAMEPAD := preload("res://scripts/input/gamepad_input.gd")
const STEP := 1.0 / 60.0

class Pilot:
	extends GAMEPAD
	var stick := Vector2.ZERO
	func _ready() -> void:
		set_process(false)
	func is_controller_ready() -> bool:
		return true
	func get_raw_flight_vector() -> Vector2:
		return stick
	func get_raw_trigger_vector() -> Vector2:
		return Vector2.ZERO
	func get_jet_throttle_axis() -> float:
		return 0.0

var pilot: Pilot
var failed := false

func _init() -> void:
	call_deferred("_run")

func _jet(pitch := 0.0, bank := 0.0):
	var jet = JET.new()
	root.add_child(jet)
	jet.set_physics_process(false)
	jet._world_limit = 100000.0
	jet.minimum_display_speed = 175.0
	jet.maximum_display_speed = 175.0
	jet.launch(Vector3(0, 3000, 0), 0.0)
	jet.basis = JET.rotate_body(jet.basis, 0.0, deg_to_rad(pitch) - asin(jet.basis.x.y), 0.0, 1.0)
	jet.basis = JET.rotate_body(jet.basis, deg_to_rad(bank), 0.0, 0.0, 1.0)
	jet.velocity = jet.basis.x * 175.0
	return jet

func _attitude(jet) -> Vector2:
	return Vector2(rad_to_deg(JET.bank_angle(jet.basis)), rad_to_deg(asin(clampf(jet.basis.x.y, -1.0, 1.0))))

func _run() -> void:
	var old_pad := root.get_node("GamepadInput")
	old_pad.name = "ParkedGamepad"
	old_pad.set_process(false)
	pilot = Pilot.new()
	pilot.name = "GamepadInput"
	root.add_child(pilot)
	# Exercise actual input routing and controller integration. A short stick
	# correction must stop near the attitude at release, in either direction.
	for stick in [Vector2(1, 0), Vector2(-1, 0), Vector2(0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5)]:
		var jet = _jet()
		# Fixture values are logical roll/pitch; the requested physical layout
		# sends pitch on X and roll on Y.
		pilot.stick = stick
		for frame in range(30):
			jet._physics_process(STEP)
		var released := _attitude(jet)
		pilot.stick = Vector2.ZERO
		for frame in range(30):
			jet._physics_process(STEP)
		var overrun := _attitude(jet) - released
		print("STICK_RELEASE input=%s release=%s overrun=%s" % [stick, released, overrun])
		_check(absf(overrun.x) < 4.0, "roll must stop within four degrees after stick release")
		_check(absf(overrun.y) < 1.5, "pitch must stop within 1.5 degrees after stick release")
		_check(released.length() > 5.0, "the correction must retain useful control authority")
		jet.free()
	# A held bank must stay held in a climb or descent too. The old level-only
	# coordination deepened a 30-degree climbing bank by nearly nine degrees.
	for pitch in [-20.0, 0.0, 20.0]:
		for bank in [-30.0, 30.0]:
			var jet = _jet(pitch, bank)
			for frame in range(600):
				jet._physics_process(STEP)
			var final := _attitude(jet)
			print("BANK_HOLD pitch=%.1f bank=%.1f final=%s" % [pitch, bank, final])
			_check(absf(final.x - bank) < 2.0, "neutral climbing/descending bank must not drift or auto-level")
			_check(absf(final.y - pitch) < 2.0, "turn coordination must preserve the selected pitch")
			jet.free()
	if not failed:
		print("JET_STICK_RELEASE_TEST_PASS")
	quit(1 if failed else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
