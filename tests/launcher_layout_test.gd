extends SceneTree

const LAYOUT := preload("res://scripts/entities/launcher_layout.gd")


func _init() -> void:
	var positions := LAYOUT.positions_for("au_qld_surfers")
	assert(positions.size() == 10, "the Surfers beach must carry exactly ten launchers")
	for index in range(1, positions.size()):
		assert(positions[index].y > positions[index - 1].y, "launchers must progress south along the beach")
	assert(LAYOUT.positions_for("au_qld_burleigh").is_empty(), "the Surfers launcher field must not leak into other theatres")
	print("LAUNCHER_LAYOUT_TEST_PASS")
	quit()
