extends "res://scripts/weapons/missile_flight.gd"

var defence: RefCounted
var decoy_provider := Callable()
var _decoy_handle := 0
var _decoy_lock_time := 0.0
var _candidate := 0
var _current_point := Vector3.ZERO
var _current_velocity := Vector3.ZERO

func _init() -> void:
	turn_limit_g = 5.5
	maximum_turn_rate = 1.0
	seeker_cone_degrees = 45.0
	maximum_speed = 650.0
	motor_acceleration_scale = 0.65
	maximum_lead_seconds = 2.0
	fuse_radius = 9.0
	loss_tolerance = 0.45

func advance(point: Vector3, velocity: Vector3, delta: float, age := 0.0) -> Array:
	_current_point = point
	_current_velocity = velocity
	if not _guidance_lost and _decoy_handle == 0 and decoy_provider.is_valid() and defence != null:
		var chosen := 0
		for decoy: Dictionary in decoy_provider.call():
			var offset: Vector3 = decoy.position - point
			if decoy.age > 3.5 or offset.length() > 1800.0 or velocity.angle_to(offset) > deg_to_rad(seeker_cone_degrees):
				continue
			var attractive := false
			if seeker == Seeker.HEAT:
				var player_distance := maxf(point.distance_squared_to(defence.position), 1.0)
				attractive = 2.6 / maxf(offset.length_squared(), 1.0) > defence.heat_strength(point) / player_distance
			else:
				attractive = defence.radar_signature < 0.7 or defence.beaming(point)
			if attractive:
				chosen = int(decoy.handle)
				break
		_decoy_lock_time = _decoy_lock_time + delta if chosen != 0 and chosen == _candidate else 0.0
		_candidate = chosen
		if _decoy_lock_time >= 0.18:
			_decoy_handle = chosen
	return super.advance(point, velocity, delta, age)

func target() -> Dictionary:
	if _decoy_handle != 0:
		if decoy_provider.is_valid():
			for decoy: Dictionary in decoy_provider.call():
				if int(decoy.handle) == _decoy_handle:
					return decoy
		return {}
	if defence != null and seeker == Seeker.RADAR and not defence.radar_trackable(_current_point):
		return {}
	return super.target()

func proximity_hit(from: Vector3, to: Vector3, age: float) -> RefCounted:
	var hit := super.proximity_hit(from, to, age)
	if hit != null and _decoy_handle != 0:
		hit.object_id = _decoy_handle
	return hit

func envelope_seconds() -> float:
	return 16.0
