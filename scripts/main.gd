extends Node3D

const HELICOPTER_SCENE := preload("res://ah-64d_apache_longbow_usa.glb")
const JET_SCENE := preload("res://3dassets/f-22_raptor_-_fighter_jet_-_free.glb")
const JET_CAMERA := preload("res://scripts/camera/jet_camera.gd")
const ORBIT_LOCK := preload("res://scripts/camera/orbit_lock.gd")
const ZOOM_PROFILE := preload("res://scripts/camera/zoom_profile.gd")
const EXTERNAL_FREE_LOOK := preload("res://scripts/camera/external_free_look.gd")
const EXTERNAL_AIM_CURSOR := preload("res://scripts/camera/external_aim_cursor.gd")
const ARCADE_CAMERA_FEEDBACK := preload("res://scripts/camera/arcade_camera_feedback.gd")
const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")
const AIRFRAME_VISUALS := preload("res://scripts/helicopter/airframe_visuals.gd")
const GROUND_RAY := preload("res://scripts/terrain/ground_ray.gd")
const BUILDING_HIT_INDEX := preload("res://scripts/terrain/building_hit_index.gd")
const WORLD_SURFACE_RESOLVER := preload("res://scripts/world/world_surface_resolver.gd")
const WORLD_HIT_QUERY := preload("res://scripts/world/world_hit_query.gd")
const BUILDING_DAMAGE := preload("res://scripts/world/building_damage_system.gd")
const WORLD_HIT := preload("res://scripts/world/world_hit_result.gd")

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

@export_group("Arcade Presentation")
@export var speed_fov_degrees := 9.0
@export var speed_fov_reference_mps := 118.0
@export var cannon_recoil_trauma := 0.075
@export var destructive_hit_stop_seconds := 0.055
@export var destructive_hit_time_scale := 0.08

@export_group("Manual Aim")
## Cockpit R1 turns the view directly. External R1 moves a virtual sight first;
## the camera only receives overflow after that sight reaches its aim window.
@export var free_look_yaw_degrees := 130.0
@export var free_look_pitch_degrees := 55.0
@export var free_look_speed := 2.4
@export var free_look_return_response := 6.0

@export_group("Jet Camera")
## The Raptor is 19 m long and the helicopter's 110 m chase distance leaves it a
## dot on a phone screen. Framed close enough to actually see the aircraft.
@export var jet_camera_distance := 42.0
@export var jet_camera_height := 12.0
## The camera falls back as the aircraft accelerates. Field of view is left to
## the shared speed-driven offset, which now reads whichever aircraft is flying.
@export var jet_distance_gain := 26.0

@export_group("Cockpit View")
## Pilot station relative to the airframe: forward along the nose and up.
@export var cockpit_offset := Vector3(2.6, 1.1, 0.0)
@export var cockpit_fov := 78.0

@onready var streamed_terrain = $StreamedTerrain
@onready var projectile_manager: Node3D = $ProjectileManager
@onready var impact_fx: Node3D = $ImpactFX
@onready var cannon_fx: Node3D = $CannonFX
@onready var launcher_field: Node3D = $LauncherField
@onready var cannon_weapon: Node3D = $CannonWeapon
@onready var helicopter_anchor: Node3D = $HelicopterAnchor
@onready var jet_anchor: Node3D = $JetAnchor
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
var _jet_view: int = JET_CAMERA.Mode.FOLLOW
var _camera_current_height := camera_height
var _camera_current_distance := camera_trailing_distance
var _orbit_lock := ORBIT_LOCK.new()
var _zoom_profile := ZOOM_PROFILE.new()
var _arcade_camera_feedback := ARCADE_CAMERA_FEEDBACK.new()
var _ballistics := BALLISTICS.new()
var _look_target := Vector3.ZERO
var _free_look := Vector2.ZERO
var _external_aim := EXTERNAL_AIM_CURSOR.new()
var _camera_aim_basis := Basis.IDENTITY
var _hit_stop_serial := 0
var _target_point := Vector3.ZERO
var _has_target_point := false
var _flying_jet := false
var _camera_up := Vector3.UP
var _active_terrain: Node
var _building_hit_index: RefCounted
var _surface_resolver: RefCounted
var _hit_query: RefCounted
var _building_damage: RefCounted


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
	settings_panel.aircraft_switched.connect(_switch_aircraft)
	settings_panel.cache_cleared.connect(_on_cache_cleared)
	settings_panel.quality_cycled.connect(_on_quality_cycled)
	flight_mode_button.pressed.connect(_toggle_flight_mode)
	_refresh_flight_mode_button()
	demo_button.pressed.connect(_toggle_settings)
	demo_button.text = "SETTINGS"
	demo_button.visible = true
	_spawn_helicopter()
	_spawn_jet()
	_refresh_aircraft_button()
	jet_anchor.crashed.connect(_on_jet_crashed)
	jet_anchor.respawned.connect(_on_jet_respawned)
	jet_anchor.boundary_warning.connect(_on_jet_boundary_warning)
	# The gun mount appears when the helicopter controller finds its visual on
	# the next frame, so the weapon graph is assembled after that.
	call_deferred("_wire_cannon_systems")
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
		_camera_aim_basis = camera.global_basis
		_apply_arcade_camera_shake(delta)
		_update_attack_reticle()
		_update_target_marker()


## The one place that knows which aircraft is being flown. Everything that is
## vehicle-agnostic -- the camera, the gunsight, the instruments, the orbit
## target -- goes through here rather than naming an anchor.
func _vehicle() -> Node3D:
	return jet_anchor if _flying_jet else helicopter_anchor


func _spawn_jet() -> void:
	var jet := JET_SCENE.instantiate()
	jet.name = "HeroJet"
	jet_anchor.add_child(jet)
	# The controller measures the wingspan and scales the model itself, so
	# there is no magic number here the way there is for the Apache.
	_set_vehicle_active(jet_anchor, false)


func _set_vehicle_active(anchor: Node3D, active: bool) -> void:
	anchor.visible = active
	anchor.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


## Swap aircraft in place, so the player keeps the piece of coastline they were
## looking at. The jet needs height and speed to exist at all, so it is launched
## rather than simply moved.
func _switch_aircraft() -> void:
	var leaving := _vehicle()
	var handover := leaving.global_position
	var heading := 0.0
	var nose := leaving.global_basis.x
	nose.y = 0.0
	if not nose.is_zero_approx():
		nose = nose.normalized()
		heading = atan2(nose.x, -nose.z)

	_flying_jet = not _flying_jet
	_free_look = Vector2.ZERO
	_external_aim = EXTERNAL_AIM_CURSOR.new()
	_set_vehicle_active(leaving, false)
	var arriving := _vehicle()
	_set_vehicle_active(arriving, true)

	var ground := _ground_height_at(handover)
	if _flying_jet:
		jet_anchor.launch(
			Vector3(handover.x, maxf(handover.y, ground + 600.0), handover.z),
			heading
		)
		_jet_view = JET_CAMERA.Mode.FOLLOW
	else:
		helicopter_anchor.global_position = Vector3(
			handover.x,
			ground + helicopter_anchor.terrain_clearance,
			handover.z
		)
		helicopter_anchor.rotation.y = heading
		helicopter_anchor.velocity = Vector3.ZERO
		helicopter_anchor.get_global_transform_interpolated()
		helicopter_anchor.reset_physics_interpolation()
		if helicopter_anchor.has_method("reset_altitude_smoothing"):
			helicopter_anchor.reset_altitude_smoothing()

	_has_target_point = false
	attack_reticle.clear_target()
	_bind_cannon_to(arriving)
	if _active_terrain != null and _active_terrain.has_method("set_focus"):
		_active_terrain.set_focus(arriving)
	_camera_up = Vector3.UP
	_apply_view_chrome()
	_snap_follow_camera()
	_refresh_aircraft_button()
	_refresh_flight_mode_button()
	settings_panel.set_flight_mode_text(flight_mode_button.text)
	status_label.text = "F-22 -- R1 + RIGHT STICK THROTTLE, L2/R2 RUDDER, R3 LEVEL" if _flying_jet else "AH-64D APACHE"


func _bind_cannon_to(vehicle: Node3D) -> void:
	if cannon_weapon == null or not vehicle.has_method("get_gun_mount"):
		return
	cannon_weapon.gun_mount = vehicle.get_gun_mount()
	cannon_weapon.carrier = vehicle
	if cannon_fx != null:
		cannon_fx.gun_mount = cannon_weapon.gun_mount


func _refresh_aircraft_button() -> void:
	settings_panel.set_aircraft_text("AIRCRAFT: %s" % ("F-22 RAPTOR" if _flying_jet else "AH-64D APACHE"))


func _spawn_helicopter() -> void:
	var helicopter := HELICOPTER_SCENE.instantiate()
	helicopter.name = "HeroHelicopter"
	helicopter_anchor.add_child(helicopter)
	helicopter.scale = Vector3.ONE * 0.105
	AIRFRAME_VISUALS.sharpen_materials(helicopter)
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
	launcher_field.clear()
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
	# Both aircraft need the terrain: whichever is parked still has to know the
	# theatre's extent so it is not fenced into the wrong one when swapped to.
	jet_anchor.set_terrain(streamed_terrain)
	helicopter_anchor.set_terrain(streamed_terrain)
	helicopter_anchor.position = streamed_terrain.get_spawn_position(120.0)
	helicopter_anchor.rotation_degrees.y = streamed_terrain.get_spawn_yaw_degrees(-35.0)
	helicopter_anchor.get_global_transform_interpolated()
	helicopter_anchor.reset_physics_interpolation()
	if helicopter_anchor.has_method("reset_altitude_smoothing"):
		helicopter_anchor.reset_altitude_smoothing()
	# The jet is parked level over the same spawn, high enough to have somewhere
	# to fall, so swapping to it never starts inside a hill.
	jet_anchor.launch(
		streamed_terrain.get_spawn_position(900.0),
		deg_to_rad(streamed_terrain.get_spawn_yaw_degrees(-35.0))
	)
	streamed_terrain.set_focus(_vehicle())
	launcher_field.populate(String(region.get("id", "")), streamed_terrain)
	_camera_follow_enabled = true
	_snap_follow_camera()


func _on_streamed_status_changed(message: String) -> void:
	status_label.text = message


## Cockpit aim turns the view. External aim updates the target cursor and its
## delayed camera catch-up as separate pieces of state.
func _update_free_look(delta: float) -> void:
	if _flying_jet:
		_external_aim.update(Vector2.ZERO, false, delta)
		_free_look = JET_CAMERA.updated_look(
			_free_look,
			GamepadInput.get_jet_look_vector(),
			free_look_speed,
			free_look_return_response,
			delta
		)
		return
	var held := GamepadInput.is_free_look_held()
	var look := GamepadInput.get_aim_vector() if held else Vector2.ZERO
	if _view != View.COCKPIT:
		var viewport_size := camera.get_viewport().get_visible_rect().size
		_external_aim.set_projection(camera.fov, viewport_size.x / maxf(viewport_size.y, 1.0))
		_external_aim.update(look, held, delta)
		_free_look = _free_look.lerp(Vector2.ZERO, 1.0 - exp(-free_look_return_response * delta))
		return
	_external_aim.update(Vector2.ZERO, false, delta)
	if held:
		_free_look.x = clampf(_free_look.x - look.x * free_look_speed * delta, -1.0, 1.0)
		_free_look.y = clampf(_free_look.y - look.y * free_look_speed * delta, -1.0, 1.0)
		return
	_free_look = _free_look.lerp(Vector2.ZERO, 1.0 - exp(-free_look_return_response * delta))


func _free_look_basis() -> Basis:
	if _free_look.is_zero_approx():
		return Basis.IDENTITY
	return Basis(Vector3.UP, deg_to_rad(_free_look.x * free_look_yaw_degrees)) \
		* Basis(Vector3.RIGHT, deg_to_rad(_free_look.y * free_look_pitch_degrees))


func _external_camera_aim_basis() -> Basis:
	return _external_aim.camera_basis()


func _update_follow_camera(delta: float) -> void:
	_update_free_look(delta)
	if _flying_jet:
		_update_jet_camera(delta)
		return
	if _view == View.COCKPIT:
		_update_cockpit_camera()
		return
	# The helicopter may hand the triggers to target orbit or camera sweep. The
	# jet always owns them as rudder, so its camera receives no trigger input.
	var orbit_input := _camera_orbit_input()
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
	if _flying_jet:
		# Framed for a 19 m airframe rather than a helicopter's loiter, and
		# falling back as the aircraft accelerates away from the viewer.
		var speed: float = jet_anchor.airspeed() if jet_anchor.has_method("airspeed") else 0.0
		target_height = jet_camera_height
		target_distance = JET_CAMERA.trailing_distance(
			speed,
			jet_anchor.minimum_display_speed,
			jet_anchor.maximum_display_speed,
			jet_camera_distance,
			jet_distance_gain
		)
	var mode_weight := 1.0 - exp(-camera_mode_response * delta)
	_camera_current_height = lerpf(_camera_current_height, target_height, mode_weight)
	_camera_current_distance = lerpf(_camera_current_distance, target_distance, mode_weight)
	_apply_follow_camera(delta)


## All Raptor cameras are horizon-stable game views. Follow and track trail the
## actual flight path so sideslip does not whip the camera; isometric uses a
## fixed compass angle and moves over the ground with the aircraft.
func _update_jet_camera(delta: float, snap: bool = false) -> void:
	var focus := _focus_position()
	var direction := JET_CAMERA.travel_direction(jet_anchor.velocity, jet_anchor.global_basis.x)
	var distance := JET_CAMERA.trailing_distance(
		jet_anchor.airspeed(),
		jet_anchor.minimum_display_speed,
		jet_anchor.maximum_display_speed,
		jet_camera_distance,
		jet_distance_gain
	) * _zoom_profile.distance_multiplier(_camera_zoom)
	var height := jet_camera_height * _zoom_profile.height_multiplier(_camera_zoom)
	var desired_position := JET_CAMERA.desired_position(
		_jet_view,
		focus,
		direction,
		distance,
		height
	)
	if JET_CAMERA.allows_free_look(_jet_view) and not _free_look.is_zero_approx():
		desired_position = JET_CAMERA.orbited_position(
			focus,
			desired_position,
			_free_look_basis()
		)
	desired_position.y = maxf(
		desired_position.y,
		_ground_height_at(desired_position) + camera_ground_clearance
	)
	var target_fov := _zoom_profile.fov(_camera_zoom) + _speed_fov_offset()
	if snap:
		camera.global_position = desired_position
		_look_target = focus
		camera.fov = target_fov
	else:
		var response := 10.0 if _jet_view == JET_CAMERA.Mode.FOLLOW else 6.5
		var weight := 1.0 - exp(-response * delta)
		camera.global_position = camera.global_position.lerp(desired_position, weight)
		_look_target = _look_target.lerp(focus, weight)
		camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-camera_mode_response * delta))
	if camera.global_position.distance_squared_to(_look_target) > 0.0001:
		camera.look_at(_look_target, Vector3.UP)


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
	# Both source models point along local +X. Ease toward the active vehicle so
	# the parked helicopter cannot steer the F-22 chase camera.
	var vehicle_forward := _vehicle().global_basis.x
	vehicle_forward.y = 0.0
	if vehicle_forward.is_zero_approx():
		return
	vehicle_forward = vehicle_forward.normalized()
	var target_heading := atan2(-vehicle_forward.x, -vehicle_forward.z)
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
	var vehicle := _vehicle()
	if vehicle.has_method("get_interpolated_focus_position"):
		return vehicle.get_interpolated_focus_position()
	if vehicle.has_method("get_focus_position"):
		return vehicle.get_focus_position()
	return vehicle.global_position


func _ground_point_under_helicopter() -> Vector3:
	var origin := _focus_position()
	return Vector3(origin.x, _ground_height_at(origin), origin.z)


func _update_instruments() -> void:
	if _flying_jet:
		# The Raptor's GLB carries its own cockpit panel, instrument glass and
		# HUD combiner. Drawing a second set of readings over the top of real
		# modelled instruments is worse than drawing none.
		attack_reticle.hide_instruments()
		return
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
	var aim_input := GamepadInput.get_aim_vector()
	var raw_flight_input := GamepadInput.get_raw_flight_vector()
	var raw_aim_input := GamepadInput.get_raw_aim_vector()
	var raw_triggers := GamepadInput.get_raw_trigger_vector()
	var sample := {
		"theatre": String(LocationService.selected_region.get("display_name", "none")),
		"aircraft": "F-22" if _flying_jet else "AH-64D",
		"view": JET_CAMERA.Mode.keys()[_jet_view] if _flying_jet else View.keys()[_view],
		"free_look_held": GamepadInput.is_free_look_held(),
		"free_look_x": _free_look.x,
		"free_look_y": _free_look.y,
		"external_aim_cursor_x": _external_aim.cursor_offset.x,
		"external_aim_cursor_y": _external_aim.cursor_offset.y,
		"external_aim_camera_x": _external_aim.camera_offset.x,
		"external_aim_camera_y": _external_aim.camera_offset.y,
		"aim_input_x": aim_input.x,
		"aim_input_y": aim_input.y,
		"raw_left_x": raw_flight_input.x,
		"raw_left_y": raw_flight_input.y,
		"raw_right_x": raw_aim_input.x,
		"raw_right_y": raw_aim_input.y,
		"raw_l2": raw_triggers.x,
		"raw_r2": raw_triggers.y,
		"controller_name": GamepadInput.active_device_name,
		"controller_guid": GamepadInput.active_device_guid,
		"orbit_input": _camera_orbit_input(),
		"aircraft_yaw_degrees": _vehicle().global_rotation_degrees.y,
		"camera_yaw_degrees": camera.global_rotation_degrees.y,
		"speed_fov_offset_degrees": _speed_fov_offset(),
		"camera_shake_trauma": _arcade_camera_feedback.trauma,
		"launchers_remaining": launcher_field.launcher_count(),
		"compressed": TileClient.compression_available,
		"cache_hits": TileClient.cache_hits,
		"net_fetches": TileClient.network_fetches,
		"tile_failures": TileClient.failures,
	}
	if _flying_jet:
		var body_rates: Vector3 = jet_anchor.body_rates()
		sample.merge({
			"jet_airspeed_mps": jet_anchor.airspeed(),
			"jet_vertical_speed_mps": jet_anchor.velocity.y,
			"jet_altitude_agl_m": jet_anchor.altitude_above_ground(),
			"jet_bank_degrees": rad_to_deg(jet_anchor.bank),
			"jet_pitch_degrees": rad_to_deg(asin(clampf(jet_anchor.global_basis.x.y, -1.0, 1.0))),
			"jet_alpha_degrees": rad_to_deg(jet_anchor.alpha),
			"jet_beta_degrees": rad_to_deg(jet_anchor.beta),
			"jet_load_factor": jet_anchor.load_factor,
			"jet_throttle_percent": jet_anchor.throttle_percent(),
			"jet_afterburner": jet_anchor.afterburner_fraction(),
			"jet_roll_input": jet_anchor.roll_input,
			"jet_pitch_input": jet_anchor.pitch_input,
			"jet_rudder_input": jet_anchor.rudder_input,
			"jet_throttle_input": jet_anchor.throttle_input,
			"jet_wings_level_requested": jet_anchor.wings_level_requested(),
			"jet_roll_rate_degrees_s": rad_to_deg(body_rates.x),
			"jet_pitch_rate_degrees_s": rad_to_deg(body_rates.y),
			"jet_yaw_rate_degrees_s": rad_to_deg(body_rates.z),
		}, true)
	if cannon_weapon != null and cannon_weapon.aim != null:
		sample.merge({
			"gun_yaw_degrees": cannon_weapon.aim.yaw_degrees,
			"gun_pitch_degrees": cannon_weapon.aim.pitch_degrees,
			"gun_aim_source": cannon_weapon.aim.AimSource.keys()[cannon_weapon.aim.aim_source],
		}, true)
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
	var vehicle := _vehicle()
	return vehicle.has_method("orbit_input") and not is_zero_approx(vehicle.orbit_input())


func _camera_orbit_input() -> float:
	return JET_CAMERA.routed_orbit_input(
		GamepadInput.get_camera_orbit_axis(),
		_flying_jet,
		_aircraft_is_orbiting()
	)


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
		if _vehicle().has_method("clear_orbit_target"):
			_vehicle().clear_orbit_target()
		status_label.text = "TARGET CLEARED"
		return
	_target_point = hit["point"]
	_has_target_point = true
	if _vehicle().has_method("set_orbit_target"):
		_vehicle().set_orbit_target(_target_point)
	var range_m := roundi(_focus_position().distance_to(_target_point))
	status_label.text = (
		"TARGET MARKED %d m" % range_m
		if _flying_jet
		else "TARGET SET %d m -- L2/R2 to orbit it" % range_m
	)


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
	# Held R1 is also always a weapon view: the movable sight marks the manual
	# ray while the pipper shows where the traversing barrel will land.
	attack_reticle.set_jet_throttle(
		_flying_jet,
		jet_anchor.throttle_percent() if _flying_jet else 0.0,
		jet_anchor.afterburner_fraction() if _flying_jet else 0.0
	)
	var cockpit_view := not _flying_jet and _view == View.COCKPIT
	var manual_aim := not _flying_jet and GamepadInput.is_free_look_held()
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var manual_position := viewport_size * 0.5
	if manual_aim and _view != View.COCKPIT:
		manual_position = _external_aim.screen_position(viewport_size)
	attack_reticle.set_manual_aim(manual_aim, manual_position)
	var alpha := 1.0 if cockpit_view or manual_aim else 1.0 - _zoom_profile.blend(_camera_zoom)
	if cockpit_view:
		_update_instruments()
	else:
		attack_reticle.hide_instruments()
	if alpha <= 0.001:
		attack_reticle.clear()
		return
	var vehicle := _vehicle()
	if not vehicle.has_method("get_muzzle_transform"):
		attack_reticle.set_solution(alpha, Vector2.ZERO, false, {})
		return
	var muzzle: Transform3D = vehicle.get_muzzle_transform()
	var carrier: Vector3 = vehicle.velocity if "velocity" in vehicle else Vector3.ZERO
	var solution := _ballistics.solve(
		muzzle.origin,
		muzzle.basis.x,
		_ground_height_xz,
		carrier,
		_hit_query.query_segment if _hit_query != null else Callable()
	)
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
	var vehicle := _vehicle()
	var frame: Transform3D = vehicle.get_cockpit_transform() if vehicle.has_method("get_cockpit_transform") else vehicle.global_transform
	camera.global_position = frame.origin
	# The airframe faces local +X, so the camera looks down that axis rather
	# than its own -Z.
	camera.global_basis = Basis.looking_at(frame.basis.x, Vector3.UP) * _free_look_basis()
	camera.fov = cockpit_fov + _speed_fov_offset() * 0.55


func _snap_follow_camera() -> void:
	_release_orbit_lock()
	if _flying_jet:
		_update_jet_camera(0.0, true)
		return
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
		if _flying_jet and not _free_look.is_zero_approx():
			desired_position = JET_CAMERA.orbited_position(focus, desired_position, _free_look_basis())
	# The attack zoom flies the camera low enough to bury it in rising ground.
	desired_position.y = maxf(
		desired_position.y,
		_ground_height_at(desired_position) + camera_ground_clearance
	)
	if not _flying_jet and not _external_aim.camera_offset.is_zero_approx():
		# External R1 is manual aim: rotate the view ray, not the camera boom.
		# Recompute from the authored target every frame so a held angle is stable.
		desired_look = EXTERNAL_FREE_LOOK.look_target(
			desired_position,
			desired_look,
			_external_camera_aim_basis()
		)
	var target_fov := _zoom_profile.fov(_camera_zoom) + _speed_fov_offset()
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
		camera.look_at(_look_target, _camera_horizon(delta, snap))


## Helicopter follow cameras retain a level horizon. F-22 views use their own
## dedicated, horizon-stable update path above.
func _camera_horizon(_delta: float, _snap: bool) -> Vector3:
	_camera_up = Vector3.UP
	return Vector3.UP


## Whichever aircraft is being flown, so the speed-driven field of view works
## for the jet without a second mechanism competing with this one.
func _horizontal_speed() -> float:
	var vehicle := _vehicle()
	if vehicle != null and "velocity" in vehicle:
		var velocity: Vector3 = vehicle.velocity
		return Vector2(velocity.x, velocity.z).length()
	return 0.0


func _speed_fov_offset() -> float:
	return ARCADE_CAMERA_FEEDBACK.speed_fov_offset(
		_horizontal_speed(),
		speed_fov_reference_mps,
		speed_fov_degrees
	)


func _apply_arcade_camera_shake(delta: float) -> void:
	var rotation_degrees: Vector3 = _arcade_camera_feedback.update(delta)
	if rotation_degrees.is_zero_approx():
		return
	camera.global_basis = camera.global_basis * Basis.from_euler(Vector3(
		deg_to_rad(rotation_degrees.x),
		deg_to_rad(rotation_degrees.y),
		deg_to_rad(rotation_degrees.z)
	))


func _on_gamepad_action_pressed(action: StringName) -> void:
	if action == GamepadInput.ACTION_ZOOM_IN:
		_camera_zoom = _zoom_profile.step(_camera_zoom, camera_zoom_step_ratio, true, camera_zoom_max)
	elif action == GamepadInput.ACTION_ZOOM_OUT:
		_camera_zoom = _zoom_profile.step(_camera_zoom, camera_zoom_step_ratio, false, camera_zoom_max)
	elif action == GamepadInput.ACTION_CAMERA_TRAVEL_TOGGLE:
		if _flying_jet:
			var accepted: bool = jet_anchor.request_wings_level()
			status_label.text = "WINGS LEVEL" if accepted else "WINGS LEVEL UNAVAILABLE"
		else:
			_cycle_view()
	elif action == GamepadInput.ACTION_TARGET_PREVIOUS and _flying_jet:
		_cycle_jet_view(-1)
	elif action == GamepadInput.ACTION_TARGET_NEXT and _flying_jet:
		_cycle_jet_view(1)
	elif action == GamepadInput.ACTION_SWITCH_AIRCRAFT:
		_switch_aircraft()
	elif action == GamepadInput.ACTION_FLIGHT_MODE:
		_toggle_flight_mode()
	elif action == GamepadInput.ACTION_SETTINGS:
		_toggle_settings()
	elif action == GamepadInput.ACTION_THEATRE_CYCLE:
		LocationService.cycle_region()


## Arcade is pick-up-and-fly: the stick sets a speed and the aircraft holds its
## height. Realistic is the rotor model, where only disc tilt moves you.
func _toggle_flight_mode() -> void:
	if _flying_jet:
		status_label.text = "THE RAPTOR IS FLY-BY-WIRE ONLY -- THE ASSIST IS THE AIRCRAFT"
		return
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
	if _flying_jet:
		flight_mode_button.text = "CONTROLS: FLY-BY-WIRE"
		return
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
			status_label.text = "ORBIT VIEW: RIGHT STICK LOOK" if _flying_jet else "ORBIT VIEW: L2/R2 SWEEP A LOCKED GROUND POINT"
		_:
			_view = View.COCKPIT
			status_label.text = "COCKPIT VIEW"
	_apply_view_chrome()
	if _view != View.COCKPIT:
		_snap_follow_camera()


func _cycle_jet_view(direction: int) -> void:
	var count := JET_CAMERA.Mode.size()
	_jet_view = posmod(_jet_view + direction, count)
	_free_look = Vector2.ZERO
	_snap_follow_camera()
	match _jet_view:
		JET_CAMERA.Mode.FOLLOW:
			status_label.text = "FOLLOW VIEW"
		JET_CAMERA.Mode.TRACK:
			status_label.text = "TRACK VIEW"
		_:
			status_label.text = "ISOMETRIC GROUND-LOCK VIEW"


## In the cockpit the screen is the HUD and nothing else.
func _apply_view_chrome() -> void:
	var external := _flying_jet or _view != View.COCKPIT
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


func _on_jet_crashed(_point: Vector3) -> void:
	status_label.text = "IMPACT -- RECOVERING"


func _on_jet_respawned() -> void:
	status_label.text = "AIRBORNE -- R1 + RIGHT STICK THROTTLE, L2/R2 RUDDER"
	_snap_follow_camera()


## The theatre edge warns rather than walling: a hard clamp at 260 m/s stops the
## aircraft dead and reads as a bug.
func _on_jet_boundary_warning(urgency: float) -> void:
	if urgency <= 0.0:
		return
	status_label.text = "LEAVING THE THEATRE -- TURNING BACK"


func _wire_cannon_systems() -> void:
	_surface_resolver = WORLD_SURFACE_RESOLVER.new()
	_surface_resolver.configure(_ground_height_xz, 0.0)
	_building_hit_index = BUILDING_HIT_INDEX.new()
	_hit_query = WORLD_HIT_QUERY.new()
	_hit_query.configure(_ground_height_xz, _building_hit_index, _surface_resolver, 0.0)
	_hit_query.entity_index = launcher_field
	_building_damage = BUILDING_DAMAGE.new()
	_building_damage.building_index = _building_hit_index

	# One profile and one Ballistics instance behind the sight and the rounds,
	# so the pipper cannot be tuned away from where the shells actually go.
	_ballistics.adopt(cannon_weapon.profile)
	cannon_weapon.ballistics = _ballistics
	projectile_manager.profile = cannon_weapon.profile
	projectile_manager.ballistics = _ballistics
	projectile_manager.hit_query = _hit_query
	projectile_manager.projectile_impacted.connect(_on_projectile_impacted)

	cannon_weapon.projectile_manager = projectile_manager
	_bind_cannon_to(_vehicle())
	cannon_weapon.hit_query = _hit_query
	cannon_weapon.ground_height = _ground_height_xz
	cannon_weapon.aim.set_target_provider(_orbit_target_point)
	cannon_weapon.aim.set_look_provider(_free_look_aim_point)
	cannon_weapon.round_fired.connect(cannon_fx.on_round_fired)
	cannon_weapon.round_fired.connect(_on_round_fired_feedback)

	cannon_fx.projectile_manager = projectile_manager
	cannon_fx.gun_mount = cannon_weapon.gun_mount
	cannon_fx.weapon = cannon_weapon

	# Collision mirrors the streamed render data: chunks bring their footprints
	# in when they go detailed and take them away when they fall behind.
	if not streamed_terrain.chunk_buildings_ready.is_connected(_on_chunk_buildings_ready):
		streamed_terrain.chunk_buildings_ready.connect(_on_chunk_buildings_ready)
	if not streamed_terrain.chunk_buildings_released.is_connected(_on_chunk_buildings_released):
		streamed_terrain.chunk_buildings_released.connect(_on_chunk_buildings_released)


func _on_chunk_buildings_ready(chunk_key: int, records: Array, ground_height: Callable) -> void:
	if _building_hit_index != null:
		_building_hit_index.add_chunk(chunk_key, records, ground_height)


func _on_chunk_buildings_released(chunk_key: int) -> void:
	if _building_hit_index != null:
		_building_hit_index.remove_chunk(chunk_key)


## A selected orbit point remains the automatic gun target whenever direct R1
## aim is not held. CannonAim gives the manual look provider priority.
func _orbit_target_point() -> Variant:
	var vehicle := _vehicle()
	if vehicle != null and "has_orbit_target" in vehicle and vehicle.has_orbit_target:
		return vehicle.orbit_target
	return null


## While R1 is held the gun chases the manual sight ray. Returns null otherwise,
## allowing the selected orbit target or forward aim to resume.
func _free_look_aim_point() -> Variant:
	if _flying_jet or camera == null or not GamepadInput.is_free_look_held():
		return null
	var origin := camera.global_position
	# Camera shake is presentation only. Aim through the stable basis captured
	# before shake so recoil cannot walk the player's held R1 aim off target.
	var forward := -_camera_aim_basis.z.normalized()
	if _view != View.COCKPIT:
		var viewport_size := camera.get_viewport().get_visible_rect().size
		var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
		forward = EXTERNAL_AIM_CURSOR.ray_direction(
			_camera_aim_basis,
			camera.fov,
			aspect,
			_external_aim.cursor_offset
		)
	# Buildings first: the gun should aim at the facade, not the ground behind.
	if _hit_query != null:
		var travelled := 0.0
		while travelled < 4000.0:
			var step := minf(40.0, 4000.0 - travelled)
			var from := origin + forward * travelled
			var blocked: RefCounted = _hit_query.query_segment(from, from + forward * step)
			if blocked != null and blocked.hit:
				return blocked.position
			travelled += step
	var ground := GROUND_RAY.intersect(origin, forward, _ground_height_xz)
	if not ground.is_empty():
		return ground["point"]
	return origin + forward * 3000.0


func _on_round_fired_feedback(_round_data: RefCounted) -> void:
	_arcade_camera_feedback.add_recoil(cannon_recoil_trauma)


func _play_destructive_hit_stop() -> void:
	_hit_stop_serial += 1
	var serial := _hit_stop_serial
	Engine.time_scale = destructive_hit_time_scale
	await get_tree().create_timer(destructive_hit_stop_seconds, true, false, true).timeout
	if serial == _hit_stop_serial:
		Engine.time_scale = 1.0


func _on_projectile_impacted(hit_result: RefCounted, round_data: RefCounted) -> void:
	if impact_fx != null:
		impact_fx.spawn_impact(hit_result, round_data)
	var destructive: bool = hit_result.object_type == WORLD_HIT.ObjectKind.ENTITY
	attack_reticle.show_hit_confirm(destructive)
	_arcade_camera_feedback.add_impact(camera.global_position.distance_to(hit_result.position), destructive)
	# Every round damages what it actually struck, selected target or not.
	if hit_result.object_type == WORLD_HIT.ObjectKind.BUILDING and _building_damage != null:
		_building_damage.apply_hit(hit_result, round_data)
	elif hit_result.object_type == WORLD_HIT.ObjectKind.ENTITY:
		var explosion_position: Variant = launcher_field.destroy_launcher(hit_result.object_id)
		if explosion_position is Vector3:
			impact_fx.spawn_explosion(explosion_position)
			_play_destructive_hit_stop()
