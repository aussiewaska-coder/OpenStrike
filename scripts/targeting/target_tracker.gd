extends RefCounted

## What is out there, and which of it is yours.
##
## Pure: no nodes, no camera, no scene tree. Sources push their contacts in each
## frame; the scope asks for `tracked()`, the visor asks for `boxed()`, and the
## weapons ask for the lock. Nothing else in the game holds target state, which
## is the whole point -- a lock that lived in two places would drift.

enum Kind {AIR_JET, AIR_DRONE, GROUND_LAUNCHER, BUILDING, GROUND_POINT}

const RADAR_RANGES_M := [5000.0, 10000.0, 20000.0, 40000.0]
const DEFAULT_RANGE_INDEX := 1
## What a visor plausibly boxes. Wider than this and the glass is a mess.
const TRACK_CONE_DEGREES := 60.0
## A squadron plus a few landmarks, not a city.
const MAX_TRACKED_BOXES := 12

var _contacts := {}
var _range_m: float = RADAR_RANGES_M[DEFAULT_RANGE_INDEX]
var _origin := Vector3.ZERO
var _origin_velocity := Vector3.ZERO
var _forward := Vector3.FORWARD


static func contact(
	handle: int,
	kind: int,
	position: Vector3,
	velocity := Vector3.ZERO,
	name := ""
) -> Dictionary:
	return {
		"handle": handle,
		"kind": kind,
		"position": position,
		"velocity": velocity,
		"name": name,
	}


func set_range(metres: float) -> void:
	_range_m = maxf(metres, 1.0)


func range_m() -> float:
	return _range_m


## The contact set is replaced wholesale each frame: the sources are the truth,
## and a contact that stopped being reported has stopped existing.
func update(contacts: Array, origin: Vector3, forward: Vector3, origin_velocity: Vector3) -> void:
	_origin = origin
	_origin_velocity = origin_velocity
	_forward = forward.normalized() if forward.length_squared() > 1e-9 else Vector3.FORWARD
	_contacts.clear()
	for c in contacts:
		_contacts[int(c["handle"])] = c


## All-aspect, nearest first. What the scope draws.
func tracked() -> Array:
	var out := []
	for handle in _contacts:
		var c: Dictionary = _contacts[handle]
		if (c["position"] as Vector3).distance_to(_origin) <= _range_m:
			out.append(c)
	out.sort_custom(_nearer)
	return out


## Narrowed to the forward cone and capped. What the visor boxes.
func boxed() -> Array:
	var limit := deg_to_rad(TRACK_CONE_DEGREES)
	var out := []
	for c in tracked():
		if angle_to(c["position"]) <= limit:
			out.append(c)
		if out.size() >= MAX_TRACKED_BOXES:
			break
	return out


func angle_to(position: Vector3) -> float:
	var offset: Vector3 = position - _origin
	if offset.length_squared() < 1e-6:
		return 0.0
	return _forward.angle_to(offset.normalized())


func _nearer(a: Dictionary, b: Dictionary) -> bool:
	return (
		(a["position"] as Vector3).distance_squared_to(_origin)
		< (b["position"] as Vector3).distance_squared_to(_origin)
	)
