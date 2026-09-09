# Helmet HUD and Targeting (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the F-22 an F-35 pilot's visor — symbology welded to the world, one target lock every consumer agrees about, a translucent scope that fades to its rim, and enemy Raptor squadrons worth pointing it all at.

**Architecture:** One pure `TargetTracker` owns all target state; the visor, the scope and the weapons read it and nothing else holds it. Conformal symbols are computed as **world directions** by a pure `hud_projection` helper and turned into screen points by `Camera3D.unproject_position` inside the `Control` — that split is what makes a head-up display unit-testable without a viewport. Enemy jets are kinematic variants of the existing drone state machine, reusing `drone_field.gd`'s spawn, hit-index and destruction machinery wholesale.

**Tech Stack:** Godot 4.7.2, GDScript, GL Compatibility renderer, Android arm64. No new addons, no new assets, no new shaders.

**Spec:** `docs/superpowers/specs/2026-09-04-helmet-hud-targeting-design.md`

## Global Constraints

- **Branch:** `look-polish`. Do not merge to `main` in this plan.
- **Renderer:** GL Compatibility. Volumetric fog, SSR, decals and GPU particles draw nothing — never reach for them.
- **The HUD is drawn, never themed.** No textures, no fonts beyond `ThemeDB.fallback_font`. Every element is a line, an arc or a polygon. Both `attack_reticle.gd` and `radar_scope.gd` state this rule in their headers; keep it.
- **Enemy aircraft are kinematic, not aerodynamic.** `drone.gd` explains why and it still holds: ten flight models on a phone are paid for in framerate.
- **Test idiom:** every test is `extends SceneTree`, runs named methods from `_init()`, calls a `_fail(message)` helper that does `push_error` then `quit(1)`, and on success prints `<NAME>_TEST_PASS` then `quit()`.
- **Run a test:** `godot --headless --script tests/<name>_test.gd` (the binary on this machine is `Godot_v4.7.2-stable_linux.arm64`).
- **A test "passing" is not enough — grep the output for `ERROR:` too.** On HEAD, `aero_model`, `bomb_flight`, `drone` and `trail_buffer` print `PASS` *after* an assertion error. Those four are pre-existing and are **not** this plan's to fix; do not be alarmed by them and do not touch them.
- **Colours:** HMDS green `Color(0.45, 1.0, 0.6)`, lock amber `Color(1.0, 0.72, 0.25)`. Both already exist in `attack_reticle.gd`.
- **Comment voice:** the codebase explains *why*, not *what*, in full sentences. Match it.

---

### Task 1: TargetTracker — contacts, range, and what is worth drawing

**Files:**
- Create: `scripts/targeting/target_tracker.gd`
- Test: `tests/target_tracker_test.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `TargetTracker.Kind` — enum `{AIR_JET, AIR_DRONE, GROUND_LAUNCHER, BUILDING, GROUND_POINT}`
  - `TargetTracker.RADAR_RANGES_M: Array[float]` — `[5000.0, 10000.0, 20000.0, 40000.0]`
  - `static contact(handle: int, kind: int, position: Vector3, velocity := Vector3.ZERO, name := "") -> Dictionary`
  - `update(contacts: Array, origin: Vector3, forward: Vector3, origin_velocity: Vector3) -> void`
  - `set_range(metres: float) -> void`, `range_m() -> float`
  - `tracked() -> Array`, `boxed() -> Array`, `angle_to(position: Vector3) -> float`

- [ ] **Step 1: Write the failing test**

Create `tests/target_tracker_test.gd`:

```gdscript
extends SceneTree

## The tracker's two answers differ on purpose: the scope sees all round, the
## visor only boxes what is in front. Everything else here is bookkeeping --
## nearest first, and nothing beyond the selected range.

const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

var _failed := false


func _init() -> void:
	_tracks_all_aspect_within_range()
	_drops_contacts_beyond_range()
	_boxes_only_the_forward_cone()
	_caps_the_boxes()
	_orders_nearest_first()
	_range_follows_the_scope()
	if _failed:
		return
	print("TARGET_TRACKER_TEST_PASS")
	quit()


## Nose along -Z. A contact behind is still tracked -- a scope that only saw
## forward would not be a scope.
func _tracks_all_aspect_within_range() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, 2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.tracked().size() != 2:
		_fail("a contact behind the aircraft is still a contact, got %d" % tracker.tracked().size())


func _drops_contacts_beyond_range() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -40000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.tracked().size() != 1:
		_fail("the default 10 km range must exclude a 40 km contact")


func _boxes_only_the_forward_cone() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, 2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	var boxed: Array = tracker.boxed()
	if boxed.size() != 1:
		_fail("only the contact in front earns a box, got %d" % boxed.size())
	if int(boxed[0]["handle"]) != 1:
		_fail("the boxed contact must be the one ahead")
	for c in boxed:
		if not tracker.tracked().has(c):
			_fail("boxed must be a subset of tracked")


func _caps_the_boxes() -> void:
	var tracker = TRACKER.new()
	var many := []
	for i in range(40):
		many.append(TRACKER.contact(i, TRACKER.Kind.AIR_DRONE, Vector3(0.0, 0.0, -100.0 - float(i))))
	tracker.update(many, Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.boxed().size() != TRACKER.MAX_TRACKED_BOXES:
		_fail("a city plus a squadron must not become noise, got %d boxes" % tracker.boxed().size())


func _orders_nearest_first() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -4000.0)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -1000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if int(tracker.tracked()[0]["handle"]) != 2:
		_fail("nearest must come first")


## Cycling the scope out must genuinely reveal contacts, not redraw the same
## ten kilometres of them at a smaller scale.
func _range_follows_the_scope() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -25000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.tracked().size() != 0:
		_fail("25 km is outside the default range")
	tracker.set_range(TRACKER.RADAR_RANGES_M[3])
	if tracker.tracked().size() != 1:
		_fail("40 km selected must reveal a 25 km contact")


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --script tests/target_tracker_test.gd`
Expected: FAIL — the preload cannot resolve `res://scripts/targeting/target_tracker.gd`.

- [ ] **Step 3: Write the implementation**

Create `scripts/targeting/target_tracker.gd`:

```gdscript
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --script tests/target_tracker_test.gd`
Expected: `TARGET_TRACKER_TEST_PASS`, and no line containing `ERROR:`.

- [ ] **Step 5: Commit**

```bash
git add scripts/targeting/target_tracker.gd tests/target_tracker_test.gd
git commit -m "Track what is out there, all round and in front"
```

---

### Task 2: The lock — pressing one, keeping it, and how fast it is closing

**Files:**
- Modify: `scripts/targeting/target_tracker.gd`
- Modify: `tests/target_tracker_test.gd`

**Interfaces:**
- Consumes: everything Task 1 produced.
- Produces:
  - `TargetTracker.LOCK_TOLERANCE_DEGREES: float` — `4.0`
  - `TargetTracker.FALLBACK_HANDLE: int` — `-2`
  - `lock_at(ray_origin: Vector3, ray_direction: Vector3, fallback_point, fallback_kind: int, fallback_name: String) -> int` — `fallback_point` is a `Vector3` or `null`. Returns the locked handle, or `-1`.
  - `locked() -> Dictionary` — `{}` when nothing is locked
  - `locked_handle() -> int`, `locked_position()` (`Vector3` or `null`)
  - `cycle_lock() -> int`, `clear_lock() -> void`
  - `closure_of(handle: int) -> float` — metres per second, positive closing

- [ ] **Step 1: Write the failing test**

Append these methods to `tests/target_tracker_test.gd`, and add the six calls to `_init()` immediately before the `if _failed:` line:

```gdscript
	_locks_the_contact_nearest_the_ray()
	_falls_back_to_the_world_when_nothing_is_close()
	_lock_survives_leaving_the_cone()
	_lock_breaks_on_destruction()
	_zooming_the_scope_in_keeps_the_lock()
	_closure_is_positive_closing()
	_cycle_walks_the_tracked_contacts()
```

```gdscript
func _locks_the_contact_nearest_the_ray() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(600.0, 0.0, -2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	var handle: int = tracker.lock_at(
		Vector3.ZERO, Vector3(0.0, 0.0, -1.0), null, TRACKER.Kind.GROUND_POINT, ""
	)
	if handle != 1:
		_fail("the ray points at contact 1, got %d" % handle)
	if int(tracker.locked()["handle"]) != 1:
		_fail("the locked contact must be readable back")


## Press the dirt and you get the dirt. One gesture, two outcomes.
func _falls_back_to_the_world_when_nothing_is_close() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(5000.0, 0.0, -2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	var handle: int = tracker.lock_at(
		Vector3.ZERO, Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, -900.0),
		TRACKER.Kind.BUILDING, "Q1"
	)
	if handle != TRACKER.FALLBACK_HANDLE:
		_fail("with no contact near the ray the world is the target, got %d" % handle)
	if String(tracker.locked()["name"]) != "Q1":
		_fail("the fallback keeps the name it was given")
	if not (tracker.locked_position() as Vector3).is_equal_approx(Vector3(0.0, 0.0, -900.0)):
		_fail("the fallback keeps the point it was given")


## A lock that dropped every time you manoeuvred would be worse than no lock.
func _lock_survives_leaving_the_cone() -> void:
	var tracker = TRACKER.new()
	var behind := TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0))
	tracker.update([behind], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	tracker.lock_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), null, TRACKER.Kind.GROUND_POINT, "")
	# Same contact, but the aircraft has turned its back on it.
	tracker.update([behind], Vector3.ZERO, Vector3.BACK, Vector3.ZERO)
	if tracker.locked_handle() != 1:
		_fail("turning away must not break the lock")
	if not tracker.boxed().is_empty():
		_fail("but it is no longer boxed on the glass")


func _lock_breaks_on_destruction() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	tracker.lock_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), null, TRACKER.Kind.GROUND_POINT, "")
	tracker.update([], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.locked_handle() != -1:
		_fail("a contact that stopped being reported is dead, and the lock goes with it")


## Zooming in to 5 km must not throw away a lock held at 8.
func _zooming_the_scope_in_keeps_the_lock() -> void:
	var tracker = TRACKER.new()
	var far := TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -8000.0))
	tracker.update([far], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	tracker.lock_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), null, TRACKER.Kind.GROUND_POINT, "")
	tracker.set_range(TRACKER.RADAR_RANGES_M[0])
	tracker.update([far], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.locked_handle() != 1:
		_fail("the lock breaks at the largest range, not the selected one")


func _closure_is_positive_closing() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		# Ahead, flying toward us.
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0), Vector3(0.0, 0.0, 200.0)),
		# Ahead, running away.
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2500.0), Vector3(0.0, 0.0, -200.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.closure_of(1) <= 0.0:
		_fail("a contact flying at us is closing, got %f" % tracker.closure_of(1))
	if tracker.closure_of(2) >= 0.0:
		_fail("a contact running away is opening, got %f" % tracker.closure_of(2))
	# Our own speed counts: chasing the runner turns it into a closure.
	tracker.update([
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2500.0), Vector3(0.0, 0.0, -200.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3(0.0, 0.0, -400.0))
	if tracker.closure_of(2) <= 0.0:
		_fail("running it down is a closure, got %f" % tracker.closure_of(2))


func _cycle_walks_the_tracked_contacts() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -1000.0)),
		TRACKER.contact(2, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.cycle_lock() != 1:
		_fail("the first cycle takes the nearest")
	if tracker.cycle_lock() != 2:
		_fail("the second cycle steps out")
	if tracker.cycle_lock() != 1:
		_fail("and it wraps")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --script tests/target_tracker_test.gd`
Expected: FAIL — `lock_at` is not declared on the tracker.

- [ ] **Step 3: Write the implementation**

Add to `scripts/targeting/target_tracker.gd`. Put the two constants beside the existing ones, the variables beside the existing ones, and the methods after `angle_to`:

```gdscript
## Forgiving on a phone, not so wide that it grabs the wrong jet.
const LOCK_TOLERANCE_DEGREES := 4.0
## The handle given to a lock on a building or a patch of dirt: those are not
## entities and have no handle of their own.
const FALLBACK_HANDLE := -2

var _locked_handle := -1
var _locked_fallback := {}
```

```gdscript
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
```

Then, at the very end of `update()`, add the lock refresh:

```gdscript
	_refresh_lock()
```

and the method itself:

```gdscript
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --script tests/target_tracker_test.gd`
Expected: `TARGET_TRACKER_TEST_PASS`, no `ERROR:` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/targeting/target_tracker.gd tests/target_tracker_test.gd
git commit -m "Press one and it is yours, until it dies or leaves"
```

---

### Task 3: Conformal projection — the directions the visor's symbols live along

**Files:**
- Create: `scripts/ui/hud_projection.gd`
- Test: `tests/hud_projection_test.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `HudProjection.CONFORMAL_DISTANCE_M: float` — `50000.0`
  - `HudProjection.PITCH_LADDER_STEP_DEGREES: float` — `5.0`
  - `HudProjection.FPM_MIN_SPEED_MPS: float` — `20.0`
  - `static level_forward(basis: Basis) -> Vector3`
  - `static level_right(basis: Basis) -> Vector3`
  - `static horizon_points(basis: Basis, origin: Vector3) -> Array` — two `Vector3`
  - `static ladder_direction(basis: Basis, degrees: float) -> Vector3`
  - `static ladder_degrees() -> PackedFloat32Array`
  - `static flight_path_direction(velocity: Vector3, basis: Basis) -> Vector3`
  - `static far_point(origin: Vector3, direction: Vector3) -> Vector3`

- [ ] **Step 1: Write the failing test**

Create `tests/hud_projection_test.gd`:

```gdscript
extends SceneTree

## The visor's symbols are world directions, not screen positions. Keeping the
## maths on this side of the line is what lets a head-up display be tested
## without a viewport: the Control only has to call unproject_position on what
## these functions return.

const HUD := preload("res://scripts/ui/hud_projection.gd")

var _failed := false


func _init() -> void:
	_horizon_is_level_whatever_the_attitude()
	_horizon_spans_the_view()
	_climb_bars_are_above_and_dive_bars_below()
	_the_ladder_covers_the_sphere()
	_the_flight_path_marker_follows_the_velocity()
	_a_parked_aircraft_puts_the_marker_on_the_nose()
	if _failed:
		return
	print("HUD_PROJECTION_TEST_PASS")
	quit()


## Whatever the aircraft is doing, the horizon is at the aircraft's altitude.
## The cant you see on the glass comes from the camera, not from this.
func _horizon_is_level_whatever_the_attitude() -> void:
	var origin := Vector3(0.0, 1500.0, 0.0)
	for attitude in [
		Basis.IDENTITY,
		Basis(Vector3.FORWARD, deg_to_rad(45.0)),
		Basis(Vector3.RIGHT, deg_to_rad(30.0)),
	]:
		var points: Array = HUD.horizon_points(attitude, origin)
		for p in points:
			if not is_equal_approx((p as Vector3).y, origin.y):
				_fail("the horizon must sit at the camera's altitude, got %f" % (p as Vector3).y)


func _horizon_spans_the_view() -> void:
	var points: Array = HUD.horizon_points(Basis.IDENTITY, Vector3.ZERO)
	if points.size() != 2:
		_fail("a horizon is a line, so it is two points")
	var span: float = (points[0] as Vector3).distance_to(points[1] as Vector3)
	if not is_equal_approx(span, HUD.CONFORMAL_DISTANCE_M * 2.0):
		_fail("the horizon must reach past anything drawn, got %f" % span)


## Godot's forward is -Z and up is +Y. A climb bar points up.
func _climb_bars_are_above_and_dive_bars_below() -> void:
	var up: Vector3 = HUD.ladder_direction(Basis.IDENTITY, 30.0)
	if up.y <= 0.0:
		_fail("the +30 bar must point above the horizon, got %v" % up)
	var down: Vector3 = HUD.ladder_direction(Basis.IDENTITY, -30.0)
	if down.y >= 0.0:
		_fail("the -30 bar must point below the horizon, got %v" % down)
	var level: Vector3 = HUD.ladder_direction(Basis.IDENTITY, 0.0)
	if not is_zero_approx(level.y):
		_fail("the zero bar is the horizon itself, got %v" % level)
	if not is_equal_approx(up.length(), 1.0):
		_fail("directions must be unit length")


func _the_ladder_covers_the_sphere() -> void:
	var degrees: PackedFloat32Array = HUD.ladder_degrees()
	if degrees[0] > -90.0 or degrees[degrees.size() - 1] < 90.0:
		_fail("the ladder must run from straight down to straight up")
	if not is_equal_approx(degrees[1] - degrees[0], HUD.PITCH_LADDER_STEP_DEGREES):
		_fail("bars must be evenly spaced")


## Where the jet is actually going, which is not where the nose points.
func _the_flight_path_marker_follows_the_velocity() -> void:
	var climbing := Vector3(0.0, 100.0, -200.0)
	var marker: Vector3 = HUD.flight_path_direction(climbing, Basis.IDENTITY)
	if marker.y <= 0.0:
		_fail("a climbing jet puts the marker above the horizon, got %v" % marker)
	if not marker.is_equal_approx(climbing.normalized()):
		_fail("the marker is the velocity, normalised")


func _a_parked_aircraft_puts_the_marker_on_the_nose() -> void:
	var marker: Vector3 = HUD.flight_path_direction(Vector3(0.0, 0.0, -1.0), Basis.IDENTITY)
	if not marker.is_equal_approx(Vector3(0.0, 0.0, -1.0)):
		_fail("below the speed floor the marker parks on the boresight, got %v" % marker)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --script tests/hud_projection_test.gd`
Expected: FAIL — `res://scripts/ui/hud_projection.gd` does not exist.

- [ ] **Step 3: Write the implementation**

Create `scripts/ui/hud_projection.gd`:

```gdscript
extends RefCounted

## Where the visor's conformal symbols live, expressed as world directions.
##
## The helmet's trick is that the horizon, the ladder and the flight path marker
## are stuck to the WORLD, not to the screen: swing the view and they stay put.
## The cheapest way to get that is to compute a world point for each symbol and
## let `Camera3D.unproject_position` do the rest. Keeping the world half here,
## pure and static, is what makes a head-up display testable without a viewport.

## Far enough to read as infinity. Only ever unprojected, never rendered, so it
## is free to sit outside the 30 km far plane.
const CONFORMAL_DISTANCE_M := 50000.0
const PITCH_LADDER_STEP_DEGREES := 5.0
## Below this the velocity vector is noise, and the marker parks on the nose.
const FPM_MIN_SPEED_MPS := 20.0


## The camera's forward flattened onto the horizontal plane: the direction the
## horizon runs across, and the axis the ladder climbs from.
static func level_forward(basis: Basis) -> Vector3:
	var forward := -basis.z
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 1e-6:
		# Straight up or straight down: the forward vector has no horizontal
		# part left, so borrow the camera's own up, which does.
		var up := basis.y
		flat = Vector3(up.x, 0.0, up.z)
	if flat.length_squared() < 1e-6:
		return Vector3.FORWARD
	return flat.normalized()


static func level_right(basis: Basis) -> Vector3:
	return level_forward(basis).cross(Vector3.UP).normalized()


static func far_point(origin: Vector3, direction: Vector3) -> Vector3:
	return origin + direction.normalized() * CONFORMAL_DISTANCE_M


## Two points at the camera's own altitude, left and right. Because they are
## level and far away, the line between them projects onto the true horizon --
## it cants under roll and slides under pitch without being told to.
static func horizon_points(basis: Basis, origin: Vector3) -> Array:
	var right := level_right(basis)
	return [
		origin - right * CONFORMAL_DISTANCE_M,
		origin + right * CONFORMAL_DISTANCE_M,
	]


static func ladder_direction(basis: Basis, degrees: float) -> Vector3:
	return level_forward(basis).rotated(level_right(basis), deg_to_rad(degrees)).normalized()


static func ladder_degrees() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var degrees := -90.0
	while degrees <= 90.0 + 0.001:
		out.append(degrees)
		degrees += PITCH_LADDER_STEP_DEGREES
	return out


static func flight_path_direction(velocity: Vector3, basis: Basis) -> Vector3:
	if velocity.length() < FPM_MIN_SPEED_MPS:
		return (-basis.z).normalized()
	return velocity.normalized()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --script tests/hud_projection_test.gd`
Expected: `HUD_PROJECTION_TEST_PASS`, no `ERROR:` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/hud_projection.gd tests/hud_projection_test.gd
git commit -m "Weld the horizon to the world, not to the glass"
```

---

### Task 4: The visor — drawing the helmet

**Files:**
- Create: `scripts/ui/helmet_hud.gd`
- Test: `tests/helmet_hud_test.gd`

**Interfaces:**
- Consumes: `HudProjection` (Task 3), `TargetTracker.Kind` (Task 1).
- Produces:
  - `HelmetHud.set_state(camera: Camera3D, velocity: Vector3, boxed: Array, locked: Dictionary, closure_mps: float, instruments: Dictionary) -> void` — `instruments` keys: `speed_mps`, `altitude_m`, `heading_degrees`, `g_load`, `mach`
  - `static box_half_extent_px(range_m: float) -> float`
  - `static closure_text(mps: float) -> String`
  - `static kind_label(kind: int) -> String`

- [ ] **Step 1: Write the failing test**

Create `tests/helmet_hud_test.gd`:

```gdscript
extends SceneTree

## Drawing cannot be asserted headless, so what is asserted is the arithmetic
## the drawing leans on: a box shrinks with range but never vanishes, and a
## closure reads with its sign so a glance tells you whether you are gaining.

const HELMET := preload("res://scripts/ui/helmet_hud.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

var _failed := false


func _init() -> void:
	_boxes_shrink_with_range()
	_boxes_never_vanish()
	_closure_reads_with_its_sign()
	_every_kind_has_a_label()
	if _failed:
		return
	print("HELMET_HUD_TEST_PASS")
	quit()


func _boxes_shrink_with_range() -> void:
	var near: float = HELMET.box_half_extent_px(500.0)
	var far: float = HELMET.box_half_extent_px(8000.0)
	if near <= far:
		_fail("a nearer target draws a bigger box, got %f then %f" % [near, far])


func _boxes_never_vanish() -> void:
	var absurd: float = HELMET.box_half_extent_px(1.0e9)
	if absurd < HELMET.BOX_MIN_PX:
		_fail("a box floors instead of disappearing, got %f" % absurd)
	var touching: float = HELMET.box_half_extent_px(0.0)
	if touching > HELMET.BOX_MAX_PX:
		_fail("a box ceilings instead of filling the screen, got %f" % touching)


## Positive is closing. A pilot reads the sign before the number.
func _closure_reads_with_its_sign() -> void:
	if not HELMET.closure_text(120.0).begins_with("+"):
		_fail("closing must be signed positive, got %s" % HELMET.closure_text(120.0))
	if not HELMET.closure_text(-120.0).begins_with("-"):
		_fail("opening must be signed negative, got %s" % HELMET.closure_text(-120.0))


func _every_kind_has_a_label() -> void:
	var seen := {}
	for kind in TRACKER.Kind.values():
		var label: String = HELMET.kind_label(kind)
		if label.is_empty():
			_fail("kind %d has no label" % kind)
		seen[label] = true
	if seen.size() != TRACKER.Kind.size():
		_fail("every kind must be told apart by its label")


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --script tests/helmet_hud_test.gd`
Expected: FAIL — `res://scripts/ui/helmet_hud.gd` does not exist.

- [ ] **Step 3: Write the implementation**

Create `scripts/ui/helmet_hud.gd`:

```gdscript
extends Control

## The visor.
##
## Two families of symbol, and the contrast between them is the whole effect.
## CONFORMAL symbols -- horizon, pitch ladder, flight path marker, target boxes
## -- are world points run through `unproject_position`, so they stay welded to
## the world while the view swings. SCREEN-FIXED symbols -- the speed, altitude
## and heading tapes -- do not move at all. Swing the view and half the glass
## slides while half stays put, which is what a helmet does and a panel cannot.
##
## Drawn, not themed, like the rest of this HUD: no textures, every element a
## line, an arc or a polygon.

const HUD := preload("res://scripts/ui/hud_projection.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

const GREEN := Color(0.45, 1.0, 0.6)
const AMBER := Color(1.0, 0.72, 0.25)
const LINE_WIDTH := 1.4
const LOCK_LINE_WIDTH := 2.4
const LABEL_SIZE := 12

const BOX_MAX_PX := 44.0
const BOX_MIN_PX := 7.0
## The range at which a box has shrunk to its floor.
const BOX_FALLOFF_M := 6000.0

const LADDER_HALF_LENGTH_PX := 46.0
const LADDER_GAP_PX := 16.0
const TAPE_MARGIN_PX := 26.0
const TAPE_HEIGHT_PX := 190.0
const FPM_RADIUS_PX := 8.0
const EDGE_MARGIN_PX := 34.0

var _camera: Camera3D
var _velocity := Vector3.ZERO
var _boxed: Array = []
var _locked := {}
var _closure := 0.0
var _instruments := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


static func box_half_extent_px(range_m: float) -> float:
	var t := clampf(range_m / BOX_FALLOFF_M, 0.0, 1.0)
	return lerpf(BOX_MAX_PX, BOX_MIN_PX, t)


static func closure_text(mps: float) -> String:
	return "%+d" % roundi(mps)


static func kind_label(kind: int) -> String:
	match kind:
		TRACKER.Kind.AIR_JET:
			return "JET"
		TRACKER.Kind.AIR_DRONE:
			return "DRONE"
		TRACKER.Kind.GROUND_LAUNCHER:
			return "SAM"
		TRACKER.Kind.BUILDING:
			return "BLDG"
		TRACKER.Kind.GROUND_POINT:
			return "GND"
	return "UNKNOWN"


func set_state(
	camera: Camera3D,
	velocity: Vector3,
	boxed: Array,
	locked: Dictionary,
	closure_mps: float,
	instruments: Dictionary
) -> void:
	_camera = camera
	_velocity = velocity
	_boxed = boxed
	_locked = locked
	_closure = closure_mps
	_instruments = instruments
	queue_redraw()


func _draw() -> void:
	if _camera == null:
		return
	_draw_horizon()
	_draw_ladder()
	_draw_flight_path_marker()
	_draw_boresight()
	_draw_boxes()
	_draw_lock()
	_draw_tapes()


## A world point becomes a screen point, or null when it is behind the camera.
func _screen(world: Vector3):
	if _camera.is_position_behind(world):
		return null
	return _camera.unproject_position(world)


func _draw_horizon() -> void:
	var points: Array = HUD.horizon_points(_camera.global_basis, _camera.global_position)
	var a = _screen(points[0])
	var b = _screen(points[1])
	if a == null or b == null:
		return
	draw_line(a, b, Color(GREEN, 0.85), LINE_WIDTH)


## Climb bars solid, dive bars dashed with their ends turned down toward the
## ground. That is what a real ladder does, and it is the cheapest way to tell
## a climb from a dive at a glance.
func _draw_ladder() -> void:
	var basis := _camera.global_basis
	var origin := _camera.global_position
	for degrees in HUD.ladder_degrees():
		if is_zero_approx(degrees):
			continue
		var centre = _screen(HUD.far_point(origin, HUD.ladder_direction(basis, degrees)))
		if centre == null:
			continue
		var along := _horizon_direction()
		var down := Vector2(-along.y, along.x)
		var climbing := degrees > 0.0
		var colour := Color(GREEN, 0.6)
		for side in [-1.0, 1.0]:
			var inner: Vector2 = centre + along * (LADDER_GAP_PX * side)
			var outer: Vector2 = centre + along * (LADDER_HALF_LENGTH_PX * side)
			if climbing:
				draw_line(inner, outer, colour, LINE_WIDTH)
			else:
				# Dashed: three short strokes rather than one line.
				for step in range(3):
					var t0 := float(step) / 3.0
					var t1 := t0 + 0.22
					draw_line(inner.lerp(outer, t0), inner.lerp(outer, t1), colour, LINE_WIDTH)
			# The turned-down end, on dive bars only.
			if not climbing:
				draw_line(outer, outer + down * 7.0, colour, LINE_WIDTH)
		draw_string(
			ThemeDB.fallback_font,
			centre + along * (LADDER_HALF_LENGTH_PX + 6.0) + Vector2(0.0, 4.0),
			"%d" % int(absf(degrees)),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, colour
		)


## The screen direction the horizon runs along, so ladder bars cant with it.
func _horizon_direction() -> Vector2:
	var points: Array = HUD.horizon_points(_camera.global_basis, _camera.global_position)
	var a = _screen(points[0])
	var b = _screen(points[1])
	if a == null or b == null:
		return Vector2.RIGHT
	var delta: Vector2 = (b as Vector2) - (a as Vector2)
	return delta.normalized() if delta.length_squared() > 1e-6 else Vector2.RIGHT


## The winged circle: where the aircraft is actually going, which is not where
## the nose is pointing. The single most convincing symbol on the glass.
func _draw_flight_path_marker() -> void:
	var direction: Vector3 = HUD.flight_path_direction(_velocity, _camera.global_basis)
	var at = _screen(HUD.far_point(_camera.global_position, direction))
	if at == null:
		return
	var colour := Color(GREEN, 0.95)
	draw_arc(at, FPM_RADIUS_PX, 0.0, TAU, 20, colour, LINE_WIDTH)
	draw_line(at + Vector2(-FPM_RADIUS_PX, 0.0), at + Vector2(-FPM_RADIUS_PX - 9.0, 0.0), colour, LINE_WIDTH)
	draw_line(at + Vector2(FPM_RADIUS_PX, 0.0), at + Vector2(FPM_RADIUS_PX + 9.0, 0.0), colour, LINE_WIDTH)
	draw_line(at + Vector2(0.0, -FPM_RADIUS_PX), at + Vector2(0.0, -FPM_RADIUS_PX - 7.0), colour, LINE_WIDTH)


func _draw_boresight() -> void:
	var nose := -_camera.global_basis.z
	var at = _screen(HUD.far_point(_camera.global_position, nose))
	if at == null:
		return
	var colour := Color(GREEN, 0.45)
	draw_line(at + Vector2(-6.0, 0.0), at + Vector2(6.0, 0.0), colour, LINE_WIDTH)
	draw_line(at + Vector2(0.0, -6.0), at + Vector2(0.0, 6.0), colour, LINE_WIDTH)


func _draw_boxes() -> void:
	var locked_handle := int(_locked.get("handle", -1)) if not _locked.is_empty() else -1
	for c in _boxed:
		if int(c["handle"]) == locked_handle:
			continue
		var position: Vector3 = c["position"]
		var at = _screen(position)
		if at == null:
			continue
		var range_m := _camera.global_position.distance_to(position)
		var half := box_half_extent_px(range_m)
		draw_rect(Rect2((at as Vector2) - Vector2(half, half), Vector2(half, half) * 2.0), Color(GREEN, 0.7), false, LINE_WIDTH)
		draw_string(
			ThemeDB.fallback_font,
			(at as Vector2) + Vector2(-half, half + LABEL_SIZE + 2.0),
			"%d" % roundi(range_m),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, Color(GREEN, 0.7)
		)


## The lock is loud, and when it goes off-screen it becomes a chevron on the
## edge rather than nothing. The scope already makes that promise about its rim
## contacts; the glass makes the same one.
func _draw_lock() -> void:
	if _locked.is_empty():
		return
	var position: Vector3 = _locked["position"]
	var range_m := _camera.global_position.distance_to(position)
	var at = _screen(position)
	var viewport := Rect2(Vector2.ZERO, size)
	if at == null or not viewport.has_point(at):
		_draw_lock_chevron(position, range_m)
		return
	var centre: Vector2 = at
	var half := maxf(box_half_extent_px(range_m), 14.0)
	# Diamond.
	draw_polyline(PackedVector2Array([
		centre + Vector2(0.0, -half), centre + Vector2(half, 0.0),
		centre + Vector2(0.0, half), centre + Vector2(-half, 0.0),
		centre + Vector2(0.0, -half),
	]), AMBER, LOCK_LINE_WIDTH)
	# Corner brackets, outside the diamond.
	var bracket := half + 8.0
	for corner in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		var c: Vector2 = centre + corner * bracket
		draw_line(c, c - Vector2(corner.x * 7.0, 0.0), AMBER, LOCK_LINE_WIDTH)
		draw_line(c, c - Vector2(0.0, corner.y * 7.0), AMBER, LOCK_LINE_WIDTH)
	var label := "%s  %d m  %s" % [
		kind_label(int(_locked["kind"])), roundi(range_m), closure_text(_closure)
	]
	var name := String(_locked.get("name", ""))
	if not name.is_empty():
		label = "%s  %s" % [name, label]
	draw_string(
		ThemeDB.fallback_font, centre + Vector2(bracket + 6.0, 4.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE + 1, AMBER
	)


func _draw_lock_chevron(position: Vector3, range_m: float) -> void:
	var centre := size * 0.5
	var to_target: Vector3 = position - _camera.global_position
	var local: Vector3 = _camera.global_basis.inverse() * to_target
	var direction := Vector2(local.x, -local.y)
	if local.z > 0.0:
		# Behind: the sideways sense is preserved, but it is astern.
		direction = Vector2(-local.x, -local.y)
	if direction.length_squared() < 1e-6:
		direction = Vector2.DOWN
	direction = direction.normalized()
	var edge := centre + direction * (minf(size.x, size.y) * 0.5 - EDGE_MARGIN_PX)
	var side := Vector2(-direction.y, direction.x)
	draw_polyline(PackedVector2Array([
		edge - direction * 10.0 + side * 7.0, edge, edge - direction * 10.0 - side * 7.0,
	]), AMBER, LOCK_LINE_WIDTH)
	draw_string(
		ThemeDB.fallback_font, edge - direction * 26.0 + Vector2(-14.0, 0.0),
		"%d" % roundi(range_m), HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, AMBER
	)


## Screen-fixed, and that is the point: they do not swing, so the conformal
## symbols read as conformal by contrast.
func _draw_tapes() -> void:
	if _instruments.is_empty():
		return
	var font := ThemeDB.fallback_font
	var speed_knots := float(_instruments.get("speed_mps", 0.0)) * 1.94384
	var altitude := float(_instruments.get("altitude_m", 0.0))
	var heading := float(_instruments.get("heading_degrees", 0.0))
	var middle := size.y * 0.5
	_draw_tape(Vector2(TAPE_MARGIN_PX, middle), "%d" % roundi(speed_knots), "KT", true)
	_draw_tape(Vector2(size.x - TAPE_MARGIN_PX, middle), "%d" % roundi(altitude), "M", false)
	# Heading across the top, boxed at the nose.
	var top := Vector2(size.x * 0.5, TAPE_MARGIN_PX)
	draw_line(top + Vector2(-140.0, 10.0), top + Vector2(140.0, 10.0), Color(GREEN, 0.5), LINE_WIDTH)
	for offset in range(-60, 61, 15):
		var x: float = top.x + float(offset) * 2.2
		draw_line(Vector2(x, top.y + 6.0), Vector2(x, top.y + 14.0), Color(GREEN, 0.5), LINE_WIDTH)
	var heading_text := "%03d" % (int(roundi(heading)) % 360)
	draw_rect(Rect2(top + Vector2(-22.0, -10.0), Vector2(44.0, 18.0)), Color(GREEN, 0.9), false, LINE_WIDTH)
	draw_string(font, top + Vector2(-17.0, 4.0), heading_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE + 1, GREEN)
	# G and Mach beneath the speed tape.
	var readout := Vector2(TAPE_MARGIN_PX, middle + TAPE_HEIGHT_PX * 0.5 + 22.0)
	draw_string(font, readout, "G %.1f" % float(_instruments.get("g_load", 1.0)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, Color(GREEN, 0.8))
	draw_string(font, readout + Vector2(0.0, LABEL_SIZE + 4.0), "M %.2f" % float(_instruments.get("mach", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, Color(GREEN, 0.8))


func _draw_tape(anchor: Vector2, value: String, unit: String, left: bool) -> void:
	var font := ThemeDB.fallback_font
	var half := TAPE_HEIGHT_PX * 0.5
	var colour := Color(GREEN, 0.5)
	draw_line(anchor + Vector2(0.0, -half), anchor + Vector2(0.0, half), colour, LINE_WIDTH)
	var direction := 1.0 if left else -1.0
	for step in range(-4, 5):
		var y: float = anchor.y + float(step) * (half / 4.0)
		var length := 10.0 if step % 2 == 0 else 5.0
		draw_line(Vector2(anchor.x, y), Vector2(anchor.x + length * direction, y), colour, LINE_WIDTH)
	var box := Rect2(anchor + Vector2(-4.0 if left else -56.0, -11.0), Vector2(60.0, 22.0))
	draw_rect(box, Color(GREEN, 0.9), false, LINE_WIDTH)
	draw_string(font, box.position + Vector2(5.0, 16.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE + 2, GREEN)
	draw_string(font, box.position + Vector2(5.0, 32.0), unit, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE - 2, Color(GREEN, 0.7))
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --script tests/helmet_hud_test.gd`
Expected: `HELMET_HUD_TEST_PASS`, no `ERROR:` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/helmet_hud.gd tests/helmet_hud_test.gd
git commit -m "Draw the visor: horizon, ladder, marker, boxes and the lock"
```

---

### Task 5: The scope — translucent, ranged, and animated

**Files:**
- Modify: `scripts/ui/radar_scope.gd`
- Modify: `tests/radar_scope_test.gd`

**Interfaces:**
- Consumes: `TargetTracker.Kind` and `TargetTracker.RADAR_RANGES_M` (Task 1).
- Produces:
  - `RadarScope.set_contacts(player_position: Vector3, heading: float, contacts: Array, locked_handle: int) -> void` — **signature change**: contacts are now tracker dictionaries, not drones, and the locked handle is new
  - `RadarScope.cycle_range() -> float`, `RadarScope.range_m() -> float`
  - `RadarScope.range_changed(metres: float)` — signal
  - `static blip_alpha(range_m: float, scope_range_m: float) -> float`
  - `static colour_for_kind(kind: int) -> Color`
  - `blip_offset` and `is_on_rim` keep their existing signatures and behaviour

**Note for the implementer:** the existing test asserts against `SCOPE.RADAR_RANGE_M`, which this task removes. Update it in Step 1; do not delete the assertions it makes about `blip_offset` and `is_on_rim`, which are still correct and still valuable.

- [ ] **Step 1: Write the failing test**

Rewrite `tests/radar_scope_test.gd` as follows. The first half is the existing file's assertions with `RADAR_RANGE_M` replaced by an explicit range; the second half is new.

```gdscript
extends SceneTree

## Nose-up: a contact dead ahead is at the top whatever the heading, and a
## contact on the right is on the right. Beyond range it pins to the rim so a
## contact is never simply absent -- it is always at least a direction. On top
## of that geometry the scope makes a claim about certainty: the further out a
## blip is, the fainter it is drawn.

const SCOPE := preload("res://scripts/ui/radar_scope.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

var _failed := false


func _init() -> void:
	_geometry_is_nose_up()
	_out_of_range_pins_to_the_rim()
	_altitude_does_not_move_a_blip()
	_range_cycles_and_wraps()
	_blips_fade_with_range()
	_the_scope_only_takes_its_own_taps()
	_every_kind_has_a_colour()
	if _failed:
		return
	print("RADAR_SCOPE_TEST_PASS")
	quit()


func _geometry_is_nose_up() -> void:
	var range_m := 4000.0
	var radius: float = SCOPE.SCOPE_RADIUS_PX
	var ahead: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -2000.0), 0.0, range_m, radius)
	if ahead.y >= 0.0 or absf(ahead.x) > 0.5:
		_fail("a contact dead ahead must be straight up, got %v" % ahead)
	if not is_equal_approx(ahead.length(), radius * 0.5):
		_fail("half range must sit at half radius, got %f" % ahead.length())
	var turned: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -2000.0), PI * 0.5, range_m, radius)
	if turned.x >= 0.0 or absf(turned.y) > 0.5:
		_fail("after a right turn a contact that was ahead is on the left, got %v" % turned)


func _out_of_range_pins_to_the_rim() -> void:
	var range_m := 4000.0
	var radius: float = SCOPE.SCOPE_RADIUS_PX
	var far: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -9000.0), 0.0, range_m, radius)
	if not is_equal_approx(far.length(), radius):
		_fail("out of range must pin to the rim, got %f" % far.length())
	if far.y >= 0.0:
		_fail("a pinned contact keeps its direction")
	if not SCOPE.is_on_rim(Vector3(0.0, 0.0, -9000.0), range_m):
		_fail("out of range must report as on the rim")
	if SCOPE.is_on_rim(Vector3(0.0, 0.0, -2000.0), range_m):
		_fail("in range must not report as on the rim")


func _altitude_does_not_move_a_blip() -> void:
	var range_m := 4000.0
	var radius: float = SCOPE.SCOPE_RADIUS_PX
	var ahead: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -2000.0), 0.0, range_m, radius)
	var high: Vector2 = SCOPE.blip_offset(Vector3(0.0, 3000.0, -2000.0), 0.0, range_m, radius)
	if not high.is_equal_approx(ahead):
		_fail("altitude must not displace a blip: this is a top-down scope")


func _range_cycles_and_wraps() -> void:
	var scope = SCOPE.new()
	if not is_equal_approx(scope.range_m(), 10000.0):
		_fail("ten kilometres is the default, got %f" % scope.range_m())
	var seen := []
	for i in range(TRACKER.RADAR_RANGES_M.size()):
		seen.append(scope.cycle_range())
	if not is_equal_approx(scope.range_m(), 10000.0):
		_fail("cycling all the way round returns to the default, got %f" % scope.range_m())
	if seen.size() != TRACKER.RADAR_RANGES_M.size():
		_fail("every range must be reachable")
	scope.free()


## Fainter further out. A 10 km blip should not look as certain as a 2 km one.
func _blips_fade_with_range() -> void:
	var near: float = SCOPE.blip_alpha(1000.0, 10000.0)
	var far: float = SCOPE.blip_alpha(9000.0, 10000.0)
	if near <= far:
		_fail("a nearer contact must be drawn stronger, got %f then %f" % [near, far])
	if far < SCOPE.BLIP_MIN_ALPHA - 1e-6:
		_fail("distant but never absent, got %f" % far)
	if near > 1.0:
		_fail("alpha cannot exceed one, got %f" % near)


## The scope takes the taps inside its own disc and lets every other tap fall
## through to the lock gesture underneath.
func _the_scope_only_takes_its_own_taps() -> void:
	var scope = SCOPE.new()
	scope.size = Vector2(1280.0, 720.0)
	var centre := scope.scope_centre()
	if not scope._has_point(centre):
		_fail("the middle of the scope is the scope")
	if scope._has_point(centre + Vector2(SCOPE.SCOPE_RADIUS_PX * 2.0, 0.0)):
		_fail("outside the disc the tap belongs to the target lock")
	scope.free()


func _every_kind_has_a_colour() -> void:
	var seen := {}
	for kind in TRACKER.Kind.values():
		seen[SCOPE.colour_for_kind(kind).to_html()] = true
	if seen.size() < 3:
		_fail("jets, ground threats and structures must be told apart")


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --script tests/radar_scope_test.gd`
Expected: FAIL — `blip_alpha`, `cycle_range`, `scope_centre` and `colour_for_kind` are not declared.

- [ ] **Step 3: Write the implementation**

Replace `scripts/ui/radar_scope.gd` entirely:

```gdscript
extends Control

## A round air scope, aircraft at centre, nose up. Targets are blips whose
## screen position is their world offset rotated by minus the heading, so a
## contact ahead is at the top whatever way the aircraft points. Beyond range a
## blip pins to the rim as a chevron: a contact is never simply absent from the
## scope, it is always at least a direction.
##
## The scope makes two different fades, and they are unrelated. The BODY fades
## to its rim, so the instrument dissolves into the view instead of sitting on
## it as a disc -- that is a look. A BLIP fades with its range, because a
## contact at nine kilometres is not known as well as one at two -- that is a
## claim. Deliberately no per-frame positional jitter: jitter that moves every
## frame reads as a bug, not as uncertainty.
##
## Drawn, not themed: no textures, scales with the viewport, and every element
## is a line, an arc or a polygon.

signal range_changed(metres: float)

const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

const SCOPE_RADIUS_PX := 90.0
const MARGIN_PX := 24.0
const RING_COLOUR := Color(0.35, 0.9, 0.5, 0.55)
const BLIP_RADIUS_PX := 3.5
const LOCK_COLOUR := Color(1.0, 0.72, 0.25)

## Translucent at the middle, gone at the rim.
const SCOPE_CENTRE_ALPHA := 0.45
const BLIP_MIN_ALPHA := 0.35
## Past this fraction of the range a blip is a ring rather than a dot.
const BLIP_SOFT_FRACTION := 0.6
const SWEEP_PERIOD_S := 2.5
## How long a contact stays lit after the sweep has crossed it.
const SWEEP_GLOW_S := 0.45
const BODY_SEGMENTS := 48

var _contacts: Array = []
var _player_position := Vector3.ZERO
var _heading := 0.0
var _locked_handle := -1
var _range_index: int = TRACKER.DEFAULT_RANGE_INDEX
var _sweep := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)


func _process(delta: float) -> void:
	_sweep = fmod(_sweep + delta / SWEEP_PERIOD_S, 1.0)
	queue_redraw()


func scope_centre() -> Vector2:
	return Vector2(size.x - MARGIN_PX - SCOPE_RADIUS_PX, size.y - MARGIN_PX - SCOPE_RADIUS_PX)


## Only the disc belongs to the scope. Everywhere else the tap falls through to
## the target lock underneath, which is the whole reason this override exists.
func _has_point(point: Vector2) -> bool:
	return point.distance_to(scope_centre()) <= SCOPE_RADIUS_PX


func _gui_input(event: InputEvent) -> void:
	var pressed := (
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or (event is InputEventMouseButton
			and (event as InputEventMouseButton).pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	)
	if pressed:
		cycle_range()
		accept_event()


func range_m() -> float:
	return TRACKER.RADAR_RANGES_M[_range_index]


func cycle_range() -> float:
	_range_index = (_range_index + 1) % TRACKER.RADAR_RANGES_M.size()
	range_changed.emit(range_m())
	queue_redraw()
	return range_m()


static func blip_offset(world_offset: Vector3, heading: float, range_m: float, radius_px: float) -> Vector2:
	var flat := Vector2(world_offset.x, world_offset.z).rotated(-heading)
	var scaled := flat * (radius_px / maxf(range_m, 1.0))
	if scaled.length() > radius_px:
		scaled = scaled.normalized() * radius_px
	return scaled


static func is_on_rim(world_offset: Vector3, range_m: float) -> bool:
	return Vector2(world_offset.x, world_offset.z).length() > range_m


static func blip_alpha(range_m: float, scope_range_m: float) -> float:
	var t := clampf(range_m / maxf(scope_range_m, 1.0), 0.0, 1.0)
	return lerpf(1.0, BLIP_MIN_ALPHA, t)


static func colour_for_kind(kind: int) -> Color:
	match kind:
		TRACKER.Kind.AIR_JET:
			return Color(1.0, 0.45, 0.35)
		TRACKER.Kind.AIR_DRONE:
			return Color(1.0, 0.78, 0.35)
		TRACKER.Kind.GROUND_LAUNCHER:
			return Color(1.0, 0.35, 0.6)
		TRACKER.Kind.BUILDING:
			return Color(0.6, 0.85, 1.0)
		TRACKER.Kind.GROUND_POINT:
			return Color(0.8, 0.9, 1.0)
	return Color(0.92, 0.96, 1.0)


func set_contacts(player_position: Vector3, heading: float, contacts: Array, locked_handle: int) -> void:
	_player_position = player_position
	_heading = heading
	_contacts = contacts
	_locked_handle = locked_handle
	queue_redraw()


func _draw() -> void:
	var centre := scope_centre()
	_draw_body(centre)
	draw_arc(centre, SCOPE_RADIUS_PX, 0.0, TAU, 64, RING_COLOUR, 1.5)
	draw_arc(centre, SCOPE_RADIUS_PX * 0.5, 0.0, TAU, 48, RING_COLOUR * Color(1.0, 1.0, 1.0, 0.6), 1.0)
	draw_line(centre + Vector2(0.0, -SCOPE_RADIUS_PX), centre + Vector2(0.0, -SCOPE_RADIUS_PX + 8.0), RING_COLOUR, 2.0)
	_draw_sweep(centre)
	draw_string(
		ThemeDB.fallback_font, centre + Vector2(SCOPE_RADIUS_PX - 40.0, -SCOPE_RADIUS_PX + 14.0),
		"%dKM" % int(range_m() / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, RING_COLOUR
	)
	_draw_contacts(centre)


## A triangle fan whose per-vertex alpha falls to nothing at the rim. No
## shader, no texture, one call -- which is what `draw_polygon`'s vertex
## colours are for.
func _draw_body(centre: Vector2) -> void:
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	points.append(centre)
	colours.append(Color(0.05, 0.14, 0.09, SCOPE_CENTRE_ALPHA))
	for i in range(BODY_SEGMENTS + 1):
		var angle := TAU * float(i) / float(BODY_SEGMENTS)
		points.append(centre + Vector2(cos(angle), sin(angle)) * SCOPE_RADIUS_PX)
		colours.append(Color(0.05, 0.14, 0.09, 0.0))
	draw_polygon(points, colours)


func _draw_sweep(centre: Vector2) -> void:
	var angle := _sweep * TAU - PI * 0.5
	for i in range(6):
		var trail := angle - float(i) * 0.06
		var alpha := 0.35 * (1.0 - float(i) / 6.0)
		draw_line(centre, centre + Vector2(cos(trail), sin(trail)) * SCOPE_RADIUS_PX, Color(0.5, 1.0, 0.7, alpha), 1.5)


func _draw_contacts(centre: Vector2) -> void:
	var scope_range := range_m()
	for c in _contacts:
		var offset: Vector3 = (c["position"] as Vector3) - _player_position
		var at := centre + blip_offset(offset, _heading, scope_range, SCOPE_RADIUS_PX)
		var kind := int(c["kind"])
		var range_m_to := Vector2(offset.x, offset.z).length()
		var colour := colour_for_kind(kind)
		colour.a = blip_alpha(range_m_to, scope_range) * _sweep_glow(offset)
		if is_on_rim(offset, scope_range):
			var outward := (at - centre).normalized()
			var side := Vector2(-outward.y, outward.x)
			draw_polyline(PackedVector2Array([
				at - outward * 6.0 + side * 4.0, at, at - outward * 6.0 - side * 4.0
			]), colour, 1.5)
		elif kind == TRACKER.Kind.GROUND_LAUNCHER:
			# Ground threats are carets, so a SAM is never mistaken for a jet.
			draw_polyline(PackedVector2Array([
				at + Vector2(-4.5, 3.5), at + Vector2(0.0, -4.0), at + Vector2(4.5, 3.5)
			]), colour, 1.5)
		elif range_m_to > scope_range * BLIP_SOFT_FRACTION:
			draw_arc(at, BLIP_RADIUS_PX, 0.0, TAU, 12, colour, 1.2)
		else:
			draw_circle(at, BLIP_RADIUS_PX, colour)
		if int(c["handle"]) == _locked_handle:
			draw_arc(at, BLIP_RADIUS_PX + 5.0, 0.0, TAU, 20, LOCK_COLOUR, 1.8)


## A contact brightens as the sweep crosses its bearing and dims again behind
## it. This is the animation, and it is one subtraction.
func _sweep_glow(offset: Vector3) -> float:
	var bearing := Vector2(offset.x, offset.z).rotated(-_heading).angle() + PI * 0.5
	var swept := fmod(_sweep * TAU - bearing + TAU * 2.0, TAU)
	var since := swept / TAU * SWEEP_PERIOD_S
	if since > SWEEP_GLOW_S:
		return 1.0
	return lerpf(1.6, 1.0, since / SWEEP_GLOW_S)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --script tests/radar_scope_test.gd`
Expected: `RADAR_SCOPE_TEST_PASS`, no `ERROR:` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/radar_scope.gd tests/radar_scope_test.gd
git commit -m "Fade the scope to its rim and let it change its range"
```

---

### Task 6: Enemy Raptors — the state machine

**Files:**
- Create: `scripts/entities/enemy_jet.gd`
- Test: `tests/enemy_jet_test.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `EnemyJet.State` — enum `{INGRESS, PURSUIT, MERGE, EVADE, EGRESS, DESTROYED}`
  - Properties: `id: int`, `position: Vector3`, `velocity: Vector3`, `heading: float`, `speed: float`, `state: int`, `break_sign: float`, `formation_offset: Vector3`
  - `update(delta: float, player_position: Vector3, player_nose: Vector3) -> void`
  - `nose() -> Vector3`, `bank() -> float`
  - Constants named in the Constants table below

- [ ] **Step 1: Write the failing test**

Create `tests/enemy_jet_test.gd`:

```gdscript
extends SceneTree

## A Raptor that will not fire still has to be frightening, so what is asserted
## here is the geometry of the fight: it closes, it goes for your six rather
## than for a shot, it breaks AWAY when you point at it, and it eventually
## gives up and leaves rather than circling you forever.

const ENEMY := preload("res://scripts/entities/enemy_jet.gd")

var _failed := false


func _init() -> void:
	_ingress_becomes_pursuit_when_it_finds_you()
	_pursuit_closes_the_range()
	_inside_merge_range_it_fights_for_position()
	_being_pointed_at_makes_it_break_away()
	_it_jinks_so_it_cannot_be_led()
	_it_gives_up_and_leaves()
	_a_destroyed_jet_stops_flying()
	if _failed:
		return
	print("ENEMY_JET_TEST_PASS")
	quit()


func _fresh(distance: float) -> RefCounted:
	var jet = ENEMY.new()
	jet.id = 1
	jet.position = Vector3(0.0, 3000.0, -distance)
	jet.heading = PI
	jet.speed = ENEMY.ENEMY_CRUISE_MPS
	return jet


func _ingress_becomes_pursuit_when_it_finds_you() -> void:
	var player := Vector3(0.0, 3000.0, 0.0)
	# Beyond pursuit range it is merely inbound.
	var distant = _fresh(15000.0)
	distant.update(0.1, player, Vector3.BACK)
	if distant.state != ENEMY.State.INGRESS:
		_fail("beyond %f m it is still only inbound, got %d" % [ENEMY.PURSUIT_RANGE_M, distant.state])
	# Inside it, it commits to the chase.
	var close = _fresh(9000.0)
	close.update(0.1, player, Vector3.BACK)
	if close.state != ENEMY.State.PURSUIT:
		_fail("inside pursuit range it commits to the chase, got %d" % close.state)


func _pursuit_closes_the_range() -> void:
	var jet = _fresh(9000.0)
	var player := Vector3(0.0, 3000.0, 0.0)
	var before: float = jet.position.distance_to(player)
	for i in range(40):
		jet.update(0.1, player, Vector3.FORWARD)
	if jet.position.distance_to(player) >= before:
		_fail("a pursuing jet must close, went from %f to %f" % [before, jet.position.distance_to(player)])


func _inside_merge_range_it_fights_for_position() -> void:
	var jet = _fresh(2000.0)
	# The player is pointing away, so the jet is not threatened and will merge.
	jet.update(0.1, Vector3(0.0, 3000.0, 0.0), Vector3.BACK)
	if jet.state != ENEMY.State.MERGE:
		_fail("inside merge range the chase becomes a knife fight, got %d" % jet.state)


## Never toward the nose: that is a head-on, and the jet loses it.
func _being_pointed_at_makes_it_break_away() -> void:
	var jet = _fresh(1000.0)
	var player := Vector3(0.0, 3000.0, 0.0)
	# The player's nose is on the jet, which sits at -Z from the player.
	jet.update(0.1, player, Vector3.FORWARD)
	if jet.state != ENEMY.State.EVADE:
		_fail("pointed at, inside threat range, it must break, got %d" % jet.state)
	# Assert the turn, not the range. At 0.32 rad/s a jet pointed straight at
	# you cannot open the distance inside a few seconds -- it has to swing its
	# nose off you first, and that swing is the actual claim being made.
	var to_player: Vector3 = (player - jet.position).normalized()
	var alignment_before: float = jet.nose().dot(to_player)
	for i in range(25):
		jet.update(0.1, player, Vector3.FORWARD)
	var to_player_now: Vector3 = (player - jet.position).normalized()
	if jet.nose().dot(to_player_now) >= alignment_before:
		_fail("breaking means turning the nose off the player, not holding it on")


func _it_jinks_so_it_cannot_be_led() -> void:
	var jet = _fresh(1000.0)
	var player := Vector3(0.0, 3000.0, 0.0)
	jet.update(0.1, player, Vector3.FORWARD)
	var first: float = jet.break_sign
	var reversed := false
	for i in range(int(ENEMY.JINK_INTERVAL / 0.1) + 6):
		jet.update(0.1, player, Vector3.FORWARD)
		if not is_equal_approx(jet.break_sign, first):
			reversed = true
			break
	if not reversed:
		_fail("a steady deflection must not solve this jet: the break has to reverse")


func _it_gives_up_and_leaves() -> void:
	var jet = _fresh(2000.0)
	var player := Vector3(0.0, 3000.0, 0.0)
	var steps := int((ENEMY.EGRESS_AFTER_SECONDS + 2.0) / 0.1)
	for i in range(steps):
		jet.update(0.1, player, Vector3.BACK)
	if jet.state != ENEMY.State.EGRESS:
		_fail("a fight that goes nowhere ends, got %d" % jet.state)


func _a_destroyed_jet_stops_flying() -> void:
	var jet = _fresh(2000.0)
	jet.state = ENEMY.State.DESTROYED
	var where: Vector3 = jet.position
	jet.update(0.5, Vector3.ZERO, Vector3.FORWARD)
	if not jet.position.is_equal_approx(where):
		_fail("the dead do not manoeuvre")


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --script tests/enemy_jet_test.gd`
Expected: FAIL — `res://scripts/entities/enemy_jet.gd` does not exist.

- [ ] **Step 3: Write the implementation**

Create `scripts/entities/enemy_jet.gd`:

```gdscript
extends RefCounted

## One enemy Raptor: where it is, what it is doing, and how it gets away from
## you.
##
## Kinematic, not aerodynamic, for the same reason `drone.gd` is: nobody can
## tell a jet is obeying a drag polar, and a second full flight model on a phone
## would be paid for in framerate. Attitude is derived from the path so it banks
## into its turns and looks like an aircraft.
##
## In this phase it carries no weapons, so POSITION is the whole threat. It
## closes, and inside the merge it works for your six rather than for a shot --
## a Raptor sliding onto your tail is legible without a round being fired. And
## like a drone it breaks AWAY when you point at it, never toward you.

enum State {INGRESS, PURSUIT, MERGE, EVADE, EGRESS, DESTROYED}

## Above the player's 134 m/s corner speed, so it cannot simply be out-turned.
const ENEMY_CRUISE_MPS := 200.0
const ENEMY_DASH_MPS := 380.0
## rad/s, near the player's, so the merge is a contest rather than a formality.
const ENEMY_TURN_RATE := 0.32
## Where inbound becomes a committed chase.
const PURSUIT_RANGE_M := 12000.0
## Where the chase becomes a knife fight.
const MERGE_RANGE_M := 2500.0
## Roughly gun-plus-rocket reach.
const THREAT_RANGE_M := 1600.0
## Pointing at it, not merely near it.
const THREAT_CONE_DEGREES := 25.0
const EVADE_SECONDS := 5.0
## Shorter than the time it takes to settle a lead.
const JINK_INTERVAL := 1.6
## A fight that goes nowhere ends, rather than accumulating jets forever.
const EGRESS_AFTER_SECONDS := 45.0
const EGRESS_SECONDS := 20.0
const MIN_ALTITUDE_M := 400.0
const CLIMB_RATE_MPS := 60.0
## How far above the player a merging jet tries to sit before it comes down.
const MERGE_ALTITUDE_ADVANTAGE_M := 250.0

var id := 0
var position := Vector3.ZERO
var velocity := Vector3.ZERO
## Radians, same convention as jet_controller.heading_of: atan2(nose.x, -nose.z).
var heading := 0.0
var speed := ENEMY_CRUISE_MPS
var state: int = State.INGRESS
## +1 or -1: which way the current break goes. Public so the jink test can see
## it reverse.
var break_sign := 1.0
## Offset from the squadron lead, so a formation reads as a formation.
var formation_offset := Vector3.ZERO

var _evade_remaining := 0.0
var _jink_remaining := JINK_INTERVAL
var _egress_remaining := 0.0
var _fight_elapsed := 0.0
var _target_altitude := 0.0
var _desired_heading := 0.0


func nose() -> Vector3:
	return Vector3(sin(heading), 0.0, -cos(heading))


## Proportional to how hard the heading is changing, so it banks into turns.
func bank() -> float:
	return clampf(wrapf(_desired_heading - heading, -PI, PI) * 1.6, -1.2, 1.2)


func update(delta: float, player_position: Vector3, player_nose: Vector3) -> void:
	if state == State.DESTROYED:
		return
	var offset := player_position - position
	var range_m := offset.length()
	_fight_elapsed += delta
	_advance_state(delta, offset, range_m, player_nose)
	_steer(delta, player_position, offset, range_m)
	_move(delta)


func _advance_state(delta: float, offset: Vector3, range_m: float, player_nose: Vector3) -> void:
	if state == State.EGRESS:
		_egress_remaining -= delta
		return
	if state == State.EVADE:
		_evade_remaining -= delta
		_jink_remaining -= delta
		if _jink_remaining <= 0.0:
			break_sign = -break_sign
			_jink_remaining = JINK_INTERVAL
		if _evade_remaining <= 0.0:
			state = State.PURSUIT
		return
	if _threatened(offset, range_m, player_nose):
		state = State.EVADE
		_evade_remaining = EVADE_SECONDS
		_jink_remaining = JINK_INTERVAL
		# Break away from wherever the player's nose is, not toward it.
		break_sign = 1.0 if offset.cross(Vector3.UP).dot(player_nose) > 0.0 else -1.0
		return
	if _fight_elapsed > EGRESS_AFTER_SECONDS:
		state = State.EGRESS
		_egress_remaining = EGRESS_SECONDS
		return
	if range_m <= MERGE_RANGE_M:
		state = State.MERGE
	elif range_m <= PURSUIT_RANGE_M:
		state = State.PURSUIT
	else:
		state = State.INGRESS


## Pointed at, and close enough for it to matter. Both, not either.
func _threatened(offset: Vector3, range_m: float, player_nose: Vector3) -> bool:
	if range_m > THREAT_RANGE_M:
		return false
	var to_jet := -offset
	if to_jet.length_squared() < 1e-6:
		return false
	return rad_to_deg(player_nose.normalized().angle_to(to_jet.normalized())) <= THREAT_CONE_DEGREES


func _steer(delta: float, player_position: Vector3, offset: Vector3, range_m: float) -> void:
	match state:
		State.EVADE:
			# Away from the player, turned hard to one side, and descending is
			# where a gun fighter least wants to follow.
			var away := -offset
			var side := away.cross(Vector3.UP).normalized() * break_sign
			_desired_heading = _heading_of(away.normalized() + side * 0.9)
			speed = ENEMY_DASH_MPS
			_target_altitude = maxf(player_position.y - 200.0, MIN_ALTITUDE_M)
		State.EGRESS:
			_desired_heading = _heading_of(-offset)
			speed = ENEMY_DASH_MPS
			_target_altitude = maxf(position.y, MIN_ALTITUDE_M)
		State.MERGE:
			# For the six, not for a shot: aim behind the player rather than at
			# it, and hold a little height in hand.
			var behind := player_position - _player_forward_guess(offset) * 600.0
			_desired_heading = _heading_of(behind - position)
			speed = ENEMY_DASH_MPS
			_target_altitude = maxf(player_position.y + MERGE_ALTITUDE_ADVANTAGE_M, MIN_ALTITUDE_M)
		_:
			_desired_heading = _heading_of(offset + formation_offset)
			speed = ENEMY_CRUISE_MPS if range_m > PURSUIT_RANGE_M else ENEMY_DASH_MPS
			_target_altitude = maxf(player_position.y, MIN_ALTITUDE_M)
	heading = _turn_toward(heading, _desired_heading, ENEMY_TURN_RATE * delta)


## With no player velocity to read, the direction it is being chased from is a
## good enough guess at where the player is pointing.
func _player_forward_guess(offset: Vector3) -> Vector3:
	var flat := Vector3(offset.x, 0.0, offset.z)
	return flat.normalized() if flat.length_squared() > 1e-6 else Vector3.FORWARD


func _move(delta: float) -> void:
	var climb := clampf(_target_altitude - position.y, -CLIMB_RATE_MPS, CLIMB_RATE_MPS)
	velocity = nose() * speed + Vector3(0.0, climb, 0.0)
	position += velocity * delta
	position.y = maxf(position.y, MIN_ALTITUDE_M)


static func _heading_of(direction: Vector3) -> float:
	if direction.length_squared() < 1e-6:
		return 0.0
	return atan2(direction.x, -direction.z)


static func _turn_toward(from: float, to: float, max_step: float) -> float:
	var difference := wrapf(to - from, -PI, PI)
	return from + clampf(difference, -max_step, max_step)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --script tests/enemy_jet_test.gd`
Expected: `ENEMY_JET_TEST_PASS`, no `ERROR:` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/enemy_jet.gd tests/enemy_jet_test.gd
git commit -m "Send up Raptors that hunt you for your six"
```

---

### Task 7: Squadrons — spawning them, flying them, killing them

**Files:**
- Create: `scripts/entities/enemy_squadron.gd`
- Test: `tests/enemy_squadron_test.gd`
- Modify: `scenes/main.tscn` (add one `Node3D` child named `EnemySquadron`)

**Interfaces:**
- Consumes: `EnemyJet` (Task 6), `entity_hit_index.gd`, `TargetTracker.Kind` (Task 1).
- Produces:
  - `EnemySquadron.FIRST_ID: int` — `200000` (must not collide with `drone_field.FIRST_ID`, which is `100000`)
  - `spawn(count: int, around: Vector3) -> void`
  - `update(delta: float, player_position: Vector3, player_nose: Vector3) -> void`
  - `jets() -> Array`
  - `contacts() -> Array` — `TargetTracker` contact dictionaries, `Kind.AIR_JET`
  - `query_segment(from: Vector3, to: Vector3) -> RefCounted`
  - `destroy_jet(entity_id: int) -> Variant`
  - `clear() -> void`, `jet_count() -> int`

- [ ] **Step 1: Write the failing test**

Create `tests/enemy_squadron_test.gd`:

```gdscript
extends SceneTree

## A squadron is a formation, not a crowd: the jets arrive together, spread out
## from a lead, and every one of them is reportable to the tracker as a contact.

const SQUADRON := preload("res://scripts/entities/enemy_squadron.gd")
const ENEMY := preload("res://scripts/entities/enemy_jet.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

var _failed := false


func _init() -> void:
	_spawns_the_requested_number()
	_spreads_them_out_from_a_lead()
	_spawns_them_far_enough_away_to_be_seen_coming()
	_reports_every_jet_as_a_contact()
	_ids_do_not_collide_with_the_drones()
	_destroying_a_jet_removes_it()
	if _failed:
		return
	print("ENEMY_SQUADRON_TEST_PASS")
	quit()


func _squadron() -> Node3D:
	var node = SQUADRON.new()
	get_root().add_child(node)
	return node


func _spawns_the_requested_number() -> void:
	var squadron := _squadron()
	squadron.spawn(4, Vector3.ZERO)
	if squadron.jet_count() != 4:
		_fail("a four ship is four jets, got %d" % squadron.jet_count())
	squadron.queue_free()


func _spreads_them_out_from_a_lead() -> void:
	var squadron := _squadron()
	squadron.spawn(3, Vector3.ZERO)
	var seen := {}
	for jet in squadron.jets():
		seen[str(jet.formation_offset)] = true
	if seen.size() != 3:
		_fail("every wingman needs its own slot, got %d distinct" % seen.size())
	for jet in squadron.jets():
		if jet.formation_offset.length() > SQUADRON.FORMATION_SPACING_M * 3.0:
			_fail("a formation is tight, not scattered")
	squadron.queue_free()


## It must appear on the scope before it appears in the canopy.
func _spawns_them_far_enough_away_to_be_seen_coming() -> void:
	var squadron := _squadron()
	var player := Vector3(0.0, 3000.0, 0.0)
	squadron.spawn(2, player)
	for jet in squadron.jets():
		var range_m: float = jet.position.distance_to(player)
		if range_m < TRACKER.RADAR_RANGES_M[1]:
			_fail("spawning inside the default scope range is an ambush, got %f" % range_m)
		if jet.position.y < ENEMY.MIN_ALTITUDE_M:
			_fail("a jet must not spawn underground")
	squadron.queue_free()


func _reports_every_jet_as_a_contact() -> void:
	var squadron := _squadron()
	squadron.spawn(3, Vector3.ZERO)
	var contacts: Array = squadron.contacts()
	if contacts.size() != 3:
		_fail("every jet is a contact, got %d" % contacts.size())
	for c in contacts:
		if int(c["kind"]) != TRACKER.Kind.AIR_JET:
			_fail("an enemy Raptor is a jet contact")
		if not c.has("velocity"):
			_fail("a contact carries its velocity so closure can be computed")
	squadron.queue_free()


func _ids_do_not_collide_with_the_drones() -> void:
	if SQUADRON.FIRST_ID <= 100000:
		_fail("jet ids must start above the drone ids or the hit index confuses them")


func _destroying_a_jet_removes_it() -> void:
	var squadron := _squadron()
	squadron.spawn(2, Vector3.ZERO)
	var id: int = squadron.jets()[0].id
	squadron.destroy_jet(id)
	for jet in squadron.jets():
		if jet.id == id and jet.state != ENEMY.State.DESTROYED:
			_fail("a killed jet must be marked destroyed")
	squadron.queue_free()


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --script tests/enemy_squadron_test.gd`
Expected: FAIL — `res://scripts/entities/enemy_squadron.gd` does not exist.

- [ ] **Step 3: Write the implementation**

Read `scripts/entities/drone_field.gd` first — this file deliberately mirrors it, and the visual spawn, hit-index registration and destruction paths must match what already works there.

Create `scripts/entities/enemy_squadron.gd`:

```gdscript
extends Node3D

## A flight of enemy Raptors, spawned as a formation on a random bearing.
##
## Deliberately shaped like `drone_field.gd`, and for the same reasons: one hit
## index, one visual pool, one destruction path. The only real differences are
## that these are jets rather than drones, that they carry no weapons in this
## phase, and that they report themselves as `TargetTracker` contacts so the
## visor and the scope can see them without knowing what a squadron is.

const ENEMY := preload("res://scripts/entities/enemy_jet.gd")
const ENTITY_HIT_INDEX := preload("res://scripts/entities/entity_hit_index.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const JET_SCENE := preload("res://assets/models/f-22_raptor_-_fighter_jet_-_free.glb")

## Above drone_field.FIRST_ID (100000) so the two never share an entity id.
const FIRST_ID := 200000
const JET_WINGSPAN_M := 13.6
const HIT_HALF_EXTENTS := Vector3(8.0, 3.0, 8.0)

const SPAWN_RANGE_M := 16000.0
const SPAWN_ALTITUDE_MIN_M := 2000.0
const SPAWN_ALTITUDE_MAX_M := 6000.0
const FORMATION_SPACING_M := 300.0

var _jets: Array = []
var _visuals := {}
var _hit_index = ENTITY_HIT_INDEX.new()
var _next_id := FIRST_ID


func jets() -> Array:
	return _jets


func jet_count() -> int:
	var alive := 0
	for jet in _jets:
		if jet.state != ENEMY.State.DESTROYED:
			alive += 1
	return alive


func clear() -> void:
	for id in _visuals:
		var node: Node3D = _visuals[id]
		if is_instance_valid(node):
			node.queue_free()
	_visuals.clear()
	_jets.clear()
	_hit_index = ENTITY_HIT_INDEX.new()


## `around` is the player. The squadron arrives on a random bearing at
## SPAWN_RANGE_M, which is outside the default scope range on purpose: it must
## be seen coming.
func spawn(count: int, around: Vector3) -> void:
	var bearing := randf() * TAU
	var lead := around + Vector3(sin(bearing), 0.0, -cos(bearing)) * SPAWN_RANGE_M
	lead.y = randf_range(SPAWN_ALTITUDE_MIN_M, SPAWN_ALTITUDE_MAX_M)
	var across := Vector3(cos(bearing), 0.0, sin(bearing))
	for i in range(count):
		var jet = ENEMY.new()
		jet.id = _next_id
		_next_id += 1
		# Line abreast: the lead in the middle, wingmen stepped out either side.
		var slot := float(i) - float(count - 1) * 0.5
		jet.formation_offset = across * slot * FORMATION_SPACING_M
		jet.position = lead + jet.formation_offset
		jet.position.y = maxf(jet.position.y, ENEMY.MIN_ALTITUDE_M)
		jet.heading = atan2(around.x - jet.position.x, -(around.z - jet.position.z))
		jet.speed = ENEMY.ENEMY_CRUISE_MPS
		_jets.append(jet)
		_register(jet)
		_spawn_visual(jet)


func update(delta: float, player_position: Vector3, player_nose: Vector3) -> void:
	for jet in _jets:
		if jet.state == ENEMY.State.DESTROYED:
			continue
		jet.update(delta, player_position, player_nose)
		_register(jet)
		_place_visual(jet)


## What the tracker consumes. The squadron does not know what a visor is.
func contacts() -> Array:
	var out := []
	for jet in _jets:
		if jet.state == ENEMY.State.DESTROYED:
			continue
		out.append(TRACKER.contact(
			jet.id, TRACKER.Kind.AIR_JET, jet.position, jet.velocity, "RAPTOR"
		))
	return out


func query_segment(from: Vector3, to: Vector3) -> RefCounted:
	return _hit_index.query_segment(from, to)


func destroy_jet(entity_id: int) -> Variant:
	for jet in _jets:
		if jet.id != entity_id:
			continue
		jet.state = ENEMY.State.DESTROYED
		_hit_index.remove(entity_id)
		if _visuals.has(entity_id):
			var node: Node3D = _visuals[entity_id]
			if is_instance_valid(node):
				node.queue_free()
			_visuals.erase(entity_id)
		return jet
	return null


func _register(jet) -> void:
	_hit_index.set_entity(jet.id, jet.position, HIT_HALF_EXTENTS)


func _spawn_visual(jet) -> Node3D:
	var node: Node3D = JET_SCENE.instantiate()
	add_child(node)
	_visuals[jet.id] = node
	_place_visual(jet)
	return node


func _place_visual(jet) -> void:
	if not _visuals.has(jet.id):
		return
	var node: Node3D = _visuals[jet.id]
	if not is_instance_valid(node):
		return
	node.global_position = jet.position
	node.rotation = Vector3(0.0, jet.heading, jet.bank())
```

**Then add the node to the scene.** Open `scenes/main.tscn` in a text editor, find the `[node name="LauncherField" type="Node3D" parent="."]` entry, and add an identical block immediately after it:

```
[node name="EnemySquadron" type="Node3D" parent="."]
script = ExtResource("<next free id>")
```

Add the matching `[ext_resource type="Script" path="res://scripts/entities/enemy_squadron.gd" id="<next free id>"]` line at the top of the file alongside the other `ext_resource` entries, using an id that is not already taken.

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --script tests/enemy_squadron_test.gd`
Expected: `ENEMY_SQUADRON_TEST_PASS`, no `ERROR:` lines.

Then confirm the scene still opens: `godot --headless --quit-after 2` — expect no `ERROR:` lines mentioning `main.tscn`.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/enemy_squadron.gd tests/enemy_squadron_test.gd scenes/main.tscn
git commit -m "Put a formation on the scope, sixteen kilometres out"
```

---

### Task 8: Wiring — the tracker between the world and the glass

**Files:**
- Modify: `scripts/main.gd` (preloads at 1-25; the scope update at 338-341; `_unhandled_input` at 1047-1080; the UI setup that creates `_radar`)
- Modify: `scripts/entities/launcher_field.gd` (add `launcher_positions()`)
- Modify: `scenes/main.tscn` (add the `HelmetHud` Control under `UI`)
- Test: `tests/helmet_wiring_test.gd`

**Interfaces:**
- Consumes: every public interface from Tasks 1-7.
- Produces: nothing new. This task connects what exists.

- [ ] **Step 1: Write the failing test**

Create `tests/helmet_wiring_test.gd`:

```gdscript
extends SceneTree

## The wiring is the thing that goes wrong quietly, so this test asserts the
## contract rather than the drawing: contacts from three unrelated sources
## arrive as one list, the tracker turns them into one lock, and the scope's
## range and the tracker's range stay the same number.

const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const SCOPE := preload("res://scripts/ui/radar_scope.gd")

var _failed := false


func _init() -> void:
	_one_list_from_many_sources()
	_the_scope_and_the_tracker_agree_about_range()
	_a_press_that_hits_nothing_clears_the_lock()
	if _failed:
		return
	print("HELMET_WIRING_TEST_PASS")
	quit()


## Jets, drones and SAM sites are three systems that have never heard of each
## other; the tracker is where they stop being three.
func _one_list_from_many_sources() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(200000, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -3000.0)),
		TRACKER.contact(100000, TRACKER.Kind.AIR_DRONE, Vector3(100.0, 0.0, -2000.0)),
		TRACKER.contact(5, TRACKER.Kind.GROUND_LAUNCHER, Vector3(-200.0, 0.0, -1500.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	if tracker.tracked().size() != 3:
		_fail("all three sources must reach the scope, got %d" % tracker.tracked().size())
	if int(tracker.tracked()[0]["kind"]) != TRACKER.Kind.GROUND_LAUNCHER:
		_fail("nearest first, whatever kind it is")


func _the_scope_and_the_tracker_agree_about_range() -> void:
	var scope = SCOPE.new()
	var tracker = TRACKER.new()
	tracker.set_range(scope.range_m())
	if not is_equal_approx(tracker.range_m(), scope.range_m()):
		_fail("the tracker must follow the scope, %f against %f" % [tracker.range_m(), scope.range_m()])
	tracker.set_range(scope.cycle_range())
	if not is_equal_approx(tracker.range_m(), scope.range_m()):
		_fail("and must keep following it after a cycle")
	scope.free()


func _a_press_that_hits_nothing_clears_the_lock() -> void:
	var tracker = TRACKER.new()
	tracker.update([
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(0.0, 0.0, -2000.0)),
	], Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	tracker.lock_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), null, TRACKER.Kind.GROUND_POINT, "")
	if tracker.locked_handle() != 1:
		_fail("locked first")
	# Press the sky: no contact near the ray, and the ground ray missed.
	tracker.lock_at(Vector3.ZERO, Vector3(0.0, 1.0, 0.0), null, TRACKER.Kind.GROUND_POINT, "")
	if tracker.locked_handle() != -1:
		_fail("pressing nothing clears the lock, got %d" % tracker.locked_handle())


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --script tests/helmet_wiring_test.gd`
Expected: FAIL — `range_m` is not declared on the scope, unless Task 5 is complete; if Tasks 1-7 are all done this test may pass immediately, which is fine. Its job is to lock the contract before `main.gd` is edited.

- [ ] **Step 3: Wire it up**

Add to the preload block at the top of `scripts/main.gd`:

```gdscript
const TARGET_TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const HELMET_HUD := preload("res://scripts/ui/helmet_hud.gd")
const ENEMY_SQUADRON := preload("res://scripts/entities/enemy_squadron.gd")
```

Add beside the other state variables:

```gdscript
var _tracker := TARGET_TRACKER.new()
var _helmet: Control
@onready var enemy_squadron: Node3D = $EnemySquadron
## Enemy squadrons arrive on a timer while the player is flying the jet.
var _next_squadron_in := 25.0
```

Where `_radar` is created in the UI setup, create the helmet beside it and connect the range signal:

```gdscript
	_helmet = HELMET_HUD.new()
	ui_layer.add_child(_helmet)
	# Behind the reticle, which keeps the gunsight and the hit markers.
	ui_layer.move_child(_helmet, 0)
	_radar.range_changed.connect(_on_radar_range_changed)
	_tracker.set_range(_radar.range_m())


func _on_radar_range_changed(metres: float) -> void:
	_tracker.set_range(metres)
	status_label.text = "RADAR %d KM" % int(metres / 1000.0)
```

**The call site to replace is `scripts/main.gd:338-341`** — the three lines that compute `heading` and call `_radar.set_contacts(...)` and `_tape.set_contacts(...)` today. Leave the `_tape` call alone; the bearing tape is still correct and still earns its place. Replace the `_radar.set_contacts` line with:

```gdscript
	_update_targeting(delta)
```

```gdscript
## The one place the three target sources become one list, and the one place the
## visor and the scope are told anything.
func _update_targeting(delta: float) -> void:
	if _flying_jet:
		_next_squadron_in -= delta
		if _next_squadron_in <= 0.0 and enemy_squadron.jet_count() == 0:
			enemy_squadron.spawn(randi_range(2, 4), _focus_position())
			_next_squadron_in = 90.0
	enemy_squadron.update(delta, _focus_position(), _vehicle_nose())

	var contacts: Array = []
	contacts.append_array(enemy_squadron.contacts())
	for drone in _drone_field.drones():
		if drone.state == DRONE_FIELD.DRONE.State.DESTROYED:
			continue
		contacts.append(TARGET_TRACKER.contact(
			drone.id, TARGET_TRACKER.Kind.AIR_DRONE, drone.position, drone.velocity, "DRONE"
		))
	# See the launcher_positions() note below: this accessor is added in this task.
	for launcher in launcher_field.launcher_positions():
		contacts.append(TARGET_TRACKER.contact(
			int(launcher["id"]), TARGET_TRACKER.Kind.GROUND_LAUNCHER,
			launcher["position"], Vector3.ZERO, "SAM"
		))

	_tracker.update(contacts, camera.global_position, -camera.global_basis.z, _vehicle_velocity())
	var locked: Dictionary = _tracker.locked()
	_helmet.set_state(
		camera,
		_vehicle_velocity(),
		_tracker.boxed(),
		locked,
		_tracker.closure_of(_tracker.locked_handle()),
		{
			"speed_mps": _vehicle_velocity().length(),
			"altitude_m": _focus_position().y,
			"heading_degrees": rad_to_deg(_vehicle_heading()),
			"g_load": _vehicle_g_load(),
			"mach": _vehicle_velocity().length() / 340.0,
		}
	)
	_radar.set_contacts(_focus_position(), _vehicle_heading(), _tracker.tracked(), _tracker.locked_handle())
	# The weapons need no wiring of their own: `cannon_weapon.aim` already reads
	# `_orbit_target_point` (main.gd:1478), which already reads `_target_point`.
	# Keeping those two in step with the lock is the whole integration.
	if not locked.is_empty():
		_target_point = locked["position"]
		_has_target_point = true
```

**These four helpers do not exist yet — add them to `main.gd` beside `_focus_position()`.** The jet exposes `velocity` as a public variable and `airspeed()`; the helicopter exposes neither, so both are guarded. G-load is genuinely not published by `jet_controller.gd`, and this task does not add it — `1.0` is the honest placeholder until somebody has a reason to compute it.

```gdscript
func _vehicle_velocity() -> Vector3:
	var vehicle := _vehicle()
	if vehicle == null:
		return Vector3.ZERO
	# jet_controller publishes `velocity`; the helicopter does not.
	var value = vehicle.get("velocity")
	return value if value is Vector3 else Vector3.ZERO


func _vehicle_nose() -> Vector3:
	var vehicle := _vehicle()
	return Vector3.FORWARD if vehicle == null else -vehicle.global_basis.z


## The same convention main.gd already uses at line 338 for the scope.
func _vehicle_heading() -> float:
	var nose := _vehicle_nose()
	return atan2(nose.x, -nose.z)


## jet_controller does not publish a load factor, and this phase does not add
## one. The tape shows a placeholder rather than a lie dressed as a measurement.
func _vehicle_g_load() -> float:
	return 1.0
```

**`launcher_field` has no `launchers()` accessor** — it keeps `_launchers` private and exposes only `launcher_count()`, `query_segment()` and `destroy_launcher()`. Add the one accessor it is missing to `scripts/entities/launcher_field.gd`:

```gdscript
## The SAM sites, as positions. Added so the target tracker can see them
## without the launcher field learning what a target tracker is.
func launcher_positions() -> Array:
	var out := []
	for id in _launchers:
		var launcher: Dictionary = _launchers[id]
		out.append({"id": int(id), "position": launcher["position"]})
	return out
```

Read `_spawn_launcher` before writing this and use the key the dictionary actually stores the position under; if the entry is a `Node3D` rather than a dictionary, return `node.global_position` instead. Then the loop in `_update_targeting` becomes:

```gdscript
	for launcher in launcher_field.launcher_positions():
		contacts.append(TARGET_TRACKER.contact(
			int(launcher["id"]), TARGET_TRACKER.Kind.GROUND_LAUNCHER,
			launcher["position"], Vector3.ZERO, "SAM"
		))
```

Now replace the body of `_unhandled_input` from the `var hit := GROUND_RAY.intersect(...)` line to the end of the function with:

```gdscript
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var hit := GROUND_RAY.intersect(origin, direction, _ground_height_xz)
	var point = null
	var kind: int = TARGET_TRACKER.Kind.GROUND_POINT
	var name := ""
	if not hit.is_empty():
		point = hit["point"]
	# `_hit_query` is already built in main.gd (line 1452) and already knows how
	# to tell a building from the dirt, so the lock asks it rather than growing
	# a second opinion about what the ray struck.
	if _hit_query != null:
		var world: RefCounted = _hit_query.query_segment(origin, origin + direction * 12000.0)
		if world.hit and world.object_type == WORLD_HIT.ObjectKind.BUILDING:
			point = world.position
			kind = TARGET_TRACKER.Kind.BUILDING
			name = "BUILDING"
	var handle := _tracker.lock_at(origin, direction, point, kind, name)
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
```

**Note:** `WORLD_HIT` is already preloaded in `main.gd` at line 25, and `_hit_query` is already assigned at line 1452 — neither needs adding. `building_hit_index.gd` offers `query_segment` and `buildings_near` but no point query, which is why the segment query is used here.

Finally, **remove** the now-duplicated instrument call: `attack_reticle.set_instruments(...)` is superseded by the helmet's tapes. Delete the call site in `main.gd` and leave `attack_reticle.set_instruments` in place unused — the helicopter still needs it, and removing it is not this phase's business.

- [ ] **Step 4: Run the whole suite**

```bash
for t in tests/target_tracker_test.gd tests/hud_projection_test.gd tests/helmet_hud_test.gd \
         tests/radar_scope_test.gd tests/enemy_jet_test.gd tests/enemy_squadron_test.gd \
         tests/helmet_wiring_test.gd tests/jet_controls_test.gd tests/jet_runtime_test.gd; do
  echo "--- $t"
  godot --headless --script "$t" 2>&1 | grep -E "PASS|ERROR:|SCRIPT ERROR" || echo "NO RESULT"
done
```

Expected: a `*_TEST_PASS` line for each, and no `ERROR:` or `SCRIPT ERROR` lines from any of them.

- [ ] **Step 5: Commit**

```bash
git add scripts/main.gd scripts/entities/launcher_field.gd scenes/main.tscn tests/helmet_wiring_test.gd
git commit -m "Put the tracker between the world and the glass"
```

---

### Task 9: See it on the phone

**Files:**
- Modify: none unless the device says so.

**Interfaces:**
- Consumes: the whole feature.
- Produces: a build, and evidence.

**Why this task exists:** green unit tests are not a working agent. Nothing in Tasks 1-8 has been seen by a human. The visor is a *look*, and a look can only be judged on the glass.

- [ ] **Step 1: Export the APK**

```bash
Godot_v4.7.2-stable_linux.arm64 --headless --export-debug "Android" build/OpenStrike-helmet.apk
cp build/OpenStrike-helmet.apk /sdcard/Download/
```

Expected: an APK around 134 MB, no `ERROR:` in the export output.

- [ ] **Step 2: Ask the user to install and launch it**

The user installs from `/sdcard/Download/OpenStrike-helmet.apk` and launches the game. Do not proceed until they confirm it is running — and confirm the build is the new one via telemetry before diagnosing anything, because running an old APK by mistake has cost this project a debugging session before.

- [ ] **Step 3: Take the screenshots**

```bash
python3 tools/telemetry_cmd.py '{"screenshot": true}' --out /tmp/helmet-level.png
```

Capture and read each of these with the Read tool:
1. Level flight — horizon across the middle, ladder symmetrical, FPM near the boresight
2. 45 degrees of roll — the horizon and ladder cant with the world, the tapes do not move
3. A climb — the FPM sits above the horizon
4. Free-look hard left — conformal symbols swing off, the tapes stay put
5. A squadron inbound on the scope, at each of the four ranges
6. A lock held through a hard turn
7. The lock off-screen — the amber chevron on the screen edge with its range

- [ ] **Step 4: Report honestly**

State which of the seven were verified and which were not. If the framerate has dropped below the 97-117 fps the weather build held in F-22 views, say so with the number. Do not claim the phase works on the strength of the tests alone.

- [ ] **Step 5: Commit any device-driven fixes**

```bash
git add -A
git commit -m "Tune the visor against the glass"
```

---

## Constants Reference

Every number below is a starting point to be tuned on the phone, not a result.

| Constant | Value | Where |
| --- | --- | --- |
| `RADAR_RANGES_M` | `[5000, 10000, 20000, 40000]` | `target_tracker.gd` |
| `DEFAULT_RANGE_INDEX` | 1 (10 km) | `target_tracker.gd` |
| `TRACK_CONE_DEGREES` | 60 | `target_tracker.gd` |
| `MAX_TRACKED_BOXES` | 12 | `target_tracker.gd` |
| `LOCK_TOLERANCE_DEGREES` | 4 | `target_tracker.gd` |
| `CONFORMAL_DISTANCE_M` | 50000 | `hud_projection.gd` |
| `PITCH_LADDER_STEP_DEGREES` | 5 | `hud_projection.gd` |
| `FPM_MIN_SPEED_MPS` | 20 | `hud_projection.gd` |
| `BOX_MAX_PX` / `BOX_MIN_PX` | 44 / 7 | `helmet_hud.gd` |
| `SCOPE_CENTRE_ALPHA` | 0.45 | `radar_scope.gd` |
| `BLIP_MIN_ALPHA` | 0.35 | `radar_scope.gd` |
| `BLIP_SOFT_FRACTION` | 0.6 | `radar_scope.gd` |
| `SWEEP_PERIOD_S` | 2.5 | `radar_scope.gd` |
| `ENEMY_CRUISE_MPS` | 200 | `enemy_jet.gd` |
| `ENEMY_DASH_MPS` | 380 | `enemy_jet.gd` |
| `ENEMY_TURN_RATE` | 0.32 rad/s | `enemy_jet.gd` |
| `MERGE_RANGE_M` | 2500 | `enemy_jet.gd` |
| `THREAT_RANGE_M` | 1600 | `enemy_jet.gd` |
| `EGRESS_AFTER_SECONDS` | 45 | `enemy_jet.gd` |
| `SPAWN_RANGE_M` | 16000 | `enemy_squadron.gd` |
| `SPAWN_ALTITUDE_MIN_M` / `MAX_M` | 2000 / 6000 | `enemy_squadron.gd` |
| `FORMATION_SPACING_M` | 300 | `enemy_squadron.gd` |
| `FIRST_ID` | 200000 | `enemy_squadron.gd` |
