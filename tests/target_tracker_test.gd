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


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
