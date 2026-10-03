extends SceneTree

## Phase 6's acceptance, and the one thing it has to prove is that a mission is a
## consequence. Nothing here is scripted, so the test drives the campaign: stand a launcher
## at every site and the board fills with jobs against them; accept one, fly it, take the
## launcher out from under the mission, and it succeeds because the world changed rather than
## because a timeline said so -- and the air that site was denying comes back. Then the two
## honesty checks the brief cares about: a target named by a mission is a target the flying
## world answers to and not a second identity for it (§25), and every offer on the board is
## justified by a number the war published (§17).

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

var failed := false
var events := {"created": {}, "assigned": {}, "completed": {}, "failed": {}}


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_refusals_seat_nothing()
	_check_sites_put_jobs_on_the_board()
	_check_every_offer_is_justified()
	_check_the_sead_loop()
	_check_the_strike_gate_has_a_reason()
	_check_a_job_nobody_flew_expires()
	_check_an_air_job_is_judged_not_lapsed()
	_check_the_board_repeats_itself()
	if not failed:
		print("MISSION_DIRECTOR_TEST_PASS")
	quit(1 if failed else 0)


## ---------------------------------------------------------------------- the refusals

## A module that keeps the last theatre's table when it refuses a new one is a board of
## orders over ground the player is no longer standing on. Phase 5 learned this twice, and
## the same rule is asked of the mission staff.
func _check_refusals_seat_nothing() -> void:
	var campaign := _campaign(1000)
	var staff: MISSIONS = campaign["staff"]
	var director: RefCounted = campaign["director"]
	var registry: RefCounted = campaign["registry"]
	var geography: RefCounted = campaign["geography"]
	check(not staff.setup(null, null, null), "a board with no war behind it cannot start")
	check(not staff.is_ready(), "and a refusal leaves it reporting nothing")
	check(not staff.setup(director, null, geography),
		"or one with no objects for a mission to point at")
	check(not staff.setup(director, registry, null),
		"or one with no geography to place them in")
	check(staff.missions().is_empty(), "with no missions seated behind any of those")
	check(staff.board().is_empty(), "and nothing offered")
	check(staff.setup(director, registry, geography),
		"and the same module takes the theatre afterwards, a refusal being no injury")
	check(not staff.accept("M9999"), "accepting a mission the board never had is refused")
	check(not staff.launch("M9999"), "and so is flying one")
	check(staff.snapshot()["missions"].is_empty(), "and the snapshot says the same")
	# A theatre with districts and no standing sites still has a front worth covering, and
	# whatever it does offer has to name something the registry actually has.
	var bare := _campaign(1001)
	bare["registry"].bind_launchers([])
	for tick in range(30):
		bare["director"].tick()
		bare["staff"].tick(bare["director"].tick_number())
	check(bare["staff"].is_ready(), "a staff over a theatre with districts can be seated")
	for record in bare["staff"].board():
		var mission: Dictionary = record
		var target := int(mission["primary_target"])
		check(target < 0 or not bare["registry"].of(target).is_empty(),
			"%s names an object the registry actually has" % String(mission["id"]))


## ------------------------------------------------------ §17: the missions are generated

## Stand a launcher at every site, run the war, and the board has to be the consequence:
## sites that deny the air are jobs, and ground still being fought over is worth covering.
func _check_sites_put_jobs_on_the_board() -> void:
	var campaign := _campaign(1002)
	var staff: MISSIONS = campaign["staff"]
	_stand_every_site(campaign["registry"])
	var kinds := {}
	for tick in range(40):
		campaign["director"].tick()
		staff.tick(campaign["director"].tick_number())
		for record in staff.board():
			var mission: Dictionary = record
			var kind := int(mission["kind"])
			kinds[kind] = int(kinds.get(kind, 0)) + 1
	check(not staff.available().is_empty(),
		"six standing SAM sites must be a problem the staff reports, got %d offers" \
			% staff.available().size())
	check(kinds.size() >= 3,
		"a campaign that is fighting has to offer more than one class of job, got %d: %s" \
			% [kinds.size(), str(kinds.keys())])
	var hammered := 0
	for record in staff.board():
		var mission: Dictionary = record
		if int(mission["kind"]) != MISSIONS.Kind.SEAD:
			continue
		hammered += 1
		var id := String(mission["id"])
		var site := staff.primary_target(id)
		check(not site.is_empty(), "a SEAD names the site it is against, %s named nothing" % id)
		check(int(site["type"]) == OBJECTS.Type.SAM_SITE,
			"and what it names is a SAM site, got %s" % OBJECTS.type_name(site))
		check(float(site["health"]) > 0.0,
			"against a site that is standing, got %s at health %f" \
				% [String(site["name"]), float(site["health"])])
		check(String(mission["region_id"]) == String(site["region_id"]),
			"%s must be filed under the district the site stands in" % String(site["name"]))
		check(String(mission["target_name"]) == String(site["name"]),
			"%s must name it the way the registry does" % id)
	check(hammered > 0 and hammered <= MISSIONS.KIND_LIMIT,
		"the board offers the worst %d sites rather than every position on the map, got %d" \
			% [MISSIONS.KIND_LIMIT, hammered])


## ------------------------------------------------------------- §25: one target, one name

## The rule the brief calls critical: a mission's objective is the object the registry has,
## and the entity it offers is the launcher standing at it -- the same handle the weapon
## tracker uses. Nothing in here gets to invent an id for a thing the world does not have.
func _check_every_offer_is_justified() -> void:
	var campaign := _campaign(1003)
	var staff: MISSIONS = campaign["staff"]
	var geography: REGIONS = campaign["geography"]
	var registry: OBJECTS = campaign["registry"]
	_stand_every_site(registry)
	for tick in range(24):
		campaign["director"].tick()
		staff.tick(campaign["director"].tick_number())
	var board := staff.board()
	check(not board.is_empty(), "the board must have something on it to inspect")
	for record in board:
		var mission: Dictionary = record
		var id := String(mission["id"])
		check(int(mission["kind"]) in MISSIONS.Kind.values(), "%s has a type §17 lists" % id)
		check(String(mission["status"]) in MISSIONS.STATUSES, "%s has a status §18 lists" % id)
		check(String(mission["faction"]) == CONTROL.FRIENDLY,
			"the player's staff offers the player's jobs, got %s" % String(mission["faction"]))
		for field in ["id", "callsign", "type", "faction", "region_id", "primary_target",
				"secondary_targets", "priority", "status", "briefing", "threat_level",
				"strategic_effect", "created_at", "expires_at"]:
			check(mission.has(field), "%s is missing §18's %s" % [id, field])
		check(String(mission["briefing"]).length() > 16,
			"%s must say why it exists, got %s" % [id, String(mission["briefing"])])
		check(String(mission["strategic_effect"]).length() > 8,
			"and what flying it would be worth, got %s" % String(mission["strategic_effect"]))
		check(String(mission["threat_level"]) in ["HIGH", "MEDIUM", "LOW"],
			"%s threat must be one of three words, got %s" % [id, String(mission["threat_level"])])
		check(String(mission["type"]) in MISSIONS.KIND_NAME.values(),
			"%s must be named for its kind, got %s" % [id, String(mission["type"])])
		var priority := int(mission["priority"])
		check(priority >= 1 and priority <= 5, "%s priority must be 1-5, got %d" % [id, priority])
		check(int(mission["expires_at"]) > int(mission["created_at"]),
			"%s must have a window in front of it" % id)
		check(int(mission["created_at"]) <= staff.tick_number(),
			"%s was raised on a tick that had not happened" % id)
		var district: Dictionary = geography.region(String(mission["region_id"]))
		check(not district.is_empty(), "%s is filed under a real district" % id)
		check(String(mission["region_name"]) == String(district["name"]),
			"and names it the way the geography does")
		var at := staff.position_of(id)
		check(at.is_finite(), "%s must stand somewhere finite, got %s" % [id, str(at)])
		var target_id := int(mission["primary_target"])
		if target_id < 0:
			check(String(mission["target_name"]).is_empty(),
				"an area job names no object, and %s must not name one either" % id)
			# The mark still has to be on the district the job was offered over, which is the
			# only fact it was generated from.
			if not district.is_empty():
				check(REGIONS._contains(district["polygon"], at),
					"%s is placed on the ground it was offered over" % id)
			continue
		var site := staff.primary_target(id)
		check(not site.is_empty(), "%s points at an object the registry has" % id)
		check(int(site["id"]) == target_id,
			"and it is the same object rather than a second copy of it")
		check(float(site["strategic_value"]) >= MISSIONS.MIN_TARGET_VALUE,
			"%s must be worth a sortie before anyone is asked to fly at it" % id)
		for secondary in (mission["secondary_targets"] as Array):
			check(not registry.of(int(secondary)).is_empty(),
				"%s lists a secondary the registry does not have: %d" % [id, int(secondary)])


## ------------------------------------------------------------------- the acceptance loop

## The brief's worked example, run against the real sites: the SAM denies the air, the staff
## says so, the player takes the job and flies it, the launcher goes away, and the mission
## succeeds on the world's own evidence -- with the denial it was raised on going down with
## the site.
func _check_the_sead_loop() -> void:
	var campaign := _campaign(1004)
	var staff: MISSIONS = campaign["staff"]
	var director: RefCounted = campaign["director"]
	var registry: OBJECTS = campaign["registry"]
	var geography: REGIONS = campaign["geography"]
	var handles := _stand_every_site(registry)
	var job := {}
	for tick in range(40):
		director.tick()
		staff.tick(director.tick_number())
		for record in staff.available():
			var offer: Dictionary = record
			if int(offer["kind"]) == MISSIONS.Kind.SEAD:
				job = offer
				break
		if not job.is_empty():
			break
	check(not job.is_empty(), "a SEAD has to be offered against standing sites")
	if job.is_empty():
		return
	var id := String(job["id"])
	var site := staff.primary_target(id)
	var district_id := String(site["region_id"])
	var entity := staff.primary_entity(id)
	check(entity >= 0,
		("a SEAD against a site with a launcher at it must hand over the launcher the tracker " \
			+ "already uses, got %d") % entity)
	check(handles.has(entity),
		"and that handover must be an entity the launcher field reported, not an invented one")
	var denied := _air(director, district_id)
	check(denied < MISSIONS.DENIED_AIR,
		"the district it was offered over must actually be denied, got share %f" % denied)
	# The same gate read the other way: nothing that needs clear air is offered over ground
	# whose air is not ours.
	for record in staff.board():
		var mission: Dictionary = record
		if int(mission["kind"]) == MISSIONS.Kind.STRIKE:
			var share := _air(director, String(mission["region_id"]))
			check(share >= MISSIONS.CLEAR_AIR,
				"a strike was offered over ground whose air we do not hold: %f" % share)
	check(staff.accept(id), "the player can take the job")
	check(String(staff.mission(id)["status"]) == MISSIONS.ASSIGNED,
		"and it becomes theirs, got %s" % String(staff.mission(id)["status"]))
	check(events["assigned"].has(id), "on the wire §33 names")
	check(not staff.accept(id), "a second acceptance of the same job is refused")
	check(staff.launch(id), "and a committed sortie goes ACTIVE")
	check(String(staff.mission(id)["status"]) == MISSIONS.ACTIVE, "in that status")
	check(not staff.launch(id), "which cannot be done twice")
	check(not staff.tasked().is_empty(), "and a HUD asking what it is working gets an answer")
	# Now the weapon arrives. The launcher field is the only thing that knows a site has lost
	# a launcher, so that is the seam this uses -- the same one main.gd reports through.
	registry.bind_launchers(_launcher_list(handles, entity))
	check(String(site["operational_state"]) == OBJECTS.DESTROYED,
		"a site with nothing standing at it is destroyed, got %s" \
			% String(site["operational_state"]))
	staff.tick(director.tick_number())
	var closed: Dictionary = staff.mission(id)
	var outcome := String(closed["status"])
	check(outcome == MISSIONS.SUCCESS,
		"the mission flown at it succeeds when it goes down, got %s: %s" \
			% [outcome, String(closed.get("reason", ""))])
	check(events["completed"].has(id), "and says so on the wire the brief names")
	check(String(closed["outcome"]) == MISSIONS.SUCCESS, "with the outcome recorded too")
	# And the reason it was offered stops being true. This cannot be read off one campaign's
	# own time series: the front moves under the number at the same moment, and the district's
	# air was measured *falling* for ninety ticks after its own site went down, because the
	# ground fight brought more of the enemy's effort within reach of it faster than the
	# suppression paid back. So the claim is an A/B -- the same seed, the same number of ticks,
	# every site left standing, and the single difference between the two wars the sortie the
	# player just flew.
	var horizon := 90
	var until := int(director.tick_number()) + horizon
	while director.tick_number() < until:
		director.tick()
		staff.tick(director.tick_number())
	var after := _air(director, district_id)
	var witness := _campaign(1004, true)
	_stand_every_site(witness["registry"])
	var mirror: RefCounted = witness["director"]
	var mirrored: MISSIONS = witness["staff"]
	while mirror.tick_number() < director.tick_number():
		mirror.tick()
		mirrored.tick(mirror.tick_number())
	var standing := _air(mirror, district_id)
	check(after > standing,
		("taking the site down has to be felt in the air over its district: %f against %f at " \
			+ "tick %d of the same war") % [after, standing, int(director.tick_number())])
	check(after - standing >= 0.02,
		"and be felt by more than the last digit: %f against %f" % [after, standing])
	# The same difference read off the staff's own output rather than off the campaign's: with
	# the launcher still standing, the war at this tick is still asking for it to come down, and
	# the campaign that flew the sortie has stopped asking. That is the board being a consequence
	# of the state, which is the whole reason a player can trust a mission over a notification.
	check(_offered(mirrored, MISSIONS.Kind.SEAD, district_id),
		"the counterfactual campaign must still be offering the job that was just flown")
	check(not _offered(staff, MISSIONS.Kind.SEAD, district_id),
		"and a site that is down must not be offered again")
	# The last line of the brief's acceptance: the follow-up becomes possible. In a corridor
	# whose whole hostile order of battle is launcher sites, the attack that succeeds a SEAD is
	# the one §17 describes as standoff work against ground targets -- so what has to be true is
	# that the campaign which flew the sortie is offering attack work over that ground or the
	# ground behind it, and the campaign that left the site standing is not.
	var opened := _attacks_within(geography, staff, district_id)
	var closed_board := _attacks_within(geography, mirrored, district_id)
	check(not opened.is_empty(),
		("with the site down, attack work has to be on the board around %s, got %s") \
			% [district_id, str(opened)])
	check(opened != closed_board,
		("and the war must offer something different from the one where it was left standing: " \
			+ "%s against %s") % [str(opened), str(closed_board)])
	# An offer on the board is never a duplicate of a job already being flown at the same
	# thing, which is what the same site being offered twice in one campaign would look like.
	for record in staff.available():
		var offer: Dictionary = record
		if int(offer["kind"]) == MISSIONS.Kind.SEAD:
			check(staff.primary_entity(String(offer["id"])) != entity,
				"a site that is down cannot be offered again")


## ------------------------------------------------------- a quiet kind is quiet for a reason

## §17 lists eight kinds, and this corridor's hostile order of battle is six launcher sites,
## which makes a strike against a position the kind the world gives least for. That is allowed;
## a gate that refuses without saying why is not, because from out here it is indistinguishable
## from a bug. So every district the air is ours over, on the line and worth flying to, has to be
## either offered for a package, or explained by what the registry actually keeps in it -- and
## what explains it is that a launcher standing there is a SEAD, which the board must not also
## put up a second time under another callsign.
func _check_the_strike_gate_has_a_reason() -> void:
	var campaign := _campaign(1005)
	var staff: MISSIONS = campaign["staff"]
	var director: RefCounted = campaign["director"]
	var registry: OBJECTS = campaign["registry"]
	var geography: REGIONS = campaign["geography"]
	_stand_every_site(registry)
	for tick in range(60):
		director.tick()
		staff.tick(director.tick_number())
	var subjects := 0
	for record in geography.regions():
		var region: Dictionary = record
		var district_id := String(region["id"])
		var own: Dictionary = director.district(district_id)
		if own.is_empty() or String(own["owner"]) == CONTROL.FRIENDLY:
			continue
		if not _from_line(geography, director, district_id):
			continue
		if float(own["value"]) < MISSIONS.MIN_DISTRICT_VALUE:
			continue
		if _air(director, district_id) < MISSIONS.CLEAR_AIR:
			continue
		subjects += 1
		if _offered(staff, MISSIONS.Kind.STRIKE, district_id):
			continue
		var names := _strikable_in(registry, district_id)
		check(names.is_empty() or staff.board().size() >= MISSIONS.LIVE_LIMIT,
			("%s is at the strike gate with the air ours and nothing offered for it and no " \
				+ "reason in the world: %s stands in it and the board has %d offers") \
				% [district_id, str(names), staff.board().size()])
	check(subjects > 0,
		"the gate has to have been asked about at all, or this test has proven nothing about it")
	for record in staff.board():
		var mission: Dictionary = record
		if int(mission["kind"]) != MISSIONS.Kind.STRIKE:
			continue
		var site := staff.primary_target(String(mission["id"]))
		if site.is_empty():
			check(int(mission["primary_target"]) < 0,
				"a strike names the object it is sent against, and %s has no target at all" \
					% String(mission["id"]))
			continue
		check(int(site["type"]) != OBJECTS.Type.SAM_SITE or float(site["health"]) <= 0.0,
			"a launcher that is standing is offered once, as a SEAD, and not twice under %s" \
				% String(mission["callsign"]))


## ----------------------------------------------------------- the job nobody took

## An offer that was never accepted, and a job accepted and never flown, both end the same
## way and for the same reason: the window closed. Neither is a success, because neither was
## flown -- that distinction is the whole reason a mission board can be trusted.
func _check_a_job_nobody_flew_expires() -> void:
	var campaign := _campaign(1006)
	var staff: MISSIONS = campaign["staff"]
	_stand_every_site(campaign["registry"])
	var job := {}
	for tick in range(30):
		campaign["director"].tick()
		staff.tick(campaign["director"].tick_number())
		if staff.available().is_empty():
			continue
		if job.is_empty():
			job = staff.available()[0]
	var left := {}
	for record in staff.board():
		var offer: Dictionary = record
		if String(offer["status"]) == MISSIONS.AVAILABLE:
			left = offer
			break
	check(not left.is_empty(), "there must be an offer on the board to leave alone")
	if left.is_empty():
		return
	var id := String(left["id"])
	var window := int(left["expires_at"]) - int(left["created_at"]) + 3
	for tick in range(window):
		campaign["director"].tick()
		staff.tick(campaign["director"].tick_number())
		if String(staff.mission(id)["status"]) in MISSIONS.CLOSED:
			break
	var closed: Dictionary = staff.mission(id)
	check(String(closed["status"]) in MISSIONS.CLOSED,
		"an offer nobody took cannot stay open past its window, got %s" \
			% String(closed["status"]))
	check(String(closed["outcome"]) != MISSIONS.SUCCESS,
		"a job nobody flew never succeeds, got %s" % String(closed["outcome"]))
	# The accepted-but-never-flown case, which is the one a player can actually do.
	var second := {}
	for record in staff.board():
		var offer: Dictionary = record
		if String(offer["status"]) == MISSIONS.AVAILABLE:
			second = offer
			break
	if second.is_empty():
		return
	var job_id := String(second["id"])
	check(staff.accept(job_id), "a player can take a second job")
	var deadline := int(second["expires_at"]) - int(second["created_at"]) + 3
	for tick in range(deadline):
		campaign["director"].tick()
		staff.tick(campaign["director"].tick_number())
		if String(staff.mission(job_id)["status"]) in MISSIONS.CLOSED:
			break
	var ended: Dictionary = staff.mission(job_id)
	var status := String(ended["status"])
	check(status != MISSIONS.SUCCESS,
		"a job taken and not flown does not succeed on the war's own account, got %s" % status)
	check(status in MISSIONS.CLOSED, "and it does end, got %s" % status)
	check(not String(ended["reason"]).is_empty(), "saying why: %s" % String(ended["reason"]))
	check(events["failed"].has(job_id), "with the failure on the wire §33 names")
	check(not job.is_empty(), "and the first offer was a real one")


## ------------------------------------------------ an air job is judged, not left running

## CAP is offered because the airspace over ground we hold is not ours. A sortie committed
## to it is answered with a verdict rather than allowed to lapse, whatever the campaign does
## afterwards -- which is the difference between a job and a notification.
func _check_an_air_job_is_judged_not_lapsed() -> void:
	var campaign := _campaign(1007)
	var staff: MISSIONS = campaign["staff"]
	var registry: OBJECTS = campaign["registry"]
	_stand_every_site(registry)
	var patrol := {}
	for tick in range(60):
		campaign["director"].tick()
		staff.tick(campaign["director"].tick_number())
		for record in staff.board():
			var mission: Dictionary = record
			if int(mission["kind"]) == MISSIONS.Kind.CAP \
					and String(mission["status"]) == MISSIONS.AVAILABLE:
				patrol = mission
				break
		if not patrol.is_empty():
			break
	if patrol.is_empty():
		# Nothing offered for CAP is a real answer about this campaign rather than a failure
		# of the module: it means every district worth covering already has the air it needs.
		check(not staff.board().is_empty(), "and the board still has the jobs it does have")
		return
	var id := String(patrol["id"])
	var district_id := String(patrol["region_id"])
	var share := _air(campaign["director"], district_id)
	check(share < MISSIONS.HOLD_AIR,
		"a CAP is offered over air we do not hold, got %f" % share)
	check(staff.accept(id) and staff.launch(id), "the patrol can be flown")
	# Take the denial away entirely and let the war work out what the airspace is worth.
	registry.bind_launchers([])
	var window := int(patrol["expires_at"]) - int(patrol["created_at"]) + 8
	for tick in range(window):
		campaign["director"].tick()
		staff.tick(campaign["director"].tick_number())
		if String(staff.mission(id)["status"]) in MISSIONS.CLOSED:
			break
	var closed: Dictionary = staff.mission(id)
	var status := String(closed["status"])
	check(status in MISSIONS.CLOSED, "a flown patrol ends, got %s" % status)
	check(status != MISSIONS.EXPIRED,
		("a patrol committed to is judged on what it achieved rather than left to lapse, " \
			+ "got %s") % status)
	check(not String(closed["reason"]).is_empty(), "with the reason recorded")
	if status == MISSIONS.SUCCESS:
		check(events["completed"].has(id), "and a success announced on the wire")


## -------------------------------------------------------------------- determinism

## Same campaign, same board. A mission generator that needs a random number to be
## interesting is a mission generator that cannot be tested.
func _check_the_board_repeats_itself() -> void:
	var first := _board_after(777, 30)
	var second := _board_after(777, 30)
	check(str(first) == str(second), "the same war must be offered the same jobs")
	var third := _board_after(4242, 30)
	check(str(first) != str(third), "and a different war must not, got the same board twice")


## -------------------------------------------------------------------------- plumbing

## A whole campaign to itself -- districts, the opening situation, the objects standing on
## them, the war over the top of both and the staff reading that war -- because a claim about
## one board cannot be answered by another board's leftovers.
func _campaign(seed_value: int, quiet := false) -> Dictionary:
	var geography := REGIONS.new()
	check(geography.load_theatre(CORRIDOR), "the corridor must still divide into districts")
	var control := CONTROL.new()
	control.setup(geography)
	var registry := OBJECTS.new()
	check(registry.load_theatre(CORRIDOR, geography, control),
		"and the corridor must have its fields, sites and towers in it")
	var director := DIRECTOR.new()
	check(director.setup(control, geography, registry), "and the war must take the theatre")
	director.set_seed(seed_value)
	var staff := MISSIONS.new()
	check(staff.setup(director, registry, geography), "and the staff must be seated over it")
	# A counterfactual campaign is run to be compared with, not announced: its missions share
	# this file's event log and its seed, so wiring it up would answer a question about the war
	# with numbers from whichever of the two boards fired last.
	if not quiet:
		staff.mission_created.connect(_on_created)
		staff.mission_assigned.connect(_on_assigned)
		staff.mission_completed.connect(_on_completed)
		staff.mission_failed.connect(_on_failed)
	return {
		"geography": geography,
		"control": control,
		"registry": registry,
		"director": director,
		"staff": staff,
	}


func _on_created(mission: Dictionary) -> void:
	events["created"][String(mission["id"])] = String(mission["callsign"])


func _on_assigned(id: String) -> void:
	events["assigned"][id] = true


func _on_completed(id: String, outcome: String) -> void:
	events["completed"][id] = outcome


func _on_failed(id: String, reason: String) -> void:
	events["failed"][id] = reason


## Every site gets a launcher, which is the only thing that makes an authored position stand:
## the field places it and the registry reads it back as the site's health. Returns the
## entity ids handed out, keyed as the launcher field keys them, so a test can ask whether a
## mission named the real one.
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


## The same set of launchers, minus one -- which is what a weapon arriving looks like to the
## launcher field.
func _launcher_list(handles: Dictionary, skip: int = -1) -> Array:
	var positions := []
	for handle in handles:
		if int(handle) == skip:
			continue
		positions.append({"id": int(handle), "name": String(handles[handle])})
	positions.sort_custom(_by_id)
	return positions


static func _by_id(a: Dictionary, b: Dictionary) -> bool:
	return int(a["id"]) < int(b["id"])


## The friendly share of the air over a district, asked of the war rather than of the module,
## so a claim about the gate is a measurement and not a restatement.
func _air(director: RefCounted, district_id: String) -> float:
	return DIRECTOR.share_of(director.air_balance(district_id), CONTROL.FRIENDLY)


## Whether the board has a job of this kind over this district right now -- asked of the
## published table rather than of a private generator, so it is what the map would show.
func _offered(staff: MISSIONS, kind: int, district_id: String) -> bool:
	for record in staff.board():
		var mission: Dictionary = record
		if int(mission["kind"]) == kind and String(mission["region_id"]) == district_id:
			return true
	return false


## Reach, recomputed here rather than borrowed: a district is on the line when we hold it or
## hold next to it, which is the same question the staff asks its own geography.
func _from_line(geography: REGIONS, director: RefCounted, district_id: String) -> bool:
	if String(director.district(district_id).get("owner", CONTROL.NEUTRAL)) == CONTROL.FRIENDLY:
		return true
	for neighbour in (geography.adjacency().get(district_id, {}) as Dictionary).keys():
		if String(director.district(String(neighbour)).get("owner", CONTROL.NEUTRAL)) \
				== CONTROL.FRIENDLY:
			return true
	return false


## The attack jobs on a board over a district or the ground touching it. What has to be true
## after a SEAD is that the neighbourhood is workable, not that one particular kind appeared:
## a strike on a position, an interdiction of the ground behind it and close air support on the
## way in are the same consequence of the corridor being open.
func _attacks_within(
		geography: REGIONS, staff: MISSIONS, district_id: String) -> Array:
	var near := {district_id: true}
	for neighbour in (geography.adjacency().get(district_id, {}) as Dictionary).keys():
		near[String(neighbour)] = true
	var found := []
	for record in staff.board():
		var mission: Dictionary = record
		var kind := int(mission["kind"])
		if kind not in [
				MISSIONS.Kind.STRIKE, MISSIONS.Kind.CAS, MISSIONS.Kind.GROUND_INTERDICTION]:
			continue
		if not near.has(String(mission["region_id"])):
			continue
		found.append([String(mission["type"]), String(mission["region_id"])])
	found.sort()
	return found


## The hostile objects in a district that a bomb package exists to be sent against: standing,
## worth a sortie, and not a launcher -- because a launcher is the SEAD's own business, and the
## board putting the same objective up twice is the duplicate §25 is about.
func _strikable_in(registry: OBJECTS, district_id: String) -> Array:
	var names := []
	for record in registry.objects():
		var object: Dictionary = record
		if String(object["faction"]) != CONTROL.ENEMY \
				or String(object["region_id"]) != district_id \
				or float(object["health"]) <= 0.0 \
				or float(object["strategic_value"]) < MISSIONS.MIN_TARGET_VALUE:
			continue
		if int(object["type"]) == OBJECTS.Type.SAM_SITE:
			continue
		names.append(String(object["name"]))
	return names


func _board_after(seed_value: int, ticks: int) -> Array:
	var campaign := _campaign(seed_value)
	_stand_every_site(campaign["registry"])
	var staff: MISSIONS = campaign["staff"]
	for tick in range(ticks):
		campaign["director"].tick()
		staff.tick(campaign["director"].tick_number())
	var board := []
	for record in staff.board():
		var mission: Dictionary = record
		board.append([
			String(mission["type"]),
			String(mission["region_id"]),
			int(mission["primary_target"]),
			int(mission["priority"]),
			String(mission["callsign"]),
		])
	return board
