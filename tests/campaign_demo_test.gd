extends SceneTree

## §35's one convincing loop, run over the corridor the game actually ships with.
##
## The brief's demonstration scenario is a chain rather than a feature list: Red's coverage
## protects a corridor, Blue's staff sends a SEAD, the player flies it, the coverage changes,
## Blue's aircraft begin entering the previously protected ground, and the front line visibly
## moves. Phases 1 to 8 each proved their own link -- the staff offers the job off the published
## state, the campaign's air answer moves when a site comes down, the campaign survives a quit --
## and this file is about the thing nobody has claimed yet: whether a pilot's sortie reaches all
## the way to the line.
##
## The method is the one phase 6 used, because it is the only honest one available. Two
## campaigns, same seed, same number of ticks, same authored ground, same commanders, same staffs.
## In one of them somebody flies; in the other nothing is flown at all. Because the simulation is
## deterministic, every difference between the two wars at the end of it is the sorties and nothing
## else, and the assertion is about how far down the chain that difference travels: the sites
## themselves, then the air over the ground they were covering, then the ground fight that air
## cover feeds, then who owns what at the end of it. A claim that the front moved is worth nothing
## unless it says what the front would have done without the pilot, since phase 5 already
## established that the line moves with nobody flying at all.
##
## What the pilot flies here is the coverage, and only the coverage, for a reason that is about the
## world rather than about the test: the corridor's entire hostile order of battle is launcher
## sites. A live site is a SEAD by §17's own rule and a dead one is not a target, so a strike card
## is never raised here against anything, and `war_objects.gd` will not invent a radar station, a
## supply depot or a column of trucks to be struck. Six sorties, six sites, and everything the two
## wars then disagree about was bought with them -- which is the brief's chain stated honestly. The
## third section is the one that fails if anybody later pads the theatre to make this read better.

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

## Long enough for a change in the air to be spent on the ground. The line does not move on the
## tick after a SEAD: presence is ground-force strength, and strength takes ticks to bleed. Two
## wars of this many ticks, run side by side, are what the measurements below are taken from.
const HORIZON := 240

## The gap between one sortie and the next, in the war's own 8-second ticks: an airframe has to
## land, rearm and get airborne again, so six sites do not come down in six ticks and the pilot who
## flew them has a campaign behind him rather than a single busy minute.
const SORTIE_GAP := 2

## Where the campaign is interrupted to be quit and reloaded: past the last site coming down and
## the air turning over, early enough that the war still has most of its horizon in front of it.
const INTERRUPT := 60

var failed := false


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_flying_the_chain_reaches_the_line()
	_check_the_chain_survives_the_quit()
	_check_the_theatre_authors_what_exists()
	if not failed:
		print("CAMPAIGN_DEMO_TEST_PASS")
	quit(1 if failed else 0)


## ------------------------------------------------------------------- the chain

## Fly every SEAD the corridor offers, let the war run the same number of ticks as its twin, and
## ask whether it is a different war. The counterfactual is the same seed with nothing flown, so
## the answer cannot be "the simulation happened to move".
func _check_flying_the_chain_reaches_the_line() -> void:
	var flown := _campaign(4242)
	var mirror := _campaign(4242)
	var war: DIRECTOR = flown["director"]
	var other: DIRECTOR = mirror["director"]
	var board: MISSIONS = flown["own_board"]
	var worked := ""
	var sorties := 0
	var noted := {}

	while war.tick_number() < HORIZON:
		_turn(flown)
		_turn(mirror)
		_note(board, noted)
		var district_id := ""
		if war.tick_number() % SORTIE_GAP == 0:
			district_id = _sortie(flown)
		if district_id == "":
			continue
		if worked == "":
			worked = district_id
		sorties += 1

	check(worked != "" and sorties > 1,
		"the corridor has to offer the job that starts the chain, and the pilot has to be able to " \
			+ "answer it: %d sorties over %s" % [sorties, worked])
	if worked == "":
		return

	# The first link is the coverage itself, and it is a fact about the ground rather than about a
	# balance: the sites the war was built with, standing in one twin and down in the other.
	var covered := _site_districts(flown["registry"])
	check(sorties == covered.size(),
		"the six positions the corridor's cover is made of must all have been flown at, got %d" \
			% sorties)
	check(_live_sites(flown["registry"]) == 0, "and none of them may still be standing")
	check(_live_sites(mirror["registry"]) == covered.size(),
		"while the war nobody touched still has every launcher in the ground")

	# Air next, because that is the link the SEAD is for -- and stated against the staff's own
	# numbers rather than against a figure invented here: `CLEAR_AIR` is the floor a bomb package
	# has to see before the staff will offer one over ground, `DENIED_AIR` is where a district has
	# become unworkable. The district the chain started on sits on one side of that line in each
	# twin, which is the brief's "coverage changes" in the only units the campaign thinks in.
	var ours := _air(war, worked)
	var theirs := _air(other, worked)
	check(ours >= MISSIONS.CLEAR_AIR,
		"the air over %s must end up good enough to fly a package into, got %f" % [worked, ours])
	check(theirs < MISSIONS.DENIED_AIR,
		"and the same district must stay closed to Blue in the war that was never flown at, got %f" \
			% theirs)
	var gained := 0
	var widened := []
	for district_id in covered:
		var id := String(district_id)
		if _air(war, id) > _air(other, id):
			gained += 1
		if _ground(war, id) > _ground(other, id):
			widened.append(id)
	check(gained == covered.size(),
		"and the air must be Blue's over every district that had a site covering it, %d of %d" \
			% [gained, covered.size()])

	# Ground: air cover is a term in the assault arithmetic, so a corridor that is open has to be
	# a corridor Blue can push through. Over the district the chain was flown at, and over as many
	# of its covered neighbours as the two wars disagree about.
	var ground := _ground(war, worked)
	var standing := _ground(other, worked)
	check(ground > standing,
		"the ground fight over %s must go better for Blue where the sortie was flown: %f against " \
			% [worked, ground]
			+ "%f" % standing)
	check(not widened.is_empty(),
		"and the ground must be better for Blue somewhere among the covered districts")

	# And the line, which is the brief's actual acceptance. Two wars, one difference: at least one
	# district must belong to somebody different at the end of it.
	var moved := _owners_differ(war, other)
	check(not moved.is_empty(),
		"the front line itself must end up in a different place, and no district is owned " \
			+ "differently: Blue holds %d against %d" % [_held(war), _held(other)])

	# The staff's own verdict, and the control on it: the jobs that were flown are called off as
	# successes, and the twin is still asking for the first of them, because in that war the site is
	# still standing.
	check(noted.has(worked),
		"and the staff must call the SEAD over the district the chain started on a success, got %s" \
			% str(noted))
	check(noted.size() == sorties,
		"and every site that was flown at must have been called down: %d sorties, %d successes" \
			% [sorties, noted.size()])
	check(_offered(mirror["own_board"], MISSIONS.Kind.SEAD, worked),
		"the war nobody flew must still be offering the job that was flown")


## §28's story, told about this chain rather than about a number: quit in the middle of the
## offensive, and the campaign comes back mid-motion -- the ownership it had reached, the air the
## pilot bought, the launchers he took out of the ground, and the record of what was flown.
func _check_the_chain_survives_the_quit() -> void:
	var save := SAVE.new()
	save.erase()
	var flown := _campaign(4242)
	var war: DIRECTOR = flown["director"]
	var board: MISSIONS = flown["own_board"]
	var worked := ""
	while war.tick_number() < INTERRUPT:
		_turn(flown)
		var district_id := ""
		if war.tick_number() % SORTIE_GAP == 0:
			district_id = _sortie(flown)
		if worked == "" and district_id != "":
			worked = district_id
		# Quit at the first moment the chain has visibly paid off, which is the state a player would
		# be annoyed to lose: the last site is down and the staff has written a success against it.
		if _live_sites(flown["registry"]) == 0 and not _successes(board).is_empty():
			break
	check(worked != "" and war.tick_number() >= 8,
		"the chain must have started and the campaign must have some history before it is " \
			+ "interrupted, got tick %d" % war.tick_number())
	var sites := _live_sites(flown["registry"])
	var cover := _air(war, worked)
	var before := _successes(board)
	check(sites == 0 and before.has(worked),
		"and be far enough gone to be worth quitting: %d sites standing, board %s" \
			% [sites, str(before)])

	var written := save.capture(war.theatre(), flown["registry"], war, flown["own"],
			flown["foe"], board, flown["foe_board"])
	check(not written.is_empty() and save.write(written),
		"a campaign in the middle of an offensive must still write out: %s" % save.refusal())

	var back := _campaign(4242)
	var rewar: DIRECTOR = back["director"]
	check(save.apply(save.read(), back["registry"], rewar, back["own"], back["foe"],
			back["own_board"], back["foe_board"]),
		"and come back in: %s" % save.refusal())
	var kept: Dictionary = rewar.district(worked)
	var was: Dictionary = war.district(worked)
	check(String(kept["owner"]) == String(was["owner"]),
		"the district that was fought over must belong to the same side on reload")
	check(_close(float(kept["ground"]), float(was["ground"])) \
			and _close(float(kept["air"]), float(was["air"])),
		"and be as far gone as it was: ground %s against %s, air %s against %s" % [
			str(was["ground"]), str(kept["ground"]), str(was["air"]), str(kept["air"])])
	check(_live_sites(back["registry"]) == sites,
		"the launchers the pilot put out of action must still be out of it, got %d of %d" \
			% [_live_sites(back["registry"]), _site_districts(flown["registry"]).size()])
	check(_close(_air(rewar, worked), cover),
		"and the air he bought over %s must still be his, got %f against %f" \
			% [worked, _air(rewar, worked), cover])

	var results := {}
	for record in board.missions():
		var mission: Dictionary = record
		results[String(mission["id"])] = String(mission["outcome"])
	var flown_back := 0
	for record in back["own_board"].missions():
		var restored: Dictionary = record
		var id := String(restored["id"])
		check(results.has(id), "the reloaded board must not invent a card, got %s" % id)
		check(String(restored["outcome"]) == String(results.get(id, "?")),
			"and %s must carry the same result it had before the quit" % id)
		if String(restored["outcome"]) == MISSIONS.SUCCESS:
			flown_back += 1
	check(flown_back > 0, "the player's successes must be on the reloaded board")

	# ...and it has to still be a campaign rather than a recording of one.
	var at := war.tick_number()
	for tick in range(12):
		_turn(back)
	check(rewar.tick_number() == at + 12,
		"the reloaded war must go on counting, got %d from %d" % [rewar.tick_number(), at])
	var moving := false
	for district_id in rewar.districts():
		var id := String(district_id)
		if not _close(float(rewar.district(id)["ground"]), float(war.district(id)["ground"])):
			moving = true
	check(moving, "and ground must go on moving in it")
	save.erase()


## ---------------------------------------------------------------- the theatre

## §35 describes an enemy region with an airbase, a radar, two SAM positions, a supply depot and
## a ground force. This says what the corridor actually has, so that the gap is a recorded fact
## rather than something a later phase fills in with an invented table -- which is what §25 and
## §38 forbid, and what `war_objects.gd` already holds the line on.
func _check_the_theatre_authors_what_exists() -> void:
	var campaign := _campaign(4242)
	var war: DIRECTOR = campaign["director"]
	var registry: OBJECTS = campaign["registry"]
	var counts := {}
	for record: Variant in registry.objects():
		var object: Dictionary = record
		counts[int(object["type"])] = int(counts.get(int(object["type"]), 0)) + 1
	var sites := int(counts.get(OBJECTS.Type.SAM_SITE, 0))
	var fields := int(counts.get(OBJECTS.Type.AIRBASE, 0))
	check(sites >= 2, "the demonstration needs more than one hostile site to be a corridor")
	check(fields >= 1, "and at least one airbase to be attacked, or to attack from")
	# The types the world has no source for stay empty. A pass that fails here has either grown
	# data nobody authored or started synthesising an order of battle to make a test read well.
	for kind in [OBJECTS.Type.RADAR, OBJECTS.Type.SUPPLY_DEPOT, OBJECTS.Type.COMMAND_POST]:
		check(int(counts.get(kind, 0)) == 0,
			"a type the world does not have must stay absent rather than be invented for the demo")
	# The consequence of that, written down where somebody will trip over it rather than work
	# around it: with nothing hostile on the ground but launchers, and a live launcher being a SEAD
	# rather than a strike, §17's bomb card has no target to be raised against in this theatre. The
	# chain above is flown with the six sorties the corridor really offers -- which is a claim about
	# a silence, so the silence has to be measured over a war that was actually running.
	var board: MISSIONS = campaign["own_board"]
	var offered := false
	var strikes := 0
	while war.tick_number() < HORIZON:
		_turn(campaign)
		_sortie(campaign)
		if not board.available().is_empty():
			offered = true
		for record in board.missions():
			var card: Dictionary = record
			if int(card["kind"]) == MISSIONS.Kind.STRIKE:
				strikes += 1
	check(offered, "the staff must have been offering something for that silence to mean anything")
	check(strikes == 0, "and a strike card must not appear against objects the world does not have")
	# Ground force is the one item of §35's list the war does model, and it models it as presence
	# in the districts rather than as an object standing on one.
	var armed := 0
	for district_id in war.districts():
		if war.presence(String(district_id), CONTROL.ENEMY) > 0.0:
			armed += 1
	check(armed > 0, "the enemy must have ground in the corridor to be flown against at all")


## ------------------------------------------------------------------------ harness

## One turn of the whole chain, in the order the flying world runs it.
func _turn(campaign: Dictionary) -> void:
	var war: DIRECTOR = campaign["director"]
	war.tick()
	var red: COMMANDER = campaign["foe"]
	var blue: COMMANDER = campaign["own"]
	blue.tick(war.tick_number())
	red.tick(war.tick_number())
	var own_board: MISSIONS = campaign["own_board"]
	var foe_board: MISSIONS = campaign["foe_board"]
	own_board.tick(war.tick_number())
	foe_board.tick(war.tick_number())


## The pilot's whole side of this chain: take the hardest SEAD on the board, fly it, and let the
## launcher field report one fewer launcher standing. That report is permanent -- the field is what
## the sites' health is derived from, so a sortie that was flown has to still be flown the next
## tick, which is the difference between this and a test that rebinds the whole troop every time
## and quietly puts the site back up. Returns the district the sortie was worked in, "" when the
## board has nothing left of the chain to offer.
func _sortie(campaign: Dictionary) -> String:
	var board: MISSIONS = campaign["own_board"]
	for record in board.available():
		var offer: Dictionary = record
		if int(offer["kind"]) != MISSIONS.Kind.SEAD:
			continue
		var id := String(offer["id"])
		if not board.accept(id) or not board.launch(id):
			return ""
		var entity := board.primary_entity(id)
		var standing: Dictionary = campaign["standing"]
		if entity < 0 or not standing.has(entity):
			return ""
		standing.erase(entity)
		(campaign["registry"] as OBJECTS).bind_launchers(_report(standing))
		return String(offer["region_id"])
	return ""


## The launcher field's report of what is left: every handle still in the ground, in handle order
## so two identical sorties bind an identical list.
func _report(standing: Dictionary) -> Array:
	var positions := []
	for handle in standing:
		positions.append({"id": int(handle), "name": String(standing[handle])})
	positions.sort_custom(_by_id)
	return positions


func _offered(board: MISSIONS, kind: int, district_id: String) -> bool:
	for record in board.board():
		var mission: Dictionary = record
		if int(mission["kind"]) == kind and String(mission["region_id"]) == district_id:
			return true
	return false


## The jobs the staff has called off as done, by the district they were flown in -- the board's
## own verdict rather than a reading of the state it was judged on.
func _successes(board: MISSIONS) -> Dictionary:
	var found := {}
	for record in board.missions():
		var mission: Dictionary = record
		if String(mission["outcome"]) == MISSIONS.SUCCESS:
			found[String(mission["region_id"])] = String(mission["id"])
	return found


## And the same, read as it is published rather than reconstructed at the end. §33's board is a
## rolling window: a card the staff has called off is dropped once the tail of the campaign pushes
## it out, so a test that asks what came off has to be listening while it comes off.
func _note(board: MISSIONS, noted: Dictionary) -> void:
	for record in board.missions():
		var mission: Dictionary = record
		if String(mission["outcome"]) == MISSIONS.SUCCESS:
			noted[String(mission["region_id"])] = String(mission["id"])


## The districts the hostile cover is standing in, which is the set the chain is measured over.
func _site_districts(registry: RefCounted) -> Dictionary:
	var found := {}
	for record in (registry as OBJECTS).of_type(OBJECTS.Type.SAM_SITE):
		var site: Dictionary = record
		if String(site["region_id"]) != "":
			found[String(site["region_id"])] = true
	return found


func _live_sites(registry: RefCounted) -> int:
	var standing := 0
	for record in (registry as OBJECTS).of_type(OBJECTS.Type.SAM_SITE):
		var site: Dictionary = record
		if float(site["health"]) > 0.0:
			standing += 1
	return standing


func _held(war: DIRECTOR) -> int:
	var count := 0
	for district_id in war.districts():
		if String(war.district(String(district_id))["owner"]) == CONTROL.FRIENDLY:
			count += 1
	return count


## The districts the two wars disagree about, which is the front line being in a different place
## rather than the same line with a different number written under it.
func _owners_differ(one: DIRECTOR, other: DIRECTOR) -> Array:
	var found := []
	for district_id in one.districts():
		var id := String(district_id)
		if String(one.district(id)["owner"]) != String(other.district(id)["owner"]):
			found.append(id)
	found.sort()
	return found


func _air(war: DIRECTOR, district_id: String) -> float:
	return DIRECTOR.share_of(war.air_balance(district_id), CONTROL.FRIENDLY)


func _ground(war: DIRECTOR, district_id: String) -> float:
	return DIRECTOR.share_of(war.ground_balance(district_id), CONTROL.FRIENDLY)


static func _by_id(a: Dictionary, b: Dictionary) -> bool:
	return int(a["id"]) < int(b["id"])


func _close(a: Variant, b: Variant) -> bool:
	return is_equal_approx(float(a), float(b)) or absf(float(a) - float(b)) < 0.0000001


## A whole campaign: the corridor's districts, the objects standing on them, the war over the top
## of both, the two commanders and both staffs -- which is what the game seats, so it is what the
## demonstration has to run. The launcher field is seeded with one launcher per authored position,
## because that is what the tracker reports when a site comes online, and the campaign keeps the
## list of what is standing so a sortie can take one out of it for good.
func _campaign(seed_value: int) -> Dictionary:
	var geography := REGIONS.new()
	check(geography.load_theatre(CORRIDOR), "the corridor must still divide into districts")
	var control := CONTROL.new()
	control.setup(geography)
	var registry := OBJECTS.new()
	check(registry.load_theatre(CORRIDOR, geography, control),
		"and the corridor must have its fields, sites and towers in it")
	var standing := {}
	var positions := []
	var handle := 1
	for record in registry.of_type(OBJECTS.Type.SAM_SITE):
		var site: Dictionary = record
		var name := "%s LAUNCHER" % String(site["detail"]["site"])
		positions.append({"id": handle, "name": name})
		standing[handle] = name
		handle += 1
	registry.bind_launchers(positions)
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
		"control": control,
		"registry": registry,
		"director": director,
		"own": blue,
		"foe": red,
		"own_board": own_board,
		"foe_board": foe_board,
		"standing": standing,
	}
