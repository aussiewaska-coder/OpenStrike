class_name WeatherState
extends RefCounted

## Four weathers as targets, and the arithmetic that drifts the sky from one
## to the next. Every number that decides how a preset looks lives here.

enum Preset {CLEAR, OVERCAST, RAIN, STORM}

const PRESET_NAMES := {
	Preset.CLEAR: "CLEAR",
	Preset.OVERCAST: "OVERCAST",
	Preset.RAIN: "RAIN",
	Preset.STORM: "STORM",
}

## Seconds for a change of weather to mostly arrive.
const TRANSITION_SECONDS := 20.0
const LIGHTNING_MIN_SECONDS := 4.0
const LIGHTNING_MAX_SECONDS := 15.0

const TARGETS := {
	Preset.CLEAR: {
		"cloud_coverage": 0.3, "sun_multiplier": 1.0, "fog_multiplier": 1.0,
		"cloud_shadow": 0.35, "wet": 0.0, "rain_rate": 0.0, "wind_mps": 6.0,
	},
	Preset.OVERCAST: {
		"cloud_coverage": 0.85, "sun_multiplier": 0.55, "fog_multiplier": 1.6,
		"cloud_shadow": 0.15, "wet": 0.2, "rain_rate": 0.0, "wind_mps": 9.0,
	},
	Preset.RAIN: {
		"cloud_coverage": 0.95, "sun_multiplier": 0.4, "fog_multiplier": 2.4,
		"cloud_shadow": 0.1, "wet": 1.0, "rain_rate": 0.6, "wind_mps": 12.0,
	},
	Preset.STORM: {
		"cloud_coverage": 1.0, "sun_multiplier": 0.25, "fog_multiplier": 3.2,
		"cloud_shadow": 0.05, "wet": 1.0, "rain_rate": 1.0, "wind_mps": 20.0,
	},
}


static func target(preset: Preset) -> Dictionary:
	return TARGETS[preset].duplicate()


## Moves every value in `current` toward `target` by the fraction of the
## transition that `delta` seconds represents. Never overshoots.
static func step(current: Dictionary, target_values: Dictionary, delta: float) -> Dictionary:
	var fraction := clampf(delta / TRANSITION_SECONDS, 0.0, 1.0)
	var next := {}
	for key in target_values:
		var from := float(current.get(key, target_values[key]))
		next[key] = lerpf(from, float(target_values[key]), fraction)
	return next


static func lightning_delay(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(LIGHTNING_MIN_SECONDS, LIGHTNING_MAX_SECONDS)


static func name_of(preset: Preset) -> String:
	return PRESET_NAMES[preset]
