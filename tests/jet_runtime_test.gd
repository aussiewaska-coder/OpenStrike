extends SceneTree

const JET := preload("res://scripts/jet/jet_controller.gd")
const STEP := 1.0 / 60.0


class FlatTerrain:
	extends Node

	func world_half_extent() -> float:
		return 6000.0

	func sample_height_world(_x: float, _z: float) -> float:
		return 0.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var terrain := FlatTerrain.new()
	root.add_child(terrain)
	var jet := JET.new()
	root.add_child(jet)
	jet.set_physics_process(false)
	jet.set_terrain(terrain)
	jet.launch(Vector3(0.0, 900.0, 0.0), 0.0)

	var starting_altitude := jet.altitude_above_ground()
	assert(jet.alpha > 0.0, "production launch must begin with positive level-flight trim")
	assert(jet.basis.x.y > 0.0, "trimmed launch must place the nose above the flight path")
	for _frame in range(15 * 60):
		jet._physics_process(STEP)

	assert(not jet.is_crashed(), "hands-off launch must remain airborne")
	assert(absf(jet.altitude_above_ground() - starting_altitude) < 25.0, "hands-off launch must hold usable altitude")
	assert(absf(jet.velocity.y) < 2.0, "hands-off launch must not enter a steep climb or dive")
	assert(absf(rad_to_deg(jet.bank)) < 1.0, "hands-off launch must keep its wings level")

	jet.basis = jet.basis.rotated(jet.basis.x, deg_to_rad(55.0)).orthonormalized()
	var recovery_start := absf(JET.bank_angle(jet.basis))
	assert(jet.request_wings_level(), "R3 recovery must engage at flying speed")
	for _frame in range(60):
		jet._physics_process(STEP)
	assert(
		absf(JET.bank_angle(jet.basis)) < recovery_start * 0.4,
		"R3 recovery must substantially level the wings"
	)
	print("JET_RUNTIME_TEST_PASS")
	quit()
