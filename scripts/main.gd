extends Node3D

const HELICOPTER_SCENE := preload("res://ah-64d_apache_longbow_usa.glb")
const ORBIT_LOCK := preload("res://scripts/camera/orbit_lock.gd")
const ZOOM_PROFILE := preload("res://scripts/camera/zoom_profile.gd")
const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")
const GROUND_RAY := preload("res://scripts/terrain/ground_ray.gd")

@export_group("Follow Camera")
@export var camera_height := 150.0
@export var camera_trailing_distance := 110.0
@export var camera_zoom_step_ratio := 0.8
@export var camera_zoom_min := 0.17
@export var camera_zoom_max := 1.45
@export var camera_orbit_speed_degrees := 95.0
@export var camera_orbit_response := 9.0
@export var travel_camera_height := 112.0
@export var travel_camera_trailing_distance := 270.0
@export var camera_mode_response := 3.6
@export var travel_heading_response := 3.2
@export var tactical_follow_response := 12.0
@export var travel_follow_response := 5.0

@export_group("Attack Zoom")
@export var attack_zoom_start := 0.68
@export var attack_height_bias := 0.35
@export var attack_fov := 78.0
@export var camera_ground_clearance := 6.0

@export_group("Free Look")
## R1 held hands the right stick to the camera. The view holds wherever it is
## pointed until the button is released, then eases back to the flight view.
@export var free_look_yaw_degrees := 130.0
@export var free_look_pitch_degrees := 55.0
@export var free_look_speed := 2.4
@export var free_look_return_response := 6.0

@export_group("Cockpit View")
## Pilot station relative to the airframe: forward along the nose and up.
@export var cockpit_offset := Vector3(2.6, 1.1, 0.0)
@export var cockpit_fov := 78.0

@onready var streamed_terrain = $StreamedTerrain
@onready var helicopter_anchor: Node3D = $HelicopterAnchor
@onready var camera: Camera3D = $Camera3D
@onready var mission_panel: Control = $UI/Margin
@onready var status_label: Label = $UI/Margin/Panel/Content/Status
@onready var region_label: Label = $UI/Margin/Panel/Content/Region
@onready var demo_button: Button = $UI/Margin/Panel/Content/DemoButton
@onready var flight_mode_button: Button = $UI/Margin/Panel/Content/FlightModeButton
@onready var attack_reticle := $UI/AttackReticle
@onready var settings_panel := $UI/SettingsPanel
@onready var gamepad_diagnostic: Label = $UI/GamepadDiagnostic/Label
@onready var controller_overlay: ColorRect = $UI/ControllerOverlay
@onready var controller_title: Label = $UI/ControllerOverlay/Center/Content/Title
@onready var controller_detail: Label = $UI/ControllerOverlay/Center/Content/Detail

var _camera_travel_direction := Vector3(0.0, 0.0, -1.0)
var _camera_zoom := 1.0
var _camera_follow_enabled := false
var _camera_orbit_radians := 0.0
var _camera_orbit_velocity := 0.0
## Three perspectives, cycled with R3. Cockpit is the default: the rotor model
## makes attitude real, and the view that shows attitude honestly is the one
## from inside the aircraft.
enum View {COCKPIT, CHASE, ORBIT}

var _view: View = View.CHASE
var _camera_current_height := camera_height
var _camera_current_distance := camera_trailing_distance
var _orbit_lock := ORBIT_LOCK.new()
var _zoom_profile := ZOOM_PROFILE.new()
var _ballistics := BALLISTICS.new()
var _look_target := Vector3.ZERO
var _free_look := Vector2.ZERO
var _target_point := Vector3.ZERO
var _has_target_point := false
var _active_terrain: Node


func _ready() -> void:
	LocationService.status_changed.connect(_on_location_status_changed)
	LocationService.region_selected.connect(_on_region_selected)
	LocationService.location_updated.connect(_on_location_updated)
	GamepadInput.connection_changed.connect(_on_gamepad_connection_changed)
	GamepadInput.controller_attention_changed.connect(_on_controller_attention_changed)
	GamepadInput.action_pressed.connect(_on_gamepad_action_pressed)
	_configure_zoom_profile()
	_apply_view_chrome()
	Telemetry.add_source(_telemetry_sample)
	settings_panel.theatre_chosen.connect(_on_theatre_chosen)
	settings_panel.flight_mode_toggled.connect(_toggle_flight_mode)
	settings_panel.cache_cleared.connect(_on_cache_cleared)
	settings_panel.quality_cycled.connect(_on_quality_cycled)
	flight_mode_button.pressed.connect(_toggle_flight_mode)
	_refresh_flight_mode_button()
	demo_button.pressed.connect(_toggle_settings)
	demo_button.text = "SETTINGS"
	demo_button.visible = true
	_spawn_helicopter()
	if not LocationService.selected_region.is_empty():
		_on_region_selected(LocationService.selected_region)
	_on_gamepad_connection_changed(
		GamepadInput.is_controller_ready(),
		GamepadInput.active_device,
		GamepadInput.active_device_name
	)
	if GamepadInput.requires_controller_attention():
		_on_controller_attention_changed(
			true,
			"CONNECT CONTROLLER",
			"Connect or wake a Bluetooth gamepad. Play resumes automatically when Android reports it."
		)


func _process(delta: float) -> void:
	gamepad_diagnostic.text = "%s\n%s" % [GamepadInput.get_diagnostic_text(), _map_diagnostic_text()]
	if _camera_follow_enabled:
		_update_follow_camera(delta)
		_update_attack_reticle()
		_update_target_marker()


func _spawn_helicopter() -> void:
	var helicopter := HELICOPTER_SCENE.instantiate()
	helicopter.name = "HeroHelicopter"
	helicopter_anchor.add_child(helicopter)
	helicopter.scale = Vector3.ONE * 0.105
	# The source model faces local +X. Put the initial presentation angle on the
	# vehicle root so its visible nose and logical flight heading are identical.
	helicopter.rotation_degrees.y = 0.0
	helicopter_anchor.rotation_degrees.y = -35.0


func _on_location_status_changed(_state: String, message: String) -> void:
	status_label.text = message


func _on_location_updated(_latitude: float, _longitude: float, accuracy_m: float) -> void:
	status_label.text = "Location acquired (±%d m). Selecting the nearest offline theatre..." % int(accuracy_m)


func _on_region_selected(region: Dictionary) -> void:
	if region.is_empty():
		region_label.text = "REGION: NO THEATRE INSTALLED"
		return
	await _load_streamed_region(region)


## Every theatre streams. The map cache is checked before the network, so a
## theatre already flown loads from disk and needs no signal.
func _load_streamed_region(region: Dictionary) -> void:
	streamed_terrain.visible = true
	if not streamed_terrain.status_changed.is_connected(_on_streamed_status_changed):
		streamed_terrain.status_changed.connect(_on_streamed_status_changed)
	_camera_follow_enabled = false
	region_label.text = "REGION: %s\n%s" % [region.get("display_name", "Unknown"), region.get("subtitle", "")]
	var loaded: bool = await streamed_terrain.load_region(region)
	if not loaded:
		region_label.text = "REGION: %s // STREAM UNAVAILABLE" % region.get("display_name", "Unknown")
		return
	streamed_terrain.set_spawn_from_coordinate(
		float(region.get("spawn_latitude", region.get("center_latitude", 0.0))),
		float(region.get("spawn_longitude", region.get("center_longitude", 0.0))),
		float(region.get("spawn_yaw_degrees", -35.0))
	)
	_active_terrain = streamed_terrain
	helicopter_anchor.set_terrain(streamed_terrain)
	helicopter_anchor.position = streamed_terrain.get_spawn_position(120.0)
	helicopter_anchor.rotation_degrees.y = streamed_terrain.get_spawn_yaw_degrees(-35.0)
	if helicopter_anchor.has_method("reset_altitude_smoothing"):
		helicopter_anchor.reset_altitude_smoothing()
	streamed_terrain.set_focus(helicopter_anchor)
	_camera_follow_enabled = true
	_snap_follow_camera()


func _on_streamed_status_changed(message: String) -> void:
	status_label.text = message


## While R1 is held the right stick aims the camera and the view stays where it
## is put; letting go eases it back to the flight view.
func _update_free_look(delta: float) -> void:
	if GamepadInput.is_free_look_held():
		var look := GamepadInput.get_aim_vector()
		_free_look.x = clampf(_free_look.x - look.x * free_look_speed * delta, -1.0, 1.0)
		_free_look.y = clampf(_free_look.y - look.y * free_look_speed * delta, -1.0, 1.0)
		return
	_free_look = _free_look.lerp(Vector2.ZERO, 1.0 - exp(-free_look_return_response * delta))


func _free_look_basis() -> Basis:
	if _free_look.is_zero_approx():
		return Basis.IDENTITY
	return Basis(Vector3.UP, deg_to_rad(_free_look.x * free_look_yaw_degrees)) \
		* Basis(Vector3.RIGHT, deg_to_rad(_free_look.y * free_look_pitch_degrees))


func _update_follow_camera(delta: float) -> void:
	_update_free_look(delta)
	if _view == View.COCKPIT:
		_update_cockpit_camera()
		return
	# With a target picked the triggers fly the aircraft around it, so the
	# camera must not also claim them.
	var orbit_input := 0.0
	if not _aircraft_is_orbiting():
		orbit_input = GamepadInput.get_camera_orbit_axis()
	if _view == View.CHASE:
		_update_orbit_lock(delta, orbit_input)
	else:
		_release_orbit_lock()
		var target_velocity := orbit_input * deg_to_rad(camera_orbit_speed_degrees)
		var response_weight := 1.0 - exp(-camera_orbit_response * delta)
		_camera_orbit_velocity = lerpf(_camera_orbit_velocity, target_velocity, response_weight)
		_camera_orbit_radians = wrapf(_camera_orbit_radians + _camera_orbit_velocity * delta, -PI, PI)

	_camera_travel_direction = Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, _camera_orbit_radians)
	var target_height := travel_camera_height if _view == View.CHASE else camera_height
	var target_distance := travel_camera_trailing_distance if _view == View.CHASE else camera_trailing_distance
	var mode_weight := 1.0 - exp(-camera_mode_response * delta)
	_camera_current_height = lerpf(_camera_current_height, target_height, mode_weight)
	_camera_current_distance = lerpf(_camera_current_distance, target_distance, mode_weight)
	_apply_follow_camera(delta)


## In travel view L2/R2 sweep around a locked ground point instead of steering
## the trailing heading. The auto-ease toward the nose is suspended while a
## sweep is running, otherwise the two fight each other for the same heading.
func _update_orbit_lock(delta: float, orbit_input: float) -> void:
	if is_zero_approx(orbit_input):
		_release_orbit_lock()
		_ease_travel_heading(delta)
		_camera_orbit_velocity = 0.0
		return
	if not _orbit_lock.active:
		_orbit_lock.engage(camera.global_position, _ground_point_under_helicopter())
	_orbit_lock.advance(
		delta,
		orbit_input,
		deg_to_rad(camera_orbit_speed_degrees),
		camera_orbit_response
	)
	_camera_orbit_radians = _orbit_lock.angle
	_camera_orbit_velocity = 0.0


## Hands the sweep's final heading back to the trailing camera, so travel-follow
## resumes from where the camera is pointing rather than whipping around.
func _release_orbit_lock() -> void:
	if not _orbit_lock.active:
		return
	_camera_orbit_radians = _orbit_lock.angle
	_orbit_lock.release()


func _ease_travel_heading(delta: float) -> void:
	# The source helicopter points along local +X. Ease the camera's travel
	# heading toward that nose direction so it naturally settles behind turns.
	var helicopter_forward := helicopter_anchor.global_basis.x
	helicopter_forward.y = 0.0
	if helicopter_forward.is_zero_approx():
		return
	helicopter_forward = helicopter_forward.normalized()
	var target_heading := atan2(-helicopter_forward.x, -helicopter_forward.z)
	var heading_weight := 1.0 - exp(-travel_heading_response * delta)
	_camera_orbit_radians = lerp_angle(_camera_orbit_radians, target_heading, heading_weight)


func _configure_zoom_profile() -> void:
	_zoom_profile.zoom_min = camera_zoom_min
	_zoom_profile.attack_zoom_start = attack_zoom_start
	_zoom_profile.attack_height_bias = attack_height_bias
	_zoom_profile.base_fov = camera.fov
	_zoom_profile.attack_fov = attack_fov


func _ground_height_xz(x: float, z: float) -> float:
	if _active_terrain != null and _active_terrain.has_method("sample_height_world"):
		return _active_terrain.sample_height_world(x, z)
	return 0.0


func _ground_height_at(point: Vector3) -> float:
	return _ground_height_xz(point.x, point.z)


func _focus_position() -> Vector3:
	if helicopter_anchor.has_method("get_focus_position"):
		return helicopter_anchor.get_focus_position()
	return helicopter_anchor.global_position


func _ground_point_under_helicopter() -> Vector3:
	var origin := _focus_position()
	return Vector3(origin.x, _ground_height_at(origin), origin.z)


func _update_instruments() -> void:
	var focus := _focus_position()
	var speed_knots := 0.0
	var collective := 0.0
	if "velocity" in helicopter_anchor:
		var velocity: Vector3 = helicopter_anchor.velocity
		speed_knots = Vector2(velocity.x, velocity.z).length() / 0.5144
	if "collective" in helicopter_anchor:
		collective = float(helicopter_anchor.collective)
	var nose := helicopter_anchor.global_basis.x
	var heading := rad_to_deg(atan2(nose.x, -nose.z))
	attack_reticle.set_instruments(
		speed_knots,
		focus.y - _ground_height_at(focus),
		collective,
		heading + 360.0
	)


## Says plainly what the map layer is doing: how big a chunk is, how many are
## detailed, what the chunk under the aircraft is textured at, and whether that
## imagery came off the disk or the network.
## Feeds the loopback telemetry socket the map layer's state alongside the
## engine's own counters, so a shell on the device sees both at once.
func _telemetry_sample() -> Dictionary:
	var sample := {
		"theatre": String(LocationService.selected_region.get("display_name", "none")),
		"view": View.keys()[_view],
		"cache_hits": TileClient.cache_hits,
		"net_fetches": TileClient.network_fetches,
		"tile_failures": TileClient.failures,
	}
	if streamed_terrain.has_method("detail_report"):
		var report: Dictionary = streamed_terrain.detail_report(_focus_position())
		sample.merge({
			"chunk_m": report["chunk_metres"],
			"chunks": report["chunks"],
			"detailed": report["detailed"],
			"pending": report["pending"],
			"under_px": report["under_px"],
			"under_detailed": report["under_detailed"],
			"quality": streamed_terrain.quality_name() if streamed_terrain.has_method("quality_name") else "?",
		}, true)
	return sample


func _map_diagnostic_text() -> String:
	if not streamed_terrain.has_method("detail_report"):
		return "MAP: --"
	var report: Dictionary = streamed_terrain.detail_report(_focus_position())
	var chunk_metres := float(report["chunk_metres"])
	var under_px := int(report["under_px"])
	var resolution := "--"
	if under_px > 0 and chunk_metres > 0.0:
		var covered: float = chunk_metres if bool(report["under_detailed"]) else float(_metadata_world_size())
		resolution = "%.2f m/px" % (covered / float(under_px))
	return "MAP chunk %dm  detail %d/%d (+%d)\nUNDER %s %dpx %s\nTILES cache %d net %d fail %d" % [
		roundi(chunk_metres), int(report["detailed"]), int(report["chunks"]), int(report["pending"]),
		"DETAIL" if bool(report["under_detailed"]) else "overview", under_px, resolution,
		TileClient.cache_hits, TileClient.network_fetches, TileClient.failures,
	]


func _metadata_world_size() -> float:
	return float(LocationService.selected_region.get("world_size_m", 0.0))


func _aircraft_is_orbiting() -> bool:
	return helicopter_anchor.has_method("orbit_input") and not is_zero_approx(helicopter_anchor.orbit_input())


## A tap picks a point on the ground to orbit. There are no collision shapes
## under the streamed terrain, so the ray is marched against the height field.
func _unhandled_input(event: InputEvent) -> void:
	if not _camera_follow_enabled:
		return
	var screen := Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed:
		screen = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		screen = (event as InputEventMouseButton).position
	else:
		return
	var hit := GROUND_RAY.intersect(
		camera.project_ray_origin(screen),
		camera.project_ray_normal(screen),
		_ground_height_xz
	)
	if hit.is_empty():
		_has_target_point = false
		attack_reticle.clear_target()
		if helicopter_anchor.has_method("clear_orbit_target"):
			helicopter_anchor.clear_orbit_target()
		status_label.text = "TARGET CLEARED"
		return
	_target_point = hit["point"]
	_has_target_point = true
	if helicopter_anchor.has_method("set_orbit_target"):
		helicopter_anchor.set_orbit_target(_target_point)
	status_label.text = "TARGET SET %d m -- L2/R2 to orbit it" % roundi(_focus_position().distance_to(_target_point))


func _update_target_marker() -> void:
	if not _has_target_point:
		attack_reticle.clear_target()
		return
	if camera.is_position_behind(_target_point):
		attack_reticle.set_target(Vector2.ZERO, false, 0.0)
		return
	attack_reticle.set_target(
		camera.unproject_position(_target_point),
		true,
		_focus_position().distance_to(_target_point)
	)


## The gunsight only exists inside the attack close-up: its alpha is the inverse
## of the zoom blend, so it fades in exactly as the camera drops low.
func _update_attack_reticle() -> void:
	# The cockpit has no panel, so the sight and the instruments are always up.
	var alpha := 1.0 if _view == View.COCKPIT else 1.0 - _zoom_profile.blend(_camera_zoom)
	if _view == View.COCKPIT:
		_update_instruments()
	else:
		attack_reticle.hide_instruments()
	if alpha <= 0.001:
		attack_reticle.clear()
		return
	if not helicopter_anchor.has_method("get_muzzle_transform"):
		attack_reticle.set_solution(alpha, Vector2.ZERO, false, {})
		return
	var muzzle: Transform3D = helicopter_anchor.get_muzzle_transform()
	var solution := _ballistics.solve(muzzle.origin, muzzle.basis.x, _ground_height_xz)
	var pipper := Vector2.ZERO
	var has_pipper := false
	if not solution.is_empty():
		var impact: Vector3 = solution["point"]
		if not camera.is_position_behind(impact):
			pipper = camera.unproject_position(impact)
			has_pipper = true
	attack_reticle.set_solution(alpha, pipper, has_pipper, solution)


## The cockpit is rigid: it takes the airframe's transform outright, so pitch,
## roll and the rotor's drift are all felt directly rather than smoothed away by
## a follow camera.
func _update_cockpit_camera() -> void:
	# The pilot station is measured off the airframe mesh: the GLB renders about
	# 31 m long, so an offset written in metres sat inside the fuselage and the
	# view was black.
	var frame: Transform3D = helicopter_anchor.get_cockpit_transform() if helicopter_anchor.has_method("get_cockpit_transform") else helicopter_anchor.global_transform
	camera.global_position = frame.origin
	# The airframe faces local +X, so the camera looks down that axis rather
	# than its own -Z.
	camera.global_basis = Basis.looking_at(frame.basis.x, Vector3.UP) * _free_look_basis()
	camera.fov = cockpit_fov


func _snap_follow_camera() -> void:
	_release_orbit_lock()
	_camera_current_height = camera_height
	_camera_current_distance = camera_trailing_distance
	_camera_travel_direction = Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, _camera_orbit_radians)
	_apply_follow_camera(0.0, true)


func _apply_follow_camera(delta: float, snap: bool = false) -> void:
	var focus := _focus_position()
	var desired_position: Vector3
	var desired_look := focus
	if _orbit_lock.active:
		desired_position = _orbit_lock.camera_position()
		desired_look = _orbit_lock.pivot
	else:
		var distance := _camera_current_distance * _zoom_profile.distance_multiplier(_camera_zoom)
		var height := _camera_current_height * _zoom_profile.height_multiplier(_camera_zoom)
		desired_position = focus - _camera_travel_direction * distance + Vector3.UP * height
	# The attack zoom flies the camera low enough to bury it in rising ground.
	desired_position.y = maxf(
		desired_position.y,
		_ground_height_at(desired_position) + camera_ground_clearance
	)
	var target_fov := _zoom_profile.fov(_camera_zoom)
	if snap:
		camera.global_position = desired_position
		_look_target = desired_look
		camera.fov = target_fov
	else:
		var follow_response := travel_follow_response if _view == View.CHASE else tactical_follow_response
		var follow_weight := 1.0 - exp(-follow_response * delta)
		camera.global_position = camera.global_position.lerp(desired_position, follow_weight)
		# Ease the look target too: releasing a sweep with the aircraft off-frame
		# would otherwise swing the view across the theatre in a single frame.
		_look_target = _look_target.lerp(desired_look, follow_weight)
		# Zoom presses are discrete, so the field of view is eased rather than
		# stepped, or the forced perspective would snap on every press.
		camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-camera_mode_response * delta))
	if camera.global_position.distance_squared_to(_look_target) > 0.0001:
		camera.look_at(_look_target, Vector3.UP)
	if not _free_look.is_zero_approx():
		# Swing the camera around the aircraft rather than turning it on the
		# spot, so the airframe stays in frame while the view moves.
		var offset := camera.global_position - focus
		camera.global_position = focus + _free_look_basis() * offset
		if camera.global_position.distance_squared_to(_look_target) > 0.0001:
			camera.look_at(_look_target, Vector3.UP)


func _on_gamepad_action_pressed(action: StringName) -> void:
	if action == GamepadInput.ACTION_ZOOM_IN:
		_camera_zoom = _zoom_profile.step(_camera_zoom, camera_zoom_step_ratio, true, camera_zoom_max)
	elif action == GamepadInput.ACTION_ZOOM_OUT:
		_camera_zoom = _zoom_profile.step(_camera_zoom, camera_zoom_step_ratio, false, camera_zoom_max)
	elif action == GamepadInput.ACTION_CAMERA_TRAVEL_TOGGLE:
		_cycle_view()
	elif action == GamepadInput.ACTION_FLIGHT_MODE:
		_toggle_flight_mode()
	elif action == GamepadInput.ACTION_SETTINGS:
		_toggle_settings()
	elif action == GamepadInput.ACTION_THEATRE_CYCLE:
		LocationService.cycle_region()


## Arcade is pick-up-and-fly: the stick sets a speed and the aircraft holds its
## height. Realistic is the rotor model, where only disc tilt moves you.
func _toggle_flight_mode() -> void:
	if not helicopter_anchor.has_method("set_flight_mode"):
		return
	var arcade: int = helicopter_anchor.FlightMode.ARCADE
	var rotor: int = helicopter_anchor.FlightMode.ROTOR
	var next: int = rotor if int(helicopter_anchor.flight_mode) == arcade else arcade
	helicopter_anchor.set_flight_mode(next)
	_refresh_flight_mode_button()
	settings_panel.set_flight_mode_text(flight_mode_button.text)
	status_label.text = "CONTROLS: %s" % ("REALISTIC ROTOR" if next == rotor else "ARCADE")


func _toggle_settings() -> void:
	if settings_panel.toggle_panel():
		_refresh_settings()


func _refresh_settings() -> void:
	settings_panel.populate_theatres(
		LocationService.installed_regions(),
		String(LocationService.selected_region.get("id", ""))
	)
	settings_panel.set_flight_mode_text(flight_mode_button.text)
	if streamed_terrain.has_method("quality_name"):
		settings_panel.set_quality_text("GRAPHICS: %s" % streamed_terrain.quality_name())
	var report: Dictionary = TileClient.cache_report()
	settings_panel.set_cache_report(int(report["files"]), int(report["bytes"]))
	var focus := _focus_position()
	settings_panel.set_status("View %s. Position %d, %d. Height %d m above ground." % [
		View.keys()[_view], roundi(focus.x), roundi(focus.z), roundi(focus.y - _ground_height_at(focus))
	])


func _on_theatre_chosen(region_id: String) -> void:
	settings_panel.close_panel()
	if helicopter_anchor.has_method("clear_orbit_target"):
		helicopter_anchor.clear_orbit_target()
	_has_target_point = false
	LocationService.select_region_by_id(region_id)


## Cycles performance, balanced, quality. Fewer resident textures is the lever
## that matters on a phone; the detail directly under the aircraft is the last
## thing to go.
func _on_quality_cycled() -> void:
	if not streamed_terrain.has_method("set_quality"):
		return
	var next: int = (int(streamed_terrain.quality) + 1) % 3
	streamed_terrain.set_quality(next)
	status_label.text = "GRAPHICS: %s" % streamed_terrain.quality_name()
	_refresh_settings()


func _on_cache_cleared() -> void:
	var removed: int = TileClient.clear_cache()
	status_label.text = "MAP CACHE CLEARED: %d files removed" % removed
	_refresh_settings()


func _refresh_flight_mode_button() -> void:
	if not ("flight_mode" in helicopter_anchor):
		return
	var arcade: int = helicopter_anchor.FlightMode.ARCADE
	flight_mode_button.text = "CONTROLS: %s" % ("ARCADE" if int(helicopter_anchor.flight_mode) == arcade else "REALISTIC")


## Cockpit, chase, orbit. Cockpit shows the HUD alone; the external views keep
## the mission panel.
func _cycle_view() -> void:
	_release_orbit_lock()
	_camera_orbit_velocity = 0.0
	match _view:
		View.COCKPIT:
			_view = View.CHASE
			status_label.text = "CHASE VIEW: astern, following the nose"
		View.CHASE:
			_view = View.ORBIT
			status_label.text = "ORBIT VIEW: L2/R2 sweep a locked ground point"
		_:
			_view = View.COCKPIT
			status_label.text = "COCKPIT VIEW"
	_apply_view_chrome()
	if _view != View.COCKPIT:
		_snap_follow_camera()


## In the cockpit the screen is the HUD and nothing else.
func _apply_view_chrome() -> void:
	var external := _view != View.COCKPIT
	mission_panel.visible = external
	gamepad_diagnostic.get_parent().visible = external


func _on_gamepad_connection_changed(connected: bool, _device_id: int, device_name: String) -> void:
	if connected:
		gamepad_diagnostic.text = "GAMEPAD: %s\nREADY" % device_name
	else:
		gamepad_diagnostic.text = "GAMEPAD: NOT CONNECTED"


func _on_controller_attention_changed(required: bool, title: String, detail: String) -> void:
	controller_overlay.visible = required
	if required:
		controller_title.text = title
		controller_detail.text = detail
