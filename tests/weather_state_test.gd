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
