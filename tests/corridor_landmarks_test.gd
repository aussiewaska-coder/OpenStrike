extends SceneTree
const HEROES := preload("res://scripts/entities/hero_towers.gd")
const TILES := preload("res://scripts/terrain/map_tiles.gd")
class Terrain:
	extends Node
	var bounds: Dictionary
	var span := 50000.0
	func world_from_coordinate(lat: float, lon: float) -> Vector2:
		return TILES.world_of(bounds, lat, lon, span)
	func sample_mesh_height(_x: float, _z: float) -> float: return 17.0
func _init(): call_deferred("_run")
func _run():
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/regions/catalog.json"))
	var corridor: Dictionary = {}
	for region in catalog.regions:
		if region.id == "au_gold_coast_tweed_corridor": corridor = region
	var terrain := Terrain.new()
	terrain.span = float(corridor.world_size_m)
	terrain.bounds = TILES.region_bounds(corridor.center_latitude, corridor.center_longitude, terrain.span)
	root.add_child(terrain)
	var towers := HEROES.new()
	root.add_child(towers)
	towers.populate(corridor.id, terrain)
	if towers.hero_count() != 3:
		push_error("Default 50 km corridor is missing Q1, Soul and Ocean: spawned %d towers" % towers.hero_count())
		towers.free()
		terrain.free()
		quit(1)
		return
	var points := HEROES.suppress_points(corridor.id, terrain.world_from_coordinate)
	assert(points.size() == 3, "OSM suppression must follow the same corridor landmarks")
	for i in range(towers._instances.size()):
		var model: Node3D = towers._instances[i]
		assert(model.visible and model.global_position.y == 17.0, "real models must be visible and grounded")
		assert(Vector2(model.position.x, model.position.z).distance_to(points[i]) < 0.01, "visual and suppression coordinates must coincide")
		assert(absf(model.position.x) < terrain.span * 0.5 and absf(model.position.z) < terrain.span * 0.5)
		assert(not model.find_children("*", "MeshInstance3D", true, false).is_empty(), "landmark must contain its real geometry")
	assert(towers.get_node_or_null("Hero_Q1") != null and towers.get_node_or_null("Hero_Soul") != null)
	towers.populate("au_qld_burleigh", terrain)
	assert(towers.hero_count() == 0, "switching to an unrelated theatre removes the models")
	await process_frame
	assert(towers.get_child_count() == 0, "old landmarks must not leak across theatre changes")
	towers.free()
	terrain.free()
	print("CORRIDOR_LANDMARKS_TEST_PASS")
	quit()
