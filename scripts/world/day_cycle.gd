extends Node

## Puts the sun where it really is over the selected theatre, and shapes the
## light to match. Real-clock mode follows the phone; fixed presets offer
## readable afternoon and morning light whenever the player wants it.

const SOLAR := preload("res://scripts/world/solar_position.gd")
const SKY := preload("res://scripts/world/sky_state.gd")

enum Mode {REAL, NOON, DUSK, NIGHT, SUNRISE}

const MODE_NAMES := {
	Mode.REAL: "REAL CLOCK",
	Mode.NOON: "NOON",
	Mode.DUSK: "AFTERNOON",
	Mode.NIGHT: "NIGHT",
	Mode.SUNRISE: "SUNRISE",
}
## Local mean solar hours. Move the old 17:36 dusk preset 45 minutes
## toward daylight; use the matching brighter morning hour for sunrise.
## Keep existing enum values so saved/telemetry mode IDs remain valid.
const MODE_HOURS := {
	Mode.NOON: 12.0,
	Mode.DUSK: 17.6 - 0.75,
	Mode.NIGHT: 23.0,
	Mode.SUNRISE: 6.4 + 0.75,
}
const REFRESH_SECONDS := 2.0
## Gold Coast, matching the location service's editor fallback.
const DEMO_LATITUDE := -28.0023
const DEMO_LONGITUDE := 153.431

@export var sun_path: NodePath
@export var environment_path: NodePath
## Weather scales these; the cycle re-applies them on every refresh.
var sun_multiplier := 1.0
var fog_multiplier := 1.0
var cloud_immersion := 0.0

var mode: Mode = Mode.DUSK
var elevation_deg := 0.0
var azimuth_deg := 0.0

var _sun: DirectionalLight3D
var _environment: Environment
var _base_fog_density := 0.0001
var _base_fog_sky_affect := 0.25
var _horizon := Color(0.78, 0.88, 0.96)
var _cloud_fog_color := Color(0.65, 0.69, 0.73)
## Looked up rather than named, so the node also runs headless where the
## autoload is not a global.
var _location: Node
var _accumulator := REFRESH_SECONDS
var applied_tint := Color.WHITE


func _ready() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	var world_environment := get_node_or_null(environment_path) as WorldEnvironment
	_environment = world_environment.environment if world_environment != null else null
	if _environment != null:
		_base_fog_density = _environment.fog_density
		_base_fog_sky_affect = _environment.fog_sky_affect
	_location = get_node_or_null("/root/LocationService")
	if _location != null:
		_location.region_selected.connect(func(_region: Dictionary): _accumulator = REFRESH_SECONDS)


func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < REFRESH_SECONDS:
		return
	_accumulator = 0.0
	refresh()


func cycle_mode() -> void:
	mode = ((mode as int) + 1) % MODE_NAMES.size() as Mode
	refresh()


func mode_name() -> String:
	return MODE_NAMES[mode]


func refresh() -> void:
	var region: Dictionary = _location.selected_region if _location != null else {}
	var latitude := float(region.get("center_latitude", DEMO_LATITUDE))
	var longitude := float(region.get("center_longitude", DEMO_LONGITUDE))
	var angles: Vector2 = SOLAR.sun_angles(latitude, longitude, _clock(longitude))
	elevation_deg = angles.x
	azimuth_deg = angles.y
	_apply(SKY.for_elevation(elevation_deg))


## Seconds since the Unix epoch, UTC. Fixed modes take today's date at the
## chosen local mean solar hour, so the season still shows.
func _clock(longitude: float) -> float:
	var now := Time.get_unix_time_from_system()
	if mode == Mode.REAL:
		return now
	var offset := longitude / 15.0 * 3600.0
	var local_midnight := floorf((now + offset) / 86400.0) * 86400.0 - offset
	return local_midnight + float(MODE_HOURS[mode]) * 3600.0


func _apply(state: Dictionary) -> void:
	if _sun != null:
		var towards_light: Vector3 = SOLAR.direction_to_sun(elevation_deg, azimuth_deg)
		if state["is_night"]:
			# The moon stands roughly opposite the sun; close enough for a
			# light that only has to come from somewhere above.
			towards_light = Vector3(-towards_light.x, absf(towards_light.y), -towards_light.z)
		_sun.look_at_from_position(Vector3.ZERO, -towards_light, _steady_up(towards_light))
		_sun.light_energy = float(state["sun_energy"]) * sun_multiplier
		_sun.light_color = state["sun_color"]
		var sun_color: Color = state["sun_color"]
		var energy: float = float(state["sun_energy"]) * sun_multiplier
		RenderingServer.global_shader_parameter_set("os_sun_dir", towards_light)
		RenderingServer.global_shader_parameter_set("os_sun_color", Vector3(sun_color.r, sun_color.g, sun_color.b) * energy)
	var horizon: Color = state["sky_horizon_color"]
	RenderingServer.global_shader_parameter_set("os_sky_horizon", Vector3(horizon.r, horizon.g, horizon.b))
	RenderingServer.global_shader_parameter_set("os_night", 1.0 - smoothstep(SKY.TWILIGHT_BELOW - 4.0, SKY.FULL_DAY_ABOVE, elevation_deg))
	if _environment != null:
		_environment.ambient_light_energy = float(state["ambient_energy"]) * lerpf(0.6, 1.0, sun_multiplier)
		_horizon = horizon
		_cloud_fog_color = Color(0.65, 0.69, 0.73).lerp(Color(0.07, 0.09, 0.14), smoothstep(0.4, 0.6, 1.0 - smoothstep(SKY.TWILIGHT_BELOW - 4.0, SKY.FULL_DAY_ABOVE, elevation_deg)))
		_apply_fog()
		var sky := _environment.sky.sky_material as ShaderMaterial if _environment.sky != null else null
		if sky != null:
			sky.set_shader_parameter("sky_top_color", state["sky_top_color"])
			sky.set_shader_parameter("sky_horizon_color", horizon)
	var tint: Color = state["terrain_tint"]
	applied_tint = tint
	RenderingServer.global_shader_parameter_set("os_terrain_tint", Vector3(tint.r, tint.g, tint.b))


func set_cloud_immersion(value: float) -> void:
	cloud_immersion = clampf(value, 0.0, 1.0)
	_apply_fog()


func _apply_fog() -> void:
	if _environment == null:
		return
	_environment.fog_light_color = _horizon.lerp(_cloud_fog_color, cloud_immersion)
	_environment.fog_density = _base_fog_density * fog_multiplier + cloud_immersion * 0.006
	_environment.fog_sky_affect = lerpf(_base_fog_sky_affect, 1.0, cloud_immersion)


## look_at needs an up vector that is not parallel to the view; straight
## overhead the sun would otherwise have no defined roll.
func _steady_up(towards_light: Vector3) -> Vector3:
	return Vector3.FORWARD if absf(towards_light.y) > 0.99 else Vector3.UP
