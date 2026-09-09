extends SceneTree

const LAYOUT := preload("res://scripts/entities/launcher_layout.gd")


func _init() -> void:
	for half in [4000.0, 6000.0]:
		var sites := LAYOUT.clusters_for("au_qld_surfers", half)
		assert(sites.size() == 6, "the layout supplies three city and three hinterland groups")
		for index in 3:
			assert(sites[index + 3].centre.x < sites[index].centre.x - 1000.0, "hinterland groups sit distinctly inland of the coastal city groups")
		for index in [1, 2, 4, 5]:
			assert(sites[index].centre.y > sites[index - 1].centre.y, "each area spans north, central and south")
	print("LAUNCHER_LAYOUT_TEST_PASS")
	quit()
