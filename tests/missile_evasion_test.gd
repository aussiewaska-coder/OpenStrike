extends SceneTree
const FLIGHT := preload("res://scripts/weapons/hostile_missile_flight.gd")
const DEFENCE := preload("res://scripts/weapons/aircraft_defence.gd")
const CM := preload("res://scripts/effects/countermeasures.gd")
const AIRFRAME := preload("res://scripts/jet/airframe.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
var failed := false
func _init(): call_deferred("run")
func run():
	var defence := DEFENCE.new()
	var normal_range := defence.radar_range()
	for profile in [AIRFRAME.raptor(), AIRFRAME.lightning(), AIRFRAME.nighthawk()]:
		defence.radar_signature = profile.radar_signature
		check(defence.radar_range() < normal_range * 0.65, "stealth shortens radar acquisition range for " + profile.display_name)
	defence.position = Vector3(0, 1000, 0)
	defence.nose = Vector3.BACK
	defence.afterburner = 0.0
	var cool := defence.heat_strength(Vector3(0, 1000, -1000))
	var cool_range := defence.heat_range()
	defence.afterburner = 1.0
	check(defence.heat_strength(Vector3(0, 1000, -1000)) > cool * 4.0 and defence.heat_range() > cool_range, "afterburner increases heat attraction and acquisition range")
	defence.velocity = Vector3.RIGHT * 220
	check(not defence.radar_trackable(Vector3(0, 1000, -2000)), "stealth aircraft can break radar tracking by beaming")
	for hz in [60, 120]:
		check(simulate(false, hz), "straight flight remains vulnerable at %d Hz" % hz)
		check(not simulate(true, hz), "a timed break evades the same missile at %d Hz" % hz)
	var cm := CM.new()
	root.add_child(cm)
	check(cm.deploy(Vector3(0, 1000, 0), Vector3.BACK * 220, Vector3.BACK), "countermeasures deploy a salvo")
	check(cm.decoys.size() == 6 and cm.charges == 7 and not cm.deploy(Vector3.ZERO, Vector3.ZERO, Vector3.BACK), "salvo consumes one charge and prevents button spam")
	for burner in [0.0, 1.0]:
		defence.afterburner = burner
		defence.velocity = Vector3.BACK * 220
		var flight := FLIGHT.new()
		flight.defence = defence
		flight.target_handle = -2
		flight.target_provider = func(_id): return TRACKER.contact(-2, TRACKER.Kind.AIR_JET, defence.position, defence.velocity, "PLAYER")
		flight.decoy_provider = cm.contacts
		for i in 30: flight.advance(Vector3(0, 1000, -900), Vector3.BACK * 450, 1.0 / 60, 1.0)
		check((flight._decoy_handle != 0) == (burner == 0), "cutting afterburner lets flares win the seeker; full reheat can defeat the decoy")
		if flight._decoy_handle != 0:
			var decoy: Dictionary = flight.target()
			var hit = flight.proximity_hit(decoy.position - Vector3.BACK * 10, decoy.position + Vector3.BACK * 10, 2.0)
			check(hit != null and hit.object_id != -2, "a missile hitting its decoy cannot damage the player")
	var radar := FLIGHT.new()
	radar.seeker = FLIGHT.Seeker.RADAR
	radar.defence = defence
	radar.target_handle = -2
	radar.target_provider = func(_id): return TRACKER.contact(-2, TRACKER.Kind.AIR_JET, defence.position, defence.velocity, "PLAYER")
	radar.radar_lock_provider = func(): return -2
	radar.decoy_provider = cm.contacts
	for i in 30: radar.advance(Vector3(0, 1000, -900), Vector3.BACK * 450, 1.0 / 60, 1.0)
	check(radar._decoy_handle != 0, "chaff can draw a radar seeker away from a stealth aircraft")
	cm.update(10.0)
	check(cm.decoys.is_empty() and cm.charges == 8, "decoys expire and depleted charges replenish")
	cm.free()
	if not failed: print("MISSILE_EVASION_TEST_PASS")
	quit(1 if failed else 0)

func simulate(turn: bool, hz: int) -> bool:
	var flight := FLIGHT.new()
	var defence := DEFENCE.new()
	defence.position = Vector3(0, 1500, 0)
	defence.velocity = Vector3.BACK * 220
	flight.defence = defence
	flight.target_handle = -2
	flight.target_provider = func(_id): return TRACKER.contact(-2, TRACKER.Kind.AIR_JET, defence.position, defence.velocity, "PLAYER")
	var point := Vector3(0, 1500, -1800)
	var velocity := Vector3.BACK * 450
	var heading := 0.0
	var breaking := false
	for i in 16 * hz:
		var dt := 1.0 / hz
		breaking = breaking or (turn and point.distance_to(defence.position) < 700)
		if breaking: heading += 0.32 * dt
		defence.velocity = Vector3(sin(heading), 0, cos(heading)) * 220
		defence.position += defence.velocity * dt
		var next := flight.advance(point, velocity, dt, float(i) / hz)
		if flight.proximity_hit(point, next[0], float(i) / hz) != null: return true
		point = next[0]
		velocity = next[1]
	return false
func check(ok: bool, message: String):
	if not ok:
		failed = true
		push_error(message)
