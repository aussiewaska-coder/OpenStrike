extends SceneTree

const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")

class Effects:
	extends Node3D
	func spawn_impact(_hit, _round) -> void:
		pass
	func spawn_explosion(_position) -> void:
		pass

class Reticle:
	extends Node
	func show_hit_confirm(_destructive) -> void:
		pass

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://tests/fixtures/tracking_impact_main.gd").new()
	var squadron = load("res://scripts/entities/enemy_squadron.gd").new()
	root.add_child(squadron)
	squadron.spawn(2, Vector3.ZERO)
	var camera := Camera3D.new()
	root.add_child(camera)
	main.camera = camera
	main.enemy_squadron = squadron
	main.impact_fx = Effects.new()
	main.attack_reticle = Reticle.new()
	var target = squadron.jets()[0]
	var origin: Vector3 = target.position + Vector3(0, 0, 1000)
	main._tracker.update(squadron.contacts(), origin, Vector3.FORWARD, Vector3.ZERO)
	main._tracker.cycle_view_lock([target.id], origin, Vector3.FORWARD)
	var hit := HIT.new()
	hit.object_type = HIT.ObjectKind.ENTITY
	hit.object_id = target.id
	hit.position = target.position
	main._on_projectile_impacted(hit, load("res://scripts/weapons/cannon_round.gd").new())
	var released: bool = not main._tracker.tracking_view and main._tracker.locked().is_empty()
	var removed: bool = main._tracker.contact_for(target.id).is_empty()
	# The next refresh must keep the target absent and leave the wingman alive.
	main._tracker.update(squadron.contacts(), origin, Vector3.FORWARD, Vector3.ZERO)
	var stays_released: bool = not main._tracker.tracking_view and main._tracker.locked().is_empty()
	main.impact_fx.free()
	main.attack_reticle.free()
	main.free()
	squadron.free()
	camera.free()
	if not released or not removed or not stays_released:
		push_error("a lethal impact must immediately remove the contact and release camera/weapon lock")
		quit(1)
		return
	print("DESTROYED_TRACKING_TEST_PASS")
	quit()
