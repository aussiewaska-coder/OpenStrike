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
