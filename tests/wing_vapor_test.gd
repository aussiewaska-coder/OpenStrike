extends SceneTree
const VAPOR := preload("res://scripts/jet/wing_vapor.gd")
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	check(VAPOR.demand(220, 1, 0.2, 1) == 0, "level flight does not produce high-G condensation")
	check(VAPOR.demand(30, 8, 0.3, 1) == 0 and VAPOR.demand(220, -3, 0.3, 1) == 0, "low speed and unloading suppress condensation")
	check(VAPOR.demand(220, 7, 0.3, 1) > 0.95, "a fast high-G pull produces strong wing vapor")
	check(VAPOR.demand(220, 7, 0.3, 0.2) < 0.25, "drier air reduces visibility")
	var carrier := Node3D.new()
	root.add_child(carrier)
	var model := Node3D.new()
	carrier.add_child(model)
	var wing := MeshInstance3D.new()
	wing.mesh = BoxMesh.new()
	wing.mesh.size = Vector3(2, 0.1, 12)
	wing.position = Vector3(-1, 0.3, 0)
	model.add_child(wing)
	carrier.hide()
	var tips := VAPOR.measure_tips(model, carrier)
	check(tips[0].distance_to(Vector3(-1, 0.3, -6)) < 0.1 and tips[1].distance_to(Vector3(-1, 0.3, 6)) < 0.1, "wing tips are measured correctly even before aircraft activation")
	carrier.show()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(-50, 25, 35)
	camera.look_at(Vector3.ZERO)
	var counts := []
	for hz in [30, 60, 120]:
		var vapor := VAPOR.new()
		carrier.add_child(vapor)
		vapor.build(model)
		vapor.set_process(false)
		vapor.moisture = 1.0
		vapor.set_flight(220, 7, 0.3)
		var before := carrier.transform
		for frame in hz * 6:
			var t: float = float(frame) / hz
			var pose := Transform3D(Basis(Vector3.RIGHT, sin(t) * 0.5), Vector3(t * 220, 20 * sin(t), 0))
			vapor.advance(1.0 / hz, pose)
		check(carrier.transform == before, "vapor cannot disturb aircraft attitude or position")
		check(vapor.strength > 0.95 and vapor._sheet_root.visible, "condensation builds smoothly during a sustained pull")
		check(vapor._history[0].size() <= VAPOR.MAX_POINTS and vapor._history[1].size() <= VAPOR.MAX_POINTS, "both trails have a hard memory and geometry bound")
		check(vapor._mesh.get_surface_count() == 1, "both wingtip trails share one mesh surface")
		counts.append(vapor._history[0].size())
		var sample: Dictionary = vapor._history[0][0].duplicate()
		check(VAPOR.displaced(sample, 3).distance_to(sample.point) > 1, "older vapor curls and drifts away from its original point")
		vapor.set_flight(220, 1, 0.03)
		var pose: Transform3D = vapor._last_pose
		for frame in hz * 7:
			pose.origin.x += 220.0 / hz
			vapor.advance(1.0 / hz, pose)
		check(vapor._history[0].is_empty() and vapor._history[1].is_empty() and not vapor._sheet_root.visible, "unloading lets existing vapor fade completely")
		vapor.set_flight(220, 7, 0.3)
		vapor.advance(0.1, pose)
		pose.origin += Vector3(10000, 0, 0)
		vapor.advance(0.016, pose)
		check(vapor._history[0].is_empty(), "teleports cannot leave a trail across the theatre")
		vapor.free()
	check(abs(counts[0] - counts[1]) <= 2 and abs(counts[1] - counts[2]) <= 2, "trail density remains consistent across frame rates")
	carrier.free()
	camera.free()
	if not failed:
		print("WING_VAPOR_TEST_PASS")
	quit(1 if failed else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
