extends Node3D

## Local visual rig. The physical airframe and cockpit mount stay rigid.
const PLUME := preload("res://shaders/afterburner.gdshader")
var ailerons: Array[Node3D] = []
var plumes: Array[MeshInstance3D] = []
var lights: Array[OmniLight3D] = []
var _roll := 0.0
var _time := 0.0
var _exhaust_origins := PackedVector3Array()

func build(model: Node3D, profile = null) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if node.get_parent().name.to_lower().begins_with("f-22-airframe"):
			_rig_wings(node)
	# Nozzle positions follow the installed model scale and orientation.
	_exhaust_origins = PackedVector3Array([Vector3(-3.65, 0, -0.69), Vector3(-3.65, 0, 0.69)])
	var radius := 0.48
	if profile != null:
		radius = profile.exhaust_radius_m
		if not profile.exhaust_model_positions.is_empty():
			_exhaust_origins.clear()
			for origin in profile.exhaust_model_positions:
				_exhaust_origins.append(model.transform * origin)
	for origin in _exhaust_origins:
		var plume := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.05
		mesh.bottom_radius = radius
		mesh.height = 1.0
		mesh.radial_segments = 16
		mesh.rings = 6
		plume.mesh = mesh
		plume.rotation.z = PI * 0.5 # Bottom cap at nozzle, tip toward -X.
		plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = PLUME
		plume.material_override = material
		plume.position = origin
		add_child(plume)
		plumes.append(plume)
		var light := OmniLight3D.new()
		light.position = origin + Vector3.RIGHT * 0.05
		light.light_color = Color(0.40, 0.52, 1.0)
		light.omni_range = 3.5
		light.shadow_enabled = false
		add_child(light)
		lights.append(light)
	update(0.0, 0.0, 0.0, 0.0)

func _rig_wings(source: MeshInstance3D) -> void:
	# This asset's mesh axes are X nose, Y span, Z down. Its trailing panels
	# already have seam vertices. Partition triangles, preserving every vertex,
	# normal, tangent, UV and material; never modify the shared imported mesh.
	var arrays := source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var groups: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for i in range(0, indices.size(), 3):
		var center := (vertices[indices[i]] + vertices[indices[i+1]] + vertices[indices[i+2]]) / 3.0
		var span := absf(center.y)
		var group := 0
		if span > 45.0 and span < 59.0 and center.x > -20.0 and center.x < 0.307 * span - 17.8:
			group = 1 if center.y < 0.0 else 2
		groups[group].append_array(indices.slice(i, i+3))
	var material := source.get_active_material(0)
	var format: int = source.mesh.surface_get_format(0)
	for group in range(3):
		var mesh := ArrayMesh.new()
		var subset := arrays.duplicate()
		subset[Mesh.ARRAY_INDEX] = groups[group]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, subset, [], {}, format)
		mesh.surface_set_material(0, material)
		if group == 0:
			source.mesh = mesh
			continue
		var side := -1.0 if group == 1 else 1.0
		var pivot := Node3D.new()
		pivot.name = "LeftAileron" if group == 1 else "RightAileron"
		source.get_parent().add_child(pivot)
		pivot.transform = source.transform
		var hinge := Vector3(-1.835, side * 52.0, 0.0)
		pivot.position += source.basis * hinge
		var panel := MeshInstance3D.new()
		panel.mesh = mesh
		panel.position = -hinge
		pivot.add_child(panel)
		pivot.set_meta("rest", pivot.basis)
		pivot.set_meta("axis", Vector3(0.307, side, 0.0).normalized())
		ailerons.append(pivot)

func update(delta: float, roll: float, brake: float, burner: float) -> void:
	_time = fmod(_time + delta, 100.0)
	_roll = lerpf(_roll, clampf(roll, -1.0, 1.0), 1.0 - exp(-12.0 * delta))
	for i in range(ailerons.size()):
		var side := -1.0 if i == 0 else 1.0
		var angle := deg_to_rad(-18.0 * _roll - 12.0 * brake * side)
		ailerons[i].basis = (ailerons[i].get_meta("rest") as Basis) * Basis(ailerons[i].get_meta("axis"), angle)
	var pulse := 0.94 + 0.04 * sin(_time * 31.0) + 0.02 * sin(_time * 53.0)
	for i in range(plumes.size()):
		var length := (0.6 + 4.8 * burner) * pulse
		plumes[i].visible = burner > 0.005
		plumes[i].scale.y = length
		plumes[i].position = _exhaust_origins[i] + Vector3.LEFT * length * 0.5
		plumes[i].material_override.set_shader_parameter("power", burner)
		lights[i].light_energy = burner * 1.5 * pulse
		lights[i].visible = burner > 0.005

static func cockpit_vibration(time: float, burner: float, brake: float) -> Vector3:
	var amount := clampf(burner * 0.045 + brake * 0.075, 0.0, 0.12)
	return Vector3(sin(time * 29.0), sin(time * 37.0) * 0.55, sin(time * 23.0) * 0.35) * amount
