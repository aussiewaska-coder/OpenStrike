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
	assert(
		int(corridor.get("chunk_count", 0)) ** 2 <= 400,
		"50 km terrain must stay within the mobile mesh/draw-call budget"
	)
	assert(
		int(corridor.get("heightfield_resolution", 0)) == 1025,
		"50 km corridor must retain terrain sampling density"
	)
	assert(int(corridor.get("building_chunk_count", 0)) == 24)
	assert(float(corridor.get("building_world_size_m", 0.0)) == 36000.0)
	var centre_sources := BUILDING_CHUNK_LAYOUT.source_chunks_for_bounds(
		Rect2(Vector2.ZERO, Vector2(2500.0, 2500.0)),
		float(corridor["building_world_size_m"]),
		int(corridor["building_chunk_count"])
	)
	assert(
		centre_sources == [Vector2i(12, 12), Vector2i(13, 12), Vector2i(12, 13), Vector2i(13, 13)],
		"coarse terrain chunks must load every overlapping source building file"
	)
	assert(
		BUILDING_CHUNK_LAYOUT.source_chunks_for_bounds(
			Rect2(Vector2(-25000.0, 0.0), Vector2(2500.0, 2500.0)),
			float(corridor["building_world_size_m"]),
			int(corridor["building_chunk_count"])
		).is_empty(),
		"the outer flight ring must not alias an existing building file"
	)
	var covered_sources := {}
	for z in range(20):
		for x in range(20):
			var terrain_bounds := Rect2(
				Vector2(-25000.0 + x * 2500.0, -25000.0 + z * 2500.0),
				Vector2(2500.0, 2500.0)
			)
			for source in BUILDING_CHUNK_LAYOUT.source_chunks_for_bounds(
				terrain_bounds,
				float(corridor["building_world_size_m"]),
				int(corridor["building_chunk_count"])
			):
				covered_sources[source] = true
	assert(covered_sources.size() == 24 * 24, "terrain remapping must cover the complete source grid")

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
