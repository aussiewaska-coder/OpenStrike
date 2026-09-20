extends SceneTree

const LOCATION_SERVICE := preload("res://scripts/location/location_service.gd")
const CATALOG_PATH := "res://data/regions/catalog.json"


func _init() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null, "region catalog must be readable")
	var catalog: Dictionary = JSON.parse_string(file.get_as_text())
	assert(catalog["regions"].size() == 1, "only the default theatre ships")
	var service := LOCATION_SERVICE.new()
	service._regions = catalog["regions"]
	service._select_region(service.DEMO_LATITUDE, service.DEMO_LONGITUDE, true)
	assert(
		String(service.selected_region.get("id", "")) == "au_gold_coast_tweed_corridor",
		"Gold Coast launch must select the default 50 km theatre"
	)
	assert(float(service.selected_region.get("world_size_m", 0.0)) == 50000.0)
	service._select_region(-28.1739, 153.545, false)
	assert(
		String(service.selected_region.get("id", "")) == "au_gold_coast_tweed_corridor",
		"Tweed coordinates must remain in the default 50 km theatre"
	)
	service.select_region_by_id("au_qld_surfers")
	assert(
		String(service.selected_region.get("id", "")) == "au_gold_coast_tweed_corridor",
		"retired theatre ids must not change the selection"
	)
	service.cycle_region()
	assert(
		String(service.selected_region.get("id", "")) == "au_gold_coast_tweed_corridor",
		"cycling a single-theatre catalog must stay on the default"
	)
	service.free()
	print("LOCATION_SELECTION_TEST_PASS")
	quit()
