extends SceneTree

## Render the actual enemy models and seeker HUD without loading a theatre.
const SQUADRON := preload("res://scripts/entities/enemy_squadron.gd")
const HELMET := preload("res://scripts/ui/helmet_hud.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const LAUNCHER := preload("res://scripts/weapons/missile_launcher.gd")
const WEAPONS := preload("res://scripts/weapons/weapon_selection.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_SKY
	world.environment.sky = Sky.new()
	world.environment.sky.sky_material = ProceduralSkyMaterial.new()
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.7, 0.8, 1.0)
	world.environment.ambient_light_energy = 0.7
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	stage.add_child(sun)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 3000, 0)
	camera.fov = 75
	var squadron := SQUADRON.new()
	stage.add_child(squadron)
	squadron.spawn(3, camera.position)
	var positions := [Vector3(0, 3010, -230), Vector3(-100, 3060, -440), Vector3(130, 3040, -500)]
	for index in 3:
		var jet = squadron.jets()[index]
		jet.position = positions[index]
		jet.heading = 0.4
		jet._desired_heading = 0.8
		squadron._place_visual(jet)
	var tracker := TRACKER.new()
	tracker.update(squadron.contacts(), camera.position, Vector3.FORWARD, Vector3(0, 0, -220))
	tracker.select_contact(squadron.jets()[0].id)
	var carrier := Node3D.new()
	stage.add_child(carrier)
	carrier.position = camera.position
	carrier.basis = Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT)
	var launcher := LAUNCHER.new()
	stage.add_child(launcher)
	launcher.carrier = carrier
	launcher.tracker = tracker
	launcher.selection = WEAPONS.new()
	launcher.selection.current = WEAPONS.Weapon.HEAT
	var helmet := HELMET.new()
	root.add_child(helmet)
	for variant in ["acquiring", "ready", "offscreen"]:
		launcher.update(0.2 if variant == "acquiring" else 0.5, false)
		if variant == "offscreen":
			camera.rotation.y = PI * 0.75
		helmet.set_seeker_state(launcher.seeker_state())
		helmet.set_state(camera, Vector3(0, 0, -220), tracker.boxed(), tracker.locked(), 120.0,
			{"speed_mps": 220.0, "altitude_m": 3000.0, "heading_degrees": 0.0, "g_load": 1.6, "mach": 0.65})
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/openstrike-dogfight-%s.png" % variant)
	helmet.free()
	stage.free()
	print("DOGFIGHT_RENDER_DONE")
	quit()
