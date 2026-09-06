class_name HeroTowers
extends Node3D

## The three towers that carry the skyline's identity, as real models rather
## than extruded boxes: Q1, Soul and Ocean, from openstrike_facade_kit_v3.
##
## Placed once per region at their real coordinates, on the sampled ground.
## Each one's OSM box is suppressed VISUALLY ONLY -- BuildingMesh skips it --
## while BuildingHitIndex keeps the footprint, so a round still strikes Q1
## where Q1 actually is. The GLBs carry no collision and need none.
##
## Mirrors launcher_field.gd: a pure layout, a populate, a clear.

const SURFERS_REGION := "au_qld_surfers"

## How close an OSM building's centre must be to a hero to be hidden. Q1's
## own record sits at its footprint centre, and the next building's centre is
## well over forty metres from a tower that size; tighter and Q1's box shows
## through the model, looser and a neighbour vanishes.
const SUPPRESS_RADIUS_M := 40.0

var _instances: Array[Node3D] = []


## Latitude, longitude, model, and a yaw. Coordinates and heights are the kit's
## README; the GLBs are true scale, Y-up and grounded at y = 0, so they are
## placed and not scaled.
static func layout_for(region_id: String) -> Array:
	if region_id != SURFERS_REGION:
		return []
	return [
		{"name": "Q1", "lat": -28.0067, "lon": 153.4300, "scene": "res://assets/models/q1_tower.glb", "yaw_degrees": 0.0},
		# Soul's sail crown crests over one corner and the README says to turn
		# it so the peak faces the ocean, which is +X here. Which corner the
		# model puts the peak on is a device check; start square.
		{"name": "Soul", "lat": -28.00117, "lon": 153.43049, "scene": "res://assets/models/soul_tower.glb", "yaw_degrees": 0.0},
		{"name": "Ocean", "lat": -27.9961, "lon": 153.4297, "scene": "res://assets/models/ocean_tower.glb", "yaw_degrees": 0.0},
	]


## World XZ of every hero in this region, for BuildingMesh to suppress. Pure so
## the terrain can compute it the moment its bounds exist, before any building
## chunk builds.
static func suppress_points(region_id: String, world_of: Callable) -> PackedVector2Array:
	var points := PackedVector2Array()
	for hero in layout_for(region_id):
		points.append(world_of.call(float(hero["lat"]), float(hero["lon"])))
	return points


func populate(region_id: String, terrain: Node) -> void:
	clear()
	if terrain == null or not terrain.has_method("world_from_coordinate"):
		return
	for hero in layout_for(region_id):
		var scene: PackedScene = load(String(hero["scene"]))
		if scene == null:
			push_warning("Hero tower model missing: %s" % hero["scene"])
			continue
		var at: Vector2 = terrain.world_from_coordinate(float(hero["lat"]), float(hero["lon"]))
		var ground := 0.0
		if terrain.has_method("sample_mesh_height"):
			ground = float(terrain.sample_mesh_height(at.x, at.y))
		var model: Node3D = scene.instantiate()
		model.name = "Hero_%s" % hero["name"]
		add_child(model)
		model.global_position = Vector3(at.x, ground, at.y)
		model.rotation_degrees.y = float(hero["yaw_degrees"])
		_instances.append(model)


func clear() -> void:
	for model in _instances:
		if is_instance_valid(model):
			model.queue_free()
	_instances.clear()


func hero_count() -> int:
	return _instances.size()
