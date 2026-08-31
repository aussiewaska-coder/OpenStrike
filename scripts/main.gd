extends Node3D

const HELICOPTER_SCENE := preload("res://ah-64d_apache_longbow_usa.glb")
const ORBIT_LOCK := preload("res://scripts/camera/orbit_lock.gd")
const ZOOM_PROFILE := preload("res://scripts/camera/zoom_profile.gd")

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

@onready var terrain = $Terrain
@onready var streamed_terrain = $StreamedTerrain
@onready var helicopter_anchor: Node3D = $HelicopterAnchor
@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label = $UI/Margin/Panel/Content/Status
@onready var region_label: Label = $UI/Margin/Panel/Content/Region
@onready var demo_button: Button = $UI/Margin/Panel/Content/DemoButton
@onready var gamepad_diagnostic: Label = $UI/GamepadDiagnostic/Label
@onready var controller_overlay: ColorRect = $UI/ControllerOverlay
@onready var controller_title: Label = $UI/ControllerOverlay/Center/Content/Title
@onready var controller_detail: Label = $UI/ControllerOverlay/Center/Content/Detail

var _camera_travel_direction := Vector3(0.0, 0.0, -1.0)
var _camera_zoom := 1.0
var _camera_follow_enabled := false
var _camera_orbit_radians := 0.0
var _camera_orbit_velocity := 0.0
var _travel_camera_enabled := false
var _camera_current_height := camera_height
var _camera_current_distance := camera_trailing_distance
var _orbit_lock := ORBIT_LOCK.new()
var _zoom_profile := ZOOM_PROFILE.new()
var _look_target := Vector3.ZERO
var _active_terrain: Node


func _ready() -> void:
	LocationService.status_changed.connect(_on_location_status_changed)
	LocationService.region_selected.connect(_on_region_selected)
	LocationService.location_updated.connect(_on_location_updated)
	GamepadInput.connection_changed.connect(_on_gamepad_connection_changed)
	GamepadInput.controller_attention_changed.connect(_on_controller_attention_changed)
	GamepadInput.action_pressed.connect(_on_gamepad_action_pressed)
	_configure_zoom_profile()
	demo_button.pressed.connect(LocationService.cycle_region)
	demo_button.text = "SWITCH THEATRE"
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
	gamepad_diagnostic.text = GamepadInput.get_diagnostic_text()
	if _camera_follow_enabled:
		_update_follow_camera(delta)


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
		region_label.text = "REGION: NO PREPARED THEATRE NEARBY"
		demo_button.visible = true
		return
	if bool(region.get("streamed", false)):
		await _load_streamed_region(region)
	else:
		_load_packaged_region(region)


func _load_packaged_region(region: Dictionary) -> void:
	streamed_terrain.set_focus(null)
	streamed_terrain.visible = false
	terrain.visible = true
	var metadata_path: String = region.get("metadata", "")
	if not terrain.load_region(metadata_path):
		status_label.text = "The selected region is registered but its offline terrain asset is missing."
		return
	region_label.text = "REGION: %s\n%s" % [region.get("display_name", "Unknown"), region.get("subtitle", "")]
	status_label.text = "Offline terrain loaded. Live location is no longer required for this session."
	_active_terrain = terrain
	helicopter_anchor.set_terrain(terrain)
	helicopter_anchor.position = terrain.get_spawn_position(90.0)
	helicopter_anchor.rotation_degrees.y = terrain.get_spawn_yaw_degrees(-35.0)
	if helicopter_anchor.has_method("reset_altitude_smoothing"):
		helicopter_anchor.reset_altitude_smoothing()
	_camera_follow_enabled = true
	_snap_follow_camera()


## Streamed theatres reach the network, so the camera stays parked until the
## elevation grid and the first imagery have actually arrived.
func _load_streamed_region(region: Dictionary) -> void:
	terrain.visible = false
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


func _update_follow_camera(delta: float) -> void:
	var orbit_input := GamepadInput.get_camera_orbit_axis()
	if _travel_camera_enabled:
		_update_orbit_lock(delta, orbit_input)
	else:
		_release_orbit_lock()
		var target_velocity := orbit_input * deg_to_rad(camera_orbit_speed_degrees)
		var response_weight := 1.0 - exp(-camera_orbit_response * delta)
		_camera_orbit_velocity = lerpf(_camera_orbit_velocity, target_velocity, response_weight)
		_camera_orbit_radians = wrapf(_camera_orbit_radians + _camera_orbit_velocity * delta, -PI, PI)

	_camera_travel_direction = Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, _camera_orbit_radians)
	var target_height := travel_camera_height if _travel_camera_enabled else camera_height
	var target_distance := travel_camera_trailing_distance if _travel_camera_enabled else camera_trailing_distance
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


func _ground_height_at(point: Vector3) -> float:
	if _active_terrain != null and _active_terrain.has_method("sample_height_world"):
		return _active_terrain.sample_height_world(point.x, point.z)
	return 0.0


func _ground_point_under_helicopter() -> Vector3:
	var origin := helicopter_anchor.global_position
	return Vector3(origin.x, _ground_height_at(origin), origin.z)


func _snap_follow_camera() -> void:
	_release_orbit_lock()
	_camera_current_height = camera_height
	_camera_current_distance = camera_trailing_distance
	_camera_travel_direction = Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, _camera_orbit_radians)
	_apply_follow_camera(0.0, true)


func _apply_follow_camera(delta: float, snap: bool = false) -> void:
	var focus := helicopter_anchor.global_position
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
		var follow_response := travel_follow_response if _travel_camera_enabled else tactical_follow_response
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


func _on_gamepad_action_pressed(action: StringName) -> void:
	if action == GamepadInput.ACTION_ZOOM_IN:
		_camera_zoom = _zoom_profile.step(_camera_zoom, camera_zoom_step_ratio, true, camera_zoom_max)
	elif action == GamepadInput.ACTION_ZOOM_OUT:
		_camera_zoom = _zoom_profile.step(_camera_zoom, camera_zoom_step_ratio, false, camera_zoom_max)
	elif action == GamepadInput.ACTION_CAMERA_TRAVEL_TOGGLE:
		_travel_camera_enabled = not _travel_camera_enabled
		_release_orbit_lock()
		_camera_orbit_velocity = 0.0
		if _travel_camera_enabled:
			status_label.text = "TRAVEL VIEW: following behind helicopter heading"
		else:
			# Keep the travel view's current heading; only height and distance ease
			# back to tactical values. L2/R2 can orbit from here immediately.
			status_label.text = "TACTICAL VIEW: current camera heading retained"


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
