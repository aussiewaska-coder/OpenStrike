extends RefCounted

## The war, running on its own schedule.
##
## Phase 3 said which ground belongs to whom. Phase 4 said what is standing on it.
## This is the part that changes both while nobody is watching: it keeps a strength
## for each side in every district, fights the battles the derived front line
## implies, spends and recovers what each side has to fight with, damages what the
## fighting passes over and repairs it when the shooting stops. Every number it
## reaches is published through `war_control.gd` and `war_objects.gd`, which are the
## two tables the map already reads, so the campaign needed no new rendering path to
## become visible -- the territory layer simply starts drawing ground that moved.
##
## The brief's split holds, and it is the reason this is a RefCounted rather than a
## node: WarDirector owns DATA, `battle_map*.gd` displays DATA, combat systems modify
## DATA through `report_sighting` and `damage_facility`. Nothing here knows what a
## district looks like, nothing draws, and nothing reads a Control. It is not a
## physics participant either, and has no per-frame work at all: the 5-15 second
## strategic tick of §14 is the smallest unit of time it recognises, and `advance` is
## what a caller with a frame has to offer it.
##
## What this deliberately is not: a commander, or a mission planner. It decides where
## the pressure is, which districts are worth taking, what each field can fly and who
## owns the air over a district. Phases 6 and 7 rank objectives and generate missions
## from those answers, and can be added without touching anything here; `reports` and
## `active_battles` are the seam they will be handed.
##
## The model is abstract on purpose. §12 asks for campaigns and advances rather than
## battalion micromanagement, so a district's strength is one number per side and a
## battle is that number moving. Air control is the -1..+1 balance §11 describes,
## published on the 0..1 share axis the district states were seeded with, where 0.5 is
## the contested middle -- which is how a signed simulation and an unsigned renderer
## agree without either of them translating twice.

signal ticked(tick: int)
signal region_changed(id: String, owner: String, previous: String)
signal battle_opened(battle: Dictionary)
signal battle_closed(battle: Dictionary, outcome: String)
signal facility_changed(object_id: int)

const CONTROL := preload("res://scripts/war/war_control.gd")
const OBJECTS := preload("res://scripts/war/war_objects.gd")

## §14: a strategic tick is 5-15 s of realtime, configurable, and never per frame.
const TICK_MIN := 5.0
const TICK_MAX := 15.0
const TICK_DEFAULT := 8.0

## The opening seed. Fixed, so that "run the simulation without a player" is a test
## with a repeatable answer rather than a different map every run; `set_seed` is what
## a campaign layer varies.
const OPENING_SEED := 20261002

## The band a district's ground balance has to sit inside to be called contested. Wide
## on purpose: a side has to leave the other holding less than about a third of the
## local strength before the line is allowed to move over it, which is what makes a
## district go contested *on the way* to changing hands instead of snapping from one
## colour straight to the other. The acceptance line -- territory naturally becoming
## contested and then changing ownership -- is this constant doing its job.
const CONTESTED_BAND := 0.35
## Leaving contested country takes more than entering it. A district that is nobody's is
## reported as nobody's until one side is in it past this much, which is the difference
## between a front that flickers colour every time a patrol is shot up and a front that
## moves when the ground has actually been taken. The opening map seeds its contested
## districts a little off centre, so without this a single exchange of fire would be
## reported as a conquest.
const CONTESTED_HOLD := 0.5
## How many ticks a district's new owner has to hold before the map is told. A district on
## a live front is a feedback loop: reporting it taken changes who attacks it and who
## bothers to, which changes whether it is held, which changes the report again. Before this
## rule existed one corridor district crossed the contested boundary 62 times in 200 ticks,
## at one tick per edge -- a square wave, which is a report flickering rather than a front
## moving. Ground that has genuinely gone over survives three ticks of its own consequences
## and is announced then; a district that only looked taken for a tick never is. What is
## held back is the owner and nothing else -- presences, balances, supply and the fights all
## keep moving on every one of those three ticks.
const SETTLE_TICKS := 3

## Below this neither side is meaningfully present and the district keeps the ground it
## had, rather than being claimed by whichever fraction happened to survive. Open
## country is not a trophy.
const PRESENT_MIN := 0.05
## Presence is a share of the district, so it is bounded by the district.
const PRESENT_MAX := 1.0
## How much of a district has to be stood on before which side is standing on it is
## believed. A ratio answers "who leans which way", and it will happily answer that
## question about two tokens of a patrol left in an empty town; this is the weight that
## says how much the answer is worth. At this much total presence the contest is taken at
## full measure, and below it for that much of itself -- so ground has to be occupied to be
## conquered, an empty district is contested country rather than a district won, and
## whichever fraction happened to survive a battle cannot claim a town that nobody is
## standing in.
const OCCUPY_AT := 0.5
## How much of a district one side has to be standing on alone before the district is
## reported as *held*. Below this the other side is still in it, and the answer to "who owns
## this place" is "both of them, at once" -- which is what contested means.
##
## This is not the paragraph above restated. A ratio is scale-free, and a scale-free number
## cannot tell an occupation from a rearguard action: measured on the corridor, one district
## on a live front spent 200 ticks with the defender holding between a third and a half of it
## while the attacker's share moved between 7 % and 18 %, and the ratio of those two numbers
## crossed the band that changes a district's colour 27 times. The defence never wavered; the
## *fraction of a token* swung. Weighting the balance by how much is actually stood on, and
## then asking whether the weaker claim is worth anything at all, is what makes a district
## change colour when it has been taken rather than when the arithmetic leaned.
##
## It also decides how a district is lost, and not only how it is held: ground falls by the
## defender being driven under this much, not by the attacker climbing to it, so an offensive
## that is only bleeding the other side cannot paint the map. The seeded minority presence in
## the opening situation is 0.15 for the enemy in friendly ground and 0.12 the other way, so
## this floor is above both of them and no district is handed over on its first tick.
const OWNED_MIN := 0.25
## And, like the two balance bands, this one has to be wider to leave than to enter: a
## district reported contested is only returned to a bloc once the weaker claim is under this
## much, which means someone has actually been driven out. Without the gap the front's
## hottest districts sat with their weaker side hovering at the threshold and were
## announced on every crossing of it -- measured at thirteen changes in one district over the
## last hundred ticks of a campaign whose map was otherwise finished by tick thirty. The
## seeded minority presences are 0.15 and 0.12, so this floor is below both and no opening
## district is reclassified by the rule that was written to stop reclassifying them.
const OWNED_KEEP := 0.10

## How far a field's fighter cover reaches: the district it stands in and, at reduced
## weight, the districts touching it. Adjacency rather than an invented radius,
## because the lattice already knows what is next to what, and a reach in kilometres
## would be a number this repository has no source for.
const COVER_OWN := 1.0
const COVER_NEAR := 0.55
## A surviving site denies air to its own district and the ones around it, weighted by
## the health `war_objects.gd` binds from the launcher field. The director reads that
## and never writes it: the field is the truth about its own launchers.
const SITE_DENIAL := 0.7
## Whoever holds the ground holds some of the air above it -- the short-range end of
## the same fact, and the reason an enemy district is never wholly denied to us the
## way a coverage circle would claim.
const GROUND_AIR := 0.35
## Cover is counted in sorties, so a parkable fleet of eight is a fraction of a
## district's air balance rather than the whole of it, and one aircraft seen from a
## cockpit is worth less again.
const AIRCRAFT_COVER := 0.15
const SIGHTING_AIR := 0.03
const SIGHTING_INTEL := 0.04
const SIGHTING_STEP := 0.1
const EVIDENCE_DECAY := 0.55
const AIR_RATE := 0.35
## Where neither side has anything in the sky, the balance falls back on the ground at
## half weight: holding the dirt is a weaker claim to the air than flying over it.
const AIR_GROUND_FALLBACK := 0.5

## Replacements arrive from the districts behind a line, so nobody can hold front
## ground they cannot reach. A district one side owns keeps a garrison -- rear areas
## hold what they were sitting on whatever the depots are doing -- while anything else
## is worth only what that side's own neighbours can spare, which is why a salient
## without a friendly flank quietly empties.
##
## A district in contact is not relieved at all: whatever is already there stays there
## unless the fighting moves it. Without that rule a side's logistics quietly unwind
## the authored opening -- a contested district with no friendly territory behind it
## would dissolve rather than be taken -- and the map would move on arithmetic instead
## of on a battle.
const REINF_RATE := 0.1
const GARRISON := 0.78
const NEIGHBOUR_WEIGHT := 0.45
## What a side's reach into ground it does not hold is worth, against what its own
## neighbours can spare. Well short of a garrison on purpose: a district nobody holds
## is held by fighting for it, not by being next to someone's depot.
const INFLUENCE_CAP := 0.35
const INFLUENCE_STOCK := 0.4
## How much of a side's strength its reserves buy -- for a rear garrison, for a
## district it is reaching into from outside, and for how fast a damaged field gets put
## back. None of them is ever purely a function of logistics: a side with nothing in the
## depots still holds the ground it was sitting on, still has someone to send forward,
## and still has crews to work a ramp.
const RESERVE_FLOOR := 0.45

## Fighting costs both sides in absolute terms -- what the other side put in is what
## you lost -- and moves the ground for whichever is winning. All rates are per tick,
## so the tick length is the only clock in the module. Attrition is per engagement and a
## district on a front is in several of them at once, so this is deliberately small: an
## hour of gunfire should not be worth more than a division.
const ATTRITION := 0.035
const PUSH := 0.10
## Attackers come on at even odds and win at good ones; below this the engagement is a
## firefight that changes nothing.
const STALE_AT := 0.02
const BATTLE_LIMIT := 40
const FATIGUE_FLOOR := 0.3
## A theatre is fed from three directions and spends in two. It draws a fixed allowance
## from the war effort behind it, which is what keeps a side that has lost its rear area
## in the fight instead of dissolving; it earns from the ground behind its own line,
## which is what conquest is for; and it rebuilds its stockpiles on a tick that spent
## nothing, which is what a quiet front is for. Against that it pays for every district
## it holds, more the further its presence reaches past its own line, and outright for
## every assault. The three earnings and the three spendings together are the governor on
## an offensive, and the fixed allowance and the recovery are why no campaign runs down to
## its floor once and then stays there like a photograph. Ground on a live front earns
## nothing and everything on it still has to be fed, so a side that has taken more
## districts than it can hold is poorer for them and slows down, which is the only thing in
## this model that can make anything stop.
const SUPPLY_BASE := 0.010
const SUPPLY_INCOME := 0.010
const SUPPLY_UPKEEP := 0.002
const SUPPLY_LINE := 0.006
const SUPPLY_FIGHT := 0.03
const SUPPLY_RECOVER := 0.010
## The pool never empties. A theatre with no fuel left is not a theatre that has stopped:
## it still holds its line, still shoots at anything that moves and still bleeds, at
## something like half the tempo of a rested one -- and half a tempo is the difference
## between a campaign that pauses to refit and one that freezes into a photograph of a
## front, which is the failure this whole table exists to avoid. Every coefficient the
## fighting reads out of supply is between its value here and its value at full stock, so
## this number is also the floor on how much worse an exhausted side is allowed to be.
const SUPPLY_FLOOR := 0.5

## §10: a field is not eliminated by one bomb. Damage is a number, repair is a rate that
## slows when the stock is thin and the air is hostile but never reaches zero, and the
## state falls out of how much of the field is left -- so a shelled ramp reads DAMAGED, a
## cratered runway OUT OF ACTION, and both come back unless the district stays under fire.
const REPAIR_RATE := 0.03
const OUT_OF_ACTION := 0.75
const DAMAGED_AT := 0.2
## A field's capacity is a staff estimate from the one published fact about it, its
## longest strip: 500 m of pavement stands for one deployable aircraft, four parked at
## the ramp whatever the length. The corridor's 2 492 m field generates eight; Sydney's
## 3 962 m generates eleven.
const AIRFRAME_PER_METRE := 500.0
const AIRFRAME_BASE := 4
## Fighting in a district takes something off the things standing in it, and off its
## infrastructure generally. Small per engagement, because a field that cannot survive
## a front settling near it is a field that will never be operational again: the
## corridor's airfield sits on the line and has to live with that.
const RAIL_WEAR := 0.006
const INFRA_WEAR := 0.3
const INFRA_REPAIR := 0.16
const INTEL_RATE := 0.25
## What a district's own intelligence picture tends toward: what you hold, and what you
## can fly over. Reconnaissance follows your own airspace, and the sightings the
## flying world reports are what push it above the line.
const INTEL_GROUND := 0.55
const INTEL_AIR := 0.3
const INTEL_BASE := 0.12

var _control: CONTROL
var _geography: RefCounted
var _objects: OBJECTS
## District id -> the simulated state. Deliberately not the published one: these are
## the signed balances and the two presences the tick computes with, and `state_of` is
## what they get folded into on the way out.
var _districts := {}
var _battles := {}
## The districts with a hostile edge this tick. Replacements are allowed to build a
## line up but not to thin it, so this is what separates a rear area from a front one.
var _contact := {}
var _facilities := {}
var _sites := []
var _neighbours := {}
var _resources := {}
var _losses := {}
var _tick := 0
var _elapsed := 0.0
var _length := TICK_DEFAULT
var _rng := RandomNumberGenerator.new()


## Take the situation, the geography it sits on and, when there is one, the objects the
## war is fought over. Without the third the war still runs and still moves the line;
## it simply has no airfields to operate and no sites to deny air to, and says so
## rather than inventing them.
func setup(control: RefCounted, geography: RefCounted, objects: RefCounted = null) -> bool:
	# Empty before anything is checked, and left empty on a refusal: a theatre this
	# module could not take is not the previous theatre's war still running. Everything
	# the clock reads is cleared with it, so a caller that ignored the `false` gets an
	# inert campaign rather than one still fighting over ground it is no longer on.
	_control = null
	_geography = null
	_objects = null
	_districts = {}
	_neighbours = {}
	_battles = {}
	_contact = {}
	_facilities = {}
	_sites = []
	_resources = {}
	_losses = {}
	_tick = 0
	_elapsed = 0.0
	if control == null or geography == null:
		return false
	if not control.has_method("set_measures") or not control.has_method("set_owner"):
		return false
	if not geography.has_method("adjacency") or not geography.is_loaded():
		return false
	_control = control
	_geography = geography
	_objects = null
	if objects != null and objects.has_method("of_type") \
			and objects.has_method("refresh_situation"):
		_objects = objects
	_neighbours = {}
	var table: Dictionary = geography.adjacency()
	for id in table:
		var links := {}
		for other in table[id]:
			links[String(other)] = true
		_neighbours[String(id)] = links
	_tick = 0
	_elapsed = 0.0
	_battles = {}
	_contact = {}
	_facilities = {}
	_sites = []
	_resources = {}
	_losses = {}
	_rng.seed = OPENING_SEED
	_seat()
	_register()
	return not _districts.is_empty()


## Whether this war is actually being fought over something. A director that refused its region
## has no districts to move, and a save layer that wrote one out would replace a campaign with an
## empty table carrying the same name.
func is_ready() -> bool:
	return _control != null and not _districts.is_empty()


## The campaign's clock, clamped to the band the brief sets so that a caller cannot
## accidentally ask this module for per-frame work.
func set_tick_length(seconds: float) -> void:
	_length = clampf(seconds, TICK_MIN, TICK_MAX)


func tick_length() -> float:
	return _length


## What the dice are seeded with.
func set_seed(value: int) -> void:
	_rng.seed = value


func seed_value() -> int:
	return _rng.seed


func tick_number() -> int:
	return _tick


## The caller's frame. This is the only method here a per-frame context may touch, and
## it does nothing but add up until a tick falls due. A war that was never seated -- a
## theatre with no districts in it -- has no clock either, and says so every frame.
func advance(delta: float) -> bool:
	if _control == null:
		return false
	_elapsed += maxf(delta, 0.0)
	if _elapsed < _length:
		return false
	# Reset from the deadline rather than by subtracting the length: a stalled frame
	# should skip the tick it missed, not bank a fight to resolve later.
	_elapsed = 0.0
	tick()
	return true


## How long until the next tick, for a caller that would rather be told than find out:
## a mission director needs to know it has seconds, not frames.
func until_tick() -> float:
	return maxf(0.0, _length - _elapsed)


## The whole tick at once, in the order the tick's stages depend on each other:
## facilities decide what can fly, that decides who owns the air, the fighting spends
## the economy, and the economy decides who is relieved -- and only then is anyone's
## owner recomputed and published.
func tick() -> void:
	if _control == null:
		return
	_tick += 1
	for id in _districts:
		district(String(id))["under_fire"] = 0.0
	_gather()
	_operate()
	_air()
	_fight()
	_reinforce()
	_settle()
	_publish()
	ticked.emit(_tick)


## Run the campaign forward by a stretch of realtime through the same clock a flight
## would use. Returns the number of ticks run, so a caller can tell a held map from a
## settled one.
func simulate(seconds: float) -> int:
	var before := _tick
	for i in range(int(seconds / _length)):
		advance(_length)
	return _tick - before


func districts() -> Array:
	return _districts.keys()


## Which ground this war is being fought over, read off the registry that seated it. A save file
## names the theatre it was written in, and this is the answer it has to match -- the one question
## a restored campaign cannot be asked twice.
func theatre() -> String:
	return String(_objects.call("theatre")) \
		if _objects != null and _objects.has_method("theatre") else ""


## A district's simulated state. The signed balances are here and not in the published
## RegionState because the published one is a share and this is the thing that moves it.
func district(id: String) -> Dictionary:
	return _districts.get(id, {})


## The strength one side has in one district, as a share of it.
func presence(id: String, faction: String) -> float:
	return float(_districts.get(id, {}).get("presence", {}).get(faction, 0.0))


## The brief's -1..+1, by district.
func air_balance(id: String) -> float:
	return float(_districts.get(id, {}).get("air", 0.0))


func ground_balance(id: String) -> float:
	return float(_districts.get(id, {}).get("ground", 0.0))


## How much of the theatre's airspace a side holds, averaged over the districts that
## fight over it. §13 asks for air superiority to be managed, and this is the number
## that says whether it has been.
func air_superiority(faction: String) -> float:
	var total := 0.0
	var counted := 0
	for id in _districts:
		total += share_of(air_balance(String(id)), faction)
		counted += 1
	return total / float(counted) if counted > 0 else 0.0


func supply(faction: String) -> float:
	return float(_resources.get(faction, {}).get("supply", 0.0))


func resources(faction: String) -> Dictionary:
	return _resources.get(faction, {})


func losses(faction: String) -> Dictionary:
	return _losses.get(faction, {})


func battles() -> Array:
	return _battles.values()


## The fights, hardest first. This is what a mission director is handed: not a list of
## missions, but the war's own statement of where it is going.
func active_battles() -> Array:
	var found := []
	for record in _battles.values():
		var battle: Dictionary = record
		if String(battle["status"]) == "FIGHTING":
			found.append(battle)
	found.sort_custom(_bigger)
	return found


func facilities() -> Array:
	return _facilities.values()


func facility(object_id: int) -> Dictionary:
	return _facilities.get(object_id, {})


## ---------------------------------------------------------------- the tick's stages

## Air activity seen by the flying world, credited and then left to fade. One pass at
## the top of the tick is what keeps a cockpit report off the frame rate: a pilot's
## position is not a strategic calculation, it is evidence waiting for one.
func _gather() -> void:
	for id in _districts:
		var own: Dictionary = district(id)
		var seen: Dictionary = own["seen"]
		for faction in seen.keys():
			var weight := float(seen[faction])
			if weight <= 0.0:
				continue
			own["intel"] = minf(1.0, float(own["intel"]) + weight * SIGHTING_INTEL)
			seen[faction] = weight * EVIDENCE_DECAY


## The airfields: how much is left of them, what that can fly, and how fast it is
## coming back. Damage arrives from the fighting and from the player; repair is slower
## with thin stock and with the enemy flying overhead, because a field the other side
## owns the air above is a field nobody can park on -- but a crew with a shovel and no
## fuel still works, so neither term can take the rate to nothing.
func _operate() -> void:
	for object_id in _facilities:
		var facility: Dictionary = _facilities[object_id]
		var wear := float(facility["wear"])
		facility["wear"] = 0.0
		var before := float(facility["damage"])
		facility["damage"] = clampf(before + wear, 0.0, 1.0)
		var repaired := 0.0
		if float(facility["damage"]) > 0.0:
			var holding := String(facility["faction"])
			var stock := supply(holding)
			var over := share_of(air_balance(String(facility["region_id"])), holding)
			var rate := REPAIR_RATE * (0.4 + 0.6 * stock) * (0.5 + 0.5 * over)
			repaired = minf(float(facility["damage"]), rate)
			facility["damage"] -= repaired
		var operational := 1.0 - float(facility["damage"])
		var capacity := int(facility["capacity"])
		var stock := supply(String(facility["faction"]))
		facility["operational"] = operational
		facility["fuel"] = stock
		facility["aircraft"] = int(round(float(capacity) * operational))
		facility["sorties"] = float(facility["aircraft"]) * AIRCRAFT_COVER * stock
		facility["radar_support"] = _radar_support(facility)
		facility["state"] = _facility_state(float(facility["damage"]))
		facility["repair_rate"] = repaired
		if not is_equal_approx(before, float(facility["damage"])):
			facility_changed.emit(int(facility["object_id"]))


## Who can fly where: the fields each side can operate, the sites the other still has
## standing, and the ground beneath both.
func _air() -> void:
	for id in _districts:
		var own: Dictionary = district(id)
		var district_id := String(id)
		var blue := presence(district_id, CONTROL.FRIENDLY) * GROUND_AIR
		var red := presence(district_id, CONTROL.ENEMY) * GROUND_AIR
		blue += float(own["seen"].get(CONTROL.FRIENDLY, 0.0)) * SIGHTING_AIR
		red += float(own["seen"].get(CONTROL.ENEMY, 0.0)) * SIGHTING_AIR
		for record in _facilities.values():
			var facility: Dictionary = record
			var effort := float(facility["sorties"])
			var reach := _reach(String(facility["region_id"]), district_id)
			if reach <= 0.0 or effort <= 0.0:
				continue
			if String(facility["faction"]) == CONTROL.FRIENDLY:
				blue += effort * reach
			else:
				red += effort * reach
		for record in _sites:
			var site: Dictionary = record
			var reach := _reach(String(site["region_id"]), district_id)
			if reach <= 0.0:
				continue
			red += float(site["health"]) * SITE_DENIAL * reach
		var total := blue + red
		var target := (blue - red) / total if total > PRESENT_MIN \
			else float(own["ground"]) * AIR_GROUND_FALLBACK
		own["air"] = lerpf(float(own["air"]), clampf(target, -1.0, 1.0), AIR_RATE)


## One engagement on one pair of districts, and the exchange it causes.
func _fight() -> void:
	var live := {}
	var edges := _edges()
	_contact = {}
	for edge in edges:
		_contact[String(edge["a"])] = true
		_contact[String(edge["b"])] = true
	for edge in edges:
		for pair in [[edge["a"], edge["b"]], [edge["b"], edge["a"]]]:
			var from := String(pair[0])
			var to := String(pair[1])
			for faction in _blocs_in(from):
				var foe := _other(faction)
				# Ground already ours is not a target, and a district the enemy has
				# left is taken by marching into it rather than by fighting.
				if String(_owner(to)) == faction or presence(to, foe) < PRESENT_MIN:
					continue
				var key := "%s>%s" % [from, to]
				var battle := _engage(from, to, faction, foe, float(edge["metres"]))
				# An engagement that has run its course is not kept on life support. It
				# is retired below, with the reason it stopped going with it, and what it
				# left behind is the ground the next one has to work with.
				if not battle.is_empty() and not bool(battle["exhausted"]):
					live[key] = true
	for key in _battles.keys():
		if live.has(String(key)):
			continue
		var closing: Dictionary = _battles[key]
		_battles.erase(key)
		battle_closed.emit(closing, _outcome(closing))


## The pair's whole front, in metres, which is why a long edge absorbs an assault
## instead of multiplying it: a corps does not attack each lattice seam separately.
func _engage(
		from: String, to: String, faction: String, foe: String,
		metres: float) -> Dictionary:
	var key := "%s>%s" % [from, to]
	var local := presence(from, faction)
	if local < PRESENT_MIN:
		return {}
	var cover := share_of(air_balance(to), faction)
	var stock := supply(faction)
	var front := clampf(metres / 10000.0, 0.25, 1.5)
	var assault := local * (0.4 + 0.6 * cover) * (0.35 + 0.65 * stock) \
		* (0.5 + 0.5 * float(district(to)["value"])) * front \
		* _rng.randf_range(0.85, 1.15)
	var defence := presence(to, foe) * (0.4 + 0.6 * (1.0 - cover)) \
		* (0.5 + 0.5 * float(district(to)["infrastructure"]))
	var odds := assault / maxf(assault + defence, 0.0001)
	var intensity := clampf((odds - 0.5) * 2.0, 0.0, 1.0)
	var battle: Dictionary = _battles.get(key, {})
	if battle.is_empty():
		battle = {
			"id": key,
			"from": from,
			"to": to,
			"attacker": faction,
			"defender": foe,
			"front_m": metres,
			"target_value": float(district(to)["value"]),
			"target_region": String(district(to)["name"]),
			"odds": odds,
			"intensity": 0.0,
			"momentum": 0.0,
			"opened": _tick,
			"last": _tick,
			"exhausted": false,
			"status": "CONTACT",
		}
		_battles[key] = battle
		battle_opened.emit(battle)
	battle["odds"] = odds
	battle["intensity"] = intensity
	battle["last"] = _tick
	var fatigue := clampf(1.0 - float(battle["momentum"]) / float(BATTLE_LIMIT),
		FATIGUE_FLOOR, 1.0)
	# A front bleeds whether or not anyone is attacking: this is the artillery line, the
	# raid on the outpost, the convoy that did not arrive. It is also the only way ground
	# changes hands with nobody issuing orders, which is what the phase is for -- and
	# because what each side loses is what the other side put in, the sector that can put
	# most in is the one that ends up standing on the far side of the line. It costs a
	# side exactly as much to attack as it does to be attacked, which is why a line is a
	# line: an offensive that cannot take ground quickly is the offensive that stops.
	_loss(faction, from, defence * ATTRITION * fatigue)
	_loss(foe, to, assault * ATTRITION * fatigue)
	# What a district under fire loses is what the fighting takes off it -- the
	# facilities standing in it and the roads into it both pay for the battle.
	var heat := intensity * fatigue + 0.25
	for id in [from, to]:
		var own: Dictionary = district(String(id))
		own["under_fire"] = float(own["under_fire"]) + heat
		for object_id in _facilities:
			var facility: Dictionary = _facilities[object_id]
			if String(facility["region_id"]) == String(id):
				facility["wear"] = float(facility["wear"]) + heat * RAIL_WEAR
	if _tick - int(battle["opened"]) >= BATTLE_LIMIT:
		battle["exhausted"] = true
		battle["status"] = "EXHAUSTED"
		return battle
	if intensity < STALE_AT:
		# The line is held and neither side is going anywhere this hour. Not the same as
		# a quiet sector: it is still costing both of them men.
		battle["status"] = "CONTACT"
		return battle
	battle["status"] = "FIGHTING"
	battle["momentum"] = float(battle["momentum"]) + intensity
	var pool: Dictionary = _resources[faction]
	pool["spent"] = float(pool["spent"]) + intensity
	# Only an engagement that is actually winning moves ground, and it moves it by the
	# amount it is winning by -- so a district goes contested before it goes friendly.
	# The balance has to cross the band, and nothing skips across it.
	var drive := intensity * PUSH * (0.5 + 0.5 * stock) * fatigue
	_set_presence(to, faction, presence(to, faction) + drive)
	return battle


## Why a fight ended: the attacker either has the district, is standing in it, or did
## not get there.
func _outcome(battle: Dictionary) -> String:
	var to := String(battle["to"])
	if String(_owner(to)) == String(battle["attacker"]):
		return "SUCCESS"
	if String(_owner(to)) == CONTROL.CONTESTED:
		return "PARTIAL"
	return "FAILED"


## Replacements and the economy that pays for them. A theatre earns from the ground
## behind its own line and pays for everything it holds, so an advance that outruns its
## supply slows down of its own accord -- and a front that settles turns its contact
## districts into rear area, which is where a campaign finds the fuel to move again. A
## tick that spent nothing also rebuilds stockpiles outright, because a theatre that has
## been pinned at its floor for one bad week is not a theatre that stays there.
func _reinforce() -> void:
	for faction in CONTROL.BLOCS:
		var key := String(faction)
		var pool: Dictionary = _resources[key]
		var rear := 0.0
		var held := 0.0
		var forward := 0.0
		for id in _districts:
			var own: Dictionary = district(String(id))
			var value := float(own["value"])
			if String(own["owner"]) == key:
				held += value
				# Ground on the line costs as much to hold as ground in the rear and
				# produces nothing. That is what a front is, and it is the whole
				# difference between a line that settles and one that runs away.
				if not _contact.has(String(id)):
					rear += value
			else:
				forward += float(own["presence"][key])
		var spent := clampf(float(pool["spent"]), 0.0, 1.0)
		pool["spent"] = 0.0
		pool["supply"] = clampf(float(pool["supply"]) \
			+ SUPPLY_BASE \
			+ SUPPLY_INCOME * rear \
			- SUPPLY_UPKEEP * held \
			- SUPPLY_LINE * forward \
			- SUPPLY_FIGHT * spent \
			+ SUPPLY_RECOVER * (1.0 - spent), SUPPLY_FLOOR, 1.0)
	for id in _districts:
		var district_id := String(id)
		var own: Dictionary = district(district_id)
		var engaged := _contact.has(district_id)
		for faction in CONTROL.BLOCS:
			var key := String(faction)
			var at := float(own["presence"][key])
			var target := _desired(district_id, key)
			if engaged:
				# On the line, logistics may bring strength up but never take it away.
				target = maxf(target, at)
			own["presence"][key] = lerpf(at, target, REINF_RATE)


## Recompute who holds what, and the measures that follow from it. The ground balance
## is the presence ratio, the owner falls out of the ground balance, and supply and
## intelligence are read as the situation that owner is part of.
func _settle() -> void:
	for id in _districts.keys():
		var district_id := String(id)
		var own: Dictionary = district(district_id)
		var blue := float(own["presence"][CONTROL.FRIENDLY])
		var red := float(own["presence"][CONTROL.ENEMY])
		var total := blue + red
		# A district neither side is in keeps the ground it had. Open country is not
		# a trophy, and a report of nobody anywhere is not a report of conquest.
		# What is published is how much more of the district one side is standing on
		# than the other, in shares of the district -- not in shares of the argument
		# between them, which is what `OWNED_MIN` is about.
		if total > PRESENT_MIN * 2.0:
			own["ground"] = clampf(total / OCCUPY_AT, 0.0, 1.0) * (blue - red)
		var fire := clampf(float(own["under_fire"]), 0.0, 1.0)
		own["infrastructure"] = lerpf(float(own["infrastructure"]),
			clampf(1.0 - fire * INFRA_WEAR, 0.05, 1.0), INFRA_REPAIR)
		own["intel"] = lerpf(float(own["intel"]), _intel_target(own), INTEL_RATE)
		var candidate := _derive_owner(
			float(own["ground"]), minf(blue, red), String(own["owner"]))
		if candidate == String(own["owner"]):
			own["pending"] = ""
			own["pending_ticks"] = 0
		elif String(own["pending"]) == candidate:
			own["pending_ticks"] = int(own["pending_ticks"]) + 1
			if int(own["pending_ticks"]) >= SETTLE_TICKS:
				own["owner"] = candidate
				own["pending"] = ""
				own["pending_ticks"] = 0
		else:
			own["pending"] = candidate
			own["pending_ticks"] = 1
		var holding := String(own["owner"])
		if not (holding in CONTROL.BLOCS):
			holding = _stronger_side(own, blue, red)
		own["supply"] = clampf(supply(holding) * (1.0 - 0.45 * fire), 0.0, 1.0)


## What the brief says every district must carry, written into the table the map reads.
## Ownership goes through `set_owner`, which reseeds from the situation an owner
## implies, and the measures go through `set_measures` over the top of that, so what
## ends up drawn is the campaign's own answer rather than the opening one.
func _publish() -> void:
	var operating := {}
	for object_id in _facilities:
		var model: Dictionary = _facilities[object_id]
		operating[int(model["object_id"])] = {
			"damage": float(model["damage"]),
			"fuel": float(model["fuel"]),
			"aircraft": int(model["aircraft"]),
			"capacity": int(model["capacity"]),
			"operational": float(model["operational"]),
			"repair_rate": float(model["repair_rate"]),
			"radar_support": float(model["radar_support"]),
			"state": String(model["state"]),
		}
	for id in _districts.keys():
		var district_id := String(id)
		var own: Dictionary = district(district_id)
		var owner := String(own["owner"])
		var previous := _control.owner_of(district_id)
		if _control.set_owner(district_id, owner):
			region_changed.emit(district_id, owner, previous)
		_control.set_measures(district_id, {
			"air_control": _share(float(own["air"])),
			"ground_control": _share(float(own["ground"])),
			"supply": float(own["supply"]),
			"infrastructure": float(own["infrastructure"]),
			"intel_level": float(own["intel"]),
		})
	# The registry is the map's only view of these places, so this is the one place the
	# war writes back into it: the district a facility stands in decides a landmark's
	# faction and everybody's confidence, and a field's own operating model decides what
	# its card says it can do. A theatre with no objects has no registry to keep current
	# and the line moves without it.
	if _objects == null:
		return
	_objects.refresh_situation()
	_objects.refresh_airbases(operating)


## ------------------------------------------------------------ what the world reports

## Air activity in the flying world, offered as a position, because that is what a
## flight has. Which district that is, is this module's question to answer -- and the
## same question the map asks, so the same `region_at` answers both.
func report_sighting(faction: String, at: Vector2, weight: float = 1.0) -> void:
	var id := _district_at(at)
	if id.is_empty():
		return
	var own: Dictionary = _districts.get(id, {})
	if own.is_empty():
		return
	var seen: Dictionary = own["seen"]
	seen[faction] = minf(1.0, float(seen.get(faction, 0.0)) + weight * SIGHTING_STEP)


## A strike against something the war models itself. Only airfields take damage this
## way: a site's launchers are the launcher field's business and a tower is the
## building system's, and both already report themselves through `war_objects.gd`.
func damage_facility(object_id: int, amount: float) -> bool:
	if not _facilities.has(object_id):
		return false
	var facility: Dictionary = _facilities[object_id]
	facility["wear"] = float(facility["wear"]) + clampf(amount, 0.0, 1.0)
	return true


## The war's own statement of where it is going, hardest fight first: what a caller
## with a pilot and a HUD should say about the campaign, and the same list phase 6
## will rank objectives from.
func reports() -> Array:
	return active_battles()


## The whole situation in one dictionary, for the debug overlay and for a test that
## wants to assert on a campaign rather than on a tick.
func snapshot() -> Dictionary:
	var held := {}
	for id in _districts.keys():
		var owner := String(district(String(id))["owner"])
		held[owner] = int(held.get(owner, 0)) + 1
	return {
		"tick": _tick,
		"tick_length_s": _length,
		"seed": _rng.seed,
		"districts": _districts.size(),
		"held": held,
		"battles": _battles.size(),
		"fighting": active_battles().size(),
		"air_superiority": {
			CONTROL.FRIENDLY: air_superiority(CONTROL.FRIENDLY),
			CONTROL.ENEMY: air_superiority(CONTROL.ENEMY),
		},
		"supply": {
			CONTROL.FRIENDLY: supply(CONTROL.FRIENDLY),
			CONTROL.ENEMY: supply(CONTROL.ENEMY),
		},
		"losses": _losses,
		"facilities": _facilities.values(),
	}


## ---------------------------------------------------------------------- §28's save

## The fields a save owns about a facility: everything the campaign computes for a field, and
## none of the things the registry authors for it -- its name, its type, the faction it belongs
## to, where it stands. A reload writes these onto a field the theatre put back there.
const SAVED_FIELD := ["damage", "wear", "repair_rate", "operational", "aircraft", "fuel",
	"sorties", "radar_support", "state"]


## The campaign written out, in the same shapes it is held in. Every field here is one of the
## list §28 asks for -- ownership, air control, ground control, facility health and repair
## progress, aircraft losses, ground-force strength, supply and campaign time -- and nothing
## outside it is: no particles, no projectiles, no node paths, no positions. A field's own
## `world_position` and its name are not saved because the registry authors those from the
## theatre's data on the way back up, and a save that carried them would be a second copy of a
## thing that already has one home (§25).
func export_state() -> Dictionary:
	var districts := {}
	for id in _districts:
		var district_id := String(id)
		var own: Dictionary = _districts[district_id]
		districts[district_id] = {
			"owner": String(own["owner"]),
			"ground": float(own["ground"]),
			"air": float(own["air"]),
			"infrastructure": float(own["infrastructure"]),
			"intel": float(own["intel"]),
			"supply": float(own["supply"]),
			"under_fire": float(own["under_fire"]),
			"presence": _both(own["presence"]),
			"seen": _both(own["seen"]),
			"pending": String(own["pending"]),
			"pending_ticks": int(own["pending_ticks"]),
		}
	var fighting := {}
	for key in _battles:
		var battle: Dictionary = _battles[key]
		fighting[String(key)] = {
			"id": String(battle["id"]),
			"from": String(battle["from"]),
			"to": String(battle["to"]),
			"attacker": String(battle["attacker"]),
			"defender": String(battle["defender"]),
			"front_m": float(battle["front_m"]),
			"target_value": float(battle["target_value"]),
			"target_region": String(battle["target_region"]),
			"odds": float(battle["odds"]),
			"intensity": float(battle["intensity"]),
			"momentum": float(battle["momentum"]),
			"opened": int(battle["opened"]),
			"last": int(battle["last"]),
			"exhausted": bool(battle["exhausted"]),
			"status": String(battle["status"]),
		}
	var worn := {}
	for object_id in _facilities:
		var field: Dictionary = _facilities[object_id]
		var kept := {}
		for term in SAVED_FIELD:
			kept[term] = field[term]
		worn[str(int(object_id))] = kept
	return {
		"tick": _tick,
		"elapsed": _elapsed,
		"length": _length,
		"seed": _rng.seed,
		"districts": districts,
		"battles": fighting,
		"contact": _contact.keys(),
		"facilities": worn,
		"resources": {
			CONTROL.FRIENDLY: _purse(CONTROL.FRIENDLY),
			CONTROL.ENEMY: _purse(CONTROL.ENEMY),
		},
		"losses": {
			CONTROL.FRIENDLY: {"ground": float(_losses[CONTROL.FRIENDLY]["ground"])},
			CONTROL.ENEMY: {"ground": float(_losses[CONTROL.ENEMY]["ground"])},
		},
	}


## Read it back. The rule is the one every other entry point in this module already keeps: a
## state that does not belong to the theatre currently seated is refused outright rather than
## partly applied, because a war holding last corridor's districts would move ground nobody can
## see and report an owner nobody can reach. What is applied is applied whole, on top of the
## seated opening, so a save from an earlier tick of the same corridor reloads exactly.
func import_state(state: Dictionary) -> bool:
	if _control == null or _districts.is_empty() or state.is_empty():
		return false
	var saved_districts := _table(state, "districts")
	if saved_districts.is_empty() or saved_districts.size() != _districts.size():
		return false
	for id in saved_districts:
		var district_id := String(id)
		var saved: Variant = saved_districts[id]
		if not _districts.has(district_id) or not _holds(saved, SAVED_DISTRICT):
			return false
		var owner := String((saved as Dictionary)["owner"])
		if not owner in CONTROL.OWNERS:
			return false
	for faction in CONTROL.BLOCS:
		var bloc := String(faction)
		if not _holds(_purse_of(state, bloc), SAVED_PURSE) \
				or not _holds(_loss_of(state, bloc), SAVED_LOSSES):
			return false
	var saved_battles := _table(state, "battles")
	for key in saved_battles:
		if not _holds(saved_battles[key], SAVED_BATTLE):
			return false
	var saved_fields := _table(state, "facilities")
	for object_id in _facilities:
		var record: Variant = saved_fields.get(str(int(object_id)))
		if record != null and not _holds(record, SAVED_FIELD):
			return false
	# Everything above either holds or the campaign is untouched; from here the state goes on
	# whole.
	for district_id in _districts:
		var own: Dictionary = _districts[String(district_id)]
		var saved: Dictionary = saved_districts[String(district_id)]
		own["owner"] = String(saved["owner"])
		own["ground"] = float(saved["ground"])
		own["air"] = float(saved["air"])
		own["infrastructure"] = float(saved["infrastructure"])
		own["intel"] = float(saved["intel"])
		own["supply"] = float(saved["supply"])
		own["under_fire"] = float(saved["under_fire"])
		own["presence"] = _both(saved["presence"])
		own["seen"] = _both(saved["seen"])
		own["pending"] = String(saved["pending"])
		own["pending_ticks"] = int(saved["pending_ticks"])
	_battles = {}
	for key in saved_battles:
		_battles[String(key)] = _kept(saved_battles[key] as Dictionary, SAVED_BATTLE)
	_contact = {}
	for edge in state.get("contact", []):
		_contact[String(edge)] = true
	for object_id in _facilities:
		var saved_field: Dictionary = saved_fields.get(str(int(object_id)), {})
		if saved_field.is_empty():
			continue
		var field: Dictionary = _facilities[object_id]
		for term in SAVED_FIELD:
			field[term] = saved_field[term]
	for faction in CONTROL.BLOCS:
		var bloc := String(faction)
		var purse: Dictionary = _purse_of(state, bloc)
		_resources[bloc] = {"supply": float(purse["supply"]), "spent": float(purse["spent"])}
		var lost: Dictionary = _loss_of(state, bloc)
		_losses[bloc] = {"ground": float(lost["ground"])}
	_length = clampf(float(state.get("length", _length)), TICK_MIN, TICK_MAX)
	_tick = int(state.get("tick", 0))
	_elapsed = clampf(float(state.get("elapsed", 0.0)), 0.0, _length)
	set_seed(int(state.get("seed", _rng.seed)))
	# The registry and the control table are the map's copies of these facts, and `_publish` is
	# the one place this module writes them. A reload that hand-rolled its own version of that
	# write would be a second author of the same ground (§25), and would drift.
	_publish()
	return true


## The terms a district must arrive with. A file missing one is not a campaign with that term
## left at its opening -- the read below would index straight through to a crash or, worse,
## silently carry an opening strength a save never described -- so the whole state is refused.
const SAVED_DISTRICT := ["owner", "ground", "air", "infrastructure", "intel", "supply",
	"under_fire", "presence", "seen", "pending", "pending_ticks"]

const SAVED_BATTLE := ["id", "from", "to", "attacker", "defender", "front_m", "target_value",
	"target_region", "odds", "intensity", "momentum", "opened", "last", "exhausted", "status"]

const SAVED_PURSE := ["supply", "spent"]

const SAVED_LOSSES := ["ground"]


## A section of the file that must be a table. Read through a helper rather than cast straight
## onto a typed variable, because a JSON document that arrived with a string where the districts
## belong must be refused, not turned into a runtime error halfway through applying it.
func _table(state: Dictionary, key: String) -> Dictionary:
	var section: Variant = state.get(key, {})
	return section if section is Dictionary else {}


func _holds(record: Variant, terms: Array) -> bool:
	if not (record is Dictionary):
		return false
	for term in terms:
		if not (record as Dictionary).has(term):
			return false
	return true


## Copy a saved record through its own list, so a key the file invented cannot walk into the
## live campaign and be printed as a fact about the front.
func _kept(record: Dictionary, terms: Array) -> Dictionary:
	var copy := {}
	for term in terms:
		copy[term] = record[term]
	return copy


func _purse_of(state: Dictionary, faction: String) -> Dictionary:
	return state.get("resources", {}).get(faction, {})


func _loss_of(state: Dictionary, faction: String) -> Dictionary:
	return state.get("losses", {}).get(faction, {})


## A {FRIENDLY, ENEMY} pair, copied rather than shared, so a save file's dictionary and the
## war's are never the same table.
func _both(source: Dictionary) -> Dictionary:
	return {
		CONTROL.FRIENDLY: float(source.get(CONTROL.FRIENDLY, 0.0)),
		CONTROL.ENEMY: float(source.get(CONTROL.ENEMY, 0.0)),
	}


func _purse(faction: String) -> Dictionary:
	var purse: Dictionary = _resources.get(faction, {})
	return {
		"supply": float(purse.get("supply", 0.0)),
		"spent": float(purse.get("spent", 0.0)),
	}


## ---------------------------------------------------------------------- internals


## Seat every district on its published opening. Strength is a share rather than a
## count: the two sides in a district start as the ground control the situation layer
## reports for it, so the war's first tick continues the map the player was shown
## instead of replacing it.
func _seat() -> void:
	for faction in CONTROL.BLOCS:
		var key := String(faction)
		# The theatre's opening economy is the average of what the districts a side
		# starts in say about their own supply, not a number chosen in here.
		_resources[key] = {
			"supply": float(CONTROL.SEED[key]["supply"]),
			"spent": 0.0,
		}
		_losses[key] = {"ground": 0.0}
	var openings := {CONTROL.FRIENDLY: [0.0, 0], CONTROL.ENEMY: [0.0, 0]}
	for record in _geography.regions():
		var region: Dictionary = record
		var id := String(region["id"])
		var state: Dictionary = _control.state_of(id)
		# Open ocean takes no part in a land war: the sea district is authored worthless
		# and owned by nobody, and it keeps both of those facts.
		if state.is_empty() or String(state["owner"]) == CONTROL.NEUTRAL:
			continue
		var ground := float(state["ground_control"])
		var owner := String(state["owner"])
		_districts[id] = {
			"id": id,
			"name": String(region["name"]),
			"value": float(region["value"]),
			"owner": owner,
			"ground": _balance_of(ground),
			"air": _balance_of(float(state["air_control"])),
			"infrastructure": float(state["infrastructure"]),
			"intel": float(state["intel_level"]),
			"supply": float(state["supply"]),
			"under_fire": 0.0,
			"presence": {
				CONTROL.FRIENDLY: ground,
				CONTROL.ENEMY: 1.0 - ground,
			},
			"seen": {CONTROL.FRIENDLY: 0.0, CONTROL.ENEMY: 0.0},
			"pending": "",
			"pending_ticks": 0,
		}
		if owner in CONTROL.BLOCS:
			var opening: Array = openings[owner]
			opening[0] = float(opening[0]) + float(state["supply"])
			opening[1] = int(opening[1]) + 1
	for faction in openings:
		var opening: Array = openings[faction]
		if int(opening[1]) > 0:
			_resources[faction]["supply"] = clampf(
				float(opening[0]) / float(opening[1]), SUPPLY_FLOOR, 1.0)


## The facilities this module is responsible for, taken from the registry the corridor
## populated. Airfields only: they are the class with no entity of their own, and
## everything else is read where it is bound rather than counted a second time.
func _register() -> void:
	if _objects == null:
		return
	for record in _objects.of_type(OBJECTS.Type.AIRBASE):
		var object: Dictionary = record
		var detail: Dictionary = object["detail"]
		var capacity := AIRFRAME_BASE + int(
			float(detail["longest_m"]) / AIRFRAME_PER_METRE)
		var stock := supply(String(object["faction"]))
		_facilities[int(object["id"])] = {
			"object_id": int(object["id"]),
			"type": int(object["type"]),
			"name": String(object["name"]),
			"faction": String(object["faction"]),
			"region_id": String(object["region_id"]),
			"world_position": object["world_position"],
			"damage": 0.0,
			"wear": 0.0,
			"repair_rate": 0.0,
			"operational": 1.0,
			"capacity": capacity,
			# Seated whole, because nothing has happened to it yet. What the side can fuel
			# is a separate fact and reaches the sorties below and the `fuel` field, not the
			# complement parked at the ramp: `_operate` recomputes that from the damage on
			# the first tick, and a seat that disagreed with one tick of running the war
			# would move the field's own numbers before anything had happened to it.
			"aircraft": capacity,
			"fuel": stock,
			"sorties": float(capacity) * AIRCRAFT_COVER * stock,
			"radar_support": 0.0,
			"state": OBJECTS.INTACT,
		}
	for record in _objects.of_type(OBJECTS.Type.SAM_SITE):
		_sites.append(record)


## What a side can put where. Its own districts keep a garrison -- rear areas hold what
## they were sitting on whatever the depots are doing -- and anywhere else is worth only
## what that side's own neighbours can spare.
func _desired(id: String, faction: String) -> float:
	var own: Dictionary = district(id)
	var stock := supply(faction)
	if String(own["owner"]) == faction:
		return GARRISON * (RESERVE_FLOOR + (1.0 - RESERVE_FLOOR) * stock)
	var spare := 0.0
	for neighbour in (_neighbours.get(id, {}) as Dictionary):
		var key := String(neighbour)
		if not _districts.has(key) or String(district(key)["owner"]) != faction:
			continue
		spare += float(district(key)["presence"][faction])
	if spare <= 0.0:
		# Ground nobody borders is ground nobody is going to walk onto from here.
		return 0.0
	var claim := minf(GARRISON * stock, INFLUENCE_CAP \
			* (INFLUENCE_STOCK + (1.0 - INFLUENCE_STOCK) * stock) \
			* spare * NEIGHBOUR_WEIGHT)
	# Ground on a side's own border is at least watched, however thin the depots are:
	# a district that both sides leave empties the balance it is computed from and
	# freezes the line where it stands, and a front with vacancies in it is a front
	# that has stopped. This is the smallest number that still counts as being there.
	return maxf(claim, PRESENT_MIN)


## The fights, grouped once per pair of districts rather than per lattice seam: two
## districts can meet along several edges and the front they share is their total.
func _edges() -> Array:
	var grouped := {}
	for record in _control.front():
		var segment: Dictionary = record
		var here := String(segment["from"])
		var there := String(segment["to"])
		if not _districts.has(here) or not _districts.has(there):
			continue
		var key := here if here < there else there
		var far := there if key == here else here
		var edge: Dictionary = grouped.get(key + "|" + far, {})
		if edge.is_empty():
			edge = {"a": key, "b": far, "metres": 0.0, "kind": String(segment["kind"])}
			grouped[key + "|" + far] = edge
		edge["metres"] = float(edge["metres"]) + float(segment["length"])
	return grouped.values()


## Who could be fighting out of a district. A contested one has both sides in it, which
## is why the line can move in either direction out of the same place.
func _blocs_in(id: String) -> Array:
	var owner := _owner(id)
	if owner == CONTROL.CONTESTED:
		return CONTROL.BLOCS
	return [owner] if owner in CONTROL.BLOCS else []


func _owner(id: String) -> String:
	return String(district(id).get("owner", CONTROL.NEUTRAL))


## Both tests are wider to leave than to enter, and both are asked of the owner the map is
## already showing. A district becomes contested on the way to changing hands -- either
## because the other side is standing in it in strength, or because the balance has closed
## up -- and it only comes back out of that state when one side has been clearly pushed
## under both floors. See `OWNED_MIN` and `OWNED_KEEP` for what happens when this is a
## single threshold instead.
func _derive_owner(ground: float, weaker: float, previous: String) -> String:
	var held := previous == CONTROL.CONTESTED
	if weaker >= (OWNED_KEEP if held else OWNED_MIN):
		return CONTROL.CONTESTED
	if absf(ground) < (CONTESTED_HOLD if held else CONTESTED_BAND):
		return CONTROL.CONTESTED
	return CONTROL.FRIENDLY if ground > 0.0 else CONTROL.ENEMY


## In a mixed district, whose logistics the district is living on: whoever is there in
## greater strength, and the incumbent when the two are exactly level.
func _stronger_side(own: Dictionary, blue: float, red: float) -> String:
	if is_equal_approx(blue, red):
		var incumbent := String(own["owner"])
		if incumbent in CONTROL.BLOCS:
			return incumbent
	return CONTROL.FRIENDLY if blue >= red else CONTROL.ENEMY


func _loss(faction: String, id: String, amount: float) -> void:
	if amount <= 0.0 or not _districts.has(id):
		return
	var own: Dictionary = district(id)
	var before := float(own["presence"][faction])
	own["presence"][faction] = maxf(0.0, before - amount)
	var ledger: Dictionary = _losses[faction]
	ledger["ground"] = float(ledger["ground"]) + before - float(own["presence"][faction])


func _set_presence(id: String, faction: String, value: float) -> void:
	district(id)["presence"][faction] = clampf(value, 0.0, PRESENT_MAX)


## A field's radar picture is the standing infrastructure around it. This theatre has no
## radar entity to point at, and inventing one would be a second map truth; what the
## district has left of itself is a measurement the war layer already publishes.
func _radar_support(facility: Dictionary) -> float:
	var state: Dictionary = _control.state_of(String(facility["region_id"]))
	if state.is_empty():
		return 0.0
	return clampf(float(state.get("infrastructure", 0.0)), 0.0, 1.0) \
		* float(facility["operational"])


func _intel_target(own: Dictionary) -> float:
	return clampf(INTEL_BASE \
		+ INTEL_GROUND * maxf(0.0, float(own["ground"])) \
		+ INTEL_AIR * maxf(0.0, float(own["air"])), 0.0, 1.0)


## The three states the brief asks an installation to have, from the one number this
## module owns for it.
func _facility_state(damage: float) -> String:
	if damage >= OUT_OF_ACTION:
		return OBJECTS.DESTROYED
	if damage >= DAMAGED_AT:
		return OBJECTS.DAMAGED
	return OBJECTS.INTACT


## How much of a district's airspace the given side holds, on the district's own axis.
func _reach(from_id: String, to_id: String) -> float:
	if from_id == to_id:
		return COVER_OWN
	return COVER_NEAR if (_neighbours.get(from_id, {}) as Dictionary).has(to_id) else 0.0


## The signed balance and the published share are the same fact told two ways: the
## brief's -1..+1 in here, the 0..1 control the district states were seeded with out
## there. 0.5 is the contested middle on that axis and 0.0 on this one, which is what
## makes the translation one line rather than a table.
static func _share(balance: float) -> float:
	return clampf(0.5 + 0.5 * balance, 0.0, 1.0)


static func _balance_of(share: float) -> float:
	return clampf(2.0 * (share - 0.5), -1.0, 1.0)


## Whichever way round a caller means it, on the axis it means it on.
static func share_of(balance: float, faction: String) -> float:
	var friendly := _share(balance)
	return friendly if faction == CONTROL.FRIENDLY else 1.0 - friendly


func _district_at(at: Vector2) -> String:
	var region: Dictionary = _geography.region_at(at)
	return String(region["id"]) if not region.is_empty() else ""


func _other(faction: String) -> String:
	return CONTROL.ENEMY if faction == CONTROL.FRIENDLY else CONTROL.FRIENDLY


static func _bigger(a: Dictionary, b: Dictionary) -> bool:
	return float(a["intensity"]) > float(b["intensity"])
