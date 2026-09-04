extends SceneTree

## The wiring is the thing that goes wrong quietly, so this test asserts the
## contract rather than the drawing: contacts from three unrelated sources
## arrive as one list, the tracker turns them into one lock, and the scope's
## range and the tracker's range stay the same number.

const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const SCOPE := preload("res://scripts/ui/radar_scope.gd")

var _failed := false


func _init() -> void:
	_one_list_from_many_sources()
	_the_scope_and_the_tracker_agree_about_range()
	_a_press_that_hits_nothing_clears_the_lock()
	if _failed:
		return
	print("HELMET_WIRING_TEST_PASS")
	quit()


## Jets, drones and SAM sites are three systems that have never heard of each
## other; the tracker is where they stop being three.
func _one_list_from_many_sources() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(200000, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -3000.0)),
		TRACKER.contact(100000, TRACKER.Kind.AIR_DRONE, Vector3(100.0, 0.0, -2000.0)),
		TRACKER.contact(5, TRACKER.Kind.GROUND_LAUNCHER, Vector3(-200.0, 0.0, -1500.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.tracked().size() != 3:
		_fail("all three sources must reach the scope, got %d" % tracker.tracked().size())
	if int(tracker.tracked()[0]["kind"]) != TRACKER.Kind.GROUND_LAUNCHER:
		_fail("nearest first, whatever kind it is")


func _the_scope_and_the_tracker_agree_about_range() -> void:
	var scope = SCOPE.new()
	var tracker = TRACKER.new()
	tracker.set_range(scope.range_m())
	if not is_equal_approx(tracker.range_m(), scope.range_m()):
		_fail("the tracker must follow the scope, %f against %f" % [tracker.range_m(), scope.range_m()])
	tracker.set_range(scope.cycle_range())
	if not is_equal_approx(tracker.range_m(), scope.range_m()):
		_fail("and must keep following it after a cycle")
	scope.free()


func _a_press_that_hits_nothing_clears_the_lock() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	tracker.lock_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), null, TRACKER.Kind.GROUND_POINT, "")
	if tracker.locked_handle() != 1:
		_fail("locked first")
	# Press the sky: no contact near the ray, and the ground ray missed.
	tracker.lock_at(Vector3.ZERO, Vector3(0.0, 1.0, 0.0), null, TRACKER.Kind.GROUND_POINT, "")
	if tracker.locked_handle() != -1:
		_fail("pressing nothing clears the lock, got %d" % tracker.locked_handle())


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
