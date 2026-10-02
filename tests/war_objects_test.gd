extends SceneTree

## Phase 4's registry, headless. The brief's rule is that a strategic object has to
## correspond to an actual place, and that where the game already has an entity for
## the thing the map must not invent a second one -- so this test asks nothing about
## whether the table looks like a campaign order of battle and everything about
## whether each row can be traced back to a source that exists for its own sake. The
## airfield is the airport the runway table publishes, the site is a position the
## launcher layout lays out, the tower is the model the terrain places, and a live
## launcher's own entity id is the only handle a site has.

const OBJECTS := preload("res://scripts/war/war_objects.gd")
const REGIONS := preload("res://scripts/war/war_regions.gd")
const CONTROL := preload("res://scripts/war/war_control.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")
const DAMAGE := preload("res://scripts/world/building_damage_system.gd")
const RUNWAYS := preload("res://scripts/world/runways.gd")
const SITES := preload("res://scripts/entities/launcher_layout.gd")
const HEROES := preload("res://scripts/entities/hero_towers.gd")
const MAP_TILES := preload("res://scripts/terrain/map_tiles.gd")
const CATALOG_PATH := "res://data/regions/catalog.json"

const CORRIDOR := "au_gold_coast_tweed_corridor"
const SYDNEY := "au_nsw_sydney_harbour"
## Launcher entity ids, as the field hands them out from 1. The world counts its
## launchers from 1, its drones from 100 000 and its enemy jets from 200 000, so a
## strategic id starting at 300 000 is above all three -- which matters because the
## card offers a tracker handle for a site that has one, and an id that could be
## mistaken for an entity would let a tap lock something that was never fired at.
const LAUNCHER_A := 1
const LAUNCHER_B := 2
const DRONE_FIRST := 100000

var failed := false


## The streaming collision answer, for the footprints whose chunk has arrived. It
## records where the registry pointed each ray, so the test can see the question as
## well as the answer.
class GroundIndex:
	extends RefCounted

	var footprints := {}
	var responder: Callable
	var asked := []

	static func key_of(at: Vector2) -> String:
		return "%0.0f,%0.0f" % [at.x, at.y]

	func query_segment(from: Vector3, _to: Vector3) -> RefCounted:
		asked.append(from)
		return responder.call(int(footprints.get(GroundIndex.key_of(Vector2(from.x, from.z)), -1)))


## A round, as far as the damage system cares: it only reads `damage_profile`.
class Round:
	extends RefCounted
	var damage_profile: Resource = null


class Profile:
	extends Resource
	var structural_damage := 0.0


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var corridor := _region(CORRIDOR)
	var geography := REGIONS.new()
	check(geography.load_theatre(corridor), "the corridor must still divide into districts")
	var control := CONTROL.new()
	control.setup(geography)
	var registry := OBJECTS.new()
	check(
		registry.load_theatre(corridor, geography, control),
		"a corridor with runways, sites and towers in it has objects")
	_check_every_row_is_a_real_place(registry, corridor)
	_check_the_fields_the_brief_asks_for(registry, corridor, geography, control)
	_check_a_site_reports_the_launchers_it_has(registry)
	_check_a_site_that_stops_reporting(registry)
	_check_a_tower_reports_what_is_left_of_it(registry)
	_check_the_lives_of_a_theatre_with_no_districts()
	_check_a_theatre_nothing_can_be_said_about()
	if not failed:
		print("WAR_OBJECTS_TEST_PASS")
	quit(1 if failed else 0)


func _region(id: String) -> Dictionary:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	check(file != null, "the catalog has to be readable to have a theatre")
	if file == null:
		return {}
	for entry in (((JSON.parse_string(file.get_as_text()) as Dictionary)["regions"]) as Array):
		if String(entry.get("id", "")) == id:
			return entry
	return {}


func _bounds(region: Dictionary) -> Dictionary:
	return MAP_TILES.region_bounds(
		float(region["center_latitude"]),
		float(region["center_longitude"]),
		float(region.get("world_size_m", 50000.0)))


## The same projection the registry builds itself with, so a source's ground position
## can be worked out here and compared rather than copied.
func _places(region: Dictionary) -> Callable:
	var bounds: Dictionary = _bounds(region)
	var size := float(region.get("world_size_m", 50000.0))
	return func(latitude: float, longitude: float) -> Vector2:
		return MAP_TILES.world_of(bounds, latitude, longitude, size)


func _launcher(site: String, entity_id: int) -> Dictionary:
	return {"id": entity_id, "position": Vector3.ZERO, "name": "%s 1" % site}


func _of(registry: OBJECTS, type: int) -> Array:
	return registry.of_type(type)


func _named(rows: Array, name: String) -> Dictionary:
	for row in rows:
		if String(row["name"]) == name:
			return row
	return {}


func _site(registry: OBJECTS, name: String) -> Dictionary:
	for object in _of(registry, OBJECTS.Type.SAM_SITE):
		if String(object["detail"]["site"]) == name:
			return object
	return {}


## The whole acceptance for a table of places: every row's position is the position its
## own source gives it, and a row whose source cannot be found is a row that has to stay
## out of the table.
func _check_every_row_is_a_real_place(registry: OBJECTS, corridor: Dictionary) -> void:
	var airbases: Array = _of(registry, OBJECTS.Type.AIRBASE)
	var sites: Array = _of(registry, OBJECTS.Type.SAM_SITE)
	var towers: Array = _of(registry, OBJECTS.Type.INFRASTRUCTURE)
	var authored_sites: Array = SITES.clusters_for(CORRIDOR, 25000.0, _places(corridor))
	var skyline: Array = HEROES.layout_for(CORRIDOR)
	check(airbases.size() == 1, "one aerodrome in this corridor means one airbase, got %d" % airbases.size())
	check(
		sites.size() == authored_sites.size(),
		"every site the launcher field lays out is on the map, got %d of %d" % [sites.size(), authored_sites.size()])
	check(
		towers.size() == skyline.size(),
		"and every landmark the terrain models is on it, got %d of %d" % [towers.size(), skyline.size()])
	for type in [
		OBJECTS.Type.RADAR, OBJECTS.Type.FORWARD_BASE, OBJECTS.Type.COMMAND_POST,
		OBJECTS.Type.SUPPLY_DEPOT, OBJECTS.Type.GROUND_FORCE, OBJECTS.Type.AIRCRAFT_GROUP,
	]:
		check(
			_of(registry, type).is_empty(),
			"nothing in this world is a %s yet, so nothing may be listed as one" % OBJECTS.TYPE_NAME[type])
	var airbase: Dictionary = airbases[0]
	check(
		is_equal_approx(float(airbase["latitude"]), RUNWAYS.COOLANGATTA_ARP_LAT)
		and is_equal_approx(float(airbase["longitude"]), RUNWAYS.COOLANGATTA_ARP_LON),
		"the airfield sits at the airport reference point the runway table publishes")
	check(String(airbase["detail"]["icao"]) == "OOL", "and it is the airport that pavement is authored for")
	var strips: Array = airbase["detail"]["strips"]
	var authored_strips: Array = RUNWAYS.for_region(CORRIDOR)
	check(
		strips.size() == authored_strips.size(),
		"one drawn strip per authored runway, got %d of %d" % [strips.size(), authored_strips.size()])
	var strip: Dictionary = strips[0]
	var authored: Dictionary = authored_strips[0]
	check(
		is_equal_approx(float(strip["length_m"]), float(authored["length_m"])),
		"a strip on the map is as long as the runway the aircraft rolls down, got %.0f m" % float(strip["length_m"]))
	var a: Vector2 = strip["a"]
	var b: Vector2 = strip["b"]
	check(
		absf(a.distance_to(b) - float(authored["length_m"])) < float(authored["length_m"]) * 0.02,
		"and its ends really are that strip's length apart, got %.0f m" % a.distance_to(b))
	var threshold_latlon: Vector2 = RUNWAYS.threshold_latlon(authored)
	var threshold: Vector2 = _places(corridor).call(threshold_latlon.x, threshold_latlon.y)
	check(
		a.distance_to(threshold) < 2.0,
		"one end is the threshold the game lines up on, %.0f m out" % a.distance_to(threshold))
	var laid := {}
	for record in authored_sites:
		laid[String(record["name"])] = record["centre"]
	for record in sites:
		var site: Dictionary = record
		var named := String(site["detail"]["site"])
		check(laid.has(named), "%s is a site the field itself lays out" % named)
		check(
			(site["world_position"] as Vector2).distance_to(laid.get(named, Vector2.INF)) < 0.001,
			"and it stands where the layout puts it, not where the map guessed")
		check(String(site["faction"]) == OBJECTS.ENEMY, "a hostile launcher site is the enemy's, whatever the districts say")
		check(
			(site["handles"] as Array).is_empty(),
			"a site is not assumed to have launchers in it before something reports them")
	for hero in skyline:
		var tower := _named(towers, String(hero["name"]))
		check(not tower.is_empty(), "%s is on the map because it is in the skyline" % String(hero["name"]))
		if tower.is_empty():
			continue
		check(
			is_equal_approx(float(tower["latitude"]), float(hero["lat"]))
			and is_equal_approx(float(tower["longitude"]), float(hero["lon"])),
			"and at the coordinate its model is placed from")


## The fields the brief insists every object carries, and the two arithmetic rules that
## hold them together: a position and its reported coordinate have to be the same place,
## and an id has to be nobody else's.
func _check_the_fields_the_brief_asks_for(registry: OBJECTS, corridor: Dictionary, geography: REGIONS, control: CONTROL) -> void:
	var seen := {}
	for object in registry.objects():
		var id := int(object["id"])
		var name := String(object["name"])
		check(id >= OBJECTS.FIRST_ID, "a strategic id sits above every entity band the world hands out, got %d" % id)
		check(not seen.has(id), "and no id is handed out twice, %d is" % id)
		seen[id] = true
		for field in [
			"id", "type", "faction", "world_position", "latitude", "longitude", "region_id",
			"health", "operational_state", "strategic_value", "discovered", "intel_confidence",
		]:
			check(object.has(field), "%s is missing the field %s" % [name, field])
		var at: Vector2 = object["world_position"]
		check(at.is_finite(), "%s stands somewhere" % name)
		var again: Vector2 = _places(corridor).call(float(object["latitude"]), float(object["longitude"]))
		check(
			again.distance_to(at) < 1.0,
			"%s reports the coordinate its own ground position unwinds to, got %.0f m of drift" % [name, again.distance_to(at)])
		check(not registry.of(id).is_empty(), "%s reads back through its own id" % name)
		var state := String(object["operational_state"])
		check(
			state in [OBJECTS.INTACT, OBJECTS.DAMAGED, OBJECTS.DESTROYED, OBJECTS.UNCONFIRMED],
			"%s is in a state the registry can reach, got %s" % [name, state])
		check(float(object["health"]) >= 0.0 and float(object["health"]) <= 1.0, "%s has health as a fraction" % name)
		var value := float(object["strategic_value"])
		var weight := float(OBJECTS.WEIGHT[int(object["type"])])
		check(
			value > 0.0 and value <= weight + 0.001 and value >= weight * 0.4,
			"%s is worth its type's weight, settled by its district: %.2f against %.2f" % [name, value, weight])
		var district := String(object["region_id"])
		var intel := float(object["intel_confidence"])
		var authored := 0.0
		if not district.is_empty():
			authored = float(control.state_of(district)["intel_level"])
		check(
			is_equal_approx(intel, authored),
			"%s's confidence is the intel its district reports, got %.2f against %.2f" % [name, intel, authored])
		check(not String(object["source"]).is_empty(), "and every row says where it came from")
		var where: Dictionary = geography.region_at(at)
		check(
			district == String(where.get("id", "")),
			"%s is registered in %s, which is the district its own ground position falls in, not %s" % [
				name, district, String(where.get("id", "nothing"))])


## A site with something standing at it is the same SAM the tracker already has, under
## the same entity id -- which is the difference between a strategic layer and a second
## set of targets.
func _check_a_site_reports_the_launchers_it_has(registry: OBJECTS) -> void:
	registry.bind_launchers([_launcher("CITY NORTH", LAUNCHER_A), _launcher("CITY CENTRAL", LAUNCHER_B)])
	var north := _site(registry, "CITY NORTH")
	check(not north.is_empty(), "the site that was reported is in the table")
	check(north["handles"] == [LAUNCHER_A], "the site carries the launcher's own id, got %s" % [north["handles"]])
	check(bool(north["discovered"]), "something is seen there")
	check(String(north["operational_state"]) == OBJECTS.INTACT, "with everything the layout planned, intact")
	check(is_equal_approx(float(north["health"]), 1.0), "at full strength")
	check(is_equal_approx(float(north["intel_confidence"]), 1.0), "a launcher reporting in is not an estimate")
	check(_site(registry, "CITY CENTRAL")["handles"] == [LAUNCHER_B], "so is the second site")
	var hinterland := _site(registry, "HINTERLAND NORTH")
	check(
		String(hinterland["operational_state"]) == OBJECTS.UNCONFIRMED,
		"a site nothing has reported is an unconfirmed position, got %s" % String(hinterland["operational_state"]))
	check(not bool(hinterland["discovered"]), "and it has not been discovered")
	check(float(hinterland["intel_confidence"]) < 1.0, "and its confidence stays wherever the district put it")
	registry.bind_launchers([_launcher("CITY NORTH", LAUNCHER_A), _launcher("CITY NORTH", 3)])
	north = _site(registry, "CITY NORTH")
	check(north["handles"] == [LAUNCHER_A, 3], "two launchers at one site are both carried, got %s" % [north["handles"]])
	check(
		not (north["handles"] as Array).has(int(north["id"])),
		"and a site's own id is never one of its launchers' handles")
	check(String(north["operational_state"]) == OBJECTS.INTACT, "more than the layout planned is still standing")
	check(is_equal_approx(float(north["health"]), 1.0), "and reports nothing lost of itself")


func _check_a_site_that_stops_reporting(registry: OBJECTS) -> void:
	check((_site(registry, "CITY NORTH")["handles"] as Array).size() == 2, "the site comes into this test with two launchers")
	registry.bind_launchers([_launcher("CITY NORTH", LAUNCHER_A)])
	var wounded := _site(registry, "CITY NORTH")
	check(String(wounded["operational_state"]) == OBJECTS.DAMAGED, "one launcher left of two is a damaged site")
	check(is_equal_approx(float(wounded["health"]), 0.5), "and it says how much of itself is left, got %.2f" % float(wounded["health"]))
	check(wounded["handles"] == [LAUNCHER_A], "and only the launcher that is still there")
	registry.bind_launchers([])
	var gone := _site(registry, "CITY NORTH")
	check(String(gone["operational_state"]) == OBJECTS.DESTROYED, "nothing at a site that had something is a destroyed site")
	check(is_equal_approx(float(gone["health"]), 0.0), "with nothing of it to report")
	check(bool(gone["discovered"]), "and it is still the place that was seen, so the map keeps drawing it")
	check((gone["handles"] as Array).is_empty(), "and it has no live track to hand a weapon")
	registry.bind_launchers([_launcher("SOME OTHER SITE", 40)])
	check(
		(_site(registry, "CITY NORTH")["handles"] as Array).is_empty(),
		"a launcher named for some other site is not this site's")


## The streaming question, put to a collision index that answers for two of the three
## footprints, with the damage written through the system the cannon already uses so the
## thresholds are the world's own and not this test's.
func _check_a_tower_reports_what_is_left_of_it(registry: OBJECTS) -> void:
	var skyline: Array = HEROES.layout_for(CORRIDOR)
	check(skyline.size() >= 3, "the corridor has three landmarks to try this on, got %d" % skyline.size())
	var index := GroundIndex.new()
	index.responder = Callable(self, "_answer_for")
	var damage := DAMAGE.new()
	var towers := {}
	for step in range(skyline.size()):
		var name := String(skyline[step]["name"])
		towers[name] = _named(_of(registry, OBJECTS.Type.INFRASTRUCTURE), name)
		if step < 2:
			index.footprints[index.key_of(towers[name]["world_position"])] = 9000 + step
	registry.bind_structures(index, damage)
	check(index.asked.size() == skyline.size(), "one ray per landmark per bind, got %d" % index.asked.size())
	var ray: Vector3 = index.asked[0]
	check(is_equal_approx(ray.y, OBJECTS.RAY_TOP_M), "fired from above anything the model kit builds")
	var first: Dictionary = towers[String(skyline[0]["name"])]
	check(
		is_equal_approx(ray.x, (first["world_position"] as Vector2).x)
		and is_equal_approx(ray.z, (first["world_position"] as Vector2).y),
		"and straight down at the ground the landmark is drawn on")
	check(int(first["detail"]["building_id"]) == 9000, "a footprint that has streamed is the OSM id it really has")
	check(bool(first["detail"]["streamed"]), "and the card may say it is standing there")
	check(String(first["operational_state"]) == OBJECTS.INTACT, "with nothing fired at it, undamaged")
	var unstreamed: Dictionary = towers[String(skyline[2]["name"])]
	check(int(unstreamed["detail"]["building_id"]) == -1, "a chunk that has not arrived answers with no building")
	check(not bool(unstreamed["detail"]["streamed"]), "and reports the footprint unloaded instead of a confident reading")
	check(String(unstreamed["operational_state"]) == OBJECTS.INTACT, "still authored, still standing as far as anyone knows")
	check(is_equal_approx(float(unstreamed["health"]), 1.0), "with no damage claimed for it")
	check(is_equal_approx(float(unstreamed["detail"]["damage"]), 0.0), "and no damage figure either")
	damage.apply_hit(_hit(9000), _round(DAMAGE.SMOKE_THRESHOLD * 2.0))
	damage.apply_hit(_hit(9001), _round(DAMAGE.SMOKE_THRESHOLD * 0.5))
	registry.bind_structures(index, damage)
	var felled: Dictionary = towers[String(skyline[0]["name"])]
	check(
		String(felled["operational_state"]) == OBJECTS.DESTROYED,
		"twice the smoke point is nothing left standing, got %s" % String(felled["operational_state"]))
	check(float(felled["health"]) <= OBJECTS.STRUCTURE_STANDING, "and its health says so, got %.2f" % float(felled["health"]))
	var scorched: Dictionary = towers[String(skyline[1]["name"])]
	check(
		String(scorched["operational_state"]) == OBJECTS.DAMAGED,
		"half the smoke point is damaged rather than destroyed, got %s" % String(scorched["operational_state"]))
	check(float(scorched["health"]) > OBJECTS.STRUCTURE_STANDING, "and still most of itself")
	check(int(scorched["detail"]["building_id"]) == 9001, "the second landmark kept its own footprint")
	check(float(scorched["detail"]["damage"]) > 0.0, "and reports what it has taken")
	felled["health"] = 0.5
	check(is_equal_approx(float(registry.of(int(felled["id"]))["health"]), 0.5), "a card holds the live row, not a copy of it")


func _hit(building_id: int) -> RefCounted:
	var hit := HIT.new()
	hit.hit = true
	hit.object_type = HIT.ObjectKind.BUILDING
	hit.building_id = building_id
	return hit


func _round(amount: float) -> RefCounted:
	var profile := Profile.new()
	profile.structural_damage = amount
	var round_data := Round.new()
	round_data.damage_profile = profile
	return round_data


func _answer_for(building_id: int) -> RefCounted:
	return HIT.miss() if building_id < 0 else _hit(building_id)


## Sydney has no authored districts yet. The places there are just as real, so the
## honest report is objects with no district rather than objects handed one.
func _check_the_lives_of_a_theatre_with_no_districts() -> void:
	var sydney := _region(SYDNEY)
	var registry := OBJECTS.new()
	check(
		registry.load_theatre(sydney, null, null),
		"Sydney has airfields, sites and landmarks without anyone owning its ground")
	var towers: Array = _of(registry, OBJECTS.Type.INFRASTRUCTURE)
	check(towers.size() == HEROES.layout_for(SYDNEY).size(), "and its own skyline, got %d" % towers.size())
	for object in registry.objects():
		var name := String(object["name"])
		check(String(object["region_id"]).is_empty(), "%s is in a theatre with no districts and must not be given one" % name)
		check(
			is_equal_approx(float(object["intel_confidence"]), 0.0),
			"and nothing is watched there, got %.2f" % float(object["intel_confidence"]))
		check(
			float(object["strategic_value"]) > 0.0,
			"ground nobody has rated is not worthless, %s reports %.2f" % [name, float(object["strategic_value"])])
	for tower in towers:
		check(
			String(tower["faction"]) == OBJECTS.NEUTRAL,
			"a tower's faction is the ground under it, and unauthored ground claims nothing")
	var airbase: Dictionary = _of(registry, OBJECTS.Type.AIRBASE)[0]
	check(String(airbase["detail"]["icao"]) == "YSSY", "the airfield there is the one the runway table knows")
	var strips: Array = airbase["detail"]["strips"]
	check(
		strips.size() == RUNWAYS.for_region(SYDNEY).size(),
		"with every one of its pavements drawn, got %d" % strips.size())
	var longest := 0.0
	for strip in strips:
		longest = maxf(longest, float(strip["length_m"]))
	check(is_equal_approx(longest, float(airbase["detail"]["longest_m"])), "and the figure the card prints is the longest of them")
	registry.bind_launchers([_launcher("CITY NORTH", LAUNCHER_A)])
	check(
		String(_site(registry, "CITY NORTH")["operational_state"]) == OBJECTS.INTACT,
		"a site reports what is standing at it even where no district owns the ground")


func _check_a_theatre_nothing_can_be_said_about() -> void:
	var registry := OBJECTS.new()
	check(not registry.load_theatre({}, null, null), "a region with no centre is not a theatre")
	check(not registry.is_loaded(), "and nothing can be asked of it")
	check(registry.objects().is_empty() and registry.count() == 0, "with no rows to draw")
	check(registry.of(OBJECTS.FIRST_ID).is_empty(), "and no id resolves to anything")
	check(
		not registry.load_theatre({"id": "", "center_latitude": 0.0, "center_longitude": 0.0}, null, null),
		"an entry with no id is not a theatre either")
	registry.bind_launchers([_launcher("CITY NORTH", LAUNCHER_A)])
	registry.bind_structures(GroundIndex.new(), null)
	check(registry.objects().is_empty(), "and a bind against an unloaded theatre changes nothing")
