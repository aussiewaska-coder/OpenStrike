extends SceneTree
const VIEW := preload("res://scripts/camera/projectile_camera.gd")
const ROUND := preload("res://scripts/weapons/cannon_round.gd")
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var aircraft := Camera3D.new()
	root.add_child(aircraft)
	aircraft.position = Vector3(100, 2000, 300)
	aircraft.make_current()
	var pose := aircraft.global_transform
	var view := VIEW.new()
	view.aircraft_camera = aircraft
	view.ground_height = func(_p): return 2.0
	root.add_child(view)
	view.set_enabled(true, [])
	check(view.enabled and not view.watching and aircraft.current, "toggle before launch arms the view while keeping the aircraft camera")
	var round_data := ROUND.new()
	round_data.initialise(123, Vector3(0, 1000, 0), Vector3.FORWARD, Vector3(0, -40, -250), false, null, "missile")
	view.on_launch(round_data)
	check(view.watching and view.camera.current and view.sequence == 123, "an armed camera follows the guided missile immediately on launch")
	var before := view.camera.position
	round_data.position += Vector3(20, -100, -400)
	round_data.previous_position = round_data.position # Teleport the render snapshot too.
	view.update(0.016, [round_data])
	check(before.distance_to(view.camera.position) > 300, "camera follows the live projectile")
	check(aircraft.global_transform == pose, "weapon camera cannot mutate the aircraft camera's pose")
	var second := ROUND.new()
	second.initialise(125, Vector3(800, 500, 0), Vector3.FORWARD, Vector3.FORWARD, false, null, "missile")
	view.on_launch(second)
	check(view.sequence == 123, "firing another missile cannot jump away from the missile being watched")
	view.finish(999, Vector3.ZERO, true)
	check(view.watching and view.sequence == 123, "another round's impact cannot steal the camera")
	view.finish(123, Vector3.ZERO, true)
	view.update(0.4, [])
	check(view.watching, "the camera holds briefly to show the impact")
	view.update(0.5, [])
	check(not view.watching and aircraft.current and view.enabled, "impact returns to aircraft view and remains armed for the next launch")
	view.on_launch(round_data)
	view.set_enabled(false, [round_data])
	check(not view.watching and not view.enabled and aircraft.current, "the on-screen toggle can immediately return during flight")
	view.set_enabled(true, [round_data])
	check(view.watching, "the toggle can join an already flying missile")
	round_data.initialise(124, Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD, false, null, "cannon")
	view.update(0.016, [round_data])
	check(not view.watching and aircraft.current, "pooled round reuse cannot attach the view to an unrelated shell")
	round_data.weapon_source = "guided_bomb"
	view.on_launch(round_data)
	check(view.watching and view.camera.position.y >= 5.0, "guided bombs also have a chase view with terrain clearance")
	view.finish(124, Vector3.ZERO, false)
	check(not view.watching and aircraft.current, "expired projectiles also restore aircraft view")
	view.free()
	aircraft.free()
	if not failed:
		print("PROJECTILE_CAMERA_TEST_PASS")
	quit(1 if failed else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
