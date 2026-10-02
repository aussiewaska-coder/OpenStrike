extends SceneTree
## Locks down the theatre's region lattice: that it covers the ground with no
## gaps and no slivers, that neighbours agree about the boundary they share, and
## that the districts the game already names fall inside the region they are
## named for. Nothing here is about who owns what -- that is
## tests/war_control_test.gd's business.

const MAP_TILES := preload("res://scripts/terrain/map_tiles.gd")
const PLACES := preload("res://scripts/ui/map_places.gd")
const WAR_REGIONS := preload("res://scripts/war/war_regions.gd")
const CATALOG_PATH := "res://data/regions/catalog.json"

const GOLD := "au_gold_coast_tweed_corridor"
const OWNERS := ["FRIENDLY", "ENEMY", "CONTESTED", "NEUTRAL"]

var _regions := WAR_REGIONS.new()
var _corridor := {}
var _bounds := {}
var _world_size := 50000.0


func _init() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null, "region catalog must be readable")
	var raw: Variant = JSON.parse_string(file.get_as_text())
	assert(raw is Dictionary, "region catalog must be a dictionary")
	for entry in ((raw as Dictionary)["regions"] as Array):
		var region: Dictionary = entry
		if String(region.get("id", "")) == GOLD:
			_corridor = region
			_world_size = float(region["world_size_m"])
			_bounds = MAP_TILES.region_bounds(
				float(region["center_latitude"]), float(region["center_longitude"]), _world_size)
	assert(not _corridor.is_empty(), "the Gold Coast corridor must be installed")

	assert(_regions.load_theatre(_corridor), "the corridor's regions must load")
	assert(_regions.is_loaded(), "and stay loaded")
	var list := _regions.regions()
	# The brief asks for roughly 15-40 meaningful regions, not a honeycomb.
	assert(list.size() >= 15 and list.size() <= 40,
		"the theatre must be divided into 15-40 regions, got %d" % list.size())
	assert(String(_regions.region("coolangatta")["name"]).contains("COOLANGATTA"),
		"a region must be readable by id")
	assert(_regions.region("nowhere").is_empty(), "an unknown region is no region")

	for region in list:
		_check_shape(region)
	_check_coverage(list)
	_check_adjacency(list)
	_check_places()
	_check_refusal_leaves_nothing(
		((raw as Dictionary)["regions"] as Array)[1] as Dictionary)
	print("WAR_REGIONS_TEST_PASS")
	quit()


## Refusing a theatre is not the same as keeping the one before it.
##
## The catalogue has exactly one district map in it, so every other theatre arrives here
## as a refusal -- and a refusal that left the corridor's lattice seated is how a campaign
## ends up fighting over ground the world no longer contains, because `WarDirector.setup`
## validates whatever tables it is handed and would happily seat the stale ones.
func _check_refusal_leaves_nothing(sydney: Dictionary) -> void:
	assert(_regions.is_loaded(), "the corridor must be seated before the refusal is tried")
	assert(not _regions.load_theatre(sydney),
		"a theatre with no authored regions must refuse rather than redraw Tweed Heads over Sydney")
	assert(not _regions.is_loaded(), "and a refusal must not leave the geography loaded")
	assert(_regions.regions().is_empty(), "with no districts of the old theatre still seated")
	assert(_regions.region("coolangatta").is_empty(), "which must not answer by id either")
	assert(_regions.region_at(Vector2.ZERO).is_empty(), "nor by position")
	assert(_regions.adjacency().is_empty(), "nor what touches a place nobody holds")
	assert(_regions.load_theatre(_corridor),
		"and the corridor must still load afterwards, a refusal being no injury")
	assert(_regions.regions().size() >= 15, "with the whole theatre back")


## One closed ring, inside the theatre, with a centre the region can actually
## report a bearing from.
func _check_shape(region: Dictionary) -> void:
	var id := String(region["id"])
	var polygon: PackedVector2Array = region["polygon"]
	var centre: Vector2 = region["centre"]
	# The lattice overshoots the theatre by a few metres so the edge cells cover
	# the last pixel of ground, which a strict box would call a fault.
	var limit := _world_size * 0.5 + 200.0
	assert(int(region["rings"]) == 1,
		"%s must be one contiguous district, got %d pieces" % [id, int(region["rings"])])
	assert(polygon.size() >= 5, "%s must have a real outline, got %d points" % [id, polygon.size()])
	assert(polygon[0] == polygon[polygon.size() - 1], "%s outline must close" % id)
	for point in polygon:
		assert(point.x == point.x and point.y == point.y, "%s outline must be finite" % id)
		assert(absf(point.x) <= limit and absf(point.y) <= limit,
			"%s outline must stay inside the theatre" % id)
	assert(WAR_REGIONS._contains(polygon, centre), "%s must report a centre inside itself" % id)
	assert(String(region["owner"]) in OWNERS, "%s owner must be one of four" % id)
	assert(float(region["value"]) >= 0.0 and float(region["value"]) <= 1.0,
		"%s strategic value must be a ratio" % id)


## The tessellation's whole point: no gap, and no double-covered ground either.
func _check_coverage(list: Array) -> void:
	var steps := 41
	var unclaimed := 0
	var overlaps := 0
	var step := _world_size / float(steps + 1)
	for i in range(steps):
		for j in range(steps):
			# Between the lattice lines rather than on them: a sample sitting
			# exactly on a shared edge belongs to whichever side the crossing
			# rule favours, which proves nothing about the tessellation.
			var u := -_world_size * 0.5 + (float(i) + 0.6) * step
			var v := -_world_size * 0.5 + (float(j) + 0.6) * step
			var hits := 0
			for region in list:
				if WAR_REGIONS._contains(region["polygon"] as PackedVector2Array, Vector2(u, v)):
					hits += 1
			if hits == 0:
				unclaimed += 1
			elif hits > 1:
				overlaps += 1
	assert(unclaimed == 0, "every part of the theatre must belong to a region, %d samples were not" % unclaimed)
	assert(overlaps == 0, "no ground may belong to two regions, %d samples did" % overlaps)


## Neighbours must agree about the boundary they share, because the front line is
## assembled out of those shared segments rather than drawn twice by hand.
func _check_adjacency(list: Array) -> void:
	var table := _regions.adjacency()
	var friendly_to_enemy := 0
	var friendly_to_contested := 0
	var contested_to_enemy := 0
	for region in list:
		var id := String(region["id"])
		var outline: PackedVector2Array = region["polygon"]
		assert(table.has(id), "%s must know its neighbours" % id)
		var neighbours: Dictionary = table.get(id, {})
		for other in neighbours:
			var mine: Array = neighbours[other]
			assert(not mine.is_empty(), "%s/%s must share at least one edge" % [id, other])
			assert(table.has(other) and (table[other] as Dictionary).has(id),
				"adjacency must be mutual: %s names %s" % [id, other])
			var theirs: Array = (table[other] as Dictionary)[id]
			assert(theirs.size() == mine.size(),
				"%s and %s must agree on how many edges they share, %d vs %d" % [
					id, other, mine.size(), theirs.size()])
			var there_outline: PackedVector2Array = _regions.region(String(other))["polygon"]
			for segment in mine:
				for endpoint in segment:
					# The two outlines must pass through the same point, not two
					# points that look alike: this is what lets the front line be
					# one stroke instead of two drawn near each other.
					assert(_is_vertex(outline, endpoint),
						"%s outline must pass through its edge to %s" % [id, other])
					assert(_is_vertex(there_outline, endpoint),
						"%s outline must pass through its edge to %s" % [other, id])
			var pair := [String(region["owner"]), String(_regions.region(String(other))["owner"])]
			pair.sort()
			if pair == ["ENEMY", "FRIENDLY"]:
				friendly_to_enemy += mine.size()
			elif pair == ["CONTESTED", "FRIENDLY"]:
				friendly_to_contested += mine.size()
			elif pair == ["CONTESTED", "ENEMY"]:
				contested_to_enemy += mine.size()
	# The front the territory layer draws has to exist before it can be drawn.
	assert(friendly_to_enemy > 0, "the two sides must actually touch somewhere")
	assert(friendly_to_contested > 0 and contested_to_enemy > 0,
		"a contested belt must sit between the blocs, got %d and %d shared edges" % [
			friendly_to_contested, contested_to_enemy])


func _is_vertex(polygon: PackedVector2Array, point: Vector2) -> bool:
	for vertex in polygon:
		if vertex.distance_squared_to(point) < 0.01:
			return true
	return false


## The gazetteer is the only geography the project treats as fact, so the
## districts are checked against it: a town must be inside the region named for
## it, or the map is lying about where the fight is.
func _check_places() -> void:
	var checked := 0
	for entry in (PLACES.PLACES as Array):
		var place: Dictionary = entry
		var at: Vector2 = MAP_TILES.world_of(
			_bounds, float(place["lat"]), float(place["lon"]), _world_size)
		if absf(at.x) > _world_size * 0.5 or absf(at.y) > _world_size * 0.5:
			continue
		var wanted := String(place["name"]).get_slice(" ", 0).to_lower()
		var hit: Dictionary = _regions.region_at(at)
		assert(not hit.is_empty(), "%s must be inside a region" % place["name"])
		var id := String(hit["id"])
		assert(id == wanted or String(hit["name"]).to_lower().contains(wanted),
			"%s must fall in the district it is named for, got %s" % [place["name"], id])
		checked += 1
	assert(checked >= 6, "the corridor must have at least six towns to check against, got %d" % checked)
