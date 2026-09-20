class_name SydneyLandmarks
extends RefCounted

## Procedural stand-ins for Sydney's skyline identity: the Harbour Bridge,
## the Opera House sails, and Centrepoint Tower. True-scale, Y-up, grounded
## at y = 0 like the Gold Coast GLB heroes, so hero_towers.gd places them
## untouched. Deliberately low-poly (a few dozen boxes); they read from
## 500 m, not from the footpath.

static var _materials := {}


static func _mat(key: String, colour: Color) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.85
		material.metallic = 0.0
		_materials[key] = material
	return _materials[key]


static func build_landmark(name: String) -> Node3D:
	match name:
		"HarbourBridge":
			return _build_bridge()
		"OperaHouse":
			return _build_opera_house()
		"Centrepoint":
			return _build_tower()
	return null


static func _box(parent: Node3D, size: Vector3, offset: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = offset
	instance.material_override = material
	parent.add_child(instance)
	return instance


## Beam between two points: a stretched box with X along the span.
static func _beam(parent: Node3D, a: Vector3, b: Vector3, height: float, width: float, material: Material) -> void:
	var direction := b - a
	var length := direction.length()
	if length < 0.01:
		return
	var x_axis := direction / length
	var up_hint := Vector3.UP
	if absf(x_axis.dot(Vector3.UP)) > 0.95:
		up_hint = Vector3.FORWARD
	var z_axis := x_axis.cross(up_hint).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(length, height, width)
	instance.mesh = mesh
	instance.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (a + b) * 0.5)
	instance.material_override = material
	parent.add_child(instance)


## The coathanger: deck on pylons, twin parabolic ribs, hangers. Deck runs
## along local +X (hero yaw turns it north-south over the harbour).
static func _build_bridge() -> Node3D:
	var root := Node3D.new()
	root.name = "HarbourBridge"
	var grey := _mat("bridge_grey", Color(0.45, 0.47, 0.50))
	var dark := _mat("bridge_dark", Color(0.30, 0.31, 0.34))
	# Deck 500 m at 55 m above the water, 24 m wide.
	_box(root, Vector3(500, 6, 24), Vector3(0, 55, 0), grey)
	_box(root, Vector3(500, 2, 2), Vector3(0, 59, -11), dark)
	_box(root, Vector3(500, 2, 2), Vector3(0, 59, 11), dark)
	# Twin arch ribs: 400 m span, 134 m rise.
	for side in [-10.0, 10.0]:
		var previous := Vector3.ZERO
		var steps := 24
		for i in range(steps + 1):
			var t := float(i) / float(steps)
			var x := lerpf(-200.0, 200.0, t)
			var y := 52.0 + 134.0 * (1.0 - pow((x / 200.0), 2.0))
			var point := Vector3(x, y, side)
			if i > 0:
				_beam(root, previous, point, 4.0, 3.0, grey)
			previous = point
	# Hangers every 20 m where the arch clears the deck.
	for x in range(-180, 181, 20):
		var arch_y := 52.0 + 134.0 * (1.0 - pow(float(x) / 200.0, 2.0))
		if arch_y > 62.0:
			for side in [-10.0, 10.0]:
				_box(root, Vector3(1.5, arch_y - 58.0, 1.5), Vector3(x, (arch_y + 58.0) * 0.5, side), dark)
	# Four pylons at the ends.
	for x in [-236.0, 236.0]:
		for side in [-14.0, 14.0]:
			_box(root, Vector3(18, 90, 12), Vector3(x, 45, side), grey)
	return root


## Sails as scaled half-buried vaults on a podium: the silhouette, not the
## tiles. Faces the harbour to the north-east; yaw handles the rest.
static func _build_opera_house() -> Node3D:
	var root := Node3D.new()
	root.name = "OperaHouse"
	var shell := _mat("opera_shell", Color(0.88, 0.86, 0.80))
	var base := _mat("opera_base", Color(0.55, 0.50, 0.44))
	_box(root, Vector3(110, 12, 70), Vector3(0, 6, 0), base)
	var vaults := [
		[26.0, 30.0, 16.0, -18.0], [22.0, 24.0, 14.0, 2.0], [18.0, 18.0, 12.0, 20.0],
	]
	for v in vaults:
		for side in [-1.0, 1.0]:
			var instance := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 1.0
			mesh.height = 2.0
			mesh.radial_segments = 12
			mesh.rings = 6
			instance.mesh = mesh
			instance.scale = Vector3(v[0], v[1], v[2])
			instance.position = Vector3(v[3], 12.0, side * 14.0)
			instance.material_override = shell
			root.add_child(instance)
	return root


## Centrepoint: shaft, turret drum, spire. 309 m all told.
static func _build_tower() -> Node3D:
	var root := Node3D.new()
	root.name = "Centrepoint"
	var shaft := _mat("tower_shaft", Color(0.60, 0.62, 0.65))
	var drum := _mat("tower_drum", Color(0.72, 0.70, 0.62))
	var shaft_mesh := MeshInstance3D.new()
	var column := CylinderMesh.new()
	column.top_radius = 6.0
	column.bottom_radius = 9.0
	column.height = 250.0
	column.radial_segments = 12
	shaft_mesh.mesh = column
	shaft_mesh.position = Vector3(0, 125, 0)
	shaft_mesh.material_override = shaft
	root.add_child(shaft_mesh)
	var drum_mesh := MeshInstance3D.new()
	var turret := CylinderMesh.new()
	turret.top_radius = 14.0
	turret.bottom_radius = 14.0
	turret.height = 22.0
	turret.radial_segments = 16
	drum_mesh.mesh = turret
	drum_mesh.position = Vector3(0, 258, 0)
	drum_mesh.material_override = drum
	root.add_child(drum_mesh)
	var spire_mesh := MeshInstance3D.new()
	var spire := CylinderMesh.new()
	spire.top_radius = 0.4
	spire.bottom_radius = 1.2
	spire.height = 40.0
	spire.radial_segments = 8
	spire_mesh.mesh = spire
	spire_mesh.position = Vector3(0, 289, 0)
	spire_mesh.material_override = shaft
	root.add_child(spire_mesh)
	return root
