extends SceneTree

# Rate of fire must be identical at 30, 60 and 120 FPS (spec section 77).

const PROFILE := preload("res://scripts/weapons/ballistic_profile.gd")


func _initialize() -> void:
	var profile: Resource = PROFILE.new()
	var interval: float = profile.shot_interval()
	assert(is_equal_approx(interval, 60.0 / 625.0), "625 RPM must be 0.096 s between rounds")

	var duration := 3.0
	var counts := []
	for fps in [30.0, 60.0, 120.0]:
		counts.append(_simulate(profile, duration, 1.0 / fps))
	for count in counts:
		assert(absf(float(count) - float(counts[0])) <= 1.0, "frame rate changed the round count: %s" % [counts])
	var expected: int = int(duration / interval)
	assert(absf(float(counts[0]) - float(expected)) <= 1.0, "expected ~%d rounds, fired %d" % [expected, counts[0]])

	# A long hitch must not dump a whole burst in one frame.
	var burst: int = _simulate(profile, 1.0, 1.0)
	assert(burst <= profile.maximum_rounds_per_frame, "hitch produced %d rounds in one frame" % burst)

	print("CANNON_RATE_TEST_PASS")
	quit()


func _simulate(profile: Resource, duration: float, delta: float) -> int:
	# Mirrors cannon_weapon.gd's accumulator exactly.
	var interval: float = profile.shot_interval()
	var accumulator: float = interval
	var elapsed := 0.0
	var fired := 0
	while elapsed < duration - 0.000001:
		accumulator += delta
		var this_frame := 0
		while accumulator >= interval and this_frame < profile.maximum_rounds_per_frame:
			accumulator -= interval
			this_frame += 1
			fired += 1
		if this_frame >= profile.maximum_rounds_per_frame:
			accumulator = 0.0
		elapsed += delta
	return fired
