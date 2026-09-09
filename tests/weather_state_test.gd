extends SceneTree

## Weather is asserted by shape: presets order themselves from clear to
## storm, transitions move toward the target and never past it, and
## lightning keeps to its window.

const WEATHER := preload("res://scripts/world/weather_state.gd")

var _failed := false


func _init() -> void:
	_presets_order_themselves()
	_step_moves_toward_and_never_past()
	_step_from_empty_snaps_to_target()
	_lightning_window()
	_altitude_and_cloud_holes()
	_transition_is_frame_rate_independent()
	_flash_is_timed()
	if _failed:
		return
	print("WEATHER_STATE_TEST_PASS")
	quit()


func _presets_order_themselves() -> void:
	var clear: Dictionary = WEATHER.target(WEATHER.Preset.CLEAR)
	var overcast: Dictionary = WEATHER.target(WEATHER.Preset.OVERCAST)
	var rain: Dictionary = WEATHER.target(WEATHER.Preset.RAIN)
	var storm: Dictionary = WEATHER.target(WEATHER.Preset.STORM)
	if not (clear["cloud_coverage"] < overcast["cloud_coverage"] and overcast["cloud_coverage"] <= storm["cloud_coverage"]):
		_fail("cloud coverage must rise from clear to storm")
	if not (clear["sun_multiplier"] > overcast["sun_multiplier"] and overcast["sun_multiplier"] > storm["sun_multiplier"]):
		_fail("sun must dim from clear to storm")
	if rain["wet"] < 1.0 or clear["wet"] > 0.0:
		_fail("rain is wet and clear is dry")
	if rain["rain_rate"] <= 0.0 or clear["rain_rate"] > 0.0:
		_fail("only rain and storm rain")
	if clear["sun_multiplier"] != 1.0 or clear["fog_multiplier"] != 1.0:
		_fail("clear must leave the day cycle's own numbers alone")


func _step_moves_toward_and_never_past() -> void:
	var current: Dictionary = WEATHER.target(WEATHER.Preset.CLEAR)
	var target: Dictionary = WEATHER.target(WEATHER.Preset.STORM)
	var previous := float(current["cloud_coverage"])
	for i in range(600):
		current = WEATHER.step(current, target, 0.1)
		var coverage := float(current["cloud_coverage"])
		if coverage < previous - 1e-9:
			_fail("coverage moved away from the target at step %d" % i)
		if coverage > float(target["cloud_coverage"]) + 1e-6:
			_fail("coverage overshot the target at step %d" % i)
		previous = coverage
	# The approach is exponential, so "arrived" means within a few percent.
	if absf(float(current["cloud_coverage"]) - float(target["cloud_coverage"])) > 0.05:
		_fail("sixty seconds should be enough to arrive, got %f" % current["cloud_coverage"])


func _step_from_empty_snaps_to_target() -> void:
	var next: Dictionary = WEATHER.step({}, WEATHER.target(WEATHER.Preset.RAIN), 0.0)
	if next["wet"] != 1.0:
		_fail("with no current value the target is adopted, got %s" % next["wet"])


func _lightning_window() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(200):
		var delay: float = WEATHER.lightning_delay(rng)
		if delay < WEATHER.LIGHTNING_MIN_SECONDS or delay > WEATHER.LIGHTNING_MAX_SECONDS:
			_fail("lightning delay out of window: %f" % delay)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)


func _altitude_and_cloud_holes() -> void:
	if not is_equal_approx(WEATHER.rain_at_altitude(0.6, 500.0), 0.6):
		_fail("rain preset intensity must survive below the clouds")
	if WEATHER.rain_at_altitude(1.0, 1900.0) <= WEATHER.rain_at_altitude(1.0, 2100.0):
		_fail("rain must taper through the top of the cloud")
	if WEATHER.rain_at_altitude(1.0, WEATHER.CLOUD_ALTITUDE_M + WEATHER.CLOUD_HALF_DEPTH_M) != 0.0 or WEATHER.rain_at_altitude(1.0, 12000.0) != 0.0:
		_fail("there must be no rain above cloud tops")
	if WEATHER.cloud_band(500.0) != 0.0 or WEATHER.cloud_band(3000.0) != 0.0 or WEATHER.cloud_band(1800.0) != 1.0:
		_fail("cloud immersion must be confined to the cloud band")
	var image := Image.create(8, 8, false, Image.FORMAT_RF)
	image.fill(Color.BLACK)
	if WEATHER.cloud_density(image, Vector2(-3000, 800), Vector2.ZERO, 1.0) != 0.0:
		_fail("a hole in the shared cloud texture must stay clear even in storm")
	image.fill(Color.WHITE)
	if WEATHER.cloud_density(image, Vector2(-3000, 800), Vector2.ZERO, 1.0) != 1.0:
		_fail("a dense cloud must reduce visibility at the camera")
	for x in 8:
		for y in 8:
			image.set_pixel(x, y, Color(float(x + y) / 14.0, 0, 0))
	# Both noise octaves repeat after ten base tiles (the second uses 3.1x).
	var sample := WEATHER.cloud_density(image, Vector2(-3200, 1800), Vector2(400, 0), 0.85)
	var repeated := WEATHER.cloud_density(image, Vector2(56800, 61800), Vector2(400, 0), 0.85)
	if not is_equal_approx(sample, repeated):
		_fail("camera cloud sampling must wrap at negative coordinates like the shader")
	var drifted := WEATHER.cloud_density(image, Vector2(-2800, 1800), Vector2.ZERO, 0.85)
	if not is_equal_approx(sample, drifted):
		_fail("cloud visibility must drift with the visible cloud field")


func _transition_is_frame_rate_independent() -> void:
	var target := WEATHER.target(WEATHER.Preset.STORM)
	var slow := WEATHER.target(WEATHER.Preset.CLEAR)
	var fast := slow.duplicate()
	for frame in 15 * 20:
		slow = WEATHER.step(slow, target, 1.0 / 15.0)
	for frame in 120 * 20:
		fast = WEATHER.step(fast, target, 1.0 / 120.0)
	if absf(slow["rain_rate"] - fast["rain_rate"]) > 0.00001:
		_fail("weather transitions must take equal real time at 15 and 120 fps")


func _flash_is_timed() -> void:
	if WEATHER.lightning_strength(0.02) <= 0.0 or WEATHER.lightning_strength(0.15) <= 0.0:
		_fail("lightning must have two visible timed pulses")
	if WEATHER.lightning_strength(-1.0) != 0.0 or WEATHER.lightning_strength(0.35) != 0.0:
		_fail("lightning must be dark outside the flash interval")
