extends SceneTree

const DAY := preload("res://scripts/world/day_cycle.gd")
const SKY := preload("res://scripts/world/sky_state.gd")
const FLARE := preload("res://scripts/world/lens_flare.gd")
const CLOUD := preload("res://scripts/world/cloud_deck.gd")

var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.name = "Camera"
	stage.add_child(camera)
	camera.current = true
	var day := DAY.new()
	day.sun_path = NodePath("../Sun")
	stage.add_child(day)
	day.set_process(false)
	day.elevation_deg = 45.0
	day.azimuth_deg = 30.0
	day._apply(SKY.for_elevation(45.0))
	var direction: Vector3 = DAY.SOLAR.direction_to_sun(45.0, 30.0)
	camera.look_at(direction * 1000.0)
	var flare := FLARE.new()
	flare.camera_path = NodePath("../Camera")
	flare.sun_path = NodePath("../Sun")
	stage.add_child(flare)
	flare.set_process(false)
	flare._process(0.0)
	check(float(flare._material.get_shader_parameter("strength")) > 0.1, "looking at the daytime sun must show its flare")
	camera.look_at(-direction * 1000.0)
	flare._process(0.0)
	check(is_zero_approx(float(flare._material.get_shader_parameter("strength"))), "looking away from the sun must hide the flare")
	var cloud := CLOUD.new()
	cloud.camera_path = NodePath("../Camera")
	stage.add_child(cloud)
	cloud.set_process(false)
	Engine.physics_ticks_per_second = 10
	Engine.max_fps = 60
	cloud.get_global_transform_interpolated()
	cloud.reset_physics_interpolation()
	var stale_frames := 0
	for frame in range(18):
		await process_frame
		camera.position.x += 1.0
		cloud._process(1.0 / 60.0)
		if not cloud.get_global_transform_interpolated().origin.is_equal_approx(cloud.global_position):
			stale_frames += 1
	print("LIGHTING_SWEEP stale cloud frames=%d" % stale_frames)
	check(stale_frames == 0, "a cloud sheet moved every render frame must not also receive physics interpolation")
	stage.free()
	if not failed:
		print("LIGHTING_WIRING_TEST_PASS")
	quit(1 if failed else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
