extends SceneTree

const BUILDING_CHUNK_LAYOUT := preload("res://scripts/terrain/building_chunk_layout.gd")
const CATALOG_PATH := "res://data/regions/catalog.json"


func _init() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null, "region catalog must be readable")
	var catalog: Dictionary = JSON.parse_string(file.get_as_text())
	var surfers: Dictionary = {}
	for region in catalog.get("regions", []):
		if String(region.get("id", "")) == "au_qld_surfers":
			surfers = region
			break

	assert(not surfers.is_empty(), "Surfers theatre must be installed")
	assert(float(surfers.get("world_size_m", 0.0)) == 12000.0, "Surfers map must span 12 km")
	assert(int(surfers.get("chunk_count", 0)) == 18, "larger map must preserve 667 m chunks")
	assert(
		is_equal_approx(
			float(surfers["world_size_m"]) / float(surfers["chunk_count"]),
			8000.0 / 12.0
		),
		"terrain and imagery density must not fall when the footprint grows"
	)

	var offset := int(surfers.get("building_chunk_offset", 0))
	var building_offset := Vector2i(offset, offset)
	var directory := String(surfers["buildings_dir"])
	assert(
		BUILDING_CHUNK_LAYOUT.path_for(directory, Vector2i(9, 9), building_offset).ends_with("/6_6.json"),
		"central buildings must retain their source chunk"
	)
	assert(
		BUILDING_CHUNK_LAYOUT.path_for(directory, Vector2i(2, 9), building_offset).is_empty(),
		"outer terrain ring must not alias a city chunk"
	)

	print("MAP_FOOTPRINT_TEST_PASS")
	quit()
