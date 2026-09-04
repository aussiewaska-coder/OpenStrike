extends SceneTree

## Drawing cannot be asserted headless, so what is asserted is the arithmetic
## the drawing leans on: a box shrinks with range but never vanishes, and a
## closure reads with its sign so a glance tells you whether you are gaining.

const HELMET := preload("res://scripts/ui/helmet_hud.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

var _failed := false


func _init() -> void:
	_boxes_shrink_with_range()
	_boxes_never_vanish()
	_closure_reads_with_its_sign()
	_every_kind_has_a_label()
	if _failed:
		return
	print("HELMET_HUD_TEST_PASS")
	quit()


func _boxes_shrink_with_range() -> void:
	var near: float = HELMET.box_half_extent_px(500.0)
	var far: float = HELMET.box_half_extent_px(8000.0)
	if near <= far:
		_fail("a nearer target draws a bigger box, got %f then %f" % [near, far])


func _boxes_never_vanish() -> void:
	var absurd: float = HELMET.box_half_extent_px(1.0e9)
	if absurd < HELMET.BOX_MIN_PX:
		_fail("a box floors instead of disappearing, got %f" % absurd)
	var touching: float = HELMET.box_half_extent_px(0.0)
	if touching > HELMET.BOX_MAX_PX:
		_fail("a box ceilings instead of filling the screen, got %f" % touching)


## Positive is closing. A pilot reads the sign before the number.
func _closure_reads_with_its_sign() -> void:
	if not HELMET.closure_text(120.0).begins_with("+"):
		_fail("closing must be signed positive, got %s" % HELMET.closure_text(120.0))
	if not HELMET.closure_text(-120.0).begins_with("-"):
		_fail("opening must be signed negative, got %s" % HELMET.closure_text(-120.0))


func _every_kind_has_a_label() -> void:
	var seen := {}
	for kind in TRACKER.Kind.values():
		var label: String = HELMET.kind_label(kind)
		if label.is_empty():
			_fail("kind %d has no label" % kind)
		seen[label] = true
	if seen.size() != TRACKER.Kind.size():
		_fail("every kind must be told apart by its label")


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
