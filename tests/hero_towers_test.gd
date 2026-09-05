extends SceneTree

## Heroes belong to Surfers and the enclosing corridor; suppression points come
## from the same coordinate conversion the terrain uses, and BuildingMesh hides
## an OSM box under a hero without hiding its neighbour.

const HEROES := preload("res://scripts/entities/hero_towers.gd")


func _init() -> void:
	if HEROES.layout_for("au_qld_surfers").size() != 3:
		_fail("Surfers has three hero towers")
	if not HEROES.layout_for("somewhere_else").is_empty():
		_fail("unrelated theatres must not have these heroes")
	for hero in HEROES.layout_for("au_qld_surfers"):
		for key in ["name", "lat", "lon", "scene", "yaw_degrees"]:
			if not hero.has(key):
				_fail("hero %s is missing %s" % [hero.get("name", "?"), key])

	# Suppression points go through whatever conversion the terrain supplies.
	var doubled := func(lat: float, lon: float) -> Vector2: return Vector2(lon * 2.0, lat * 2.0)
	var points: PackedVector2Array = HEROES.suppress_points("au_qld_surfers", doubled)
	if points.size() != 3:
		_fail("one suppression point per hero, got %d" % points.size())
	if not is_equal_approx(points[0].x, 153.4300 * 2.0):
		_fail("suppression points must use the supplied conversion")

	# The mesh builder hides a box under a hero and keeps the one next door.
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var pair := [
		{"x": 5.0, "z": 5.0, "height": 20.0, "osm_id": 1,
			"footprint": [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]]},
		{"x": 25.0, "z": 5.0, "height": 12.0, "osm_id": 2,
			"footprint": [[20.0, 0.0], [30.0, 0.0], [30.0, 10.0], [20.0, 10.0]]},
	]
	var suppressed: ArrayMesh = BuildingMesh.build(pair, flat, PackedVector2Array([Vector2(5.0, 5.0)]), 10.0)
	if suppressed == null:
		_fail("the neighbour must still produce a mesh")
	var box := suppressed.get_aabb()
	if not is_equal_approx(box.position.x, 20.0) or not is_equal_approx(box.size.x, 10.0):
		_fail("only the building under the hero is hidden, got x %f..%f" % [box.position.x, box.position.x + box.size.x])
	if BuildingMesh.build(pair, flat, PackedVector2Array([Vector2(5.0, 5.0), Vector2(25.0, 5.0)]), 10.0) != null:
		_fail("hiding every building must produce no mesh, not an empty one")
	if BuildingMesh.build(pair, flat).get_aabb().size.x != 30.0:
		_fail("no suppression points must change nothing")

	print("HERO_TOWERS_TEST_PASS")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
