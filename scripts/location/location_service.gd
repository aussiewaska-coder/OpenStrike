extends Node

signal status_changed(state: String, message: String)
signal location_updated(latitude: float, longitude: float, accuracy_m: float)
signal region_selected(region: Dictionary)

const PLUGIN_NAME := "OpenStrikeLocation"
const REGION_CATALOG_PATH := "res://data/regions/catalog.json"
const DEMO_LATITUDE := -28.0023
const DEMO_LONGITUDE := 153.4310

var selected_region: Dictionary = {}
var _regions: Array = []
var _plugin: Object
var _poll_accumulator := 0.0
var _updates_started := false
var _last_timestamp := 0


func _ready() -> void:
	_regions = _load_region_catalog()
	set_process(false)
	call_deferred("begin_location_selection")


func begin_location_selection() -> void:
	if OS.get_name() != "Android":
		_emit_status("demo", "Editor mode: using the prepared Surfers Paradise demo location.")
		use_demo_location()
		return
	if not Engine.has_singleton(PLUGIN_NAME):
		_emit_status("unavailable", "Android location plug-in is unavailable. You can still load a prepared region manually.")
		region_selected.emit({})
		return
	_plugin = Engine.get_singleton(PLUGIN_NAME)
	set_process(true)
	if _plugin.hasLocationPermission():
		_start_updates()
	else:
		_emit_status("permission", "Allow foreground location to select the nearest offline theatre.")
		_plugin.requestLocationPermission()


func use_demo_location() -> void:
	_select_region(DEMO_LATITUDE, DEMO_LONGITUDE, true)


func _process(delta: float) -> void:
	_poll_accumulator += delta
	if _poll_accumulator < 0.5 or _plugin == null:
		return
	_poll_accumulator = 0.0
	if not _updates_started:
		if _plugin.hasLocationPermission():
			_start_updates()
		elif _plugin.getStatus() == "permission_denied":
			_emit_status("denied", "Location was not granted. Choose the prepared demo region to continue.")
			region_selected.emit({})
		return
	var timestamp: int = _plugin.getLastTimestampMillis()
	if timestamp <= 0 or timestamp == _last_timestamp:
		return
	_last_timestamp = timestamp
	var latitude: float = _plugin.getLastLatitude()
	var longitude: float = _plugin.getLastLongitude()
	var accuracy_m: float = _plugin.getLastAccuracyMeters()
	location_updated.emit(latitude, longitude, accuracy_m)
	_select_region(latitude, longitude, false)
	_plugin.stopLocationUpdates()
	set_process(false)


func _start_updates() -> void:
	_updates_started = true
	_plugin.startLocationUpdates()
	_emit_status("locating", "Finding your location to select a prepared offline theatre...")


func _select_region(latitude: float, longitude: float, force_nearest: bool) -> void:
	var nearest: Dictionary = {}
	var nearest_distance: float = INF
	for candidate in _regions:
		var distance: float = _distance_km(
			latitude,
			longitude,
			float(candidate.get("center_latitude", 0.0)),
			float(candidate.get("center_longitude", 0.0))
		)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate.duplicate(true)
	if nearest.is_empty():
		_emit_status("unavailable", "No prepared terrain regions are installed.")
		region_selected.emit({})
		return
	var activation_radius: float = float(nearest.get("activation_radius_km", 50.0))
	if not force_nearest and nearest_distance > activation_radius:
		selected_region = {}
		_emit_status("outside", "No offline theatre is prepared near this location yet.")
		region_selected.emit({})
		return
	nearest["distance_km"] = nearest_distance
	selected_region = nearest
	region_selected.emit(selected_region)


## Cycles to the next installed theatre. Nearest-by-distance is right on
## launch, but the packaged Surfers box sits wholly inside the streamed
## corridor, so the two overlap and the player needs a way to pick.
func cycle_region() -> void:
	if _regions.is_empty():
		return
	var index := 0
	var current := String(selected_region.get("id", ""))
	for position in range(_regions.size()):
		if String(_regions[position].get("id", "")) == current:
			index = (position + 1) % _regions.size()
			break
	selected_region = _regions[index].duplicate(true)
	_emit_status("manual", "Theatre selected manually.")
	region_selected.emit(selected_region)


## The settings panel picks a theatre outright rather than by distance.
func select_region_by_id(region_id: String) -> void:
	for region in _regions:
		if String(region.get("id", "")) == region_id:
			selected_region = region.duplicate(true)
			_emit_status("manual", "Theatre selected.")
			region_selected.emit(selected_region)
			return


func installed_regions() -> Array:
	return _regions.duplicate(true)


func _load_region_catalog() -> Array:
	if not FileAccess.file_exists(REGION_CATALOG_PATH):
		push_error("Region catalog is missing: %s" % REGION_CATALOG_PATH)
		return []
	var file := FileAccess.open(REGION_CATALOG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("regions", [])) != TYPE_ARRAY:
		push_error("Region catalog is invalid: %s" % REGION_CATALOG_PATH)
		return []
	return parsed["regions"]


func _emit_status(state: String, message: String) -> void:
	status_changed.emit(state, message)


func _distance_km(lat_a: float, lon_a: float, lat_b: float, lon_b: float) -> float:
	const EARTH_RADIUS_KM := 6371.0088
	var lat_delta := deg_to_rad(lat_b - lat_a)
	var lon_delta := deg_to_rad(lon_b - lon_a)
	var a := sin(lat_delta * 0.5) ** 2
	a += cos(deg_to_rad(lat_a)) * cos(deg_to_rad(lat_b)) * sin(lon_delta * 0.5) ** 2
	return EARTH_RADIUS_KM * 2.0 * atan2(sqrt(a), sqrt(1.0 - a))


func _notification(what: int) -> void:
	if _plugin == null:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_plugin.stopLocationUpdates()
	elif what == NOTIFICATION_APPLICATION_RESUMED and selected_region.is_empty():
		_updates_started = false
		set_process(true)
