extends SceneTree

## Phase 4's map side: the objects the registry says are there, drawn where they
## actually stand, tapped for what they are, and refused when the theatre has nothing
## to say. This is the acceptance in headless form -- selecting a strategic object on
## the map has to resolve to world data -- against the two rules the brief cares about:
## an object is a real place, and a target the weapons already know stays the
## tracker's, not the map's.

const MFD := preload("res://scripts/ui/tactical_mfd.gd")
const LEVELS := preload("res://scripts/battle_map/battle_map_layers.gd")
const STRATEGY := preload("res://scripts/battle_map/battle_map_strategy.gd")
const OBJECTS := preload("res://scripts/war/war_objects.gd")
const REGIONS := preload("res://scripts/war/war_regions.gd")
const CONTROL := preload("res://scripts/war/war_control.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const CATALOG_PATH := "res://data/regions/catalog.json"

const CORRIDOR := "au_gold_coast_tweed_corridor"
## The launcher field's own entity id for the SAM standing at CITY NORTH, and a jet
## nowhere near anything, so a tap has two different answers to choose between.
const LAUNCHER := 21
const BANDIT := 101
const BANDIT_GROUND := Vector2(16000, -20000)

var failed := false
var _mfd: MFD
var _registry: OBJECTS
var _geography: REGIONS
var _control: CONTROL
var _asks: Array = []
var _strategic: Array = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _region(id: String) -> Dictionary:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	check(file != null, "the catalog has to be readable to have a war")
	if file == null:
		return {}
	for entry in (((JSON.parse_string(file.get_as_text()) as Dictionary)["regions"]) as Array):
		if String(entry.get("id", "")) == id:
			return entry
	return {}


func _site(name: String) -> Dictionary:
	for object in _registry.of_type(OBJECTS.Type.SAM_SITE):
		if String(object["detail"]["site"]) == name:
			return object
	return {}


func _airbase() -> Dictionary:
	return _registry.of_type(OBJECTS.Type.AIRBASE)[0]


## The world the map is handed: the corridor's districts, the objects in them, and one
## launcher at one site reporting in as itself.
func _build() -> void:
	var corridor := _region(CORRIDOR)
	_geography = REGIONS.new()
	check(_geography.load_theatre(corridor), "the corridor must divide into districts")
	_control = CONTROL.new()
	_control.setup(_geography)
	_registry = OBJECTS.new()
	check(_registry.load_theatre(corridor, _geography, _control), "and the corridor must have objects in it")
	_registry.bind_launchers([{"id": LAUNCHER, "position": Vector3.ZERO, "name": "CITY NORTH 1"}])
	var north: Vector2 = _site("CITY NORTH")["world_position"]
	_mfd = MFD.new()
	root.add_child(_mfd)
	root.size = Vector2i(900, 600)
	_mfd.size = Vector2(900, 600)
	_mfd.map.size = Vector2(900, 600)
	_mfd.contact_selected.connect(func(handle: int) -> void: _asks.append(handle))
	_mfd.map.strategic_selected.connect(func(id: int) -> void: _strategic.append(id))
	_mfd.open_panel()
	# Opening the panel recentres the map on the aircraft and takes the follow back, so
	# the camera is only the test's to move after that.
	_mfd.map.follow_player = false
	_mfd.map.set_war(_geography, _control)
	_mfd.map.set_objects(_registry)
	_mfd.map.set_state(
		Vector3.ZERO, 0.0,
		[
			TRACKER.contact(LAUNCHER, TRACKER.Kind.GROUND_LAUNCHER, Vector3(north.x, 30, north.y)),
			TRACKER.contact(BANDIT, TRACKER.Kind.AIR_JET, Vector3(BANDIT_GROUND.x, 800, BANDIT_GROUND.y), Vector3(0, 0, -220)),
		],
		-1, null)


func _map() -> Control:
	return _mfd.map


func _settle(metres: float) -> void:
	_map().set_range(metres)
	for frame in range(90):
		_map()._process(1.0 / 60.0)
	_map().markers()


func _batch() -> Array:
	var map: Control = _map()
	return map.strategy.batch(
		map._projector(), map._visible_ground(), map.semantic.alpha(&"objects"),
		map.semantic.level(), map.pixels_per_metre())


func _item_of(items: Array, id: int) -> Dictionary:
	for item in items:
		if int(item["id"]) == id:
			return item
	return {}


func _card() -> String:
	return String(_mfd._card_lines.text)


func _tap(world: Vector2) -> void:
	_map().select_at(_map().world_to_screen(world))


func _refresh_card() -> void:
	_mfd._card_elapsed = 0.0
	_mfd._process(MFD.CARD_SECONDS + 0.01)


func _run() -> void:
	# The panel's layer keys live in user://, and a run that was interrupted has no
	# business deciding what this one sees.
	DirAccess.remove_absolute(LEVELS.SETTINGS_FILE)
	_build()
	_settle(40000.0)
	_check_the_layer_comes_online()
	_check_the_map_draws_them_where_they_stand()
	_check_the_view_culls_the_symbols_not_the_ground()
	_check_a_tap_answers_with_the_object_it_hit()
	_check_the_card_reads_the_world()
	_check_the_card_keeps_reading_it()
	_check_a_theatre_with_no_objects_says_so()
	DirAccess.remove_absolute(LEVELS.SETTINGS_FILE)
	_mfd.free()
	if not failed:
		print("BATTLE_MAP_STRATEGY_TEST_PASS")
	quit(1 if failed else 0)


## The key on the panel is the honest part: a layer with objects behind it is drawn and
## switches, and switching it off takes both the drawing and the tapping with it.
func _check_the_layer_comes_online() -> void:
	var map: Control = _map()
	check(map.strategy.is_ready(), "the corridor's objects are a layer the map can draw")
	check(map.semantic.has_source(&"objects"), "so Strategic objects is no longer a key with nothing behind it")
	check(map.semantic.is_enabled(&"objects"), "and a layer that came online with nothing decided about it is drawn")
	_settle(40000.0)
	check(map.semantic.alpha(&"objects") == 1.0, "at theatre range as well as in the cockpit")
	var items := _batch()
	check(not items.is_empty(), "and the war's objects are on the map, got %d" % items.size())
	check(map.semantic.toggle(&"objects"), "the key switches it")
	_settle(40000.0)
	check(map.semantic.alpha(&"objects") == 0.0, "off, and the layer fades out")
	check(_batch().is_empty(), "and a layer the pilot switched off draws nothing")
	_strategic.clear()
	_tap(_airbase()["world_position"])
	check(_strategic.is_empty(), "and a layer that is not drawn cannot be tapped")
	check(map.semantic.toggle(&"objects"), "and back on again")
	_settle(40000.0)
	check(
		map.semantic.alpha(&"objects") == 1.0 and _batch().size() == items.size(),
		"which brings the whole layer back as it was")


## Every symbol sits on its own ground: the screen point it is drawn at is where the map
## says that world position is, the airfield's pavement is projected rather than painted,
## and a position nobody has confirmed is not allowed to look confirmed.
func _check_the_map_draws_them_where_they_stand() -> void:
	var map: Control = _map()
	var items := _batch()
	check(items.size() == _registry.count(), "the whole corridor is on screen at theatre range, got %d" % items.size())
	for object in _registry.objects():
		var name := String(object["name"])
		var item := _item_of(items, int(object["id"]))
		check(not item.is_empty(), "%s is drawn" % name)
		if item.is_empty():
			continue
		var where: Vector2 = map.world_to_screen(object["world_position"])
		check(
			(item["at"] as Vector2).distance_to(where) < 0.01,
			"%s is drawn on the ground it stands on, %.1f px out" % [name, (item["at"] as Vector2).distance_to(where)])
		check(
			where.is_finite() and Rect2(Vector2.ZERO, map.size).has_point(where),
			"and that ground is inside the map the pilot is looking at")
		check(not (item["paths"] as Array).is_empty(), "%s is drawn as line work, not an icon" % name)
		var colour: Color = item["colour"]
		if String(object["faction"]) == OBJECTS.ENEMY:
			check(colour.r > colour.b, "a hostile object is drawn in the red the ground it holds is washed with")
		else:
			check(colour.b >= colour.r, "and a friendly one in the same blue as its district")
		if bool(object["discovered"]):
			check(float(item["colour"].a) > STRATEGY.UNCONFIRMED, "%s is seen, and drawn as seen" % name)
		else:
			check(
				is_equal_approx(float(colour.a), map.semantic.alpha(&"objects") * STRATEGY.UNCONFIRMED),
				"%s has only ever been an estimate, and is drawn as one, got %.2f" % [name, float(colour.a)])
		if int(object["type"]) == OBJECTS.Type.AIRBASE:
			check(
				(item["strips"] as Array).size() == (object["detail"]["strips"] as Array).size(),
				"an airfield is drawn with its real pavement through it, got %d strips" % (item["strips"] as Array).size())
			check(String(item["label"]) == name, "the airfield is named on the theatre map")
		check(String(item["sub"]).is_empty(), "and the type is left off until the map closes in")
	# The names come back with the tactical view, and the pavement comes back at the
	# length it really is: the same object, three amounts of useful information.
	map.centre = _airbase()["world_position"]
	_settle(2000.0)
	var close := _batch()
	var here := _item_of(close, int(_airbase()["id"]))
	check(not here.is_empty(), "the airfield is on the tactical map over it")
	var strip: Array = (here["strips"] as Array)[0]
	check(
		(strip[0] as Vector2).distance_to(strip[1]) > 100.0,
		"with its runway drawn as long as the airport has it, got %.0f px" % (strip[0] as Vector2).distance_to(strip[1]))
	for item in close:
		var object := _registry.of(int(item["id"]))
		check(String(item["label"]) == String(object["name"]), "a tactical map names each thing it draws")
		check(
			String(item["sub"]) == OBJECTS.type_name(object),
			"with its type under the name, got %s" % String(item["sub"]))


## The visible ground box does the culling, so a symbol the camera has flown away from
## costs nothing -- which is what keeps hundreds of entities usable.
func _check_the_view_culls_the_symbols_not_the_ground() -> void:
	var map: Control = _map()
	var field := int(_airbase()["id"])
	map.centre = Vector2.ZERO
	_settle(2000.0)
	var items := _batch()
	check(items.size() < _registry.count(), "over one suburb the map draws a few of them, got %d" % items.size())
	for item in items:
		check(
			float(_registry.of(int(item["id"]))["strategic_value"]) >= STRATEGY.DRAWN_VALUE,
			"and nothing below the layer's own value floor is drawn")
	check(_item_of(items, field).is_empty(), "the airfield is out of frame from here and draws nothing")
	map.centre = _airbase()["world_position"]
	_settle(2000.0)
	check(not _item_of(_batch(), field).is_empty(), "flying to it puts it on the map")
	map.centre = Vector2.ZERO
	_settle(40000.0)
	check(
		_batch().size() == _registry.count(),
		"and pulling back out to theatre range brings every one of them into the cull box again")


## The seam the brief is judged on: a tap on a place answers with that place, and a tap
## on a track the weapons already know still answers with the track.
func _check_a_tap_answers_with_the_object_it_hit() -> void:
	var map: Control = _map()
	map.centre = Vector2.ZERO
	_settle(40000.0)
	_asks.clear()
	_strategic.clear()
	_tap(_airbase()["world_position"])
	check(_asks.is_empty(), "an airfield is not a contact and must not ask the tracker for one")
	check(_strategic == [int(_airbase()["id"])], "a tap on the field selects the field, got %s" % [_strategic])
	check(
		int(map.strategic_at(map.world_to_screen(_airbase()["world_position"]))["id"]) == int(_airbase()["id"]),
		"and the map answers the same question the tap asked")
	_asks.clear()
	_strategic.clear()
	_tap(BANDIT_GROUND)
	check(_asks == [BANDIT], "a track in the open is still the track a tap buys, got %s" % [_asks])
	check(_strategic.is_empty(), "and it does not arrive as an object")
	_asks.clear()
	_strategic.clear()
	_tap(_site("CITY NORTH")["world_position"])
	check(
		_asks == [LAUNCHER],
		"a launcher standing at a site is the thing the pilot asked for, got %s" % [_asks])
	check(_strategic.is_empty(), "and the site's own id never reaches the weapons")
	_asks.clear()
	_strategic.clear()
	var quiet := _site("HINTERLAND SOUTH")
	_tap(quiet["world_position"])
	check(_strategic == [int(quiet["id"])], "a site with nothing at it is still a place, and still selects, got %s" % [_strategic])
	check(_asks.is_empty(), "with no contact there to lock by accident")
	check((quiet["handles"] as Array).is_empty(), "and nothing in the table to mistake for a target")


## The card, reading the world through the id the map handed it: the strip's length is
## the airport's, the launcher count is the SAM field's, the district and its holder are
## the war's, and a landmark whose chunk has not streamed reports that rather than a
## confident nothing.
func _check_the_card_reads_the_world() -> void:
	var map: Control = _map()
	map.centre = Vector2.ZERO
	_settle(40000.0)
	var airbase := _airbase()
	_strategic.clear()
	_tap(airbase["world_position"])
	check(not _strategic.is_empty(), "the tap reached the card through the map's own signal")
	var text := _card()
	check(_mfd._card.visible, "and the card is open")
	check(
		text.contains("COOLANGATTA AIRPORT · AIRBASE · FRIENDLY"),
		"the card names the place, what it is and whose it is, got %s" % text)
	check(text.contains("1 STRIP · 14 2492 m · HDG 140°"), "the strip is the length the runway table says, got %s" % text)
	check(text.contains("LAT -28.1644"), "and it is at the coordinate the airport is at, got %s" % text)
	check(not text.contains("AREA UNMAPPED"), "in a theatre with authored districts the district is named, got %s" % text)
	check(
		text.contains("HELD FRIENDLY") or text.contains("HELD ENEMY") or text.contains("HELD CONTESTED"),
		"and who holds that ground is the war's own report, got %s" % text)
	check(text.contains("STATE INTACT"), "with the state the registry reports")
	check(text.contains("INTEL "), "and how well it is watched")
	check(text.contains("VALUE "), "and what the staff reckon it is worth")
	check(text.contains("FROM runways.gd OOL"), "saying where the row came from, got %s" % text)
	_asks.clear()
	_mfd._assign.pressed.emit()
	check(_asks.is_empty(), "ASSIGN TARGET on an airfield does not invent a lock")
	check(
		String(_mfd._status.text).contains("NO LIVE TRACK"),
		"and says so instead of pretending, got %s" % String(_mfd._status.text))
	_mfd._fly.pressed.emit()
	check(map._view.is_gliding(), "FLY TO flies the camera at an object rather than cutting to it")
	var seconds := 0.0
	while map._view.is_gliding() and seconds < 4.0:
		map._process(1.0 / 60.0)
		seconds += 1.0 / 60.0
	check(
		map.centre.distance_to(airbase["world_position"]) < 500.0,
		"and arrives at the airfield that was tapped, %.0f m out" % map.centre.distance_to(airbase["world_position"]))
	check(seconds < 2.5, "the flight is a planning gesture, not a journey: %.2f s" % seconds)
	check(_asks.is_empty() and _strategic.size() == 1, "flying to a place is not a second selection")
	_settle(40000.0)
	var north := _site("CITY NORTH")
	_mfd._strategic_selected(int(north["id"]))
	text = _card()
	check(text.contains("CITY NORTH SITE · SAM SITE · ENEMY"), "a hostile site is the enemy's whatever the districts say, got %s" % text)
	check(
		text.contains("1 LAUNCHER OF 1 · TRACK %d" % LAUNCHER),
		"and the card carries the tracker's own handle for it, got %s" % text)
	_asks.clear()
	_mfd._assign.pressed.emit()
	check(_asks == [LAUNCHER], "ASSIGN TARGET buys the launcher the site is reporting, got %s" % [_asks])
	var quiet := _site("HINTERLAND SOUTH")
	_mfd._strategic_selected(int(quiet["id"]))
	text = _card()
	check(
		text.contains("NOTHING SEEN HERE · POSITION FROM THE LAYOUT"),
		"an unconfirmed site says so on the card, got %s" % text)
	check(text.contains("STATE UNCONFIRMED"), "and reports the uncertainty instead of inventing a certainty")
	_mfd._strategic_selected(int(_registry.of_type(OBJECTS.Type.INFRASTRUCTURE)[0]["id"]))
	check(
		_card().contains("FOOTPRINT NOT STREAMED"),
		"a landmark nobody has looked at yet reports no damage read, got %s" % _card())


## The card is a live readout of the registry, not a photograph of the tap: what stands
## at a site changes between refreshes and the card has to change with it.
func _check_the_card_keeps_reading_it() -> void:
	_settle(40000.0)
	var north := _site("CITY NORTH")
	_mfd._strategic_selected(int(north["id"]))
	check(_card().contains("TRACK %d" % LAUNCHER), "the card opens with the launcher standing there")
	_registry.bind_launchers([])
	_refresh_card()
	var text := _card()
	check(text.contains("NOTHING LEFT AT THIS SITE"), "the site lost its launcher and the card knows, got %s" % text)
	check(String(north["operational_state"]) == OBJECTS.DESTROYED, "which is what the registry now says it is")
	var drawn := _item_of(_batch(), int(north["id"]))
	check(not drawn.is_empty(), "and a destroyed site is still on the map where it was")
	check(
		(drawn["paths"] as Array).size() > 2,
		"struck through so it cannot be read as something still standing, got %d strokes" % (drawn["paths"] as Array).size())
	check(bool(north["discovered"]), "having been seen is a fact the war keeps")
	_registry.bind_launchers([
		{"id": LAUNCHER, "position": Vector3.ZERO, "name": "CITY NORTH 1"},
		{"id": 22, "position": Vector3.ZERO, "name": "CITY NORTH 2"},
	])
	_registry.bind_launchers([{"id": LAUNCHER, "position": Vector3.ZERO, "name": "CITY NORTH 1"}])
	_refresh_card()
	check(
		_card().contains("1 LAUNCHER OF 2"),
		"a site that had two and kept one reports a damaged site, got %s" % _card())
	check(String(north["operational_state"]) == OBJECTS.DAMAGED, "and the registry agrees")


## A theatre the campaign has no objects for -- and a map that was never handed one --
## both get the same answer: no layer, no card, no invented ground.
func _check_a_theatre_with_no_objects_says_so() -> void:
	var map: Control = _map()
	_mfd._strategic_selected(int(_site("CITY NORTH")["id"]))
	map.set_objects(null)
	check(not map.strategy.is_ready(), "taking the objects away takes the layer with it")
	check(not map.semantic.has_source(&"objects"), "and the key says so on the panel")
	check(not map.semantic.toggle(&"objects"), "so the toggle is refused, not faked")
	check(_batch().is_empty(), "and nothing is drawn")
	check(map.strategic_object(int(_site("CITY NORTH")["id"])).is_empty(), "and a card cannot read a registry that is gone")
	_refresh_card()
	check(not _mfd._card.visible, "so the card that was open on it closes instead of reporting a stale one")
	_asks.clear()
	_strategic.clear()
	_tap(_site("CITY NORTH")["world_position"])
	check(_asks == [LAUNCHER], "the launcher on the ground is still there, and still the answer")
	check(_strategic.is_empty(), "with no object to answer as")
	map.set_objects(_registry)
	check(
		map.strategy.is_ready() and map.semantic.has_source(&"objects"),
		"and the next theatre with objects in it brings the layer back")
	_mfd.close_panel()
	check(not _mfd._card.visible, "and closing the map takes the object card with it")
