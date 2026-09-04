extends SceneTree

## The light curve is asserted by shape: brighter as the sun climbs, warm
## only when it is low, never black, and the moon takes over below twilight.

const SKY := preload("res://scripts/world/sky_state.gd")

var _failed := false


func _init() -> void:
	_brightness_rises_with_the_sun()
	_low_sun_is_warm_and_noon_is_white()
	_night_is_moonlit_not_black()
	_twilight_is_continuous()
	_sky_follows_the_sun()
	if _failed:
		return
	print("SKY_STATE_TEST_PASS")
	quit()


func _brightness_rises_with_the_sun() -> void:
	var previous_energy := -1.0
	var previous_tint := -1.0
	for elevation in range(-10, 60, 2):
		var state: Dictionary = SKY.for_elevation(float(elevation))
		var energy: float = state["sun_energy"]
		var tint: float = (state["terrain_tint"] as Color).get_luminance()
		if energy < previous_energy - 1e-6:
			_fail("sun energy fell at %d degrees" % elevation)
		if tint < previous_tint - 1e-6:
			_fail("terrain tint darkened at %d degrees" % elevation)
		previous_energy = energy
		previous_tint = tint


func _low_sun_is_warm_and_noon_is_white() -> void:
	var low: Color = SKY.for_elevation(3.0)["sun_color"]
	if low.b >= low.r - 0.2:
		_fail("a sun three degrees up should be amber, got %s" % low)
	var noon: Color = SKY.for_elevation(60.0)["sun_color"]
	if absf(noon.r - noon.b) > 0.06:
		_fail("a high sun should be near white, got %s" % noon)
	var day_tint: Color = SKY.for_elevation(60.0)["terrain_tint"]
	if not day_tint.is_equal_approx(Color.WHITE):
		_fail("full day must leave the imagery untinted, got %s" % day_tint)


func _night_is_moonlit_not_black() -> void:
	var night: Dictionary = SKY.for_elevation(-40.0)
	if not night["is_night"]:
		_fail("forty degrees below the horizon is night")
	if night["sun_energy"] <= 0.0 or night["ambient_energy"] <= 0.0:
		_fail("night still needs light to play by")
	var tint: Color = night["terrain_tint"]
	if tint.get_luminance() <= 0.02 or tint.get_luminance() >= 0.3:
		_fail("night imagery should be dim but readable, got luminance %f" % tint.get_luminance())
	if tint.b <= tint.r:
		_fail("night should lean blue, got %s" % tint)
	if SKY.for_elevation(30.0)["is_night"]:
		_fail("a sun thirty degrees up is not night")


func _sky_follows_the_sun() -> void:
	var day: Dictionary = SKY.for_elevation(60.0)
	var night: Dictionary = SKY.for_elevation(-40.0)
	if (day["sky_top_color"] as Color).get_luminance() <= (night["sky_top_color"] as Color).get_luminance() * 5.0:
		_fail("the day sky must be far brighter than the night sky")
	var dusk_horizon: Color = SKY.for_elevation(2.0)["sky_horizon_color"]
	if dusk_horizon.r <= dusk_horizon.b:
		_fail("the dusk horizon should glow warm, got %s" % dusk_horizon)
	if not (day["sky_horizon_color"] as Color).get_luminance() > (day["sky_top_color"] as Color).get_luminance():
		_fail("by day the horizon is paler than the zenith")


func _twilight_is_continuous() -> void:
	# Crossing the twilight line swaps sun for moon; the energies must meet
	# there so the swap is not a visible pop.
	var just_above: Dictionary = SKY.for_elevation(SKY.TWILIGHT_BELOW + 0.01)
	var just_below: Dictionary = SKY.for_elevation(SKY.TWILIGHT_BELOW - 0.01)
	if absf(float(just_above["sun_energy"]) - float(just_below["sun_energy"])) > 0.01:
		_fail("sun energy pops at twilight: %f vs %f" % [just_above["sun_energy"], just_below["sun_energy"]])


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
