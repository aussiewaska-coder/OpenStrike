extends SceneTree


class LowTickMover:
	extends Node3D

	func _physics_process(delta: float) -> void:
		position.x += 10.0 * delta


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(
		bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)),
		"rendering must interpolate fixed-tick aircraft motion under variable frame load"
	)
	var scene := FileAccess.open("res://scenes/main.tscn", FileAccess.READ)
	assert(scene != null, "main scene must be readable")
	var source := scene.get_as_text()
	assert(
		source.contains("physics_interpolation_mode = 2"),
		"the frame-driven camera must not receive automatic interpolation on top of its own"
	)
	var jet: Node3D = load("res://scripts/jet/jet_controller.gd").new()
	assert(
		jet.has_method("get_interpolated_focus_position"),
		"camera focus must read the aircraft's displayed interpolated transform"
	)
	jet.free()

	Engine.physics_ticks_per_second = 10
	Engine.max_fps = 60
	var mover := LowTickMover.new()
	root.add_child(mover)
	await process_frame
	mover.get_global_transform_interpolated()
	mover.reset_physics_interpolation()
	var raw_changes := 0
	var displayed_changes := 0
	var previous_raw := mover.global_position.x
	var previous_displayed := mover.get_global_transform_interpolated().origin.x
	for _frame in range(24):
		await process_frame
		var raw := mover.global_position.x
		var displayed := mover.get_global_transform_interpolated().origin.x
		if not is_equal_approx(raw, previous_raw):
			raw_changes += 1
		if not is_equal_approx(displayed, previous_displayed):
			displayed_changes += 1
		previous_raw = raw
		previous_displayed = displayed
	assert(raw_changes > 0, "low-tick fixture must advance physics")
	assert(
		displayed_changes > raw_changes,
		"interpolated display motion must update between coarse physics ticks"
	)
	mover.queue_free()
	print("CAMERA_INTERPOLATION_TEST_PASS")
	quit()
