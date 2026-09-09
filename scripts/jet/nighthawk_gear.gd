extends RefCounted

## Rig for the bundled F-117 GLB. Its Object_N nodes are material groups:
## Object_30 contains two wheels AND cockpit glass, so it cannot simply hide.
const STRUTS_AND_WHEELS := ["Object_22", "Object_27", "Object_28", "Object_29",
	"Object_31", "Object_32", "Object_33", "Object_34", "Object_35", "Object_36"]
const DOORS := ["Object_20", "Object_23", "Object_24"]

static func stow(root: Node3D) -> void:
	if root.has_meta("nighthawk_gear_stowed"):
		return
	var into_aircraft := root.transform * root.global_transform.affine_inverse()
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var part := String(mesh.name)
		if part in STRUTS_AND_WHEELS:
			mesh.hide()
		elif part == "Object_30":
			_remove_shared_wheels(mesh, into_aircraft * mesh.global_transform)
		elif part in DOORS:
			var frame := into_aircraft * mesh.global_transform
			var box: AABB = frame * mesh.get_aabb()
			# Hinge is the upper longitudinal edge. Rotate the hanging panel
			# inward until it lies flush across its gear bay.
			var hinge := Vector3(box.get_center().x, box.end.y, box.get_center().z)
			var rotation := Basis(Vector3.RIGHT, signf(hinge.z) * PI * 0.5)
			var close := Transform3D(rotation, hinge - rotation * hinge)
			var parent_frame := into_aircraft * mesh.get_parent_node_3d().global_transform
			mesh.transform = parent_frame.affine_inverse() * close * frame
	root.set_meta("nighthawk_gear_stowed", true)


static func _remove_shared_wheels(instance: MeshInstance3D, into_aircraft: Transform3D) -> void:
	var source := instance.mesh
	var stowed := ArrayMesh.new()
	for surface in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var kept := PackedInt32Array()
		for triangle in range(0, indices.size(), 3):
			# These disconnected wheels top out at -1.63 m. Glass starts above
			# -0.38 m, leaving a clear separation without cutting either part.
			var wheel := true
			for corner in range(3):
				wheel = wheel and (into_aircraft * vertices[indices[triangle + corner]]).y < -1.4
			if not wheel:
				kept.append_array(indices.slice(triangle, triangle + 3))
		arrays[Mesh.ARRAY_INDEX] = kept
		stowed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, source.surface_get_format(surface))
		stowed.surface_set_material(surface, source.surface_get_material(surface))
	instance.mesh = stowed
