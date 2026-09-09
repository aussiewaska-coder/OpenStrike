extends SceneTree

const JET := preload("res://scripts/jet/jet_controller.gd")
const AIRFRAME := preload("res://scripts/jet/airframe.gd")
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for profile in [AIRFRAME.raptor(), AIRFRAME.nighthawk(), AIRFRAME.super_hornet(), AIRFRAME.lightning()]:
		var jet = JET.new()
		jet.airframe = profile
		jet.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		var visual: Node3D = load(profile.scene_path).instantiate()
		visual.name = "HeroJet"
		jet.add_child(visual)
		root.add_child(jet)
		jet.set_physics_process(false)
		await process_frame
		jet._world_limit = 100000.0
		jet.launch(Vector3(0, 900, 0), 0.7)
		_check_first_person_camera(jet, visual)
		var installed: Transform3D = visual.transform
		var nose_before: Vector3 = jet.global_transform.affine_inverse() * jet.get_cockpit_transform().origin
		for frame in range(5):
			jet._physics_process(1.0 / 60.0)
			var mesh_nose: Vector3 = (visual.global_basis * (profile.model_basis.inverse() * Vector3.RIGHT)).normalized()
			var alignment: float = mesh_nose.dot(jet.global_basis.x.normalized())
			print("VISUAL_FORWARD %s frame=%d dot=%.3f" % [profile.display_name, frame, alignment])
			_check(alignment > 0.999, "rendered nose must match flight direction after every production visual update")
			_check(visual.transform.is_equal_approx(installed), "visual updates must preserve installed model rotation and scale")
		var nose_after: Vector3 = jet.global_transform.affine_inverse() * jet.get_cockpit_transform().origin
		_check(nose_after.distance_to(nose_before) < 0.001, "updating the visual must not move the nose camera across the aircraft")
		var camera_frame: Transform3D = jet.get_interpolated_airframe_transform()
		var displayed_airframe: Transform3D = jet.get_global_transform_interpolated()
		_check(camera_frame.basis.x.normalized().dot(displayed_airframe.basis.x.normalized()) > 0.999, "camera must receive the aircraft nose, not the imported mesh axis")
		_check(camera_frame.basis.y.normalized().dot(displayed_airframe.basis.y.normalized()) > 0.999, "camera must receive aircraft up")
		jet.basis = Basis.from_euler(Vector3(0.3, 1.2, 0.6))
		jet._measure_first_person_camera()
		_check_first_person_camera(jet, visual)
		var rotated_nose: Vector3 = jet.global_transform.affine_inverse() * jet.get_cockpit_transform().origin
		_check(rotated_nose.distance_to(nose_before) < 0.001, "camera placement must not depend on heading or bank when measured")
		jet.free()
	await _switch_models()
	if not failed:
		print("AIRFRAME_VISUAL_RUNTIME_TEST_PASS")
	quit(1 if failed else 0)

func _switch_models() -> void:
	var main = load("res://scripts/main.gd").new()
	var jet = JET.new()
	root.add_child(jet)
	jet.set_physics_process(false)
	var helicopter := Node3D.new()
	root.add_child(helicopter)
	main.jet_anchor = jet
	main.helicopter_anchor = helicopter
	var previous_gun: WeakRef
	for index in [3, 0, 1, 2, 3, 0]:
		main._jet_index = index
		main._spawn_jet()
		await process_frame
		var installed := jet.get_node("HeroJet")
		_check(is_instance_valid(jet._visual) and jet._visual == installed, "spawning a replacement must rebind the controller to the new model")
		if not is_instance_valid(jet._visual) or jet._visual != installed:
			continue
		if previous_gun != null:
			_check(previous_gun.get_ref() == null, "replacement must remove the previous gun mount")
		previous_gun = weakref(jet.get_gun_mount())
		_check((jet._effects != null) == jet.airframe.has_jet_effects, "replacement must use only the current airframe's effects")
		jet._physics_process(1.0 / 60.0)
		var nose: Vector3 = (installed.global_basis * (jet.airframe.model_basis.inverse() * Vector3.RIGHT)).normalized()
		_check(nose.dot(jet.global_basis.x.normalized()) > 0.999, "switched aircraft must point along the flight nose")
		_check(jet.get_hardpoints().size() == 2, "replacement must rebuild its own hardpoints without duplicates")
	jet.free()
	helicopter.free()
	main.free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _check_first_person_camera(jet: Node3D, visual: Node3D) -> void:
	var camera_frame: Transform3D = jet.get_cockpit_transform()
	var camera_local: Vector3 = jet.global_transform.affine_inverse() * camera_frame.origin
	var forwardmost := -INF
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var bounds := mesh.get_aabb()
		var mesh_to_aircraft := jet.global_transform.affine_inverse() * mesh.global_transform
		for corner in range(8):
			forwardmost = maxf(forwardmost, (mesh_to_aircraft * bounds.get_endpoint(corner)).x)
	print("NOSE_CAMERA %s forwardmost=%.3f camera_x=%.3f" % [jet.airframe.display_name, forwardmost, camera_local.x])
	if jet.airframe.has_cockpit:
		_check(camera_local.x < forwardmost, "modelled cockpit must remain inside the aircraft")
	else:
		_check(camera_local.x > forwardmost + 0.1 and camera_local.x < forwardmost + 1.0, "F-117 camera must sit ahead of the nose")
	_check(camera_frame.basis.is_equal_approx(_camera_basis(jet, jet.global_basis)), "nose camera must follow aircraft axes without cockpit tilt")
	var interpolated: Transform3D = jet.get_interpolated_cockpit_transform()
	var displayed: Transform3D = jet.get_global_transform_interpolated()
	_check(interpolated.origin.distance_to(displayed * camera_local) < 0.001 and interpolated.basis.is_equal_approx(_camera_basis(jet, displayed.basis)), "nose camera must use displayed aircraft position and attitude")

func _camera_basis(jet: Node3D, basis: Basis) -> Basis:
	var expected := basis.orthonormalized()
	return expected.rotated(expected.z, deg_to_rad(jet.airframe.cockpit_pitch_degrees)) if jet.airframe.has_cockpit else expected
