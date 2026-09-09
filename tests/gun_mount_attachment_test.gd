extends SceneTree

const AIRFRAME := preload("res://assets/models/ah-64d_apache_longbow_usa.glb")
const GUN_MOUNT := preload("res://scripts/weapons/gun_mount.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var visual: Node3D = AIRFRAME.instantiate()
	visual.name = "HeroHelicopter"
	visual.scale = Vector3.ONE * 0.105
	root.add_child(visual)
	var gun: Node3D = GUN_MOUNT.new()
	gun.name = "GunMount"
	visual.add_child(gun)
	await process_frame
	assert(gun != null, "the production airframe must create a gun mount")
	var body_bounds := AABB()
	var found_body := false
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.is_ancestor_of(gun) or gun.is_ancestor_of(instance):
			continue
		var local: AABB = visual.global_transform.affine_inverse() * (instance.global_transform * instance.get_aabb())
		# The imported rotor mesh spans more than 200 source units laterally;
		# fuselage surfaces are below 20. Keep this fixture-specific distinction
		# independent from the production filtering algorithm.
		if local.size.z < 50.0:
			var world: AABB = instance.global_transform * instance.get_aabb()
			body_bounds = world if not found_body else body_bounds.merge(world)
			found_body = true
	assert(found_body, "the imported fixture must expose fuselage surfaces")
	var receiver := gun.find_child("Receiver", true, false) as MeshInstance3D
	var barrel := gun.find_child("Barrel", true, false) as MeshInstance3D
	var receiver_bounds: AABB = receiver.global_transform * receiver.get_aabb()
	var receiver_x := receiver_bounds.get_center().x
	assert(
		receiver_x >= body_bounds.position.x and receiver_x <= body_bounds.end.x,
		"gun receiver must sit under the fuselage, got x %.2f outside %.2f..%.2f" % [
			receiver_x, body_bounds.position.x, body_bounds.end.x,
		]
	)
	var attachment_gap := body_bounds.position.y - receiver_bounds.end.y
	assert(
		absf(attachment_gap) <= 0.12,
		"gun receiver must contact the belly, gap was %.2f m" % attachment_gap
	)
	assert(barrel.global_position.x > receiver.global_position.x, "barrel must point along the +X nose")
	assert(gun.get_muzzle_transform().origin.x > barrel.global_position.x, "muzzle must remain at the barrel tip")
	print("GUN_MOUNT_ATTACHMENT_TEST_PASS")
	quit()
