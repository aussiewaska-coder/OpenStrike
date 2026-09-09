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
const CLOUD_ALTITUDE_M := 1800.0
const CLOUD_HALF_DEPTH_M := 800.0
const CLOUD_SCALE_M := 6000.0
const SOUND_SPEED_MPS := 343.0

const TARGETS := {
	Preset.CLEAR: {
		"cloud_coverage": 0.65, "sun_multiplier": 1.0, "fog_multiplier": 1.0,
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
	var fraction := 1.0 - exp(-maxf(delta, 0.0) / TRANSITION_SECONDS)
	var next := {}
	for key in target_values:
		var from := float(current.get(key, target_values[key]))
		next[key] = lerpf(from, float(target_values[key]), fraction)
	return next


static func lightning_delay(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(LIGHTNING_MIN_SECONDS, LIGHTNING_MAX_SECONDS)


static func name_of(preset: Preset) -> String:
	return PRESET_NAMES[preset]


static func cloud_band(altitude: float) -> float:
	var distance := absf(altitude - CLOUD_ALTITUDE_M)
	return 1.0 - smoothstep(CLOUD_HALF_DEPTH_M * 0.45, CLOUD_HALF_DEPTH_M, distance)


static func above_clouds(altitude: float) -> float:
	return smoothstep(CLOUD_ALTITUDE_M, CLOUD_ALTITUDE_M + CLOUD_HALF_DEPTH_M, altitude)


static func rain_at_altitude(rate: float, altitude: float) -> float:
	return clampf(rate, 0.0, 1.0) * (1.0 - above_clouds(altitude))


## Sample the same cached seamless texture and threshold as os_clouds.gdshaderinc.
## Cloud holes stay clear when the camera crosses the cloud altitude.
static func cloud_density(image: Image, world_xz: Vector2, wind: Vector2, coverage: float) -> float:
	if image == null or image.is_empty():
		return 0.0
	var uv := (world_xz + wind) / CLOUD_SCALE_M
	var noise := _sample_repeat(image, uv) * 0.7 + _sample_repeat(image, uv * 3.1 + Vector2(0.37, 0.11)) * 0.3
	var threshold := lerpf(0.78, 0.28, clampf(coverage, 0.0, 1.0))
	return smoothstep(threshold, threshold + 0.22, noise)


static func _sample_repeat(image: Image, uv: Vector2) -> float:
	var size := image.get_size()
	var pixel := Vector2(fposmod(uv.x, 1.0), fposmod(uv.y, 1.0)) * Vector2(size) - Vector2(0.5, 0.5)
	var x := floori(pixel.x)
	var y := floori(pixel.y)
	var fraction := pixel - Vector2(x, y)
	var a := image.get_pixel(posmod(x, size.x), posmod(y, size.y)).r
	var b := image.get_pixel(posmod(x + 1, size.x), posmod(y, size.y)).r
	var c := image.get_pixel(posmod(x, size.x), posmod(y + 1, size.y)).r
	var d := image.get_pixel(posmod(x + 1, size.x), posmod(y + 1, size.y)).r
	return lerpf(lerpf(a, b, fraction.x), lerpf(c, d, fraction.x), fraction.y)


## Seconds, not rendered frames: the flash has the same duration on a slow phone.
static func lightning_strength(elapsed: float) -> float:
	if elapsed < 0.0:
		return 0.0
	var first := (1.0 - smoothstep(0.025, 0.11, elapsed)) * 0.8
	var second := smoothstep(0.12, 0.14, elapsed) * (1.0 - smoothstep(0.16, 0.34, elapsed))
	return maxf(first, second)
