extends SceneTree

const AIRFRAME_MOTION := preload("res://scripts/helicopter/airframe_motion.gd")


func _init() -> void:
	# A hover wanders most; translating settles the aircraft.
	var hover := AIRFRAME_MOTION.hover_weight(0.0)
	var cruise := AIRFRAME_MOTION.hover_weight(1.0)
	if hover <= cruise:
		push_error("hover must drift more than cruise: %f vs %f" % [hover, cruise])
		quit(1)
	if not is_equal_approx(hover, 1.0):
		push_error("a stationary aircraft carries the full drift, got %f" % hover)
		quit(1)

	# The drift is bounded by its amplitude on every axis, so it can never throw
	# the airframe somewhere silly.
	for step in range(400):
		var time := float(step) * 0.05
		var phase := AIRFRAME_MOTION.phases(time, 0.35)
		var offset := AIRFRAME_MOTION.position_offset(phase, 0.6, 1.0)
		if absf(offset.x) > 0.31 or absf(offset.y) > 0.61 or absf(offset.z) > 0.31:
			push_error("drift left its amplitude at t = %f: %s" % [time, offset])
			quit(1)
		var sway := AIRFRAME_MOTION.sway_degrees(phase, 1.2, 1.0, 2.5, 1.0)
		if absf(sway.x) > 3.71 or absf(sway.y) > 2.23 or absf(sway.z) > 1.86:
			push_error("sway left its bounds at t = %f: %s" % [time, sway])
			quit(1)

	# Deterministic: the same moment always produces the same attitude.
	var first := AIRFRAME_MOTION.phases(12.5, 0.35)
	var second := AIRFRAME_MOTION.phases(12.5, 0.35)
	if not first.is_equal_approx(second):
		push_error("drift must be deterministic")
		quit(1)

	# The three axes must not share a period, or the drift reads as a loop.
	var quarter := AIRFRAME_MOTION.phases(1.0 / (0.35 * 4.0), 0.35)
	if is_equal_approx(quarter.x, quarter.y) or is_equal_approx(quarter.y, quarter.z):
		push_error("drift axes must not move together: %s" % quarter)
		quit(1)

	# No amplitude, no motion.
	var still := AIRFRAME_MOTION.position_offset(AIRFRAME_MOTION.phases(3.0, 0.35), 0.0, 1.0)
	if not still.is_zero_approx():
		push_error("zero amplitude must be perfectly still, got %s" % still)
		quit(1)
	print("AIRFRAME_MOTION_TEST_PASS")
	quit()
