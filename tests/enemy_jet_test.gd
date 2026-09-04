extends SceneTree

## A Raptor that will not fire still has to be frightening, so what is asserted
## here is the geometry of the fight: it closes, it goes for your six rather
## than for a shot, it breaks AWAY when you point at it, and it eventually
## gives up and leaves rather than circling you forever.

const ENEMY := preload("res://scripts/entities/enemy_jet.gd")

var _failed := false


func _init() -> void:
	_ingress_becomes_pursuit_when_it_finds_you()
	_pursuit_closes_the_range()
	_inside_merge_range_it_fights_for_position()
	_being_pointed_at_makes_it_break_away()
	_it_jinks_so_it_cannot_be_led()
	_it_gives_up_and_leaves()
	_a_destroyed_jet_stops_flying()
	if _failed:
		return
	print("ENEMY_JET_TEST_PASS")
	quit()


func _fresh(distance: float) -> RefCounted:
	var jet = ENEMY.new()
	jet.id = 1
	jet.position = Vector3(0.0, 3000.0, -distance)
	jet.heading = PI
	jet.speed = ENEMY.ENEMY_CRUISE_MPS
	return jet


func _ingress_becomes_pursuit_when_it_finds_you() -> void:
	var player := Vector3(0.0, 3000.0, 0.0)
	# Beyond pursuit range it is merely inbound.
	var distant = _fresh(15000.0)
	distant.update(0.1, player, Vector3.BACK)
	if distant.state != ENEMY.State.INGRESS:
		_fail("beyond %f m it is still only inbound, got %d" % [ENEMY.PURSUIT_RANGE_M, distant.state])
	# Inside it, it commits to the chase.
	var close = _fresh(9000.0)
	close.update(0.1, player, Vector3.BACK)
	if close.state != ENEMY.State.PURSUIT:
		_fail("inside pursuit range it commits to the chase, got %d" % close.state)


func _pursuit_closes_the_range() -> void:
	var jet = _fresh(9000.0)
	var player := Vector3(0.0, 3000.0, 0.0)
	var before: float = jet.position.distance_to(player)
	for i in range(40):
		jet.update(0.1, player, Vector3.BACK)
	if jet.position.distance_to(player) >= before:
		_fail("a pursuing jet must close, went from %f to %f" % [before, jet.position.distance_to(player)])


func _inside_merge_range_it_fights_for_position() -> void:
	var jet = _fresh(2000.0)
	# The player is pointing away, so the jet is not threatened and will merge.
	jet.update(0.1, Vector3(0.0, 3000.0, 0.0), Vector3.BACK)
	if jet.state != ENEMY.State.MERGE:
		_fail("inside merge range the chase becomes a knife fight, got %d" % jet.state)


## Never toward the nose: that is a head-on, and the jet loses it.
func _being_pointed_at_makes_it_break_away() -> void:
	var jet = _fresh(1000.0)
	var player := Vector3(0.0, 3000.0, 0.0)
	# The player's nose is on the jet, which sits at -Z from the player.
	jet.update(0.1, player, Vector3.FORWARD)
	if jet.state != ENEMY.State.EVADE:
		_fail("pointed at, inside threat range, it must break, got %d" % jet.state)
	# Assert the turn, not the range. At 0.32 rad/s a jet pointed straight at
	# you cannot open the distance inside a few seconds -- it has to swing its
	# nose off you first, and that swing is the actual claim being made.
	var to_player: Vector3 = (player - jet.position).normalized()
	var alignment_before: float = jet.nose().dot(to_player)
	for i in range(25):
		jet.update(0.1, player, Vector3.FORWARD)
	var to_player_now: Vector3 = (player - jet.position).normalized()
	if jet.nose().dot(to_player_now) >= alignment_before:
		_fail("breaking means turning the nose off the player, not holding it on")


func _it_jinks_so_it_cannot_be_led() -> void:
	var jet = _fresh(1000.0)
	var player := Vector3(0.0, 3000.0, 0.0)
	jet.update(0.1, player, Vector3.FORWARD)
	var first: float = jet.break_sign
	var reversed := false
	for i in range(int(ENEMY.JINK_INTERVAL / 0.1) + 6):
		jet.update(0.1, player, Vector3.FORWARD)
		if not is_equal_approx(jet.break_sign, first):
			reversed = true
			break
	if not reversed:
		_fail("a steady deflection must not solve this jet: the break has to reverse")


func _it_gives_up_and_leaves() -> void:
	var jet = _fresh(2000.0)
	var player := Vector3(0.0, 3000.0, 0.0)
	var steps := int((ENEMY.EGRESS_AFTER_SECONDS + 2.0) / 0.1)
	for i in range(steps):
		jet.update(0.1, player, Vector3.BACK)
	if jet.state != ENEMY.State.EGRESS:
		_fail("a fight that goes nowhere ends, got %d" % jet.state)


func _a_destroyed_jet_stops_flying() -> void:
	var jet = _fresh(2000.0)
	jet.state = ENEMY.State.DESTROYED
	var where: Vector3 = jet.position
	jet.update(0.5, Vector3.ZERO, Vector3.FORWARD)
	if not jet.position.is_equal_approx(where):
		_fail("the dead do not manoeuvre")


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
