extends RefCounted

## §37's debug read-out of the campaign, written once.
##
## The brief asks for a panel that shows the tick, who owns what, the air and ground numbers, what
## each commander is doing and why, what each staff has on its board and why, the aircraft and the
## objects and the reason the front moved. All but the last of those already exist -- as tables the
## war publishes for the map, the MFD and the save. So this is not a new measurement layer: it is
## one place that reads the six modules in a fixed order and turns them into a dictionary, and then
## three consumers -- the telemetry socket, the overlay on the screen and the test that keeps both
## honest -- all read that one place. The alternative is a second copy of the same eleven answers
## formatted twice, which is §25's bug even when both copies agree, and which is how a debug panel
## comes to be lying about a war that is fine.
##
## What it deliberately does not do is decide anything. Nothing here is written back to a module, no
## value is computed that a module does not already publish, and no term is smoothed: a balance is
## printed signed where the war keeps it signed and as a share where the control table keeps it as a
## share, because those are two different published facts and a debug panel that quietly picks one
## is the thing that makes an emergent bug unreadable.

const CONTROL := preload("res://scripts/war/war_control.gd")
const OBJECTS := preload("res://scripts/war/war_objects.gd")
const DIRECTOR := preload("res://scripts/war/war_director.gd")

## How many of each list the panel prints. The dictionary carries everything -- a shell reading the
## telemetry wants all 32 districts, and truncating it to fit a phone would make the two consumers
## disagree about what the campaign is -- but a screen does not.
const PANEL_DISTRICTS := 6
const PANEL_CHANGES := 4
const PANEL_OPERATIONS := 3
const PANEL_MISSIONS := 3

## A name column and a total line width. Both exist so that the sentence -- the part a reader
## actually came for -- gets whatever room is left rather than being cut to a fixed length that
## every other column has already eaten into.
const PANEL_NAME := 16
const PANEL_WIDTH := 100

var _war: RefCounted
var _control: RefCounted
var _objects: RefCounted
var _own: RefCounted
var _foe: RefCounted
var _own_board: RefCounted
var _foe_board: RefCounted


## Seat the report on the campaign. Everything here is optional in the same sense the campaign is:
## a theatre with no objects still has a front, and a staff that was never seated has no board
## rather than an empty one. What is required is the war and the table it publishes, because
## without those there is nothing to read out.
func setup(war: RefCounted, control: RefCounted, objects: RefCounted, own: RefCounted,
		foe: RefCounted, own_board: RefCounted, foe_board: RefCounted) -> void:
	_war = war
	_control = control
	_objects = objects
	_own = own
	_foe = foe
	_own_board = own_board
	_foe_board = foe_board


func is_ready() -> bool:
	return _war != null and _control != null and not _war.districts().is_empty()


## ---------------------------------------------------------------------- the dictionary

## The whole of §37's list, in one document. Field names are the ones the modules already use, so
## that a line printed here can be looked up where it came from.
func sample() -> Dictionary:
	if not is_ready():
		return {}
	var where: String = _war.theatre()
	var report := {
		"theatre": where,
		"tick": int(_war.tick_number()),
		"tick_length": float(_war.tick_length()),
		"until_tick": float(_war.until_tick()),
		"seed": int(_war.seed_value()),
		"districts": _district_rows(),
		"front": _front_rows(),
		"changes": _change_rows(),
		"held": _held_rows(),
		# Held is counted over every region the map knows and the rows above are the districts the
		# war fights over, which is not the same set: an authored stretch of open sea belongs to
		# nobody and takes no part in a land war, so the director seats no district for it. Printed
		# beside the tally rather than reconciled with it, because two numbers that do not add up
		# are exactly what this panel is for.
		"regions": _control.ids().size(),
		"air": {
			CONTROL.FRIENDLY: float(_war.air_superiority(CONTROL.FRIENDLY)),
			CONTROL.ENEMY: float(_war.air_superiority(CONTROL.ENEMY)),
		},
		"resources": _purse_rows(),
		"objects": _object_rows(),
		"friendly": _side(_own, _own_board),
		"enemy": _side(_foe, _foe_board),
	}
	return report


## One side, told the way §37's example tells it: what its commander is committed to, the score it
## gave that, the six terms the score was made of and the sentence it wrote for itself; then what
## its staff is offering, with the briefing that says why each card is on the board at all.
func _side(commander: RefCounted, staff: RefCounted) -> Dictionary:
	if commander == null:
		return {"ready": false, "faction": "NONE", "force": 0.0, "focus": {},
			"operations": [], "board": [], "pattern": {}}
	var operations := []
	for record: Dictionary in commander.operations():
		var factors: Dictionary = record["factors"]
		operations.append({
			"id": String(record["id"]),
			"label": String(record["label"]),
			"objective": String(record["objective_name"]),
			"district": String(record["region_name"]),
			"target": String(record["target_name"]),
			"score": float(record["score"]),
			"held": int(record["held"]),
			"air": bool(record["air_effort"]),
			"reason": String(record["reason"]),
			"value": float(factors["value"]),
			"urgency": float(factors["urgency"]),
			"exposure": float(factors["exposure"]),
			"force": float(factors["force"]),
			"priority": float(factors["priority"]),
			"reserve": float(factors["reserve"]),
		})
	var offers := []
	var cards: Array = staff.board() if staff != null else []
	for record: Dictionary in cards:
		offers.append({
			"id": String(record["id"]),
			"callsign": String(record["callsign"]),
			"type": String(record["type"]),
			"district": String(record["region_name"]),
			"target": String(record["target_name"]),
			"priority": int(record["priority"]),
			"score": float(record["score"]),
			"status": String(record["status"]),
			"operation": String(record.get("operation", "")),
			"briefing": String(record.get("briefing", "")),
			"effect": String(record.get("strategic_effect", "")),
			"closed": String(record.get("reason", "")),
		})
	var remembered: Dictionary = commander.snapshot()["pattern"]
	return {
		"ready": commander.is_ready(),
		"faction": String(commander.faction()),
		"force": float(commander.available_force()),
		"focus": _focus_row(commander),
		"operations": operations,
		"board": offers,
		"pattern": remembered,
	}


func _focus_row(commander: RefCounted) -> Dictionary:
	var focused: Dictionary = commander.focused()
	if focused.is_empty():
		return {}
	return {
		"id": String(focused["id"]),
		"label": String(focused["label"]),
		"score": float(focused["score"]),
	}


## Every district, in the order the war holds them. Both the signed balance the tick computes with
## and the published share the map draws are here, because the distance between those two is one of
## the things a debug panel exists to see.
func _district_rows() -> Array:
	var rows := []
	for record: Variant in _war.districts():
		var district_id := String(record)
		var own: Dictionary = _war.district(district_id)
		var published: Dictionary = _control.state_of(district_id)
		rows.append({
			"id": district_id,
			"name": String(own["name"]),
			"owner": String(own["owner"]),
			"value": float(own["value"]),
			"air": float(own["air"]),
			"ground": float(own["ground"]),
			"air_control": float(published["air_control"]),
			"ground_control": float(published["ground_control"]),
			"supply": float(own["supply"]),
			"infrastructure": float(own["infrastructure"]),
			"intel": float(own["intel"]),
			"fire": float(own["under_fire"]),
			"blue": float(own["presence"][CONTROL.FRIENDLY]),
			"red": float(own["presence"][CONTROL.ENEMY]),
			"pending": String(own["pending"]),
			"pending_ticks": int(own["pending_ticks"]),
		})
	return rows


## The line as the control table derived it: which districts touch, which way the pressure runs, and
## how hard the ground is held on either side of each segment. The middle and the direction are
## written as pairs rather than as the vectors they are stored in, because this document goes out
## over a JSON socket and a `Vector2` has no encoding there -- the same reason the campaign save
## refuses to carry one.
func _front_rows() -> Array:
	var rows := []
	for record: Variant in _control.front():
		var segment: Dictionary = record
		var strong := String(segment["from"])
		var weak := String(segment["to"])
		var middle: Vector2 = segment["middle"]
		var toward: Vector2 = segment["pressure"]
		rows.append({
			"from": strong,
			"to": weak,
			"kind": String(segment["kind"]),
			"length": float(segment["length"]),
			"middle": [float(middle.x), float(middle.y)],
			"pressure": [float(toward.x), float(toward.y)],
			"ground_from": float(_control.state_of(strong)["ground_control"]),
			"ground_to": float(_control.state_of(weak)["ground_control"]),
		})
	return rows


## Why the front moved, oldest of the remembered ones first. The sentence is the director's, written
## at the tick the owner changed -- see `_change_reason` there -- and the only thing added here is
## the district's name, which this file reads off the war rather than carrying a second copy of.
func _change_rows() -> Array:
	var rows := []
	for record: Variant in _war.changes():
		var change: Dictionary = record
		var district_id := String(change["id"])
		rows.append({
			"tick": int(change["tick"]),
			"id": district_id,
			"name": String(_war.district(district_id)["name"]),
			"from": String(change["from"]),
			"to": String(change["to"]),
			"ground": float(change["ground"]),
			"air": float(change["air"]),
			"blue": float(change["blue"]),
			"red": float(change["red"]),
			"latched": int(change["latched"]),
			"reason": String(change["reason"]),
		})
	return rows


func _held_rows() -> Dictionary:
	var rows := {}
	for owner in CONTROL.OWNERS:
		rows[String(owner)] = int(_control.held_by(String(owner)))
	return rows


## Aircraft, fuel and the purse, both sides. §37 lists "aircraft resources" and the war keeps them
## in two places -- the purse it spends from and the airfields that hold the airframes -- so both
## are printed and neither is added up into a number that belongs to nobody.
func _purse_rows() -> Array:
	var rows := []
	var frames := {}
	for record: Dictionary in _war.facilities():
		var faction := String(record["faction"])
		frames[faction] = int(frames.get(faction, 0)) + int(record["aircraft"])
	for bloc: Variant in CONTROL.BLOCS:
		var faction := String(bloc)
		var purse: Dictionary = _war.resources(faction)
		var lost: Dictionary = _war.losses(faction)
		rows.append({
			"faction": faction,
			"supply": float(purse["supply"]),
			"spent": float(purse["spent"]),
			"airframes": int(frames.get(faction, 0)),
			"ground_lost": float(lost["ground"]),
		})
	return rows


## Every strategic object the theatre has, which is what §37's "strategic-object state" means: not
## the war's operating model of an airfield, which is printed above, but what the registry the map
## reads believes about each place, including the launchers it has not seen.
func _object_rows() -> Array:
	var rows := []
	if _objects == null:
		return rows
	for record: Variant in _objects.objects():
		var object: Dictionary = record
		rows.append({
			"id": int(object["id"]),
			"type": OBJECTS.type_name(object),
			"name": String(object["name"]),
			"faction": String(object["faction"]),
			"district": String(object["region_id"]),
			"health": float(object["health"]),
			"state": String(object["operational_state"]),
			"discovered": bool(object["discovered"]),
			"value": float(object["strategic_value"]),
			"handles": (object["handles"] as Array).size(),
		})
	return rows


## -------------------------------------------------------------------------- the panel

## The same document, as lines. Kept deliberately short -- a panel over a cockpit is read in a
## second, and anything longer belongs on the socket, where the whole of `sample()` already goes.
func text() -> String:
	var report := sample()
	if report.is_empty():
		return "NO CAMPAIGN SEATED"
	var lines := ["WAR %s  tick %d  next %.1fs  seed %d" % [
		String(report["theatre"]), int(report["tick"]), float(report["until_tick"]),
		int(report["seed"])]]
	var held: Dictionary = report["held"]
	var tally := []
	for owner in CONTROL.OWNERS:
		tally.append("%s %d" % [String(owner), int(held.get(String(owner), 0))])
	lines.append("HELD  " + "  ".join(tally) + "  over %d of %d regions" % [
		(report["districts"] as Array).size(), int(report["regions"])])
	for row in _hot_districts(report["districts"]):
		var place := String(row["name"]).left(PANEL_NAME)
		lines.append("%-16s %-9s air %.2f gnd %.2f  %.2f/%.2f  fire %.2f" % [
			place, String(row["owner"]), float(row["air"]), float(row["ground"]),
			float(row["blue"]), float(row["red"]), clampf(float(row["fire"]), 0.0, 1.0)])
	for side in ["friendly", "enemy"]:
		var bloc: Dictionary = report[side]
		if not bool(bloc["ready"]):
			lines.append("%s COMMANDER  not seated" % String(bloc["faction"]).to_upper())
			continue
		lines.append("%s COMMANDER  force %.2f  %d operations  %d cards" % [
			String(bloc["faction"]).to_upper(), float(bloc["force"]),
			(bloc["operations"] as Array).size(), (bloc["board"] as Array).size()])
		for record in bloc["operations"]:
			var operation: Dictionary = record
			var head := "  %-34s %.2f  " % [
				String(operation["label"]).left(34), float(operation["score"])]
			lines.append(head + _fits(head, String(operation["reason"])))
		for record in bloc["board"]:
			var card: Dictionary = record
			var head := "  %-10s %-12s %-16s " % [
				String(card["id"]), String(card["type"]), String(card["district"]).left(PANEL_NAME)]
			lines.append(head + _fits(head, String(card["briefing"])))
	for record in _recent_changes(report["changes"]):
		var change: Dictionary = record
		var head := "[%d] %-16s %-9s -> %-9s  " % [int(change["tick"]),
				String(change["name"]).left(PANEL_NAME), String(change["from"]),
				String(change["to"])]
		lines.append(head + _fits(head, String(change["reason"])))
	if (report["changes"] as Array).is_empty():
		lines.append("no district has changed hands yet")
	return "\n".join(lines)


## The districts worth the top of the panel: the ones being fought over hardest, which is what the
## rest of the war's output is for. Read off the published rows rather than re-derived, so the
## ordering and the numbers cannot disagree with each other.
func _hot_districts(rows: Array) -> Array:
	var hot := rows.duplicate(true)
	hot.sort_custom(_busier)
	var kept := []
	for index in range(mini(PANEL_DISTRICTS, hot.size())):
		kept.append(hot[index])
	return kept


static func _busier(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["fire"]), float(b["fire"])):
		return float(a["fire"]) > float(b["fire"])
	if not is_equal_approx(absf(float(a["ground"])), absf(float(b["ground"]))):
		return absf(float(a["ground"])) > absf(float(b["ground"]))
	return String(a["id"]) < String(b["id"])


func _recent_changes(rows: Array) -> Array:
	var kept := []
	for index in range(maxi(0, rows.size() - PANEL_CHANGES), rows.size()):
		kept.append(rows[index])
	return kept


## A reason is a sentence, and sentences are the thing that runs off the edge of an overlay. The
## panel measures what it has already written and cuts the sentence to the room that is left; the
## whole of every reason stays in `sample()`, which is what the socket carries.
func _fits(prefix: String, sentence: String) -> String:
	var room := clampi(PANEL_WIDTH - prefix.length(), 24, PANEL_WIDTH)
	if sentence.length() <= room:
		return sentence
	return sentence.left(room - 3) + "..."
