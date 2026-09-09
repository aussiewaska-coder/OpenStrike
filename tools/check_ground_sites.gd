extends SceneTree
## Read the already-cached corridor elevation and packaged buildings; no HTTP.
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var terrain = load("res://scripts/terrain/streamed_terrain.gd").new()
	var tiles = root.get_node("TileClient")
	var field: Dictionary = tiles._heightfield_from_buffer(FileAccess.get_file_as_bytes("user://map_cache/height_au_gold_coast_tweed_corridor_z12_r1025_s2.bin"), 1025)
	terrain._height_image = field.image
	terrain._metadata = {"world_size_m": 50000.0, "elevation_min_m": field.elevation_min_m, "elevation_max_m": field.elevation_max_m, "vertical_exaggeration": 1.8}
	terrain._bounds = load("res://scripts/terrain/map_tiles.gd").region_bounds(-28.08, 153.365, 50000.0)
	terrain._buildings_dir = "res://data/regions/au_gold_coast_tweed_corridor/buildings"
	terrain._building_world_size_m = 36000.0
	terrain._building_chunk_count = 24
	var targets = load("res://scripts/entities/launcher_field.gd").new()
	root.add_child(targets)
	targets.populate("au_gold_coast_tweed_corridor", terrain)
	for site in targets.launcher_positions():
		print("GROUND_SITE %s at %s" % [site.name, site.position])
	print("GROUND_SITES_TOTAL ", targets.launcher_count())
	var count: int = targets.launcher_count()
	targets.free()
	terrain.free()
	quit(0 if count == 6 else 1)
