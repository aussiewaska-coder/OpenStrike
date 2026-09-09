extends SceneTree
const JET=preload("res://scripts/jet/jet_controller.gd")
const AIRFRAME=preload("res://scripts/jet/airframe.gd")
var failed=false
func _init():call_deferred("run")
func check(ok: bool, message: String):
	if not ok:
		failed=true
		push_error(message)
func run():
	var profile=AIRFRAME.lightning()
	var original=load(profile.scene_path).instantiate()
	var jet=JET.new()
	jet.airframe=profile
	var model=load(profile.scene_path).instantiate()
	model.name="HeroJet"
	jet.add_child(model)
	root.add_child(jet)
	jet.set_physics_process(false)
	await process_frame
	var exterior_count=0
	for mi in model.find_children("*","MeshInstance3D",true,false):
		var source=original.get_node_or_null(model.get_path_to(mi))
		if source == null:
			check(mi.name == "LiveScreen", "only the live cockpit display may add geometry")
			continue
		for surface in mi.mesh.get_surface_count():
			var material=mi.get_active_material(surface)
			var imported=source.get_active_material(surface)
			var part=String(mi.get_parent().name).to_lower()
			if part.contains("airframe") or part.contains("landingoff"):
				exterior_count+=1
				check(material.clearcoat_enabled and material.clearcoat>0.0,"F-35 exterior needs its satin highlight layer")
				check(material.disable_receive_shadows,"F-35 exterior must reject the unstable world shadow map")
				check(material.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL,"sunlight must still shade the F-35")
				check(material.albedo_texture==imported.albedo_texture and material.normal_texture==imported.normal_texture and material.roughness_texture==imported.roughness_texture and material.metallic_texture==imported.metallic_texture,"authored paint and surface maps must survive the finish")
				check(mi.mesh==source.mesh,"finish must not add or alter aircraft geometry")
				check(mi.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"aircraft must still cast a world shadow")
				check(not imported.clearcoat_enabled and not imported.disable_receive_shadows,"shared imported material must remain untouched")
			elif part.contains("cockpit"):
				check(material==imported and not material.clearcoat_enabled,"cockpit must not inherit the exterior finish")
	check(exterior_count==2,"finish covers the body and closed gear doors")
	jet.free()
	original.free()
	if not failed:print("F35_FINISH_TEST_PASS")
	quit(1 if failed else 0)
