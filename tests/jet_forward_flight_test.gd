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

var failed := false
var pilot: Pilot

func _init() -> void:
	call_deferred("_run")

func _jet(speed: float):
	var jet = JET.new()
	root.add_child(jet)
	jet.set_physics_process(false)
	jet._world_limit = 100000.0
	jet.minimum_display_speed = speed
	jet.maximum_display_speed = speed
	jet.launch(Vector3(0, 900, 0), 0.0)
	return jet

func _run() -> void:
	var old := root.get_node("GamepadInput")
	old.name = "ParkedGamepad"
	old.set_process(false)
	pilot = Pilot.new()
	pilot.name = "GamepadInput"
	root.add_child(pilot)
	# User-requested swap, exercised through the actual physical-axis routing.
	for sign_value in [-1.0, 1.0]:
		var jet = _jet(175.0)
		pilot.stick = Vector2(sign_value, 0)
		jet._read_controls(STEP)
		_check(jet.roll_input * sign_value > 0.99 and is_zero_approx(jet.pitch_input), "left/right stick must command roll only")
		jet.free()
		jet = _jet(175.0)
		pilot.stick = Vector2(0, sign_value)
		jet._read_controls(STEP)
		_check(jet.pitch_input * sign_value > 0.99 and is_zero_approx(jet.roll_input), "up/down stick must command pitch only")
		jet.free()
	pilot.stick = Vector2.ZERO
	# The phone trace showed over 33 degrees of slip at 55 m/s with no stick
	# input. Recreate cross-body motion, then measure actual travel after release.
	for speed in [55.0, 175.0]:
		for sign_value in [-1.0, 1.0]:
			var jet = _jet(speed)
			jet.velocity = jet.velocity.rotated(jet.basis.y, deg_to_rad(35.0) * sign_value)
			var start: Vector3 = jet.position
			for frame in range(30):
				jet._physics_process(STEP)
			var local_velocity: Vector3 = jet.basis.inverse() * jet.velocity
			var slip := rad_to_deg(atan2(local_velocity.z, absf(local_velocity.x)))
			print("FORWARD_FLIGHT speed=%.0f sign=%.0f slip_after_half_second=%.2f" % [speed, sign_value, slip])
			_check(absf(slip) < 5.0, "released jet must follow its nose within half a second, including at low speed")
			_check(local_velocity.x > 0.0 and (jet.position - start).dot(jet.basis.x) > 0.0, "the jet must travel forward")
			_check(jet.airspeed() < speed + 5.0 and jet.airspeed() > speed * 0.85, "direction correction must not invent speed or stop the aircraft")
			jet.free()
	# Keeping a roll held must still complete an aerobatic roll without the
	# aircraft strafing or reversing its travel underneath the visual model.
	var rolling = _jet(175.0)
	pilot.stick = Vector2(1, 0)
	var turned := 0.0
	var previous_bank := 0.0
	var worst_slip := 0.0
	var least_forward := 1.0
	for frame in range(300):
		rolling._physics_process(STEP)
		var bank: float = JET.bank_angle(rolling.basis)
		turned += wrapf(bank - previous_bank, -PI, PI)
		previous_bank = bank
		worst_slip = maxf(worst_slip, absf(rad_to_deg(rolling.beta)))
		least_forward = minf(least_forward, rolling.velocity.normalized().dot(rolling.basis.x))
	print("FORWARD_ROLL turned=%.1f slip=%.2f forward=%.3f" % [rad_to_deg(turned), worst_slip, least_forward])
	_check(turned > TAU, "holding horizontal stick must still complete a full roll")
	_check(worst_slip < 5.0 and least_forward > 0.9, "a sustained roll must keep flying forward")
	rolling.free()
	if not failed:
		print("JET_FORWARD_FLIGHT_TEST_PASS")
	quit(1 if failed else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
