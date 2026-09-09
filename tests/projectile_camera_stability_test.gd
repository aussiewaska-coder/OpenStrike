extends SceneTree
const VIEW := preload("res://scripts/camera/projectile_camera.gd")
const MANAGER := preload("res://scripts/weapons/projectile_manager.gd")
const FLIGHT := preload("res://scripts/weapons/missile_flight.gd")
const FX := preload("res://scripts/effects/missile_fx.gd")
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(960, 540)
	var aircraft := Camera3D.new()
	root.add_child(aircraft)
	var view := VIEW.new()
	view.aircraft_camera = aircraft
	root.add_child(view)
	var manager := MANAGER.new()
	root.add_child(manager)
	var fx := FX.new()
	fx.projectile_manager = manager
	root.add_child(fx)
	var round_data: RefCounted = manager.acquire_round()
	round_data.initialise(901, Vector3(0, 3000, 0), Vector3.FORWARD, Vector3(0, 0, -850), false, null, "missile")
	round_data.flight = FLIGHT.new()
	manager.spawn(round_data)
	view.enabled = true
	view.on_launch(round_data)
	var previous := Vector2.ZERO
	var maximum_jump := 0.0
	for frame in 90:
		await create_timer(0.007 if frame % 2 == 0 else 0.019).timeout
		fx._process(0.0)
		view.update(view.get_process_delta_time(), manager.active_rounds)
		var at := view.camera.unproject_position(fx._models[0].global_position)
		if frame > 3:
			maximum_jump = maxf(maximum_jump, at.distance_to(previous))
		previous = at
	print("CAMERA_PHASE_JUMP_PX %.3f" % maximum_jump)
	check(maximum_jump < 2.0, "the rendered missile must stay steady when render and physics timing differ")
	manager.set_physics_process(false)
	round_data.position = Vector3(0, 3000, 0)
	round_data.previous_position = round_data.position
	var maximum_turn := 0.0
	for frame in 181:
		var pitch := deg_to_rad(65.0 + frame * 0.25)
		round_data.velocity = Vector3(0, -sin(pitch), -cos(pitch)) * 700.0
		var before := view.camera.global_basis
		view.update(1.0 / 60.0, manager.active_rounds)
		if frame > 10:
			maximum_turn = maxf(maximum_turn, before.get_rotation_quaternion().angle_to(view.camera.global_basis.get_rotation_quaternion()))
	print("CAMERA_VERTICAL_STEP_DEGREES %.3f" % rad_to_deg(maximum_turn))
	check(maximum_turn < deg_to_rad(8.0), "a steep diving missile must not flip the camera's up axis")
	fx.free()
	manager.free()
	view.free()
	aircraft.free()
	if not failed:
		print("PROJECTILE_CAMERA_STABILITY_TEST_PASS")
	quit(1 if failed else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
