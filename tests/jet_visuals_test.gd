extends SceneTree

const JET_SCENE := preload("res://assets/models/f-22_raptor_-_fighter_jet_-_free.glb")
const JET_VISUALS := preload("res://scripts/jet/jet_visuals.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var jet := JET_SCENE.instantiate()
	root.add_child(jet)
	var changed := JET_VISUALS.clarify_canopy(jet)
	assert(changed > 0, "the imported F-22 canopy mesh must receive a material override")
	var canopy := jet.find_child("*canopy*", true, false)
	assert(canopy != null, "the imported fixture must retain its named canopy node")
	var canopy_mesh := canopy.find_child("*", true, false) as MeshInstance3D
	assert(canopy_mesh != null, "the canopy node must contain a mesh")
	var material := canopy_mesh.get_active_material(0) as BaseMaterial3D
	assert(material != null, "the canopy must expose a 3D material")
	assert(material.albedo_color.a <= 0.24, "canopy must be transparent enough to see the HUD and panel")
	assert(material.albedo_color.r < 0.9, "canopy must not retain the imported orange tint")
	assert(material.disable_receive_shadows, "canopy must not darken under its own aircraft shadow")
	print("JET_VISUALS_TEST_PASS")
	quit()
