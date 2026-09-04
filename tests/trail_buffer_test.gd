extends SceneTree

## Breadcrumbs are laid by DISTANCE, never per frame. Laying them per frame
## makes trail density a function of framerate, so a hitching phone draws a
## gap-toothed trail and a fast one wastes vertices on a dense stub.

const TRAIL := preload("res://scripts/effects/trail_buffer.gd")


func _init() -> void:
	_spacing_is_by_distance()
	_width_grows_and_alpha_fades()
	_old_segments_retire()
	_finishes_after_the_last_breadcrumb_dies()
	print("TRAIL_BUFFER_TEST_PASS")
	quit()


func _spacing_is_by_distance() -> void:
	var trail = TRAIL.new()
	trail.push(Vector3.ZERO, 0.0)
	# A step far shorter than the spacing must not lay anything.
	var laid: bool = trail.push(Vector3(TRAIL.SEGMENT_METRES * 0.1, 0.0, 0.0), 0.01)
	if laid:
		_fail("a step shorter than the spacing must not lay a breadcrumb")
	# One beyond it must.
	if not trail.push(Vector3(TRAIL.SEGMENT_METRES * 1.5, 0.0, 0.0), 0.02):
		_fail("a step past the spacing must lay a breadcrumb")

	# Sixty small frames covering the same ground as six big ones must produce
	# the same trail. This is the framerate-independence claim, tested.
	var fine = TRAIL.new()
	for i in range(61):
		fine.push(Vector3(float(i) * 1.0, 0.0, 0.0), float(i) * 0.001)
	var coarse = TRAIL.new()
	for i in range(7):
		coarse.push(Vector3(float(i) * 10.0, 0.0, 0.0), float(i) * 0.01)
	if absi(fine.segment_count() - coarse.segment_count()) > 1:
		_fail("trail density must not depend on framerate, got %d against %d" % [
			fine.segment_count(), coarse.segment_count()
		])


func _width_grows_and_alpha_fades() -> void:
	if TRAIL.width_for_age(0.0) >= TRAIL.width_for_age(TRAIL.LIFETIME_SECONDS * 0.5):
		_fail("smoke must billow as it ages")
	if not is_equal_approx(TRAIL.width_for_age(0.0), TRAIL.BIRTH_WIDTH):
		_fail("a fresh breadcrumb must be born at the nozzle width")
	if TRAIL.width_for_age(TRAIL.LIFETIME_SECONDS * 4.0) > TRAIL.MAX_WIDTH + 0.001:
		_fail("billowing must stop at the maximum width")
	if TRAIL.alpha_for_age(0.0) <= TRAIL.alpha_for_age(TRAIL.LIFETIME_SECONDS * 0.9):
		_fail("smoke must thin as it ages")
	if TRAIL.alpha_for_age(TRAIL.LIFETIME_SECONDS + 0.1) > 0.0:
		_fail("smoke past its lifetime must be gone, not faint")


func _old_segments_retire() -> void:
	var trail = TRAIL.new()
	for i in range(40):
		trail.push(Vector3(float(i) * TRAIL.SEGMENT_METRES, 0.0, 0.0), float(i) * 0.05)
	var laid := trail.segment_count()
	if laid < 10:
		_fail("expected a long trail to test retirement, got %d" % laid)
	# Jump well past the lifetime; everything must age out.
	trail.advance_age(100.0)
	if trail.segment_count() != 0:
		_fail("every breadcrumb past its lifetime must retire, %d left" % trail.segment_count())


func _finishes_after_the_last_breadcrumb_dies() -> void:
	var trail = TRAIL.new()
	trail.push(Vector3.ZERO, 0.0)
	trail.push(Vector3(TRAIL.SEGMENT_METRES * 2.0, 0.0, 0.0), 0.1)
	trail.stop_emitting()
	if trail.is_finished(0.2):
		_fail("a dead rocket's smoke must linger, not vanish with it")
	if not trail.is_finished(TRAIL.LIFETIME_SECONDS + 1.0):
		_fail("the trail must eventually finish so its slot can be reused")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
