extends SceneTree
const COMBAT := preload("res://scripts/entities/enemy_combat.gd")
const ENEMY := preload("res://scripts/entities/enemy_jet.gd")
const QUERY := preload("res://scripts/world/world_hit_query.gd")
const WARNING := preload("res://scripts/ui/threat_warning.gd")
const TRAILS := preload("res://scripts/effects/trail_renderer.gd")
var failed := false
var hits := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var combat := COMBAT.new()
	root.add_child(combat)
	var trails := TRAILS.new()
	root.add_child(trails)
	combat.trails = trails
	combat.player_hit.connect(func(_p): hits += 1)
	var site := {"id": 1, "position": Vector3(0, 10, -2000)}
	for altitude in [152.3, 152.4]:
		combat.clear()
		combat.grace_remaining = 0.0
		advance(combat, 4.0, Vector3(0, altitude + 900, 0), altitude, [], [site])
		check(combat.projectiles.active_rounds.is_empty() and combat.warning_state().locks == 0, "SAM must not lock at/below 500 ft AGL even over high terrain")
	combat.clear()
	combat.grace_remaining = 0.0
	advance(combat, 3.0, Vector3(0, 1000, 0), 1000, [], [site])
	check(combat.warning_state().locks == 1 and combat.projectiles.active_rounds.is_empty(), "SAM acquisition warns before it fires")
	advance(combat, 1.5, Vector3(0, 1000, 0), 1000, [], [site])
	check(combat.projectiles.active_rounds.size() == 1, "SAM launches after sustained lock")
	check(trails.total_segments() > 0, "hostile SAM lays a world-space smoke trail")
	var sam_round: RefCounted = combat.projectiles.active_rounds[0]
	advance(combat, 0.8, Vector3(0, 1000, 0), 150, [], [site])
	check(sam_round.flight._guidance_lost, "descending below the floor breaks in-flight SAM radar guidance")
	combat.clear()
	combat.grace_remaining = 0.0
	advance(combat, 4.5, Vector3(0, 1000, 0), 1000, [], [site])
	sam_round = combat.projectiles.active_rounds[0]
	advance(combat, 1.0, Vector3(0, 1000, 0), 1000, [], [])
	check(combat.warning_state().locks == 0 and sam_round.flight._guidance_lost, "destroying a SAM retires its radar lock")
	combat.clear()
	combat.grace_remaining = 0.0
	hits = 0
	advance(combat, 14.0, Vector3(0, 1000, 0), 1000, [], [site])
	check(hits == 1, "live SAM missile intercepts and damages the player")
	combat.clear()
	combat.grace_remaining = 0.0
	var query := QUERY.new()
	query.configure(func(_x, z): return 1500.0 if z > -1200 and z < -800 else 0.0, null, null, 0)
	combat.world_query = query
	advance(combat, 4.0, Vector3(0, 1000, 0), 1000, [], [site])
	check(combat.projectiles.active_rounds.is_empty() and combat.warning_state().locks == 0, "intervening terrain blocks acquisition")
	combat.world_query = null
	for hz in [60, 120]:
		combat.clear()
		combat.grace_remaining = 0.0
		hits = 0
		var jet := ENEMY.new()
		jet.id = 200001
		jet.position = Vector3(0, 1000, -2400)
		jet.heading = PI
		jet.velocity = Vector3.BACK * 300.0
		jet.state = ENEMY.State.PURSUIT
		advance(combat, 4.5, Vector3(0, 1000, 0), 1000, [jet], [], hz)
		check(combat.projectiles.active_rounds.size() == 1, "aircraft fires from its forward firing cone")
		check(combat.warning_state().incoming == 1, "closing aircraft missile raises inbound warning")
		advance(combat, 8.0, Vector3(0, 1000, 0), 1000, [], [], hz)
		check(hits == 1, "live air missile intercepts and damages player once at %d Hz" % hz)
		combat.clear()
		combat.grace_remaining = 0.0
		jet.state = ENEMY.State.EVADE
		advance(combat, 4.0, Vector3(0, 1000, 0), 1000, [jet], [])
		check(combat.projectiles.active_rounds.is_empty(), "defensive manoeuvres suppress new launches")
	combat.clear()
	combat.grace_remaining = 0.0
	combat.clear()
	advance(combat, 19.0, Vector3(0, 1200, 0), 1200, [], [site])
	check(combat.projectiles.active_rounds.is_empty() and combat.warning_state().locks == 0, "spawn/recovery grace prevents immediate attacks and lock alarms")
	combat.grace_remaining = 0.0
	var sites := []
	for i in 24:
		sites.append({"id": i + 1, "position": Vector3(i * 25, 10, -5000)})
	for frame in 3600:
		combat.update(1.0 / 60.0, Vector3(0, 1200, 0), Vector3.ZERO, 1200, [], sites)
		if combat.warning_state().locks > 1:
			check(false, "only one hostile source may acquire the player at a time")
			break
		if combat.projectiles.active_rounds.size() > 1:
			check(false, "never more than one hostile missile, even across full clusters")
			break
	check(combat.projectiles.active_rounds.size() <= COMBAT.MAX_MISSILES, "clusters share a bounded, staggered missile budget")
	combat.update(0.1, Vector3.ZERO, Vector3.ZERO, 0, [], [], false)
	check(combat.projectiles.active_rounds.is_empty() and combat.warning_state().incoming == 0, "inactive aircraft clears attacks and warnings")
	check(WARNING.pulse_period(200, true) < WARNING.pulse_period(2000, true) and WARNING.pulse_period(2000, true) < WARNING.pulse_period(6000, true), "pulse and audio cadence accelerates continuously with proximity")
	check(WARNING._warning_tone().data.size() > 4000, "warning contains audible PCM samples")
	combat.free()
	trails.free()
	if not failed:
		print("ENEMY_COMBAT_TEST_PASS")
	quit(1 if failed else 0)

func advance(combat: Node3D, seconds: float, point: Vector3, agl: float, jets: Array, sites: Array, hz := 60) -> void:
	for i in roundi(seconds * hz):
		combat.update(1.0 / hz, point, Vector3.ZERO, agl, jets, sites)

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
