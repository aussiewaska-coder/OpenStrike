extends SceneTree

const BUILDING_CHUNK_LAYOUT := preload("res://scripts/terrain/building_chunk_layout.gd")
const CATALOG_PATH := "res://data/regions/catalog.json"


func _init() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null, "region catalog must be readable")
	var catalog: Dictionary = JSON.parse_string(file.get_as_text())
	var surfers: Dictionary = {}
	var corridor: Dictionary = {}
	for region in catalog.get("regions", []):
		if String(region.get("id", "")) == "au_qld_surfers":
			surfers = region
		elif String(region.get("id", "")) == "au_gold_coast_tweed_corridor":
			corridor = region

	assert(not surfers.is_empty(), "Surfers theatre must be installed")
	assert(not corridor.is_empty(), "Gold Coast corridor must be installed")
	assert(float(surfers.get("world_size_m", 0.0)) == 12000.0, "Surfers map must span 12 km")
	assert(int(surfers.get("chunk_count", 0)) == 18, "larger map must preserve 667 m chunks")
	assert(
		is_equal_approx(
			float(surfers["world_size_m"]) / float(surfers["chunk_count"]),
			8000.0 / 12.0
		),
		"terrain and imagery density must not fall when the footprint grows"
	)
	assert(float(corridor.get("world_size_m", 0.0)) == 50000.0, "corridor must span 50 km")
	assert(int(corridor.get("chunk_count", 0)) == 34, "50 km corridor must use 34 chunks per side")
	assert(
		int(corridor.get("heightfield_resolution", 0)) == 1025,
		"50 km corridor must retain terrain sampling density"
	)
	assert(
		float(corridor["world_size_m"]) / float(corridor["chunk_count"]) <= 1500.0,
		"50 km expansion must preserve the streamed detail density"
	)
	var corridor_offset_value := int(corridor.get("building_chunk_offset", 0))
	var corridor_offset := Vector2i(corridor_offset_value, corridor_offset_value)
	var corridor_buildings := String(corridor["buildings_dir"])
	assert(
		BUILDING_CHUNK_LAYOUT.path_for(corridor_buildings, Vector2i(17, 17), corridor_offset) \
			.ends_with("/12_12.json"),
		"the expanded outer ring must keep the existing city grid centred"
	)
	assert(
		BUILDING_CHUNK_LAYOUT.path_for(corridor_buildings, Vector2i(4, 17), corridor_offset).is_empty(),
		"the new outer flight ring must not alias an existing building chunk"
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
