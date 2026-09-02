extends Node3D

## Unguided rockets off the wing hardpoints, modelled on cannon_weapon.gd.
##
## The one thing that matters for how a salvo reads: rockets leave ONE AT A
## TIME, alternating sides. Emptying the pod in a frame gives a single puff of
## smoke and no sense of a salvo; a ripple gives the row of diverging trails
## that is the whole reason for the effect.

const ROCKET_FLIGHT := preload("res://scripts/weapons/rocket_flight.gd")
const WEAPON_SELECTION := preload("res://scripts/weapons/weapon_selection.gd")

signal rocket_fired(round_data: RefCounted, hardpoint_index: int)
signal magazine_changed(remaining: int, capacity: int)

## Enough for a long salvo without becoming an infinite hose.
const POD_CAPACITY := 14
## Gap between launches. Fast enough to feel like a salvo, slow enough that the
## trails separate instead of merging into one smear.
const RIPPLE_INTERVAL := 0.11
## Automatic, because there is no free face button left to ask for it and an
## enforced pause gives the weapon a rhythm.
const RELOAD_SECONDS := 3.4

var projectile_manager: Node3D
var carrier: Node3D
var hardpoints: Array[Node3D] = []
var selection: RefCounted

var rockets_remaining := POD_CAPACITY
var is_reloading := false

var _since_last_launch := RIPPLE_INTERVAL
var _reload_remaining := 0.0
var _next_hardpoint := 0
var _sequence := 0


func can_fire() -> bool:
	if is_reloading or rockets_remaining <= 0:
		return false
	if projectile_manager == null or hardpoints.is_empty():
		return false
	if selection != null and selection.current != WEAPON_SELECTION.Weapon.ROCKETS:
		return false
	return true


## Driven by the owner rather than _physics_process, so the tests can step time
## directly and the pod cannot fire while the game is paused.
func update(delta: float, trigger_held: bool) -> void:
	if is_reloading:
		_reload_remaining -= delta
		if _reload_remaining <= 0.0:
			is_reloading = false
			rockets_remaining = POD_CAPACITY
			magazine_changed.emit(rockets_remaining, POD_CAPACITY)
		return
	_since_last_launch += delta
	if not trigger_held or not can_fire():
		return
	if _since_last_launch < RIPPLE_INTERVAL:
		return
	_since_last_launch = 0.0
	_launch()
	if rockets_remaining <= 0:
		is_reloading = true
		_reload_remaining = RELOAD_SECONDS


func _launch() -> void:
	var index := _next_hardpoint % hardpoints.size()
	# Alternate before anything below can fail, so a bad hardpoint cannot pin
	# every rocket to one wing.
	_next_hardpoint = (_next_hardpoint + 1) % hardpoints.size()
	var hardpoint := hardpoints[index]
	var muzzle := hardpoint.global_transform
	var direction := muzzle.basis.x.normalized()
	var inherited: Vector3 = carrier.velocity if carrier != null and "velocity" in carrier else Vector3.ZERO
	var flight = ROCKET_FLIGHT.new()
	_sequence += 1
	var round_data: RefCounted = projectile_manager.acquire_round()
	round_data.initialise(
		_sequence,
		muzzle.origin,
		direction,
		flight.launch_velocity(direction, inherited),
		false,
		null,
		"rocket"
	)
	round_data.flight = flight
	projectile_manager.spawn(round_data)
	rockets_remaining -= 1
	rocket_fired.emit(round_data, index)
	magazine_changed.emit(rockets_remaining, POD_CAPACITY)
