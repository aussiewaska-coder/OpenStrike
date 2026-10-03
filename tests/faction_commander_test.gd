extends SceneTree

## Phase 7's acceptance: repeated player behaviour causes an understandable enemy response
## rather than a random one.
##
## Which is a claim about three things, and the test makes each of them separately. A commander
## must want an operation because the campaign says so, term by term (§15). It must remember the
## pattern longer than the war remembers the sighting that made it, because that is the only way
## "repeated" means anything to a sim whose intelligence goes stale on purpose (§16). And it must
## change what the staff offers, or it is a commentary track on a war that was already decided.
## Then the two honesty checks the phase depends on: the commander writes nothing, and nothing in
## it is a random number.

const COMMANDER := preload("res://scripts/war/faction_commander.gd")
const MISSIONS := preload("res://scripts/war/mission_director.gd")
const DIRECTOR := preload("res://scripts/war/war_director.gd")
const REGIONS := preload("res://scripts/war/war_regions.gd")
const CONTROL := preload("res://scripts/war/war_control.gd")
const OBJECTS := preload("res://scripts/war/war_objects.gd")
const SQUADRON := preload("res://scripts/entities/enemy_squadron.gd")

const CORRIDOR := {
	"id": "au_gold_coast_tweed_corridor",
	"center_latitude": -28.08,
	"center_longitude": 153.365,
	"world_size_m": 50000.0,
}

## How long the pilot keeps flying into the same district, and how long they then stop. Both are
## read off the commander's own constants: the habit has to be full before the response is
## asserted about, and the war's own evidence has to have decayed before the memory is asserted
## about outlasting it.
const WORKED_TICKS := 40
const GONE_TICKS := 25

var failed := false


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_refusal_seats_nothing()
	_check_nobody_flying_raises_no_intercept()
	_check_a_pattern_buys_a_response()
	_check_the_memory_outlives_the_news()
	_check_elsewhere_is_discounted()
	_check_the_commander_writes_nothing()
	_check_the_decision_repeats_itself()
	_check_priority_reaches_the_board()
	_check_intent_reaches_the_squadron()
	if not failed:
		print("FACTION_COMMANDER_TEST_PASS")
	quit(1 if failed else 0)


## ---------------------------------------------------------------------- the refusals

## The phase 5 rule, asked of the third module on the campaign: a commander that cannot see the
## war is not allowed to keep seeing the last one, and an unseated one must answer the staff with
## the neutral number rather than a stale opinion.
func _check_refusal_seats_nothing() -> void:
	var campaign := _campaign(1004)
	var commander: COMMANDER = campaign["commander"]
	check(commander.is_ready(), "a commander over a seated war is seated")
	check(not commander.setup(null, null, null), "and refuses a war that is not there")
	check(not commander.is_ready(), "refusing leaves it unseated")
	check(commander.operations().is_empty(), "with no operations carried over")
	check(commander.snapshot()["pattern"].is_empty(), "and no memory carried over")
	check(commander.setup(campaign["director"], campaign["registry"], campaign["geography"]),
		"a refusal does not break the next real setup")
	check(commander.is_ready(), "and the war is seated again")
	# A commander that was never seated is the pre-phase-7 board: the staff asks its eight
	# questions and nothing scales the answers.
	var blank := COMMANDER.new()
	check(is_equal_approx(blank.priority_for("tweed_heads"), 1.0),
		"an unseated commander has no opinion about any ground")
	check(is_zero_approx(blank.effort_at(Vector2.ZERO)),
		"and says no air is committed anywhere")
	check(blank.operations().is_empty() and blank.focused().is_empty(),
		"with nothing committed to print")


## ------------------------------------------------------------------ wanting a response

## The other side is not obliged to guess. Before anyone flies anywhere, nothing in the campaign
## reports hostile aircraft working a district, so the intercept objective -- the one that is
## entirely a memory of what the other side has been doing -- must not be raised. A commander
## that invented it would be a scripted encounter with a diagram on it.
func _check_nobody_flying_raises_no_intercept() -> void:
	var campaign := _campaign(1004)
	var red: COMMANDER = campaign["commander"]
	red.set_faction(CONTROL.ENEMY)
	_settle(campaign, 12)
	for record: Dictionary in red.operations():
		check(int(record["objective"]) != COMMANDER.Objective.INTERCEPT_AIRCRAFT,
			"nobody is intercepted who has never been seen: %s" % String(record["label"]))
		check(_close(float(record["score"]), _product(record)),
			"the score on %s is the product of the terms printed beside it" % String(record["id"]))


## The acceptance, stated as the brief states it. Fly into the same district for long enough and
## the enemy does not roll a die at you: it commits an operation over that ground, and says why
## in the same sentence a player could read off the map.
func _check_a_pattern_buys_a_response() -> void:
	var campaign := _campaign(1004)
	var red: COMMANDER = campaign["commander"]
	red.set_faction(CONTROL.ENEMY)
	var target := _richest(campaign, CONTROL.ENEMY)
	check(not target.is_empty(), "the enemy holds ground worth flying into")
	_settle(campaign, 12)
	check(_intercept_of(red, target).is_empty(),
		"before the flying starts, no operation names that ground")
	_work(campaign, target, WORKED_TICKS)
	var after := _intercept_of(red, target)
	check(not after.is_empty(),
		"after %d ticks in one district the enemy commits an intercept over it" % WORKED_TICKS)
	if after.is_empty():
		return
	check(String(after["objective_name"]) == "INTERCEPT AIRCRAFT", "as the objective §15 names it")
	check(String(after["label"]).begins_with("INTERCEPT OVER"),
		"and labelled as an operation over a place: %s" % String(after["label"]))
	var reason := String(after["reason"])
	check(reason.contains("worked") and reason.contains(str(COMMANDER.PATTERN_WINDOW)),
		"the reason is the pattern itself, counted in ticks: %s" % reason)
	check(float(after["factors"]["urgency"]) > 0.5,
		"and the pattern is the term carrying it: urgency %0.2f" % float(after["factors"]["urgency"]))
	check(float(after["score"]) >= COMMANDER.MIN_OPERATION, "and it is worth committing")
	check(_close(float(after["score"]), _product(after)),
		"whose five terms still multiply out to it afterwards")
	var focus := red.focused()
	check(String(focus["id"]) == String(after["id"]) or float(focus["score"]) > float(after["score"]),
		"and it is at the top of what the commander cares about")


## §16's whole trick, and the reason the memory lives here rather than in the director: the war
## decays a sighting on purpose, so a district the pilot has left stops being news within a
## couple of ticks. A response to a pattern has to outlast the news, and then has to go.
func _check_the_memory_outlives_the_news() -> void:
	var campaign := _campaign(1004)
	var red: COMMANDER = campaign["commander"]
	var director: DIRECTOR = campaign["director"]
	red.set_faction(CONTROL.ENEMY)
	var target := _richest(campaign, CONTROL.ENEMY)
	_work(campaign, target, WORKED_TICKS)
	var habit := float(red.snapshot()["pattern"][target]["habit"])
	check(habit > 0.0, "the pattern is held as a weight, not just a count")
	_settle(campaign, GONE_TICKS)
	var news := float(director.district(target)["seen"].get(CONTROL.FRIENDLY, 0.0))
	var still := float(red.snapshot()["pattern"][target]["habit"])
	check(news < COMMANDER.SEEN_MIN,
		"the war has stopped believing anyone is there (%0.3f left)" % news)
	check(still > 0.0, "and the commander still remembers that they were: %0.3f" % still)
	check(still < habit, "but the memory is settling rather than being renewed")
	var late := _intercept_of(red, target)
	check(late.is_empty() or float(late["factors"]["urgency"]) < 0.5,
		"and the operation is standing down rather than being held up")
	# Gone long enough and the pattern leaves the memory too: a commander that remembered forever
	# would be a script with better table manners.
	_settle(campaign, COMMANDER.PATTERN_WINDOW + 8)
	check(int(red.snapshot()["pattern"].get(target, {"visits": 0})["visits"]) == 0,
		"an abandoned pattern is eventually dropped")
	check(_intercept_of(red, target).is_empty(), "and takes its operation with it")


## The other half of a response: what it costs the war elsewhere. §16 says redirecting means
## taking air off quiet ground, and a commander that only ever added would be inflation rather
## than command.
func _check_elsewhere_is_discounted() -> void:
	var campaign := _campaign(1004)
	var red: COMMANDER = campaign["commander"]
	var geography: REGIONS = campaign["geography"]
	red.set_faction(CONTROL.ENEMY)
	var target := _richest(campaign, CONTROL.ENEMY)
	_work(campaign, target, WORKED_TICKS)
	var focused := red.priority_for(target)
	check(focused > 1.0, "the worked district is worth more than the raw state says (%0.2f)"
		% focused)
	var quiet := ""
	var quiet_centre := Vector2.ZERO
	for record: Variant in geography.regions():
		var id := String(record["id"])
		if id != target and red.priority_for(id) < 1.0:
			quiet = id
			quiet_centre = geography.region(id)["centre"]
			break
	check(not quiet.is_empty(), "and ground the commander left alone is worth less")
	if quiet.is_empty():
		return
	check(red.priority_for(quiet) < focused,
		"the two ends of one decision, apart by doctrine rather than by luck")
	var effort := red.effort_at(geography.region(target)["centre"])
	check(effort > 0.0, "the committed air is measurable from above")
	check(red.effort_at(quiet_centre) < effort,
		"and there is less of it over the ground nobody committed to")


## --------------------------------------------------------------------- what it does not do

## Read-only over the campaign, in the strictest sense the module can be caught being: not one
## district's published state moves while a commander is thinking about it. §13 gave the flying
## world two verbs into the war and this module is not allowed a third, so the check is that the
## war is the same war after the thinking.
func _check_the_commander_writes_nothing() -> void:
	var campaign := _campaign(1004)
	var red: COMMANDER = campaign["commander"]
	var director: DIRECTOR = campaign["director"]
	red.set_faction(CONTROL.ENEMY)
	_settle(campaign, 10)
	var target := _richest(campaign, CONTROL.FRIENDLY)
	var centre: Vector2 = campaign["geography"].region(target)["centre"]
	director.report_sighting(CONTROL.FRIENDLY, centre, 1.0)
	var before := {}
	for record: Variant in director.districts():
		before[String(record)] = str(director.district(String(record)))
	var spend := str(director.losses(CONTROL.ENEMY)) + str(director.resources(CONTROL.ENEMY))
	var facilities := str(director.facilities())
	for tick in range(6):
		red.tick(director.tick_number())
	for record: Variant in director.districts():
		check(before[String(record)] == str(director.district(String(record))),
			"a commander's turn moves nothing about the district it read (%s)" % String(record))
	check(spend == str(director.losses(CONTROL.ENEMY)) + str(director.resources(CONTROL.ENEMY)),
		"and it spends nothing: no aircraft, no supply, no losses of its own")
	check(facilities == str(director.facilities()), "and it damages no facility it was told about")


## Nothing in the score is a random number, so the same war worked the same way produces the same
## commander twice. This is what makes §16's response arguable rather than lucky.
func _check_the_decision_repeats_itself() -> void:
	var target := _richest(_campaign(1004), CONTROL.ENEMY)
	var first := str(_led_by(_campaign(777), target, WORKED_TICKS, true)["state"])
	var second := str(_led_by(_campaign(777), target, WORKED_TICKS, true)["state"])
	check(first == second, "the same campaign and the same flying give the same commander")
	check(first.contains("INTERCEPT"), "and that commander actually decided something")
	var other := str(_led_by(_campaign(4242), target, WORKED_TICKS, true)["state"])
	check(first != other, "and a different campaign does not, got one answer twice")


## ------------------------------------------------------------------ the seam with the staff

## The claim the phase rests on. A commander that changed no board would be a diagram: the same
## war, the same pilot, the same eight questions, and a different set of priorities because
## something decided what to care about first.
func _check_priority_reaches_the_board() -> void:
	var target := _richest(_campaign(1004), CONTROL.ENEMY)
	var bare := _led_by(_campaign(1004), target, WORKED_TICKS, false)
	var led := _led_by(_campaign(1004), target, WORKED_TICKS, true)
	var staff: MISSIONS = led["staff"]
	check(staff.commander() != null, "a staff seated over a commander keeps it")
	var before := {}
	for record: Dictionary in (bare["staff"] as MISSIONS).board():
		before[String(record["region_id"])] = record
	var worked := {}
	for record: Dictionary in staff.board():
		if String(record["region_id"]) == target:
			worked = record
	check(not worked.is_empty(), "the enemy staff has a job over the ground being worked")
	check(not String(worked.get("operation", "")).is_empty(),
		"and it names the operation the commander committed: %s"
			% String(worked.get("operation", "")))
	check(before.has(target), "the same job exists with nobody commanding")
	if before.has(target):
		check(float(worked["score"]) > float(before[target]["score"]) + 0.001,
			"and it comes out higher under command: %0.3f against %0.3f"
			% [float(worked["score"]), float(before[target]["score"])])
	# The neutral case, which is what lets a theatre with no campaign still have a board: with
	# nobody seated every mission is the phase 6 record, and no operation is claimed for one.
	for record: Dictionary in (bare["staff"] as MISSIONS).board():
		check(String(record.get("operation", "")).is_empty(),
			"an uncommanded board names no operation (%s)" % String(record["id"]))


## ------------------------------------------------------------------- the seam with the sky

## One number crosses into the flying world, and it is the only one §26 allows: how hard the
## enemy is pushing the ground the pilot is standing on. The shipped rhythm stays intact when
## nobody is commanding -- a negative intent means "you are your own squadron" -- and where a
## commander has committed air, the wave that arrives is bigger and comes back sooner.
##
## Every claim here is about a bound rather than a roll: the sizes the old pattern could produce,
## and the shortest gap it could have produced, so no run of this test can fail by being unlucky.
func _check_intent_reaches_the_squadron() -> void:
	var sizes := _wave_at(-1.0)
	check(sizes.has(1) and sizes.has(2) and sizes.size() == 2,
		"a squadron with no campaign flies the two ship patrol it always flew, got %s" % str(sizes))
	check(not _returns_at(-1.0, 29.9), "and on the breather it always had, never under half a minute")
	sizes = _wave_at(0.0)
	check(sizes.has(1) and sizes.has(2),
		"commanded, with nothing committed over this ground, is still the patrol")
	check(not _returns_at(0.0, 29.9), "on the same clock")
	sizes = _wave_at(0.5)
	for size in sizes:
		check(int(size) >= 2, "half an effort is at least a pair, never below the patrol")
	check(not _returns_at(0.5, 23.1), "back no sooner than 23 seconds")
	check(_returns_at(0.5, 34.9), "and no later than 35")
	sizes = _wave_at(1.0)
	for size in sizes:
		check(int(size) >= 3, "a full enemy effort arrives at least three deep, got %s" % size)
	check(_returns_at(1.0, 24.9), "and it comes back inside a quarter of a minute, every time")


## The wave the squadron actually raises, `intent` set first. Counted from a fresh node so no
## earlier roll is carried into a later one.
func _wave_at(intent: float) -> Dictionary:
	var found := {}
	for roll in range(40):
		var squadron = _squadron(intent)
		squadron.advance_encounters(
			SQUADRON.FIRST_ENCOUNTER_SECONDS + 0.1, Vector3.ZERO, Vector3.ZERO)
		found[squadron.jet_count()] = true
		squadron.free()
	return found


## Has a cleared flight come back after `seconds`? True must hold for every roll the countdown
## could have rolled, which is why the bounds above are the shortest and longest of the band.
func _returns_at(intent: float, seconds: float) -> bool:
	var squadron = _squadron(intent)
	squadron.advance_encounters(
		SQUADRON.FIRST_ENCOUNTER_SECONDS + 0.1, Vector3.ZERO, Vector3.ZERO)
	# `jets()` is the live array rather than a report of it, so killing a flight means iterating
	# over a copy -- erasing out of the one being walked would leave a wingman behind and read
	# the survivor as the next wave.
	for jet in squadron.jets().duplicate():
		squadron.destroy_jet(jet.id)
	check(squadron.jet_count() == 0, "the flight really is cleared before the clock is measured")
	squadron.advance_encounters(seconds, Vector3.ZERO, Vector3.ZERO)
	var back: bool = squadron.jet_count() > 0
	squadron.free()
	return back


func _squadron(intent: float) -> Node3D:
	var node = SQUADRON.new()
	get_root().add_child(node)
	node.intent = intent
	return node


## ------------------------------------------------------------------------------ plumbing

## A corridor with its launchers standing, its war running, and three modules seated on the same
## tables the map reads -- so a claim about a commander is a claim about the campaign the player
## is actually shown.
func _campaign(seed_value: int) -> Dictionary:
	var geography := REGIONS.new()
	check(geography.load_theatre(CORRIDOR), "the corridor must still divide into districts")
	var control := CONTROL.new()
	control.setup(geography)
	var registry := OBJECTS.new()
	check(registry.load_theatre(CORRIDOR, geography, control),
		"and the corridor must have its fields, sites and towers in it")
	var handle := 1
	var positions := []
	for record in registry.of_type(OBJECTS.Type.SAM_SITE):
		var site: Dictionary = record
		positions.append({"id": handle, "name": "%s LAUNCHER" % String(site["detail"]["site"])})
		handle += 1
	registry.bind_launchers(positions)
	var director := DIRECTOR.new()
	check(director.setup(control, geography, registry), "and the war must take the theatre")
	director.set_seed(seed_value)
	var blue := COMMANDER.new()
	check(blue.setup(director, registry, geography), "and Blue's commander must be seated")
	var red := COMMANDER.new()
	check(red.setup(director, registry, geography), "and Red's commander must be seated")
	var staff := MISSIONS.new()
	check(staff.setup(director, registry, geography), "and so must the staff over it")
	return {
		"geography": geography,
		"registry": registry,
		"director": director,
		"commander": red,
		"own": blue,
		"staff": staff,
	}


## The district one side holds that is worth the most: where a pilot would sensibly be flown, and
## therefore the district whose pattern the other side should notice.
func _richest(campaign: Dictionary, faction: String) -> String:
	var geography: REGIONS = campaign["geography"]
	var director: DIRECTOR = campaign["director"]
	var best := ""
	var value := -1.0
	for record: Variant in geography.regions():
		var id := String(record["id"])
		var state: Dictionary = director.district(id)
		if state.is_empty() or String(state["owner"]) != faction:
			continue
		if float(state["value"]) > value:
			value = float(state["value"])
			best = id
	return best


## One turn of the whole chain, in the order the flying world runs it: the campaign's clock, then
## both commanders, then the staff that turns a decision into a job.
func _settle(campaign: Dictionary, ticks: int) -> void:
	var director: DIRECTOR = campaign["director"]
	var red: COMMANDER = campaign["commander"]
	var blue: COMMANDER = campaign["own"]
	var staff: MISSIONS = campaign["staff"]
	for tick in range(ticks):
		director.tick()
		red.tick(director.tick_number())
		blue.tick(director.tick_number())
		staff.tick(director.tick_number())


## The pilot's habit: the centre of one district, reported by the friendly side, every tick, in
## the order main uses -- the sighting in ahead of the thinking.
func _work(campaign: Dictionary, district_id: String, ticks: int) -> void:
	var director: DIRECTOR = campaign["director"]
	var centre: Vector2 = campaign["geography"].region(district_id)["centre"]
	for tick in range(ticks):
		director.report_sighting(CONTROL.FRIENDLY, centre, 1.0)
		_settle(campaign, 1)


## §15's product, recomputed from the terms the operation prints beside its score.
func _product(operation: Dictionary) -> float:
	var factors: Dictionary = operation["factors"]
	var score := 1.0
	for term in factors:
		score *= float(factors[term])
	return score


func _close(a: float, b: float) -> bool:
	return absf(a - b) < 0.0005


func _intercept_of(commander: COMMANDER, district_id: String) -> Dictionary:
	for record: Dictionary in commander.operations():
		if int(record["objective"]) == COMMANDER.Objective.INTERCEPT_AIRCRAFT \
				and String(record["region_id"]) == district_id:
			return record
	return {}


## One campaign run to the end with the pattern built. `led` is the entire experiment: the same
## war and the same flying, with a commander on the staff's board and without one.
func _led_by(campaign: Dictionary, district_id: String, ticks: int, led: bool) -> Dictionary:
	var red: COMMANDER = campaign["commander"]
	var staff: MISSIONS = campaign["staff"]
	red.set_faction(CONTROL.ENEMY)
	staff.set_faction(CONTROL.ENEMY)
	staff.set_commander(red if led else null)
	_settle(campaign, 12)
	_work(campaign, district_id, ticks)
	return {"staff": staff, "state": red.snapshot()}
