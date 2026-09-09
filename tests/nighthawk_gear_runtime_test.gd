extends SceneTree
const JET = preload("res://scripts/jet/jet_controller.gd")
const AIRFRAME = preload("res://scripts/jet/airframe.gd")
var failed := false
func _init(): call_deferred("_run")
func _run():
	var profile = AIRFRAME.nighthawk()
	var source: PackedScene = load(profile.scene_path)
	for attitude in [Basis.IDENTITY, Basis.from_euler(Vector3(0.4, 1.2, 0.7))]:
		var jet = JET.new()
		jet.airframe = profile
		var model = source.instantiate()
		model.name = "HeroJet"
		jet.add_child(model)
		root.add_child(jet)
		jet.set_physics_process(false)
		jet.basis = attitude
		await process_frame
		jet._update_visual(1.0 / 60.0)
		var lowest := INF
		var glass_triangles := 0
		for child in model.find_children("*", "MeshInstance3D", true, false):
			if not child.is_visible_in_tree(): continue
			var frame: Transform3D = jet.global_transform.affine_inverse() * child.global_transform
			for surface in range(child.mesh.get_surface_count()):
				var arrays = child.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for index in indices:
					lowest = minf(lowest, (frame * vertices[index]).y)
				if String(child.name) == "Object_30": glass_triangles += indices.size() / 3
		print("GEAR_STOW lowest_visible=%.3f retained_glass_triangles=%d" % [lowest, glass_triangles])
		_check(lowest > -0.8, "retracted F-117 must have no wheels, struts or open doors hanging below its belly")
		_check(glass_triangles > 0, "shared wheel/glass material must retain cockpit and window geometry")
		jet.free()
	# Rigging must not change the cached GLB used by future aircraft instances.
	var untouched = source.instantiate()
	var wheel = untouched.find_child("Object_31", true, false)
	_check(wheel.visible, "runtime gear changes must not mutate the imported scene")
	untouched.free()
	if not failed: print("NIGHTHAWK_GEAR_RUNTIME_TEST_PASS")
	quit(1 if failed else 0)
func _check(ok: bool, message: String):
	if not ok:
		failed = true
		push_error(message)
