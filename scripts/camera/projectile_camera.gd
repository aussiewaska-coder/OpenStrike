extends Node3D

## Separate camera: the aircraft camera and its tracking continue untouched.
## Store a sequence, never a pooled round reference that can become a shell.
const PRESENTATION := preload("res://scripts/weapons/projectile_presentation.gd")
var aircraft_camera: Camera3D
var ground_height := Callable()
var enabled := false
var watching := false
var sequence := -1
var camera: Camera3D
var _impact_remaining := 0.0
var _boom_direction := Vector3.FORWARD
var _boom_up := Vector3.UP
var _pan_offset := 0.0
var _impact_point := Vector3.ZERO
var _state := {}

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera = Camera3D.new()
	camera.name = "WeaponCamera"
	camera.fov = 65.0
	camera.near = 0.05
	camera.far = 50000.0
	add_child(camera)
	camera.current = false

func set_enabled(value: bool, rounds: Array) -> void:
	enabled = value
	if not enabled:
		stop()
		return
	for index in range(rounds.size() - 1, -1, -1):
		if _eligible(rounds[index]):
			on_launch(rounds[index])
			return

func _eligible(round_data: RefCounted) -> bool:
	return round_data.weapon_source in ["missile", "guided_bomb"]

func on_launch(round_data: RefCounted) -> void:
	if not enabled or watching or not _eligible(round_data):
		return
	sequence = round_data.sequence
	_impact_remaining = 0.0
	watching = true
	_place(round_data, 0.0, true)
	camera.make_current()

func finish(round_sequence: int, point: Vector3, impacted: bool) -> void:
	if not watching or sequence != round_sequence:
		return
	sequence = -1
	if not impacted:
		stop()
		return
	_impact_remaining = 0.8
	_impact_point = point
	_state["status"] = "IMPACT"
	_state["locked"] = false
	_state["range_m"] = 0.0
	_state["projectile_position"] = null
	_state["target_position"] = point

func update(delta: float, rounds: Array) -> void:
	if not watching:
		return
	if _impact_remaining > 0.0:
		_impact_remaining -= delta
		_pan_to(_impact_point, delta)
		if _impact_remaining <= 0.0:
			stop()
		return
	for round_data in rounds:
		if round_data.sequence == sequence and _eligible(round_data):
			_place(round_data, delta)
			return
	stop()

func _place(round_data: RefCounted, delta: float, snap := false) -> void:
	var direction: Vector3 = round_data.velocity.normalized()
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	var point := PRESENTATION.position_of(round_data)
	_state = round_data.flight.tracking_state(point, round_data.velocity) if round_data.flight != null and round_data.flight.has_method("tracking_state") else {"weapon": "MISSILE", "status": "NO SEEKER LOCK", "locked": false}
	_state["projectile_position"] = point
	var target: Variant = _state.get("target_position")
	var to_target: Vector3 = (target - point).normalized() if target is Vector3 and point.distance_squared_to(target) > 0.01 else direction
	if snap:
		_boom_direction = direction
		_boom_up = PRESENTATION.transported_up(direction, Vector3.UP)
		_pan_offset = 0.0
	else:
		var angle := _boom_direction.angle_to(direction)
		var weight := minf(1.0 - exp(-6.0 * delta), 2.0 * delta / maxf(angle, 0.00001))
		_boom_direction = _boom_direction.slerp(direction, weight).normalized()
		_boom_up = PRESENTATION.transported_up(_boom_direction, _boom_up)
	var right := _boom_direction.cross(_boom_up).normalized()
	var wanted_pan := clampf(-right.dot(to_target) * 7.0, -4.0, 4.0)
	_pan_offset = lerpf(_pan_offset, wanted_pan, 1.0 - exp(-3.0 * delta))
	# Anchor to the displayed projectile each frame. Smoothing world position
	# alone would leave the camera hundreds of metres behind a fast missile.
	var desired := point - _boom_direction * 26.0 + _boom_up * 8.0 + right * _pan_offset
	if ground_height.is_valid():
		desired.y = maxf(desired.y, float(ground_height.call(desired)) + 3.0)
	camera.global_position = desired
	var aim := point + _boom_direction * 5.0 + to_target * 10.0
	_pan_to(aim, delta, snap)
	_state["range_m"] = point.distance_to(target) if target is Vector3 else 0.0

func _pan_to(aim: Vector3, delta: float, snap := false) -> void:
	var offset := aim - camera.global_position
	if offset.length_squared() < 0.00001:
		return
	var forward := offset.normalized()
	var up := PRESENTATION.transported_up(forward, _boom_up if snap else camera.global_basis.y)
	var wanted := Basis.looking_at(forward, up)
	if snap:
		camera.global_basis = wanted
		return
	var angle := camera.global_basis.get_rotation_quaternion().angle_to(wanted.get_rotation_quaternion())
	var weight := minf(1.0 - exp(-8.0 * delta), 1.6 * delta / maxf(angle, 0.00001))
	camera.global_basis = camera.global_basis.slerp(wanted, weight).orthonormalized()

func tracking_state() -> Dictionary:
	return _state if watching else {}

func stop() -> void:
	watching = false
	sequence = -1
	_impact_remaining = 0.0
	_state.clear()
	if is_instance_valid(aircraft_camera):
		aircraft_camera.make_current()

func cancel() -> void:
	enabled = false
	stop()

func button_text() -> String:
	if watching:
		return "MISSILE VIEW: ON • RETURN"
	return "MISSILE VIEW: ARMED" if enabled else "MISSILE VIEW: OFF"
