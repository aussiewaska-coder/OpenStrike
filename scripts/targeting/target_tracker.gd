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
## Forgiving on a phone, not so wide that it grabs the wrong jet.
const LOCK_TOLERANCE_DEGREES := 4.0
## The handle given to a lock on a building or a patch of dirt: those are not
## entities and have no handle of their own.
const FALLBACK_HANDLE := -2

var _contacts := {}
var _range_m: float = RADAR_RANGES_M[DEFAULT_RANGE_INDEX]
var _origin := Vector3.ZERO
var _origin_velocity := Vector3.ZERO
var _forward := Vector3.FORWARD
var _locked_handle := -1
var _locked_fallback := {}


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
	_refresh_lock()


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


func locked_handle() -> int:
	return _locked_handle


func locked() -> Dictionary:
	if _locked_handle < 0 and _locked_handle != FALLBACK_HANDLE:
		return {}
	if _contacts.has(_locked_handle):
		return _contacts[_locked_handle]
	if not _locked_fallback.is_empty() and int(_locked_fallback["handle"]) == _locked_handle:
		return _locked_fallback
	return {}


func locked_position():
	var c := locked()
	return null if c.is_empty() else c["position"]


func clear_lock() -> void:
	_locked_handle = -1
	_locked_fallback = {}


## The press. A contact close enough to the ray wins; otherwise the world does,
## which is how "press that jet" and "press that building" are one gesture.
## `fallback_point` is a Vector3 or null when the ray hit nothing at all.
func lock_at(
	ray_origin: Vector3,
	ray_direction: Vector3,
	fallback_point,
	fallback_kind: int,
	fallback_name: String
) -> int:
	var direction := ray_direction.normalized()
	var best := -1
	var best_angle := deg_to_rad(LOCK_TOLERANCE_DEGREES)
	for c in tracked():
		var offset: Vector3 = (c["position"] as Vector3) - ray_origin
		if offset.length_squared() < 1e-6:
			continue
		var angle := direction.angle_to(offset.normalized())
		if angle < best_angle:
			best_angle = angle
			best = int(c["handle"])
	if best >= 0:
		_locked_fallback = {}
		_locked_handle = best
		return best
	if fallback_point == null:
		clear_lock()
		return -1
	_locked_fallback = contact(
		FALLBACK_HANDLE, fallback_kind, fallback_point, Vector3.ZERO, fallback_name
	)
	_locked_handle = FALLBACK_HANDLE
	return FALLBACK_HANDLE


## For the controller, which has no screen to press.
func cycle_lock() -> int:
	var list := tracked()
	if list.is_empty():
		clear_lock()
		return -1
	var index := -1
	for i in range(list.size()):
		if int(list[i]["handle"]) == _locked_handle:
			index = i
			break
	_locked_fallback = {}
	_locked_handle = int(list[(index + 1) % list.size()]["handle"])
	return _locked_handle


## Metres per second along the line of sight, positive closing. Our own motion
## counts: running a target down is a closure even when it is fleeing.
func closure_of(handle: int) -> float:
	var c: Dictionary = _contacts.get(handle, {})
	if c.is_empty():
		if _locked_fallback.is_empty() or int(_locked_fallback["handle"]) != handle:
			return 0.0
		c = _locked_fallback
	var offset: Vector3 = (c["position"] as Vector3) - _origin
	if offset.length_squared() < 1e-6:
		return 0.0
	var relative: Vector3 = (c["velocity"] as Vector3) - _origin_velocity
	return -relative.dot(offset.normalized())


## A lock is broken by death or by distance, and by nothing else -- notably not
## by looking away, and not by cycling the scope in. The break range is the
## LARGEST range the scope offers, so zooming in never costs you a target.
func _refresh_lock() -> void:
	if _locked_handle == -1:
		return
	var c := locked()
	if c.is_empty():
		clear_lock()
		return
	var break_range: float = RADAR_RANGES_M[RADAR_RANGES_M.size() - 1]
	if (c["position"] as Vector3).distance_to(_origin) > break_range:
		clear_lock()
