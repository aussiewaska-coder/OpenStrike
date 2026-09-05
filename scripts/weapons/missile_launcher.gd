extends Node3D

const FLIGHT := preload("res://scripts/weapons/missile_flight.gd")
const WEAPONS := preload("res://scripts/weapons/weapon_selection.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
signal missile_fired(round_data: RefCounted, hardpoint_index: int)

const CAPACITY := 4
const RELOAD_SECONDS := 7.0
var projectile_manager: Node3D
var carrier: Node3D
var hardpoints: Array[Node3D] = []
var tracker: RefCounted
var selection: RefCounted
var remaining := CAPACITY
var ready_time := 0.0
var status := "NO LOCK"
var _acquiring_handle := -1
var _acquiring_weapon := -1
var _cooldown := 0.0
var _reload := 0.0
var _trigger_was_held := false
var _sequence := 1000000
var _side := 0

func update(delta: float, trigger: bool) -> void:
	var pressed := trigger and not _trigger_was_held
	_trigger_was_held = trigger
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _reload > 0.0:
		_reload -= delta
		status = "RELOADING"
		if _reload <= 0.0:
			remaining = CAPACITY
		return
	if selection == null or selection.current not in [WEAPONS.Weapon.HEAT, WEAPONS.Weapon.RADAR]:
		ready_time = 0.0
		return
	var c: Dictionary = tracker.locked() if tracker != null else {}
	var handle := int(c.get("handle", -1))
	if handle != _acquiring_handle or selection.current != _acquiring_weapon:
		ready_time = 0.0
		_acquiring_handle = handle
		_acquiring_weapon = selection.current
	if not can_acquire(c):
		ready_time = 0.0
		status = "NO SEEKER LOCK"
		return
	ready_time += delta
	var acquisition := 0.45 if selection.current == WEAPONS.Weapon.HEAT else 0.85
	status = "READY %d/%d" % [remaining, CAPACITY] if ready_time >= acquisition else "ACQUIRING"
	if pressed and ready_time >= acquisition and _cooldown <= 0.0 and projectile_manager != null and not hardpoints.is_empty():
		_launch(c)

func can_acquire(c: Dictionary) -> bool:
	if c.is_empty() or not TRACKER.is_airborne(c) or carrier == null:
		return false
	var offset: Vector3 = c.position - carrier.global_position
	var heat: bool = selection.current == WEAPONS.Weapon.HEAT
	return offset.length() >= 100.0 and offset.length() <= (6500.0 if heat else 18000.0) and carrier.global_basis.x.angle_to(offset.normalized()) <= deg_to_rad(55.0 if heat else 65.0)

func _launch(c: Dictionary) -> void:
	var index := _side % hardpoints.size()
	_side += 1
	var muzzle := hardpoints[index].global_transform
	var flight := FLIGHT.new()
	flight.seeker = FLIGHT.Seeker.HEAT if selection.current == WEAPONS.Weapon.HEAT else FLIGHT.Seeker.RADAR
	flight.target_handle = int(c.handle)
	flight.target_provider = tracker.contact_for
	flight.radar_lock_provider = tracker.locked_handle
	var inherited: Vector3 = carrier.velocity if "velocity" in carrier else Vector3.ZERO
	_sequence += 1
	var round_data: RefCounted = projectile_manager.acquire_round()
	round_data.initialise(_sequence, muzzle.origin, muzzle.basis.x, flight.launch_velocity(muzzle.basis.x, inherited), false, null, "missile")
	round_data.flight = flight
	projectile_manager.spawn(round_data)
	remaining -= 1
	_cooldown = 0.65
	missile_fired.emit(round_data, index)
	if remaining == 0:
		_reload = RELOAD_SECONDS
