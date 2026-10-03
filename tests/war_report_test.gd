extends SceneTree

## §37's acceptance: the debug read-out shows the campaign's own numbers, and shows them the same
## way to whoever asks.
##
## The brief lists what the panel has to show: the tick, who owns what, the air and ground numbers,
## what each commander is after and why, what each staff has on its board and why, the aircraft, the
## objects, and the reason territory changed. All but the last already exist as tables the war
## publishes for the map, the MFD and the save, so the risk in this phase is not a missing number
## but a second version of one -- rounded, filtered, or recomputed from somewhere else. Section one
## therefore asserts against the modules themselves rather than against the report's own output:
## every field the panel prints has to be the value the module that owns it publishes for the same
## key at the same tick.
##
## Section two is the one genuinely new surface. A change reason is a sentence the director writes
## at the instant the owner flips, out of the thresholds and the two presences it had already
## computed for the ownership test, and it cannot be recomputed afterwards: by the next tick the
## balance it was read off is gone. So this asks that the sentence names the rule that fired and
## quotes the numbers on its own row, that a contested hold and a turnover do not read alike, that
## the log stays inside its bound and in tick order, and that it survives a save and a reload --
## including a reload of a file written before any of this existed.
##
## Section three asks the screen and the socket the same question. Both read this one module, so
## the overlay's text has to be the panel's text, and both have to answer with nothing seated
## rather than crash: a debug panel that dies before a theatre loads never gets used for the bugs
## that happen at load.

const REPORT := preload("res://scripts/war/war_report.gd")
const OVERLAY := preload("res://scripts/ui/war_debug_overlay.gd")
const DIRECTOR := preload("res://scripts/war/war_director.gd")
const REGIONS := preload("res://scripts/war/war_regions.gd")
const CONTROL := preload("res://scripts/war/war_control.gd")
const OBJECTS := preload("res://scripts/war/war_objects.gd")
const COMMANDER := preload("res://scripts/war/faction_commander.gd")
const MISSIONS := preload("res://scripts/war/mission_director.gd")
const SAVE := preload("res://scripts/war/campaign_save.gd")

const CORRIDOR := {
	"id": "au_gold_coast_tweed_corridor",
	"center_latitude": -28.08,
	"center_longitude": 153.365,
	"world_size_m": 50000.0,
}

## Far enough for the line to have moved and for both staffs to have raised something. The director
## needs `SETTLE_TICKS` of settled ground before it hands a district over, and the commanders need a
## few ticks of air before they send anything at it.
const HORIZON := 120

var failed := false


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var campaign := _seat(4242)
	var war: RefCounted = campaign["war"]
	for tick in range(HORIZON):
		war.tick()
		campaign["blue"].tick(war.tick_number())
		campaign["red"].tick(war.tick_number())
		campaign["own_board"].tick(war.tick_number())
		campaign["foe_board"].tick(war.tick_number())
	var report: Dictionary = campaign["report"].sample()
	check(not report.is_empty(), "a seated campaign produced no report at all")
	_check_list(report)
	_check_against_modules(campaign, report)
	_check_reasons(war, report)
	_check_panel(campaign, report)
	_check_after_reload(campaign)
	await _check_screen(campaign)
	if failed:
		print("WAR_REPORT_TEST_FAIL")
		quit(1)
		return
	print("WAR_REPORT_TEST_PASS")
	quit(0)


## ------------------------------------------------------------------ every line item is present
func _check_list(report: Dictionary) -> void:
	for key in ["theatre", "tick", "tick_length", "until_tick", "seed", "districts", "front",
			"changes", "held", "air", "resources", "objects", "friendly", "enemy"]:
		check(report.has(key), "the report is missing §37's \"%s\"" % key)
	check(String(report["theatre"]) == String(CORRIDOR["id"]),
		"the report names a theatre the campaign is not in")
	check(int(report["tick"]) == HORIZON, "the report does not show the simulation tick")
	check(float(report["tick_length"]) > 0.0 and float(report["until_tick"]) >= 0.0 \
			and float(report["until_tick"]) <= float(report["tick_length"]),
		"the report's countdown is not inside the tick it runs on")
	check(int(report["seed"]) == 4242, "the report does not show the seed the war ran on")
	var held: Dictionary = report["held"]
	var tallied := 0
	for owner in CONTROL.OWNERS:
		check(held.has(String(owner)), "nobody counted the districts held by %s" % String(owner))
		tallied += int(held.get(String(owner), 0))
	check(tallied == int(report["regions"]),
			"the tally covers %d owners of %d regions" % [tallied, int(report["regions"])])
	check((report["districts"] as Array).size() <= int(report["regions"]),
		"the war fights over more districts than the map has regions")
	check((report["air"] as Dictionary).has(CONTROL.FRIENDLY) \
			and (report["air"] as Dictionary).has(CONTROL.ENEMY),
		"the air over the theatre is only counted for one side")
	for side in ["friendly", "enemy"]:
		var bloc: Dictionary = report[side]
		for key in ["ready", "faction", "force", "focus", "operations", "board", "pattern"]:
			check(bloc.has(key), "the %s commander is missing \"%s\"" % [side, key])
		check(bool(bloc["ready"]), "the %s commander was never seated" % side)
		check(not (bloc["operations"] as Array).is_empty(),
			"the %s commander is fighting for nothing" % side)
		check(not (bloc["board"] as Array).is_empty(),
			"the %s staff has no missions to explain" % side)
		for record in bloc["operations"]:
			var operation: Dictionary = record
			for key in ["label", "score", "reason", "value", "urgency", "exposure", "force",
					"priority", "reserve"]:
				check(operation.has(key), "an operation is missing \"%s\"" % key)
			check(not String(operation["reason"]).is_empty(),
				"an operation does not say why the commander wants it")
		for record in bloc["board"]:
			var card: Dictionary = record
			for key in ["id", "callsign", "type", "district", "status", "operation", "briefing",
					"effect"]:
				check(card.has(key), "a card is missing the §37 field \"%s\"" % key)
			check(not String(card["briefing"]).is_empty(),
					"a card does not say why it was generated")
	var purse: Array = report["resources"]
	check(purse.size() == 2, "the purse is not counted for both sides")
	for key in ["faction", "supply", "spent", "airframes", "ground_lost"]:
		check((purse[0] as Dictionary).has(key), "the purse is missing \"%s\"" % key)
	var objects: Array = report["objects"]
	check(not objects.is_empty(), "no strategic object was read out")
	for key in ["id", "type", "name", "faction", "district", "health", "state", "discovered"]:
		check((objects[0] as Dictionary).has(key), "an object row is missing \"%s\"" % key)
	var front: Array = report["front"]
	check(not front.is_empty(), "no front segment was read out")
	for key in ["from", "to", "kind", "length", "middle", "pressure"]:
		check((front[0] as Dictionary).has(key), "a front segment is missing \"%s\"" % key)


## ---------------------------------------------------------------- the report cannot disagree
## Every number is compared to the module that owns it, at the same tick, from the same dictionary.
## A report that rounded, re-derived or cached would fail here rather than on a screen later.
func _check_against_modules(campaign: Dictionary, report: Dictionary) -> void:
	var war: RefCounted = campaign["war"]
	var control: RefCounted = campaign["control"]
	var registry: RefCounted = campaign["objects"]
	var districts: Array = war.districts()
	check((report["districts"] as Array).size() == districts.size(),
		"the report does not carry every district the war has")
	for record in report["districts"]:
		var row: Dictionary = record
		var district_id := String(row["id"])
		var live: Dictionary = war.district(district_id)
		var published: Dictionary = control.state_of(district_id)
		check(districts.has(district_id), "the report invented a district: %s" % district_id)
		check(String(row["owner"]) == String(live["owner"]),
			"%s is printed with an owner the war does not have" % district_id)
		check(is_equal_approx(float(row["ground"]), float(live["ground"])),
			"%s is printed with a re-derived ground balance" % district_id)
		check(is_equal_approx(float(row["air"]), float(live["air"])),
			"%s is printed with a re-derived air balance" % district_id)
		check(is_equal_approx(float(row["ground_control"]), float(published["ground_control"])),
			"%s is printed with a share the control table does not publish" % district_id)
		check(is_equal_approx(float(row["air_control"]), float(published["air_control"])),
			"%s is printed with a share the control table does not publish" % district_id)
		check(is_equal_approx(float(row["fire"]), float(live["under_fire"])),
			"%s is printed with a fire level the tick does not have" % district_id)
		for faction in [CONTROL.FRIENDLY, CONTROL.ENEMY]:
			var key := "blue" if faction == CONTROL.FRIENDLY else "red"
			check(is_equal_approx(float(row[key]), float(war.presence(district_id, faction))),
					"%s is printed with a %s presence nobody measured" % [district_id, faction])
	var air: Dictionary = report["air"]
	for faction in [CONTROL.FRIENDLY, CONTROL.ENEMY]:
		check(is_equal_approx(float(air[faction]), float(war.air_superiority(faction))),
			"%s's air over the theatre was adjusted on the way out" % faction)
	var seen := {}
	for record in registry.objects():
		var facility: Dictionary = record
		seen[int(facility["id"])] = facility
	for record in report["objects"]:
		var row: Dictionary = record
		var object_id := int(row["id"])
		check(seen.has(object_id), "the panel invented object %d" % object_id)
		if seen.has(object_id):
			var live_object: Dictionary = seen[object_id]
			check(String(row["state"]) == String(live_object["operational_state"]),
				"object %d is printed in a state its registry does not have" % object_id)
			check(is_equal_approx(float(row["health"]), float(live_object["health"])),
				"object %d is printed at a health its registry does not have" % object_id)
	for record in report["front"]:
		var segment: Dictionary = record
		var strong := String(segment["from"])
		var weak := String(segment["to"])
		check(is_equal_approx(float(segment["ground_from"]),
			float(control.state_of(strong)["ground_control"])),
			"the front quotes ground the control table is not holding at %s" % strong)
		check(is_equal_approx(float(segment["ground_to"]),
			float(control.state_of(weak)["ground_control"])),
			"the front quotes ground the control table is not holding at %s" % weak)
	for side in ["friendly", "enemy"]:
		var bloc: Dictionary = report[side]
		var staff: RefCounted = campaign["blue"] if String(bloc["faction"]) == CONTROL.FRIENDLY \
				else campaign["red"]
		var board: RefCounted = campaign["own_board"] if staff == campaign["blue"] \
				else campaign["foe_board"]
		check((bloc["operations"] as Array).size() <= (staff.operations() as Array).size(),
			"a commander is shown more operations than it is fighting")
		check((bloc["board"] as Array).size() == (board.board() as Array).size(),
			"a staff's board changed size on the way to the report")
		check(is_equal_approx(float(bloc["force"]), float(staff.available_force())),
			"a commander's force was adjusted on the way to the report")
		var offered := {}
		for entry: Variant in board.board():
			var live_card: Dictionary = entry
			offered[String(live_card["id"])] = live_card
		for record in bloc["board"]:
			var card: Dictionary = record
			var card_id := String(card["id"])
			check(offered.has(card_id), "the report shows a card its staff has retired")
			if offered.has(card_id):
				check(String(card["status"]) == String(offered[card_id]["status"]),
					"card %s is printed in a state its staff does not have" % card_id)


## ------------------------------------------------------------------- why the territory changed
func _check_reasons(war: RefCounted, report: Dictionary) -> void:
	var changes: Array = report["changes"]
	check(not changes.is_empty(),
		"nothing has changed hands by tick %d, so the reason log proves nothing" % HORIZON)
	var turned := 0
	var shared := 0
	var oldest := 0
	var owners := {}
	for record in changes:
		var change: Dictionary = record
		for key in ["tick", "id", "name", "from", "to", "ground", "air", "blue", "red", "latched",
				"reason"]:
			check(change.has(key), "a change row is missing \"%s\"" % key)
		var reason := String(change["reason"])
		var title := String(change["name"])
		check(int(change["tick"]) >= oldest, "the reason log is not in tick order")
		check(int(change["tick"]) <= int(war.tick_number()), "a change is stamped in the future")
		check(int(change["latched"]) >= DIRECTOR.SETTLE_TICKS,
			"a change latched for fewer ticks than the director requires")
		check(String(change["from"]) != String(change["to"]), "a district changed into what it was")
		check(title == String(war.district(String(change["id"]))["name"]),
			"a change row names a district the geography does not have")
		check(reason.contains(title), "a change reason does not name the district it is about")
		if String(change["to"]) == CONTROL.CONTESTED:
			shared += 1
			check(reason.contains("is contested"),
				"a contested hold does not say the district is contested")
			check(reason.contains("%.2f" % float(change["blue"])) \
					and reason.contains("%.2f" % float(change["red"])),
				"a contested hold does not quote the two presences it was read off")
		else:
			turned += 1
			check(reason.contains("turned to %s" % String(change["to"])),
				"a turnover does not say which way the district turned")
			check(reason.contains("%d settled ticks" % int(change["latched"])),
				"a turnover does not say how long the ground was settled for")
			check(reason.contains("%+.2f" % float(change["ground"])),
				"a turnover does not quote the balance that carried it")
		# The log is bounded, so the last entry it still holds for a district has to agree with the
		# map. Anything older than the window it dropped is allowed to be history.
		if not owners.has(String(change["id"])) \
				or int(change["tick"]) > int(owners[String(change["id"])]["tick"]):
			owners[String(change["id"])] = change
	check(turned > 0, "no district was ever handed over, so the ownership rule is unread")
	check(shared > 0, "no district was ever contested, so the two rules read as one")
	check(changes.size() <= DIRECTOR.CHANGE_KEEP,
		"the reason log grew past the %d entries it is kept inside" % DIRECTOR.CHANGE_KEEP)
	for district_id in owners:
		var latest: Dictionary = owners[district_id]
		check(String(latest["to"]) == String(war.district(district_id)["owner"]),
			"%s is logged as turning to %s and the map still says %s" % [district_id,
				String(latest["to"]), String(war.district(district_id)["owner"])])


## ------------------------------------------------------------------------ the panel as text
func _check_panel(campaign: Dictionary, report: Dictionary) -> void:
	var staff: RefCounted = campaign["report"]
	var panel := String(staff.text())
	check(panel.contains("WAR %s" % String(report["theatre"])), "the panel has no headline")
	check(panel.contains("tick %d" % int(report["tick"])), "the panel does not show the tick")
	check(panel.contains("seed %d" % int(report["seed"])), "the panel does not show the seed")
	check(panel.contains("HELD"), "the panel does not tally who holds what")
	check(panel.contains("FRIENDLY COMMANDER"), "the panel does not show Blue's commands")
	check(panel.contains("ENEMY COMMANDER"), "the panel does not show Red's commands")
	var held: Dictionary = report["held"]
	check(panel.contains("FRIENDLY %d" % int(held[CONTROL.FRIENDLY])) \
			and panel.contains("ENEMY %d" % int(held[CONTROL.ENEMY])),
		"the panel's tally is not the tally the report carries")
	check(panel.contains("over %d of %d regions" % [(report["districts"] as Array).size(),
			int(report["regions"])]),
		"the panel prints a tally without saying what fraction of the map it covers")
	var lines := panel.split("\n")
	check(lines.size() > 12, "the panel is too short to be the whole read-out")
	for line: String in lines:
		check(not line.strip_edges().is_empty(), "the panel carries a blank line")
		check(line.length() <= REPORT.PANEL_WIDTH,
			"a panel line runs off the screen: %s" % line.left(36))
	for record in staff._hot_districts(report["districts"]):
		var row: Dictionary = record
		check(panel.contains(String(row["name"]).left(REPORT.PANEL_NAME)),
			"the panel drops the district it sorted to the top: %s" % String(row["id"]))
	for record in staff._recent_changes(report["changes"]):
		var change: Dictionary = record
		check(panel.contains("[%d]" % int(change["tick"])),
			"the panel drops a change the campaign remembers")
		check(panel.contains(String(change["name"])), "the panel drops the place a change is about")
	for record in (report["friendly"] as Dictionary)["board"]:
		var card: Dictionary = record
		if (report["friendly"]["board"] as Array).find(card) < REPORT.PANEL_MISSIONS:
			check(panel.contains(String(card["id"])), "the panel drops a card it should show")


## The reason log is part of the campaign rather than of the session: the save has to carry its
## sentences, and a file written before §37 has to stay loadable without them.
func _check_after_reload(campaign: Dictionary) -> void:
	var war: RefCounted = campaign["war"]
	var changes: Array = war.changes()
	check(not changes.is_empty(), "there is nothing here to carry across a reload")
	var mirror := _seat(99)
	var save := SAVE.new()
	var state: Dictionary = save.capture(String(war.theatre()), campaign["objects"], war,
		campaign["blue"], campaign["red"], campaign["own_board"], campaign["foe_board"])
	check(not state.is_empty(), "the campaign could not be written out at all: %s" % save.refusal())
	check(save.apply(state, mirror["objects"], mirror["war"], mirror["blue"], mirror["red"],
		mirror["own_board"], mirror["foe_board"]),
		"the campaign refused to reload with a log: %s" % save.refusal())
	var carried: Array = mirror["war"].changes()
	check(carried.size() == changes.size(),
		"a reload changed how many reasons the war remembers")
	for index in range(carried.size()):
		var before: Dictionary = changes[index]
		var after: Dictionary = carried[index]
		for key in before:
			check(before[key] == after[key],
				"a reload rewrote the change field \"%s\"" % key)
		check(not String(after["reason"]).is_empty(), "a reload lost a reason sentence")
		check(not after.has("name"),
			"a save carried a copy of a name the geography the map loaded already knows")
	mirror["war"].tick()
	check(int(mirror["war"].tick_number()) == HORIZON + 1,
		"a reloaded campaign restarted the clock instead of carrying it on")
	var bare: Dictionary = save.capture(String(war.theatre()), campaign["objects"], war,
		campaign["blue"], campaign["red"], campaign["own_board"], campaign["foe_board"])
	bare["war"].erase("changes")
	var orphan := _seat(7)
	check(save.apply(bare, orphan["objects"], orphan["war"], orphan["blue"], orphan["red"],
		orphan["own_board"], orphan["foe_board"]),
		"a save written before the reason log existed was refused: %s" % save.refusal())
	check(orphan["war"].changes().is_empty(), "a log appeared out of a file that had none")
	var forged: Dictionary = save.capture(String(war.theatre()), campaign["objects"], war,
		campaign["blue"], campaign["red"], campaign["own_board"], campaign["foe_board"])
	forged["war"]["changes"] = [{"tick": 1, "id": "nowhere", "from": "NEUTRAL", "to": "FRIENDLY",
			"ground": 0.0, "air": 0.0, "blue": 0.0, "red": 0.0, "latched": 3, "reason": "x"}]
	var guarded := _seat(5)
	check(not save.apply(forged, guarded["objects"], guarded["war"], guarded["blue"],
		guarded["red"], guarded["own_board"], guarded["foe_board"]),
		"a change was accepted for a district the campaign does not have")


## --------------------------------------------------------------- the screen and the socket agree
func _check_screen(campaign: Dictionary) -> void:
	var staff: RefCounted = campaign["report"]
	var panel := String(staff.text())
	var overlay: Control = OVERLAY.new()
	root.add_child(overlay)
	check(not overlay.visible, "a debug panel that shows itself at boot is one left switched on")
	overlay.read_from(staff.text)
	await process_frame
	var label := _find_label(overlay)
	check(label != null, "the overlay has no text on it at all")
	if label == null:
		overlay.free()
		return
	check(String(label.text) != panel,
		"a hidden overlay painted a campaign nobody asked to see")
	overlay.visible = true
	overlay._process(overlay.REFRESH_SECONDS)
	check(String(label.text) == panel,
		"the screen and the socket disagree: screen \"%s\" / socket \"%s\"" % [
			String(label.text).left(58).replace("\n", " | "), panel.left(58).replace("\n", " | ")])
	var feed := {"text": panel}
	overlay.read_from(func() -> String: return String(feed["text"]))
	feed["text"] = "REPAINTED"
	overlay._process(overlay.REFRESH_SECONDS)
	check(String(label.text) == "REPAINTED",
		"the overlay never repainted once it was on the screen")
	overlay.visible = false
	feed["text"] = "WHILE HIDDEN"
	overlay._process(overlay.REFRESH_SECONDS * 4.0)
	check(String(label.text) == "REPAINTED",
		"a hidden overlay is still spending a tick on text nobody is looking at")
	overlay.free()
	var bare := REPORT.new()
	check(not bare.is_ready(), "an unseated report claims to be reading a campaign")
	check(String(bare.text()).contains("NO CAMPAIGN"),
		"the panel has nothing to say before a theatre loads")
	check(bare.sample().is_empty(), "an unseated report invented a document")
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.set_script(load("res://tests/fixtures/startup_main.gd"))
	root.add_child(main)
	for frame in range(6):
		await process_frame
	var live: Control = main.get("_war_overlay")
	check(live != null and is_instance_valid(live), "the production scene never builds the overlay")
	check(main.settings_panel.is_connected("war_overlay_toggled",
		main._on_war_overlay_toggled), "the settings panel's switch is wired to nothing")
	if live != null:
		check(live.get_parent() == main.get_node("UI"),
			"the overlay was built outside the layer that draws over the cockpit")
		## Whichever way the persisted switch is set, this is the only thing that decides whether
		## §37's panel is on the screen at boot: it never shows itself because a theatre loaded.
		check(live.visible == bool(main.call("_load_ui_flag", "war_overlay", false)),
			"the overlay's first frame does not agree with the switch that remembers it")
	main.free()


func _find_label(node: Node) -> Label:
	if node is Label:
		return node
	for child in node.get_children():
		var found := _find_label(child)
		if found != null:
			return found
	return null


## ------------------------------------------------------------------ the campaign under test
func _seat(seed_value: int) -> Dictionary:
	var geography := REGIONS.new()
	geography.load_theatre(CORRIDOR)
	var control := CONTROL.new()
	control.setup(geography)
	var registry := OBJECTS.new()
	registry.load_theatre(CORRIDOR, geography, control)
	## The same binding the game does when hostiles are on: a launcher that is not bound to a
	## handle is a launcher the tactical layer cannot fly at, and the staffs rank their cards
	## against what is actually there.
	var positions := []
	var handle := 1
	for record: Variant in registry.of_type(OBJECTS.Type.SAM_SITE):
		var site: Dictionary = record
		positions.append({"id": handle, "name": "%s LAUNCHER" % String(site["detail"]["site"])})
		handle += 1
	registry.bind_launchers(positions)
	var war := DIRECTOR.new()
	war.setup(control, geography, registry)
	war.set_seed(seed_value)
	var blue := COMMANDER.new()
	blue.setup(war, registry, geography)
	blue.set_faction(CONTROL.FRIENDLY)
	var red := COMMANDER.new()
	red.setup(war, registry, geography)
	red.set_faction(CONTROL.ENEMY)
	var own_board := MISSIONS.new()
	own_board.set_faction(CONTROL.FRIENDLY)
	own_board.setup(war, registry, geography)
	own_board.set_commander(blue if blue.is_ready() else null)
	var foe_board := MISSIONS.new()
	foe_board.set_faction(CONTROL.ENEMY)
	foe_board.setup(war, registry, geography)
	foe_board.set_commander(red if red.is_ready() else null)
	var report := REPORT.new()
	report.setup(war, control, registry, blue, red, own_board, foe_board)
	return {
		"geography": geography,
		"control": control,
		"objects": registry,
		"war": war,
		"blue": blue,
		"red": red,
		"own_board": own_board,
		"foe_board": foe_board,
		"report": report,
	}
