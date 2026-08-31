extends Node3D

const HELICOPTER_SCENE := preload("res://ah-64d_apache_longbow_usa.glb")

@export_group("Follow Camera")
@export var camera_height := 150.0
@export var camera_trailing_distance := 110.0
@export var camera_zoom_step := 22.0
@export var camera_zoom_min := 0.68
@export var camera_zoom_max := 1.45
@export var camera_orbit_speed_degrees := 95.0
@export var camera_orbit_response := 9.0
@export var travel_camera_height := 112.0
@export var travel_camera_trailing_distance := 270.0
@export var camera_mode_response := 3.6
@export var travel_heading_response := 3.2
@export var tactical_follow_response := 12.0
@export var travel_follow_response := 5.0

@onready var terrain = $Terrain
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


func _ready() -> void:
	LocationService.status_changed.connect(_on_location_status_changed)
	LocationService.region_selected.connect(_on_region_selected)
	LocationService.location_updated.connect(_on_location_updated)
	GamepadInput.connection_changed.connect(_on_gamepad_connection_changed)
	GamepadInput.controller_attention_changed.connect(_on_controller_attention_changed)
	GamepadInput.action_pressed.connect(_on_gamepad_action_pressed)
	demo_button.pressed.connect(LocationService.use_demo_location)
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
	var metadata_path: String = region.get("metadata", "")
	if not terrain.load_region(metadata_path):
		status_label.text = "The selected region is registered but its offline terrain asset is missing."
		return
	region_label.text = "REGION: %s\n%s" % [region.get("display_name", "Unknown"), region.get("subtitle", "")]
	status_label.text = "Offline terrain loaded. Live location is no longer required for this session."
	demo_button.visible = false
	helicopter_anchor.position = terrain.get_spawn_position(90.0)
	helicopter_anchor.rotation_degrees.y = terrain.get_spawn_yaw_degrees(-35.0)
	if helicopter_anchor.has_method("reset_altitude_smoothing"):
		helicopter_anchor.reset_altitude_smoothing()
	_camera_follow_enabled = true
	_snap_follow_camera()


func _update_follow_camera(delta: float) -> void:
	if _travel_camera_enabled:
		# The source helicopter points along local +X. Ease the camera's travel
		# heading toward that nose direction so it naturally settles behind turns.
		var helicopter_forward := helicopter_anchor.global_basis.x
		helicopter_forward.y = 0.0
		if not helicopter_forward.is_zero_approx():
			helicopter_forward = helicopter_forward.normalized()
			var target_heading := atan2(-helicopter_forward.x, -helicopter_forward.z)
			var heading_weight := 1.0 - exp(-travel_heading_response * delta)
			_camera_orbit_radians = lerp_angle(_camera_orbit_radians, target_heading, heading_weight)
		_camera_orbit_velocity = 0.0
	else:
		var orbit_input := GamepadInput.get_camera_orbit_axis()
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


func _snap_follow_camera() -> void:
	_camera_current_height = camera_height
	_camera_current_distance = camera_trailing_distance
	_camera_travel_direction = Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, _camera_orbit_radians)
	_apply_follow_camera(0.0, true)


func _apply_follow_camera(delta: float, snap: bool = false) -> void:
	var focus := helicopter_anchor.global_position
	var trailing_offset := -_camera_travel_direction * _camera_current_distance * _camera_zoom
	var height_offset := Vector3.UP * _camera_current_height * _camera_zoom
	var desired_position := focus + trailing_offset + height_offset
	if snap:
		camera.global_position = desired_position
	else:
		var follow_response := travel_follow_response if _travel_camera_enabled else tactical_follow_response
		var follow_weight := 1.0 - exp(-follow_response * delta)
		camera.global_position = camera.global_position.lerp(desired_position, follow_weight)
	# Always look at the aircraft so it remains centred while the camera eases.
	camera.look_at(focus, Vector3.UP)


func _on_gamepad_action_pressed(action: StringName) -> void:
	if action == GamepadInput.ACTION_ZOOM_IN:
		_camera_zoom = clampf(
			_camera_zoom - camera_zoom_step / camera_trailing_distance,
			camera_zoom_min,
			camera_zoom_max
		)
	elif action == GamepadInput.ACTION_ZOOM_OUT:
		_camera_zoom = clampf(
			_camera_zoom + camera_zoom_step / camera_trailing_distance,
			camera_zoom_min,
			camera_zoom_max
		)
	elif action == GamepadInput.ACTION_CAMERA_TRAVEL_TOGGLE:
		_travel_camera_enabled = not _travel_camera_enabled
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
