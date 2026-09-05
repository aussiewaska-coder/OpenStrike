extends Node3D

const HELICOPTER_SCENE := preload("res://ah-64d_apache_longbow_usa.glb")
const JET_SCENE := preload("res://3dassets/f-22_raptor_-_fighter_jet_-_free.glb")
const JET_CAMERA := preload("res://scripts/camera/jet_camera.gd")
const ORBIT_LOCK := preload("res://scripts/camera/orbit_lock.gd")
const ZOOM_PROFILE := preload("res://scripts/camera/zoom_profile.gd")
const EXTERNAL_FREE_LOOK := preload("res://scripts/camera/external_free_look.gd")
const EXTERNAL_AIM_CURSOR := preload("res://scripts/camera/external_aim_cursor.gd")
const ARCADE_CAMERA_FEEDBACK := preload("res://scripts/camera/arcade_camera_feedback.gd")
const TRAIL_RENDERER := preload("res://scripts/effects/trail_renderer.gd")
const ROCKET_POD := preload("res://scripts/weapons/rocket_pod.gd")
const MISSILE_LAUNCHER := preload("res://scripts/weapons/missile_launcher.gd")
const MISSILE_FX := preload("res://scripts/effects/missile_fx.gd")
const WEAPON_SELECTION := preload("res://scripts/weapons/weapon_selection.gd")
const DRONE_FIELD := preload("res://scripts/entities/drone_field.gd")
const RAID_MISSION := preload("res://scripts/entities/raid_mission.gd")
const RADAR_SCOPE := preload("res://scripts/ui/radar_scope.gd")
const BEARING_TAPE := preload("res://scripts/ui/bearing_tape.gd")
const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")
const AIRFRAME_VISUALS := preload("res://scripts/helicopter/airframe_visuals.gd")
const GROUND_RAY := preload("res://scripts/terrain/ground_ray.gd")
const BUILDING_HIT_INDEX := preload("res://scripts/terrain/building_hit_index.gd")
const WORLD_SURFACE_RESOLVER := preload("res://scripts/world/world_surface_resolver.gd")
const WORLD_HIT_QUERY := preload("res://scripts/world/world_hit_query.gd")
const BUILDING_DAMAGE := preload("res://scripts/world/building_damage_system.gd")
const WORLD_HIT := preload("res://scripts/world/world_hit_result.gd")
const TARGET_TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const HELMET_HUD := preload("res://scripts/ui/helmet_hud.gd")

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
## Cockpit A turns the view directly. External A moves a virtual sight first;
## the camera only receives overflow after that sight reaches its aim window.
@export var free_look_yaw_degrees := 130.0
@export var free_look_pitch_degrees := 55.0
@export var free_look_speed := 2.4
@export var free_look_return_response := 6.0
@export var view_return_duration := 0.85
@export var jet_external_orbit_yaw_degrees := 180.0
## Near-polar, so the orbit is a sphere rather than a band round the waist.
@export var jet_external_orbit_pitch_degrees := 85.0

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
@onready var day_cycle = $DayCycle
@onready var weather = $Weather
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var projectile_manager: Node3D = $ProjectileManager
@onready var impact_fx: Node3D = $ImpactFX
@onready var cannon_fx: Node3D = $CannonFX
@onready var launcher_field: Node3D = $LauncherField
@onready var cannon_weapon: Node3D = $CannonWeapon
@onready var helicopter_anchor: Node3D = $HelicopterAnchor
@onready var jet_anchor: Node3D = $JetAnchor
@onready var camera: Camera3D = $Camera3D
@onready var enemy_squadron: Node3D = $EnemySquadron
@onready var ui_layer: CanvasLayer = $UI
## The one line of the old mission panel that was actually live. Built in code
## so the panel and its five dead labels could go.
var status_label: Label
var _mission_label: Label
var _settings_button: Button
var _radar: Control
const TACTICAL_MFD := preload("res://scripts/ui/tactical_mfd.gd")
const TACTICAL_NAV := preload("res://scripts/ui/tactical_navigation.gd")
const WAYPOINT_HUD := preload("res://scripts/ui/waypoint_hud.gd")
var _tactical_mfd: Control
var _waypoint_hud: Control
var _navigation := TACTICAL_NAV.new()
var _map_layers_timer := 0.0
var _helmet: Control
var _tracker := TARGET_TRACKER.new()
## Enemy squadrons arrive on a timer while the player is flying the jet.
var _next_squadron_in := 25.0
var _tape: Control
var _drone_field: Node3D
var _hero_towers: Node3D
var _mission := RAID_MISSION.new()
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
var _jet_view: int = JET_CAMERA.Mode.COCKPIT
var _camera_current_height := camera_height
var _camera_current_distance := camera_trailing_distance
var _orbit_lock := ORBIT_LOCK.new()
var _zoom_profile := ZOOM_PROFILE.new()
var _arcade_camera_feedback := ARCADE_CAMERA_FEEDBACK.new()
var _ballistics := BALLISTICS.new()
var _look_target := Vector3.ZERO
var _free_look := Vector2.ZERO
var _manual_view_active := false
var _manual_view_basis := Basis.IDENTITY
var _view_returning := false
var _view_return_start := Vector2.ZERO
var _view_return_elapsed := 0.0
var _view_return_from_tracking := false
var _view_return_basis := Basis.IDENTITY
## Head bob runs on its own clock so it does not reset when a view changes.
var _cockpit_bob_time := 0.0
var _weapons := WEAPON_SELECTION.new()
## Built in code rather than declared in the scene: neither needs authored
## properties, and a scene entry would only be two more uids to keep in step.
var _trail_renderer: MeshInstance3D
var _rocket_pod: Node3D
var _missile_launcher: Node3D
var _missile_fx: Node3D
var _tracking_basis := Basis.IDENTITY
var _jet_camera_focus := Vector3.ZERO
var _weapon_label: Label
var _external_aim := EXTERNAL_AIM_CURSOR.new()
var _camera_aim_basis := Basis.IDENTITY
var _hit_stop_serial := 0
var _target_point := Vector3.ZERO
var _has_target_point := false
var _flying_jet := true
var _camera_up := Vector3.UP
var _active_terrain: Node
var _building_hit_index: RefCounted
var _surface_resolver: RefCounted
var _hit_query: RefCounted
var _building_damage: RefCounted
## `--shot=<path> --shot-frame=<n>` after `++` on the command line saves the
## frame to disk and quits: how a local software-GL run is inspected.
var _shot_path := ""
var _shot_at_frame := 240
var _shot_frames := 0


func _ready() -> void:
	var start_time_mode := -1
	var start_weather := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--shot-frame="):
			_shot_at_frame = int(arg.trim_prefix("--shot-frame="))
		elif arg.begins_with("--time="):
			start_time_mode = int(arg.trim_prefix("--time="))
		elif arg.begins_with("--weather="):
			start_weather = int(arg.trim_prefix("--weather="))
	_build_hud()
	LocationService.status_changed.connect(_on_location_status_changed)
	LocationService.region_selected.connect(_on_region_selected)
	LocationService.location_updated.connect(_on_location_updated)
	GamepadInput.connection_changed.connect(_on_gamepad_connection_changed)
	GamepadInput.controller_attention_changed.connect(_on_controller_attention_changed)
	GamepadInput.action_pressed.connect(_on_gamepad_action_pressed)
	GamepadInput.action_released.connect(_on_gamepad_action_released)
	_configure_zoom_profile()
	_apply_view_chrome()
	Telemetry.add_source(_telemetry_sample)
	Telemetry.add_command_handler(_telemetry_command)
	settings_panel.theatre_chosen.connect(_on_theatre_chosen)
	settings_panel.open_changed.connect(_on_settings_open_changed)
	settings_panel.flight_mode_toggled.connect(_toggle_flight_mode)
	settings_panel.aircraft_switched.connect(_switch_aircraft)
	settings_panel.cache_cleared.connect(_on_cache_cleared)
	settings_panel.quality_cycled.connect(_on_quality_cycled)
	settings_panel.time_cycled.connect(_on_time_cycled)
	settings_panel.weather_cycled.connect(_on_weather_cycled)
	settings_panel.input_monitor_toggled.connect(func(on: bool): gamepad_diagnostic.get_parent().visible = on)
	settings_panel.raid_restarted.connect(_start_raid)
	_mission.raid_ended.connect(_on_raid_ended)
	if start_time_mode >= 0:
		day_cycle.mode = start_time_mode
		day_cycle.refresh()
	if start_weather >= 0:
		weather.set_preset(start_weather)
		weather.current = weather.WEATHER.target(start_weather)
	_spawn_helicopter()
	_spawn_jet()
	_snap_follow_camera()
	_hero_towers = HeroTowers.new()
	_hero_towers.name = "HeroTowers"
	add_child(_hero_towers)
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
	_shot_frames += 1
	if _shot_path != "" and _shot_frames == _shot_at_frame:
		_save_shot_and_quit()
	gamepad_diagnostic.text = "%s\n%s" % [GamepadInput.get_diagnostic_text(), _map_diagnostic_text()]
	_update_rockets(delta)
	if _camera_follow_enabled:
		_update_follow_camera(delta)
		_camera_aim_basis = camera.global_basis
		_apply_arcade_camera_shake(delta)
		_update_raid(delta)
		if _tracker.tracking_view:
			_camera_aim_basis = camera.global_basis
		_update_attack_reticle()
		_update_target_marker()


## Rockets are driven from here rather than from their own _physics_process, so
## the pod cannot fire while the game is paused and the trail is fed from the
## same frame the rocket moved in.
func _update_rockets(delta: float) -> void:
	if _rocket_pod == null or _trail_renderer == null:
		return
	if _flying_jet:
		if _rocket_pod.hardpoints.is_empty() and jet_anchor.has_method("get_hardpoints"):
			_rocket_pod.hardpoints = jet_anchor.get_hardpoints()
		_rocket_pod.carrier = jet_anchor
		_rocket_pod.update(delta, GamepadInput.is_rockets_firing())
		_missile_launcher.carrier = jet_anchor
		_missile_launcher.hardpoints = _rocket_pod.hardpoints
		_missile_launcher.update(delta, GamepadInput.is_rockets_firing())
	else:
		# Releasing the trigger on the helicopter must not leave a salvo running.
		_rocket_pod.update(delta, false)
		_missile_launcher.update(delta, false)
	# Live rockets lay smoke wherever they are now. Shells do not: at 625 RPM
	# they would swamp the segment cap, and there is nothing to see behind a
	# 30 mm round anyway.
	for round_data in projectile_manager.active_rounds:
		if round_data.weapon_source in ["rocket", "missile"]:
			var ignited: bool = round_data.flight.is_boosting(round_data.age)
			if ignited:
				_trail_renderer.push_point(round_data.sequence, round_data.position)
			elif round_data.age > 0.5:
				_trail_renderer.end_trail(round_data.sequence)
	if _weapon_label != null:
		_weapon_label.text = _weapons.name_of(_weapons.current)
		if _weapons.current in [WEAPON_SELECTION.Weapon.HEAT, WEAPON_SELECTION.Weapon.RADAR]:
			_weapon_label.text += "  " + _missile_launcher.status


## What is left on screen while flying: a status line, the raid line, the
## radar, the tape in cockpit, and the way into settings. Everything the old
## panel showed is in settings now.
func _build_hud() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 28)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(status_label)
	_mission_label = Label.new()
	_mission_label.add_theme_font_size_override("font_size", 20)
	_mission_label.add_theme_color_override("font_color", Color(0.91, 0.77, 0.28))
	_mission_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_mission_label)
	_settings_button = Button.new()
	_settings_button.text = "SETTINGS"
	_settings_button.custom_minimum_size = Vector2(140, 52)
	_settings_button.pressed.connect(_toggle_settings)
	row.add_child(_settings_button)
	_weapon_label = Label.new()
	_weapon_label.text = _weapons.name_of(_weapons.current)
	_weapon_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
	_weapon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_weapon_label)

	# The visor goes in first so the scope and the tape draw over it.
	_helmet = HELMET_HUD.new()
	ui_layer.add_child(_helmet)
	_waypoint_hud = WAYPOINT_HUD.new()
	ui_layer.add_child(_waypoint_hud)
	_tactical_mfd = TACTICAL_MFD.new()
	ui_layer.add_child(_tactical_mfd)
	_tactical_mfd.open_changed.connect(func(on: bool): GamepadInput.set_tactical_open(on, _tactical_mfd.pause_flight))
	_tactical_mfd.contact_selected.connect(_select_map_contact)
	_tactical_mfd.waypoint_requested.connect(_add_map_waypoint)
	_tactical_mfd.route_skip_requested.connect(func(): _navigation.skip(); _sync_tactical_state())
	_tactical_mfd.route_clear_requested.connect(func(): _navigation.clear(); _sync_tactical_state())
	_radar = RADAR_SCOPE.new()
	ui_layer.add_child(_radar)
	_radar.range_changed.connect(_on_radar_range_changed)
	_tracker.set_range(_radar.range_m())
	_tape = BEARING_TAPE.new()
	ui_layer.add_child(_tape)
	# The input monitor is opt-in from settings now, not a fixture.
	gamepad_diagnostic.get_parent().visible = false


func _start_raid() -> void:
	if _drone_field == null:
		return
	var half_extent: float = streamed_terrain.world_half_extent() if streamed_terrain.has_method("world_half_extent") else 5000.0
	_drone_field.populate(10, half_extent, Vector3.ZERO)
	_mission.start(10)
	_mission_label.remove_theme_color_override("font_color")
	_mission_label.add_theme_color_override("font_color", Color(0.91, 0.77, 0.28))
	_mission_label.text = _mission.hud_line()


func _on_building_damaged_for_raid(building_id: int, accumulated: float, _relative_height: float) -> void:
	_mission.building_damaged(building_id, accumulated)
	_mission_label.text = _mission.hud_line()


func _on_raid_ended(won: bool) -> void:
	_mission_label.text = _mission.hud_line()
	_mission_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6) if won else Color(1.0, 0.3, 0.25))
	status_label.text = "RAID REPELLED -- SETTINGS TO RESTART" if won else "THE CITY IS BURNING -- SETTINGS TO RESTART"


## The drones and the instruments that find them, stepped from the same frame
## the camera uses so the player's position is the one already on screen.
func _update_raid(delta: float) -> void:
	if _drone_field == null or not _camera_follow_enabled:
		return
	var vehicle := _vehicle()
	# Both airframes use +X for the nose. Instruments follow the displayed
	# attitude, matching the camera between physics ticks.
	var nose: Vector3 = vehicle.get_global_transform_interpolated().basis.x
	_drone_field.update(delta, vehicle.global_position, nose)
	# Falling wreckage lays smoke through the phase 1 renderer until it is
	# below the ground, at which point its trail is left to fade.
	for drone in _drone_field.drones():
		if drone.state == DRONE_FIELD.DRONE.State.DESTROYED:
			_trail_renderer.push_point(drone.id, drone.position)
			if drone.position.y < _ground_height_at(drone.position) - 20.0:
				_trail_renderer.end_trail(drone.id)
	var heading := atan2(nose.x, -nose.z)
	_update_targeting(delta, vehicle, nose, heading)
	if _tape.visible:
		_tape.set_contacts(vehicle.global_position, heading, _drone_field.drones())


func _on_radar_range_changed(metres: float) -> void:
	_tracker.set_range(metres)
	status_label.text = "RADAR %d KM" % int(metres / 1000.0)


## The one place the three target sources become one list, and the one place the
## visor and the scope are told anything.
func _update_targeting(delta: float, vehicle: Node3D, nose: Vector3, heading: float) -> void:
	if _flying_jet:
		_next_squadron_in -= delta
		if _next_squadron_in <= 0.0 and enemy_squadron.jet_count() == 0:
			enemy_squadron.spawn(randi_range(2, 4), vehicle.global_position)
			_next_squadron_in = 90.0
	enemy_squadron.update(delta, vehicle.global_position, nose)

	var contacts: Array = []
	contacts.append_array(enemy_squadron.contacts())
	for drone in _drone_field.drones():
		if drone.state == DRONE_FIELD.DRONE.State.DESTROYED:
			continue
		contacts.append(TARGET_TRACKER.contact(
			drone.id, TARGET_TRACKER.Kind.AIR_DRONE, drone.position, drone.velocity, "DRONE"
		))
	for launcher in launcher_field.launcher_positions():
		contacts.append(TARGET_TRACKER.contact(
			int(launcher["id"]), TARGET_TRACKER.Kind.GROUND_LAUNCHER,
			launcher["position"], Vector3.ZERO, "SAM"
		))

	# The tracker's cone is the CAMERA's, not the airframe's: what the visor
	# boxes is what the pilot is looking at, which is the point of a helmet.
	var velocity := _vehicle_velocity()
	_tracker.update(contacts, camera.global_position, -camera.global_basis.z, velocity)
	# Apply POV tracking before selecting the HUD's visible contact boxes.
	_apply_target_tracking(delta)
	var locked: Dictionary = _tracker.locked()
	_helmet.set_state(
		camera,
		velocity,
		_tracker.boxed(),
		locked,
		_tracker.closure_of(_tracker.locked_handle()),
		{
			"speed_mps": velocity.length(),
			"altitude_m": _focus_position().y,
			"heading_degrees": rad_to_deg(heading),
			"g_load": jet_anchor.load_factor if _flying_jet else 1.0,
			"mach": velocity.length() / 340.0,
		}
	)
	_radar.set_contacts(vehicle.get_global_transform_interpolated().origin, heading, _tracker.tracked(), _tracker.locked_handle())
	_navigation.advance(vehicle.global_position)
	if _waypoint_hud != null:
		_waypoint_hud.set_state(camera, vehicle.global_position, _navigation)
	if _tactical_mfd != null and _tactical_mfd.visible:
		_sync_tactical_state()
		_map_layers_timer += delta
		if _map_layers_timer >= 1.0:
			_map_layers_timer = 0.0
			_tactical_mfd.map.set_layers(streamed_terrain.tactical_map_layers())
	# The weapons need no wiring of their own: cannon_weapon.aim already reads
	# `_orbit_target_point`, which already reads `_target_point`. Keeping those
	# two in step with the lock is the whole integration.
	if not locked.is_empty():
		_target_point = locked["position"]
		_has_target_point = true
	else:
		_has_target_point = false


## jet_controller publishes `velocity`; the helicopter does not, so both are
## guarded rather than assumed.
func _vehicle_velocity() -> Vector3:
	var vehicle := _vehicle()
	if vehicle == null:
		return Vector3.ZERO
	var value = vehicle.get("velocity")
	return value if value is Vector3 else Vector3.ZERO


func _on_rocket_fired(round_data: RefCounted, _hardpoint_index: int) -> void:
	# Keyed on the sequence number, which is unique for the life of the round and
	# is what the manager hands back on impact and expiry.
	_trail_renderer.begin_trail(round_data.sequence)


func _on_magazine_changed(remaining: int, capacity: int) -> void:
	if _weapons.current != WEAPON_SELECTION.Weapon.ROCKETS:
		return
	status_label.text = (
		"RELOADING" if remaining == 0 else "ROCKETS %d/%d" % [remaining, capacity]
	)


func _on_weapon_changed(weapon: int) -> void:
	status_label.text = "WEAPON: %s" % _weapons.name_of(weapon)


## A rocket that runs out of fuel and range leaves its smoke behind to fade.
func _on_projectile_expired(round_data: RefCounted) -> void:
	if _trail_renderer != null and round_data.weapon_source in ["rocket", "missile"]:
		_trail_renderer.end_trail(round_data.sequence)


## X carries two jobs, told apart by how long it was held. The decision waits for
## the release, because until the button comes up there is no way to know which
## one the player meant.
func _on_gamepad_action_released(action: StringName, held_seconds: float) -> void:
	if _tactical_mfd != null and _tactical_mfd.visible:
		return
	if settings_panel != null and settings_panel.visible:
		if action == GamepadInput.ACTION_WEAPON_CYCLE and not GamepadInput.mapper_active:
			settings_panel.close_panel()
		return
	if action != GamepadInput.ACTION_WEAPON_CYCLE:
		return
	if GamepadInput.is_hold(held_seconds):
		_toggle_settings()
	else:
		_weapons.cycle()


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
	_set_vehicle_active(jet_anchor, _flying_jet)
	_set_vehicle_active(helicopter_anchor, not _flying_jet)
	if _flying_jet:
		jet_anchor.launch(Vector3(0.0, 900.0, 0.0), 0.0)


func _set_vehicle_active(anchor: Node3D, active: bool) -> void:
	anchor.visible = active
	anchor.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


## Swap aircraft in place, so the player keeps the piece of coastline they were
## looking at. The jet needs height and speed to exist at all, so it is launched
## rather than simply moved.
func _switch_aircraft() -> void:
	_tracker.clear_lock()
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
		_jet_view = JET_CAMERA.Mode.PURSUIT
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
	settings_panel.set_flight_mode_text(_flight_mode_text())
	status_label.text = "F-22 -- " + GamepadInput.control_hint("A THROTTLE, R1 TRACK, L2/R2 RUDDER, BOTH VECTOR") if _flying_jet else "AH-64D APACHE"


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
		settings_panel.set_region_text("REGION: NO THEATRE INSTALLED")
		return
	await _load_streamed_region(region)


## Every theatre streams. The map cache is checked before the network, so a
## theatre already flown loads from disk and needs no signal.
func _load_streamed_region(region: Dictionary) -> void:
	_navigation.clear()
	if _tactical_mfd != null:
		_tactical_mfd.map.set_layers({})
	_tracker.clear_lock()
	launcher_field.clear()
	_hero_towers.clear()
	streamed_terrain.visible = true
	if not streamed_terrain.status_changed.is_connected(_on_streamed_status_changed):
		streamed_terrain.status_changed.connect(_on_streamed_status_changed)
	_camera_follow_enabled = false
	settings_panel.set_region_text("REGION: %s\n%s" % [region.get("display_name", "Unknown"), region.get("subtitle", "")])
	var loaded: bool = await streamed_terrain.load_region(region)
	if not loaded:
		settings_panel.set_region_text("REGION: %s // STREAM UNAVAILABLE" % region.get("display_name", "Unknown"))
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
	# Prepare the F-22 at cruise altitude, whether active or parked.
	jet_anchor.launch(
		streamed_terrain.get_spawn_position(900.0),
		deg_to_rad(streamed_terrain.get_spawn_yaw_degrees(-35.0))
	)
	streamed_terrain.set_focus(_vehicle())
	launcher_field.populate(String(region.get("id", "")), streamed_terrain)
	_hero_towers.populate(String(region.get("id", "")), streamed_terrain)
	_camera_follow_enabled = true
	_start_raid()
	_snap_follow_camera()


func _on_streamed_status_changed(message: String) -> void:
	status_label.text = message


## Cockpit aim turns the view. External aim updates the target cursor and its
## delayed camera catch-up as separate pieces of state.
func _update_free_look(delta: float) -> void:
	var manual_look := GamepadInput.get_jet_look_vector() if _flying_jet else (GamepadInput.get_aim_vector() if GamepadInput.is_free_look_held() else Vector2.ZERO)
	if _flying_jet and _advance_view_return(delta, manual_look):
		return
	if _tracker.tracking_view and not manual_look.is_zero_approx():
		_begin_manual_view()
	if _manual_view_active:
		var yaw := -manual_look.x * free_look_speed * deg_to_rad(free_look_yaw_degrees) * delta
		var pitch := -manual_look.y * free_look_speed * deg_to_rad(free_look_pitch_degrees) * delta
		_manual_view_basis = (Basis(Vector3.UP, yaw) * _manual_view_basis * Basis(Vector3.RIGHT, pitch)).orthonormalized()
		return
	if _flying_jet:
		_external_aim.update(Vector2.ZERO, false, delta)
		var look := GamepadInput.get_jet_look_vector()
		if _jet_view == JET_CAMERA.Mode.COCKPIT:
			_free_look = JET_CAMERA.updated_look(
				_free_look, look, free_look_speed, free_look_return_response, delta
			)
		else:
			_free_look = JET_CAMERA.updated_external_look(
				_free_look,
				look if JET_CAMERA.allows_free_look(_jet_view) else Vector2.ZERO,
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


## Cockpit look is a neck and keeps the default limits. The external orbit is a
## camera on a sphere and takes the wider ones, so the player can pass over and
## under the aircraft rather than round a band at its waist.
func _free_look_basis(yaw_degrees := -1.0, pitch_degrees := -1.0) -> Basis:
	if _free_look.is_zero_approx():
		return Basis.IDENTITY
	var yaw_limit := free_look_yaw_degrees if yaw_degrees < 0.0 else yaw_degrees
	var pitch_limit := free_look_pitch_degrees if pitch_degrees < 0.0 else pitch_degrees
	if yaw_degrees < 0.0 and pitch_degrees < 0.0:
		return JET_CAMERA.cockpit_look_basis(
			deg_to_rad(_free_look.x * yaw_limit), deg_to_rad(_free_look.y * pitch_limit)
		)
	return Basis(Vector3.UP, deg_to_rad(_free_look.x * yaw_limit)) \
		* Basis(Vector3.RIGHT, deg_to_rad(_free_look.y * pitch_limit))


func _view_return_weight() -> float:
	var t := clampf(_view_return_elapsed / maxf(view_return_duration, 0.001), 0.0, 1.0)
	# Zero velocity and acceleration at both ends: a deliberate head turn.
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


func _begin_view_return() -> void:
	_view_return_from_tracking = _tracker.tracking_view or _manual_view_active
	if _view_return_from_tracking:
		var reference: Basis
		if _jet_view == JET_CAMERA.Mode.COCKPIT:
			var frame: Transform3D = jet_anchor.get_interpolated_cockpit_transform()
			reference = Basis.looking_at(frame.basis.x, frame.basis.y)
		else:
			var frame: Transform3D = jet_anchor.get_interpolated_airframe_transform()
			reference = Basis.looking_at(_look_target - camera.global_position, JET_CAMERA.camera_up(_jet_view, frame.basis.y))
		_view_return_basis = reference.inverse() * camera.global_basis
	_tracker.stop_view_tracking()
	_manual_view_active = false
	_view_return_start = _free_look
	_view_return_elapsed = 0.0
	_view_returning = true


func _advance_view_return(delta: float, manual_look: Vector2) -> bool:
	if not _view_returning:
		return false
	if not manual_look.is_zero_approx():
		if _view_return_from_tracking:
			_begin_manual_view()
		_view_returning = false
		return false
	_view_return_elapsed += delta
	_free_look = _view_return_start.lerp(Vector2.ZERO, _view_return_weight())
	if _view_return_elapsed >= view_return_duration:
		_free_look = Vector2.ZERO
		_view_returning = false
	return true


func _external_camera_aim_basis() -> Basis:
	return _external_aim.camera_basis()


func _update_follow_camera(delta: float) -> void:
	_update_free_look(delta)
	# Wrapped on the bob's own repeat period: 1.4 Hz and 0.9 Hz both come back
	# to phase at ten seconds, so this is exact and the clock cannot drift off
	# into the range where a float stops resolving fractions of a cycle.
	_cockpit_bob_time = fmod(_cockpit_bob_time + delta, 10.0)
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


## Raptor views are authored separately: cockpit inherits the interpolated
## airframe, while external body and aim targets use independent damped springs.
func _update_jet_camera(delta: float, snap: bool = false) -> void:
	var speed: float = jet_anchor.airspeed()
	var speed_span: float = maxf(
		jet_anchor.maximum_display_speed - jet_anchor.minimum_display_speed,
		1.0
	)
	var speed_fraction := clampf(
		(speed - jet_anchor.minimum_display_speed) / speed_span,
		0.0,
		1.0
	)
	if _jet_view == JET_CAMERA.Mode.COCKPIT:
		var cockpit: Transform3D = jet_anchor.get_interpolated_cockpit_transform()
		var bob: Vector2 = JET_CAMERA.head_bob(
			_cockpit_bob_time,
			jet_anchor.load_factor,
			speed_fraction
		)
		camera.global_position = cockpit.origin
		var head_basis := _free_look_basis()
		if _view_returning and _view_return_from_tracking:
			head_basis = _view_return_basis.slerp(Basis.IDENTITY, _view_return_weight())
		camera.global_basis = Basis.looking_at(cockpit.basis.x, cockpit.basis.y) \
			* head_basis \
			* Basis.from_euler(Vector3(deg_to_rad(bob.x), 0.0, deg_to_rad(bob.y)))
		camera.fov = JET_CAMERA.field_of_view(
			_jet_view, _camera_zoom, speed_fraction, camera_zoom_max
		)
		_look_target = cockpit.origin + cockpit.basis.x * 100.0
		_jet_camera_focus = _focus_position()
		_apply_manual_view()
		return

	var focus := _focus_position()
	var airframe: Transform3D = jet_anchor.get_interpolated_airframe_transform()
	var maximum_camera_pitch := 30.0 if _jet_view == JET_CAMERA.Mode.TRACK else 40.0
	var direction := JET_CAMERA.flight_direction(
		jet_anchor.velocity,
		airframe.basis.x,
		maximum_camera_pitch
	)
	var distance := JET_CAMERA.trailing_distance(
		speed,
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
		var orbit_frame := Basis.looking_at(direction, Vector3.UP)
		desired_position = JET_CAMERA.external_orbit_position(
			_jet_view,
			focus,
			desired_position,
			orbit_frame * _free_look_basis(jet_external_orbit_yaw_degrees, jet_external_orbit_pitch_degrees) * orbit_frame.inverse(),
			_free_look
		)
	desired_position = JET_CAMERA.clear_orbit_position(
		focus, desired_position, _ground_height_at(desired_position) + camera_ground_clearance
	)
	var desired_look := JET_CAMERA.look_target(
		_jet_view,
		focus,
		jet_anchor.velocity,
		direction,
		distance
	)
	# The aircraft is the orbit pivot and stays in frame at every azimuth.
	if JET_CAMERA.allows_free_look(_jet_view):
		desired_look = focus
	var target_fov := JET_CAMERA.field_of_view(
		_jet_view, _camera_zoom, speed_fraction, camera_zoom_max
	)
	if snap:
		camera.global_position = desired_position
		_look_target = desired_look
		camera.fov = target_fov
	else:
		var position_weight := 1.0 - exp(-JET_CAMERA.position_response(_jet_view) * delta)
		var aim_weight := 1.0 - exp(-JET_CAMERA.aim_response(_jet_view) * delta)
		if JET_CAMERA.allows_free_look(_jet_view):
			camera.global_position = focus + JET_CAMERA.smooth_orbit_offset(
				camera.global_position - _jet_camera_focus, desired_position - focus, position_weight
			)
		else:
			camera.global_position = camera.global_position.lerp(desired_position, position_weight)
		_look_target = _look_target.lerp(desired_look, aim_weight)
		camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-camera_mode_response * delta))
	_jet_camera_focus = focus
	if JET_CAMERA.allows_free_look(_jet_view):
		_look_target = focus
	camera.global_position = JET_CAMERA.clear_orbit_position(
		focus, camera.global_position, _ground_height_at(camera.global_position) + camera_ground_clearance
	)
	if camera.global_position.distance_squared_to(_look_target) > 0.0001:
		camera.look_at(_look_target, JET_CAMERA.camera_up(_jet_view, airframe.basis.y))
		if _view_returning and _view_return_from_tracking:
			camera.global_basis *= _view_return_basis.slerp(Basis.IDENTITY, _view_return_weight())
	_apply_manual_view()


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
func _save_shot_and_quit() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png(_shot_path)
		print("SHOT_SAVED ", _shot_path)
	else:
		print("SHOT_FAILED")
	get_tree().quit()


## Live tuning over the telemetry socket, so the look can be adjusted from a
## shell on the device instead of through a five-minute APK build per guess.
## {"set": {...}} writes the listed knobs; {"screenshot": true} returns the
## frame as base64 PNG, shrunk to keep the line small.
func _telemetry_command(command: Dictionary) -> Dictionary:
	var reply := {}
	var environment: Environment = world_environment.environment
	var sky_material := environment.sky.sky_material as ShaderMaterial
	var settings: Dictionary = command.get("set", {})
	for key in settings:
		var value = settings[key]
		match String(key):
			"day_cycle_enabled":
				day_cycle.set_process(bool(value))
			"time_mode":
				day_cycle.mode = int(value)
				day_cycle.refresh()
			"fog_enabled":
				environment.fog_enabled = bool(value)
			"fog_density":
				environment.fog_density = float(value)
			"fog_aerial_perspective":
				environment.fog_aerial_perspective = float(value)
			"fog_sky_affect":
				environment.fog_sky_affect = float(value)
			"fog_light_color":
				environment.fog_light_color = Color(value[0], value[1], value[2])
			"tonemap_mode":
				environment.tonemap_mode = int(value)
			"tonemap_exposure":
				environment.tonemap_exposure = float(value)
			"tonemap_white":
				environment.tonemap_white = float(value)
			"ambient_energy":
				environment.ambient_light_energy = float(value)
			"camera_far":
				camera.far = float(value)
			"sun_energy":
				sun.light_energy = float(value)
			"sky_top_color":
				if sky_material != null:
					sky_material.set_shader_parameter("sky_top_color", Color(value[0], value[1], value[2]))
			"sky_horizon_color":
				if sky_material != null:
					sky_material.set_shader_parameter("sky_horizon_color", Color(value[0], value[1], value[2]))
			"fog_multiplier":
				day_cycle.fog_multiplier = float(value)
				day_cycle.refresh()
			"weather":
				weather.set_preset(int(value))
			"cloud_coverage":
				weather.current["cloud_coverage"] = float(value)
			"sun_multiplier":
				day_cycle.sun_multiplier = float(value)
				day_cycle.refresh()
			"terrain_tint":
				RenderingServer.global_shader_parameter_set("os_terrain_tint", Vector3(value[0], value[1], value[2]))
			_:
				reply["unknown_" + String(key)] = true
	if command.get("screenshot", false):
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			reply["screenshot_error"] = "no frame"
		else:
			var width := int(command.get("width", 960))
			image.resize(width, int(float(image.get_height()) * float(width) / float(image.get_width())), Image.INTERPOLATE_BILINEAR)
			reply["screenshot_png_base64"] = Marshalls.raw_to_base64(image.save_png_to_buffer())
	return reply


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
	var environment: Environment = world_environment.environment
	sample.merge({
		"renderer": RenderingServer.get_current_rendering_method(),
		"time_mode": day_cycle.mode_name(),
		"sun_elevation_degrees": day_cycle.elevation_deg,
		"sun_azimuth_degrees": day_cycle.azimuth_deg,
		"sun_energy": sun.light_energy,
		"terrain_tint": str(day_cycle.applied_tint),
		"fog_enabled": environment.fog_enabled,
		"fog_density": environment.fog_density,
		"tonemap_mode": environment.tonemap_mode,
		"weather": weather.preset_name(),
		"cloud_coverage": float(weather.current.get("cloud_coverage", 0.0)),
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
	if _tactical_mfd != null and _tactical_mfd.visible:
		return
	if settings_panel != null and settings_panel.visible:
		return
	if not _camera_follow_enabled:
		return
	var screen := Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed:
		screen = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		screen = (event as InputEventMouseButton).position
	else:
		return
	_lock_at_screen(screen)


## A screen press locks a target independently of the gamepad flight controls.
func _lock_at_screen(screen: Vector2) -> void:
	if not _camera_follow_enabled:
		return
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var hit := GROUND_RAY.intersect(origin, direction, _ground_height_xz)
	var point = null
	var kind: int = TARGET_TRACKER.Kind.GROUND_POINT
	var target_name := ""
	if not hit.is_empty():
		point = hit["point"]
	# `_hit_query` already knows how to tell a building from the dirt, so the
	# lock asks it rather than growing a second opinion about what was struck.
	if _hit_query != null:
		var world: RefCounted = _hit_query.query_segment(origin, origin + direction * 12000.0)
		if world != null and world.hit and world.object_type == WORLD_HIT.ObjectKind.BUILDING:
			point = world.position
			kind = TARGET_TRACKER.Kind.BUILDING
			target_name = "BUILDING"
	var handle := _tracker.lock_at(origin, direction, point, kind, target_name)
	if handle == -1:
		_has_target_point = false
		attack_reticle.clear_target()
		if _vehicle().has_method("clear_orbit_target"):
			_vehicle().clear_orbit_target()
		status_label.text = "TARGET CLEARED"
		return
	var locked: Dictionary = _tracker.locked()
	_target_point = locked["position"]
	_has_target_point = true
	if _vehicle().has_method("set_orbit_target"):
		_vehicle().set_orbit_target(_target_point)
	var range_m := roundi(_focus_position().distance_to(_target_point))
	status_label.text = "LOCK %s  %d m" % [HELMET_HUD.kind_label(int(locked["kind"])), range_m]


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
	# Held A is also always a weapon view: the movable sight marks the manual
	# ray while the pipper shows where the traversing barrel will land.
	attack_reticle.set_jet_throttle(
		_flying_jet,
		jet_anchor.throttle_percent() if _flying_jet else 0.0,
		jet_anchor.afterburner_fraction() if _flying_jet else 0.0
	)
	var cockpit_view := _is_cockpit_view()
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
	_apply_manual_view()


func _is_cockpit_view() -> bool:
	return _jet_view == JET_CAMERA.Mode.COCKPIT if _flying_jet else _view == View.COCKPIT


func _snap_follow_camera() -> void:
	_manual_view_active = false
	_view_returning = false
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
		# External A is manual aim: rotate the view ray, not the camera boom.
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
	_apply_manual_view()


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
	if action == GamepadInput.ACTION_TACTICAL_MAP:
		_toggle_tactical_map()
		return
	if _tactical_mfd != null and _tactical_mfd.visible:
		return
	if settings_panel != null and settings_panel.visible:
		return
	if action == GamepadInput.ACTION_TRACK_TARGET:
		_track_looked_at_target()
	elif action == GamepadInput.ACTION_ZOOM_IN:
		_camera_zoom = _zoom_profile.step(_camera_zoom, camera_zoom_step_ratio, true, camera_zoom_max)
	elif action == GamepadInput.ACTION_ZOOM_OUT:
		_camera_zoom = _zoom_profile.step(_camera_zoom, camera_zoom_step_ratio, false, camera_zoom_max)
	elif action == GamepadInput.ACTION_CAMERA_TRAVEL_TOGGLE:
		if _tracker.tracking_view:
			if _flying_jet:
				_begin_view_return()
			else:
				_tracker.stop_view_tracking()
				_free_look = Vector2.ZERO
			status_label.text = "TRACKING OFF -- WEAPON LOCK RETAINED"
			return
		if _flying_jet:
			if _view_returning:
				return
			# R3 straightens whatever is crooked, nearest first. A turned head
			# is the more urgent of the two -- and you cannot judge a wings-level
			# recovery while looking at your own tailplane anyway -- so the view
			# comes back before the aircraft does.
			if _manual_view_active or JET_CAMERA.is_look_displaced(_free_look):
				_begin_view_return()
				status_label.text = "RETURNING VIEW FORWARD"
			else:
				var accepted: bool = jet_anchor.request_wings_level()
				status_label.text = "WINGS LEVEL" if accepted else "WINGS LEVEL UNAVAILABLE"
		else:
			_cycle_view()
	elif action == GamepadInput.ACTION_TARGET_PREVIOUS and _flying_jet:
		_cycle_jet_view(-1)
	elif action == GamepadInput.ACTION_TARGET_NEXT and _flying_jet:
		_cycle_jet_view(1)
	# Settings is no longer a press: it is the hold half of X, handled in
	# _on_gamepad_action_released. The on-screen SETTINGS button still calls
	# _toggle_settings directly.


func _track_looked_at_target() -> void:
	if not _camera_follow_enabled:
		return
	var visible: Array[int] = []
	var viewport_rect := camera.get_viewport().get_visible_rect()
	for c in _tracker.tracked():
		if not camera.is_position_behind(c.position) and viewport_rect.has_point(camera.unproject_position(c.position)):
			visible.append(int(c.handle))
	var handle := _tracker.cycle_view_lock(visible, camera.global_position, -camera.global_basis.z)
	if handle == -1:
		status_label.text = "NO TARGET IN VIEW CLUSTER"
		return
	_view_returning = false
	_tracking_basis = camera.global_basis
	_has_target_point = true
	_target_point = _tracker.locked().position
	status_label.text = "TRACKING %s -- %s NEXT IN CLUSTER" % [_tracker.locked().get("name", "TARGET"), GamepadInput.BINDINGS.label(GamepadInput.bindings.values.track_target)]


func _apply_target_tracking(delta: float) -> void:
	if not _tracker.tracking_view:
		return
	_manual_view_active = false
	var c := _tracker.locked()
	if c.is_empty():
		_tracker.stop_view_tracking()
		return
	var offset: Vector3 = c.position - camera.global_position
	if offset.length_squared() < 0.01:
		return
	var reference := Basis.IDENTITY
	var cockpit_view := _is_cockpit_view()
	if cockpit_view and _vehicle() != null:
		if _flying_jet:
			var frame: Transform3D = jet_anchor.get_interpolated_cockpit_transform()
			reference = Basis.looking_at(frame.basis.x, frame.basis.y)
		else:
			var vehicle := _vehicle()
			var frame: Transform3D = vehicle.get_cockpit_transform() if vehicle.has_method("get_cockpit_transform") else vehicle.global_transform
			reference = Basis.looking_at(frame.basis.x, frame.basis.y)
	var wanted := JET_CAMERA.tracking_basis(offset, reference, _tracking_basis, cockpit_view)
	_tracking_basis = _tracking_basis.slerp(wanted, 1.0 - exp(-12.0 * delta)).orthonormalized()
	camera.global_basis = _tracking_basis
	_tracker.update_view(camera.global_position, -camera.global_basis.z, _vehicle_velocity())


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
	settings_panel.set_flight_mode_text(_flight_mode_text())
	status_label.text = "CONTROLS: %s" % ("REALISTIC ROTOR" if next == rotor else "ARCADE")


func _toggle_settings() -> void:
	if _tactical_mfd != null:
		_tactical_mfd.close_panel()
	if settings_panel.toggle_panel():
		_refresh_settings()


func _on_settings_open_changed(is_open: bool) -> void:
	GamepadInput.set_settings_open(is_open)
	if not is_open and _settings_button != null:
		_settings_button.release_focus()


func _refresh_settings() -> void:
	settings_panel.populate_theatres(
		LocationService.installed_regions(),
		String(LocationService.selected_region.get("id", ""))
	)
	settings_panel.set_flight_mode_text(_flight_mode_text())
	if streamed_terrain.has_method("quality_name"):
		settings_panel.set_quality_text("GRAPHICS: %s" % streamed_terrain.quality_name())
	settings_panel.set_time_text("TIME: %s" % day_cycle.mode_name())
	settings_panel.set_weather_text("WEATHER: %s" % weather.preset_name())
	var report: Dictionary = TileClient.cache_report()
	settings_panel.set_cache_report(int(report["files"]), int(report["bytes"]))
	var focus := _focus_position()
	var view_name: String = JET_CAMERA.Mode.keys()[_jet_view] if _flying_jet else View.keys()[_view]
	settings_panel.set_status("%s · %s view\n%d m above ground" % [
		"F-22 Raptor" if _flying_jet else "AH-64D Apache", view_name.to_lower(), roundi(focus.y - _ground_height_at(focus))
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


func _on_time_cycled() -> void:
	day_cycle.cycle_mode()
	status_label.text = "TIME: %s" % day_cycle.mode_name()
	_refresh_settings()


func _on_weather_cycled() -> void:
	weather.cycle_preset()
	status_label.text = "WEATHER: %s" % weather.preset_name()
	_refresh_settings()


func _on_cache_cleared() -> void:
	var removed: int = TileClient.clear_cache()
	status_label.text = "MAP CACHE CLEARED: %d files removed" % removed
	_refresh_settings()


func _flight_mode_text() -> String:
	if _flying_jet:
		return "CONTROLS: FLY-BY-WIRE"
	if not ("flight_mode" in helicopter_anchor):
		return "CONTROLS: --"
	var arcade: int = helicopter_anchor.FlightMode.ARCADE
	return "CONTROLS: %s" % ("ARCADE" if int(helicopter_anchor.flight_mode) == arcade else "REALISTIC")


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
			status_label.text = "ORBIT VIEW: " + GamepadInput.control_hint("RIGHT STICK LOOK" if _flying_jet else "L2/R2 SWEEP A LOCKED GROUND POINT")
		_:
			_view = View.COCKPIT
			status_label.text = "COCKPIT VIEW"
	_apply_view_chrome()
	if _view != View.COCKPIT:
		_snap_follow_camera()


func _cycle_jet_view(direction: int) -> void:
	_tracker.stop_view_tracking()
	var count := JET_CAMERA.Mode.size()
	_jet_view = posmod(_jet_view + direction, count)
	_free_look = Vector2.ZERO
	_apply_view_chrome()
	_snap_follow_camera()
	match _jet_view:
		JET_CAMERA.Mode.COCKPIT:
			status_label.text = "COCKPIT VIEW"
		JET_CAMERA.Mode.PURSUIT:
			status_label.text = "PURSUIT VIEW"
		JET_CAMERA.Mode.TRACK:
			status_label.text = "TRACKING VIEW"
		_:
			status_label.text = "TACTICAL GROUND-LOCK VIEW"


## In the cockpit the screen is the HUD and nothing else.
func _apply_view_chrome() -> void:
	# The tape is a cockpit instrument; the scope is always up. The input
	# monitor is a settings toggle now and does not follow the view.
	if _tape != null:
		_tape.visible = _is_cockpit_view()
	if _helmet != null:
		_helmet.set_cockpit_view(_is_cockpit_view())


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
	_tracker.clear_lock()
	status_label.text = "IMPACT -- RECOVERING"


func _on_jet_respawned() -> void:
	status_label.text = "AIRBORNE -- " + GamepadInput.control_hint("A THROTTLE, R1 TRACK, L2/R2 RUDDER, BOTH VECTOR")
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
	_drone_field = DRONE_FIELD.new()
	_drone_field.name = "DroneField"
	add_child(_drone_field)
	_drone_field.projectile_manager = projectile_manager
	_hit_query.secondary_entity_index = _drone_field
	_hit_query.additional_entity_indices.append(enemy_squadron)
	_building_damage = BUILDING_DAMAGE.new()
	_building_damage.building_index = _building_hit_index
	_drone_field.building_index = _building_hit_index
	_building_damage.building_damaged.connect(_on_building_damaged_for_raid)

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

	_trail_renderer = TRAIL_RENDERER.new()
	_trail_renderer.name = "TrailRenderer"
	add_child(_trail_renderer)
	_rocket_pod = ROCKET_POD.new()
	_rocket_pod.name = "RocketPod"
	add_child(_rocket_pod)
	_rocket_pod.projectile_manager = projectile_manager
	_rocket_pod.selection = _weapons
	_rocket_pod.rocket_fired.connect(_on_rocket_fired)
	_rocket_pod.magazine_changed.connect(_on_magazine_changed)
	_missile_launcher = MISSILE_LAUNCHER.new()
	_missile_launcher.name = "MissileLauncher"
	add_child(_missile_launcher)
	_missile_launcher.projectile_manager = projectile_manager
	_missile_launcher.selection = _weapons
	_missile_launcher.tracker = _tracker
	_missile_launcher.missile_fired.connect(_on_rocket_fired)
	_missile_fx = MISSILE_FX.new()
	_missile_fx.projectile_manager = projectile_manager
	add_child(_missile_fx)
	_weapons.changed.connect(_on_weapon_changed)
	projectile_manager.projectile_expired.connect(_on_projectile_expired)

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


## The tracker owns weapon lock for both tap and R1 selection. Reading the
## vehicle's orbit point instead leaves the turret aiming at a moving target's
## old tap position. CannonAim still gives held A manual aim priority.
func _orbit_target_point() -> Variant:
	return _tracker.locked_position()


## While A is held the gun chases the manual sight ray. Returns null otherwise,
## allowing the selected orbit target or forward aim to resume.
func _free_look_aim_point() -> Variant:
	if _flying_jet or camera == null or not GamepadInput.is_free_look_held():
		return null
	var origin := camera.global_position
	# Camera shake is presentation only. Aim through the stable basis captured
	# before shake so recoil cannot walk the player's held A aim off target.
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
	if _trail_renderer != null and round_data.weapon_source in ["rocket", "missile"]:
		_trail_renderer.end_trail(round_data.sequence)
	if impact_fx != null:
		impact_fx.spawn_impact(hit_result, round_data)
		if round_data.weapon_source == "missile" and hit_result.object_type != WORLD_HIT.ObjectKind.ENTITY:
			impact_fx.spawn_explosion(hit_result.position)
	var destructive: bool = hit_result.object_type == WORLD_HIT.ObjectKind.ENTITY
	attack_reticle.show_hit_confirm(destructive)
	_arcade_camera_feedback.add_impact(camera.global_position.distance_to(hit_result.position), destructive)
	# Every round damages what it actually struck, selected target or not.
	if hit_result.object_type == WORLD_HIT.ObjectKind.BUILDING and _building_damage != null:
		_building_damage.apply_hit(hit_result, round_data)
	elif hit_result.object_type == WORLD_HIT.ObjectKind.ENTITY:
		# The fields have disjoint id spaces, so whichever claims the id
		# is the one that was hit. A bomb striking its own drone is refused
		# by weapon_source, or drones would shoot themselves down.
		var explosion_position: Variant = null
		if hit_result.object_id >= enemy_squadron.FIRST_ID:
			var destroyed = enemy_squadron.destroy_jet(hit_result.object_id)
			if destroyed != null:
				explosion_position = destroyed.position
		elif hit_result.object_id >= DRONE_FIELD.FIRST_ID:
			if round_data.weapon_source != "bomb":
				explosion_position = _drone_field.destroy_drone(hit_result.object_id)
				if explosion_position is Vector3:
					_mission.drone_destroyed()
					_mission_label.text = _mission.hud_line()
					_trail_renderer.begin_trail(hit_result.object_id)
		else:
			explosion_position = launcher_field.destroy_launcher(hit_result.object_id)
		if explosion_position is Vector3:
			_tracker.remove_contact(hit_result.object_id)
			if _tracker.locked().is_empty():
				_has_target_point = false
			impact_fx.spawn_explosion(explosion_position)
			_play_destructive_hit_stop()


func _toggle_tactical_map() -> void:
	if _tactical_mfd == null or (settings_panel != null and settings_panel.visible):
		return
	if _tactical_mfd.visible:
		_tactical_mfd.close_panel()
	else:
		_sync_tactical_state()
		_tactical_mfd.map.set_layers(streamed_terrain.tactical_map_layers())
		_tactical_mfd.open_panel()


func _sync_tactical_state() -> void:
	if _tactical_mfd == null or _vehicle() == null:
		return
	var position := _vehicle().global_position
	var heading: float = _radar._heading if _radar != null else 0.0
	_tactical_mfd.map.set_state(position, heading, _tracker.known_contacts(), _tracker.locked_handle(), _navigation)
	if _waypoint_hud != null:
		_waypoint_hud.set_state(camera, position, _navigation)


func _select_map_contact(handle: int) -> void:
	if not _tracker.select_contact(handle):
		_tactical_mfd.show_message("Contact unavailable or outside 40 km lock range")
		return
	var contact: Dictionary = _tracker.locked()
	_target_point = contact.position
	_has_target_point = true
	if _vehicle().has_method("set_orbit_target"):
		_vehicle().set_orbit_target(_target_point)
	_tactical_mfd.show_message("SELECTED %s · %.1f km · Weapon lock set" % [contact.get("name", "CONTACT"), _focus_position().distance_to(_target_point) / 1000.0])
	_sync_tactical_state()


func _add_map_waypoint(point: Vector2) -> void:
	var half := float(_tactical_mfd.map.layers.get("world_size_m", 50000.0)) * 0.5
	if absf(point.x) > half or absf(point.y) > half:
		_tactical_mfd.show_message("Waypoint outside this theatre · pan back inside the mapped area")
		return
	var position := Vector3(point.x, _ground_height_xz(point.x, point.y), point.y)
	if _navigation.add(position):
		_tactical_mfd.show_message("WP %02d SET · %d remaining · Add WP mode stays active" % [_navigation.completed + _navigation.points.size(), _navigation.points.size()])
	else:
		_tactical_mfd.show_message("Route full · maximum 12 waypoints")
	_sync_tactical_state()


## A tracking handoff keeps the complete displayed pose, including neck roll
## and directions outside normal manual-look limits. The old look/orbit state
## stays fixed until an explicit recenter or view change.
func _manual_view_reference() -> Basis:
	if _is_cockpit_view():
		if _flying_jet:
			var frame: Transform3D = jet_anchor.get_interpolated_cockpit_transform()
			return Basis.looking_at(frame.basis.x, frame.basis.y)
		var vehicle := _vehicle()
		var frame: Transform3D = vehicle.get_cockpit_transform() if vehicle.has_method("get_cockpit_transform") else vehicle.global_transform
		return Basis.looking_at(frame.basis.x, Vector3.UP)
	var up := Vector3.UP
	if _flying_jet:
		var frame: Transform3D = jet_anchor.get_interpolated_airframe_transform()
		up = JET_CAMERA.camera_up(_jet_view, frame.basis.y)
	if camera.global_position.distance_squared_to(_look_target) < 0.0001:
		return camera.global_basis
	return Basis.looking_at(_look_target - camera.global_position, up)


func _begin_manual_view() -> void:
	_manual_view_basis = (_manual_view_reference().inverse() * camera.global_basis).orthonormalized()
	_manual_view_active = true
	_tracker.stop_view_tracking()


func _apply_manual_view() -> void:
	if _manual_view_active:
		camera.global_basis = _manual_view_reference() * _manual_view_basis
