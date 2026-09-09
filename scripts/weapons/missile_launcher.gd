extends Node3D

const FLIGHT := preload("res://scripts/weapons/missile_flight.gd")
const WEAPONS := preload("res://scripts/weapons/weapon_selection.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const GROUND_FLIGHT := preload("res://scripts/weapons/guided_ground_flight.gd")
const BOMB_DAMAGE := preload("res://scripts/weapons/bomb_damage_profile.gd")
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
	if selection == null or not WEAPONS.is_guided(selection.current):
		ready_time = 0.0
		status = "NO LOCK"
		return
	var c: Dictionary = tracker.locked() if tracker != null else {}
	var handle := int(c.get("handle", -1))
	if handle != _acquiring_handle or selection.current != _acquiring_weapon:
		ready_time = 0.0
		_acquiring_handle = handle
		_acquiring_weapon = selection.current
	if not can_acquire(c):
		ready_time = 0.0
		status = launch_problem(c)
		return
	ready_time += delta
	status = "READY %d/%d" % [remaining, CAPACITY] if is_ready() else ("COOLDOWN" if _cooldown > 0.0 else "ACQUIRING")
	if pressed and is_ready() and projectile_manager != null and not hardpoints.is_empty():
		_launch(c)
		status = "RELOADING" if _reload > 0.0 else "COOLDOWN"


func acquisition_seconds() -> float:
	if selection != null and WEAPONS.is_ground(selection.current):
		return 0.6
	return 0.45 if selection != null and selection.current == WEAPONS.Weapon.HEAT else 0.85


func is_ready() -> bool:
	if selection == null or not WEAPONS.is_guided(selection.current):
		return false
	if selection.current != _acquiring_weapon or tracker == null or tracker.locked_handle() != _acquiring_handle:
		return false
	return (
		can_acquire(tracker.locked()) and remaining > 0
		and _reload <= 0.0 and _cooldown <= 0.0
		and ready_time >= acquisition_seconds()
	)


## The reticle consumes seeker state, never guesses readiness from target lock.
func seeker_state() -> Dictionary:
	if selection == null or not WEAPONS.is_guided(selection.current):
		return {}
	return {
		"handle": _acquiring_handle,
		"progress": clampf(ready_time / acquisition_seconds(), 0.0, 1.0),
		"ready": is_ready(),
		"status": status,
		"fire_label": "RELEASE BOMB" if selection.current == WEAPONS.Weapon.GUIDED_BOMB else "MISSILE LOCK - FIRE",
	}

func can_acquire(c: Dictionary) -> bool:
	return launch_problem(c).is_empty()

func launch_problem(c: Dictionary) -> String:
	if carrier == null or selection == null:
		return "NO CARRIER"
	if WEAPONS.is_ground(selection.current):
		var inherited: Vector3 = carrier.velocity if "velocity" in carrier else Vector3.ZERO
		return GROUND_FLIGHT.launch_problem(c, carrier.global_position, carrier.global_basis.x, inherited, selection.current == WEAPONS.Weapon.GROUND_MISSILE)
	if c.is_empty() or not TRACKER.is_airborne(c):
		return "SELECT AIR TARGET"
	var offset: Vector3 = c.position - carrier.global_position
	var heat: bool = selection.current == WEAPONS.Weapon.HEAT
	if offset.length() < 100.0 or offset.length() > (6500.0 if heat else 18000.0):
		return "OUT OF RANGE"
	return "" if carrier.global_basis.x.angle_to(offset.normalized()) <= deg_to_rad(55.0 if heat else 65.0) else "TURN TOWARD TARGET"

func _launch(c: Dictionary) -> void:
	var index := _side % hardpoints.size()
	_side += 1
	var muzzle := hardpoints[index].global_transform
	var ground := WEAPONS.is_ground(selection.current)
	var flight: RefCounted = GROUND_FLIGHT.new() if ground else FLIGHT.new()
	if ground:
		flight.powered = selection.current == WEAPONS.Weapon.GROUND_MISSILE
		flight.target_position = c.position
		flight.target_name = c.get("name", "GROUND TARGET")
	else:
		flight.seeker = FLIGHT.Seeker.HEAT if selection.current == WEAPONS.Weapon.HEAT else FLIGHT.Seeker.RADAR
		flight.radar_lock_provider = tracker.locked_handle
	flight.target_handle = int(c.handle)
	flight.target_provider = tracker.contact_for
	var inherited: Vector3 = carrier.velocity if "velocity" in carrier else Vector3.ZERO
	_sequence += 1
	var round_data: RefCounted = projectile_manager.acquire_round()
	var source := "guided_bomb" if selection.current == WEAPONS.Weapon.GUIDED_BOMB else "missile"
	round_data.initialise(_sequence, muzzle.origin, muzzle.basis.x, flight.launch_velocity(muzzle.basis.x, inherited), false, BOMB_DAMAGE.new() if ground else null, source)
	round_data.flight = flight
	projectile_manager.spawn(round_data)
	remaining -= 1
	_cooldown = 0.65
	missile_fired.emit(round_data, index)
	if remaining == 0:
		_reload = RELOAD_SECONDS
