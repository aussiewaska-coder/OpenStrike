extends SceneTree
const FIELD := preload("res://scripts/entities/launcher_field.gd")
const LAYOUT := preload("res://scripts/entities/launcher_layout.gd")
class Terrain extends Node:
	var water := false
	var obstructed := false
	func world_half_extent() -> float: return 4000.0
	func sample_mesh_height(_x: float, _z: float) -> float: return 0.0 if water else 15.0
	func ground_site_obstacles(bounds: Rect2) -> Array:
		return [bounds] if obstructed else []
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var terrain := Terrain.new()
	root.add_child(terrain)
	var field := FIELD.new()
	root.add_child(field)
	for region in ["au_qld_surfers", "au_qld_burleigh", "au_nsw_tweed", "au_qld_tamborine"]:
		field.populate(region, terrain)
		var names := {}
		for target in field.launcher_positions():
			var cluster: String = target.name.substr(0, target.name.length() - 2)
			names[cluster] = int(names.get(cluster, 0)) + 1
			check(absf(target.position.x) < 4000 and absf(target.position.z) < 4000, "sites stay inside the theatre")
			check(target.position.y >= 15, "target bounds sit above the sampled terrain")
		check(names.size() == 6, "each theatre has city and hinterland clusters")
		for count in names.values():
			check(count == 4, "clusters contain four independently targetable sites")
		check(field.hit_index.entity_count() == 24, "repopulation must replace old collision entries")
	var coords := []
	var clusters := LAYOUT.clusters_for("au_gold_coast_tweed_corridor", 25000.0, func(lat, lon):
		coords.append(Vector2(lat, lon))
		return Vector2((lon - 153.365) * 98000.0, (-28.08 - lat) * 111000.0)
	)
	check(coords.size() == 6 and clusters.size() == 6, "the large corridor places groups using real coordinate conversion")
	for cluster in clusters:
		check(absf(cluster.centre.x) < 24000 and absf(cluster.centre.y) < 24000, "corridor groups fit within the 50 km map")
	terrain.water = true
	field.populate("au_qld_surfers", terrain)
	check(field.launcher_count() == 0, "a patch with no dry sites must not put launchers in the sea")
	terrain.water = false
	terrain.obstructed = true
	field.populate("au_qld_surfers", terrain)
	check(field.launcher_count() == 0, "packaged building footprints must block sites before visual chunks stream in")
	field.free()
	terrain.free()
	if not failed:
		print("GROUND_CLUSTER_TEST_PASS")
	quit(1 if failed else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
