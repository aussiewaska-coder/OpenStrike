extends SceneTree
const JET = preload("res://scripts/jet/jet_controller.gd")
const AIRFRAME = preload("res://scripts/jet/airframe.gd")
var failed = false
func _init(): call_deferred("run")
func run():
	for profile in [AIRFRAME.raptor(), AIRFRAME.super_hornet(), AIRFRAME.lightning(), AIRFRAME.nighthawk()]:
		var jet = JET.new()
		jet.airframe = profile
		var model = load(profile.scene_path).instantiate()
		model.name = "HeroJet"
		jet.add_child(model)
		root.add_child(jet)
		jet.set_physics_process(false)
		await process_frame
		var seat = jet.get_cockpit_transform().origin
		var tub: Node3D
		for child in model.find_children("*", "Node3D", true, false):
			if String(child.name).to_lower().contains("cockpit"): tub = child; break
		if tub != null:
			var box = AABB()
			var found = false
			for mi in tub.find_children("*", "MeshInstance3D", true, false):
				var part: AABB = mi.global_transform * mi.get_aabb()
				box = box.merge(part) if found else part
				found = true
			if not found or not box.has_point(seat):
				failed = true
				push_error("%s camera is outside its modelled cockpit: %s" % [profile.display_name, seat])
		else:
			var forwardmost = -INF
			for mi in model.find_children("*", "MeshInstance3D", true, false):
				forwardmost = maxf(forwardmost, (mi.global_transform * mi.get_aabb()).end.x)
			if seat.x <= forwardmost:
				failed = true
				push_error("F-117 must retain its unobstructed nose camera")
		jet.free()
	if not failed: print("JET_COCKPIT_POSITION_TEST_PASS")
	quit(1 if failed else 0)
