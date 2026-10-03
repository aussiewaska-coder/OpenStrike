extends RefCounted

## The staff work that sits on top of the war.
##
## `war_director.gd` knows where the pressure is and does nothing with the knowledge. This
## is the part that decides what to fly against it, and every mission on the board is here
## because a published number said so: a SAM site the launcher field reports as standing at
## ground whose air we cannot win generates a SEAD, a district we are grinding forward into
## with the enemy still in it generates CAS, a field the damage model has been chewing on
## generates its own defence. Nothing is scripted, nothing is scheduled, and an offer that
## the state has stopped justifying stops being repeated.
##
## The phase-4 split holds, and it is the reason this is a RefCounted with no `_process`:
## this owns DATA. It spawns no aircraft, fires no weapon, writes no district state, and
## runs once per strategic tick on the director's clock rather than on its own. It reads
## `war_director.gd` and `war_objects.gd` and writes only its own table, which is what
## lets phase 7 put a commander in front of it without either of them noticing.
##
## What it will not be is a second target database. §25: a mission whose primary target is
## a site carries that site's strategic id, and the launcher standing at it comes back out
## of the registry as the entity the weapon tracker already uses. One thing, three names --
## map, cockpit, campaign. A job with no discrete object in the world to point at carries
## -1 and is placed on its district, because this world has no enemy airframe entity and
## inventing one to fill a field would be exactly the duplicate §25 forbids.

signal mission_created(mission: Dictionary)
signal mission_assigned(id: String)
signal mission_completed(id: String, outcome: String)
signal mission_failed(id: String, reason: String)

const CONTROL := preload("res://scripts/war/war_control.gd")
const OBJECTS := preload("res://scripts/war/war_objects.gd")
const DIRECTOR := preload("res://scripts/war/war_director.gd")

## §17's eight, and deliberately no more. Each one here is earned by a condition the war
## can be seen to be in; a ninth would have to invent its own justification.
enum Kind {
	CAP,
	INTERCEPT,
	ESCORT,
	SEAD,
	STRIKE,
	CAS,
	AIRBASE_DEFENCE,
	GROUND_INTERDICTION,
}

const KIND_NAME := {
	Kind.CAP: "CAP",
	Kind.INTERCEPT: "INTERCEPT",
	Kind.ESCORT: "ESCORT",
	Kind.SEAD: "SEAD",
	Kind.STRIKE: "STRIKE",
	Kind.CAS: "CAS",
	Kind.AIRBASE_DEFENCE: "AIRBASE DEFENCE",
	Kind.GROUND_INTERDICTION: "INTERDICTION",
}

## The word is per kind rather than per mission, so two SEAD packages on the board are
## HAMMER 3 and HAMMER 4 and a pilot knows the job from the radio check alone.
const CALLSIGN := {
	Kind.CAP: "SHIELD",
	Kind.INTERCEPT: "DART",
	Kind.ESCORT: "LANCE",
	Kind.SEAD: "HAMMER",
	Kind.STRIKE: "SWORD",
	Kind.CAS: "TALON",
	Kind.AIRBASE_DEFENCE: "BASTION",
	Kind.GROUND_INTERDICTION: "AXE",
}

## §18's statuses. The four closed ones are final and stay on the board only long enough
## for a card to be opened on them.
const AVAILABLE := "AVAILABLE"
const ASSIGNED := "ASSIGNED"
const ACTIVE := "ACTIVE"
const SUCCESS := "SUCCESS"
const PARTIAL := "PARTIAL"
const FAILED := "FAILED"
const EXPIRED := "EXPIRED"
const STATUSES := [AVAILABLE, ASSIGNED, ACTIVE, SUCCESS, PARTIAL, FAILED, EXPIRED]
const CLOSED := [SUCCESS, PARTIAL, FAILED, EXPIRED]
const OPEN := [AVAILABLE, ASSIGNED, ACTIVE]

## How long a job is worth flying for, in strategic ticks -- 8 s apiece at the default. A
## sortie is minutes, so every window here is comfortably longer than it takes to arm, get
## airborne and arrive, and the short ones are the jobs that are only true for a while: an
## attack already on its way in, a field already burning.
const WINDOW := {
	Kind.CAP: 14,
	Kind.INTERCEPT: 8,
	Kind.ESCORT: 10,
	Kind.SEAD: 36,
	Kind.STRIKE: 30,
	Kind.CAS: 14,
	Kind.AIRBASE_DEFENCE: 20,
	Kind.GROUND_INTERDICTION: 24,
}

## The three numbers the air tasking turns on. `DENIED_AIR` is where our own aircraft have
## stopped being able to work a district, which is what a SEAD is a response to; `CLEAR_AIR`
## is the floor a strike package will be offered at, which is how knocking sites down makes
## the next mission appear rather than the next mission being written; `HOLD_AIR` is what a
## CAP or intercept is flown to achieve and judged against afterwards.
const DENIED_AIR := 0.45
const CLEAR_AIR := 0.55
const HOLD_AIR := 0.6

## Judging a sortie. `GOAL` is the problem solved, `PARTIAL_GAIN` is the problem measurably
## smaller, and both are differences against the figure the mission was raised on -- so a
## district that was already quiet never earns a success for staying quiet.
const GOAL := 0.34
const PARTIAL_GAIN := 0.12

## A district has to be worth a sortie to be offered one, and a board of twelve plausible
## jobs is worse than a board of four real ones. `MIN_OFFER` is a noise gate rather than a
## threshold of importance: below it the conditions are met by numbers too small to fly for.
## `MIN_TARGET_VALUE` sits where it does because a structure's ceiling in this theatre is
## 0.45 -- 0.4 would refuse every strike against anything that is not a SAM site -- and
## `KIND_LIMIT` is the staff's own rule of presentation: six sites are six sites, and the
## three that matter most are the three the player is offered, or the board is a list of
## every position on the map rather than a set of priorities.
const MIN_DISTRICT_VALUE := 0.25
const MIN_TARGET_VALUE := 0.3
const MIN_ENEMY_PRESENCE := 0.25
const MIN_OFFER := 0.08
const LIVE_LIMIT := 8
const KIND_LIMIT := 3
const RESOLVED_KEEP := 10

var _war: RefCounted
var _objects: RefCounted
var _geography: RefCounted
var _commander: RefCounted
var _faction := CONTROL.FRIENDLY
var _missions := []
var _by_id := {}
var _tick := 0
var _serial := 0
var _words := {}
var _ready := false


## Take the tables this reads. A director that cannot report its own air battle, or a
## registry with nothing in it, is refused -- and refused cleanly, which after phase 5 means
## the board is empty rather than full of tasks over the last theatre's ground.
func setup(director: RefCounted, objects: RefCounted, geography: RefCounted = null) -> bool:
	_missions = []
	_by_id = {}
	_words = {}
	_serial = 0
	_tick = 0
	_ready = false
	_war = null
	_objects = null
	_geography = null
	_commander = null
	if director == null or not director.has_method("air_balance") \
			or not director.has_method("active_battles"):
		return false
	if objects == null or not objects.has_method("objects") or not objects.is_loaded():
		return false
	if geography == null or not geography.has_method("adjacency"):
		return false
	_war = director
	_objects = objects
	_geography = geography
	_ready = not _war.districts().is_empty()
	return _ready


func is_ready() -> bool:
	return _ready


func set_faction(faction: String) -> void:
	if faction in CONTROL.BLOCS:
		_faction = faction


## Hand the board to a commander, or take it away again. This is §15's chain arriving in the
## only place it can: the staff is still the one writing missions for reasons the war publishes,
## and the commander only gets a vote on which of those reasons it cares about first. Null is
## the pre-phase-7 board back, unchanged, which is what lets the staff be seated before a
## commander exists and a theatre with no campaign still have a board.
func set_commander(commander: RefCounted) -> void:
	_commander = commander \
			if commander != null and commander.has_method("priority_for") \
			and commander.has_method("operations_in") else null


func commander() -> RefCounted:
	return _commander


func faction() -> String:
	return _faction


## The campaign's clock, as this module last heard it.
func tick_number() -> int:
	return _tick


## One turn of staff work: settle what came back, drop what has been read, ask the war what
## it needs. In that order, so a mission that has just succeeded cannot be reoffered over
## the same objective in the same tick.
func tick(tick_number: int) -> void:
	if not _ready:
		return
	_tick = tick_number
	_resolve()
	_prune()
	_generate()


func missions() -> Array:
	return _missions


func mission(id: String) -> Dictionary:
	return _by_id.get(id, {})


## Everything on the board with a decision outstanding, hardest first: what the map draws
## and what a card walks through.
func board() -> Array:
	var found := []
	for record in _missions:
		var mission: Dictionary = record
		if String(mission["status"]) in OPEN:
			found.append(mission)
	found.sort_custom(_harder)
	return found


func available() -> Array:
	var found := []
	for record in _missions:
		var mission: Dictionary = record
		if String(mission["status"]) == AVAILABLE:
			found.append(mission)
	found.sort_custom(_harder)
	return found


## The job a flying player is working, if there is one. A HUD that wants to name the
## tasking rather than list the board asks this and gets at most one answer.
func tasked() -> Dictionary:
	for record in _missions:
		var mission: Dictionary = record
		if String(mission["status"]) in [ASSIGNED, ACTIVE]:
			return mission
	return {}


## Take an offer. The clock becomes the player's problem here: an accepted job that is never
## flown still expires, and says what it expired on.
func accept(id: String) -> bool:
	var taken := _open(id)
	if taken.is_empty() or String(taken["status"]) != AVAILABLE:
		return false
	taken["status"] = ASSIGNED
	mission_assigned.emit(id)
	return true


## The sortie is committed to this job. Nothing here needs to know that an airframe is
## literally airborne -- the effect a mission is judged on is the campaign's own state, so
## all this can honestly record is that someone went to work on it. What it does on the way
## is re-read the baseline: an offer made during a lull and flown into a battle is judged on
## the battle.
func launch(id: String) -> bool:
	var taken := _open(id)
	if taken.is_empty() or String(taken["status"]) != ASSIGNED:
		return false
	taken["status"] = ACTIVE
	taken["basis"] = _basis_of(int(taken["kind"]), String(taken["region_id"]),
		int(taken["primary_target"]))
	return true


func primary_target(id: String) -> Dictionary:
	var taken: Dictionary = _by_id.get(id, {})
	if taken.is_empty():
		return {}
	return _target(int(taken["primary_target"]))


## The entity the flying world answers to for this mission's primary target -- the launcher
## standing at the site, which is the same handle the weapon tracker uses. -1 for a job with
## no discrete object, and -1 means the card offers no lock rather than a lock on a fiction.
func primary_entity(id: String) -> int:
	var target := primary_target(id)
	if target.is_empty():
		return -1
	var handles: Array = target["handles"]
	return int(handles[0]) if not handles.is_empty() else -1


## Where a mission's mark stands: the objective itself when there is one, the middle of the
## district when the job is over ground rather than a point on it.
func position_of(id: String) -> Vector2:
	var taken: Dictionary = _by_id.get(id, {})
	if taken.is_empty():
		return Vector2.INF
	var target := _target(int(taken["primary_target"]))
	if not target.is_empty():
		return target["world_position"]
	return _centre(String(taken["region_id"]))


func snapshot() -> Dictionary:
	var list := []
	for record in _missions:
		var mission: Dictionary = record
		list.append({
			"id": String(mission["id"]),
			"callsign": String(mission["callsign"]),
			"type": String(mission["type"]),
			"kind": int(mission["kind"]),
			"faction": String(mission["faction"]),
			"region_id": String(mission["region_id"]),
			"region_name": String(mission["region_name"]),
			"primary_target": int(mission["primary_target"]),
			"target_name": String(mission["target_name"]),
			"secondary_targets": (mission["secondary_targets"] as Array).duplicate(),
			"priority": int(mission["priority"]),
			"status": String(mission["status"]),
			"operation": String(mission.get("operation", "")),
			"briefing": String(mission["briefing"]),
			"threat_level": String(mission["threat_level"]),
			"strategic_effect": String(mission["strategic_effect"]),
			"created_at": int(mission["created_at"]),
			"expires_at": int(mission["expires_at"]),
			"outcome": String(mission.get("outcome", "")),
			"reason": String(mission.get("reason", "")),
		})
	return {"tick": _tick, "faction": _faction, "serial": _serial, "missions": list}


## ---------------------------------------------------------------------- §28's save

## The board as it stands: every card still on it, with the outcome the flying world reported
## against it, plus the calling-forward counter and the serial the next id comes from. A
## resolved strike is part of the campaign's memory -- it is the reason a district is quiet --
## and §28 asks for the strategic consequences to survive a reload, which they do not if the
## staff forgets what it already flew.
func export_state() -> Dictionary:
	var list := []
	for record: Dictionary in _missions:
		list.append(record.duplicate(true))
	var words := {}
	for word in _words:
		words[String(word)] = int(_words[word])
	return {
		"faction": _faction,
		"tick": _tick,
		"serial": _serial,
		"words": words,
		"missions": list,
	}


## Read it back onto the seated staff. Refused whole, as everywhere else in this module: a board
## carrying another side's missions would task flights over districts its own war does not name,
## and half a board restored is the failure mode nobody can see. `_by_id` is not saved because it
## is the same dictionaries as `_missions`; the prune at the end of a tick rebuilds it from the
## list and so does this.
func import_state(state: Dictionary) -> bool:
	if not _ready or state.is_empty():
		return false
	if String(state.get("faction", "")) != _faction:
		return false
	var list: Variant = state.get("missions", [])
	if not (list is Array):
		return false
	for record in list:
		if not _holds(record, SAVED_MISSION):
			return false
		var mission := record as Dictionary
		if String(mission["faction"]) != _faction:
			return false
		if _district(String(mission["region_id"])).is_empty():
			return false
	var words := _section(state, "words")

	_missions = []
	_by_id = {}
	for record in list:
		var mission: Dictionary = _carried(record as Dictionary)
		_missions.append(mission)
		_by_id[String(mission["id"])] = mission
	_words = {}
	for word in words:
		_words[String(word)] = int(words[word])
	_tick = int(state.get("tick", _tick))
	_serial = int(state.get("serial", _serial))
	return true


## The terms a card must arrive with. Everything the board prints comes off this list, so a save
## that carries these carries the same card the pilot was offered.
const SAVED_MISSION := ["id", "callsign", "type", "kind", "faction", "region_id", "region_name",
	"primary_target", "target_name", "secondary_targets", "priority", "status", "threat_level",
	"created_at", "expires_at", "outcome", "reason", "score", "operation", "basis", "briefing",
	"strategic_effect"]


## A card, put back the way the staff holds it. JSON has one number type, and this table keeps a
## kind, a priority, two clock marks, a target id and a list of them as ints -- an id that came
## back as `4013.0` would not match the registry's `4013`, and a `%d` on either prints the drift.
func _carried(record: Dictionary) -> Dictionary:
	var copy := record.duplicate(true)
	for term in SAVED_WHOLE:
		copy[term] = int(record[term])
	var secondaries := []
	for target in record["secondary_targets"]:
		secondaries.append(int(target))
	copy["secondary_targets"] = secondaries
	if record.has("closed_at"):
		copy["closed_at"] = int(record["closed_at"])
	return copy


const SAVED_WHOLE := ["kind", "priority", "created_at", "expires_at", "primary_target"]


func _holds(record: Variant, terms: Array) -> bool:
	if not (record is Dictionary):
		return false
	for term in terms:
		if not (record as Dictionary).has(term):
			return false
	return true


## A section of the file that must be a table: a string where the callsign counts belong reads
## as an empty table, so a malformed save is refused rather than crashed on halfway through.
func _section(state: Dictionary, key: String) -> Dictionary:
	var found: Variant = state.get(key, {})
	return found if found is Dictionary else {}


## ---------------------------------------------------------------- what it is offered over

## The eight questions the board is built from. Each returns the ground, and the thing on
## it, that a sortie would be sent to -- scored by how much the published state says it
## matters -- and none of them looks at a script.
##
## The commander is heard between the questions and the ranking, on §15's own term: a district
## it has committed operations over is worth more than the raw state says, and a district it has
## deliberately left alone is worth less. The scaling happens here rather than inside each
## question because the questions are the war's arithmetic and belong to nobody else -- a SEAD
## builder that knew about doctrine would stop being a description of the ground, and the eight
## would turn into eight opinions.
func _generate() -> void:
	var candidates := []
	candidates.append_array(_sead())
	candidates.append_array(_strike())
	candidates.append_array(_cas())
	candidates.append_array(_intercept())
	candidates.append_array(_patrol())
	candidates.append_array(_escort())
	candidates.append_array(_base_defence())
	candidates.append_array(_interdiction())
	for offer in candidates:
		offer["score"] = float(offer["score"]) * _priority(String(offer["region_id"]))
	candidates.sort_custom(_weightier)
	for offer in candidates:
		if _count_open() >= LIVE_LIMIT:
			return
		_offer(offer)


## §15's `commander_priority`, on the staff's own axis: 1.0 is the commander having no opinion
## about this ground, which is the whole board before phase 7 and the whole board in a theatre
## with no commander seated.
func _priority(district_id: String) -> float:
	return _commander.priority_for(district_id) if _commander != null else 1.0


## Which of the commander's operations this job would be serving, for the card and the debug
## overlay to print. An offer the commander has not committed over is not given an operation it
## does not have: the mission's own briefing already says what the war did.
func _operation(district_id: String) -> String:
	if _commander == null:
		return ""
	var live: Array = _commander.operations_in(district_id)
	if live.is_empty():
		return ""
	return String(live[0]["label"])


## The brief's opening loop, and the only mission type that gates another one: a site
## standing on ground whose air we do not have, within reach of the line, is a job whether
## or not anyone has ever flown against it.
func _sead() -> Array:
	var offers := []
	for record in _objects.objects():
		var site: Dictionary = record
		if int(site["type"]) != OBJECTS.Type.SAM_SITE:
			continue
		if String(site["faction"]) != _foe() or float(site["health"]) <= 0.0:
			continue
		var district_id := String(site["region_id"])
		if district_id.is_empty() or not _from_line(district_id):
			continue
		var denial := 1.0 - _air(district_id)
		if denial < DENIED_AIR:
			continue
		var value := float(_district(district_id)["value"])
		if value < MIN_DISTRICT_VALUE:
			continue
		offers.append({
			"kind": Kind.SEAD,
			"region_id": district_id,
			"target": site,
			"score": denial * clampf(float(site["health"]), 0.0, 1.0) * (0.4 + 0.6 * value),
		})
	return offers


func _strike() -> Array:
	var offers := []
	for id in _districts():
		var district_id := String(id)
		if _owns(district_id) or not _from_line(district_id):
			continue
		var value := float(_district(district_id)["value"])
		if value < MIN_DISTRICT_VALUE:
			continue
		# The gate the SEAD opens: the air these sites were denying is the air this package
		# needs, so a district moves from "not offered" to "on the board" because the state
		# changed and not because anything here was told to offer it. It is a majority of the
		# sky rather than a mild preference because a bomb package is flown slow, low and
		# unarmed, and the corridor it comes back through is the thing being bought.
		if _air(district_id) < CLEAR_AIR:
			continue
		for record in _enemy_in(district_id):
			var object: Dictionary = record
			if float(object["strategic_value"]) < MIN_TARGET_VALUE:
				continue
			# A launcher that is still standing is a SEAD, and the board saying so twice -- once
			# as HAMMER and once as SWORD, at the same object -- is the duplicate §25 is about,
			# only with two callsigns on it. What a strike is for is everything else the enemy
			# keeps at a position: a radar, a depot, a post, parked airframes. In a corridor
			# whose whole hostile order of battle is launchers, this is the reason the kind is
			# quiet, and it is quiet for a fact about the world rather than for a threshold.
			if int(object["type"]) == OBJECTS.Type.SAM_SITE \
					and float(object["health"]) > 0.0:
				continue
			offers.append({
				"kind": Kind.STRIKE,
				"region_id": district_id,
				"target": object,
				"score": float(object["strategic_value"]) * _air(district_id) * value,
			})
	return offers


func _cas() -> Array:
	var offers := []
	for record in _war.active_battles():
		var battle: Dictionary = record
		if String(battle["attacker"]) != _faction:
			continue
		var district_id := String(battle["to"])
		var own := _district(district_id)
		if own.is_empty():
			continue
		var hostile := float(own["presence"].get(_foe(), 0.0))
		if hostile <= 0.05:
			continue
		var target := _best_enemy(district_id)
		if target.is_empty():
			continue
		var intensity := clampf(float(battle["intensity"]), 0.0, 1.0)
		# Our own attack is the reason, so a battle that is barely moving still wants air
		# above it -- the + 0.2 is the call to be there, the presence is the call to hit
		# something specific.
		offers.append({
			"kind": Kind.CAS,
			"region_id": district_id,
			"target": target,
			"score": intensity * hostile * float(own["value"]) + 0.2 * intensity,
		})
	return offers


func _intercept() -> Array:
	var offers := []
	for record in _war.active_battles():
		var battle: Dictionary = record
		if String(battle["defender"]) != _faction:
			continue
		var district_id := String(battle["to"])
		var share := _air(district_id)
		if share >= HOLD_AIR:
			continue
		var own := _district(district_id)
		offers.append({
			"kind": Kind.INTERCEPT,
			"region_id": district_id,
			"target": {},
			"score": clampf(float(battle["intensity"]), 0.0, 1.0) * (1.0 - share) \
				+ 0.15 * (1.0 - share),
		})
	return offers


func _patrol() -> Array:
	var offers := []
	for id in _districts():
		var district_id := String(id)
		if not _owns(district_id):
			continue
		var own := _district(district_id)
		var value := float(own["value"])
		if value < MIN_DISTRICT_VALUE:
			continue
		var share := _air(district_id)
		if share >= HOLD_AIR:
			continue
		# Ground we hold that we cannot see the top of is a rear area that has to be covered,
		# and the nearer the line the more it is worth: a district under fire asks for CAP the
		# way a breach asks for a stopper.
		var heat := clampf(float(own["under_fire"]) / 3.0, 0.0, 1.0)
		offers.append({
			"kind": Kind.CAP,
			"region_id": district_id,
			"target": {},
			"score": (1.0 - share) * value * (0.5 + 0.5 * _edge(district_id)) \
				* (0.6 + 0.4 * heat),
		})
	return offers


## The one offer that comes from the board rather than from the war: a package that has been
## committed into contested air is flown with someone, and the escort appears when the
## player accepts the job rather than when the staff imagines they might.
func _escort() -> Array:
	var offers := []
	for record in _missions:
		var package: Dictionary = record
		var kind := int(package["kind"])
		if String(package["status"]) not in [ASSIGNED, ACTIVE]:
			continue
		if kind not in [Kind.SEAD, Kind.STRIKE, Kind.CAS]:
			continue
		var district_id := String(package["region_id"])
		var denial := 1.0 - _air(district_id)
		if denial < DENIED_AIR:
			continue
		offers.append({
			"kind": Kind.ESCORT,
			"region_id": district_id,
			"target": {},
			"score": denial * (0.5 + 0.5 * float(package["priority"]) / 5.0),
			"for": String(package["callsign"]),
		})
	return offers


func _base_defence() -> Array:
	var offers := []
	for record in _war.facilities():
		var field: Dictionary = record
		if String(field["faction"]) != _faction or float(field["damage"]) < 0.15:
			continue
		var district_id := String(field["region_id"])
		var threat := _standing_sites_in_reach(district_id)
		if threat.is_empty():
			continue
		# Defending a field that is being shot up means going after the thing shooting at it,
		# so the mission carries a real objective rather than a perimeter.
		var worst: Dictionary = threat[0]
		for site in threat:
			if float(site["health"]) > float(worst["health"]):
				worst = site
		var denial := 1.0 - _air(district_id)
		offers.append({
			"kind": Kind.AIRBASE_DEFENCE,
			"region_id": district_id,
			"target": worst,
			"score": clampf(float(field["damage"]), 0.0, 1.0) * (0.4 + 0.6 * denial) \
				* clampf(float(worst["health"]), 0.0, 1.0),
		})
	return offers


func _interdiction() -> Array:
	var offers := []
	for id in _districts():
		var district_id := String(id)
		if _owns(district_id) or not _from_line(district_id):
			continue
		var own := _district(district_id)
		var hostile := float(own["presence"].get(_foe(), 0.0))
		if hostile < MIN_ENEMY_PRESENCE:
			continue
		# What the enemy's own logistics are doing is published: a district feeding an attack
		# behind the line is worth cutting, and a quiet garrison holding its own ground is not
		# worth a package yet.
		var feeding := 0.0
		for record in _war.active_battles():
			var battle: Dictionary = record
			if String(battle["attacker"]) == _foe() and String(battle["from"]) == district_id:
				feeding = maxf(feeding, clampf(float(battle["intensity"]), 0.0, 1.0))
		offers.append({
			"kind": Kind.GROUND_INTERDICTION,
			"region_id": district_id,
			"target": _best_enemy(district_id),
			"score": hostile * (0.4 + 0.6 * float(own["value"])) * (1.0 + feeding) \
				* (0.5 + 0.5 * float(own["infrastructure"])),
		})
	return offers


## ----------------------------------------------------------------------- the war, read

func _districts() -> Array:
	return _war.districts()


func _district(id: String) -> Dictionary:
	return _war.district(id)


## Our own share of the air over a district, on the 0..1 axis the map is drawn with. The
## director keeps the signed balance and this reads it the way a commander wants, which is
## why it goes through `share_of` rather than through a second translation.
func _air(id: String) -> float:
	return DIRECTOR.share_of(float(_war.air_balance(id)), _faction)


func _foe() -> String:
	return CONTROL.ENEMY if _faction == CONTROL.FRIENDLY else CONTROL.FRIENDLY


func _owns(id: String) -> bool:
	return String(_district(id).get("owner", CONTROL.NEUTRAL)) == _faction


## Ground a sortie can be sent to from where we are standing: our own districts and the ones
## touching them. Reach is the war's own measure of it -- the same ring its air battle is
## fought on -- rather than a radius invented for the map.
func _from_line(id: String) -> bool:
	if _owns(id):
		return true
	for neighbour in _neighbours(id):
		if _owns(String(neighbour)):
			return true
	return false


func _neighbours(id: String) -> Array:
	return (_geography.adjacency().get(id, {}) as Dictionary).keys()


## Enemy objects standing at something. Health is the filter rather than state: an
## unconfirmed position on the authored layout is a fact about the route and not a target,
## and the war's own air model already refuses to let it deny anything.
func _enemy_in(id: String) -> Array:
	var found := []
	for record in _objects.objects():
		var object: Dictionary = record
		if String(object["faction"]) != _foe() or String(object["region_id"]) != id:
			continue
		if float(object["health"]) <= 0.0:
			continue
		found.append(object)
	return found


func _standing_sites_in_reach(id: String) -> Array:
	var found := []
	for record in _objects.objects():
		var object: Dictionary = record
		if int(object["type"]) != OBJECTS.Type.SAM_SITE \
				or String(object["faction"]) != _foe():
			continue
		if float(object["health"]) <= 0.0:
			continue
		var site := String(object["region_id"])
		if site.is_empty() or _touches(site, id):
			found.append(object)
	return found


func _touches(here: String, there: String) -> bool:
	if here == there:
		return true
	return (_geography.adjacency().get(here, {}) as Dictionary).has(there)


func _best_enemy(id: String) -> Dictionary:
	var best := {}
	for record in _enemy_in(id):
		var object: Dictionary = record
		if best.is_empty() or float(object["strategic_value"]) > float(best["strategic_value"]):
			best = object
	return best


func _target(object_id: int) -> Dictionary:
	if object_id < 0:
		return {}
	return _objects.of(object_id)


func _gone(object: Dictionary) -> bool:
	if object.is_empty():
		return false
	return String(object["operational_state"]) == OBJECTS.DESTROYED \
		or (bool(object["discovered"]) and float(object["health"]) <= 0.0)


func _centre(id: String) -> Vector2:
	var region: Dictionary = _geography.region(id)
	return region["centre"] if not region.is_empty() else Vector2.INF


func _name(id: String) -> String:
	var region: Dictionary = _geography.region(id)
	return String(region["name"]) if not region.is_empty() else id


## How much of a district's border is front rather than rear: the difference between
## covering an airfield and patrolling a county nobody is trying to take.
func _edge(id: String) -> float:
	var neighbours := _neighbours(id)
	if neighbours.is_empty():
		return 0.0
	var hostile := 0
	for neighbour in neighbours:
		if not _owns(String(neighbour)):
			hostile += 1
	return float(hostile) / float(neighbours.size())


## ---------------------------------------------------------------------- putting up a card

func _offer(offer: Dictionary) -> void:
	var kind := int(offer["kind"])
	var district_id := String(offer["region_id"])
	var target: Dictionary = offer["target"]
	var target_id := int(target["id"]) if not target.is_empty() else -1
	if _has(kind, district_id, target_id):
		return
	if _count_kind(kind) >= KIND_LIMIT:
		return
	var score := clampf(float(offer["score"]), 0.0, 1.0)
	if score < MIN_OFFER:
		return
	_serial += 1
	var word := String(CALLSIGN.get(kind, "STAFF"))
	_words[word] = int(_words.get(word, 0)) + 1
	var secondaries := []
	for record in _enemy_in(district_id):
		var object: Dictionary = record
		if int(object["id"]) != target_id:
			secondaries.append(int(object["id"]))
	var mission := {
		"id": "M%04d" % _serial,
		"callsign": "%s %d" % [word, int(_words[word])],
		"type": String(KIND_NAME.get(kind, "MISSION")),
		"kind": kind,
		"faction": _faction,
		"region_id": district_id,
		"region_name": _name(district_id),
		"primary_target": target_id,
		"target_name": String(target["name"]) if not target.is_empty() else "",
		"secondary_targets": secondaries,
		"priority": clampi(1 + int(round(score * 4.0)), 1, 5),
		"status": AVAILABLE,
		"threat_level": _threat(district_id),
		"created_at": _tick,
		"expires_at": _tick + int(WINDOW.get(kind, 20)),
		"outcome": "",
		"reason": "",
		"score": score,
		"operation": _operation(district_id),
		"basis": _basis_of(kind, district_id, target_id),
	}
	mission["briefing"] = _briefing(kind, district_id, target, offer)
	mission["strategic_effect"] = _effect(kind, district_id)
	_missions.append(mission)
	_by_id[String(mission["id"])] = mission
	mission_created.emit(mission)


## The line a card prints and a pilot reads, naming the fact that put the mission on the
## board -- so an offer that looks wrong on the map is arguable with the staff rather than a
## mystery to whoever is flying it.
func _briefing(kind: int, district_id: String, target: Dictionary, offer: Dictionary) -> String:
	var place := _name(district_id)
	var site := String(target["name"]) if not target.is_empty() else "the objective"
	match kind:
		Kind.SEAD:
			return "%s at %s is holding the air down. Take it out and the corridor opens." \
				% [site, place]
		Kind.STRIKE:
			return "%s is ours to work over. Strike %s and what the enemy keeps stops holding it." \
				% [place, site]
		Kind.CAS:
			return "Our ground is attacking into %s with the enemy still standing in it. Work %s." \
				% [place, site]
		Kind.INTERCEPT:
			return "The enemy is going into %s and we do not own the air over it. Get there first." \
				% place
		Kind.CAP:
			return "%s is ours and the airspace over it is not. Cover the line and keep it so." \
				% place
		Kind.ESCORT:
			return "Package %s is working into %s without escort. Fly with it." \
				% [String(offer.get("for", "the strike")), place]
		Kind.AIRBASE_DEFENCE:
			return "%s is taking damage with %s still firing into it. Clear it or the field dies." \
				% [place, site]
		Kind.GROUND_INTERDICTION:
			return "%s is feeding an attack across the line. Cut what stands at %s." \
				% [place, site]
	return "Strategic tasking over %s." % place


func _effect(kind: int, district_id: String) -> String:
	var place := _name(district_id)
	match kind:
		Kind.SEAD:
			return "Opens the corridor over %s for strike packages." % place
		Kind.STRIKE:
			return "Removes what the enemy keeps standing in %s." % place
		Kind.CAS:
			return "Speeds the capture of %s and the ground that has to take it." % place
		Kind.INTERCEPT:
			return "Blunts the enemy attack into %s." % place
		Kind.CAP:
			return "Holds the air over %s so the rear stays usable." % place
		Kind.ESCORT:
			return "Keeps our own packages alive long enough to matter." % place
		Kind.AIRBASE_DEFENCE:
			return "Protects the sortie effort generating from %s." % place
		Kind.GROUND_INTERDICTION:
			return "Slows the enemy logistics building through %s." % place
	return "Affects the balance over %s." % place


## HIGH, MEDIUM, LOW, from the two things that actually shoot at a package: how much of the
## air the enemy has, and how many sites are standing within reach of the ground being flown
## to.
func _threat(district_id: String) -> String:
	var denial := 1.0 - _air(district_id)
	var sites := _standing_sites_in_reach(district_id).size()
	if denial >= 1.0 - CLEAR_AIR or sites >= 2:
		return "HIGH"
	if denial <= 1.0 - HOLD_AIR and sites == 0:
		return "LOW"
	return "MEDIUM"


## ----------------------------------------------------------------------------- judging

## How bad the problem is, as one number that can only move with the campaign's own state.
## Positive means the district is harder to fly over; a mission succeeds when the number has
## fallen far enough, or when the thing it was sent against has stopped standing.
func _problem(kind: int, district_id: String, target_id: int) -> float:
	match kind:
		Kind.SEAD, Kind.AIRBASE_DEFENCE, Kind.CAP, Kind.INTERCEPT, Kind.ESCORT:
			return 1.0 - _air(district_id)
		Kind.STRIKE, Kind.CAS:
			if _gone(_target(target_id)):
				return 0.0
			return float(_district(district_id)["presence"].get(_foe(), 0.0))
		Kind.GROUND_INTERDICTION:
			if _gone(_target(target_id)):
				return 0.0
			return float(_district(district_id)["presence"].get(_foe(), 0.0)) \
				* clampf(float(_district(district_id)["infrastructure"]), 0.0, 1.0)
	return 0.0


func _basis_of(kind: int, district_id: String, target_id: int) -> Dictionary:
	return {"problem": _problem(kind, district_id, target_id)}


func _gain(mission: Dictionary) -> float:
	var basis: Dictionary = mission.get("basis", {})
	var before := float(basis.get("problem", 0.0))
	var kind := int(mission["kind"])
	var district_id := String(mission["region_id"])
	var target_id := int(mission["primary_target"])
	return before - _problem(kind, district_id, target_id)


## Whether the mission's own reason for existing has been settled, as opposed to merely
## improved. An air job is settled when we hold the district; a bomb is settled when the
## target is not standing in it any more.
func _settled(mission: Dictionary) -> bool:
	var kind := int(mission["kind"])
	var district_id := String(mission["region_id"])
	var target_id := int(mission["primary_target"])
	# A bomb is settled when the thing it was aimed at has stopped standing. An area job is
	# settled when the air over the ground it was flown to is ours. An interdiction into a
	# district with nothing worth hitting in it is settled by the district being quieter,
	# which is the only reading of it the campaign actually publishes.
	if target_id >= 0 and kind in [
			Kind.SEAD, Kind.STRIKE, Kind.CAS, Kind.AIRBASE_DEFENCE, Kind.GROUND_INTERDICTION]:
		return _gone(_target(target_id))
	if kind in [Kind.CAP, Kind.INTERCEPT, Kind.ESCORT]:
		return _air(district_id) >= HOLD_AIR
	if kind == Kind.GROUND_INTERDICTION:
		return _gain(mission) >= GOAL
	return _air(district_id) >= HOLD_AIR


func _count_open() -> int:
	var count := 0
	for record in _missions:
		var mission: Dictionary = record
		if String(mission["status"]) in OPEN:
			count += 1
	return count


func _count_kind(kind: int) -> int:
	var count := 0
	for record in _missions:
		var mission: Dictionary = record
		if String(mission["status"]) in OPEN and int(mission["kind"]) == kind:
			count += 1
	return count


func _has(kind: int, district_id: String, target_id: int) -> bool:
	for record in _missions:
		var mission: Dictionary = record
		if String(mission["status"]) not in OPEN:
			continue
		if int(mission["kind"]) != kind or String(mission["region_id"]) != district_id:
			continue
		# An area job over a district is one offer, whatever else stands in it. A job with an
		# objective is one offer per objective, because two sites in one district are two
		# sites and the war does not treat them as a single problem.
		if target_id < 0 or int(mission["primary_target"]) == target_id:
			return true
	return false


func _open(id: String) -> Dictionary:
	return _by_id.get(id, {})


## -------------------------------------------------------------------------- resolving

## Three answers and one retirement, and the retirement carries the distinction that makes
## the board mean something: a mission that was never flown cannot succeed, however good the
## news is, because the effect it was raised for came from somewhere else.
func _resolve() -> void:
	for record in _missions:
		var mission: Dictionary = record
		var status := String(mission["status"])
		if status in CLOSED:
			continue
		if status != ACTIVE:
			if _settled(mission):
				_retire(mission, EXPIRED, "somebody else dealt with it")
			elif _tick > int(mission["expires_at"]):
				_retire(mission, EXPIRED, "the window closed")
			continue
		if _settled(mission):
			if _gone(_target(int(mission["primary_target"]))):
				_retire(mission, SUCCESS, "%s is down" % String(mission["target_name"]))
			else:
				_retire(mission, SUCCESS, "the air over %s is ours" % String(mission["region_name"]))
		elif _gain(mission) >= GOAL:
			_retire(mission, SUCCESS, "the problem it was raised on has gone")
		elif _gain(mission) >= PARTIAL_GAIN:
			_retire(mission, PARTIAL, "the district is easier to fly over than it was")
		else:
			_retire(mission, FAILED, "nothing the enemy has there changed")


func _retire(mission: Dictionary, status: String, reason: String) -> void:
	mission["status"] = status
	mission["outcome"] = status
	mission["reason"] = reason
	mission["closed_at"] = _tick
	# §33's four events, and this is where the last two of them come from: a success is the
	# campaign agreeing that the reason the mission existed no longer does, and everything
	# else -- a partial, a failure, a window that ran out over ground someone else quieted --
	# is a failure to fly, which is what the caller with an after-action screen needs to hear.
	var id := String(mission["id"])
	if status == SUCCESS:
		mission_completed.emit(id, status)
	else:
		mission_failed.emit(id, reason)


## A resolved mission stays readable for a few ticks -- long enough for a card to be opened
## on the answer -- and then leaves the board, so the marks on the map are only ever the jobs
## that can still be flown.
func _prune() -> void:
	var kept := []
	_by_id = {}
	for record in _missions:
		var mission: Dictionary = record
		if String(mission["status"]) in CLOSED \
				and _tick - int(mission.get("closed_at", _tick)) > RESOLVED_KEEP:
			continue
		kept.append(mission)
		_by_id[String(mission["id"])] = mission
	_missions = kept


static func _harder(a: Dictionary, b: Dictionary) -> bool:
	if int(a["priority"]) != int(b["priority"]):
		return int(a["priority"]) > int(b["priority"])
	return float(a["score"]) > float(b["score"])


## Candidates are ranked before they have priorities: the offer with the most weight behind
## it is the one that gets a slot, and the priority it would have been given falls out of the
## same figure.
static func _weightier(a: Dictionary, b: Dictionary) -> bool:
	return float(a["score"]) > float(b["score"])
