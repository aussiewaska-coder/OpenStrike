extends SceneTree

## Phase 8's acceptance, in the order the brief tells the story (§28, line 788): destroy airbase
## assets. Quit. Reload. Damage and strategic consequences remain.
##
## "Quit" is the hard part to test honestly, and the way to do it is to refuse to fake it. The
## reloaded campaign here is a second set of modules, seated from the region's own data the same
## way the first set was -- nothing is handed over by pointer, and the registry is asked to
## re-author its airfields, launcher sites and towers before the save goes back on. A save that
## only survives being applied to the objects that wrote it is a save that does not work.
##
## Then the two ways this phase can go wrong without any test noticing. A campaign can be restored
## *nearly*: the war back and the commanders forgot, or the damage present and the repair progress
## lost. So the comparisons below go term by term through what §28 lists, rather than checking one
## number and calling it the state. And a save can be *partly* applied when it should have been
## refused -- a file from another theatre, or from a build that wrote a shape this one does not
## know. Those refusals are tested with the campaign they were aimed at, and the assertion is that
## the campaign is untouched afterwards, word for word.

const SAVE := preload("res://scripts/war/campaign_save.gd")
const COMMANDER := preload("res://scripts/war/faction_commander.gd")
const MISSIONS := preload("res://scripts/war/mission_director.gd")
const DIRECTOR := preload("res://scripts/war/war_director.gd")
const REGIONS := preload("res://scripts/war/war_regions.gd")
const CONTROL := preload("res://scripts/war/war_control.gd")
const OBJECTS := preload("res://scripts/war/war_objects.gd")

const CORRIDOR := {
	"id": "au_gold_coast_tweed_corridor",
	"center_latitude": -28.08,
	"center_longitude": 153.365,
	"world_size_m": 50000.0,
}

## A campaign long enough to have a history: ticks fought, an operation committed, a card flown.
const RUN_TICKS := 24
const HIT := 0.42

var failed := false
var _serial := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var save := SAVE.new()
	save.erase()
	_check_the_damage_outlives_the_quit(save)
	_check_the_decision_outlives_the_quit(save)
	_check_the_disk_round_trip_is_exact(save)
	_check_a_foreign_file_is_refused(save)
	_check_a_refusal_changes_nothing(save)
	_check_an_unseated_module_is_refused(save)
	save.erase()
	if not failed:
		print("CAMPAIGN_SAVE_TEST_PASS")
	quit(1 if failed else 0)


## ------------------------------------------------------------------ the acceptance

## Destroy airbase assets, quit, reload: the field is still broken, the repair crew is still
## partway through, the sorties already flown are still counted, and the ground the fighting cost
## is still the other side's.
func _check_the_damage_outlives_the_quit(save: SAVE) -> void:
	var first := _campaign(2001)
	var war: DIRECTOR = first["director"]
	_run_campaign(first, RUN_TICKS)
	# The flying world's own verb, called the way a bomb run calls it: wear is what a strike
	# leaves on the concrete, and `_operate` is what turns it into damage on the next tick.
	var airfield := _airfields(war)
	check(not airfield.is_empty(), "the corridor must have an airbase to break")
	var object_id := int(airfield[0])
	# `duplicate` because a Dictionary is a reference: `war.facility()` hands out the live table,
	# so two reads of one field are two names for the same numbers and cannot disagree.
	var before: Dictionary = war.facility(object_id).duplicate(true)
	check(war.damage_facility(object_id, HIT), "and the strike must land")
	check(float(war.facility(object_id)["wear"]) > float(before["wear"]),
		"and leave its mark on the field")
	_run_campaign(first, 1)
	var damaged: Dictionary = war.facility(object_id).duplicate(true)
	check(float(damaged["damage"]) > float(before["damage"]),
		"the field must be measurably worse for it (%s -> %s)" % [
			str(before["damage"]), str(damaged["damage"])])
	# The other half of the same sentence, which the war does not own: an airfield's damage lives in
	# the campaign's facility table and comes back with it, while a launcher site's is a function of
	# how many launchers are standing at it -- a report from the flying world, which a quit takes
	# away. So the registry is asked to remember what the field last said, and the acceptance here is
	# that a site whose launcher is gone is still a wreck after the reload rather than a battery that
	# has quietly re-formed.
	var field := _launcher_field(first["registry"])
	check(field.size() >= 2, "and the corridor must have launchers enough to be covered")
	(first["registry"] as OBJECTS).bind_launchers(field.slice(0, field.size() - 1))
	var wrecked := _silenced_site(first["registry"])
	check(not wrecked.is_empty(), "and dropping one launcher must put one site out of action")
	var written := save.capture(String(war.theatre()), first["registry"], war, first["own"],
		first["foe"], first["own_board"], first["foe_board"])
	check(not written.is_empty(), "the campaign must write out")
	check(save.write(written), "and the file must go to the disk")
	check(save.read() != {}, "and come back off it")

	# Quit, then reload: everything here is built again from the region's data.
	var second := _campaign(2001)
	var back: DIRECTOR = second["director"]
	var restored := save.read()
	check(save.apply(restored, second["registry"], back, second["own"], second["foe"],
			second["own_board"], second["foe_board"]),
		"the save must be accepted by a freshly seated corridor: %s" % save.refusal())
	var after: Dictionary = back.facility(object_id)
	for term in DIRECTOR.SAVED_FIELD:
		check(_close(after[term], damaged[term]),
			"the field's %s must survive the reload (%s -> %s)" % [
				String(term), str(damaged[term]), str(after[term])])
	# The registry is the map's copy of the same fact, and the acceptance is about what the map
	# shows: a field the save put back on the ground has to read as broken there too.
	var registry: OBJECTS = second["registry"]
	var seen := _field_on_map(registry, object_id)
	check(not seen.is_empty(), "and the reloaded field must still be on the map")
	var detail: Dictionary = seen["detail"]
	check(_close(float(detail["damage"]), float(damaged["damage"])),
		"the airbase damage must reach the registry the map draws (%s -> %s)" % [
			str(damaged["damage"]), str(detail["damage"])])
	check(String(seen["operational_state"]) == String(damaged["state"]),
		"and so must the state word that goes with it")
	# The site whose launcher the field stopped reporting, read off the reloaded registry by the id
	# it was authored with. Positions are not in the file and are not wanted: the layout puts the
	# wreck back on the same ground it was standing on, and only what happened to it comes over.
	var silenced: Dictionary = registry.of(int(wrecked["id"]))
	check(not silenced.is_empty(), "and the wrecked site must still be a site the map knows")
	var memory: Dictionary = silenced["detail"]
	var left: Dictionary = wrecked["detail"]
	for term in OBJECTS.SAVED_SITE:
		var reported: bool = term == "seen" or term == "strongest"
		check(_close(memory[term] if reported else silenced[term],
				left[term] if reported else wrecked[term]),
			"the site's %s must come back as the field left it" % String(term))
	for record: Variant in back.districts():
		var id := String(record)
		var kept: Dictionary = war.district(id)
		var now: Dictionary = back.district(id)
		for term in DIRECTOR.SAVED_DISTRICT:
			if term == "presence" or term == "seen":
				check(_close(now[term][CONTROL.FRIENDLY], kept[term][CONTROL.FRIENDLY])
					and _close(now[term][CONTROL.ENEMY], kept[term][CONTROL.ENEMY]),
					"%s must keep its %s shares" % [id, term])
			else:
				check(_close(now[term], kept[term]), "%s must keep its %s" % [id, term])
	for faction in CONTROL.BLOCS:
		check(_close(back.supply(faction), war.supply(faction)),
			"%s must have the supply it had" % faction)
		check(_close(back.losses(faction)["ground"], war.losses(faction)["ground"]),
			"%s must still have lost the ground it lost" % faction)
	check(back.tick_number() == war.tick_number(), "and the campaign clock must not restart")
	check(int(back.seed_value()) == int(war.seed_value()), "nor the war's own dice")


## The strategic consequences are not only the map's: they are what the enemy is doing about it
## and what the pilot was last offered. A reload that restored the ground and lost the reasoning
## would resume the campaign as a different war.
func _check_the_decision_outlives_the_quit(save: SAVE) -> void:
	var first := _campaign(2002)
	var war: DIRECTOR = first["director"]
	# Give Red something to notice: the player's jet works one district until the habit is real.
	var target := _richest(first, CONTROL.ENEMY)
	check(target != "", "and the enemy must hold somewhere to fly against")
	for tick in range(COMMANDER.PATTERN_WINDOW + 8):
		var centre: Vector2 = _centre(first, target)
		war.report_sighting(CONTROL.FRIENDLY, centre, 1.0)
		_run_campaign(first, 1)
	var blue: COMMANDER = first["own"]
	var red: COMMANDER = first["foe"]
	var red_board: MISSIONS = first["foe_board"]
	check(not red.operations().is_empty(), "Red must be running operations by now")
	check(not blue.operations().is_empty(), "and so must Blue")
	check(not red_board.missions().is_empty(), "and a board must have cards on it")
	var written := save.capture(String(war.theatre()), first["registry"], war, blue, red,
		first["own_board"], red_board)
	check(save.write(written), "the campaign with its decisions in it must write")

	var second := _campaign(2002)
	var back: DIRECTOR = second["director"]
	check(save.apply(save.read(), second["registry"], back, second["own"], second["foe"],
		second["own_board"], second["foe_board"]),
		"and reload: %s" % save.refusal())
	_against(second["foe"], red, "Red")
	_against(second["own"], blue, "Blue")
	_boards(second["foe_board"], red_board, "Red")
	_boards(second["own_board"], first["own_board"], "Blue")
	# The number the whole phase is about: the reason the pilot finds fighters over that valley.
	var foe: COMMANDER = second["foe"]
	var effort := foe.effort_at(_centre(second, target))
	check(_close(effort, red.effort_at(_centre(first, target))),
		"the enemy's intent over the worked district must survive the reload (%s -> %s)" \
			% [str(red.effort_at(_centre(first, target))), str(effort)])
	# ...and it must go on working from there, not be a recording.
	_run_campaign(second, 8)
	check(not foe.operations().is_empty(), "the reloaded commander must still be commanding")
	check(foe.effort_at(_centre(second, target)) > 0.0,
		"and still be answering the pattern it was saved with")


## ---------------------------------------------------------------------- the file

## A save is a JSON document on a disk, and JSON flattens the shapes this campaign is made of:
## int keys become strings, floats come back as floats, and an Array of ints comes back as an
## Array of numbers. Applied to a third campaign and re-written, the file must be stable --
## otherwise the second reload is not the first campaign, and the drift only shows up in a game
## that has been quit and reopened a dozen times.
func _check_the_disk_round_trip_is_exact(save: SAVE) -> void:
	var first := _campaign(2003)
	var war: DIRECTOR = first["director"]
	_run_campaign(first, RUN_TICKS)
	var written := save.capture(String(war.theatre()), first["registry"], war, first["own"],
		first["foe"], first["own_board"], first["foe_board"])
	check(save.write(written), "the campaign must write")
	var again := _campaign(2003)
	check(save.apply(save.read(), again["registry"], again["director"], again["own"], again["foe"],
		again["own_board"], again["foe_board"]),
		"the file must apply to a fresh seating: %s" % save.refusal())
	var second := save.capture(String(again["director"].theatre()), again["registry"],
		again["director"], again["own"], again["foe"], again["own_board"], again["foe_board"])
	_identical(second["war"], written["war"], "war")
	_identical(second["objects"], written["objects"], "objects")
	for key in ["own", "foe", "own_board", "foe_board"]:
		_identical(second[key], written[key], key)
	# A file is only worth what its worst reader makes of it: hand the JSON text itself through
	# the same path the game does on a real restart.
	var text := JSON.stringify(second)
	var parsed: Variant = JSON.parse_string(text)
	check(parsed is Dictionary, "the written form must parse back to an object")
	var third := _campaign(2003)
	check(save.apply(parsed as Dictionary, third["registry"], third["director"], third["own"],
		third["foe"], third["own_board"], third["foe_board"]),
		"and the parsed text must apply as well as the dictionary did: %s" % save.refusal())
	_identical(save.capture(String(third["director"].theatre()), third["registry"],
		third["director"], third["own"], third["foe"], third["own_board"],
		third["foe_board"])["war"], written["war"], "war")


## A file from another theatre, or another build, or none at all.
func _check_a_foreign_file_is_refused(save: SAVE) -> void:
	var campaign := _campaign(2004)
	var war: DIRECTOR = campaign["director"]
	_run_campaign(campaign, 6)
	var written := save.capture(String(war.theatre()), campaign["registry"], war, campaign["own"],
		campaign["foe"], campaign["own_board"], campaign["foe_board"])
	check(save.write(written), "the corridor campaign must write")

	var future := written.duplicate(true)
	future["version"] = SAVE.VERSION + 1
	var other := _campaign(2004)
	check(not save.apply(future, other["registry"], other["director"], other["own"],
		other["foe"], other["own_board"], other["foe_board"]),
		"a later save format must be refused")
	check(not save.refusal().is_empty(), "with a reason a player can be shown")

	var island := written.duplicate(true)
	island["theatre"] = "somewhere_else_entirely"
	var atsea := _campaign(2004)
	check(not save.apply(island, atsea["registry"], atsea["director"], atsea["own"], atsea["foe"],
		atsea["own_board"], atsea["foe_board"]),
		"and a save naming a different theatre must be refused by this one")
	check(save.refusal().find("theatre") >= 0,
		"naming the theatre it did not match: %s" % save.refusal())

	var broken := written.duplicate(true)
	broken["war"] = {}
	var third := _campaign(2004)
	var kept: Dictionary = third["director"].export_state()
	check(not save.apply(broken, third["registry"], third["director"], third["own"], third["foe"],
		third["own_board"], third["foe_board"]), "a campaign missing its war must be refused")
	_identical(third["director"].export_state(), kept, "war")

	check(not save.write({}), "and an empty capture must never reach the disk")
	save.erase()
	check(not save.exists(), "erase must take the file off the disk")
	check(save.read() == {}, "and a read with nothing there is no campaign, not an error")


## The failure mode a save layer has by construction: it applies to six modules in a row, so it
## can stop halfway and leave a campaign made of two different wars. Every refusal below must
## leave the module it was aimed at exactly as it was.
func _check_a_refusal_changes_nothing(save: SAVE) -> void:
	var campaign := _campaign(2005)
	var war: DIRECTOR = campaign["director"]
	_run_campaign(campaign, RUN_TICKS)
	var written := save.capture(String(war.theatre()), campaign["registry"], war, campaign["own"],
		campaign["foe"], campaign["own_board"], campaign["foe_board"])

	var target := _campaign(2005)
	_run_campaign(target, 9)
	var before := {
		"objects": target["registry"].export_state(),
		"war": target["director"].export_state(),
		"own": target["own"].export_state(),
		"foe": target["foe"].export_state(),
		"own_board": target["own_board"].export_state(),
		"foe_board": target["foe_board"].export_state(),
	}

	# Wrong side's slice, handed to the wrong commander.
	var swapped := written.duplicate(true)
	swapped["own"] = written["foe"]
	check(not save.apply(swapped, target["registry"], target["director"], target["own"],
		target["foe"], target["own_board"], target["foe_board"]),
		"Blue must refuse Red's operations")
	# Red's board is the one that carries enemy cards; the war's districts are still the corridor's,
	# so this refuses on faction rather than on geography.
	var muddled := written.duplicate(true)
	muddled["foe_board"] = written["own_board"]
	check(not save.apply(muddled, target["registry"], target["director"], target["own"],
		target["foe"], target["own_board"], target["foe_board"]),
		"and a staff must refuse the other side's board")

	var torn := written.duplicate(true)
	torn["war"] = {}
	check(not save.apply(torn, target["registry"], target["director"], target["own"],
		target["foe"], target["own_board"], target["foe_board"]),
		"and a warless state must be refused outright")

	# The registry is the sixth name in the file, and its part can be the torn one too: a save
	# that lost its launcher sites is a save that would put a battery back on the ground without
	# anybody reporting it there.
	var maimed := written.duplicate(true)
	maimed["objects"] = {}
	check(not save.apply(maimed, target["registry"], target["director"], target["own"],
		target["foe"], target["own_board"], target["foe_board"]),
		"and a state with no sites in it must be refused by the registry itself")

	for key in before:
		_identical(_module(target, key).export_state(), before[key], key)


## Nothing seated, nothing saved: the module that cannot see the map must not be offered a state
## that would give it one, and the save layer must say so rather than crash on it.
func _check_an_unseated_module_is_refused(save: SAVE) -> void:
	var campaign := _campaign(2006)
	var war: DIRECTOR = campaign["director"]
	_run_campaign(campaign, 4)
	var stray := COMMANDER.new()
	check(not stray.is_ready(), "a commander with no war under it is not seated")
	check(not stray.import_state(war.export_state()), "and it must refuse a state outright")
	check(stray.export_state().is_empty() or stray.export_state()["operations"].is_empty(),
		"an unseated commander has no operations to write")
	var other := _campaign(2006)
	var through_stray := save.capture(other["director"].theatre(), other["registry"],
		other["director"], stray, other["foe"], other["own_board"], other["foe_board"])
	check(through_stray.is_empty(), "a capture through an unseated module must be refused")
	check(not save.refusal().is_empty(), "and the reason must be kept for the caller: %s"
		% save.refusal())
	check(save.capture("", other["registry"], other["director"], other["own"], other["foe"],
		other["own_board"], other["foe_board"]).is_empty(),
		"and a campaign that names no theatre is not a campaign either")
	var naked := _campaign(2006)
	naked["director"] = DIRECTOR.new()
	check(not save.apply(save.capture(other["director"].theatre(), other["registry"],
		other["director"], other["own"], other["foe"], other["own_board"], other["foe_board"]),
		naked["registry"], naked["director"], naked["own"], naked["foe"],
		naked["own_board"], naked["foe_board"]),
		"and a restore onto an unseated war must be refused")


## ------------------------------------------------------------------------ harness

## The module a section of the save belongs to. The campaign dictionary names the director
## `director` and the registry `registry`, while the save calls those two `war` and `objects`.
func _module(campaign: Dictionary, key: String) -> RefCounted:
	if key == "war":
		return campaign["director"]
	if key == "objects":
		return campaign["registry"]
	return campaign[key]


## The three terms of one commander's memory, compared.
func _against(kept: COMMANDER, was: COMMANDER, label: String) -> void:
	var now := kept.snapshot()
	var then := was.snapshot()
	check(bool(now["ready"]), "%s must be seated after the reload" % label)
	var now_list: Array = now["operations"]
	var then_list: Array = then["operations"]
	check(now_list.size() == then_list.size(),
		"%s must be running the same number of operations (%d -> %d)" \
			% [label, then_list.size(), now_list.size()])
	for index in range(mini(now_list.size(), then_list.size())):
		for term in ["id", "label", "region_id", "objective", "status", "held", "reason"]:
			check(str(now_list[index][term]) == str(then_list[index][term]),
				"%s's operation %d must keep its %s" % [label, index, term])
		check(_close(float(now_list[index]["score"]), float(then_list[index]["score"])),
			"%s's operation %d must keep its score" % [label, index])
	var now_pattern: Dictionary = now["pattern"]
	var then_pattern: Dictionary = then["pattern"]
	check(now_pattern.size() == then_pattern.size(),
		"%s must remember the same districts it was watching" % label)
	for district_id in then_pattern:
		check(now_pattern.has(district_id), "%s must still remember %s" % [label, district_id])
		check(_close(float(now_pattern[district_id]["habit"]),
			float(then_pattern[district_id]["habit"])),
			"and %s's habit over %s must be the same" % [label, district_id])
		check(int(now_pattern[district_id]["visits"]) == int(then_pattern[district_id]["visits"]),
			"and %s's visit count over %s" % [label, district_id])
	var now_focus: Dictionary = now["priority"]
	var then_focus: Dictionary = then["priority"]
	for district_id in then_focus:
		check(_close(float(now_focus.get(district_id, -1.0)), float(then_focus[district_id])),
			"%s must lean on %s as hard as it did" % [label, district_id])


## The cards the pilot was offered, and what came of them.
func _boards(kept: MISSIONS, was: MISSIONS, label: String) -> void:
	var now := kept.snapshot()
	var then := was.snapshot()
	var now_list: Array = now["missions"]
	var then_list: Array = then["missions"]
	check(now_list.size() == then_list.size(),
		"%s's board must hold the same number of cards (%d -> %d)" \
			% [label, then_list.size(), now_list.size()])
	for index in range(mini(now_list.size(), then_list.size())):
		for term in ["id", "callsign", "type", "status", "region_id", "briefing", "outcome",
			"reason", "operation"]:
			check(str(now_list[index][term]) == str(then_list[index][term]),
				"%s's card %d must keep its %s" % [label, index, term])
		check(int(now_list[index]["priority"]) == int(then_list[index]["priority"]),
			"%s's card %d must keep its priority" % [label, index])
	check(int(now["serial"]) == int(then["serial"]),
		"%s must not hand out an id twice" % label)
	check(int(now["tick"]) == int(then["tick"]), "%s's clock must not restart" % label)


func _identical(kept: Variant, was: Variant, label: String) -> void:
	var difference := _first_difference(kept, was)
	check(difference == "", "%s must come back out of the file as it went in: %s" \
		% [label, difference])


## Name the term that drifted, rather than only saying that something did.
func _first_difference(kept: Variant, was: Variant, path := "") -> String:
	if kept is Dictionary and was is Dictionary:
		var table: Dictionary = kept
		var other: Dictionary = was
		for key in table:
			if not other.has(key):
				return "%s: %s is missing" % [path, key]
			var found := _first_difference(table[key], other[key],
				"%s.%s" % [path, String(key)])
			if found != "":
				return found
		for key in other:
			if not table.has(key):
				return "%s: %s appeared" % [path, key]
		return ""
	if kept is Array and was is Array:
		var list: Array = kept
		var other_list: Array = was
		if list.size() != other_list.size():
			return "%s: %d against %d entries" % [path, list.size(), other_list.size()]
		for index in range(list.size()):
			var found := _first_difference(list[index], other_list[index],
				"%s[%d]" % [path, index])
			if found != "":
				return found
		return ""
	if kept is float or was is float:
		if not _close(float(kept), float(was)):
			return "%s: %s against %s" % [path, str(kept), str(was)]
		return ""
	return "" if kept == was else "%s: %s against %s" % [path, str(kept), str(was)]


func _close(a: Variant, b: Variant) -> bool:
	if a is bool or b is bool:
		return bool(a) == bool(b)
	if a is String or b is String:
		return String(a) == String(b)
	return is_equal_approx(float(a), float(b)) or absf(float(a) - float(b)) < 0.0000001


## One turn of the whole chain, in the order the flying world runs it.
func _run_campaign(campaign: Dictionary, ticks: int) -> void:
	var war: DIRECTOR = campaign["director"]
	var red: COMMANDER = campaign["foe"]
	var blue: COMMANDER = campaign["own"]
	var own_board: MISSIONS = campaign["own_board"]
	var foe_board: MISSIONS = campaign["foe_board"]
	for tick in range(ticks):
		war.tick()
		blue.tick(war.tick_number())
		red.tick(war.tick_number())
		own_board.tick(war.tick_number())
		foe_board.tick(war.tick_number())


func _campaign(seed_value: int) -> Dictionary:
	var geography := REGIONS.new()
	check(geography.load_theatre(CORRIDOR), "the corridor must divide into districts")
	var control := CONTROL.new()
	control.setup(geography)
	var registry := OBJECTS.new()
	check(registry.load_theatre(CORRIDOR, geography, control),
		"and the corridor must have its fields, sites and towers in it")
	registry.bind_launchers(_launcher_field(registry))
	var director := DIRECTOR.new()
	check(director.setup(control, geography, registry), "and the war must take the theatre")
	director.set_seed(seed_value)
	var blue := COMMANDER.new()
	check(blue.setup(director, registry, geography), "and Blue's commander must be seated")
	blue.set_faction(CONTROL.FRIENDLY)
	var red := COMMANDER.new()
	check(red.setup(director, registry, geography), "and so must Red's")
	red.set_faction(CONTROL.ENEMY)
	var own_board := MISSIONS.new()
	check(own_board.setup(director, registry, geography), "and Blue's staff")
	own_board.set_faction(CONTROL.FRIENDLY)
	own_board.set_commander(blue)
	var foe_board := MISSIONS.new()
	check(foe_board.setup(director, registry, geography), "and Red's")
	foe_board.set_faction(CONTROL.ENEMY)
	foe_board.set_commander(red)
	return {
		"geography": geography,
		"registry": registry,
		"director": director,
		"own": blue,
		"foe": red,
		"own_board": own_board,
		"foe_board": foe_board,
	}


## Every object id the war is fighting over that is an airfield.
func _airfields(war: DIRECTOR) -> Array:
	var found := []
	for record: Variant in war.facilities():
		var field: Dictionary = record
		if int(field["type"]) == OBJECTS.Type.AIRBASE:
			found.append(int(field["object_id"]))
	return found


## The launcher field's own report of the corridor: one launcher standing at every site the layout
## authored, named the way the tracker names it, because `bind_launchers` matches a site to its
## launchers by that name and nothing else.
func _launcher_field(registry: RefCounted) -> Array:
	var positions := []
	var handle := 1
	for record in (registry as OBJECTS).of_type(OBJECTS.Type.SAM_SITE):
		var site: Dictionary = record
		positions.append({"id": handle, "name": "%s LAUNCHER" % String(site["detail"]["site"])})
		handle += 1
	return positions


## The site the field has stopped reporting -- the one a sortie put out of action and the campaign
## has to remember that way.
func _silenced_site(registry: RefCounted) -> Dictionary:
	for record in (registry as OBJECTS).of_type(OBJECTS.Type.SAM_SITE):
		var site: Dictionary = record
		if (site["handles"] as Array).is_empty() \
				and String(site["operational_state"]) == OBJECTS.DESTROYED:
			return site
	return {}


## The registry's own view of one field -- the map's copy of the fact, not the war's.
func _field_on_map(registry: OBJECTS, object_id: int) -> Dictionary:
	for record: Variant in registry.of_type(OBJECTS.Type.AIRBASE):
		var seen: Dictionary = record
		if int(seen["id"]) == object_id:
			return seen
	return {}


func _richest(campaign: Dictionary, faction: String) -> String:
	var geography: REGIONS = campaign["geography"]
	var war: DIRECTOR = campaign["director"]
	var best := ""
	var value := -1.0
	for record: Variant in geography.regions():
		var id := String(record["id"])
		var state: Dictionary = war.district(id)
		if state.is_empty() or String(state["owner"]) != faction:
			continue
		if float(state["value"]) > value:
			value = float(state["value"])
			best = id
	return best


func _centre(campaign: Dictionary, district_id: String) -> Vector2:
	var geography: REGIONS = campaign["geography"]
	for record: Variant in geography.regions():
		var region: Dictionary = record
		if String(region["id"]) == district_id:
			var centre: Variant = region["centre"]
			if centre is Vector2:
				return centre
	return Vector2.ZERO
