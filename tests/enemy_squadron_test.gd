extends SceneTree

## A squadron is a formation, not a crowd: the jets arrive together, spread out
## from a lead, and every one of them is reportable to the tracker as a contact.

const SQUADRON := preload("res://scripts/entities/enemy_squadron.gd")
const ENEMY := preload("res://scripts/entities/enemy_jet.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_spawns_the_requested_number()
	_spreads_them_out_from_a_lead()
	_spawns_them_far_enough_away_to_be_seen_coming()
	_reports_every_jet_as_a_contact()
	_ids_do_not_collide_with_the_drones()
	_destroying_a_jet_removes_it()
	_world_query_includes_enemy_jets()
	if _failed:
		return
	print("ENEMY_SQUADRON_TEST_PASS")
	quit()


func _squadron() -> Node3D:
	var node = SQUADRON.new()
	get_root().add_child(node)
	return node


func _spawns_the_requested_number() -> void:
	var squadron := _squadron()
	squadron.spawn(4, Vector3.ZERO)
	if squadron.jet_count() != 4:
		_fail("a four ship is four jets, got %d" % squadron.jet_count())
	squadron.free()


func _spreads_them_out_from_a_lead() -> void:
	var squadron := _squadron()
	squadron.spawn(3, Vector3.ZERO)
	var seen := {}
	for jet in squadron.jets():
		seen[str(jet.formation_offset)] = true
	if seen.size() != 3:
		_fail("every wingman needs its own slot, got %d distinct" % seen.size())
	for jet in squadron.jets():
		if jet.formation_offset.length() > SQUADRON.FORMATION_SPACING_M * 3.0:
			_fail("a formation is tight, not scattered")
	squadron.free()


## It must appear on the scope before it appears in the canopy.
func _spawns_them_far_enough_away_to_be_seen_coming() -> void:
	var squadron := _squadron()
	var player := Vector3(0.0, 3000.0, 0.0)
	squadron.spawn(2, player)
	for jet in squadron.jets():
		var range_m: float = jet.position.distance_to(player)
		if range_m < TRACKER.RADAR_RANGES_M[1]:
			_fail("spawning inside the default scope range is an ambush, got %f" % range_m)
		if jet.position.y < ENEMY.MIN_ALTITUDE_M:
			_fail("a jet must not spawn underground")
	squadron.free()


func _reports_every_jet_as_a_contact() -> void:
	var squadron := _squadron()
	squadron.spawn(3, Vector3.ZERO)
	var contacts: Array = squadron.contacts()
	if contacts.size() != 3:
		_fail("every jet is a contact, got %d" % contacts.size())
	for c in contacts:
		if int(c["kind"]) != TRACKER.Kind.AIR_JET:
			_fail("an enemy Raptor is a jet contact")
		if not c.has("velocity"):
			_fail("a contact carries its velocity so closure can be computed")
	squadron.free()


func _ids_do_not_collide_with_the_drones() -> void:
	if SQUADRON.FIRST_ID <= 100000:
		_fail("jet ids must start above the drone ids or the hit index confuses them")


func _destroying_a_jet_removes_it() -> void:
	var squadron := _squadron()
	squadron.spawn(2, Vector3.ZERO)
	var id: int = squadron.jets()[0].id
	squadron.destroy_jet(id)
	for jet in squadron.jets():
		if jet.id == id and jet.state != ENEMY.State.DESTROYED:
			_fail("a killed jet must be marked destroyed")
	if squadron.jet_count() != 1:
		_fail("a killed jet stops counting, got %d alive" % squadron.jet_count())
	squadron.free()


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)

func _world_query_includes_enemy_jets() -> void:
	var squadron := _squadron()
	squadron.spawn(1, Vector3.ZERO)
	var jet = squadron.jets()[0]
	var query = load("res://scripts/world/world_hit_query.gd").new()
	query.additional_entity_indices.append(squadron)
	var hit = query.query_segment(jet.position - Vector3(100,0,0), jet.position + Vector3(100,0,0))
	if hit == null or hit.object_id != jet.id:
		_fail("the production world query must include enemy jet hulls")
	squadron.destroy_jet(jet.id)
	if query.query_segment(jet.position - Vector3(100,0,0), jet.position + Vector3(100,0,0)) != null:
		_fail("destroyed enemy hulls must leave the world hit query")
	squadron.free()
