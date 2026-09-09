extends SceneTree
const JET := preload("res://scripts/jet/jet_controller.gd")
const AIRFRAME := preload("res://scripts/jet/airframe.gd")
const SQUADRON := preload("res://scripts/entities/enemy_squadron.gd")
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for profile in [AIRFRAME.raptor(), AIRFRAME.nighthawk(), AIRFRAME.super_hornet(), AIRFRAME.lightning()]:
		var jet := JET.new()
		jet.airframe = profile
		var model: Node3D = load(profile.scene_path).instantiate()
		model.name = "HeroJet"
		jet.add_child(model)
		root.add_child(jet)
		jet.set_physics_process(false)
		await process_frame
		jet._vapor.set_process(false)
		var tips: PackedVector3Array = jet._vapor.tips
		print("VAPOR_TIPS %s %s" % [profile.display_name, tips])
		check(tips.size() == 2 and tips[0].z < 0 and tips[1].z > 0, "each aircraft has a pair of correctly oriented wingtip emitters")
		check(absf(tips[1].z - tips[0].z - profile.reference_wingspan_m) < 0.8, "emitters follow the installed aircraft's actual wingspan")
		jet.velocity = Vector3(220, 0, 0)
		jet.load_factor = 7
		jet.alpha = 0.3
		var before := jet.transform
		jet._update_visual(0.1)
		jet._vapor.advance(0.2, jet.global_transform)
		check(jet._vapor.strength > 0.3 and not jet._vapor._history[0].is_empty(), "production flight telemetry drives both wing sheets and trails")
		check(jet.transform == before, "condensation leaves the flight anchor rigid")
		jet.launch(Vector3(0, 1500, 0), 0)
		check(jet._vapor._history[0].is_empty() and jet._vapor.strength == 0, "respawn clears old vapor immediately")
		jet._crashed = true
		jet._update_visual(0.1)
		check(jet._vapor._wanted == 0, "crashed aircraft stop emitting")
		jet.free()
	var squadron := SQUADRON.new()
	root.add_child(squadron)
	squadron.spawn(1, Vector3(0, 1500, 0), Vector3.FORWARD)
	var enemy: RefCounted = squadron.jets()[0]
	var vapor: Node3D = squadron._visuals[enemy.id].get_node("WingVapor")
	var maximum := 0.0
	for frame in 120:
		squadron.update(1.0 / 60.0, enemy.position + Vector3(700, 0, 0), Vector3.LEFT)
		maximum = maxf(maximum, vapor._wanted)
	check(maximum > 0.1, "enemy manoeuvre curvature also drives visible vapor")
	squadron.clear()
	await process_frame
	check(not is_instance_valid(vapor), "removing an enemy releases its vapor rig")
	squadron.free()
	if not failed:
		print("WING_VAPOR_RUNTIME_TEST_PASS")
	quit(1 if failed else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
