extends SceneTree
const JET=preload("res://scripts/jet/jet_controller.gd")
const AIRFRAME=preload("res://scripts/jet/airframe.gd")
const VISUALS=preload("res://scripts/jet/jet_visuals.gd")
var shots: Dictionary={}
func _init():call_deferred("run")
func run():
	var telemetry=root.get_node_or_null("Telemetry")
	if telemetry: telemetry.free()
	root.size=Vector2i(960,540)
	var stage=Node3D.new()
	root.add_child(stage)
	var env=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_SKY
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE
	env.environment.ambient_light_energy=0.28
	var sky=Sky.new()
	sky.radiance_size=Sky.RADIANCE_SIZE_64
	sky.sky_material=ProceduralSkyMaterial.new()
	env.environment.sky=sky
	stage.add_child(env)
	var sun=DirectionalLight3D.new()
	stage.add_child(sun)
	sun.look_at_from_position(Vector3.ZERO,-Vector3(20,11,-19))
	sun.light_energy=0.9
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=6500.0
	sun.directional_shadow_split_1=0.025
	var profile=AIRFRAME.lightning()
	profile.satin_exterior=false
	var jet=JET.new()
	jet.airframe=profile
	var model=load(profile.scene_path).instantiate()
	model.name="HeroJet"
	jet.add_child(model)
	stage.add_child(jet)
	jet.set_physics_process(false)
	await process_frame
	var camera=Camera3D.new()
	stage.add_child(camera)
	camera.position=Vector3(-18,11,19)
	camera.fov=38
	camera.far=20000
	camera.look_at(Vector3(2,0,0))
	for variant in ["before","stable-matte","satin","satin-no-casters"]:
		if variant=="stable-matte":
			VISUALS.satin_exterior(model)
			for mi in model.find_children("*","MeshInstance3D",true,false):
				for s in mi.mesh.get_surface_count():
					var material=mi.get_active_material(s)
					if material.clearcoat_enabled:
						material.clearcoat_enabled=false
						material.roughness=1.0
		if variant=="satin":VISUALS.satin_exterior(model)
		# Keep the light's shadow rendering path identical. Turning the light's
		# shadows off also changes its Compatibility lighting pass, so it is
		# not a valid self-shadow comparison.
		if variant=="satin-no-casters":
			for mi in model.find_children("*","MeshInstance3D",true,false):
				mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in 2:await process_frame
		await RenderingServer.frame_post_draw
		var shot=root.get_texture().get_image()
		shots[variant]=shot
		shot.save_png("/tmp/f35-finish-%s.png" % variant)
	var highlighted=0
	var unstable=0
	var image: Image=shots["satin"]
	for y in image.get_height():
		for x in image.get_width():
			var brightness=image.get_pixel(x,y).get_luminance()
			if brightness-shots["stable-matte"].get_pixel(x,y).get_luminance()>0.015: highlighted+=1
			if absf(brightness-shots["satin-no-casters"].get_pixel(x,y).get_luminance())>0.02:unstable+=1
	print("F35_FINISH highlighted_pixels=%d shadow_affected_pixels=%d" % [highlighted,unstable])
	var ok=highlighted>100 and unstable<300
	if ok:print("F35_FINISH_RENDER_TEST_PASS")
	else:push_error("finish must catch the sun without world-shadow blotches")
	stage.free()
	quit(0 if ok else 1)
