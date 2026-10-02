extends SceneTree

## Phase 5's acceptance, headless and with nobody in the cockpit: the simulation runs
## on its own, and the territory it runs on becomes contested and changes hands because
## of that and not because something was scripted. Everything the director computes has
## to leave the building through the two tables the map already reads, so this asks
## nothing about drawing and everything about whether the data is a campaign: whether
## the opening map survives the first tick, whether a field recovers from being bombed,
## whether the air over a district belongs to whoever can actually fly there, and whether
## the whole thing runs on a tick rather than on a frame.

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

var failed := false
var _moved := []
var _closed := []
var _untouched := {}


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var geography := REGIONS.new()
	check(geography.load_theatre(CORRIDOR), "the corridor must still divide into districts")
	var control := CONTROL.new()
	control.setup(geography)
	# What the ocean looked like before the war started. The sea district is authored,
	# takes no part in a land war, and has to be found exactly as it was at the end.
	for record in geography.regions():
		var region: Dictionary = record
		if String(region["owner"]) == CONTROL.NEUTRAL:
			var state: Dictionary = control.state_of(String(region["id"]))
			_untouched[String(region["id"])] = float(state["ground_control"])
	var registry := OBJECTS.new()
	check(
		registry.load_theatre(CORRIDOR, geography, control),
		"a corridor with runways, sites and towers in it has objects")
	_check_the_clock(control, geography)
	_check_the_opening_survives_the_first_tick(control, geography)
	_check_the_line_moves_with_nobody_flying(control, geography)
	_check_the_measures_stay_honest(control, geography)
	_check_the_air_belongs_to_whoever_can_fly(control, geography, registry)
	_check_a_field_recovers(control, geography, registry)
	_check_the_campaign_repeats_itself()
	_check_the_world_can_report(control, geography, registry)
	_check_a_theatre_with_no_objects(control, geography)
	if not failed:
		print("WAR_DIRECTOR_TEST_PASS")
	quit(1 if failed else 0)


## ------------------------------------------------------------------ the clock, §14

## A strategic tick is 5-15 s of realtime and is never a per-frame calculation. This is
## the module that has to honour that, so the frames are counted rather than trusted.
func _check_the_clock(control: RefCounted, geography: RefCounted) -> void:
	var director := _war(control, geography, null)
	check(
		director.tick_length() >= DIRECTOR.TICK_MIN
			and director.tick_length() <= DIRECTOR.TICK_MAX,
		"the opening clock must be inside the brief's band, got %f" % director.tick_length())
	director.set_tick_length(0.5)
	check(
		is_equal_approx(director.tick_length(), DIRECTOR.TICK_MIN),
		"a caller cannot ask the war for a faster tick than the brief allows, got %f" \
			% director.tick_length())
	director.set_tick_length(600.0)
	check(
		is_equal_approx(director.tick_length(), DIRECTOR.TICK_MAX),
		"or a slower one, got %f" % director.tick_length())
	director.set_tick_length(DIRECTOR.TICK_DEFAULT)
	var frames := 0
	for second in range(7):
		for frame in range(60):
			if director.advance(1.0 / 60.0):
				frames += 1
	check(
		frames == 0 and director.tick_number() == 0,
		"seven seconds of a 60 Hz frame must not be a strategic tick, got %d" % frames)
	var before: int = director.tick_number()
	# The four hundred and twenty frames above add up to a hair under seven whole
	# seconds in binary, so the eighth second is asked for with room: the claim is one
	# tick per deadline and nothing banked over it, not that a tick is owed at exactly
	# eight point zero zero zero zero.
	check(director.advance(1.1), "and the eighth second must be a tick")
	check(director.tick_number() == before + 1, "one tick, not a burst")
	check(
		is_equal_approx(director.until_tick(), DIRECTOR.TICK_DEFAULT),
		"the clock restarts from the deadline instead of banking the overshoot, got %f" \
		% director.until_tick())


## ------------------------------------------------------- the opening map is continued

## The director seeds its own numbers from what the situation layer reports, so its first
## tick has to say the same thing about the map that the map already said. A war that
## rewrites the opening the instant it starts is not continuing anything.
func _check_the_opening_survives_the_first_tick(
		control: RefCounted, geography: RefCounted) -> void:
	# A fresh situation, because the sections share one theatre and the clock above has
	# already run a tick through it. This one is about the opening, so it starts there.
	control.setup(geography)
	var director := _war(control, geography, null)
	for record in geography.regions():
		var region: Dictionary = record
		var id := String(region["id"])
		check(
			control.owner_of(id) == String(region["owner"]),
			"%s starts where the geography says" % id)
		if String(region["owner"]) == CONTROL.NEUTRAL:
			continue
		var own: Dictionary = director.district(id)
		check(not own.is_empty(), "%s must be seated in the war" % id)
		# The published share and the signed balance are the same fact told two ways.
		check(
			is_equal_approx(
				DIRECTOR.share_of(float(own["ground"]), CONTROL.FRIENDLY),
				float(control.state_of(id)["ground_control"])),
			"%s must be seeded from the ground control the map is drawing" % id)
	check(director.district("sea").is_empty(),
		"open ocean takes no part in a land war")
	var opening := _held(control)
	director.tick()
	check(_held(control) == opening,
		"the first tick must continue the opening situation, got %s after %s" \
			% [str(_held(control)), str(opening)])
	check(director.battles().size() > 0,
		"and it must find the line the districts already agree they share")
	for record in director.battles():
		var battle: Dictionary = record
		check(
			String(battle["attacker"]) != String(battle["defender"]),
			"an engagement has two sides, got %s" % str(battle["attacker"]))
		check(
			control.owner_of(String(battle["from"])) != CONTROL.NEUTRAL
				and control.owner_of(String(battle["to"])) != CONTROL.NEUTRAL,
			"and neither end of it is water")


## --------------------------------------------------------- the acceptance, §PHASE 5

## No pilot, no orders, no scripted sequence: the campaign runs and the map changes.
func _check_the_line_moves_with_nobody_flying(
		control: RefCounted, geography: RefCounted) -> void:
	var director := _war(control, geography, null)
	var opening := {}
	for record in geography.regions():
		var region: Dictionary = record
		if String(region["owner"]) == CONTROL.NEUTRAL:
			continue
		opening[String(region["id"])] = control.owner_of(String(region["id"]))
	_moved = []
	_closed = []
	if not director.region_changed.is_connected(_note_move):
		director.region_changed.connect(_note_move)
	if not director.battle_closed.is_connected(_note_close):
		director.battle_closed.connect(_note_close)
	var ticks: int = director.simulate(900.0)
	check(ticks > 20, "the run must have had time to fight, got %d ticks" % ticks)
	check(not _moved.is_empty(),
		"territory must change hands with nobody in the cockpit")
	var contested := 0
	var taken := 0
	for record in _moved:
		var move: Array = record
		if String(move[1]) == CONTROL.CONTESTED:
			contested += 1
		elif String(move[1]) in CONTROL.BLOCS:
			taken += 1
	check(contested > 0,
		"a district has to become contested on the way, got %d" % contested)
	check(taken > 0, "and at least one has to change bloc, got %d" % taken)
	# The war moves ground; it does not flicker it. A district's own reported owner feeds
	# back into who attacks it and who bothers to, and before the presence floors and the
	# settling rule that loop was measured re-announcing one district 62 times in 200 ticks,
	# a tick apart. A map that repaints the same place twice a minute is a report failing,
	# not a front fighting, so the busiest district is bounded here.
	var counts := {}
	for change in _moved:
		var moved_id := String((change as Array)[0])
		counts[moved_id] = int(counts.get(moved_id, 0)) + 1
	var busiest := 0
	var worst_id := ""
	for id in counts:
		if int(counts[id]) > busiest:
			busiest = int(counts[id])
			worst_id = String(id)
		var every := maxi(1, int(float(ticks) / float(maxi(busiest, 1))))
		check(busiest * 8 <= ticks, ("%s was announced %d times in %d ticks -- one move " \
			+ "every %d ticks is a report flickering, not a front fighting") % [
			worst_id, busiest, ticks, every])
	var latest := {}
	for move in _moved:
		var entry: Array = move
		check(String(entry[2]) != String(entry[1]),
			"a district is only announced as moved when it moved, got %s" % str(entry))
		latest[String(entry[0])] = String(entry[1])
	# A district can change hands twice in fifteen minutes, so what the map has to agree
	# with is the last thing the war said about it rather than everything.
	for id in latest:
		check(control.owner_of(String(id)) == String(latest[id]),
			"%s: the map must read the owner the war announced, got %s against %s" \
			% [id, String(control.owner_of(String(id))), String(latest[id])])
	check(not _closed.is_empty(),
		"engagements end, so that a sector that has fought itself out can go quiet")
	for record in _closed:
		var closing: Array = record
		check(
			String(closing[1]) in ["SUCCESS", "PARTIAL", "FAILED"],
			"and say how they ended, got %s" % String(closing[1]))
	check(not control.front().is_empty(),
		"the war is not over: a campaign that decided itself in fifteen minutes of " \
		+ "ticks would leave the map with nothing to draw")
	var still_held := _held(control)
	check(still_held[CONTROL.ENEMY] > 0,
		"and red must still be holding ground, got %s" % str(still_held))
	check(still_held[CONTROL.FRIENDLY] > 0,
		"with blue still holding its own, got %s" % str(still_held))


## Every district still carries the fields the brief lists, and every one of them is a
## ratio -- after a campaign, not just at the start.
func _check_the_measures_stay_honest(control: RefCounted, geography: RefCounted) -> void:
	var held := _held(control)
	var total := 0
	for record in geography.regions():
		var region: Dictionary = record
		var id := String(region["id"])
		var state: Dictionary = control.state_of(id)
		total += 1
		check(String(state["owner"]) == control.owner_of(id),
			"%s state and owner must agree, got %s against %s" \
				% [id, String(state["owner"]), control.owner_of(id)])
		for field in CONTROL.MEASURES:
			var value := float(state[field])
			check(value >= 0.0 and value <= 1.0 and is_finite(value),
				"%s %s must stay a finite ratio, got %s" % [id, field, str(state[field])])
		if String(region["owner"]) == CONTROL.NEUTRAL:
			check(
				control.owner_of(id) == CONTROL.NEUTRAL
					and is_equal_approx(
						float(state["ground_control"]), float(_untouched[id])),
				"the war must leave the ground it has no part in alone, got %s" % id)
	var accounted := 0
	for key in held:
		accounted += int(held[key])
	check(accounted == total,
		"every district is held by someone, got %d of %d" % [accounted, total])


## --------------------------------------------------------------- the air, §11 and §13

## Air control is not a coverage circle: it belongs to whoever can actually fly, which
## means the fields that are operating and the sites that are still standing.
func _check_the_air_belongs_to_whoever_can_fly(
		control: RefCounted, geography: RefCounted, registry: RefCounted) -> void:
	var director := _war(control, geography, registry)
	var airfield := _first(registry, OBJECTS.Type.AIRBASE)
	var district_id := String(airfield["region_id"])
	check(not district_id.is_empty(), "the test needs the airfield inside a district")
	# A field that is generating sorties holds the air over its own district; a hostile
	# site with launchers standing at it denies it.
	registry.bind_launchers([])
	director.simulate(160.0)
	var clear: float = director.air_balance(district_id)
	var launchers := []
	var handle := 1
	for record in registry.of_type(OBJECTS.Type.SAM_SITE):
		var site: Dictionary = record
		launchers.append({
			"id": handle,
			"name": "%s LAUNCHER" % String(site["detail"]["site"]),
		})
		handle += 1
	registry.bind_launchers(launchers)
	director.simulate(160.0)
	var denied: float = director.air_balance(district_id)
	check(clear > denied,
		"surviving SAM sites must be felt in the airspace: clear %f, denied %f" \
		% [clear, denied])
	var ours: float = director.presence(district_id, CONTROL.FRIENDLY)
	check(ours > 0.0, "and blue must be the side that owns the field it flies from")
	# Now take the field away and ask the same question again: the air balance has to
	# answer to the operating state, not to the existence of the concrete.
	director.damage_facility(int(airfield["id"]), 1.0)
	director.simulate(160.0)
	check(director.air_balance(district_id) < clear,
		"a destroyed airfield cannot hold the air it used to")
	for faction in CONTROL.BLOCS:
		var share: float = director.air_superiority(String(faction))
		check(share >= 0.0 and share <= 1.0,
			"air superiority must be a share of the theatre, got %f" % share)
	check(
		director.air_superiority(CONTROL.FRIENDLY) \
			+ director.air_superiority(CONTROL.ENEMY) > 0.99,
		"and the two sides' shares must divide the same sky")


## --------------------------------------------------------------- the fields, §10

## One bomb does not eliminate an airbase, and a field that is kept out of action is
## still being repaired. This is the brief's gradual-repair rule, measured against the
## only airfield this world has a source for.
func _check_a_field_recovers(
		control: RefCounted, geography: RefCounted, registry: RefCounted) -> void:
	var director := _war(control, geography, registry)
	var airfield := _first(registry, OBJECTS.Type.AIRBASE)
	var id := int(airfield["id"])
	var model: Dictionary = director.facility(id)
	check(not model.is_empty(), "the war operates the fields the registry knows")
	# Capacity is a staff estimate read off the one published fact about the field, so
	# the corridor's 2 492 m runway is not the same base as Sydney's 3 962 m one.
	var longest := float(airfield["detail"]["longest_m"])
	var expected := DIRECTOR.AIRFRAME_BASE \
		+ int(longest / DIRECTOR.AIRFRAME_PER_METRE)
	check(
		int(model["capacity"]) == expected,
		"a field's capacity must come from its own pavement, got %d for %f m" \
			% [int(model["capacity"]), longest])
	var full := int(model["aircraft"])
	check(full > 0 and full <= expected, "with aircraft to fly, got %d" % full)
	check(String(model["state"]) == OBJECTS.INTACT, "and nothing has arrived yet")
	check(director.damage_facility(id, 0.35), "the war takes a report of damage")
	director.tick()
	model = director.facility(id)
	check(
		String(model["state"]) == OBJECTS.DAMAGED,
		"a hit ramp is a damaged field, not a destroyed one, got %s" \
			% String(model["state"]))
	check(
		int(model["aircraft"]) < full and int(model["aircraft"]) > 0,
		"a damaged field flies fewer aircraft and still flies some, got %d" \
			% int(model["aircraft"]))
	var repaired := 0
	# Repair is a rate rather than an event, so the claim has to be shaped as "tick until
	# the damage is gone", not "tick until the state reads INTACT" -- that word flips a
	# fifth of the way down the scale, and a field at the turn is operational without yet
	# being whole. Each tick must be a step forward, and the complement has to come back
	# with the damage it was limited by rather than with the state word.
	while repaired < 200 and float(model["damage"]) > 0.0:
		repaired += 1
		var before := float(model["damage"])
		director.tick()
		model = director.facility(id)
		check(
			float(model["damage"]) <= before,
			"repair never makes a field worse, got %f after %f" \
				% [float(model["damage"]), before])
		check(
			int(model["aircraft"]) == roundi(float(model["capacity"]) \
				* (1.0 - float(model["damage"]))),
			"what is parked must be what the damage leaves, got %d at %f" \
				% [int(model["aircraft"]), float(model["damage"])])
	check(
		float(model["damage"]) < 0.001,
		"a field nobody shoots at for %d ticks is whole again, got damage %f" \
			% [repaired, float(model["damage"])])
	check(String(model["state"]) == OBJECTS.INTACT,
		"and reads intact on the map, got %s" % String(model["state"]))
	check(int(model["aircraft"]) == full, "with its full complement back")
	# Enough damage, though, and it is out of action -- and still being repaired.
	check(director.damage_facility(id, 0.95), "a direct hit on the runway itself")
	director.tick()
	model = director.facility(id)
	check(String(model["state"]) == OBJECTS.DESTROYED, "is out of action")
	var stuck := float(model["damage"])
	director.tick()
	model = director.facility(id)
	check(
		float(model["damage"]) < stuck,
		"out of action is not deleted: %f came down to %f" \
			% [stuck, float(model["damage"])])
	# And the registry is where the map reads it, so the answer has to be in there.
	var published: Dictionary = registry.of(id)
	check(
		String(published["operational_state"]) == String(model["state"]),
		"the card must report the field's own state, got %s against %s" \
			% [String(published["operational_state"]), String(model["state"])])
	check(
		int(published["detail"]["capacity"]) == expected
			and is_equal_approx(float(published["detail"]["damage"]),
				float(model["damage"])),
		"and its operating figures with it")


## ------------------------------------------------------------------- determinism

## A fixed seed is what turns "the simulation runs without a player" from a screenshot
## into a claim. The same seed must give the same campaign; a different one must not be
## the same campaign wearing a hat.
func _check_the_campaign_repeats_itself() -> void:
	# Each on its own theatre, because two directors over one situation layer are not two
	# runs of anything: the second reads the front the first published into it.
	var first := _theatre(4242)
	var second := _theatre(4242)
	first.simulate(400.0)
	second.simulate(400.0)
	check(
		str(_campaign(first)) == str(_campaign(second)),
		"the same seed must run the same war")
	var third := _theatre(9999)
	third.simulate(400.0)
	check(
		str(_campaign(first)) != str(_campaign(third)),
		"and a different seed must not, got the same campaign twice")


## ------------------------------------------------------- the world can report to it

## The seam combat systems use. A sighting is intelligence; a strike is damage; and
## neither is allowed to invent an object the registry does not have.
func _check_the_world_can_report(
		control: RefCounted, geography: RefCounted, registry: RefCounted) -> void:
	var director := _war(control, geography, registry)
	var watch := _war(control, geography, registry)
	var tower := _first(registry, OBJECTS.Type.INFRASTRUCTURE)
	var at: Vector2 = tower["world_position"]
	for tick in range(12):
		director.report_sighting(CONTROL.FRIENDLY, at, 1.0)
		director.tick()
		watch.tick()
	var id := String(tower["region_id"])
	check(
		director.district(id)["intel"] > float(watch.district(id)["intel"]),
		"a pilot who keeps flying over a district knows more about it")
	check(
		float(control.state_of(id)["intel_level"]) > 0.0,
		"and what is known has to reach the map the card reads")
	var site := _first(registry, OBJECTS.Type.SAM_SITE)
	check(
		not director.damage_facility(int(site["id"]), 0.5),
		"a launcher site is the launcher field's to damage, not the war's")
	check(
		not director.damage_facility(OBJECTS.FIRST_ID - 1, 0.5),
		"and an id the registry does not have is refused, not seated")
	check(not director.battle_closed.is_connected(_note_close),
		"a fresh director carries no signals from the last one")


## A theatre with districts and no objects is a real case -- the map reports NONE for
## those rows, and the war still has to be a war.
func _check_a_theatre_with_no_objects(control: RefCounted, geography: RefCounted) -> void:
	var director := DIRECTOR.new()
	check(
		director.setup(control, geography, null),
		"a war can be run over ground with nothing standing on it")
	check(director.facilities().is_empty(), "with no fields to operate")
	var opening := _held(control)
	director.simulate(900.0)
	check(_held(control) != opening, "and the line still moves")
	for id in director.districts():
		var state: Dictionary = control.state_of(String(id))
		check(is_equal_approx(float(state["ground_control"]),
				DIRECTOR.share_of(director.ground_balance(String(id)), CONTROL.FRIENDLY)),
			"%s still publishes exactly what the war computed" % String(id))
	check(not director.setup(null, null, null), "a war with no situation cannot start")
	check(not director.setup(control, null, null), "or one with no geography")


## ------------------------------------------------------------------------ helpers

## A director over the corridor's own districts, freshly seated from whatever the
## situation layer reports at the moment it is built.
func _war(control: RefCounted, geography: RefCounted, registry: RefCounted) -> RefCounted:
	var director := DIRECTOR.new()
	check(director.setup(control, geography, registry), "the war must take the theatre")
	return director


## A whole theatre to itself -- geography, opening situation and war over the top of
## both -- so that a claim about one run of the campaign cannot be answered by another.
func _theatre(seed_value: int) -> RefCounted:
	var geography := REGIONS.new()
	check(geography.load_theatre(CORRIDOR), "the corridor must still divide")
	var control := CONTROL.new()
	control.setup(geography)
	var director := _war(control, geography, null)
	director.set_seed(seed_value)
	return director


func _note_move(id: String, owner: String, previous: String) -> void:
	_moved.append([id, owner, previous])


func _note_close(battle: Dictionary, outcome: String) -> void:
	_closed.append([battle["id"], outcome])


func _held(control: RefCounted) -> Dictionary:
	return {
		CONTROL.FRIENDLY: control.held_by(CONTROL.FRIENDLY),
		CONTROL.ENEMY: control.held_by(CONTROL.ENEMY),
		CONTROL.CONTESTED: control.held_by(CONTROL.CONTESTED),
		CONTROL.NEUTRAL: control.held_by(CONTROL.NEUTRAL),
	}


## The campaign as an observable: who holds each district, and the balances that put it
## there. Not a snapshot -- this is the question a test is allowed to ask twice.
func _campaign(director: RefCounted) -> Dictionary:
	var record := {}
	for id in director.districts():
		var key := String(id)
		record[key] = [
			str(int(round(director.ground_balance(key) * 1000.0))),
			str(int(round(director.air_balance(key) * 1000.0))),
			str(int(round(director.presence(key, CONTROL.FRIENDLY) * 1000.0))),
		]
	return record


func _first(registry: RefCounted, type: int) -> Dictionary:
	var found: Array = registry.of_type(type)
	check(not found.is_empty(), "the corridor must have one of type %d" % type)
	return found[0] if not found.is_empty() else {}
