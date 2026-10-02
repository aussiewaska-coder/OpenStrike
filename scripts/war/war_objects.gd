extends RefCounted

## What the war is fought over, taken from the world rather than invented for
## the map.
##
## Phase 3 said which ground belongs to whom. This says what is standing on it,
## under the brief's two rules: an object has to correspond to an actual place,
## and where the game already has an entity for the thing, this is a view of that
## entity and not a second copy of it. So every object here comes out of a source
## that exists for its own sake -- the authored runway table the jet takes off
## from, the launcher sites the SAM field populates itself, the hero towers the
## terrain places at their real coordinates -- and no position in this table was
## made up here.
##
## What those sources do not cover is left unclaimed. There is no command post,
## supply depot, enemy airbase or radar station in this world yet, so this table
## contains none and the map draws none: the types are here for the WarDirector to
## fill from entities it can actually point at. An unclaimed type is a hole a later
## phase has to fill honestly, not a placeholder full of round numbers.
##
## Two live bindings run in at sensible intervals -- `bind_launchers` and
## `bind_structures` -- and they are the only thing here that changes state on its
## own. What a site is doing is a question the launcher field answers, and how much
## of a tower is left is a question the building damage system answers.

const RUNWAYS := preload("res://scripts/world/runways.gd")
const SITES := preload("res://scripts/entities/launcher_layout.gd")
const HEROES := preload("res://scripts/entities/hero_towers.gd")
const MAP_TILES := preload("res://scripts/terrain/map_tiles.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")
const DAMAGE := preload("res://scripts/world/building_damage_system.gd")
const REGIONS := preload("res://scripts/war/war_regions.gd")
const CONTROL := preload("res://scripts/war/war_control.gd")

## The nine types the brief opens with. Six of them have nothing in this world to
## correspond to yet, and are declared rather than populated.
enum Type {
	AIRBASE,
	FORWARD_BASE,
	RADAR,
	SAM_SITE,
	COMMAND_POST,
	SUPPLY_DEPOT,
	GROUND_FORCE,
	## The brief writes this one as BRIDGE/INFRASTRUCTURE. A bridge needs a real
	## crossing authored, and this theatre has none, so the type is named for the
	## class of thing rather than the example.
	INFRASTRUCTURE,
	AIRCRAFT_GROUP,
}

const TYPE_NAME := {
	Type.AIRBASE: "AIRBASE",
	Type.FORWARD_BASE: "FWD BASE",
	Type.RADAR: "RADAR",
	Type.SAM_SITE: "SAM SITE",
	Type.COMMAND_POST: "COMMAND POST",
	Type.SUPPLY_DEPOT: "SUPPLY",
	Type.GROUND_FORCE: "GROUND FORCE",
	Type.INFRASTRUCTURE: "INFRASTRUCTURE",
	Type.AIRCRAFT_GROUP: "AIRCRAFT GP",
}

## The id bands this world already hands out: launcher entities count from 1,
## drones from 100000 and enemy jets from 200000. A strategic id has to stay out of
## all three, because the card offers a tracker handle for a site that has one --
## an id that could be mistaken for an entity would let the map lock something that
## does not exist.
const FIRST_ID := 300000

const FRIENDLY := "FRIENDLY"
const ENEMY := "ENEMY"
const NEUTRAL := "NEUTRAL"

const INTACT := "INTACT"
const DAMAGED := "DAMAGED"
const DESTROYED := "DESTROYED"
## On the authored layout, with nothing standing at it: no launcher has ever been
## seen there this sortie, and the terrain may never have accepted one. Drawn as an
## unconfirmed position rather than as a target.
const UNCONFIRMED := "UNCONFIRMED"

## A structure keeps reporting INTACT until it has lost more than a graze's worth
## of itself. The world's only published damage scale is the accumulated structural
## damage at which a building starts to smoke, so health is measured against that:
## half of it is the smoke point, twice it is nothing left standing. When the
## campaign grows a real destruction model it replaces this rather than arguing
## with it.
const STRUCTURE_INTACT := 0.9
const STRUCTURE_STANDING := 0.05
## How far above and below a structure the binding ray is fired. The top clears the
## tallest tower in the kit and the bottom reaches under the ground the footprint
## sits on, so the hit index answers with whatever the player would actually strike
## at that coordinate.
const RAY_TOP_M := 600.0
const RAY_BOTTOM_M := -200.0

## What a type is worth to whoever holds the ground it stands on, before the
## district's own authored value is taken into account. A staff estimate and not a
## measurement: the brief asks every object for a `strategic_value`, and the only
## honest inputs in this repository are this table and the district values in
## `war_regions.gd`.
const WEIGHT := {
	Type.AIRBASE: 1.0,
	Type.FORWARD_BASE: 0.8,
	Type.RADAR: 0.85,
	Type.SAM_SITE: 0.72,
	Type.COMMAND_POST: 0.9,
	Type.SUPPLY_DEPOT: 0.6,
	Type.GROUND_FORCE: 0.65,
	Type.INFRASTRUCTURE: 0.45,
	Type.AIRCRAFT_GROUP: 0.8,
}

## The aerodromes this world has authored pavements for, at the aerodrome
## reference point published for each one -- the same two coordinates
## `map_places.gd` prints as airport labels, and `runways.gd`'s own constants
## rather than a third statement of them.
const AERODROME := {
	"OOL": {
		"name": "COOLANGATTA AIRPORT",
		"latitude": RUNWAYS.COOLANGATTA_ARP_LAT,
		"longitude": RUNWAYS.COOLANGATTA_ARP_LON,
	},
	"YSSY": {
		"name": "SYDNEY AIRPORT",
		"latitude": RUNWAYS.SYDNEY_ARP_LAT,
		"longitude": RUNWAYS.SYDNEY_ARP_LON,
	},
}

var _objects := []
var _by_id := {}
var _geography: REGIONS
var _control: CONTROL
var _theatre := ""
var _bounds := {}
var _size := 50000.0
var _next_id := FIRST_ID
var _loaded := false


## Build the table for one catalog entry. `geography` and `control` may both be
## null, which is what a theatre with no districts authored looks like: the objects
## are still real places and still get built, and they simply report no region
## rather than being handed a district invented for the occasion.
func load_theatre(region: Dictionary, geography: RefCounted, control: RefCounted) -> bool:
	_objects = []
	_by_id = {}
	_geography = null
	_control = null
	_loaded = false
	_next_id = FIRST_ID
	_theatre = ""
	if not region.has("center_latitude") or not region.has("center_longitude"):
		return false
	_theatre = String(region.get("id", ""))
	if _theatre.is_empty():
		return false
	_size = float(region.get("world_size_m", 50000.0))
	_bounds = MAP_TILES.region_bounds(
		float(region["center_latitude"]), float(region["center_longitude"]), _size)
	if _bounds.is_empty():
		return false
	if geography != null and geography.has_method("region_at") and geography.is_loaded():
		_geography = geography
	if control != null and control.has_method("state_of"):
		_control = control
	_airbases()
	_launcher_sites()
	_structures()
	_loaded = not _objects.is_empty()
	return _loaded


func is_loaded() -> bool:
	return _loaded


func theatre() -> String:
	return _theatre


func objects() -> Array:
	return _objects


## The object itself, not a copy: the live bindings write into these dictionaries,
## so a card that holds an id reads the current state through it rather than the
## state at the moment it was opened.
func of(id: int) -> Dictionary:
	return _by_id.get(id, {})


## The airfields are the one class of object whose *capability* is not something the
## world has an entity for: the runway table says how long the pavement is, and
## nothing else says whether the field can generate sorties this hour. That answer is
## the WarDirector's -- it owns the airbase damage-and-repair model and publishes it
## back through `refresh_airbases` on its own tick. Until the campaign has a director
## and the registry has answers, the fields report as they were built, and this
## refuses the offer rather than filling them with round numbers.
func refresh_airbases(operating: Dictionary) -> bool:
	if not _loaded or operating.is_empty():
		return false
	var applied := 0
	for record in of_type(Type.AIRBASE):
		var object: Dictionary = record
		var fields: Dictionary = operating.get(int(object["id"]), {})
		if fields.is_empty():
			continue
		var detail: Dictionary = object["detail"]
		for field in ["damage", "fuel", "aircraft", "capacity", "operational",
				"repair_rate", "radar_support"]:
			if fields.has(field):
				detail[field] = fields[field]
		object["operational_state"] = String(fields.get("state", INTACT))
		# What is left to fly off it, not what the concrete could once have carried:
		# a destroyed field's length is a fact about the past.
		object["health"] = clampf(float(fields.get("operational", 0.0)), 0.0, 1.0)
		applied += 1
	return applied > 0


## And the same for the fields every object shares that are not about the thing at
## all, but about the ground it stands on and how well anyone can see it. The
## district's value is authored and does not move; who holds it and what the
## district's own intel level is are both things a campaign changes. This runs before
## `refresh_airbases`, which is the authority on a field's own operating state.
func refresh_situation() -> bool:
	if not _loaded or _control == null:
		return false
	for record in _objects:
		var object: Dictionary = record
		var district := String(object["region_id"])
		var state: Dictionary = _control.state_of(district)
		if state.is_empty():
			continue
		if int(object["type"]) == Type.INFRASTRUCTURE:
			# A tower has no order of battle: the ground it stands on is the only
			# claim on it, so when the ground moves, the claim moves with it. A
			# launcher site belongs to whoever fired the round and an airfield to the
			# table that published it, and neither follows a district.
			object["faction"] = String(state["owner"])
		# What has been seen is not an estimate any more: a site with a launcher
		# standing at it keeps the confidence the binding gave it.
		if (object["handles"] as Array).is_empty():
			object["intel_confidence"] = _intel(district)
		if float(object["health"]) >= STRUCTURE_INTACT:
			# Only a field that reports itself undamaged may be called off again by
			# the situation around it; something that has lost pieces of itself has
			# already been accounted for by whatever binds it.
			object["operational_state"] = INTACT \
				if _wear(district) < 1.0 - STRUCTURE_INTACT else DAMAGED
	return true


## How much of a district's own infrastructure is no longer standing, as its war
## measures report it. A ruined province does not hold an intact facility, whatever
## the runway table says about the concrete.
func _wear(district: String) -> float:
	if district.is_empty():
		return 0.0
	var state: Dictionary = _control.state_of(district)
	return 1.0 - clampf(float(state.get("infrastructure", 1.0)), 0.0, 1.0)


func of_type(type: int) -> Array:
	var found := []
	for record in _objects:
		if int(record["type"]) == type:
			found.append(record)
	return found


func count() -> int:
	return _objects.size()


static func type_name(object: Dictionary) -> String:
	return String(TYPE_NAME.get(int(object.get("type", -1)), "OBJECT"))


## The launcher field is the truth about its sites: it places them, it removes one
## when a round arrives, and it is the only thing that knows whether a site on the
## authored layout was ever accepted by the ground. What comes back through here is
## `launcher_positions()`, so a site that has a launcher standing at it carries that
## launcher's own entity id -- the tracker's handle for the same SAM, not a second
## identity for it.
func bind_launchers(positions: Array) -> void:
	if not _loaded:
		return
	var reported := {}
	for item in positions:
		var entry: Dictionary = item
		reported[int(entry["id"])] = String(entry.get("name", ""))
	for record in _objects:
		var object: Dictionary = record
		if int(object["type"]) != Type.SAM_SITE:
			continue
		var site := String(object["detail"]["site"])
		var handles: Array = []
		for id in reported:
			if String(reported[id]).begins_with(site + " "):
				handles.append(id)
		handles.sort()
		object["handles"] = handles
		var live := handles.size()
		var planned := maxi(int(object["detail"]["planned"]), 1)
		var district := String(object["region_id"])
		if live > 0:
			object["detail"]["seen"] = true
			# The strongest the site has ever been seen at is what it is measured
			# against afterwards. The authored layout plans one launcher per position,
			# so a yardstick taken only from the table would call a site that held two
			# and kept one perfectly intact -- and a site losing half of what it
			# arrived with is exactly the report the map needs.
			var strongest := maxi(planned, maxi(int(object["detail"].get("strongest", 0)), live))
			object["detail"]["strongest"] = strongest
			object["health"] = clampf(float(live) / float(strongest), 0.0, 1.0)
			object["operational_state"] = INTACT if live >= strongest else DAMAGED
			object["discovered"] = true
			# A launcher reporting in is not an estimate any more.
			object["intel_confidence"] = 1.0
		elif bool(object["detail"]["seen"]):
			object["health"] = 0.0
			object["operational_state"] = DESTROYED
			object["discovered"] = true
			object["intel_confidence"] = _intel(district)
		else:
			object["health"] = 0.0
			object["operational_state"] = UNCONFIRMED
			object["discovered"] = false
			object["intel_confidence"] = _intel(district)


## And the same for the skyline: a tower's state is whatever the cannon has left of
## the footprint the terrain collision answers for at that coordinate. When the
## chunk is not streamed in detailed the ray finds nothing, and the object reports
## the authored structure with no damage claimed for it -- the card says the
## footprint is not loaded rather than printing a confident reading of a building it
## cannot see.
func bind_structures(index: RefCounted, reported: RefCounted) -> void:
	if not _loaded or index == null or not index.has_method("query_segment"):
		return
	var damage: DAMAGE = null
	if reported != null and reported.has_method("damage_for"):
		damage = reported
	for record in _objects:
		var object: Dictionary = record
		if int(object["type"]) != Type.INFRASTRUCTURE:
			continue
		var at: Vector2 = object["world_position"]
		var hit: HIT = index.query_segment(
			Vector3(at.x, RAY_TOP_M, at.y), Vector3(at.x, RAY_BOTTOM_M, at.y))
		var detail: Dictionary = object["detail"]
		if hit == null or not hit.hit or int(hit.object_type) != HIT.ObjectKind.BUILDING:
			detail["building_id"] = -1
			detail["damage"] = 0.0
			detail["streamed"] = false
			object["health"] = 1.0
			object["operational_state"] = INTACT
			continue
		var building_id := int(hit.building_id)
		detail["building_id"] = building_id
		detail["streamed"] = true
		var amount := float(damage.damage_for(building_id)) if damage != null else 0.0
		detail["damage"] = amount
		object["health"] = clampf(1.0 - amount / (2.0 * DAMAGE.SMOKE_THRESHOLD), 0.0, 1.0)
		if float(object["health"]) >= STRUCTURE_INTACT:
			object["operational_state"] = INTACT
		elif float(object["health"]) > STRUCTURE_STANDING:
			object["operational_state"] = DAMAGED
		else:
			object["operational_state"] = DESTROYED


## The airfields, one per aerodrome, from the runways the game already flies
## off. The pavement lines are the authored centre, heading and length turned into
## both ends of the strip in world metres, which is what lets the map draw the
## actual runway rather than an icon standing for one.
func _airbases() -> void:
	var grouped := {}
	for strip in RUNWAYS.for_region(_theatre):
		var runway: Dictionary = strip
		var code := String(runway["airport"])
		if not grouped.has(code):
			grouped[code] = []
		grouped[code].append(runway)
	for code in grouped:
		var aerodrome: Dictionary = AERODROME.get(code, {})
		if aerodrome.is_empty():
			continue
		var runways: Array = grouped[code]
		var latitude := float(aerodrome["latitude"])
		var longitude := float(aerodrome["longitude"])
		var longest := 0.0
		var strips := []
		for entry in runways:
			var runway: Dictionary = entry
			longest = maxf(longest, float(runway["length_m"]))
			var ends := _strip_ends(runway)
			strips.append({
				"id": String(runway["id"]),
				"heading_deg": float(runway["heading_deg"]),
				"length_m": float(runway["length_m"]),
				"a": ends[0],
				"b": ends[1],
			})
		_append({
			"type": Type.AIRBASE,
			"name": String(aerodrome["name"]),
			"faction": FRIENDLY,
			"world_position": _place(latitude, longitude),
			"latitude": latitude,
			"longitude": longitude,
			"source": "runways.gd %s · %d authored strip%s" % [code, runways.size(), "s" if runways.size() > 1 else ""],
			"detail": {"icao": code, "strips": strips, "longest_m": longest},
		})


## The SAM sites, at the six positions the launcher field lays itself out from.
## They are the field's hostile sites, so their faction is the enemy's whatever
## district the ground war happens to claim around them -- which is a real fact
## about this campaign, not an oversight: the opening layout puts enemy sites
## behind lines the districts report as friendly.
func _launcher_sites() -> void:
	for record in SITES.clusters_for(_theatre, _size * 0.5, Callable(self, "_place")):
		var site: Dictionary = record
		var at: Vector2 = site["centre"]
		var coordinate := _coordinate(at)
		_append({
			"type": Type.SAM_SITE,
			"name": "%s SITE" % String(site["name"]),
			"faction": ENEMY,
			"world_position": at,
			"latitude": coordinate.x,
			"longitude": coordinate.y,
			"source": "launcher_layout.gd · %s" % String(site["name"]),
			"operational_state": UNCONFIRMED,
			"health": 0.0,
			"discovered": false,
			"detail": {"site": String(site["name"]), "planned": SITES.TARGETS_PER_CLUSTER, "seen": false, "strongest": 0},
		})


## The structures the skyline is known for, at the coordinates the terrain places
## their models from.
func _structures() -> void:
	for record in HEROES.layout_for(_theatre):
		var hero: Dictionary = record
		var latitude := float(hero["lat"])
		var longitude := float(hero["lon"])
		var name := String(hero["name"])
		_append({
			"type": Type.INFRASTRUCTURE,
			"name": name,
			"faction": _holder_of(_region_id_at(_place(latitude, longitude))),
			"world_position": _place(latitude, longitude),
			"latitude": latitude,
			"longitude": longitude,
			"source": "hero_towers.gd · %s" % name,
			"detail": {"structure": name, "building_id": -1, "damage": 0.0, "streamed": false},
		})


## Put one object in the table, and give it the fields the brief insists on. The
## caller supplies the position and where it came from; everything else -- the
## district it lands in, what that district and its type make it worth, and how well
## the ground around it is watched -- is derived here, so no two sources can
## disagree about the same field.
func _append(fields: Dictionary) -> void:
	var at: Vector2 = fields["world_position"]
	if not at.is_finite():
		return
	var region_id := String(_region_id_at(at))
	# Ground no district claims is not worthless, so an object outside the lattice
	# is rated on the middle of the district scale rather than on nothing.
	var district := 0.35
	if not region_id.is_empty():
		district = float(_geography.region(region_id)["value"])
	var object := {
		"id": _next_id,
		"type": int(fields["type"]),
		"name": String(fields["name"]),
		"faction": String(fields["faction"]),
		"world_position": at,
		"latitude": float(fields["latitude"]),
		"longitude": float(fields["longitude"]),
		"region_id": region_id,
		"health": float(fields.get("health", 1.0)),
		"operational_state": String(fields.get("operational_state", INTACT)),
		"strategic_value": clampf(
			float(WEIGHT.get(int(fields["type"]), 0.4)) * (0.45 + 0.55 * district), 0.0, 1.0),
		"discovered": bool(fields.get("discovered", true)),
		"intel_confidence": _intel(region_id),
		"source": String(fields["source"]),
		"handles": [],
		"detail": fields.get("detail", {}),
	}
	_next_id += 1
	_objects.append(object)
	_by_id[object["id"]] = object


func _intel(region_id: String) -> float:
	if _control == null or region_id.is_empty():
		return 0.0
	var state: Dictionary = _control.state_of(region_id)
	return clampf(float(state.get("intel_level", 0.0)), 0.0, 1.0)


## Whoever holds the district a structure stands in. An object's faction is its
## own until a source says otherwise: a tower has no order of battle, so the ground
## it is on is the only claim on it, and an unauthored theatre claims nothing.
func _holder_of(region_id: String) -> String:
	if _control == null or region_id.is_empty():
		return NEUTRAL
	return String(_control.owner_of(region_id))


func _region_id_at(at: Vector2) -> String:
	if _geography == null:
		return ""
	var region: Dictionary = _geography.region_at(at)
	return String(region["id"]) if not region.is_empty() else ""


func _place(latitude: float, longitude: float) -> Vector2:
	return MAP_TILES.world_of(_bounds, latitude, longitude, _size)


## The other way round, for the sources that hand over a ground position and expect
## a coordinate back. It is `world_of` unwound, which is why it stays inside the
## same two-decimal range the authored tables do.
func _coordinate(at: Vector2) -> Vector2:
	var u := at.x / _size + 0.5
	var v := at.y / _size + 0.5
	return Vector2(MAP_TILES.latitude_at(_bounds, v), MAP_TILES.longitude_at(_bounds, u))


## Both ends of a runway's pavement, in world metres: the threshold an aircraft
## lines up on, which `runways.gd` already works out, and the far end the same half
## length the other way along the takeoff heading.
func _strip_ends(runway: Dictionary) -> Array:
	var centre := Vector2(float(runway["center_lat"]), float(runway["center_lon"]))
	var heading := deg_to_rad(float(runway["heading_deg"]))
	var half := float(runway["length_m"]) * 0.5
	var threshold: Vector2 = RUNWAYS.threshold_latlon(runway)
	var across := half / (MAP_TILES.METRES_PER_DEGREE_LAT * cos(deg_to_rad(centre.x)))
	var far := Vector2(
		centre.x + cos(heading) * half / MAP_TILES.METRES_PER_DEGREE_LAT,
		centre.y + sin(heading) * across)
	return [_place(threshold.x, threshold.y), _place(far.x, far.y)]
