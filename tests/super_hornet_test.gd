extends SceneTree
const JET := preload("res://scripts/jet/jet_controller.gd")
const AIRFRAME := preload("res://scripts/jet/airframe.gd")
var failed := false
func _init(): call_deferred("_run")
func _run():
	var profile = AIRFRAME.super_hornet()
	var jet = JET.new()
	jet.airframe = profile
	var model = load(profile.scene_path).instantiate()
	model.name = "HeroJet"
	jet.add_child(model)
	root.add_child(jet)
	jet.set_physics_process(false)
	await process_frame
	_check(jet._effects != null and jet._effects.plumes.size() == 2, "Super Hornet must have two afterburners")
	_check(jet._effects.ailerons.is_empty(), "F-22 mesh surgery must not run on the F-18")
	_check(model.find_child("F18-landingOn*", true, false) == null, "gear-down assemblies must remain excluded")
	_check(jet.get_hardpoints().size() == 2, "both wing rails need weapon mounts")
	for power in [0.0, 0.25, 1.0]:
		jet._effects.update(1.0 / 60.0, 0, 0, power)
		for i in range(2):
			var plume: MeshInstance3D = jet._effects.plumes[i]
			var mouth: Vector3 = plume.transform * Vector3(0, -0.5, 0)
			# Measured model nozzle centres lie roughly six metres aft, with
			# about one metre between them. The plume must stay on each mouth.
			_check(mouth.x > -6.1 and mouth.x < -5.7 and absf(mouth.y - 0.14) < 0.06, "flames must start at the F-18 nozzle mouths")
			_check(absf(absf(mouth.z) - 0.515) < 0.03, "each burner must sit on its own engine centreline")
			_check(plume.visible == (power > 0), "burners must extinguish below the detent")
			_check(plume.position.x < mouth.x, "both flames must extend aft")
			_check(jet._effects.lights[i].visible == (power > 0), "nozzle lights must follow afterburner power")
	jet._world_limit = 100000
	jet.launch(Vector3(0,900,0),0)
	for frame in range(900): jet._physics_process(1.0/60.0)
	print("HORNET_CRUISE altitude=%.2f speed=%.2f" % [jet.position.y, jet.airspeed()])
	_check(not jet.is_crashed() and absf(jet.position.y - 900) < 35, "neutral F-18 launch must remain stable in level flight")
	_check(jet.velocity.normalized().dot(jet.basis.x) > 0.99, "Super Hornet must fly forward along its visible nose")
	jet._thrust_setting = 1.35
	jet._crashed = true
	jet._update_visual(1.0/60.0)
	for plume in jet._effects.plumes: _check(not plume.visible, "crashing must cut both afterburners")
	jet.free()
	var speeds := []
	for throttle in [1.0, 1.35]:
		var flying = JET.new()
		flying.airframe = profile
		root.add_child(flying)
		flying.set_physics_process(false)
		flying._world_limit = 100000
		flying.starting_throttle = throttle
		flying.launch(Vector3(0,900,0),0)
		for frame in range(900): flying._physics_process(1.0/60.0)
		speeds.append(flying.airspeed())
		flying.free()
	print("HORNET_POWER military=%.2f afterburner=%.2f" % [speeds[0],speeds[1]])
	_check(speeds[1] > speeds[0] + 15, "afterburner must add real acceleration, not just flames")
	if not failed: print("SUPER_HORNET_TEST_PASS")
	quit(1 if failed else 0)
func _check(ok: bool, message: String):
	if not ok:
		failed = true
		push_error(message)
