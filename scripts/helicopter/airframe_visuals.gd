class_name AirframeVisuals
extends RefCounted


## The hero airframe is viewed at a steep angle in external cameras. Preserve
## texture detail across that angle without changing filtering for the terrain.
static func sharpen_materials(root: Node3D) -> int:
	var changed := 0
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in range(instance.mesh.get_surface_count()):
			var material := instance.get_active_material(surface)
			if not material is BaseMaterial3D:
				continue
			var sharpened := sharpen_material(material)
			instance.set_surface_override_material(surface, sharpened)
			changed += 1
	return changed


static func sharpen_material(material: BaseMaterial3D) -> BaseMaterial3D:
	var sharpened := material.duplicate() as BaseMaterial3D
	sharpened.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return sharpened
