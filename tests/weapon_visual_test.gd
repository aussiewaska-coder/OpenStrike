extends SceneTree
const MANAGER := preload("res://scripts/weapons/projectile_manager.gd")
const ROUND := preload("res://scripts/weapons/cannon_round.gd")
const FLIGHT := preload("res://scripts/weapons/missile_flight.gd")
const TRAILS := preload("res://scripts/effects/trail_renderer.gd")
const MISSILE_FX := preload("res://scripts/effects/missile_fx.gd")
const CANNON_FX := preload("res://scripts/effects/cannon_fx.gd")
const IMPACT_FX := preload("res://scripts/effects/impact_fx_manager.gd")

class Mount extends Node3D:
	func get_muzzle_transform() -> Transform3D:
		return global_transform

class Gun extends Node3D:
	var is_firing := true
	var continuous_fire_time := 3.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--visual-out="):
			output = arg.trim_prefix("--visual-out=")
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.13, 0.23, 0.35)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	stage.add_child(environment)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(65, 30, 85)
	camera.look_at(Vector3(0, 5, 0))
	camera.current = true
	camera.fov = 42.0
	var sun := DirectionalLight3D.new()
	stage.add_child(sun)
	sun.rotation_degrees = Vector3(-45,-30,0)
	var manager := MANAGER.new()
	stage.add_child(manager)
	manager.set_physics_process(false)
	var trails := TRAILS.new()
	stage.add_child(trails)
	trails.set_process(false)
	trails.begin_trail(1)
	for sample in range(60):
		trails.age_trails(sample * 0.04)
		trails.push_point(1, Vector3(-70 + sample * 1.6, 3 + pow(sample / 18.0, 2), 0))
	trails._rebuild()
	var round_data := ROUND.new()
	round_data.weapon_source = "missile"
	round_data.flight = FLIGHT.new()
	round_data.age = 2.0
	round_data.position = Vector3(24.4, 13.74, 0)
	round_data.previous_position = round_data.position - Vector3(1.6,0.35,0)
	round_data.velocity = Vector3(400,90,0)
	manager.spawn(round_data)
	var missile_fx := MISSILE_FX.new()
	missile_fx.projectile_manager = manager
	stage.add_child(missile_fx)
	var mount := Mount.new()
	stage.add_child(mount)
	mount.position = Vector3(-15,0,25)
	var gun := Gun.new()
	stage.add_child(gun)
	var cannon_fx := CANNON_FX.new()
	cannon_fx.gun_mount = mount
	cannon_fx.weapon = gun
	cannon_fx.projectile_manager = manager
	stage.add_child(cannon_fx)
	var impacts := IMPACT_FX.new()
	stage.add_child(impacts)
	impacts.spawn_explosion(Vector3(32,3,-12))
	cannon_fx._update_smoke()
	cannon_fx._muzzle_smoke.preprocess = 0.9
	await process_frame
	missile_fx._process(0.0)
	assert(cannon_fx._muzzle_smoke.color_ramp != null)
	assert(cannon_fx._muzzle_smoke.scale_amount_curve != null)
	assert(missile_fx._models[0].visible)
	assert(missile_fx._models[0].global_basis.determinant() > 0.99)
	assert(trails.mesh.get_surface_count() == 1)
	if output != "" and DisplayServer.get_name() != "headless":
		await create_timer(0.3).timeout
		cannon_fx.on_round_fired(round_data)
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(output + ".png") == OK)
		print("VISUAL_SAVED ", output + ".png")
	stage.free()
	print("WEAPON_VISUAL_TEST_PASS")
	quit()
