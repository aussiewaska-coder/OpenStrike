extends SceneTree

const GAMEPAD := preload("res://scripts/input/gamepad_input.gd")
const JET := preload("res://scripts/jet/jet_controller.gd")
const STEP := 1.0 / 60.0

class Pilot:
	extends GAMEPAD
	var stick := Vector2.ZERO
	var pedals := Vector2.ZERO
	var shoulder := false
	func _ready() -> void:
		set_process(false)
	func is_controller_ready() -> bool:
		return true
	func get_raw_trigger_vector() -> Vector2:
		return pedals
	func get_raw_flight_vector() -> Vector2:
		return stick
	func get_raw_aim_vector() -> Vector2:
		return Vector2.ZERO
	func is_free_look_held() -> bool:
		return shoulder

var pilot: Pilot
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var old_pad := root.get_node("GamepadInput")
	old_pad.name = "ParkedGamepad"
	old_pad.set_process(false)
	pilot = Pilot.new()
	pilot.name = "GamepadInput"
	root.add_child(pilot)
	pilot.pedals = Vector2.ONE
	check(pilot.is_vectoring_held(), "both yaw triggers must engage vectoring")
	check(is_zero_approx(pilot.get_rudder_axis()), "equal pedals must not command a yaw direction")
	pilot.pedals = Vector2.ZERO
	pilot.shoulder = true
	check(not pilot.is_vectoring_held(), "adjusting throttle with R1 must not change the manoeuvre envelope")
	pilot.shoulder = false
	# Trigger noise must not flicker the envelope, and signed Android triggers
	# must behave like the usual 0..1 mapping.
	pilot.pedals = Vector2.ONE
	check(pilot.is_vectoring_held(), "full pressure engages vectoring")
	pilot.pedals = Vector2(0.5, 0.5)
	check(pilot.is_vectoring_held(), "small pressure changes must retain engaged vectoring")
	pilot.pedals = Vector2(0.3, 1.0)
	check(not pilot.is_vectoring_held(), "releasing either pedal must disengage vectoring")
	pilot._left_trigger_rest = -1.0
	pilot._right_trigger_rest = -1.0
	pilot.pedals = -Vector2.ONE
	check(not pilot.is_vectoring_held(), "signed triggers at rest must not engage")
	pilot.pedals = Vector2.ONE
	check(pilot.is_vectoring_held(), "signed triggers must engage at full pressure")
	pilot._left_trigger_rest = 0.0
	pilot._right_trigger_rest = 0.0
	for sign_value in [-1.0, 1.0]:
		_rudder_release(sign_value)
	var cruise_yaw := _rudder_authority(175.0)
	var slow_yaw := _rudder_authority(45.0)
	check(slow_yaw < cruise_yaw * 0.5, "rudder surfaces must lose authority at low airspeed")
	var ordinary := _pull(false)
	var vectored := _pull(true)
	print("FLIGHT_SWEEP turn ordinary=%s vectored=%s" % [ordinary, vectored])
	check(vectored.alpha > ordinary.alpha + 5.0, "vectoring must give additional pitch pointing at low speed")
	check(vectored.radius < ordinary.radius * 0.9, "a banked vectored pull must tighten the actual flight path")
	check(vectored.speed < ordinary.speed, "a tighter vectored manoeuvre must cost energy")
	if not failed:
		print("FLIGHT_SWEEP_TEST_PASS")
	quit(1 if failed else 0)

func _jet(speed := 175.0) -> Node3D:
	var jet := JET.new()
	root.add_child(jet)
	jet.set_physics_process(false)
	jet._world_limit = 100000.0
	jet.minimum_display_speed = speed
	jet.maximum_display_speed = speed
	jet.starting_throttle = 1.0
	jet.launch(Vector3(0.0, 900.0, 0.0), 0.0)
	return jet

func _rudder_release(direction: float) -> void:
	var jet := _jet()
	pilot.stick = Vector2.ZERO
	pilot.pedals = Vector2(1.0, 0.0) if direction < 0.0 else Vector2(0.0, 1.0)
	for frame in range(90):
		jet._physics_process(STEP)
	var at_release: float = JET.heading_of(jet.basis) * direction
	var path_at_release: float = atan2(jet.velocity.x, -jet.velocity.z) * direction
	pilot.pedals = Vector2.ZERO
	var lowest := at_release
	for frame in range(180):
		jet._physics_process(STEP)
		lowest = minf(lowest, JET.heading_of(jet.basis) * direction)
	var final_path: float = atan2(jet.velocity.x, -jet.velocity.z) * direction
	print("FLIGHT_SWEEP rudder=%s nose_release=%.2f minimum=%.2f path_release=%.2f path_final=%.2f beta=%.2f" % [direction, rad_to_deg(at_release), rad_to_deg(lowest), rad_to_deg(path_at_release), rad_to_deg(final_path), rad_to_deg(jet.beta)])
	check(at_release > deg_to_rad(15.0), "rudder must yaw the nose in the requested direction")
	check(path_at_release < at_release * 0.8, "momentum must lag the nose while the aircraft slips")
	check(lowest > at_release * 0.6, "releasing rudder must not erase most of the heading change")
	check(final_path > deg_to_rad(8.0), "rudder must produce a lasting change in flight path")
	check(absf(jet.beta) < deg_to_rad(8.0), "sideslip must settle after release")
	jet.free()

func _pull(use_vectoring: bool) -> Dictionary:
	var jet := _jet(130.0)
	jet.basis = jet.basis.rotated(jet.basis.x, -deg_to_rad(60.0)).orthonormalized()
	pilot.pedals = Vector2.ONE if use_vectoring else Vector2.ZERO
	pilot.stick = Vector2(0.0, 1.0)
	var peak_alpha := 0.0
	var travelled := 0.0
	var turned := 0.0
	var previous := 0.0
	for frame in range(180):
		jet._physics_process(STEP)
		peak_alpha = maxf(peak_alpha, jet.alpha)
		travelled += Vector2(jet.velocity.x, jet.velocity.z).length() * STEP
		var heading := atan2(jet.velocity.x, -jet.velocity.z)
		turned += wrapf(heading - previous, -PI, PI)
		previous = heading
	var result := {"alpha": rad_to_deg(peak_alpha), "radius": travelled / maxf(absf(turned), 0.001), "speed": jet.velocity.length()}
	jet.free()
	return result

func _rudder_authority(speed: float) -> float:
	var jet := _jet(speed)
	pilot.pedals = Vector2(0.0, 1.0)
	pilot.stick = Vector2.ZERO
	for frame in range(15):
		jet._physics_process(STEP)
	var turned: float = absf(JET.heading_of(jet.basis))
	jet.free()
	return turned

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
