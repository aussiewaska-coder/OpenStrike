extends RefCounted

## The two minds on top of the war.
##
## `war_director.gd` knows where the pressure is and does nothing with the knowledge.
## `mission_director.gd` knows how to write a tasking and does not decide what it is for.
## Between them is §15: a commander that looks at the published state, scores the nine things a
## commander could be trying to do, and commits to the best few it can afford. This decides what
## the war is being fought for over a piece of ground; the staff turns that into a mission a
## pilot can accept; the flight AI, which this module does not touch, decides how the resulting
## fight is flown.
##
## The score is the brief's, term for term:
##
##     score = strategic_value x urgency x vulnerability x available_force x commander_priority
##
## and every one of the five is a number this module can point at in the campaign's own tables,
## which is the only reason the debug overlay (§37) is allowed to print the answer with a reason
## beside it. Nothing here is random and nothing here is scheduled, so a decision that looks
## wrong is arguable with the state that produced it -- §36's "debuggable enough to inspect why
## something happened" is the whole design constraint.
##
## What it is read-only over, it is read-only over: no district state is written, no aircraft is
## spawned, and no third verb is added to the war. §13's two seams -- sightings and facility
## damage -- belong to the flying world, and a commander that reported its own intentions as
## evidence would be inventing a fact about the sky. The one thing kept here is the commander's
## own memory, keyed by the director's district ids, because §25's rule that a thing has one
## name applies to a pattern as much as to a target.
##
## That memory is the whole of §16's agentic feel. The war decays a sighting on purpose, because
## intelligence is supposed to go stale; a pattern is the opposite thing -- what the other side
## has kept doing for the last several minutes. Slowing the director's decay to remember it would
## corrupt what the campaign knows, so the pattern is remembered here instead, where it can be as
## long-lived as a habit needs to be. Red's commander therefore knows that Blue keeps working the
## same district long after that district's own picture of it has faded, and scores an operation
## over it accordingly. No LLM and no network in the loop, which is what makes the response the
## same one twice and therefore testable.

signal operation_opened(operation: Dictionary)
signal operation_closed(id: String, reason: String)

const CONTROL := preload("res://scripts/war/war_control.gd")
const OBJECTS := preload("res://scripts/war/war_objects.gd")
const DIRECTOR := preload("res://scripts/war/war_director.gd")

## §15's nine, spelled as the brief spells them and evaluated in that order. An objective this
## world cannot justify -- there is no radar entity in the corridor -- scores nothing and is
## simply not committed to, which is the discipline the object layer uses when it reports a type
## as `· NONE` instead of drawing an estimate of one.
enum Objective {
	DEFEND_REGION,
	CAPTURE_REGION,
	GAIN_AIR_SUPERIORITY,
	DEFEND_AIRBASE,
	SUPPRESS_SAM,
	DESTROY_RADAR,
	INTERDICT_SUPPLY,
	SUPPORT_GROUND_ATTACK,
	INTERCEPT_AIRCRAFT,
}

## The overlay's `Objective:` line prints these. §37's example names the objective *and the
## ground it is about*, so `OBJECTIVE_VERB` is the half that reads as English and the district's
## own name is the other half: `DEFEND TWEED HEADS`, not an enum with a place stapled on.
const OBJECTIVE_NAME := {
	Objective.DEFEND_REGION: "DEFEND REGION",
	Objective.CAPTURE_REGION: "CAPTURE REGION",
	Objective.GAIN_AIR_SUPERIORITY: "GAIN AIR SUPERIORITY",
	Objective.DEFEND_AIRBASE: "DEFEND AIRBASE",
	Objective.SUPPRESS_SAM: "SUPPRESS SAM",
	Objective.DESTROY_RADAR: "DESTROY RADAR",
	Objective.INTERDICT_SUPPLY: "INTERDICT SUPPLY",
	Objective.SUPPORT_GROUND_ATTACK: "SUPPORT GROUND ATTACK",
	Objective.INTERCEPT_AIRCRAFT: "INTERCEPT AIRCRAFT",
}

const OBJECTIVE_VERB := {
	Objective.DEFEND_REGION: "DEFEND",
	Objective.CAPTURE_REGION: "CAPTURE",
	Objective.GAIN_AIR_SUPERIORITY: "AIR SUPERIORITY OVER",
	Objective.DEFEND_AIRBASE: "DEFEND AIRBASE AT",
	Objective.SUPPRESS_SAM: "SUPPRESS SAM AT",
	Objective.DESTROY_RADAR: "DESTROY RADAR AT",
	Objective.INTERDICT_SUPPLY: "CUT SUPPLY IN",
	Objective.SUPPORT_GROUND_ATTACK: "SUPPORT ATTACK INTO",
	Objective.INTERCEPT_AIRCRAFT: "INTERCEPT OVER",
}

## The four objectives that are flown by being over ground and staying there, as opposed to going
## somewhere once. These are what a fighter CAP is, what §16 says Red redirects first, and the
## only ones whose weight reaches the enemy formation's intent: a district Red has committed to
## defending is a district in which the pilot flying into it finds fighters.
const AIR_PRESENCE := [
	Objective.DEFEND_REGION,
	Objective.GAIN_AIR_SUPERIORITY,
	Objective.DEFEND_AIRBASE,
	Objective.INTERCEPT_AIRCRAFT,
]

## Doctrine: §15's `commander_priority`, and the only term in the product that is not a fact
## about the world. Two commanders reading one campaign ought to decide differently, or the war
## is a mirror rather than an opponent -- so each side is allowed a taste, in a band narrow
## enough that it settles a contest between two near-equal objectives and cannot put a quiet
## district on top of the list by itself. Blue buys the air and the sites, because it is the side
## that has to fly into somebody else's corridor; Red buys fighters and its own ground, because
## it is the side being flown into.
const DOCTRINE := {
	CONTROL.FRIENDLY: {
		Objective.DEFEND_REGION: 0.95,
		Objective.CAPTURE_REGION: 1.05,
		Objective.GAIN_AIR_SUPERIORITY: 1.20,
		Objective.DEFEND_AIRBASE: 1.10,
		Objective.SUPPRESS_SAM: 1.25,
		Objective.DESTROY_RADAR: 1.10,
		Objective.INTERDICT_SUPPLY: 0.90,
		Objective.SUPPORT_GROUND_ATTACK: 1.00,
		Objective.INTERCEPT_AIRCRAFT: 0.85,
	},
	CONTROL.ENEMY: {
		Objective.DEFEND_REGION: 1.20,
		Objective.CAPTURE_REGION: 0.90,
		Objective.GAIN_AIR_SUPERIORITY: 1.05,
		Objective.DEFEND_AIRBASE: 1.15,
		Objective.SUPPRESS_SAM: 0.80,
		Objective.DESTROY_RADAR: 0.80,
		Objective.INTERDICT_SUPPLY: 0.95,
		Objective.SUPPORT_GROUND_ATTACK: 0.95,
		Objective.INTERCEPT_AIRCRAFT: 1.30,
	},
}

## -------------------------------------------------------------------------- the memory
##
## Half of these constants exist because the war's own numbers change too fast to read a habit
## off them, and half because a habit that never expired would keep reacting to a raid nobody
## has flown in three campaigns.

## How much of a district's pattern survives a tick with nobody in it. Measured, not chosen: a
## tick in a district is worth 0.155 of weight, because the commander reads the tick's own
## `SIGHTING_STEP` of 0.1 *and* the 0.055 the war left behind when it decayed the previous one.
## At this rate the term is full after the twenty-odd ticks of continuous work that a pilot
## actually makes a habit of a valley out of, and half-dead about eleven ticks after they leave.
const HABIT_DECAY := 0.94
const HABIT_FULL := 2.4
## The other half of the same fact, in the units a reason is written in: how many of the last N
## ticks the other side was seen in the district. A weight answers "how hard" and a count answers
## "how often", and `INTERCEPT OVER a district the enemy has entered twelve times in the last
## thirty-odd ticks` is a decision a human can argue with. The window is as long as the weight's
## useful life on purpose: a count that ran out first produced a reason saying the enemy had
## worked a ground in 0 of the last 20 ticks while the memory that raised the operation was
## still two-thirds full, which is an explanation that contradicts itself.
const PATTERN_WINDOW := 32
## A tick with less evidence than this in it is a district nobody is in. The director leaves a
## sighting's tail decaying for several ticks and the tail is not a visit: 0.1 is one tick of
## presence, 0.055 is the memory of the last one.
const SEEN_MIN := 0.08
## The pattern floor for a district to be worth fighters over at all, and the level above which
## the pattern is named in the reason whatever the objective was.
const HABIT_INTEREST := 0.2
const HABIT_NOTABLE := 0.35

## ----------------------------------------------------------------------- the commitment

## A district's authored value has to be worth a sortie for the pattern in it to matter. The same
## floor the staff uses, so the two modules cannot disagree about which counties are worth flying
## to and which are only ground.
const MIN_DISTRICT_VALUE := 0.25
## The floor an objective has to clear to take a slot, and the reference a focus weight is scaled
## against. Both measured off this theatre's own scores rather than chosen: five fractions
## multiplied together make small numbers, and a commander whose every idea clears its floor by a
## hundredth has no floor.
const MIN_OPERATION := 0.03
const SCORE_FULL := 0.16
## A commander with no focus is a list. Four operations is what a board can be seen to be about,
## and §16's "reduce offensive operations elsewhere" needs the elsewhere to exist.
const OPERATION_LIMIT := 4
## Two in one district is as much concentration as this allows: an air battle and a ground fight
## over the same towns are different jobs, but four names for one problem is a report repeating
## itself.
const PER_DISTRICT := 2
## What one committed operation costs the next one. This is the mechanic behind reducing
## operations elsewhere -- the effort is spent, so the fifth idea scores lower whatever the map
## says about it -- and the floor is why a fully committed side can still react to news.
const OPERATION_COST := 0.22
const RESERVE_FLOOR := 0.4
## An operation whose reason has gone is given this many ticks to come back before it is closed,
## for the director's own reason (`SETTLE_AT`): one quiet tick is a fluctuation, and cancelling
## and re-raising the same operation every other tick is a report flickering rather than a
## decision being held to.
const STALE_TICKS := 3

## -------------------------------------------------------------- what the staff is told
##
## The factor this module contributes to a mission score, per district: the commander's voice in
## a choice the raw arithmetic would otherwise make on its own. A district committed over is
## worth more than the state says; a district the commander has left alone is worth less -- not
## zero, because the war publishes reasons to fly that no commander has thought of yet, and a
## staff that could only ever echo its commander is a script with extra arithmetic in it.
const UNFOCUSED := 0.72
const FOCUS_STEP := 0.34
const FOCUS_MAX := 1.45

## The rest are the terms' own shapes, and each one is a number a test can put its finger on.

## How much of an air, ground or presence balance has to move in one tick for the commander to
## call it a slide rather than a wobble.
const SLIP_FULL := 0.06
## How much damage a field has to have taken to be worth defending, and how much of a tick's
## change counts as the damage increasing. Between the two, a cratered field the crews have
## already filled is not a threatened field.
const FIELD_AT_RISK := 0.1
const FIELD_TREND := 0.02
## A whole field's worth of airframes, for the term that asks how much of a side's effort is
## standing at one ramp. The corridor's airport seats eight, which is what this is scaled to.
const FIELD_CAPACITY := 8.0
## A site is worth attacking whole, but a wounded one is a better bet: this is the difference
## between a plan and a gamble, and it is the only reason an objective can get more attractive
## because someone else has already been at it.
const BROKEN_BET := 0.35
## An air defence coverage of a district is worth 1/3 of the winnability term per site: three
## standing sites in reach make the sky over a district somebody else's, for the purposes of
## deciding whether to go and get it.
const COVERAGE_SITE := 0.3
## The enemy presence a district has to have before cutting its lines is worth the sortie, and
## the effort a district fully covered by committed operations is worth -- the 0..1 axis the
## enemy formation reads as intent.
const MIN_HOSTILE := 0.1
const EFFORT_FULL := 0.3

var _war: RefCounted
var _objects: RefCounted
var _geography: RefCounted
var _faction := CONTROL.FRIENDLY
var _operations := []
var _live := {}
var _focus := {}
var _pattern := {}
var _trends := {}
var _hits := {}
var _then := {}
var _wear := {}
var _tick := 0
var _serial := 0
var _ready := false


## ----------------------------------------------------------------------------- seating

## Take the three tables this reads, or clear the board for a theatre the campaign is not run
## over. The refusal empties first, which is the rule phase 5 established and phase 6 kept: a
## caller that survives a refusal keeps whatever was seated before it, and a commander that still
## had last theatre's districts in mind would commit operations over ground no longer loaded.
func setup(director: RefCounted, objects: RefCounted, geography: RefCounted = null) -> bool:
	clear()
	_ready = director != null and objects != null and geography != null \
		and director.has_method("district") and director.has_method("air_balance") \
		and director.has_method("active_battles") and director.has_method("facilities") \
		and director.has_method("supply") and director.has_method("presence") \
		and objects.has_method("objects") and objects.has_method("of") and objects.is_loaded() \
		and geography.has_method("region_at") and geography.has_method("adjacency") \
		and geography.has_method("region") \
		and not director.districts().is_empty()
	_war = director if _ready else null
	_objects = objects if _ready else null
	_geography = geography if _ready else null
	return _ready


func clear() -> void:
	_war = null
	_objects = null
	_geography = null
	_operations = []
	_live = {}
	_focus = {}
	_pattern = {}
	_trends = {}
	_hits = {}
	_then = {}
	_wear = {}
	_serial = 0
	_tick = 0
	_ready = false


func is_ready() -> bool:
	return _ready


func set_faction(faction: String) -> void:
	if faction in CONTROL.BLOCS:
		_faction = faction


func faction() -> String:
	return _faction


func tick_number() -> int:
	return _tick


## One turn of command: remember, stand down what has stopped being true, score the nine, commit
## to what can be afforded. In that order, so an operation closed this tick is not counted as
## spent effort against the one raised in its place.
func tick(tick_number: int) -> void:
	if not _ready:
		return
	_tick = tick_number
	_remember()
	_settle()
	_commit(_score())
	_prune()


## -------------------------------------------------------------------------- what it says

## The live operations, hardest first: the answer to "what is this side trying to do", and the
## list the staff's priorities are derived from.
func operations() -> Array:
	var found := []
	for record in _operations:
		var operation: Dictionary = record
		if String(operation["status"]) == "ACTIVE":
			found.append(operation)
	found.sort_custom(_harder)
	return found


func operation(id: String) -> Dictionary:
	for record in _operations:
		if String(record["id"]) == id:
			return record
	return {}


## The one the commander cares most about, which is what an overlay with one line prints.
func focused() -> Dictionary:
	var found := operations()
	return found[0] if not found.is_empty() else {}


func operations_in(district_id: String) -> Array:
	var found := []
	for record in operations():
		if String(record["region_id"]) == district_id:
			found.append(record)
	return found


## §15's fifth term, offered to the staff for the districts it is tasking over.
func priority_for(district_id: String) -> float:
	return float(_focus.get(district_id, UNFOCUSED)) if not _operations.is_empty() else 1.0


## How hard this commander is working the ground under a point, on the 0..1 axis the enemy
## formation reads as intent. Only the air-presence objectives count: an interdiction is flown
## once, and is not the reason a pilot finds fighters overhead.
func effort_at(at: Vector2) -> float:
	if not _ready:
		return 0.0
	var district_id := _district_at(at)
	if district_id.is_empty():
		return 0.0
	var weight := 0.0
	for record in operations():
		var operation: Dictionary = record
		if String(operation["region_id"]) != district_id \
				or int(operation["objective"]) not in AIR_PRESENCE:
			continue
		weight += float(operation["score"])
	return clampf(weight / EFFORT_FULL, 0.0, 1.0)


## The whole reading in one dictionary, for the debug overlay and for a save file: what the
## commander is doing, what it remembers, and why.
func snapshot() -> Dictionary:
	var list := []
	for record in operations():
		list.append(record.duplicate(true))
	var remembered := {}
	for district_id in _pattern:
		var memory: Dictionary = _pattern[district_id]
		remembered[district_id] = {
			"habit": float(memory["weight"]),
			"visits": (memory["recent"] as Array).count(1),
		}
	return {
		"faction": _faction,
		"tick": _tick,
		"ready": _ready,
		"effort": available_force(),
		"operations": list,
		"priority": _focus.duplicate(),
		"pattern": remembered,
	}


## ---------------------------------------------------------------------- §28's save

## The decisions and the memory behind them, written out. What is here is what a commander *is*:
## the operations it is standing, which districts it has chosen to lean on, how often the enemy
## was seen where, and the last reading of every level and airfield it is differencing against.
## What is not here is anything the war itself owns -- no district state, no facility health, no
## supply. The reload hands this back to a module already seated on a restored war, and a save
## that carried the map twice would be a second copy of a thing that has one home (§25).
func export_state() -> Dictionary:
	var operations := []
	for record: Dictionary in _operations:
		operations.append(record.duplicate(true))
	var remembered := {}
	for district_id in _pattern:
		var memory: Dictionary = _pattern[district_id]
		remembered[String(district_id)] = {
			"weight": float(memory["weight"]),
			"recent": Array(memory["recent"]).duplicate(),
		}
	var before := {}
	for district_id in _then:
		before[String(district_id)] = _levels(_then[district_id])
	var slipping := {}
	for district_id in _trends:
		slipping[String(district_id)] = _levels(_trends[district_id])
	return {
		"faction": _faction,
		"tick": _tick,
		"serial": _serial,
		"operations": operations,
		"focus": _focus.duplicate(true),
		"pattern": remembered,
		"then": before,
		"trends": slipping,
		"wear": _numbers(_wear),
		"hits": _numbers(_hits),
	}


## Hand it back. The rule the director keeps and the staff keeps: refuse a state that does not
## belong to the side seated here rather than apply part of it, because a BLUE commander given
## RED's operations would task a staff over districts its own war does not name. `_live` is not
## saved -- it is the same dictionaries as `_operations`, indexed by the key this module derives
## from them, so rebuilding the index is the only honest way to restore it.
func import_state(state: Dictionary) -> bool:
	if not _ready or state.is_empty():
		return false
	if String(state.get("faction", "")) != _faction:
		return false
	var operations: Variant = state.get("operations", [])
	if not (operations is Array):
		return false
	for record in operations:
		if not _holds(record, SAVED_OPERATION):
			return false
		var operation := record as Dictionary
		if _district(String(operation["region_id"])).is_empty():
			return false
	var pattern := _table(state, "pattern")
	for district_id in pattern:
		if not _holds(pattern[district_id], SAVED_MEMORY):
			return false
		if _district(String(district_id)).is_empty():
			return false

	var focus := _table(state, "focus")
	var levels := _table(state, "then")
	var rates := _table(state, "trends")
	for district_id in levels:
		if not _holds(levels[district_id], SAVED_LEVEL) \
				or _district(String(district_id)).is_empty():
			return false
	for district_id in rates:
		if not _holds(rates[district_id], SAVED_LEVEL) \
				or _district(String(district_id)).is_empty():
			return false

	_operations = []
	_live = {}
	for record in operations:
		var operation: Dictionary = _kept(record as Dictionary, SAVED_OPERATION)
		_operations.append(operation)
		if String(operation["status"]) == "ACTIVE":
			_live[_key_of(operation)] = operation
	_focus = {}
	for district_id in focus:
		_focus[String(district_id)] = float(focus[district_id])
	_pattern = {}
	for district_id in pattern:
		var memory: Dictionary = pattern[district_id]
		var window := []
		for visit in memory["recent"]:
			window.append(int(visit))
		_pattern[String(district_id)] = {"weight": float(memory["weight"]), "recent": window}
	_then = {}
	for district_id in levels:
		_then[String(district_id)] = _levels(levels[district_id] as Dictionary)
	_trends = {}
	for district_id in rates:
		_trends[String(district_id)] = _levels(rates[district_id] as Dictionary)
	_wear = _restore(_table(state, "wear"))
	_hits = _restore(_table(state, "hits"))
	_tick = int(state.get("tick", _tick))
	_serial = int(state.get("serial", _serial))
	return true


## The terms an operation must arrive with. `target` is an object id the registry puts back
## itself, and `factors` is the six published numbers the reason sentence was made of.
const SAVED_OPERATION := ["id", "faction", "objective", "objective_name", "label", "region_id",
	"region_name", "target", "target_name", "air_effort", "score", "factors", "reason",
	"status", "opened_at", "held", "quiet"]

const SAVED_MEMORY := ["weight", "recent"]

const SAVED_LEVEL := ["air", "ground", "hostile"]


## One reading of a district, copied through the three terms it is made of.
func _levels(level: Dictionary) -> Dictionary:
	return {
		"air": float(level["air"]),
		"ground": float(level["ground"]),
		"hostile": float(level["hostile"]),
	}


## A table keyed by object id, written with the keys the file can carry.
func _numbers(table: Dictionary) -> Dictionary:
	var written := {}
	for object_id in table:
		written[str(int(object_id))] = float(table[object_id])
	return written


## ...and read back through the ids this module actually indexes by.
func _restore(written: Dictionary) -> Dictionary:
	var table := {}
	for object_id in written:
		table[int(object_id)] = float(written[object_id])
	return table


func _holds(record: Variant, terms: Array) -> bool:
	if not (record is Dictionary):
		return false
	for term in terms:
		if not (record as Dictionary).has(term):
			return false
	return true


## Copy a saved record through its own list, so a key the file invented cannot walk into the live
## campaign. The whole-number terms are put back as ints, because JSON has one number type and
## this module holds an objective, a target id and four counters: `%d` on a float prints `3.0`,
## and an operation whose `held` came back as a float is the same operation printed wrongly.
func _kept(record: Dictionary, terms: Array) -> Dictionary:
	var copy := {}
	for term in terms:
		copy[term] = int(record[term]) if term in SAVED_WHOLE else record[term]
	if record.has("closed_at"):
		copy["closed_at"] = int(record["closed_at"])
	return copy


const SAVED_WHOLE := ["objective", "target", "opened_at", "held", "quiet"]


## The same guard the director's read keeps: a section that is not a table reads as an empty one,
## so a malformed file is refused rather than crashed on halfway through.
func _table(state: Dictionary, key: String) -> Dictionary:
	var section: Variant = state.get(key, {})
	return section if section is Dictionary else {}


## ------------------------------------------------------------------------ remembering

## Fold this tick's evidence into the pattern and take the differences the scoring reads as
## trends. Both are read off the district records the director has already published, so a
## sighting the flying world made and a card the map opens are answers to the same question --
## and both are taken *before* the levels are overwritten, because a difference measured against
## this tick is always zero.
func _remember() -> void:
	var foe := _foe()
	for record in _districts():
		var district_id := String(record)
		var own := _district(district_id)
		var seen := float(own["seen"].get(foe, 0.0))
		var memory: Dictionary = _pattern.get(district_id, {"weight": 0.0, "recent": []})
		memory["weight"] = float(memory["weight"]) * HABIT_DECAY + seen
		# The count is of ticks, not of sightings: a pilot who works a valley for five ticks has
		# entered it five times as far as a commander is concerned, and one who crossed it at
		# altitude is recorded once.
		var window: Array = memory["recent"]
		window.append(1 if seen >= SEEN_MIN else 0)
		while window.size() > PATTERN_WINDOW:
			window.pop_front()
		_pattern[district_id] = memory
		var air := _air(district_id)
		var ground := DIRECTOR.share_of(float(own["ground"]), _faction)
		var hostile := float(own["presence"].get(foe, 0.0))
		var before: Dictionary = _then.get(district_id, {})
		if not before.is_empty():
			_trends[district_id] = {
				"air": clampf((float(before["air"]) - air) / SLIP_FULL, 0.0, 1.0),
				"ground": clampf((ground - float(before["ground"])) / SLIP_FULL, 0.0, 1.0),
				"hostile": clampf((hostile - float(before["hostile"])) / SLIP_FULL, 0.0, 1.0),
			}
		_then[district_id] = {"air": air, "ground": ground, "hostile": hostile}
	for record in _fields():
		var field: Dictionary = record
		var object_id := int(field["object_id"])
		var damage := float(field["damage"])
		if _wear.has(object_id):
			_hits[object_id] = clampf(
				(damage - float(_wear[object_id])) / maxf(FIELD_TREND, 0.001), 0.0, 1.0)
		_wear[object_id] = damage


## The three rates this module reads, on the axis where positive means the situation is getting
## worse for us -- or better, in the ground term's case, where a side advancing is the reason an
## attack is worth reinforcing. A level says how bad things are; a rate says why now.
func _slipping(district_id: String) -> float:
	return float(_trends.get(district_id, {}).get("air", 0.0))


func _gaining(district_id: String) -> float:
	return float(_trends.get(district_id, {}).get("ground", 0.0))


func _filling(district_id: String) -> float:
	return float(_trends.get(district_id, {}).get("hostile", 0.0))


## §16's "airbase damage increasing", as a 0..1 rate.
func _being_hit(object_id: int) -> float:
	return float(_hits.get(object_id, 0.0))


## The retained pattern, normalised: 0 for ground the other side has never worked, 1 for ground
## it has been working continuously for the whole window.
func _habit(district_id: String) -> float:
	var memory: Dictionary = _pattern.get(district_id, {})
	if memory.is_empty():
		return 0.0
	return clampf(float(memory["weight"]) / HABIT_FULL, 0.0, 1.0)


func _visits(district_id: String) -> int:
	return (Array(_pattern.get(district_id, {"recent": []})["recent"])).count(1)


## ----------------------------------------------------------------------- scoring the nine

## Every candidate carries its five terms, so the number that ranked an operation and the
## sentence that explains it come out of the same arithmetic rather than out of a guess made
## afterwards.
func _score() -> Array:
	var candidates := []
	for builder in [_defend_region, _capture_region, _gain_air_superiority, _defend_airbase,
			_suppress_sam, _destroy_radar, _interdict_supply, _support_ground_attack,
			_intercept_aircraft]:
		candidates.append_array(builder.call())
	for candidate in candidates:
		candidate["score"] = float(candidate["value"]) * float(candidate["urgency"]) \
			* float(candidate["exposure"]) * float(candidate["force"]) \
			* float(candidate["priority"])
	candidates.sort_custom(_weightier)
	return candidates


## Ground we hold that the other side is working on. Being shot at and being flown into are
## different emergencies: a district under attack is the reason to be interested this minute, and
## the enemy's pattern in the sky over it is the reason to stay interested after the attack has
## been repulsed. Presence on its own is a garrison doing its job, so it only counts when it is
## growing.
func _defend_region() -> Array:
	var found := []
	for record in _districts():
		var district_id := String(record)
		if not _owns(district_id):
			continue
		var own := _district(district_id)
		var value := float(own["value"])
		if value < MIN_DISTRICT_VALUE:
			continue
		var fire := clampf(float(own["under_fire"]) / 3.0, 0.0, 1.0)
		var denial := 1.0 - _air(district_id)
		found.append(_candidate(Objective.DEFEND_REGION, district_id, {},
			value, maxf(fire, _habit(district_id)) * 0.7 + _filling(district_id) * 0.3,
			clampf(0.6 * denial + 0.4 * _slipping(district_id), 0.0, 1.0)))
	return found


## Ground we do not hold and are already standing on. Opportunity rather than appetite: a
## district we merely would like is a wish, not an operation, which is why both terms below read
## the fight the war is already fighting instead of the map's opinions about it.
func _capture_region() -> Array:
	var found := []
	for record in _districts():
		var district_id := String(record)
		if _owns(district_id) or not _from_line(district_id):
			continue
		var own := _district(district_id)
		var value := float(own["value"])
		if value < MIN_DISTRICT_VALUE:
			continue
		var share := DIRECTOR.share_of(float(own["ground"]), _faction)
		var hostile := float(own["presence"].get(_foe(), 0.0))
		var forward := clampf(0.5 * share + 0.5 * maxf(_momentum(district_id), _gaining(district_id)),
			0.0, 1.0)
		found.append(_candidate(Objective.CAPTURE_REGION, district_id, {},
			value * (0.5 + 0.5 * _edge(district_id)), forward,
			clampf(0.6 * (1.0 - hostile) + 0.4 * _air(district_id), 0.0, 1.0)))
	return found


## The air itself as the objective: the ground whose sky we need and do not have, weighted by how
## winnable it is rather than by how much we would like it. Winnability is the term that makes
## the SEAD-then-strike chain read as one plan instead of two hopes -- a district the enemy's
## surviving sites are holding down is worth less to a commander than the same ground once they
## are not.
func _gain_air_superiority() -> Array:
	var found := []
	for record in _districts():
		var district_id := String(record)
		if not _from_line(district_id):
			continue
		var own := _district(district_id)
		var value := float(own["value"])
		if value < MIN_DISTRICT_VALUE:
			continue
		var denial := 1.0 - _air(district_id)
		var coverage := clampf(float(_standing_in_reach(district_id).size()) * COVERAGE_SITE, 0.0, 1.0)
		found.append(_candidate(Objective.GAIN_AIR_SUPERIORITY, district_id, {},
			value * (0.5 + 0.5 * _edge(district_id)),
			clampf(denial + 0.3 * _habit(district_id), 0.0, 1.0),
			clampf(1.0 - coverage, 0.0, 1.0)))
	return found


## A field of ours that is being cratered faster than it is being filled, and the enemy site
## doing it. The operation names the threat rather than the runway, because defending a damaged
## airfield means going after the thing shooting at it -- and that is the only way this objective
## can be argued with afterwards.
func _defend_airbase() -> Array:
	var found := []
	for record in _fields():
		var field: Dictionary = record
		var damage := clampf(float(field["damage"]), 0.0, 1.0)
		if damage < FIELD_AT_RISK:
			continue
		var district_id := String(field["region_id"])
		if district_id.is_empty():
			continue
		var threat := _standing_in_reach(district_id)
		var value := clampf(float(field["capacity"]) / FIELD_CAPACITY, 0.2, 1.0) \
			* maxf(float(_value_of(district_id)), MIN_DISTRICT_VALUE)
		var rising := _being_hit(int(field["object_id"]))
		found.append(_candidate(Objective.DEFEND_AIRBASE, district_id, _worst(threat),
			value, maxf(rising, damage * 0.5),
			clampf(0.5 * damage + 0.25 * minf(float(threat.size()) / 2.0, 1.0) \
				+ 0.25 * (1.0 - _air(district_id)), 0.0, 1.0)))
	return found


## §16's answer to the SAM coverage a corridor is protected by, and the objective Blue's whole
## opening loop turns on. A site's worth is the ground under it: a launcher in a county nobody is
## flying into suppresses nothing, and the campaign's own air model already says so.
func _suppress_sam() -> Array:
	var found := []
	for record in _foe_objects(OBJECTS.Type.SAM_SITE):
		var site: Dictionary = record
		var district_id := String(site["region_id"])
		if district_id.is_empty() or not _from_line(district_id):
			continue
		var denial := 1.0 - _air(district_id)
		var health := clampf(float(site["health"]), 0.0, 1.0)
		found.append(_candidate(Objective.SUPPRESS_SAM, district_id, site,
			float(site["strategic_value"]) * maxf(_value_of(district_id), 0.2),
			clampf(denial * health + 0.2 * _habit(district_id), 0.0, 1.0),
			BROKEN_BET + (1.0 - BROKEN_BET) * (1.0 - health)))
	return found


## Blinding: worth what the enemy can see, which is the district's own intelligence picture, and
## how much of that picture this set of emitters is contributing. Nothing in the corridor is a
## radar entity, so this builder returns an empty list there and the objective is never committed
## to -- which is the honest outcome, and the one that changes the day a radar is authored.
func _destroy_radar() -> Array:
	var found := []
	for record in _foe_objects(OBJECTS.Type.RADAR):
		var radar: Dictionary = record
		var district_id := String(radar["region_id"])
		if district_id.is_empty() or not _from_line(district_id):
			continue
		var health := clampf(float(radar["health"]), 0.0, 1.0)
		found.append(_candidate(Objective.DESTROY_RADAR, district_id, radar,
			float(radar["strategic_value"]) * maxf(_value_of(district_id), 0.2),
			clampf(float(_district(district_id)["intel"]) * health, 0.0, 1.0),
			BROKEN_BET + (1.0 - BROKEN_BET) * (1.0 - health)))
	return found


## The traffic, not the depot: what the enemy is pushing *out* of a district into an attack is
## what cutting it buys, so a quiet garrison with a full yard is left alone and a district feeding
## a battle is worth the sortie whatever its own state.
func _interdict_supply() -> Array:
	var found := []
	for record in _districts():
		var district_id := String(record)
		if _owns(district_id) or not _from_line(district_id):
			continue
		var own := _district(district_id)
		if float(own["value"]) < MIN_DISTRICT_VALUE:
			continue
		var hostile := float(own["presence"].get(_foe(), 0.0))
		var feeding := _feeding(district_id)
		if hostile < MIN_HOSTILE or feeding <= 0.0:
			continue
		found.append(_candidate(Objective.INTERDICT_SUPPLY, district_id, _best_foe(district_id),
			float(own["value"]) * (0.5 + 0.5 * hostile), feeding,
			clampf(float(own["infrastructure"]) \
				* (1.0 - 0.5 * clampf(float(own["supply"]), 0.0, 1.0)), 0.0, 1.0)))
	return found


## Our own attack, asked to go faster: the battles this side is starting, with the ground they are
## breaking against as the exposure. The target is whatever the enemy has standing in the district
## being attacked into, which is the same answer the staff's CAS offer gives.
func _support_ground_attack() -> Array:
	var found := []
	for record in _war.active_battles():
		var battle: Dictionary = record
		if String(battle["attacker"]) != _faction:
			continue
		var district_id := String(battle["to"])
		var own := _district(district_id)
		if own.is_empty():
			continue
		var hostile := float(own["presence"].get(_foe(), 0.0))
		var intensity := clampf(float(battle["intensity"]), 0.0, 1.0)
		found.append(_candidate(Objective.SUPPORT_GROUND_ATTACK, district_id, _best_foe(district_id),
			maxf(float(own["value"]), MIN_DISTRICT_VALUE), intensity,
			clampf(0.5 * hostile + 0.5 * (1.0 - _air(district_id)), 0.0, 1.0)))
	return found


## The response §16 asks for by name, and the only objective whose urgency comes out of the
## memory rather than out of the state: the ground the other side keeps flying into, whether or
## not anything in the district is still standing to notice. Exposure is deliberately generous at
## the bottom -- a district where we already own the sky is still worth a fighter patrol if the
## enemy insists on coming through it -- because the alternative is an objective that answers a
## habit only when it is already losing.
func _intercept_aircraft() -> Array:
	var found := []
	for record in _districts():
		var district_id := String(record)
		if not _from_line(district_id):
			continue
		var habit := _habit(district_id)
		if habit < HABIT_INTEREST:
			continue
		var own := _district(district_id)
		var denial := 1.0 - _air(district_id)
		found.append(_candidate(Objective.INTERCEPT_AIRCRAFT, district_id, {},
			maxf(float(own["value"]), MIN_DISTRICT_VALUE), habit,
			clampf(0.5 + 0.5 * denial, 0.0, 1.0)))
	return found


## --------------------------------------------------------------------------- committing

## Take the best few, in order, and let each one accepted make the next one cheaper to want. The
## reserve is applied here rather than inside the builders because it is a fact about the *list*
## of decisions: the fifth idea is worse than the first only once there have been four.
func _commit(candidates: Array) -> void:
	var taken := {}
	var accepted := 0
	for candidate in candidates:
		var key := _key(candidate)
		var district_id := String(candidate["region_id"])
		if accepted >= OPERATION_LIMIT:
			break
		# An operation carried over from last tick is not a new claim on the district's two slots;
		# it has already spent them.
		if not _live.has(key) and operations_in(district_id).size() >= PER_DISTRICT:
			continue
		var reserve := clampf(1.0 - float(accepted) * OPERATION_COST, RESERVE_FLOOR, 1.0)
		var score := clampf(float(candidate["score"]) * reserve, 0.0, 1.0)
		if score < MIN_OPERATION:
			continue
		taken[_raise(candidate, score)] = true
		accepted += 1
	for id in _live.keys():
		if not taken.has(id):
			_quiet(String(id))
	_focus = {}
	for record in operations():
		var operation: Dictionary = record
		var district_id := String(operation["region_id"])
		var weight := FOCUS_STEP * clampf(float(operation["score"]) / SCORE_FULL, 0.0, 1.0)
		_focus[district_id] = minf(float(_focus.get(district_id, 1.0)) + weight, FOCUS_MAX)


## A live operation is carried forward rather than rebuilt when it is justified again: the id, the
## tick it was raised and how many ticks it has been held all survive, because "we have been
## defending this for an hour" is a different fact from "we decided it four seconds ago" and the
## overlay prints the first one.
func _raise(candidate: Dictionary, score: float) -> String:
	var key := _key(candidate)
	var district_id := String(candidate["region_id"])
	var target: Dictionary = candidate["target"]
	var factors := {
		"value": float(candidate["value"]),
		"urgency": float(candidate["urgency"]),
		"exposure": float(candidate["exposure"]),
		"force": float(candidate["force"]),
		"priority": float(candidate["priority"]),
		"reserve": clampf(score / maxf(float(candidate["score"]), 0.0001), RESERVE_FLOOR, 1.0),
	}
	if _live.has(key):
		var again: Dictionary = _live[key]
		again["score"] = score
		again["factors"] = factors
		again["reason"] = _reason(candidate)
		again["quiet"] = 0
		again["held"] = int(again["held"]) + 1
		return String(again["id"])
	_serial += 1
	var objective := int(candidate["objective"])
	var operation := {
		"id": "%sO%04d" % [_faction.left(1), _serial],
		"faction": _faction,
		"objective": objective,
		"objective_name": String(OBJECTIVE_NAME.get(objective, "OPERATION")),
		"label": "%s %s" % [String(OBJECTIVE_VERB.get(objective, "OPERATE OVER")), _name(district_id)],
		"region_id": district_id,
		"region_name": _name(district_id),
		"target": int(target["id"]) if not target.is_empty() else -1,
		"target_name": String(target["name"]) if not target.is_empty() else "",
		"air_effort": objective in AIR_PRESENCE,
		"score": score,
		"factors": factors,
		"reason": _reason(candidate),
		"status": "ACTIVE",
		"opened_at": _tick,
		"held": 1,
		"quiet": 0,
	}
	_operations.append(operation)
	_live[key] = operation
	operation_opened.emit(operation)
	return String(operation["id"])


## The sentence §37 prints, made out of whichever terms are actually carrying the decision. It is
## not a flavour line: every clause below is a published number a test can fail on, which is the
## difference between an explanation and a decoration.
func _reason(candidate: Dictionary) -> String:
	var objective := int(candidate["objective"])
	var district_id := String(candidate["region_id"])
	var own := _district(district_id)
	var parts := []
	if _habit(district_id) >= HABIT_NOTABLE and _visits(district_id) > 0:
		parts.append("%s aircraft have worked %s in %d of the last %d ticks" \
			% [_foe(), _name(district_id), _visits(district_id), PATTERN_WINDOW])
	match objective:
		Objective.DEFEND_AIRBASE:
			parts.append("airbase damage increasing")
		Objective.DEFEND_REGION:
			if _slipping(district_id) > 0.0:
				parts.append("local air control declining")
			if float(own["under_fire"]) > 0.0:
				parts.append("ground battle in contact")
		Objective.CAPTURE_REGION, Objective.SUPPORT_GROUND_ATTACK:
			parts.append("our own attack is in contact")
		Objective.INTERCEPT_AIRCRAFT:
			parts.append("they keep coming through here")
		Objective.GAIN_AIR_SUPERIORITY, Objective.SUPPRESS_SAM:
			parts.append("we do not hold the air over it")
		Objective.DESTROY_RADAR:
			parts.append("the district is well watched")
		Objective.INTERDICT_SUPPLY:
			parts.append("the enemy is feeding an attack out of it")
	if parts.is_empty():
		parts.append("%s is worth %0.2f of the theatre" % [_name(district_id), float(candidate["value"])])
	var clause := " + ".join(parts)
	var site := String(candidate["target"].get("name", ""))
	if not site.is_empty() and objective in [Objective.SUPPRESS_SAM, Objective.DESTROY_RADAR,
			Objective.DEFEND_AIRBASE]:
		clause = "%s at %s: %s" % [site, _name(district_id), clause]
	return clause


## --------------------------------------------------------------------------- standing down

## An operation stops when the campaign has stopped justifying it, and that takes more than one
## tick of not being justified. A target that has stopped standing ends its own argument at once,
## because the thing the operation was aimed at is no longer a fact about the world.
func _settle() -> void:
	for record in _operations:
		var operation: Dictionary = record
		if String(operation["status"]) != "ACTIVE":
			continue
		if _finished(operation):
			_close(operation, "%s is not standing any more" % String(operation["target_name"]))
		elif _wrong_side(operation):
			_close(operation, "%s is not the situation it was raised on" % String(operation["region_name"]))


func _quiet(id: String) -> void:
	var operation: Dictionary = _live.get(id, {})
	if operation.is_empty() or String(operation["status"]) != "ACTIVE":
		return
	operation["quiet"] = int(operation["quiet"]) + 1
	if int(operation["quiet"]) > STALE_TICKS:
		_close(operation, "the reason went away")


func _finished(operation: Dictionary) -> bool:
	if int(operation["target"]) < 0:
		return false
	var target: Dictionary = _objects.of(int(operation["target"]))
	return not target.is_empty() \
		and String(target["operational_state"]) == OBJECTS.DESTROYED


## Two ways an area operation's subject stops being itself: ground we were defending that is not
## ours any more, and ground we were attacking that is. Either way the next tick's builders will
## raise the new situation under its own name rather than this one inheriting it.
func _wrong_side(operation: Dictionary) -> bool:
	var objective := int(operation["objective"])
	var district_id := String(operation["region_id"])
	if objective == Objective.DEFEND_REGION or objective == Objective.DEFEND_AIRBASE:
		return not _owns(district_id)
	if objective == Objective.CAPTURE_REGION:
		return _owns(district_id)
	return false


func _close(operation: Dictionary, reason: String) -> void:
	operation["status"] = "CLOSED"
	operation["closed_at"] = _tick
	operation["reason"] = "%s · %s" % [String(operation["reason"]), reason]
	_live.erase(_key_of(operation))
	operation_closed.emit(String(operation["id"]), reason)


## Closed operations leave the table, and the identity-free way to do it is to rebuild from the
## one thing that is authoritative about them: a live operation is in `_live` under its key, and
## anything else has been stood down.
func _prune() -> void:
	var kept := []
	for record in _operations:
		var operation: Dictionary = record
		if String(operation["status"]) == "ACTIVE" and _live.has(_key_of(operation)):
			kept.append(operation)
	_operations = kept


## ----------------------------------------------------------------------- the five terms

## A candidate before it is weighed: the three terms that come off the campaign's state, with the
## two that describe the commander rather than the map fitted here, so the whole product can be
## printed as the factors it was made of.
func _candidate(objective: int, district_id: String, target: Dictionary,
		value: float, urgency: float, exposure: float) -> Dictionary:
	return {
		"objective": objective,
		"region_id": district_id,
		"target": target,
		"value": clampf(value, 0.0, 1.0),
		"urgency": clampf(urgency, 0.0, 1.0),
		"exposure": clampf(exposure, 0.0, 1.0),
		"force": available_force(),
		"priority": float(DOCTRINE.get(_faction, {}).get(objective, 1.0)),
	}


## §15's `available_force`: what this side can put in the air at all. The depots set the tempo and
## the surviving fields set how many aircraft can be flying it, against the complement they would
## have parked undamaged. A side with no airfield in this theatre is not grounded, it is working
## from somewhere else, so the airframe term defaults to the stock rather than vetoing every idea
## the commander has -- the corridor's enemy is exactly that side, and it still defends itself.
func available_force() -> float:
	# Asked from outside the campaign's own clock -- the debug overlay and a save file both read
	# a commander that refused its theatre -- and a side with no war in front of it has no air.
	if not _ready:
		return 0.0
	var stock := clampf(_war.supply(_faction), 0.0, 1.0)
	var flying := 0
	var whole := 0
	for record in _fields():
		var field: Dictionary = record
		flying += int(field["aircraft"])
		whole += int(field["capacity"])
	var hulls := 0.6 if whole <= 0 else clampf(float(flying) / float(whole), 0.0, 1.0)
	return clampf(0.25 + 0.75 * stock * (0.4 + 0.6 * hulls), 0.0, 1.0)


static func _key(candidate: Dictionary) -> String:
	var target: Dictionary = candidate["target"]
	return "%d>%s>%d" % [int(candidate["objective"]), String(candidate["region_id"]),
		int(target["id"]) if not target.is_empty() else -1]


static func _key_of(operation: Dictionary) -> String:
	return "%d>%s>%d" % [int(operation["objective"]), String(operation["region_id"]),
		int(operation["target"])]


## Equal scores are broken by who asked first rather than by a coin, so that two runs of the same
## campaign over the same state produce the same board of operations.
static func _harder(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["score"]), float(b["score"])):
		return float(a["score"]) > float(b["score"])
	return int(a["opened_at"]) < int(b["opened_at"])


static func _weightier(a: Dictionary, b: Dictionary) -> bool:
	return float(a["score"]) > float(b["score"])


## ------------------------------------------------------------------------ the war, read
##
## The same questions the staff asks, asked the same way, so a commander and its own staff cannot
## disagree about where the front is or who is standing in it.

func _districts() -> Array:
	return _war.districts()


func _district(id: String) -> Dictionary:
	return _war.district(id)


func _air(id: String) -> float:
	return DIRECTOR.share_of(float(_war.air_balance(id)), _faction)


func _value_of(id: String) -> float:
	return float(_district(id).get("value", 0.0))


func _foe() -> String:
	return CONTROL.ENEMY if _faction == CONTROL.FRIENDLY else CONTROL.FRIENDLY


func _owns(id: String) -> bool:
	return String(_district(id).get("owner", CONTROL.NEUTRAL)) == _faction


## Ground a commander can do anything about: its own districts and the ones touching them. The
## same reach the war's own air battle is fought on, rather than a radius chosen for the map.
func _from_line(id: String) -> bool:
	if _owns(id):
		return true
	for neighbour in _neighbours(id):
		if _owns(String(neighbour)):
			return true
	return false


func _neighbours(id: String) -> Array:
	return (_geography.adjacency().get(id, {}) as Dictionary).keys()


## How much of a district's border is front rather than rear: the difference between covering an
## airfield and patrolling a county nobody is trying to take.
func _edge(id: String) -> float:
	var neighbours := _neighbours(id)
	if neighbours.is_empty():
		return 0.0
	var hostile := 0
	for neighbour in neighbours:
		if not _owns(String(neighbour)):
			hostile += 1
	return float(hostile) / float(neighbours.size())


## How far this side's own attack has got into a district.
func _momentum(id: String) -> float:
	var best := 0.0
	for record in _war.active_battles():
		var battle: Dictionary = record
		if String(battle["attacker"]) == _faction and String(battle["to"]) == id:
			best = maxf(best, clampf(float(battle["intensity"]), 0.0, 1.0))
	return best


## How far the other side's attack is being fed *out* of a district, which is the same question
## asked from the other end of the line.
func _feeding(id: String) -> float:
	var best := 0.0
	for record in _war.active_battles():
		var battle: Dictionary = record
		if String(battle["attacker"]) == _foe() and String(battle["from"]) == id:
			best = maxf(best, clampf(float(battle["intensity"]), 0.0, 1.0))
	return best


func _fields() -> Array:
	var found := []
	for record in _war.facilities():
		var field: Dictionary = record
		if String(field["faction"]) == _faction:
			found.append(field)
	return found


func _foe_objects(type: int) -> Array:
	var found := []
	for record in _objects.objects():
		var object: Dictionary = record
		if int(object["type"]) != type or String(object["faction"]) != _foe():
			continue
		if float(object["health"]) <= 0.0:
			continue
		found.append(object)
	return found


func _standing_in_reach(id: String) -> Array:
	var found := []
	for record in _foe_objects(OBJECTS.Type.SAM_SITE):
		var object: Dictionary = record
		var site := String(object["region_id"])
		if not site.is_empty() and _touches(site, id):
			found.append(object)
	return found


func _best_foe(id: String) -> Dictionary:
	var best := {}
	for record in _objects.objects():
		var object: Dictionary = record
		if String(object["faction"]) != _foe() or String(object["region_id"]) != id:
			continue
		if float(object["health"]) <= 0.0:
			continue
		if best.is_empty() or float(object["strategic_value"]) > float(best["strategic_value"]):
			best = object
	return best


## The site doing the most damage to the field: the strongest one still standing, which is the
## one the crews on the ramp are actually under.
func _worst(threat: Array) -> Dictionary:
	var worst := {}
	for record in threat:
		var site: Dictionary = record
		if worst.is_empty() or float(site["health"]) > float(worst["health"]):
			worst = site
	return worst


func _touches(here: String, there: String) -> bool:
	if here == there:
		return true
	return (_geography.adjacency().get(here, {}) as Dictionary).has(there)


func _district_at(at: Vector2) -> String:
	var region: Dictionary = _geography.region_at(at)
	return String(region.get("id", ""))


func _name(id: String) -> String:
	var region: Dictionary = _geography.region(id)
	return String(region["name"]) if not region.is_empty() else id
