extends SceneTree

## Every aircraft must arrive the same way round.
##
## _scale_to_reference() measures bounds.size.z and calls it the wingspan. The
## Raptor's GLB happens to import with its span on Z, so that worked while it
## was the only aircraft. The F-117 imports span on X and length on Y -- 10.43
## by 16.00 by 2.92 -- so the same code would read 2.92 m as its wingspan and
## scale the aeroplane about five times too large.
##
## The profile carries a basis that fixes that before anything is measured.

const AIRFRAME := preload("res://scripts/jet/airframe.gd")

func _init(): call_deferred("_run")

func _run():
	for profile in [AIRFRAME.raptor(), AIRFRAME.nighthawk(), AIRFRAME.super_hornet(), AIRFRAME.lightning()]:
		var scene = load(profile.scene_path)
		assert(scene != null, "%s must load: %s" % [profile.display_name, profile.scene_path])
		var model: Node3D = scene.instantiate()
		root.add_child(model)
		model.transform = Transform3D(profile.model_basis, Vector3.ZERO)
		await process_frame
		var bounds := _bounds(model)

		# Z is the span, which is what the scaling code reads.
		var factor: float = profile.reference_wingspan_m / bounds.size.z
		assert(factor > 0.0, "%s span must be positive" % profile.display_name)
		var length: float = bounds.size.x * factor
		var span: float = bounds.size.z * factor
		var height: float = bounds.size.y * factor
		assert(is_equal_approx(span, profile.reference_wingspan_m),
			"%s must scale to its real span" % profile.display_name)

		# An aeroplane, once scaled: longer than it is tall, and of a plausible
		# size. This is what catches a model left on the wrong axis, because a
		# wrong axis makes the length or the height absurd.
		assert(length > height,
			"%s must be longer than it is tall, got %.1f long and %.1f tall" % [
				profile.display_name, length, height])
		assert(length > 8.0 and length < 40.0,
			"%s scaled to %.1f m long, which is not an aeroplane" % [profile.display_name, length])
		assert(height > 0.5 and height < 12.0,
			"%s scaled to %.1f m tall, which is not an aeroplane" % [profile.display_name, height])
		model.queue_free()
		await process_frame
	print("AIRFRAME_RIGGING_TEST_PASS")
	quit()


func _bounds(node: Node) -> AABB:
	var bounds := AABB()
	var found := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		var box: AABB = instance.global_transform * instance.get_aabb()
		if not found:
			bounds = box
			found = true
		else:
			bounds = bounds.merge(box)
	return bounds
