extends SceneTree

const LOCATION_SERVICE := preload("res://scripts/location/location_service.gd")
const CATALOG_PATH := "res://data/regions/catalog.json"


func _init() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null, "region catalog must be readable")
	var catalog: Dictionary = JSON.parse_string(file.get_as_text())
	var service := LOCATION_SERVICE.new()
	service._regions = catalog["regions"]
	service._select_region(service.DEMO_LATITUDE, service.DEMO_LONGITUDE, true)
	assert(
		String(service.selected_region.get("id", "")) == "au_gold_coast_tweed_corridor",
		"Gold Coast launch must select the requested 50 km theatre, not nested 12 km Surfers"
	)
	assert(float(service.selected_region.get("world_size_m", 0.0)) == 50000.0)
	service._select_region(-28.1739, 153.545, false)
	assert(
		String(service.selected_region.get("id", "")) == "au_gold_coast_tweed_corridor",
		"nested Tweed coordinates must remain in the default 50 km theatre"
	)
	service.select_region_by_id("au_qld_surfers")
	assert(
		float(service.selected_region.get("world_size_m", 0.0)) == 12000.0,
		"small theatres must remain available by explicit settings selection"
	)
	service.free()
	print("LOCATION_SELECTION_TEST_PASS")
	quit()
