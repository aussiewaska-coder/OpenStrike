extends Node3D

## Render-only condensation. World-space history never moves with its emitter.
const SHADER := preload("res://shaders/wing_vapor.gdshader")
const SAMPLE_SECONDS := 1.0 / 30.0
const LIFETIME := 4.0
const MAX_POINTS := 128
var carrier: Node3D
var tips := PackedVector3Array()
var moisture := 0.7
var strength := 0.0
var _wanted := 0.0
var _now := 0.0
var _sample_clock := 0.0
var _history: Array[Array] = [[], []]
var _last_pose := Transform3D.IDENTITY
var _have_pose := false
var _sheet_root: Node3D
var _sheets: Array[MeshInstance3D] = []
var _sheet_material: ShaderMaterial
var _trail_material: ShaderMaterial
var _ribbon: MeshInstance3D
var _mesh: ImmediateMesh
var _surface_started := false

func build(model: Node3D) -> void:
	carrier = get_parent() as Node3D
	# This node consumes the carrier's interpolated pose once, just as the model
	# is displayed. Applying automatic interpolation again would detach the tips.
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	tips = measure_tips(model, carrier)
	_sheet_material = ShaderMaterial.new()
	_sheet_material.shader = SHADER
	_sheet_root = Node3D.new()
	add_child(_sheet_root)
	for tip in tips:
		var sheet := MeshInstance3D.new()
		sheet.mesh = _wing_sheet(tip)
		sheet.material_override = _sheet_material
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sheet_root.add_child(sheet)
		_sheets.append(sheet)
	_trail_material = ShaderMaterial.new()
	_trail_material.shader = SHADER
	_trail_material.set_shader_parameter("trail", true)
	_ribbon = MeshInstance3D.new()
	_mesh = ImmediateMesh.new()
	_ribbon.mesh = _mesh
	_ribbon.material_override = _trail_material
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ribbon)
	clear()

static func measure_tips(model: Node3D, anchor: Node3D) -> PackedVector3Array:
	# Measure visible geometry after model orientation, scale and gear stow.
	# Average the outermost vertices so the emitter sits on each actual wing.
	var inverse := anchor.global_transform.affine_inverse()
	var surfaces: Array = []
	var span := 0.0
	for child in model.find_children("*", "MeshInstance3D", true, false):
		if child.mesh == null or not _part_visible(child, anchor):
			continue
		var transform: Transform3D = inverse * child.global_transform
		for surface in child.mesh.get_surface_count():
			var vertices: PackedVector3Array = child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			surfaces.append([vertices, transform])
			for vertex in vertices:
				span = maxf(span, absf((transform * vertex).z))
	var sums := [Vector3.ZERO, Vector3.ZERO]
	var counts := [0, 0]
	for surface in surfaces:
		for vertex in surface[0]:
			var p: Vector3 = surface[1] * vertex
			if absf(p.z) >= span * 0.975:
				var side := 0 if p.z < 0 else 1
				sums[side] += p
				counts[side] += 1
	var result := PackedVector3Array()
	for side in 2:
		result.append(sums[side] / maxf(counts[side], 1.0) if counts[side] > 0 else Vector3(-1, 0, -6 if side == 0 else 6))
	return result

static func _part_visible(part: Node3D, anchor: Node3D) -> bool:
	var node: Node = part
	while node != null and node != anchor:
		if node is Node3D and not node.visible:
			return false
		node = node.get_parent()
	return true

func _wing_sheet(tip: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 10
	var columns := 10
	for row in rows:
		for column in columns:
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				var uv := Vector2((column + corner.x) / columns, (row + corner.y) / rows)
				var span_fraction := lerpf(0.12, 1.02, uv.y)
				var chord := lerpf(5.8, 1.0, uv.y)
				var x := tip.x * span_fraction + (0.5 - uv.x) * chord
				var y := tip.y + 0.12 + sin(uv.x * PI) * sin(uv.y * PI) * 0.65
				surface.set_uv(uv)
				surface.add_vertex(Vector3(x, y, tip.z * span_fraction))
	return surface.commit()

static func demand(speed: float, load_g: float, alpha: float, humidity: float) -> float:
	# Game-scale visibility gates: unload or slow down and condensation clears.
	var pressure := smoothstep(65.0, 150.0, speed)
	var pull := smoothstep(1.7, 5.5, load_g)
	var incidence := smoothstep(deg_to_rad(5), deg_to_rad(18), alpha)
	return pressure * pull * lerpf(0.55, 1.0, incidence) * clampf(humidity, 0.0, 1.0)

func set_flight(speed: float, load_g: float, alpha: float, active := true) -> void:
	_wanted = demand(speed, load_g, alpha, moisture) if active else 0.0

func _process(delta: float) -> void:
	if is_instance_valid(carrier) and _sheet_root != null:
		advance(delta, carrier.get_global_transform_interpolated())

func advance(delta: float, pose: Transform3D) -> void:
	if _have_pose and pose.origin.distance_to(_last_pose.origin) > maxf(150.0, delta * 1200.0):
		clear()
	_now += delta
	strength = lerpf(strength, _wanted, 1.0 - exp(-delta * (5.0 if _wanted > strength else 3.5)))
	_sheet_root.global_transform = pose
	_sheet_root.visible = strength > 0.015
	_sheet_material.set_shader_parameter("strength", strength)
	_sheet_material.set_shader_parameter("flow_time", _now)
	_trail_material.set_shader_parameter("flow_time", _now)
	if not _have_pose:
		_last_pose = pose
		_have_pose = true
	_sample_clock += delta
	var samples := 0
	while _sample_clock >= SAMPLE_SECONDS and samples < 8:
		_sample_clock -= SAMPLE_SECONDS
		samples += 1
		if strength > 0.02:
			var fraction := clampf(1.0 - _sample_clock / maxf(delta, 0.00001), 0, 1)
			var at := _last_pose.interpolate_with(pose, fraction)
			for side in 2:
				_history[side].append({"point": at * tips[side], "born": _now - _sample_clock, "up": at.basis.y, "span": at.basis.z * (-1.0 if side == 0 else 1.0), "amount": strength})
	if samples == 8:
		_sample_clock = 0.0
	for side in 2:
		while not _history[side].is_empty() and (_now - float(_history[side][0].born) > LIFETIME or _history[side].size() > MAX_POINTS):
			_history[side].pop_front()
	_last_pose = pose
	_rebuild(pose)

static func displaced(sample: Dictionary, age: float) -> Vector3:
	var radius := minf(age * age * 0.35, 3.5)
	var phase := age * 3.5 + sin(float(sample.born) * 2.3) * age * 0.35
	return sample.point + sample.span * (cos(phase) - 1.0) * radius + sample.up * sin(phase) * radius + Vector3(0.9, -0.3 * age, 0.35) * age

func _rebuild(pose: Transform3D) -> void:
	_mesh.clear_surfaces()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_surface_started = false
	for side in 2:
		var points: Array = _history[side].duplicate()
		if not points.is_empty() and strength > 0.02:
			points.append({"point": pose * tips[side], "born": _now, "up": pose.basis.y, "span": pose.basis.z, "amount": strength})
		for index in range(points.size() - 1):
			var a: Dictionary = points[index]
			var b: Dictionary = points[index + 1]
			# A gap between separate pulls must not become a fresh straight line.
			if float(b.born) - float(a.born) > SAMPLE_SECONDS * 2.5:
				continue
			var age_a := _now - float(a.born)
			var age_b := _now - float(b.born)
			var pa := displaced(a, age_a)
			var pb := displaced(b, age_b)
			var crosswise := (pb - pa).cross(camera.global_position - (pa + pb) * 0.5).normalized()
			if crosswise.is_zero_approx():
				continue
			var wa := crosswise * (0.09 + pow(maxf(age_a, 0), 1.4) * 0.24)
			var wb := crosswise * (0.09 + pow(maxf(age_b, 0), 1.4) * 0.24)
			var alpha_a := float(a.amount) * pow(maxf(1.0 - age_a / LIFETIME, 0), 1.3) * 0.8
			var alpha_b := float(b.amount) * pow(maxf(1.0 - age_b / LIFETIME, 0), 1.3) * 0.8
			if not _surface_started:
				_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				_surface_started = true
			for vertex in [[pa-wa, Vector2(0, 0), alpha_a], [pa+wa, Vector2(0, 1), alpha_a], [pb+wb, Vector2(1, 1), alpha_b], [pa-wa, Vector2(0, 0), alpha_a], [pb+wb, Vector2(1, 1), alpha_b], [pb-wb, Vector2(1, 0), alpha_b]]:
				_mesh.surface_set_uv(vertex[1])
				_mesh.surface_set_color(Color(1, 1, 1, vertex[2]))
				_mesh.surface_add_vertex(vertex[0])
	if _surface_started:
		_mesh.surface_end()

func clear() -> void:
	_history = [[], []]
	strength = 0.0
	_wanted = 0.0
	_sample_clock = 0.0
	_have_pose = false
	if _mesh != null:
		_mesh.clear_surfaces()
	if _sheet_root != null:
		_sheet_root.hide()
