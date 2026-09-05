extends SceneTree
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

func _init() -> void:
	var tracker := TRACKER.new()
	var contacts := [
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0, 100, -3000)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(180, 100, -3000)),
		TRACKER.contact(3, TRACKER.Kind.AIR_JET, Vector3(2100, 100, -3000)),
		TRACKER.contact(4, TRACKER.Kind.AIR_JET, Vector3(0, 100, 1000)),
	]
	tracker.update(contacts, Vector3(0, 100, 0), Vector3.FORWARD, Vector3.ZERO)
	assert(tracker.cycle_view_lock([1,2,3,4], Vector3(0,100,0), Vector3.FORWARD) == 1)
	assert(tracker.tracking_view)
	for repeat in range(4):
		assert(tracker.cycle_view_lock([1,2,3,4], Vector3(0,100,0), Vector3.FORWARD) == (2 if repeat % 2 == 0 else 1), "repeat presses must remain in the original nearby squadron")
	assert(tracker.cycle_view_lock([3,4], Vector3(0,100,0), Vector3.FORWARD) == -1, "no jumping to another cluster when this one leaves view")
	assert(tracker.locked_handle() == 1)
	tracker.lock_at(Vector3(0,100,0), Vector3(180,0,-3000).normalized(), null, TRACKER.Kind.GROUND_POINT, "")
	assert(tracker.locked_handle() == 2)
	assert(not tracker.tracking_view, "a screen lock must not track the camera")
	tracker.cycle_view_lock([1,2], Vector3(0,100,0), Vector3.FORWARD)
	tracker.update([], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	assert(not tracker.tracking_view and tracker.locked().is_empty(), "destroying the target must release tracking")
	print("VIEW_LOCK_TEST_PASS")
	quit()
