extends SceneTree

## The sun's position is checked against facts a navigator would know, not
## against another implementation: the equinox sun rises due east, stands
## (90 - latitude) high at local noon, and at the solstices moves by the
## obliquity of the ecliptic.

const SOLAR := preload("res://scripts/world/solar_position.gd")

const GOLD_COAST_LAT := -28.0023
const GOLD_COAST_LON := 153.431

var _failed := false


func _init() -> void:
	_equinox_noon()
	_equinox_sunrise()
	_solstice_noons()
	_midnight_is_below_the_horizon()
	_direction_axes()
	if _failed:
		return
	print("SOLAR_POSITION_TEST_PASS")
	quit()


func _equinox_noon() -> void:
	# Solar noon on the Gold Coast, 2026-03-20: 12:00 mean solar time is
	# 01:46 UTC, and the equation of time puts the true sun about seven
	# minutes later.
	var noon := _unix("2026-03-20T01:53:00Z")
	var angles: Vector2 = SOLAR.sun_angles(GOLD_COAST_LAT, GOLD_COAST_LON, noon)
	_assert_within(angles.x, 90.0 - 28.0, 1.0, "equinox noon elevation")
	# Southern hemisphere: the noon sun is to the north.
	_assert_within(_bearing_error(angles.y, 0.0), 0.0, 6.0, "equinox noon azimuth is north")


func _equinox_sunrise() -> void:
	var sunrise := _unix("2026-03-19T19:53:00Z")
	var angles: Vector2 = SOLAR.sun_angles(GOLD_COAST_LAT, GOLD_COAST_LON, sunrise)
	_assert_within(angles.x, 0.0, 2.5, "equinox sunrise elevation")
	_assert_within(_bearing_error(angles.y, 90.0), 0.0, 3.0, "equinox sunrise is due east")


func _solstice_noons() -> void:
	# December: the sun is 23.44 degrees south of the equator, almost
	# overhead here. June: it is 23.44 north, and low.
	var december: Vector2 = SOLAR.sun_angles(GOLD_COAST_LAT, GOLD_COAST_LON, _unix("2026-12-21T01:49:00Z"))
	_assert_within(december.x, 90.0 - (28.0 - 23.44), 1.0, "december noon elevation")
	var june: Vector2 = SOLAR.sun_angles(GOLD_COAST_LAT, GOLD_COAST_LON, _unix("2026-06-21T01:48:00Z"))
	_assert_within(june.x, 90.0 - (28.0 + 23.44), 1.0, "june noon elevation")
	_assert_within(_bearing_error(june.y, 0.0), 0.0, 6.0, "june noon azimuth is north")


func _midnight_is_below_the_horizon() -> void:
	var midnight: Vector2 = SOLAR.sun_angles(GOLD_COAST_LAT, GOLD_COAST_LON, _unix("2026-03-20T13:53:00Z"))
	if midnight.x > -55.0:
		_fail("equinox midnight elevation should be near -62, got %f" % midnight.x)


func _direction_axes() -> void:
	var east: Vector3 = SOLAR.direction_to_sun(0.0, 90.0)
	_assert_vector(east, Vector3(1, 0, 0), "azimuth 90 is +X (east)")
	var north: Vector3 = SOLAR.direction_to_sun(0.0, 0.0)
	_assert_vector(north, Vector3(0, 0, -1), "azimuth 0 is -Z (north)")
	var zenith: Vector3 = SOLAR.direction_to_sun(90.0, 123.0)
	_assert_vector(zenith, Vector3(0, 1, 0), "elevation 90 is straight up")


func _unix(iso: String) -> float:
	return float(Time.get_unix_time_from_datetime_string(iso))


func _bearing_error(actual: float, expected: float) -> float:
	return absf(wrapf(actual - expected, -180.0, 180.0))


func _assert_within(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) > tolerance:
		_fail("%s: expected %f +/- %f, got %f" % [label, expected, tolerance, actual])


func _assert_vector(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) > 0.001:
		_fail("%s: expected %s, got %s" % [label, expected, actual])


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
