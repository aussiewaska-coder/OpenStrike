extends Node3D

const MATERIALS := preload("res://scripts/effects/effect_materials.gd")
const PRESENTATION := preload("res://scripts/weapons/projectile_presentation.gd")
const POOL_SIZE := 24
var projectile_manager: Node3D
var _models: Array[Node3D] = []

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for index in range(POOL_SIZE):
		var model := Node3D.new()
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.8, 0.84, 0.86)
		metal.metallic = 0.4
		metal.roughness = 0.3
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.14
		capsule.height = 2.6
		capsule.radial_segments = 8
		capsule.rings = 2
		body.mesh = capsule
		body.rotation.z = PI * 0.5
		body.material_override = metal
		model.add_child(body)
		for vertical in [false, true]:
			var fin := MeshInstance3D.new()
			var shape := BoxMesh.new()
			shape.size = Vector3(0.65, 0.7 if vertical else 0.035, 0.035 if vertical else 0.7)
			fin.mesh = shape
			fin.position.x = -0.8
			fin.material_override = metal
			model.add_child(fin)
		var exhaust := MeshInstance3D.new()
		exhaust.name = "Exhaust"
		var quad := QuadMesh.new()
		quad.size = Vector2(3.4, 1.3)
		exhaust.mesh = quad
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		glow.billboard_keep_scale = true
		glow.albedo_texture = MATERIALS.soft_disc()
		glow.albedo_color = Color(1.0, 0.52, 0.12)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.35, 0.05)
		glow.emission_energy_multiplier = 4.0
		exhaust.material_override = glow
		exhaust.position.x = -1.7
		exhaust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(exhaust)
		model.visible = false
		add_child(model)
		_models.append(model)

func _process(_delta: float) -> void:
	var used := 0
	if projectile_manager != null:
		for round_data in projectile_manager.active_rounds:
			if round_data.weapon_source not in ["missile", "rocket", "guided_bomb"] or used >= _models.size():
				continue
			var model := _models[used]
			used += 1
			var direction: Vector3 = round_data.velocity.normalized()
			if direction.is_zero_approx():
				direction = Vector3.FORWARD
			var previous_up: Vector3 = model.global_basis.y.normalized() if int(model.get_meta("sequence", -1)) == round_data.sequence else Vector3.UP
			var up := PRESENTATION.transported_up(direction, previous_up)
			var right := direction.cross(up).normalized()
			up = right.cross(direction).normalized()
			var point := PRESENTATION.position_of(round_data)
			model.global_transform = Transform3D(Basis(direction, up, right), point)
			model.set_meta("sequence", round_data.sequence)
			model.scale *= 0.65 if round_data.weapon_source == "rocket" else 1.0
			if round_data.weapon_source == "guided_bomb":
				model.scale *= Vector3(0.65, 1.8, 1.8)
			model.visible = true
			var exhaust: MeshInstance3D = model.get_node("Exhaust")
			exhaust.visible = round_data.flight.is_boosting(round_data.age)
			exhaust.scale = Vector3.ONE * (0.95 + 0.08 * sin(round_data.age * 71.0))
	for index in range(used, _models.size()):
		_models[index].visible = false
