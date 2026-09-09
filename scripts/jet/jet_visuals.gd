extends RefCounted

## The imported canopy is orange at 56% opacity, which heavily veils the HUD
## and panel. Replace only that named surface; cockpit and instrument glass keep
## their authored materials.


static func clarify_canopy(root: Node3D) -> int:
	var changed := 0
	for node in root.find_children("*", "Node3D", true, false):
		if not String(node.name).to_lower().contains("canopy"):
			continue
		for child in node.find_children("*", "MeshInstance3D", true, false):
			var instance := child as MeshInstance3D
			if instance.mesh == null:
				continue
			for surface in range(instance.mesh.get_surface_count()):
				var material := instance.get_active_material(surface)
				if not material is BaseMaterial3D:
					continue
				instance.set_surface_override_material(
					surface,
					clarified_canopy_material(material as BaseMaterial3D)
				)
				changed += 1
	return changed


static func clarified_canopy_material(material: BaseMaterial3D) -> BaseMaterial3D:
	var glass := material.duplicate() as BaseMaterial3D
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.68, 0.82, 0.88, 0.2)
	glass.metallic = 0.0
	glass.roughness = 0.08
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.disable_receive_shadows = true
	return glass


## Keep the authored paint/normal/metal maps under a restrained satin coat.
## The 6.5 km world shadow map produces unstable self-shadow patches on a
## close aircraft. Exterior paint receives direct/ambient light without that
## map; the geometry still casts shadows into the world. The cockpit shares
## the imported material, so overrides must be per exterior instance only.
static func satin_exterior(root: Node3D) -> int:
	var finishes: Dictionary = {}
	var changed := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var part := String(node.get_parent().name).to_lower()
		if not (part.contains("airframe") or part.contains("landingoff")):
			continue
		for surface in node.mesh.get_surface_count():
			var original := node.get_active_material(surface) as BaseMaterial3D
			if original == null:
				continue
			if not finishes.has(original):
				var finish := original.duplicate() as BaseMaterial3D
				finish.clearcoat_enabled = true
				finish.clearcoat = 0.35
				finish.clearcoat_roughness = 0.28
				finish.roughness = original.roughness * 0.9
				finish.disable_receive_shadows = true
				finishes[original] = finish
			node.set_surface_override_material(surface, finishes[original])
			changed += 1
	return changed


## The imported aircraft carry their landing gear modelled down on nodes with
## no useful names -- the Nighthawk's are all Object_N -- so the gear is found
## by where it sits rather than what it is called: anything hanging entirely
## below the given height is a wheel or a leg.
##
## Everything is judged in the engine's convention, so the caller passes the
## basis that puts this model there and a fraction of the airframe's height.
## Working in the root's own frame rather than the world means it does not
## matter where the aeroplane happens to be standing.
static func hide_landing_gear(root: Node3D, basis: Basis, height_fraction: float) -> int:
	var boxes := _oriented_boxes(root, basis)
	if boxes.is_empty():
		return 0
	var bounds: AABB = boxes[0]["box"]
	for entry in boxes:
		bounds = bounds.merge(entry["box"])
	var cut: float = bounds.position.y + bounds.size.y * height_fraction
	var hidden := 0
	for entry in boxes:
		var box: AABB = entry["box"]
		var instance: MeshInstance3D = entry["node"]
		if instance.visible and box.position.y + box.size.y <= cut:
			instance.visible = false
			hidden += 1
	return hidden


## Same treatment as clarify_canopy(), for a model whose parts carry no names:
## the canopy is whichever meshes sit wholly inside the forward upper part of
## the airframe. Without this the Nighthawk's canopy facets are opaque from the
## inside and the cockpit view is a blue wall rather than a view.
static func clarify_canopy_by_bounds(root: Node3D, basis: Basis) -> int:
	var boxes := _oriented_boxes(root, basis)
	if boxes.is_empty():
		return 0
	var bounds: AABB = boxes[0]["box"]
	for entry in boxes:
		bounds = bounds.merge(entry["box"])
	var region := AABB(
		Vector3(
			bounds.position.x + bounds.size.x * 0.45,
			bounds.position.y + bounds.size.y * 0.45,
			bounds.position.z - 1.0),
		Vector3(bounds.size.x * 0.60, bounds.size.y * 0.70, bounds.size.z + 2.0))
	var changed := 0
	for entry in boxes:
		if not region.encloses(entry["box"]):
			continue
		var instance: MeshInstance3D = entry["node"]
		for surface in range(instance.mesh.get_surface_count()):
			var material := instance.get_active_material(surface)
			if not material is BaseMaterial3D:
				continue
			instance.set_surface_override_material(
				surface, clarified_canopy_material(material as BaseMaterial3D)
			)
			changed += 1
	return changed


## Every mesh under the root with its box in the engine's convention, measured
## in the root's own frame so the aeroplane's position in the world is
## irrelevant.
static func _oriented_boxes(root: Node3D, basis: Basis) -> Array:
	var into_root := root.global_transform.affine_inverse()
	var turn := Transform3D(basis, Vector3.ZERO)
	var boxes: Array = []
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		var local: AABB = (turn * into_root * instance.global_transform) * instance.get_aabb()
		boxes.append({"node": instance, "box": local})
	return boxes
