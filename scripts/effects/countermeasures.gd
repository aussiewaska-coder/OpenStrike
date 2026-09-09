extends Node3D
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const MATERIALS := preload("res://scripts/effects/effect_materials.gd")
const CAPACITY := 8
var charges := CAPACITY
var cooldown := 0.0
var _refill := 0.0
var _sequence := -100
var decoys: Array[Dictionary] = []

func clear() -> void:
	for decoy in decoys:
		decoy.visual.queue_free()
	decoys.clear()
	charges = CAPACITY
	cooldown = 0.0
	_refill = 0.0

func deploy(point: Vector3, velocity: Vector3, nose: Vector3) -> bool:
	if charges <= 0 or cooldown > 0.0:
		return false
	charges -= 1
	cooldown = 2.5
	var right := nose.cross(Vector3.UP).normalized()
	if right.is_zero_approx(): right = Vector3.RIGHT
	for i in range(6):
		_sequence -= 1
		var flare := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(7, 7)
		flare.mesh = quad
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.albedo_texture = MATERIALS.soft_disc()
		material.albedo_color = Color(1.0, 0.75, 0.25)
		material.emission_enabled = true
		material.emission = Color(1, 0.45, 0.06)
		material.emission_energy_multiplier = 4.0
		flare.material_override = material
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flare)
		var origin := point - nose * 8.0
		flare.global_position = origin
		decoys.append({"handle": _sequence, "position": origin, "velocity": velocity * 0.6 - nose * 45.0 + right * (float(i) - 2.5) * 22.0 + Vector3.DOWN * (8 + i * 3), "age": 0.0, "visual": flare})
	return true

func update(delta: float) -> void:
	cooldown = maxf(0, cooldown - delta)
	_refill += delta
	if _refill >= 10.0:
		_refill = fmod(_refill, 10.0)
		charges = mini(CAPACITY, charges + 1)
	for decoy in decoys.duplicate():
		decoy.age += delta
		if decoy.age >= 5.0:
			decoy.visual.queue_free()
			decoys.erase(decoy)
			continue
		decoy.velocity *= exp(-0.7 * delta)
		decoy.velocity.y -= 9.8 * delta
		decoy.position += decoy.velocity * delta
		decoy.visual.global_position = decoy.position
		decoy.visual.scale = Vector3.ONE * (1.0 - float(decoy.age) / 5.0)

func contacts() -> Array:
	var out := []
	for decoy in decoys:
		var contact := TRACKER.contact(decoy.handle, TRACKER.Kind.AIR_JET, decoy.position, decoy.velocity, "FLARE / CHAFF")
		contact["age"] = decoy.age
		out.append(contact)
	return out

func button_text() -> String:
	return "COUNTERMEASURES %d • %.1f" % [charges, cooldown] if cooldown > 0 else "COUNTERMEASURES %d" % charges
