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
	var to_xz := func(lat: float, lon: float) -> Vector2: return Vector2((lon - 151.20) * 90000.0, (lat + 33.87) * 111320.0)
	var syd := LAYOUT.clusters_for("au_nsw_sydney_harbour", 25000.0, to_xz)
	assert(syd.size() == 6, "Sydney supplies six game sites")
	assert(syd[1].centre.distance_to(Vector2.ZERO) < 6000.0, "Sydney city central sits near the harbour spawn")
	for index in 3:
		assert(syd[index + 3].centre.x < syd[index].centre.x - 1000.0, "Sydney hinterland sits inland of the city")
	print("LAUNCHER_LAYOUT_TEST_PASS")
	quit()
