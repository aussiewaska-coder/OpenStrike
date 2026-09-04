class_name SkyState
extends RefCounted

## What the light should look like for a given sun elevation. One place
## holds every tuning number so dawn, day, dusk and night are a single curve
## rather than four presets that drift apart.
##
## The terrain is a photograph and is drawn unshaded, so the sun never lights
## it: night is made by tinting the imagery itself, which is `terrain_tint`.

## Civil twilight to full daylight, in degrees of sun elevation.
const TWILIGHT_BELOW := -6.0
const FULL_DAY_ABOVE := 12.0
## The sun turns from amber to white over this band.
const WARM_UNTIL := 25.0

const SUN_ENERGY_DAY := 0.9
const MOON_ENERGY := 0.08
const AMBIENT_DAY := 0.28
const AMBIENT_NIGHT := 0.10

const SUN_COLOR_NOON := Color(1.0, 0.98, 0.95)
const SUN_COLOR_LOW := Color(1.0, 0.58, 0.32)
const MOON_COLOR := Color(0.55, 0.65, 0.95)
const TINT_DAY := Color(1.0, 1.0, 1.0)
const TINT_LOW := Color(1.0, 0.86, 0.72)
const TINT_NIGHT := Color(0.17, 0.20, 0.30)
## Procedural sky rather than physical: the physical sky renders near black
## on the Compatibility renderer (godot#84441). Fog takes the horizon colour
## so distant ground and sky meet without a band.
const SKY_TOP_DAY := Color(0.19, 0.50, 0.82)
const SKY_TOP_LOW := Color(0.16, 0.24, 0.45)
const SKY_TOP_NIGHT := Color(0.02, 0.03, 0.07)
const SKY_HORIZON_DAY := Color(0.78, 0.88, 0.96)
const SKY_HORIZON_LOW := Color(0.95, 0.58, 0.32)
const SKY_HORIZON_NIGHT := Color(0.07, 0.09, 0.15)


## Everything the day cycle applies, keyed by name. `is_night` says whether
## the light should come from the moon (opposite the sun) instead.
static func for_elevation(elevation_deg: float) -> Dictionary:
	var daylight := smoothstep(TWILIGHT_BELOW, FULL_DAY_ABOVE, elevation_deg)
	var whiteness := smoothstep(0.0, WARM_UNTIL, elevation_deg)
	var is_night := elevation_deg < TWILIGHT_BELOW

	var warm_tint := TINT_LOW.lerp(TINT_DAY, whiteness)
	var warm_top := SKY_TOP_LOW.lerp(SKY_TOP_DAY, whiteness)
	var warm_horizon := SKY_HORIZON_LOW.lerp(SKY_HORIZON_DAY, whiteness)

	return {
		"is_night": is_night,
		"sun_energy": MOON_ENERGY if is_night else lerpf(MOON_ENERGY, SUN_ENERGY_DAY, daylight),
		"sun_color": MOON_COLOR if is_night else SUN_COLOR_LOW.lerp(SUN_COLOR_NOON, whiteness),
		"ambient_energy": lerpf(AMBIENT_NIGHT, AMBIENT_DAY, daylight),
		"terrain_tint": TINT_NIGHT.lerp(warm_tint, daylight),
		"sky_top_color": SKY_TOP_NIGHT.lerp(warm_top, daylight),
		"sky_horizon_color": SKY_HORIZON_NIGHT.lerp(warm_horizon, daylight),
	}
