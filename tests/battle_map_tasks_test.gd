extends SceneTree

## Phase 6's map side, and the half of the acceptance the staff module cannot prove on its
## own: a mission is offered *where the job is*, so the board is a set of marks on the ground
## rather than a menu (§19), and a tap on one of them opens a card that can answer it. The two
## rules it is judged on are the two the brief keeps repeating: a mark stands on ground the
## registry already names, never on a position the map invented (§25), and a job that stops
## being true stops being drawn.

const MFD := preload("res://scripts/ui/tactical_mfd.gd")
const LEVELS := preload("res://scripts/battle_map/battle_map_layers.gd")
const TASKS := preload("res://scripts/battle_map/battle_map_tasks.gd")
const MISSIONS := preload("res://scripts/war/mission_director.gd")
const DIRECTOR := preload("res://scripts/war/war_director.gd")
const REGIONS := preload("res://scripts/war/war_regions.gd")
const CONTROL := preload("res://scripts/war/war_control.gd")
const OBJECTS := preload("res://scripts/war/war_objects.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

const CORRIDOR := {
	"id": "au_gold_coast_tweed_corridor",
	"center_latitude": -28.08,
	"center_longitude": 153.365,
	"world_size_m": 50000.0,
}
## A jet that is nobody's objective, put as far from every mark on the board as the theatre
## allows, so a tap on it is a question about the sky rather than about the staff.
const JET_CORNERS := [
	Vector2(-20000, -20000), Vector2(20000, -20000), Vector2(-20000, 20000),
	Vector2(20000, 20000), Vector2(0, -20000), Vector2(0, 20000),
	Vector2(-20000, 0), Vector2(20000, 0),
]
const BANDIT := 501

var failed := false
var _mfd: MFD
var _registry: OBJECTS
var _staff: MISSIONS
var _director: RefCounted
var _handles := {}
var _job := {}
var _bandit := Vector2.ZERO
var _asks: Array = []
var _strategic: Array = []
var _missions: Array = []
var _legs: Array = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# The panel's layer keys live in user://, and a run that was interrupted has no business
	# deciding what this one sees.
	DirAccess.remove_absolute(LEVELS.SETTINGS_FILE)
	_build()
	_check_the_board_comes_online()
	_settle(40000.0)
	_check_a_mark_stands_where_the_job_is()
	_check_the_view_culls_the_marks()
	_check_a_tap_opens_the_tasking()
	_check_accepting_flying_and_answering()
	_check_the_layer_goes_back_off()
	DirAccess.remove_absolute(LEVELS.SETTINGS_FILE)
	_mfd.free()
	if not failed:
		print("BATTLE_MAP_TASKS_TEST_PASS")
	quit(1 if failed else 0)


## ---------------------------------------------------------------------- the world handed in

## The corridor, the war over it, the staff's board running on the war's clock, and one
## launcher at every site -- which is the condition the phase-6 acceptance is written against,
## since a SEAD is only offered at a site that is standing.
func _build() -> void:
	var geography := REGIONS.new()
	check(geography.load_theatre(CORRIDOR), "the corridor must divide into districts")
	var control := CONTROL.new()
	control.setup(geography)
	_registry = OBJECTS.new()
	check(_registry.load_theatre(CORRIDOR, geography, control), "and the corridor must have objects in it")
	_director = DIRECTOR.new()
	check(_director.setup(control, geography, _registry), "and the war must take the theatre")
	_director.set_seed(1004)
	_staff = MISSIONS.new()
	check(_staff.setup(_director, _registry, geography), "and the staff must be seated over it")
	_handles = _stand_every_site(_registry)
	_mfd = MFD.new()
	root.add_child(_mfd)
	root.size = Vector2i(900, 600)
	_mfd.size = Vector2(900, 600)
	_mfd.map.size = Vector2(900, 600)
	_mfd.contact_selected.connect(func(handle: int) -> void: _asks.append(handle))
	_mfd.waypoint_requested.connect(func(point: Vector2) -> void: _legs.append(point))
	_mfd.map.strategic_selected.connect(func(id: int) -> void: _strategic.append(id))
	_mfd.map.mission_selected.connect(func(id: String) -> void: _missions.append(id))
	_mfd.open_panel()
	# Opening the panel recentres the map on the aircraft and takes the follow back, so the
	# camera is only the test's to move after that.
	_mfd.map.follow_player = false
	_mfd.map.set_war(geography, control)
	_mfd.map.set_objects(_registry)
	_mfd.set_tasks(_staff)
	# The job this file is about: the first SEAD the war raises, flown at the launcher the
	# weapons tracker already answers to for that site.
	for tick in range(40):
		_director.tick()
		_staff.tick(_director.tick_number())
		for record in _staff.available():
			var offer: Dictionary = record
			if int(offer["kind"]) == MISSIONS.Kind.SEAD:
				_job = offer
				break
		if not _job.is_empty():
			break
	check(not _job.is_empty(), "a standing site has to put a SEAD on the board")
	if _job.is_empty():
		quit(1)
		return
	_bandit = _quiet_ground()
	_feed(_staff.primary_entity(_id()))


## The tracks the map is told about: the launcher under the tasking's own objective when one is
## asked for, and a jet that is nobody's objective.
func _feed(launcher: int) -> void:
	var tracks := [TRACKER.contact(
		BANDIT, TRACKER.Kind.AIR_JET,
		Vector3(_bandit.x, 800, _bandit.y), Vector3(0, 0, -220))]
	if launcher >= 0:
		var at: Vector2 = _staff.position_of(_id())
		tracks.append(TRACKER.contact(launcher, TRACKER.Kind.GROUND_LAUNCHER, Vector3(at.x, 30, at.y)))
	_mfd.map.set_state(Vector3.ZERO, 0.0, tracks, -1, null)


## The corner of the theatre furthest from every mark on the board.
func _quiet_ground() -> Vector2:
	var best := JET_CORNERS[0]
	var furthest := -1.0
	for candidate in JET_CORNERS:
		var nearest := INF
		for record in _staff.missions():
			nearest = minf(nearest, _staff.position_of(String(record["id"])).distance_to(candidate))
		if nearest > furthest:
			furthest = nearest
			best = candidate
	return best


func _stand_every_site(registry: OBJECTS) -> Dictionary:
	var handles := {}
	var positions := []
	var handle := 1
	for record in registry.of_type(OBJECTS.Type.SAM_SITE):
		var site: Dictionary = record
		var name := "%s LAUNCHER" % String(site["detail"]["site"])
		positions.append({"id": handle, "name": name})
		handles[handle] = name
		handle += 1
	registry.bind_launchers(positions)
	return handles


## The same launchers, minus the one a weapon reached.
func _launcher_list(skip: int) -> Array:
	var positions := []
	for handle in _handles:
		if int(handle) == skip:
			continue
		positions.append({"id": int(handle), "name": String(_handles[handle])})
	positions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return positions


func _id() -> String:
	return String(_job["id"])


func _map() -> Control:
	return _mfd.map


func _settle(metres: float) -> void:
	_map().set_range(metres)
	for frame in range(90):
		_map()._process(1.0 / 60.0)


func _batch() -> Array:
	var map: Control = _map()
	return map.tasks.batch(
		map._projector(), map._visible_ground(), map.semantic.alpha(&"missions"),
		map.semantic.level(), map.pixels_per_metre())


func _item_of(items: Array, id: String) -> Dictionary:
	for item in items:
		if String(item["id"]) == id:
			return item
	return {}


func _card() -> String:
	return String(_mfd._card_lines.text)


func _tap(world: Vector2) -> void:
	_map().select_at(_map().world_to_screen(world))


func _refresh_card() -> void:
	_mfd._card_elapsed = 0.0
	_mfd._process(MFD.CARD_SECONDS + 0.01)


## The shortest distance from a mark's own point to one of its strokes, in screen pixels: what
## a bracket is drawn around, and how tightly.
func _reach(path: Variant, at: Vector2) -> float:
	var nearest := INF
	for point in (path as PackedVector2Array):
		nearest = minf(nearest, (point as Vector2).distance_to(at))
	return nearest


## ---------------------------------------------------------------------- the checks

## A layer is only on the panel when something is behind it, and a board with no offers left is
## a layer with nothing drawn rather than a layer that does not exist.
func _check_the_board_comes_online() -> void:
	var map: Control = _map()
	check(map.tasks.is_ready(), "a staff seated over a war is a layer the map can draw")
	check(map.semantic.has_source(&"missions"), "so Missions is no longer a key with nothing behind it")
	check(map.semantic.is_enabled(&"missions"), "and a layer that came online undecided is drawn")
	check(
		map.tasks.count() == _staff.board().size(),
		"the map reads the staff's own board, %d against %d" % [map.tasks.count(), _staff.board().size()])
	check(map.semantic.toggle(&"missions"), "the key switches it")
	_settle(40000.0)
	check(map.semantic.alpha(&"missions") == 0.0, "off, and it fades out")
	check(_batch().is_empty(), "and a layer the pilot switched off draws nothing")
	_missions.clear()
	_asks.clear()
	_tap(_staff.position_of(_id()))
	check(_missions.is_empty(), "and a layer that is not drawn cannot be tapped")
	check(map.tasks.of("M9999").is_empty(), "a job the board never had has no record to read")
	check(not map.tasks.position_of("M9999").is_finite(), "and no ground to fly to")
	check(map.tasks.entity_of("M9999") < 0, "and no weapon to hand over")
	check(map.semantic.toggle(&"missions"), "and back on again")
	_settle(40000.0)
	check(map.semantic.alpha(&"missions") == 1.0, "with the fades caught up")
	var items := _batch()
	check(not items.is_empty(), "and the board is on the map, got %d marks" % items.size())


## §19 and §25 in one pass: every mark is at the place the staff says the job is, that place is
## a registry object's own ground when the job has an objective, and nothing about a mission is
## a second copy of a fact the map already has.
func _check_a_mark_stands_where_the_job_is() -> void:
	var map: Control = _map()
	var items := _batch()
	var view: Rect2 = map._visible_ground().grow(6000.0)
	var culled := 0
	for record in _staff.missions():
		var mission: Dictionary = record
		if view.has_point(_staff.position_of(String(mission["id"]))):
			culled += 1
	check(
		culled == items.size(),
		"the marks drawn are the marks on the board, %d against %d" % [culled, items.size()])
	for record in _staff.missions():
		var mission: Dictionary = record
		var id := String(mission["id"])
		var at: Vector2 = _staff.position_of(id)
		if not view.has_point(at):
			continue
		var item := _item_of(items, id)
		check(not item.is_empty(), "%s is drawn where the staff puts it" % String(mission["callsign"]))
		if item.is_empty():
			continue
		var where: Vector2 = map.world_to_screen(at)
		check(
			(item["at"] as Vector2).distance_to(where) < 0.01,
			"%s is drawn on the ground it was raised over, %.1f px out" \
				% [String(mission["callsign"]), (item["at"] as Vector2).distance_to(where)])
		check(
			where.is_finite() and Rect2(Vector2.ZERO, map.size).has_point(where),
			"and that ground is inside the map the pilot is looking at")
		check(
			(item["paths"] as Array).size() >= 4,
			"as a bracket round it rather than an icon on it, got %d strokes" \
				% (item["paths"] as Array).size())
		check(
			String(item["label"]) == "%s %s" % [
				String(mission["callsign"]), String(mission["type"])],
			"named with the call sign and the job at theatre range, got %s" % String(item["label"]))
		check(
			not String(item["label"]).contains("· P"),
			"and the priority left off until the map closes in, got %s" % String(item["label"]))
		if String(mission["status"]) != MISSIONS.AVAILABLE:
			continue
		var colour: Color = item["colour"]
		check(colour.r > colour.b, "an offer nobody has taken is drawn in the amber of a question")
		check(float(colour.a) > 0.9, "and as strongly as anything else on the board")
	var site := _staff.primary_target(_id())
	check(not site.is_empty(), "and the SEAD names an object the registry has")
	check(
		_staff.position_of(_id()).distance_to(site["world_position"]) < 0.01,
		"standing on the ground that object is at, not beside a copy of it")
	check(
		map.mission_object(_id()) == _staff.mission(_id()),
		"the map's record for a job is the staff's own, not a snapshot of the tap")
	map.centre = _staff.position_of(_id())
	_settle(4000.0)
	var close := _item_of(_batch(), _id())
	check(not close.is_empty(), "and the job is still drawn in the tactical band it is flown in")
	check(
		String(close.get("label", "")) == "%s %s · P%d" % [
			String(_job["callsign"]), String(_job["type"]), int(_job["priority"])],
		"and a tactical map says what the job is worth, got %s" % String(close.get("label", "")))
	_settle(40000.0)


## The same cull box the rest of the map uses, so a board of hundreds stays usable.
func _check_the_view_culls_the_marks() -> void:
	var map: Control = _map()
	map.centre = _staff.position_of(_id()) + Vector2(0, 90000)
	_settle(2000.0)
	check(_item_of(_batch(), _id()).is_empty(), "a mark the camera has flown away from draws nothing")
	map.centre = _staff.position_of(_id())
	_settle(2000.0)
	check(not _item_of(_batch(), _id()).is_empty(), "and flying back puts it on the map")
	map.centre = Vector2.ZERO
	_settle(40000.0)


## The tap the brief asks for: a finger on a tasking opens that tasking, and a finger on an
## airframe that is not what the job is about still gets the airframe.
func _check_a_tap_opens_the_tasking() -> void:
	var map: Control = _map()
	var id := _id()
	var entity := _staff.primary_entity(id)
	check(entity >= 0, "the launcher the job is about is a track the flying world answers to")
	map.centre = _bandit
	_settle(4000.0)
	_asks.clear()
	_strategic.clear()
	_missions.clear()
	_tap(_bandit)
	check(_asks == [BANDIT], "a jet with no tasking over it is still just a jet, got %s" % [_asks])
	check(_missions.is_empty(), "and it does not arrive as a mission")
	map.centre = _staff.position_of(id)
	_settle(4000.0)
	_asks.clear()
	_strategic.clear()
	_missions.clear()
	_tap(_staff.position_of(id))
	check(_missions == [id], "a tap on the bracket opens the tasking, got %s" % [_missions])
	check(
		_asks.is_empty() and _strategic.is_empty(),
		"and it is one decision rather than three: no lock, no object card")
	var text := _card()
	check(_mfd._card.visible, "with the card up")
	check(
		text.contains("%s · %s · P%d · %s" % [
			String(_job["callsign"]), String(_job["type"]), int(_job["priority"]), MISSIONS.AVAILABLE]),
		"the card is headed with the radio check, got %s" % text)
	check(text.contains(String(_job["briefing"])), "and the briefing it was raised with, got %s" % text)
	check(text.contains("TRACK %d" % entity), "naming the launcher it is about, got %s" % text)
	check(text.contains("PRIMARY %s" % String(_job["target_name"])), "and the objective by the registry's name, got %s" % text)
	check(text.contains("THREAT "), "with the threat the staff published")
	check(text.contains("EFFECT "), "and what flying it is for")
	check(text.contains("WINDOW "), "and how long the offer stands")
	check(String(_mfd._assign.text) == "Accept", "ACCEPT is the key that answers it")
	check(_mfd._objective.visible, "and the objective is one tap away rather than a search")
	_strategic.clear()
	_missions.clear()
	_mfd._objective.pressed.emit()
	check(
		int(_mfd._subject.get("object", -1)) == int(_job["primary_target"]),
		"a tap on Target moves the card onto the object the mission names, got %s" % [_mfd._subject])
	check(
		_card().contains(String(_registry.of(int(_job["primary_target"]))["name"])) \
			and _card().contains("SAM SITE"),
		"which is the registry's own intelligence card for that place, not the staff's: %s" % _card())
	check(_missions.is_empty(), "and reading the target is not a second tasking")
	# §19's middle key: the job is planned onto the ground it is about, through the same
	# waypoint seam a hand-drawn leg uses.
	_mfd._mission_selected(id)
	_legs.clear()
	_missions.clear()
	check(_mfd._route.visible, "and PLAN ROUTE stands on a job that can still be flown")
	_mfd._route.pressed.emit()
	check(_legs.size() == 1, "Route lays one leg, got %s" % [_legs])
	if _legs.size() == 1:
		check(
			(_legs[0] as Vector2).distance_to(_staff.position_of(id)) < 0.01,
			"onto the ground the job is about, not beside a copy of it")
	check(_missions.is_empty(), "and planning a route is not a second tasking")
	var seconds := 0.0
	map._focus_at(map.world_to_screen(_bandit))
	while map._view.is_gliding() and seconds < 4.0:
		map._process(1.0 / 60.0)
		seconds += 1.0 / 60.0
	check(
		map.centre.distance_to(_bandit) < 2000.0,
		"a double tap on a track flies to the track rather than to its neighbours, %.0f m out" \
			% map.centre.distance_to(_bandit))
	_settle(40000.0)


## The acceptance loop at the end of a finger: ACCEPT takes it, FLY commits the sortie and hands
## the weapon the same handle the visor would have given, and the answer at the end comes from
## the world rather than from a script.
func _check_accepting_flying_and_answering() -> void:
	var map: Control = _map()
	var id := _id()
	var entity := _staff.primary_entity(id)
	var site := _staff.primary_target(id)
	var at := _staff.position_of(id)
	map.centre = at
	_settle(4000.0)
	_mfd._mission_selected(id)
	check(_mfd._card.visible, "the card opens on a selected tasking")
	var offered := _item_of(_batch(), id)
	check(not offered.is_empty(), "an offer on the board is drawn before anyone takes it")
	_mfd._assign.pressed.emit()
	check(String(_staff.mission(id)["status"]) == MISSIONS.ASSIGNED, "ACCEPT takes the job")
	check(String(_mfd._assign.text) == "Taken", "and the key says so, got %s" % String(_mfd._assign.text))
	check(_mfd._assign.disabled, "a job already taken cannot be taken again from the card")
	_settle(4000.0)
	var taken := _item_of(_batch(), id)
	var offered_strokes: Array = offered.get("paths", [])
	var taken_strokes: Array = taken.get("paths", [])
	check(
		taken_strokes.size() > offered_strokes.size(),
		"and the mark closes on itself once it is ours, got %d strokes against %d" \
			% [taken_strokes.size(), offered_strokes.size()])
	var ours: Color = taken["colour"]
	check(ours.b > ours.r, "in the blue of a tasking rather than the amber of an offer")
	_asks.clear()
	_mfd._fly.pressed.emit()
	check(String(_staff.mission(id)["status"]) == MISSIONS.ACTIVE, "FLY commits the sortie")
	check(_asks == [entity], "and hands the weapon the launcher at the objective, got %s" % [_asks])
	check(_strategic.is_empty(), "without asking the registry for a second opinion of it")
	var seconds := 0.0
	while map._view.is_gliding() and seconds < 4.0:
		map._process(1.0 / 60.0)
		seconds += 1.0 / 60.0
	check(
		map.centre.distance_to(site["world_position"]) < 500.0,
		"and flies the camera onto the ground the job is about, %.0f m out" \
			% map.centre.distance_to(site["world_position"]))
	_refresh_card()
	check(String(_mfd._assign.text) == "Flying", "the card reads as flown, got %s" % String(_mfd._assign.text))
	var flown := _item_of(_batch(), id)
	check(not flown.is_empty(), "a flown job stays on the map while it is being flown")
	var flown_strokes: Array = flown.get("paths", [])
	var screen: Vector2 = map.world_to_screen(at)
	check(
		not flown_strokes.is_empty() and taken_strokes.size() > 0 \
			and _reach(flown_strokes[0], screen) < _reach(taken_strokes[0], screen),
		"with the bracket drawn tighter than a taken one, so a committed sortie is legible")
	# The weapon arrives. The launcher field is the only thing that knows a site has lost a
	# launcher, so the mission is settled through the same seam the flying world reports on.
	_registry.bind_launchers(_launcher_list(entity))
	check(
		String(site["operational_state"]) == OBJECTS.DESTROYED,
		"the site is down as far as the registry is concerned")
	_director.tick()
	_staff.tick(_director.tick_number())
	var closed := _staff.mission(id)
	check(
		String(closed["status"]) == MISSIONS.SUCCESS,
		"and the mission flown at it succeeds because the world changed, got %s: %s" \
			% [String(closed["status"]), String(closed.get("reason", ""))])
	_refresh_card()
	check(
		_card().contains("OUTCOME %s" % MISSIONS.SUCCESS),
		"the card reads the answer rather than the ask, got %s" % _card())
	var settled := _item_of(_batch(), id)
	check(not settled.is_empty(), "and the mark is still up while a card is open on it")
	check(
		float(settled["colour"].a) < 0.6,
		"drawn down, so a settled job cannot be read as an outstanding one, got %.2f" \
			% float(settled["colour"].a))
	for tick in range(MISSIONS.RESOLVED_KEEP + 2):
		_director.tick()
		_staff.tick(_director.tick_number())
	_settle(4000.0)
	check(_item_of(_batch(), id).is_empty(), "then it leaves the board, and the map with it")
	check(map.tasks.of(id).is_empty(), "and the card has nothing left to read")
	_refresh_card()
	check(not _mfd._card.visible, "so the card that was open on it closes instead of reporting a stale one")


## A theatre with no war run over it gets no layer, no marks and no invented board -- the same
## honesty the objects layer is asked for.
func _check_the_layer_goes_back_off() -> void:
	var map: Control = _map()
	var id := _id()
	_mfd._mission_selected("M4242")
	check(not _mfd._card.visible, "a card opened on a job the board never had stays shut")
	_feed(-1)
	_mfd.set_tasks(null)
	check(not map.tasks.is_ready(), "taking the staff away takes the layer with it")
	check(not map.semantic.has_source(&"missions"), "and the key says so on the panel")
	check(not map.semantic.toggle(&"missions"), "so the toggle is refused, not faked")
	_settle(40000.0)
	check(_batch().is_empty(), "and nothing is drawn")
	_missions.clear()
	_asks.clear()
	_strategic.clear()
	_tap(_staff.position_of(id))
	check(_missions.is_empty(), "with no tasking to tap into")
	check(_asks.is_empty(), "and a mark that is not drawn cannot swallow a track under it either")
	check(not _strategic.is_empty(), "the ground underneath answers as it always did, got %s" % [_strategic])
	_mfd.set_tasks(_staff)
	_director.tick()
	_staff.tick(_director.tick_number())
	check(
		map.tasks.is_ready() and map.semantic.has_source(&"missions"),
		"and the next theatre with a war run over it brings the layer back")
	map.set_missions(null)
	check(not map.tasks.is_ready(), "the map takes the same refusal on its own seam")
	_mfd._mission_selected(id)
	check(not _mfd._card.visible, "and a card has nothing to open on a table that is gone")
	_mfd.close_panel()
	check(not _mfd._card.visible, "and closing the map takes the tasking card with it")
