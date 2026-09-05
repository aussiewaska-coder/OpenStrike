extends SceneTree

## The Nighthawk arrives with its gear down and an opaque canopy.
##
## Its parts carry no names -- they are all Object_N -- so neither the existing
## gear stow, which matches "landingon", nor the existing canopy clarifier,
## which matches "canopy", finds anything. Both have to work by position.
##
## The canopy matters more than it sounds: rendering from the seat shows those
## facets as solid dark blue, so without clearing them the cockpit view is a
## wall rather than a view.

const AIRFRAME := preload("res://scripts/jet/airframe.gd")
const VISUALS := preload("res://scripts/jet/jet_visuals.gd")

func _init(): call_deferred("_run")

func _run():
	var profile = AIRFRAME.nighthawk()
	assert(profile.parts_are_named == false, "this model has no node called canopy")
	assert(profile.has_jet_effects == false, "the Raptor's aileron surgery must not run on it")
	assert(profile.cockpit_seat_fraction > 0.0 and profile.cockpit_seat_fraction < 1.0)
	assert(profile.cockpit_eye_height_fraction > 0.0 and profile.cockpit_eye_height_fraction < 1.0)

	var model: Node3D = (load(profile.scene_path) as PackedScene).instantiate()
	root.add_child(model)
	# Deliberately parked away from the origin: the helpers must work in the
	# model's own frame, not the world's.
	model.transform = Transform3D(Basis.IDENTITY, Vector3(1200.0, 300.0, -800.0))
	await process_frame

	var before := _visible_meshes(model)

	# Anything hanging below the lowest third of the airframe is gear.
	var hidden: int = VISUALS.hide_landing_gear(model, profile.model_basis, 0.30)
	assert(hidden > 0, "the gear is modelled down and must be hidden")
	assert(_visible_meshes(model) == before - hidden, "hiding gear must remove exactly those meshes")
	assert(_visible_meshes(model) > 0, "and must not hide the aeroplane with it")

	var cleared: int = VISUALS.clarify_canopy_by_bounds(model, profile.model_basis)
	assert(cleared > 0, "the canopy must be found and cleared, or the pilot sees a blue wall")

	model.queue_free()
	await process_frame
	print("NIGHTHAWK_COCKPIT_TEST_PASS")
	quit()


func _visible_meshes(node: Node) -> int:
	var count := 0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if (child as MeshInstance3D).visible:
			count += 1
	return count


func _bounds(node: Node) -> AABB:
	var bounds := AABB()
	var found := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		var box: AABB = instance.global_transform * instance.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
	return bounds
