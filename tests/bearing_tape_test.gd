extends SceneTree

## The tape answers "which way do I turn" without looking down. A contact to
## the right is a tick to the right, proportionally, and one outside the tape
## clamps at the end with its side preserved.

const TAPE := preload("res://scripts/ui/bearing_tape.gd")


func _init() -> void:
	var half_deg: float = TAPE.TAPE_HALF_WIDTH_DEGREES
	var half_px := 300.0

	# Heading 0, nose along -Z. A contact at +X is 90 degrees right.
	var right: float = TAPE.relative_bearing(Vector3(1000.0, 0.0, 0.0), 0.0)
	if not is_equal_approx(right, PI * 0.5):
		_fail("a contact at +X from heading 0 is 90 right, got %f" % rad_to_deg(right))
	# Turn to face +X: it is now dead ahead.
	if absf(TAPE.relative_bearing(Vector3(1000.0, 0.0, 0.0), PI * 0.5)) > 0.001:
		_fail("facing the contact puts it at zero relative bearing")
	# Directly behind wraps to +/-180, not 540.
	var behind: float = TAPE.relative_bearing(Vector3(0.0, 0.0, 1000.0), 0.0)
	if absf(absf(behind) - PI) > 0.001:
		_fail("a contact behind is 180, got %f" % rad_to_deg(behind))

	# Thirty degrees right on a sixty-degree half tape is halfway to the end.
	var half: float = TAPE.tick_x(deg_to_rad(30.0), half_deg, half_px)
	if not is_equal_approx(half, half_px * 0.5):
		_fail("30 degrees must be half way along a 60 degree half tape, got %f" % half)
	if TAPE.tick_x(deg_to_rad(-30.0), half_deg, half_px) >= 0.0:
		_fail("left is negative")
	# Beyond the tape clamps, side preserved.
	if not is_equal_approx(TAPE.tick_x(deg_to_rad(150.0), half_deg, half_px), half_px):
		_fail("150 right clamps to the right end")
	if not is_equal_approx(TAPE.tick_x(deg_to_rad(-150.0), half_deg, half_px), -half_px):
		_fail("150 left clamps to the left end")
	if not TAPE.is_clamped(deg_to_rad(150.0), half_deg):
		_fail("150 must report as clamped")
	if TAPE.is_clamped(deg_to_rad(30.0), half_deg):
		_fail("30 must not report as clamped")

	print("BEARING_TAPE_TEST_PASS")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
