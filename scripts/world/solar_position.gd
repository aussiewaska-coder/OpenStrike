class_name SolarPosition
extends RefCounted

## Where the sun is, for a place and a moment. The low-precision algorithm
## from the Astronomical Almanac: within about a quarter of a degree, which
## is far finer than any light angle a player could notice.
##
## Angles come back in degrees: elevation above the horizon (negative at
## night) and azimuth clockwise from true north. World space follows the
## terrain: +X east, -Z north, +Y up.

const J2000_UNIX := 946728000.0  # 2000-01-01T12:00:00Z
const SECONDS_PER_DAY := 86400.0


## Elevation and azimuth of the sun, as Vector2(elevation_deg, azimuth_deg).
static func sun_angles(latitude_deg: float, longitude_deg: float, unix_seconds: float) -> Vector2:
	var days := (unix_seconds - J2000_UNIX) / SECONDS_PER_DAY

	var mean_longitude := fposmod(280.460 + 0.9856474 * days, 360.0)
	var mean_anomaly := deg_to_rad(fposmod(357.528 + 0.9856003 * days, 360.0))
	var ecliptic_longitude := deg_to_rad(
		mean_longitude + 1.915 * sin(mean_anomaly) + 0.020 * sin(2.0 * mean_anomaly)
	)
	var obliquity := deg_to_rad(23.439 - 0.0000004 * days)

	var right_ascension := atan2(cos(obliquity) * sin(ecliptic_longitude), cos(ecliptic_longitude))
	var declination := asin(sin(obliquity) * sin(ecliptic_longitude))

	var sidereal_hours := fposmod(18.697374558 + 24.06570982441908 * days, 24.0)
	var local_sidereal := deg_to_rad(sidereal_hours * 15.0 + longitude_deg)
	var hour_angle := local_sidereal - right_ascension

	var latitude := deg_to_rad(latitude_deg)
	var east := -cos(declination) * sin(hour_angle)
	var north := sin(declination) * cos(latitude) - cos(declination) * sin(latitude) * cos(hour_angle)
	var up := sin(declination) * sin(latitude) + cos(declination) * cos(latitude) * cos(hour_angle)

	return Vector2(rad_to_deg(asin(clampf(up, -1.0, 1.0))), fposmod(rad_to_deg(atan2(east, north)), 360.0))


## Unit vector from the ground towards the sun, in world space.
static func direction_to_sun(elevation_deg: float, azimuth_deg: float) -> Vector3:
	var elevation := deg_to_rad(elevation_deg)
	var azimuth := deg_to_rad(azimuth_deg)
	var flat := cos(elevation)
	return Vector3(flat * sin(azimuth), sin(elevation), -flat * cos(azimuth)).normalized()
