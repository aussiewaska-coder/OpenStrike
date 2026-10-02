extends SceneTree

## The wired map: the same seven tracks, the same projection, three different
## amounts of useful information. This is the Phase 2 acceptance in headless form
## -- zooming has to change what the map tells you, not merely how big the icons
## are -- and a tap must still reach the target the weapons already know.

const CANVAS := preload("res://scripts/ui/tactical_map_canvas.gd")
const LEVELS := preload("res://scripts/battle_map/battle_map_layers.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const WAR_REGIONS := preload("res://scripts/war/war_regions.gd")
const WAR_CONTROL := preload("res://scripts/war/war_control.gd")
const CATALOG_PATH := "res://data/regions/catalog.json"

const JET_A := 101
const JET_B := 102
const DRONE := 103
const JET_C := 104
const LAUNCHER_A := 201
const LAUNCHER_B := 202
const SITE := 301

var failed := false
var _locks: Array = []
var _titles: Array = []
var _groups_tapped: Array = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _note_contact(handle: int) -> void:
	_locks.append(handle)


func _note_group(handles: Array, title: String, centroid: Vector3) -> void:
	_groups_tapped.append({"handles": handles.duplicate(), "title": title, "centroid": centroid})
	_titles.append(title)


func _track(handle: int, kind: int, at: Vector3, velocity := Vector3.ZERO) -> Dictionary:
	return TRACKER.contact(handle, kind, at, velocity, "BANDIT %02d" % handle)


## A four-ship forming up over ownship, a launcher pair out to the south-east and
## a fixed site a long way off to the north-west: close enough to fold together,
## far enough apart to stay three reports.
func _contacts() -> Array:
	return [
		_track(JET_A, TRACKER.Kind.AIR_JET, Vector3(300, 400, 200), Vector3(0, 0, -220)),
		_track(JET_B, TRACKER.Kind.AIR_JET, Vector3(-300, 410, -100), Vector3(0, 0, -220)),
		_track(DRONE, TRACKER.Kind.AIR_DRONE, Vector3(100, 90, 700), Vector3(40, 0, -160)),
		_track(JET_C, TRACKER.Kind.AIR_JET, Vector3(-700, 430, 500), Vector3(-40, 0, -230)),
		_track(LAUNCHER_A, TRACKER.Kind.GROUND_LAUNCHER, Vector3(8000, 30, -6000)),
		_track(LAUNCHER_B, TRACKER.Kind.GROUND_LAUNCHER, Vector3(8400, 30, -5600)),
		_track(SITE, TRACKER.Kind.BUILDING, Vector3(-20000, 60, 18000)),
	]


func _run() -> void:
	# Panel state lives in user:// and decides what the map draws, so a run that
	# was interrupted halfway must not decide what this one sees.
	DirAccess.remove_absolute(LEVELS.SETTINGS_FILE)
	var map: CANVAS = CANVAS.new()
	root.add_child(map)
	map.size = Vector2(900, 600)
	map.set_state(Vector3.ZERO, 0.0, _contacts(), -1, null)
	map.contact_selected.connect(_note_contact)
	map.group_selected.connect(_note_group)
	_check_tactical(map)
	_check_regional(map)
	_check_theatre(map)
	_check_layers_declutter(map)
	_check_a_group_tap_locks_nothing(map)
	_check_a_double_tap_opens_a_group(map)
	_check_the_war_arrives(map)
	_check_the_cull_box_reaches_the_ground_it_shows(map)
	DirAccess.remove_absolute(LEVELS.SETTINGS_FILE)
	map.free()
	if not failed:
		print("BATTLE_MAP_ZOOM_TEST_PASS")
	quit(1 if failed else 0)


func _settle(map: CANVAS, metres: float) -> void:
	map.set_range(metres)
	for frame in range(90):
		map._process(1.0 / 60.0)


## The map is 900 by 600 and the scale is set by the short axis, so this view is
## roughly 30 x 20 km at a 20 km range. A track outside it is drawn nowhere and
## cannot be tapped there, at any density.
func _on_screen(map: CANVAS, world: Vector3) -> bool:
	var at: Vector2 = map.world_to_screen(Vector2(world.x, world.z))
	return at.is_finite() and Rect2(Vector2.ZERO, map.size).has_point(at)


## The formations this view is drawing. The map only reclusters when something
## asks what to draw -- a headless run draws nothing -- so the question has to be
## asked here before the answer is read back.
func _groups_of(map: CANVAS) -> Array:
	map.markers()
	var found := []
	for group in map.cluster.live_groups():
		found.append(group)
	return found


## The individual track the map is drawing under this world point, or nothing.
func _handle_under(map: CANVAS, world: Vector3) -> int:
	var marker: Dictionary = map.marker_at(map.world_to_screen(Vector2(world.x, world.z)))
	return int(marker.get("handle", -1))


func _counted(items: Array) -> int:
	var total := 0
	for item in items:
		total += 1 if bool(item["individual"]) else int(item["group"]["count"])
	return total


func _check_tactical(map: CANVAS) -> void:
	_settle(map, 2000.0)
	check(map.semantic.level() == LEVELS.Level.TACTICAL, "2 km is the tactical density")
	check(map.semantic.alpha(&"sweep") == 1.0, "the radar sweep belongs to the tactical map")
	var items := map.markers()
	check(map.cluster.live_groups().is_empty(), "at tactical range nothing is folded into a formation")
	check(_counted(items) == 7, "every track is still itself at tactical range, got %d" % _counted(items))
	var visible := 0
	var found := 0
	for contact in map.contacts:
		if not _on_screen(map, contact["position"]):
			continue
		visible += 1
		if _handle_under(map, contact["position"]) == int(contact["handle"]):
			found += 1
	check(visible >= 4, "the test must actually be looking at the formation, got %d tracks" % visible)
	check(found == visible, "every track on the map is individually tappable, got %d of %d" % [found, visible])


func _check_regional(map: CANVAS) -> void:
	_settle(map, 20000.0)
	check(map.semantic.level() == LEVELS.Level.REGIONAL, "20 km is still the regional density")
	check(
		map.semantic.alpha(&"sweep") == 0.0,
		"a planning view drops the instrument it cannot use")
	var items := map.markers()
	var groups := _groups_of(map)
	var individuals := 0
	for item in items:
		if bool(item["individual"]):
			individuals += 1
	check(groups.size() == 2, "the tracks fold into two formations, got %d" % groups.size())
	check(individuals == 1, "and a track with nothing beside it stays a track of one, got %d" % individuals)
	check(_counted(items) == 7, "no track may be lost between densities, got %d" % _counted(items))
	var air := _air_of(map, groups)
	var marker: Dictionary = map.marker_at(map.world_to_screen(Vector2(
		(air["centroid"] as Vector3).x, (air["centroid"] as Vector3).z)))
	check(marker.has("group"), "the formation is tappable where it is drawn")
	var handles: Array = marker.get("handles", [])
	handles.sort()
	check(handles == [JET_A, JET_B, DRONE, JET_C],
		"the whole four-ship is one report, not two overlapping ones, got %s" % [handles])
	check(
		_handle_under(map, Vector3(-20000, 60, 18000)) == SITE,
		"a track with nothing near it stays an individual at regional range")
	var ground := {}
	for group in groups:
		if not bool(group["air"]):
			ground = group
	check(
		int(ground["count"]) == 2 and not bool(ground["air"]),
		"a launcher pair is a ground formation, not an air one")


func _check_theatre(map: CANVAS) -> void:
	_settle(map, 40000.0)
	check(map.semantic.level() == LEVELS.Level.THEATRE, "40 km is the theatre density")
	var items := map.markers()
	var individuals := 0
	for item in items:
		if bool(item["individual"]):
			individuals += 1
	check(individuals == 1, "a theatre merge folds the formations together and leaves the lone site alone")
	var groups := _groups_of(map)
	check(groups.size() == 2, "the four-ship and the launcher pair over the corridor, got %d" % groups.size())
	check(_counted(items) == 7, "and all seven tracks are still accounted for, got %d" % _counted(items))
	var marker: Dictionary = map.marker_at(map.world_to_screen(Vector2(-20000, 18000)))
	check(
		marker.has("handle") and int(marker["handle"]) == SITE,
		"a track alone in the theatre is still itself, and still tappable as the thing it is")


func _check_layers_declutter(map: CANVAS) -> void:
	_settle(map, 2000.0)
	check(_handle_under(map, map.contacts[0]["position"]) == JET_A, "and back in, the tracks are tappable")
	check(not map.semantic.toggle(&"territory"), "a layer with no intelligence behind it is refused, not faked")
	map.semantic.toggle(&"contacts")
	_settle(map, 2000.0)
	check(map.semantic.alpha(&"contacts") == 0.0, "switching contacts off fades the whole contact layer out")
	check(_handle_under(map, map.contacts[0]["position"]) == -1, "and a layer that is not drawn cannot be tapped")
	check(map.contact_at(map.world_to_screen(Vector2(300, 200))) == JET_A,
		"the shipped picking helper still answers for the tactical overlay")
	map.semantic.toggle(&"contacts")
	_settle(map, 2000.0)
	check(map.semantic.alpha(&"contacts") == 1.0, "switching them back in brings them all back")
	map.semantic.toggle(&"places")
	map.semantic.toggle(&"route")
	map.semantic.toggle(&"grid")
	_settle(map, 2000.0)
	check(
		map.semantic.alpha(&"places") == 0.0
		and map.semantic.alpha(&"route") == 0.0
		and map.semantic.alpha(&"grid") == 0.0,
		"every layer the map draws can be taken off it")
	for id in [&"places", &"route", &"grid"]:
		map.semantic.toggle(id)
	_settle(map, 2000.0)
	check(
		map.semantic.alpha(&"places") == 1.0 and map.semantic.alpha(&"sweep") == 1.0,
		"and putting them back leaves the map as it was found")


func _air_of(map: CANVAS, groups: Array) -> Dictionary:
	for group in groups:
		if bool(group["air"]):
			return group
	return {}


func _check_a_group_tap_locks_nothing(map: CANVAS) -> void:
	_settle(map, 20000.0)
	var air := _air_of(map, _groups_of(map))
	_locks.clear()
	_titles.clear()
	_groups_tapped.clear()
	map.select_at(map.world_to_screen(Vector2(
		(air["centroid"] as Vector3).x, (air["centroid"] as Vector3).z)))
	check(_locks.is_empty(), "tapping a formation must not lock one aircraft inside it")
	check(_groups_tapped.size() == 1, "and it must put exactly one card on the panel")
	check(String(_titles[0]) == String(air["label"]), "the card is named for the formation that was tapped")
	var handles: Array = _groups_tapped[0]["handles"]
	handles.sort()
	check(handles == [JET_A, JET_B, DRONE, JET_C],
		"the card carries the tracker's own handles, so ASSIGN TARGET has something real to assign")
	_locks.clear()
	_titles.clear()
	_groups_tapped.clear()
	map.select_at(map.world_to_screen(Vector2(-20000, 18000)))
	check(_locks == [SITE], "a lone track still selects as the target it always was")
	check(_groups_tapped.is_empty(), "and it does not arrive as a group of one")


## The point of a group marker is that it can be opened up. A double tap has to
## fly the camera in far enough that the formation stops being one thing.
func _check_a_double_tap_opens_a_group(map: CANVAS) -> void:
	_settle(map, 40000.0)
	var biggest := {}
	for group in _groups_of(map):
		if int(group["count"]) > int(biggest.get("count", 0)):
			biggest = group
	check(int(biggest["count"]) == 4, "the four-ship is the biggest thing to open, got %d" % int(biggest["count"]))
	var centroid: Vector3 = biggest["centroid"]
	# The group records are pooled, and flying in rebuilds them, so the handles
	# have to be read out while the formation is still on the map.
	var members: Array = map.cluster.handles_of(biggest)
	_locks.clear()
	_titles.clear()
	_groups_tapped.clear()
	map._focus_at(map.world_to_screen(Vector2(centroid.x, centroid.z)))
	check(map._view.is_gliding(), "opening a formation must be a flight, not a cut")
	var seconds := 0.0
	while map._view.is_gliding() and seconds < 3.0:
		map._process(1.0 / 60.0)
		seconds += 1.0 / 60.0
	check(map.range_m <= LEVELS.TACTICAL_ENTER,
		"and it arrives inside the tactical band, at %.0f m" % map.range_m)
	check(seconds < 1.5, "the flight is a second, not a journey: %.2f s" % seconds)
	check(map.semantic.level() == LEVELS.Level.TACTICAL, "which is the density where the members are drawn apart")
	check(map.centre.distance_to(Vector2(centroid.x, centroid.z)) < 200.0,
		"and stops on the thing that was tapped, %.0f m away" % map.centre.distance_to(Vector2(centroid.x, centroid.z)))
	var opened := 0
	for handle in members:
		var member := _member(map, int(handle))
		if not member.is_empty() and _handle_under(map, member["position"]) == int(handle):
			opened += 1
	check(opened == 4, "the members of the opened formation are individually tappable, got %d" % opened)
	check(_locks.is_empty() and _groups_tapped.is_empty(), "flying in is not a selection")


func _member(map: CANVAS, handle: int) -> Dictionary:
	for contact in map.contacts:
		if int(contact["handle"]) == handle:
			return contact
	return {}


## Phase 3, headless. The earlier sections assert that Territory is refused while
## nothing is behind it; this asserts the opposite half -- that the districts the
## shipped corridor actually has turn that key into a live layer, and that the
## batch the canvas would draw over them says what the brief asked for: claimed
## ground, contested ground carrying both claims, and a border whose arrows point
## the way the stronger side is pushing. Colour and opacity over real imagery are
## `tools/check_battle_map_terrain.gd`'s business.
func _check_the_war_arrives(map: CANVAS) -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	check(file != null, "the region catalog has to be readable for a war to exist")
	if file == null:
		return
	var corridor := {}
	for entry in (((JSON.parse_string(file.get_as_text()) as Dictionary)["regions"]) as Array):
		if String(entry.get("id", "")) == String(WAR_REGIONS.THEATRE):
			corridor = entry
	check(not corridor.is_empty(), "the corridor the game flies over must be in its own catalog")
	var geography := WAR_REGIONS.new()
	var situation := WAR_CONTROL.new()
	check(geography.load_theatre(corridor), "and the corridor must divide into districts")
	situation.setup(geography)
	map.follow_player = false
	map.centre = Vector2.ZERO
	map.set_war(geography, situation)
	check(map.territory.is_ready(), "the map must be able to draw the war it was handed")
	check(map.semantic.has_source(&"territory"), "so Territory is no longer a key with nothing behind it")
	check(map.semantic.toggle(&"territory"), "and its toggle is accepted")
	check(map.semantic.toggle(&"territory"), "and it switches back")
	_settle(map, 40000.0)
	var batch: Dictionary = map.territory.batch(
		map._projector(), map._visible_ground(), 1.0, map.pixels_per_metre())
	var fills: Array = batch["fills"]
	var wash := 0.0
	for fill in fills:
		wash = maxf(wash, float((fill["colour"] as Color).a))
	var hatched := 0
	for edge in batch["edges"]:
		if (edge["path"] as PackedVector2Array).size() == 2:
			hatched += 1
	var pushed := 0
	var unsettled := 0
	for mark in batch["front"]:
		if mark.has("arrow"):
			pushed += 1
		else:
			unsettled += 1
	check(fills.size() >= 8, "the corridor on screen is claimed by districts, got %d" % fills.size())
	check(wash > 0.0 and wash < 0.3, "a control area is a wash the terrain shows through, got %.2f" % wash)
	check(hatched > 0, "contested ground carries both claims as hatch strokes, got %d" % hatched)
	check(pushed > 0, "the line between the two sides says which way it is being pushed")
	check(unsettled > 0, "and an edge against ground nobody holds is drawn without a claim to direction")
	# The war is a density of information, so it goes away as the map closes: over
	# the suburb the layer fades out and draws nothing at all.
	_settle(map, 2600.0)
	check(map.semantic.alpha(&"territory") == 0.0, "a tactical view is not the map for a war")
	check(
		map.territory.batch(
			map._projector(), map._visible_ground(), map.semantic.alpha(&"territory"),
			map.pixels_per_metre())["fills"].is_empty(),
		"and a layer the density has faded out draws nothing")
	_settle(map, 20000.0)
	check(
		map.semantic.alpha(&"territory") == 1.0
		and not map.territory.batch(
			map._projector(), map._visible_ground(), 1.0, map.pixels_per_metre())["fills"].is_empty(),
		"and pulling back out to regional brings the same war in again")
	# A theatre with no authored regions is what `main` hands the map for any
	# corridor this one has not been drawn for yet: the layer goes back to being
	# honest about having nothing to say.
	map.set_war(null, null)
	check(not map.territory.is_ready(), "taking the war away must take the overlay with it")
	check(not map.semantic.has_source(&"territory"), "and Territory must say so on its key again")
	check(not map.semantic.toggle(&"territory"), "so it is refused, not faked, a second time")


## The box the map culls its ground layers to is built by intersecting what the
## camera can see with the theatre's own extent — and a Rect2 is a position plus a
## size, not two corners. Written from corners, the theatre's box ended at its
## centre, so everything east and south of it was culled before it could be drawn:
## an invisible bug unless something asks whether ground the camera is looking at
## counts as visible.
func _check_the_cull_box_reaches_the_ground_it_shows(map: CANVAS) -> void:
	map.follow_player = false
	map.centre = Vector2(18000.0, 18000.0)
	_settle(map, 4000.0)
	var seen: Rect2 = map._visible_ground()
	check(seen.has_point(map.centre), "the map must see the ground it is centred on, got %s" % seen)
	check(
		seen.end.x > 19000.0 and seen.end.y > 19000.0,
		"and it must reach the far side of the theatre rather than stopping at its middle, got %s" % seen)
