extends SceneTree

## The tracker's two answers differ on purpose: the scope sees all round, the
## visor only boxes what is in front. Everything else here is bookkeeping --
## nearest first, and nothing beyond the selected range.

const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

var _failed := false


func _init() -> void:
	_tracks_all_aspect_within_range()
	_drops_contacts_beyond_range()
	_boxes_only_the_forward_cone()
	_caps_the_boxes()
	_orders_nearest_first()
	_range_follows_the_scope()
	_locks_the_contact_nearest_the_ray()
	_falls_back_to_the_world_when_nothing_is_close()
	_lock_survives_leaving_the_cone()
	_lock_breaks_on_destruction()
	_zooming_the_scope_in_keeps_the_lock()
	_closure_is_positive_closing()
	_cycle_walks_the_tracked_contacts()
	if _failed:
		return
	print("TARGET_TRACKER_TEST_PASS")
	quit()


## Nose along -Z. A contact behind is still tracked -- a scope that only saw
## forward would not be a scope.
func _tracks_all_aspect_within_range() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, 2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.tracked().size() != 2:
		_fail("a contact behind the aircraft is still a contact, got %d" % tracker.tracked().size())


func _drops_contacts_beyond_range() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -40000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.tracked().size() != 1:
		_fail("the default 10 km range must exclude a 40 km contact")


func _boxes_only_the_forward_cone() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, 2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	var boxed: Array = tracker.boxed()
	if boxed.size() != 1:
		_fail("only the contact in front earns a box, got %d" % boxed.size())
	if int(boxed[0]["handle"]) != 1:
		_fail("the boxed contact must be the one ahead")
	for c in boxed:
		if not tracker.tracked().has(c):
			_fail("boxed must be a subset of tracked")


func _caps_the_boxes() -> void:
	var tracker = TRACKER.new()
	var many := []
	for i in range(40):
		many.append(TRACKER.contact(i, TRACKER.Kind.AIR_DRONE, Vector3(0.0, 0.0, -100.0 - float(i))))
	tracker.update(many, Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.boxed().size() != TRACKER.MAX_TRACKED_BOXES:
		_fail("a city plus a squadron must not become noise, got %d boxes" % tracker.boxed().size())


func _orders_nearest_first() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -4000.0)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -1000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if int(tracker.tracked()[0]["handle"]) != 2:
		_fail("nearest must come first")


## Cycling the scope out must genuinely reveal contacts, not redraw the same
## ten kilometres of them at a smaller scale.
func _range_follows_the_scope() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -25000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.tracked().size() != 0:
		_fail("25 km is outside the default range")
	tracker.set_range(TRACKER.RADAR_RANGES_M[3])
	if tracker.tracked().size() != 1:
		_fail("40 km selected must reveal a 25 km contact")


func _locks_the_contact_nearest_the_ray() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(600.0, 0.0, -2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	var handle: int = tracker.lock_at(
		Vector3.ZERO, Vector3(0.0, 0.0, -1.0), null, TRACKER.Kind.GROUND_POINT, ""
	)
	if handle != 1:
		_fail("the ray points at contact 1, got %d" % handle)
	if int(tracker.locked()["handle"]) != 1:
		_fail("the locked contact must be readable back")


## Press the dirt and you get the dirt. One gesture, two outcomes.
func _falls_back_to_the_world_when_nothing_is_close() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(5000.0, 0.0, -2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	var handle: int = tracker.lock_at(
		Vector3.ZERO, Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, -900.0),
		TRACKER.Kind.BUILDING, "Q1"
	)
	if handle != TRACKER.FALLBACK_HANDLE:
		_fail("with no contact near the ray the world is the target, got %d" % handle)
	if String(tracker.locked()["name"]) != "Q1":
		_fail("the fallback keeps the name it was given")
	if not (tracker.locked_position() as Vector3).is_equal_approx(Vector3(0.0, 0.0, -900.0)):
		_fail("the fallback keeps the point it was given")


## A lock that dropped every time you manoeuvred would be worse than no lock.
func _lock_survives_leaving_the_cone() -> void:
	var tracker = TRACKER.new()
	var behind := TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0))
	tracker.update([behind], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	tracker.lock_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), null, TRACKER.Kind.GROUND_POINT, "")
	# Same contact, but the aircraft has turned its back on it.
	tracker.update([behind], Vector3.ZERO, Vector3.BACK, Vector3.ZERO)
	if tracker.locked_handle() != 1:
		_fail("turning away must not break the lock")
	if not tracker.boxed().is_empty():
		_fail("but it is no longer boxed on the glass")


func _lock_breaks_on_destruction() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	tracker.lock_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), null, TRACKER.Kind.GROUND_POINT, "")
	tracker.update([], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.locked_handle() != -1:
		_fail("a contact that stopped being reported is dead, and the lock goes with it")


## Zooming in to 5 km must not throw away a lock held at 8.
func _zooming_the_scope_in_keeps_the_lock() -> void:
	var tracker = TRACKER.new()
	var far := TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -8000.0))
	tracker.update([far], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	tracker.lock_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), null, TRACKER.Kind.GROUND_POINT, "")
	tracker.set_range(TRACKER.RADAR_RANGES_M[0])
	tracker.update([far], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.locked_handle() != 1:
		_fail("the lock breaks at the largest range, not the selected one")


func _closure_is_positive_closing() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		# Ahead, flying toward us.
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0), Vector3(0.0, 0.0, 200.0)),
		# Ahead, running away.
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2500.0), Vector3(0.0, 0.0, -200.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.closure_of(1) <= 0.0:
		_fail("a contact flying at us is closing, got %f" % tracker.closure_of(1))
	if tracker.closure_of(2) >= 0.0:
		_fail("a contact running away is opening, got %f" % tracker.closure_of(2))
	# Our own speed counts: chasing the runner turns it into a closure.
	tracker.update([
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2500.0), Vector3(0.0, 0.0, -200.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3(0.0, 0.0, -400.0))
	if tracker.closure_of(2) <= 0.0:
		_fail("running it down is a closure, got %f" % tracker.closure_of(2))


func _cycle_walks_the_tracked_contacts() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -1000.0)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.cycle_lock() != 1:
		_fail("the first cycle takes the nearest")
	if tracker.cycle_lock() != 2:
		_fail("the second cycle steps out")
	if tracker.cycle_lock() != 1:
		_fail("and it wraps")


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
