extends SceneTree
const JET=preload("res://scripts/jet/jet_controller.gd")
const AIRFRAME=preload("res://scripts/jet/airframe.gd")
func _init(): call_deferred("run")
func run():
	root.size=Vector2i(1280,720)
	var stage=Node3D.new()
	root.add_child(stage)
	var world=WorldEnvironment.new()
	world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color(0.35,0.55,0.75)
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color=Color.WHITE
	world.environment.ambient_light_energy=0.6
	stage.add_child(world)
	var sun=DirectionalLight3D.new()
	stage.add_child(sun)
	sun.rotation_degrees=Vector3(-45,-30,0)
	sun.light_energy=1.0
	var camera=Camera3D.new()
	camera.near=0.03
	camera.fov=78
	stage.add_child(camera)
	for profile in [AIRFRAME.raptor(),AIRFRAME.super_hornet(),AIRFRAME.lightning()]:
		var jet=JET.new()
		jet.airframe=profile
		var model=load(profile.scene_path).instantiate()
		model.name="HeroJet"
		jet.add_child(model)
		stage.add_child(jet)
		jet.set_physics_process(false)
		await process_frame
		var seat=jet.get_cockpit_transform()
		camera.global_position=seat.origin
		camera.look_at(seat.origin+seat.basis.x,seat.basis.y)
		for i in 3:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/%s-cockpit.png" % profile.display_name.replace("/",""))
		if profile.display_name.begins_with("F-35"):
			jet._thrust_setting=1.35
			jet._update_visual(1.0/60.0)
			camera.position=Vector3(-17,-7,16)
			camera.fov=48
			camera.look_at(Vector3(1.5,0,0))
			for i in 3:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/f35-gear-up-burner.png")
		jet.free()
	print("F35_COCKPIT_RENDER_TEST_PASS")
	quit()
