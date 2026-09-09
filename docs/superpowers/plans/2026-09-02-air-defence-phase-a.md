# Air Defence Phase A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ten evasive mini-Raptor drones on attack runs against the Gold Coast skyline, a radar scope and cockpit bearing tape to find them with, a mission loop counting drones left against buildings lost, and a cleared screen with everything else tucked into settings.

**Architecture:** Drones are pure kinematic state machines (`drone.gd`, `RefCounted`, headless-testable) owned by a `drone_field.gd` node that mirrors `launcher_field.gd`: it spawns visuals, refreshes each drone's AABB in an `EntityHitIndex` every frame so every projectile in the game can hit them, and fires bombs through the existing `projectile_manager`. The radar and tape are `Control`s whose geometry is static functions, so the maths is tested and only the pixels are a device check. The mission panel is deleted from the scene and its one live line moves to a code-built HUD.

**Tech Stack:** Godot 4.7.2, GDScript. No physics server, no `RigidBody3D`.

**Spec:** `docs/superpowers/specs/2026-09-02-air-defence-phase-a-design.md`

## Global Constraints

- Godot binary: `/root/godot-dist/Godot_v4.7.2-stable_linux.arm64`
- Test command shape: `<godot> --headless --script tests/<name>_test.gd`
- Tests are `extends SceneTree`, work in `_init()`, print `<NAME>_TEST_PASS` and `quit()`. Failure is `_fail(message)` → `push_error` then `quit(1)`. A test that uses `assert()` and trips it **hangs** rather than exits (the tree never reaches `quit()`); always run with `timeout 90`.
- A test passes only if `<NAME>_TEST_PASS` appears in stdout.
- Suite: 42 tests green before this plan, 48 after.
- Comments explain **why**. Where a constant exists because something failed without it, record the failure beside it.
- Branch: continue on `jet-weapons-phase1`. Phase 1 is unflown; this stacks on it deliberately so one APK carries both.
- **Entity ID spaces must not collide.** `launcher_field` numbers from 1. `drone_field` numbers from `100000`. `_on_projectile_impacted` routes by which field claims the id.
- Spec constants, verbatim: `DRONE_COUNT` 10, `DRONE_WINGSPAN_M` 5.5, `DRONE_CRUISE_MPS` 95, `DRONE_DASH_MPS` 150, `DRONE_TURN_RATE` 0.9, `ATTACK_ENTRY_RANGE` 2500, `BOMB_RELEASE_RANGE` 350, `THREAT_RANGE` 1400, `THREAT_CONE_DEGREES` 25, `DASH_SECONDS` 4.0, `JINK_INTERVAL` 1.6, `EVADE_SECONDS` 5.0, `EGRESS_SECONDS` 12.0, `RAID_FAILS_AT` 5, `RADAR_RANGE_M` 4000, `TAPE_HALF_WIDTH_DEGREES` 60.

**Refinements on the spec, recorded here:**
- `BOMB_DAMAGE` is expressed as a `structural_damage` of **320** on a damage profile, because `building_damage_system.apply_hit` reads that field and applies ×1.35 to roof strikes: one roof hit reaches 432, past the 420 smoke threshold. "Destroyed in two" is the mission's own `BUILDING_LOST_AT` of 640 accumulated damage — the damage system has no destroy notion, only smoke, so the mission owns "lost".
- Drone spawn is a **ring at the theatre edge on the +X side**, spread across a 120° arc. The launchers sit along a beach at x≈0 with the sea to +X, so this is seaward for Surfers and theatre-agnostic elsewhere.
- Evasion "away from the player's turn direction" is implemented as **away from the player's nose**: the drone breaks to whichever side increases its angle-off from the nose. That needs no knowledge of the player's roll rate and is what a warning receiver could actually infer.

---

### Task 1: `buildings_near` on the building index

Drones need to pick the tallest building in their forward cone. The index has handles and heights already; it just has no way to list them by area.

**Files:**
- Modify: `scripts/terrain/building_hit_index.gd` (append one function)
- Test: `tests/building_hit_index_test.gd` (append assertions)

**Interfaces:**
- Consumes: nothing.
- Produces: `buildings_near(centre: Vector2, radius: float) -> Array` of `{handle: int, position: Vector3, height: float}` where `position` is the footprint centre at `top_height`.

- [ ] **Step 1: Append the failing assertions**

In `tests/building_hit_index_test.gd`, before the final `print(...)`/`quit()` in `_initialize()`, add:

```gdscript
	# Drones pick targets by area. The list must carry height, because they go
	# for the skyline, and a building outside the radius must not appear.
	var area: RefCounted = INDEX.new()
	area.add_chunk(0, [
		_square(1, 0.0, 0.0, 10.0, 20.0),
		_square(2, 100.0, 0.0, 10.0, 80.0),
		_square(3, 5000.0, 0.0, 10.0, 200.0),
	], flat)
	var near: Array = area.buildings_near(Vector2(50.0, 0.0), 200.0)
	assert(near.size() == 2, "two buildings sit inside 200 m, got %d" % near.size())
	var tallest_height := 0.0
	for entry in near:
		assert(entry.has("handle") and entry.has("position") and entry.has("height"), "entries carry handle, position, height")
		tallest_height = maxf(tallest_height, float(entry["height"]))
	assert(is_equal_approx(tallest_height, 80.0), "the 80 m tower must be listed with its height")
	assert(area.buildings_near(Vector2(50.0, 0.0), 10.0).is_empty(), "nothing inside 10 m of a point between buildings")
```

- [ ] **Step 2: Run to verify it hangs/fails**

```bash
cd /root/OpenStrike && timeout 60 /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/building_hit_index_test.gd 2>&1 | grep -oE "_TEST_PASS|Invalid call[^\"]{0,60}|Nonexistent[^\"]{0,60}" | head -2
```

Expected: `Nonexistent function 'buildings_near'` and no `_TEST_PASS`.

- [ ] **Step 3: Implement**

Append to `scripts/terrain/building_hit_index.gd`:

```gdscript
## Every building whose footprint centre lies within `radius` of `centre`, with
## its height. Drones choose attack targets from this; the cell grid is not
## used because a 2.5 km entry range spans most of the city anyway and a plain
## scan of a few hundred records is cheaper than assembling cell lists.
func buildings_near(centre: Vector2, radius: float) -> Array:
	var found: Array = []
	var radius_squared := radius * radius
	for handle in buildings:
		var building: Dictionary = buildings[handle]
		var footprint_centre: Vector2 = (building["minimum"] + building["maximum"]) * 0.5
		if footprint_centre.distance_squared_to(centre) > radius_squared:
			continue
		found.append({
			"handle": int(handle),
			"position": Vector3(footprint_centre.x, float(building["top_height"]), footprint_centre.y),
			"height": float(building["building_height"]),
		})
	return found
```

- [ ] **Step 4: Run to verify it passes**

Same command. Expected: `BUILDING_HIT_INDEX_TEST_PASS` (check the file's exact pass string with `grep _PASS tests/building_hit_index_test.gd`).

- [ ] **Step 5: Commit**

```bash
git add scripts/terrain/building_hit_index.gd tests/building_hit_index_test.gd
git commit -m "List buildings by area, with their heights

Drones choose the tallest building in their forward cone. The index had
handles and heights but no way to ask for them by area."
```

---

### Task 2: Bomb flight model

**Files:**
- Create: `scripts/weapons/bomb_flight.gd`
- Create: `scripts/weapons/bomb_damage_profile.gd`
- Test: `tests/bomb_flight_test.gd`

**Interfaces:**
- Consumes: the flight-model contract from phase 1 (`advance(point, velocity, delta, age)`, `envelope_seconds()`, `envelope_metres()`).
- Produces: `BombFlight` (`RefCounted`) with those three, plus `release_velocity(carrier_velocity: Vector3) -> Vector3`. `BombDamageProfile` (`Resource`) with `structural_damage := 320.0`.

- [ ] **Step 1: Write the failing test**

Create `tests/bomb_flight_test.gd`:

```gdscript
extends SceneTree

## A bomb is a shell with no muzzle: it leaves at the carrier's speed and falls.
## Nothing here thrusts, which is the whole difference from a rocket.

const BOMB := preload("res://scripts/weapons/bomb_flight.gd")
const PROFILE := preload("res://scripts/weapons/bomb_damage_profile.gd")


func _init() -> void:
	var flight = BOMB.new()
	var carried := Vector3(0.0, 0.0, -95.0)
	var released: Vector3 = flight.release_velocity(carried)
	if not released.is_equal_approx(carried):
		_fail("a bomb leaves at exactly the carrier's velocity, got %v" % released)

	var stepped: Array = flight.advance(Vector3(0.0, 600.0, 0.0), carried, 0.05, 0.0)
	var after: Vector3 = stepped[1]
	if after.y >= 0.0:
		_fail("a bomb must fall, got vy %f" % after.y)
	if after.z > carried.z + 0.001:
		_fail("a bomb must not accelerate forward, got vz %f" % after.z)
	if absf(after.z) > absf(carried.z) + 0.001:
		_fail("drag must not add speed")

	if flight.envelope_seconds() < 30.0:
		_fail("a bomb from 900 m needs over thirty seconds to land, got %f" % flight.envelope_seconds())
	if flight.envelope_metres() < 3000.0:
		_fail("a bomb released at speed travels well past a kilometre")

	var profile = PROFILE.new()
	if float(profile.structural_damage) * 1.35 < 420.0:
		_fail("one roof strike must reach the smoke threshold, got %f" % (profile.structural_damage * 1.35))
	if float(profile.structural_damage) >= 420.0:
		_fail("a facade strike alone must NOT reach the smoke threshold, or every bomb smokes")

	print("BOMB_FLIGHT_TEST_PASS")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /root/OpenStrike && timeout 60 /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/bomb_flight_test.gd 2>&1 | grep -oE "BOMB_FLIGHT_TEST_PASS|Failed to load script" | head -1
```

Expected: `Failed to load script`.

- [ ] **Step 3: Implement**

Create `scripts/weapons/bomb_flight.gd`:

```gdscript
extends RefCounted

## Free fall. A bomb is a shell with no muzzle velocity: it leaves at the
## carrier's speed and gravity and drag do the rest. It shares the projectile
## manager with shells and rockets, so it hits buildings through the same swept
## segment query and the same damage path.

const GRAVITY := 9.80665
## Draggier than a shell -- an iron bomb is a blunt shape -- but not by much at
## the speeds a drone releases at.
const DRAG_PER_SECOND := 0.12
## From 900 m it takes about 14 s to land; the envelope is generous so a bomb
## never expires in the air.
const MAX_FLIGHT_SECONDS := 40.0
const MAX_RANGE_METRES := 6000.0


func release_velocity(carrier_velocity: Vector3) -> Vector3:
	return carrier_velocity


## Trapezoidal like ballistics.advance, so bombs integrate the way everything
## else does and the hit query sees consistent segments.
func advance(point: Vector3, velocity: Vector3, delta: float, _age := 0.0) -> Array:
	var next_velocity := velocity * exp(-DRAG_PER_SECOND * delta)
	next_velocity.y -= GRAVITY * delta
	var next_point := point + (velocity + next_velocity) * 0.5 * delta
	return [next_point, next_velocity]


func envelope_seconds() -> float:
	return MAX_FLIGHT_SECONDS


func envelope_metres() -> float:
	return MAX_RANGE_METRES
```

Create `scripts/weapons/bomb_damage_profile.gd`:

```gdscript
extends Resource

## What a bomb does to a building. building_damage_system reads
## `structural_damage` and multiplies a roof strike by 1.35, so 320 puts one
## roof hit at 432 -- past the 420 smoke threshold -- while a facade graze at
## 320 does not. The raid's "building lost" line sits at twice this.

@export var structural_damage := 320.0
```

- [ ] **Step 4: Run to verify it passes**

Expected: `BOMB_FLIGHT_TEST_PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/weapons/bomb_flight.gd scripts/weapons/bomb_damage_profile.gd tests/bomb_flight_test.gd
git commit -m "Add a bomb: a shell with no muzzle

Leaves at the carrier's speed and falls. Rides the same projectile manager as
everything else, so it hits buildings through the same swept query and the
same damage path. One roof strike smokes a building; the raid decides when one
is lost."
```

---

### Task 3: The drone

The whole behaviour, pure and headless. Position, heading, state machine, threat detection, evasion. No node, no mesh, no index.

**Files:**
- Create: `scripts/entities/drone.gd`
- Test: `tests/drone_test.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Drone` (`RefCounted`) with:
  - `enum State {INBOUND, ATTACK_RUN, EVADING, EGRESS, DESTROYED}`
  - fields `position: Vector3`, `velocity: Vector3`, `heading: float` (radians, same convention as `jet_controller.heading_of`: `atan2(nose.x, -nose.z)`), `state: int`, `target_handle: int`, `target_position: Vector3`, `speed: float`, `id: int`
  - `update(delta: float, player_position: Vector3, player_nose: Vector3, city_centre: Vector3, rng: RandomNumberGenerator) -> bool` — advances one step and returns **true if a bomb should be released this frame**
  - `assign_target(handle: int, at: Vector3) -> void` — enters `ATTACK_RUN`
  - `wants_target() -> bool` — `INBOUND` and within `ATTACK_ENTRY_RANGE` of `city_centre` on the last update
  - `is_threatened(player_position, player_nose) -> bool` (public for tests)
  - `destroy() -> void`
  - `nose() -> Vector3`, `bank() -> float` (for the visual)
  - constants as in Global Constraints, plus `INBOUND_ALTITUDE` 700, `MIN_ALTITUDE` 120, `DROP_BELOW_PLAYER` 150, `CLIMB_RATE` 25.

- [ ] **Step 1: Write the failing test**

Create `tests/drone_test.gd`:

```gdscript
extends SceneTree

## Evasion is what makes a drone worth chasing. These pin the rules: it breaks
## AWAY from the player's nose and never toward it, it dashes, it jinks, and it
## aborts an attack run rather than pressing through the guns.

const DRONE := preload("res://scripts/entities/drone.gd")

const STEP := 1.0 / 60.0


func _init() -> void:
	_flies_toward_the_city()
	_threat_needs_range_cone_and_closure()
	_breaks_away_from_the_nose()
	_dashes_when_threatened()
	_jinks_reverse()
	_aborts_the_run_when_threatened()
	_resumes_after_the_threat_clears()
	_releases_a_bomb_at_range()
	print("DRONE_TEST_PASS")
	quit()


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return rng


## A drone at the +X edge, heading west toward a city at the origin.
func _inbound() -> RefCounted:
	var drone = DRONE.new()
	drone.position = Vector3(6000.0, DRONE.INBOUND_ALTITUDE, 0.0)
	drone.heading = atan2(-1.0, 0.0)  # nose along -X
	drone.speed = DRONE.DRONE_CRUISE_MPS
	drone.velocity = drone.nose() * drone.speed
	return drone


func _far_player() -> Vector3:
	return Vector3(0.0, 800.0, 20000.0)


func _flies_toward_the_city() -> void:
	var drone := _inbound()
	var start := drone.position.x
	for _i in range(120):
		drone.update(STEP, _far_player(), Vector3(0.0, 0.0, -1.0), Vector3.ZERO, _rng())
	if drone.position.x >= start:
		_fail("an inbound drone must close on the city, x went %f -> %f" % [start, drone.position.x])
	if drone.state != DRONE.State.INBOUND:
		_fail("unthreatened and far from the city, the drone stays INBOUND")


func _threat_needs_range_cone_and_closure() -> void:
	var drone := _inbound()
	# Player 800 m behind, nose on the drone, and closing.
	var behind := drone.position + Vector3(800.0, 0.0, 0.0)
	var nose_on := Vector3(-1.0, 0.0, 0.0)
	drone.update(STEP, behind + Vector3(10.0, 0.0, 0.0), nose_on, Vector3.ZERO, _rng())
	if not drone.is_threatened(behind, nose_on):
		_fail("in range, in the cone and closing must be a threat")
	# Same range, nose pointed 90 degrees away: not a threat.
	if drone.is_threatened(behind, Vector3(0.0, 0.0, 1.0)):
		_fail("a player not pointing at the drone is not a threat")
	# Nose on but far away: not a threat.
	if drone.is_threatened(drone.position + Vector3(5000.0, 0.0, 0.0), nose_on):
		_fail("a player outside threat range is not a threat")


func _breaks_away_from_the_nose() -> void:
	var drone := _inbound()
	# Player behind and slightly to the drone's LEFT (-Z), nose on it. The
	# drone must break RIGHT (+Z), increasing the angle off the nose.
	var player := drone.position + Vector3(800.0, 0.0, -60.0)
	var nose := (drone.position - player).normalized()
	drone.update(STEP, player + Vector3(5.0, 0.0, 0.0), nose, Vector3.ZERO, _rng())
	var before_z := drone.position.z
	for _i in range(60):
		drone.update(STEP, player, nose, Vector3.ZERO, _rng())
	if drone.state != DRONE.State.EVADING:
		_fail("a threatened drone must be EVADING")
	if drone.position.z <= before_z:
		_fail("the drone must break AWAY from the nose (+Z here), z went %f -> %f" % [before_z, drone.position.z])


func _dashes_when_threatened() -> void:
	var drone := _inbound()
	var player := drone.position + Vector3(800.0, 0.0, 0.0)
	var nose := Vector3(-1.0, 0.0, 0.0)
	drone.update(STEP, player + Vector3(5.0, 0.0, 0.0), nose, Vector3.ZERO, _rng())
	drone.update(STEP, player, nose, Vector3.ZERO, _rng())
	if drone.speed <= DRONE.DRONE_CRUISE_MPS:
		_fail("a threatened drone must dash, speed %f" % drone.speed)
	if drone.speed > DRONE.DRONE_DASH_MPS + 0.001:
		_fail("dash must not exceed the dash speed")


func _jinks_reverse() -> void:
	var drone := _inbound()
	var player := drone.position + Vector3(800.0, 0.0, 0.0)
	var nose := Vector3(-1.0, 0.0, 0.0)
	drone.update(STEP, player + Vector3(5.0, 0.0, 0.0), nose, Vector3.ZERO, _rng())
	drone.update(STEP, player, nose, Vector3.ZERO, _rng())
	var first_sign: float = drone.break_sign
	# Run just past one jink interval.
	var elapsed := 0.0
	while elapsed < DRONE.JINK_INTERVAL + 0.1:
		drone.update(STEP, player, nose, Vector3.ZERO, _rng())
		elapsed += STEP
	if drone.break_sign == first_sign:
		_fail("the break direction must reverse after a jink interval")


func _aborts_the_run_when_threatened() -> void:
	var drone := _inbound()
	drone.assign_target(5, Vector3(0.0, 60.0, 0.0))
	if drone.state != DRONE.State.ATTACK_RUN:
		_fail("assigning a target starts an attack run")
	var player := drone.position + Vector3(800.0, 0.0, 0.0)
	var nose := Vector3(-1.0, 0.0, 0.0)
	drone.update(STEP, player + Vector3(5.0, 0.0, 0.0), nose, Vector3.ZERO, _rng())
	drone.update(STEP, player, nose, Vector3.ZERO, _rng())
	if drone.state != DRONE.State.EVADING:
		_fail("a threatened drone must abort its run, state %d" % drone.state)
	if drone.target_handle != -1:
		_fail("aborting must drop the target")


func _resumes_after_the_threat_clears() -> void:
	var drone := _inbound()
	var player := drone.position + Vector3(800.0, 0.0, 0.0)
	var nose := Vector3(-1.0, 0.0, 0.0)
	drone.update(STEP, player + Vector3(5.0, 0.0, 0.0), nose, Vector3.ZERO, _rng())
	drone.update(STEP, player, nose, Vector3.ZERO, _rng())
	# Threat gone; wait out the evade timer.
	var elapsed := 0.0
	while elapsed < DRONE.EVADE_SECONDS + 0.5:
		drone.update(STEP, _far_player(), Vector3(0.0, 0.0, -1.0), Vector3.ZERO, _rng())
		elapsed += STEP
	if drone.state != DRONE.State.INBOUND:
		_fail("once the threat clears the drone goes back to INBOUND, state %d" % drone.state)
	if drone.speed > DRONE.DRONE_CRUISE_MPS + 0.001:
		_fail("cruise resumes after the dash")


func _releases_a_bomb_at_range() -> void:
	var drone := _inbound()
	drone.position = Vector3(DRONE.BOMB_RELEASE_RANGE + 400.0, 300.0, 0.0)
	drone.assign_target(5, Vector3(0.0, 60.0, 0.0))
	var released := false
	for _i in range(600):
		if drone.update(STEP, _far_player(), Vector3(0.0, 0.0, -1.0), Vector3.ZERO, _rng()):
			released = true
			break
	if not released:
		_fail("an unthreatened attack run must release a bomb")
	if drone.state != DRONE.State.EGRESS:
		_fail("after release the drone egresses, state %d" % drone.state)
	if drone.position.distance_to(Vector3(0.0, 60.0, 0.0)) > DRONE.BOMB_RELEASE_RANGE + 60.0:
		_fail("release must happen near the release range")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /root/OpenStrike && timeout 60 /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/drone_test.gd 2>&1 | grep -oE "DRONE_TEST_PASS|Failed to load script" | head -1
```

Expected: `Failed to load script`.

- [ ] **Step 3: Implement**

Create `scripts/entities/drone.gd`:

```gdscript
extends RefCounted

## One drone: where it is, what it is doing, and how it gets away from you.
##
## Kinematic, not aerodynamic. Attitude is derived from the path so it banks
## into turns and looks like an aircraft, but there is no lift and no drag;
## nobody can tell a drone is obeying a drag polar, and ten flight models on a
## phone would be paid for in framerate.
##
## The behaviour that matters is evasion. A threatened drone breaks AWAY from
## the player's nose -- never toward it, that is a head-on and the drone loses
## it -- dashes, jinks on a timer so it cannot be led with a steady deflection,
## and drops below the player where a gun fighter least wants to follow. And it
## ABORTS its attack run: a pilot on a drone's tail saves the building without
## firing; shooting it down is what stops it coming back.

enum State {INBOUND, ATTACK_RUN, EVADING, EGRESS, DESTROYED}

const DRONE_CRUISE_MPS := 95.0
## Briefly above the F-22's cruise, so a chase is a chase.
const DRONE_DASH_MPS := 150.0
## rad/s. Tighter than the F-22 at speed, looser than it at corner.
const DRONE_TURN_RATE := 0.9
const ATTACK_ENTRY_RANGE := 2500.0
const BOMB_RELEASE_RANGE := 350.0
## Roughly gun-plus-rocket reach.
const THREAT_RANGE := 1400.0
## Pointing at it, not merely near it.
const THREAT_CONE_DEGREES := 25.0
const DASH_SECONDS := 4.0
## Shorter than the time it takes to settle a lead.
const JINK_INTERVAL := 1.6
const EVADE_SECONDS := 5.0
const EGRESS_SECONDS := 12.0

const INBOUND_ALTITUDE := 700.0
const MIN_ALTITUDE := 120.0
## How far under the player an evading drone tries to get.
const DROP_BELOW_PLAYER := 150.0
## Vertical rate cap, so altitude changes read as flight rather than as lifts.
const CLIMB_RATE := 25.0

var id := 0
var position := Vector3.ZERO
var velocity := Vector3.ZERO
## Radians, same convention as jet_controller.heading_of: atan2(nose.x, -nose.z).
var heading := 0.0
var speed := DRONE_CRUISE_MPS
var state: int = State.INBOUND
var target_handle := -1
var target_position := Vector3.ZERO
## +1 or -1: which way the current break goes. Public so the jink test can see
## it reverse.
var break_sign := 1.0

var _target_altitude := INBOUND_ALTITUDE
var _evade_remaining := 0.0
var _dash_remaining := 0.0
var _jink_remaining := 0.0
var _egress_remaining := 0.0
var _last_range := INF
var _near_city := false
var _desired_heading := 0.0


func nose() -> Vector3:
	return Vector3(sin(heading), 0.0, -cos(heading))


## Bank for the visual: proportional to how hard the heading is changing.
func bank() -> float:
	var error := wrapf(_desired_heading - heading, -PI, PI)
	return clampf(error * 1.4, -1.1, 1.1)


func wants_target() -> bool:
	return state == State.INBOUND and target_handle < 0 and _near_city


func assign_target(handle: int, at: Vector3) -> void:
	target_handle = handle
	target_position = at
	state = State.ATTACK_RUN


func destroy() -> void:
	state = State.DESTROYED
	target_handle = -1


## Range, cone and closure together. Any one alone is not a threat: a player
## flying past at 500 m is not attacking, and neither is one pointing at the
## drone from four kilometres.
func is_threatened(player_position: Vector3, player_nose: Vector3) -> bool:
	var to_drone := position - player_position
	var range_m := to_drone.length()
	if range_m > THREAT_RANGE or range_m < 0.001:
		return false
	var cone := cos(deg_to_rad(THREAT_CONE_DEGREES))
	if player_nose.normalized().dot(to_drone / range_m) < cone:
		return false
	return range_m < _last_range


## One step. Returns true if a bomb should be released this frame.
func update(
	delta: float,
	player_position: Vector3,
	player_nose: Vector3,
	city_centre: Vector3,
	rng: RandomNumberGenerator
) -> bool:
	if state == State.DESTROYED:
		# Dead weight: falls, keeps its heading, nothing else.
		velocity.y -= 9.80665 * delta
		position += velocity * delta
		return false

	var release := false
	var threatened := is_threatened(player_position, player_nose)
	_last_range = position.distance_to(player_position)
	_near_city = Vector2(position.x, position.z).distance_to(Vector2(city_centre.x, city_centre.z)) <= ATTACK_ENTRY_RANGE

	if threatened and state != State.EVADING:
		_begin_evasion(player_position, player_nose)
	if state == State.EVADING and threatened:
		# Every frame under threat resets the clock, so the drone keeps
		# evading for EVADE_SECONDS after the LAST moment it was threatened.
		_evade_remaining = EVADE_SECONDS

	match state:
		State.INBOUND:
			_desired_heading = _heading_to(city_centre)
			_target_altitude = INBOUND_ALTITUDE
		State.ATTACK_RUN:
			_desired_heading = _heading_to(target_position)
			# Descend onto the target so the run reads as a dive, but never
			# under the minimum: a drone that flies into the sea is a bug.
			_target_altitude = maxf(target_position.y + 120.0, MIN_ALTITUDE)
			if Vector2(position.x, position.z).distance_to(Vector2(target_position.x, target_position.z)) <= BOMB_RELEASE_RANGE:
				release = true
				_begin_egress(city_centre)
		State.EVADING:
			_update_evasion(delta, player_position, rng)
		State.EGRESS:
			_target_altitude = INBOUND_ALTITUDE
			_egress_remaining -= delta
			if _egress_remaining <= 0.0:
				state = State.INBOUND

	_steer(delta)
	return release


func _heading_to(point: Vector3) -> float:
	var to_point := point - position
	return atan2(to_point.x, -to_point.z)


func _begin_evasion(player_position: Vector3, player_nose: Vector3) -> void:
	state = State.EVADING
	target_handle = -1
	_evade_remaining = EVADE_SECONDS
	_dash_remaining = DASH_SECONDS
	_jink_remaining = JINK_INTERVAL
	speed = DRONE_DASH_MPS
	# Break to the side that increases the angle off the player's nose. The
	# sign of the cross product of nose and approach says which side of the
	# nose the drone is already on; going further that way is "away".
	var approach := position - player_position
	var cross_y := player_nose.x * approach.z - player_nose.z * approach.x
	break_sign = 1.0 if cross_y >= 0.0 else -1.0


func _update_evasion(delta: float, player_position: Vector3, rng: RandomNumberGenerator) -> void:
	_evade_remaining -= delta
	_dash_remaining -= delta
	_jink_remaining -= delta
	if _jink_remaining <= 0.0:
		_jink_remaining = JINK_INTERVAL * rng.randf_range(0.7, 1.3)
		break_sign = -break_sign
	if _dash_remaining <= 0.0:
		speed = DRONE_CRUISE_MPS
	# Perpendicular to the line from the player, on the chosen side.
	var from_player := position - player_position
	from_player.y = 0.0
	if from_player.is_zero_approx():
		from_player = nose()
	var away_heading := atan2(from_player.x, -from_player.z)
	_desired_heading = away_heading + break_sign * PI * 0.5
	# Drop under the player if there is room. A gun fighter hates looking down.
	_target_altitude = maxf(player_position.y - DROP_BELOW_PLAYER, MIN_ALTITUDE)
	if _evade_remaining <= 0.0:
		state = State.INBOUND
		speed = DRONE_CRUISE_MPS


func _begin_egress(city_centre: Vector3) -> void:
	state = State.EGRESS
	target_handle = -1
	_egress_remaining = EGRESS_SECONDS
	# Turn back the way it came: away from the city.
	var away := position - city_centre
	_desired_heading = atan2(away.x, -away.z)


## Turn toward the desired heading at the rate cap, hold speed, and ease toward
## the target altitude. Position integrates from the resulting velocity.
func _steer(delta: float) -> void:
	var error := wrapf(_desired_heading - heading, -PI, PI)
	var turn := clampf(error, -DRONE_TURN_RATE * delta, DRONE_TURN_RATE * delta)
	heading = wrapf(heading + turn, -PI, PI)
	var vertical := clampf(_target_altitude - position.y, -CLIMB_RATE, CLIMB_RATE)
	velocity = nose() * speed + Vector3(0.0, vertical, 0.0)
	position += velocity * delta
```

- [ ] **Step 4: Run to verify it passes**

Expected: `DRONE_TEST_PASS`. If `_breaks_away_from_the_nose` fails, the sign of `cross_y` is the first thing to check — the test fixes the geometry (player left of the drone, so the break must be +Z) and the implementation must match it, not the other way round.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/drone.gd tests/drone_test.gd
git commit -m "Add the drone: kinematic, and hard to catch

Breaks away from the player's nose and never toward it, dashes, jinks on a
timer so it cannot be led, drops under the player, and aborts its attack run
rather than pressing through the guns. A pilot on its tail saves the building
without firing; shooting it down is what stops it coming back."
```

---

### Task 4: Raid mission

**Files:**
- Create: `scripts/entities/raid_mission.gd`
- Test: `tests/raid_mission_test.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `RaidMission` (`RefCounted`) with `drones_remaining: int`, `buildings_lost: int`, `buildings_hit: int`, `ended: bool`, `won: bool`; `start(drone_count: int) -> void`; `drone_destroyed() -> void`; `building_damaged(building_id: int, accumulated: float) -> void`; `hud_line() -> String`; signal `raid_ended(won: bool)`; constants `RAID_FAILS_AT` 5, `BUILDING_LOST_AT` 640.0.

- [ ] **Step 1: Write the failing test**

Create `tests/raid_mission_test.gd`:

```gdscript
extends SceneTree

## The loop: drones down against buildings lost. Win at zero drones, lose at
## the threshold, and a restart puts it all back.

const MISSION := preload("res://scripts/entities/raid_mission.gd")


func _init() -> void:
	var mission = MISSION.new()
	var outcomes: Array[bool] = []
	mission.raid_ended.connect(func(won: bool) -> void: outcomes.append(won))

	mission.start(3)
	if mission.drones_remaining != 3 or mission.ended:
		_fail("start sets the drone count and clears ended")
	mission.drone_destroyed()
	mission.drone_destroyed()
	if mission.ended:
		_fail("one drone left is not a win")
	mission.drone_destroyed()
	if not mission.ended or not mission.won:
		_fail("zero drones is a win")
	if outcomes != [true]:
		_fail("raid_ended must fire once with true, got %s" % [outcomes])

	# Loss. Each building needs BUILDING_LOST_AT accumulated damage, and it
	# must be counted once however many more hits it takes.
	mission.start(10)
	outcomes.clear()
	for building in range(MISSION.RAID_FAILS_AT):
		mission.building_damaged(building, MISSION.BUILDING_LOST_AT * 0.5)
		if mission.buildings_lost != building:
			_fail("half the lost threshold must not count as lost")
		mission.building_damaged(building, MISSION.BUILDING_LOST_AT)
		mission.building_damaged(building, MISSION.BUILDING_LOST_AT * 3.0)
	if mission.buildings_lost != MISSION.RAID_FAILS_AT:
		_fail("each building lost counts exactly once, got %d" % mission.buildings_lost)
	if not mission.ended or mission.won:
		_fail("losing the threshold of buildings is a loss")
	if outcomes != [false]:
		_fail("raid_ended must fire once with false, got %s" % [outcomes])
	if mission.hud_line().find("DRONES 10") < 0:
		_fail("the HUD line must show drones remaining, got '%s'" % mission.hud_line())
	if mission.hud_line().find("%d/%d" % [MISSION.RAID_FAILS_AT, MISSION.RAID_FAILS_AT]) < 0:
		_fail("the HUD line must show buildings lost over the limit, got '%s'" % mission.hud_line())

	# After the end nothing moves the counters.
	mission.drone_destroyed()
	if mission.drones_remaining != 10:
		_fail("a finished raid must not keep counting")

	print("RAID_MISSION_TEST_PASS")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /root/OpenStrike && timeout 60 /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/raid_mission_test.gd 2>&1 | grep -oE "RAID_MISSION_TEST_PASS|Failed to load script" | head -1
```

Expected: `Failed to load script`.

- [ ] **Step 3: Implement**

Create `scripts/entities/raid_mission.gd`:

```gdscript
extends RefCounted

## The loop the raid gives the player: drones down against buildings lost.
##
## "Lost" is the mission's word, not the damage system's. building_damage_system
## only knows about smoke, at 420 accumulated; a building is lost here at twice
## a bomb, so one bomb smokes it and a second finishes it.

signal raid_ended(won: bool)

const RAID_FAILS_AT := 5
## Twice a bomb's structural damage of 320.
const BUILDING_LOST_AT := 640.0

var drones_remaining := 0
var buildings_lost := 0
var buildings_hit := 0
var ended := false
var won := false

var _lost: Dictionary = {}
var _hit: Dictionary = {}


func start(drone_count: int) -> void:
	drones_remaining = drone_count
	buildings_lost = 0
	buildings_hit = 0
	ended = false
	won = false
	_lost.clear()
	_hit.clear()


func drone_destroyed() -> void:
	if ended:
		return
	drones_remaining = maxi(drones_remaining - 1, 0)
	if drones_remaining == 0:
		_finish(true)


## Fed from building_damage_system.building_damaged. Accumulated is the total
## the damage system has recorded for that building, so this is idempotent
## per building: it counts a loss once however many more hits land.
func building_damaged(building_id: int, accumulated: float) -> void:
	if ended:
		return
	if not _hit.has(building_id):
		_hit[building_id] = true
		buildings_hit += 1
	if accumulated >= BUILDING_LOST_AT and not _lost.has(building_id):
		_lost[building_id] = true
		buildings_lost += 1
		if buildings_lost >= RAID_FAILS_AT:
			_finish(false)


func hud_line() -> String:
	if ended:
		return "RAID %s -- DRONES %d  BUILDINGS %d/%d" % [
			"REPELLED" if won else "FAILED", drones_remaining, buildings_lost, RAID_FAILS_AT
		]
	return "DRONES %d  BUILDINGS %d/%d" % [drones_remaining, buildings_lost, RAID_FAILS_AT]


func _finish(victory: bool) -> void:
	ended = true
	won = victory
	raid_ended.emit(victory)
```

- [ ] **Step 4: Run to verify it passes**

Expected: `RAID_MISSION_TEST_PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/raid_mission.gd tests/raid_mission_test.gd
git commit -m "Add the raid's scoreboard

Drones down against buildings lost; win at zero, lose at five. A building is
lost at twice a bomb, which is the mission's word for it -- the damage system
only knows about smoke."
```

---

### Task 5: Drone field and a second entity source for the hit query

The node that owns the drones: spawns mini-Raptors, refreshes their AABBs every frame, assigns targets from the building index, fires bombs through the projectile manager, and answers `query_segment`. Plus the one-line change that lets the world hit query see it.

**Files:**
- Create: `scripts/entities/drone_field.gd`
- Modify: `scripts/world/world_hit_query.gd:11-12` (second entity index), `:26-32` (query both)
- Test: `tests/drone_field_test.gd`

**Interfaces:**
- Consumes: `Drone` (Task 3), `BombFlight` + `BombDamageProfile` (Task 2), `buildings_near` (Task 1), `projectile_manager.acquire_round()/spawn()`, `EntityHitIndex`.
- Produces: `DroneField` (`Node3D`) with `populate(count: int, half_extent: float, city_centre: Vector3) -> void`, `clear() -> void`, `update(delta, player_position, player_nose) -> void`, `query_segment(from, to) -> RefCounted`, `destroy_drone(entity_id: int) -> Variant` (explosion position or null), `drone_count() -> int`, `drones() -> Array` (of `Drone`), properties `projectile_manager`, `building_index`, `hit_index`; signal `bomb_released(round_data)`; `FIRST_ID` 100000. `WorldHitQuery.secondary_entity_index: Object`.

- [ ] **Step 1: Write the failing test**

Create `tests/drone_field_test.gd`:

```gdscript
extends SceneTree

## The field is what makes drones real to the rest of the game: an AABB that
## follows each one so rounds can hit it, a target picked off the building
## index, a bomb fired through the projectile manager. The visuals are not
## asserted; headless cannot see them.

const FIELD := preload("res://scripts/entities/drone_field.gd")
const DRONE := preload("res://scripts/entities/drone.gd")
const PROJECTILE_MANAGER := preload("res://scripts/weapons/projectile_manager.gd")
const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")
const BUILDING_INDEX := preload("res://scripts/terrain/building_hit_index.gd")
const HIT_QUERY := preload("res://scripts/world/world_hit_query.gd")

const STEP := 1.0 / 60.0


func _init() -> void:
	_spawns_at_the_edge_with_unique_ids()
	_bounds_follow_the_drone()
	_a_segment_through_a_drone_hits_it()
	_destroy_removes_it_from_the_index()
	_picks_a_target_and_bombs_it()
	_the_hit_query_sees_both_fields()
	print("DRONE_FIELD_TEST_PASS")
	quit()


func _build() -> Node3D:
	var field = FIELD.new()
	root.add_child(field)
	var manager = PROJECTILE_MANAGER.new()
	manager.ballistics = BALLISTICS.new()
	field.projectile_manager = manager
	field.building_index = BUILDING_INDEX.new()
	return field


func _spawns_at_the_edge_with_unique_ids() -> void:
	var field := _build()
	field.populate(10, 5000.0, Vector3.ZERO)
	if field.drone_count() != 10:
		_fail("ten drones must spawn, got %d" % field.drone_count())
	var ids := {}
	for drone in field.drones():
		if drone.position.length() < 3500.0:
			_fail("drones spawn at the theatre edge, one is at %v" % drone.position)
		if drone.position.x <= 0.0:
			_fail("drones spawn on the +X side, one is at %v" % drone.position)
		ids[drone.id] = true
		if drone.id < FIELD.FIRST_ID:
			_fail("drone ids must not collide with launcher ids, got %d" % drone.id)
	if ids.size() != 10:
		_fail("drone ids must be unique")
	field.free()


func _bounds_follow_the_drone() -> void:
	var field := _build()
	field.populate(1, 5000.0, Vector3.ZERO)
	var drone = field.drones()[0]
	var before: Vector3 = drone.position
	for _i in range(60):
		field.update(STEP, Vector3(0.0, 800.0, 20000.0), Vector3(0.0, 0.0, -1.0))
	# A segment through where it WAS must miss; through where it IS must hit.
	var stale: RefCounted = field.query_segment(before + Vector3(0.0, 0.0, -50.0), before + Vector3(0.0, 0.0, 50.0))
	var fresh: RefCounted = field.query_segment(drone.position + Vector3(0.0, 0.0, -50.0), drone.position + Vector3(0.0, 0.0, 50.0))
	if stale != null and stale.hit:
		_fail("the AABB must move with the drone, a stale segment still hit")
	if fresh == null or not fresh.hit:
		_fail("a segment through the drone's current position must hit")
	field.free()


func _a_segment_through_a_drone_hits_it() -> void:
	var field := _build()
	field.populate(1, 5000.0, Vector3.ZERO)
	field.update(STEP, Vector3(0.0, 800.0, 20000.0), Vector3(0.0, 0.0, -1.0))
	var drone = field.drones()[0]
	var hit: RefCounted = field.query_segment(drone.position + Vector3(-40.0, 0.0, 0.0), drone.position + Vector3(40.0, 0.0, 0.0))
	if hit == null or not hit.hit:
		_fail("a segment through a drone must hit it")
	if hit.object_id != drone.id:
		_fail("the hit must carry the drone's id, got %d" % hit.object_id)
	field.free()


func _destroy_removes_it_from_the_index() -> void:
	var field := _build()
	field.populate(1, 5000.0, Vector3.ZERO)
	field.update(STEP, Vector3(0.0, 800.0, 20000.0), Vector3(0.0, 0.0, -1.0))
	var drone = field.drones()[0]
	var where: Variant = field.destroy_drone(drone.id)
	if not (where is Vector3):
		_fail("destroying a live drone returns where it was")
	if field.destroy_drone(drone.id) != null:
		_fail("destroying it twice returns null")
	var after: RefCounted = field.query_segment(drone.position + Vector3(-40.0, 0.0, 0.0), drone.position + Vector3(40.0, 0.0, 0.0))
	if after != null and after.hit:
		_fail("a destroyed drone must leave the hit index")
	if drone.state != DRONE.State.DESTROYED:
		_fail("the drone must know it is destroyed")
	field.free()


func _picks_a_target_and_bombs_it() -> void:
	var field := _build()
	var flat := func(_x: float, _z: float) -> float: return 0.0
	field.building_index.add_chunk(0, [{
		"osm_id": 1, "x": 0.0, "z": 0.0, "height": 120.0,
		"footprint": [[-15.0, -15.0], [15.0, -15.0], [15.0, 15.0], [-15.0, 15.0]],
	}], flat)
	field.populate(1, 5000.0, Vector3.ZERO)
	var drone = field.drones()[0]
	# Put it just inside entry range so it picks a target immediately.
	drone.position = Vector3(DRONE.ATTACK_ENTRY_RANGE - 100.0, DRONE.INBOUND_ALTITUDE, 0.0)
	drone.heading = atan2(-1.0, 0.0)
	var bombs := [0]
	field.bomb_released.connect(func(_r) -> void: bombs[0] += 1)
	var elapsed := 0.0
	while elapsed < 60.0 and bombs[0] == 0:
		field.update(STEP, Vector3(0.0, 800.0, 20000.0), Vector3(0.0, 0.0, -1.0))
		elapsed += STEP
	if bombs[0] == 0:
		_fail("an unthreatened drone inside entry range must pick the tower and bomb it")
	var bomb: RefCounted = field.projectile_manager.active_rounds[0]
	if bomb.weapon_source != "bomb":
		_fail("the released projectile must be a bomb, got '%s'" % bomb.weapon_source)
	if bomb.flight == null:
		_fail("a bomb must carry its own flight model")
	if bomb.damage_profile == null or float(bomb.damage_profile.structural_damage) < 300.0:
		_fail("a bomb must carry a heavy damage profile")
	field.free()


func _the_hit_query_sees_both_fields() -> void:
	var field := _build()
	field.populate(1, 5000.0, Vector3.ZERO)
	field.update(STEP, Vector3(0.0, 800.0, 20000.0), Vector3(0.0, 0.0, -1.0))
	var drone = field.drones()[0]
	var query = HIT_QUERY.new()
	query.configure(func(_x: float, _z: float) -> float: return -1000.0, null, null, -2000.0)
	query.secondary_entity_index = field
	var hit: RefCounted = query.query_segment(drone.position + Vector3(-40.0, 0.0, 0.0), drone.position + Vector3(40.0, 0.0, 0.0))
	if hit == null or not hit.hit or hit.object_id != drone.id:
		_fail("the world hit query must find drones through its second entity source")
	field.free()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /root/OpenStrike && timeout 90 /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/drone_field_test.gd 2>&1 | grep -oE "DRONE_FIELD_TEST_PASS|Failed to load script" | head -1
```

Expected: `Failed to load script`.

- [ ] **Step 3: Give the hit query a second entity source**

In `scripts/world/world_hit_query.gd`, change lines 11-12 to:

```gdscript
var building_index: RefCounted = null
var entity_index: Object = null
## Drones. A second source rather than a list, because there are exactly two
## and a list would need every caller to know the order.
var secondary_entity_index: Object = null
```

And replace the entity block inside `query_segment` (lines 28-31) with:

```gdscript
	for index in [entity_index, secondary_entity_index]:
		if index == null:
			continue
		var entity: RefCounted = index.query_segment(from, to)
		if entity != null and (nearest == null or entity.t < nearest.t):
			nearest = entity
```

- [ ] **Step 4: Implement the field**

Create `scripts/entities/drone_field.gd`:

```gdscript
class_name DroneField
extends Node3D

## The raid, as the rest of the game sees it. Owns ten drones, gives each a
## mini-Raptor and an AABB that follows it every frame, picks their targets off
## the building index, and fires their bombs through the projectile manager --
## so a bomb hits a building through the same swept query and the same damage
## path as a shell.
##
## Mirrors launcher_field.gd. The AABB refresh is the one difference: launchers
## sit still and are indexed once; drones re-register every frame. Ten entities
## re-registering per frame is nothing, and it keeps one collision path where a
## second sphere index would drift.

const DRONE := preload("res://scripts/entities/drone.gd")
const ENTITY_HIT_INDEX := preload("res://scripts/entities/entity_hit_index.gd")
const BOMB_FLIGHT := preload("res://scripts/weapons/bomb_flight.gd")
const BOMB_PROFILE := preload("res://scripts/weapons/bomb_damage_profile.gd")
const JET_SCENE := preload("res://assets/models/f-22_raptor_-_fighter_jet_-_free.glb")

signal bomb_released(round_data: RefCounted)

## Launchers number from 1. Starting here keeps the two id spaces apart, so
## the impact handler can route by id without asking both fields.
const FIRST_ID := 100000
## About 40% of the Raptor's 13.56 -- clearly smaller, still an aircraft.
const DRONE_WINGSPAN_M := 5.5
## Spawn on the +X side, spread across this arc. Seaward for Surfers, where the
## launchers sit along a beach at x near zero.
const SPAWN_ARC_DEGREES := 120.0
const SPAWN_RADIUS_FRACTION := 0.85
## Half-extents of the collision box round each drone, in metres. Generous
## against a 5.5 m span: a drone that is hard to hit because its box is exact
## is not fun, and the rocket trail will hide the difference.
const HIT_HALF_EXTENTS := Vector3(4.0, 2.0, 4.0)

var projectile_manager: Node3D
var building_index: RefCounted
var hit_index := ENTITY_HIT_INDEX.new()

var _drones: Array = []
var _visuals: Dictionary = {}
var _city_centre := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _bomb_sequence := 0
var _bomb_profile: Resource


func _ready() -> void:
	_rng.randomize()
	_bomb_profile = BOMB_PROFILE.new()


func populate(count: int, half_extent: float, city_centre: Vector3) -> void:
	clear()
	_city_centre = city_centre
	var radius := half_extent * SPAWN_RADIUS_FRACTION
	var arc := deg_to_rad(SPAWN_ARC_DEGREES)
	for index in range(count):
		var fraction := (float(index) + 0.5) / float(maxi(count, 1))
		var angle := (fraction - 0.5) * arc
		var drone = DRONE.new()
		drone.id = FIRST_ID + index
		drone.position = city_centre + Vector3(cos(angle) * radius, DRONE.INBOUND_ALTITUDE, sin(angle) * radius)
		drone.heading = atan2(city_centre.x - drone.position.x, -(city_centre.z - drone.position.z))
		drone.speed = DRONE.DRONE_CRUISE_MPS
		drone.velocity = drone.nose() * drone.speed
		_drones.append(drone)
		_visuals[drone.id] = _spawn_visual(drone)
		_register(drone)


func clear() -> void:
	hit_index.clear()
	for visual in _visuals.values():
		if is_instance_valid(visual):
			visual.queue_free()
	_visuals.clear()
	_drones.clear()


func drone_count() -> int:
	var alive := 0
	for drone in _drones:
		if drone.state != DRONE.State.DESTROYED:
			alive += 1
	return alive


func drones() -> Array:
	return _drones


func query_segment(from: Vector3, to: Vector3) -> RefCounted:
	return hit_index.query_segment(from, to)


func destroy_drone(entity_id: int) -> Variant:
	for drone in _drones:
		if drone.id != entity_id or drone.state == DRONE.State.DESTROYED:
			continue
		var where: Vector3 = drone.position
		drone.destroy()
		hit_index.remove_entity(entity_id)
		return where
	return null


## Driven by main, so the raid pauses with the game and the player's position
## is the one the camera is already using this frame.
func update(delta: float, player_position: Vector3, player_nose: Vector3) -> void:
	for drone in _drones:
		if drone.state == DRONE.State.DESTROYED:
			# Falling wreckage: keep moving it, keep the visual on it, and
			# drop it once it is below the ground the visuals can see.
			drone.update(delta, player_position, player_nose, _city_centre, _rng)
			_place_visual(drone)
			continue
		if drone.wants_target() and building_index != null:
			_assign_target(drone)
		if drone.update(delta, player_position, player_nose, _city_centre, _rng):
			_release_bomb(drone)
		_register(drone)
		_place_visual(drone)


## The tallest building within the drone's forward cone, so raids go for the
## skyline rather than a car park. Falls back to the tallest anywhere in range
## if nothing is ahead.
func _assign_target(drone) -> void:
	var here := Vector2(drone.position.x, drone.position.z)
	var candidates: Array = building_index.buildings_near(here, DRONE.ATTACK_ENTRY_RANGE)
	if candidates.is_empty():
		return
	var nose := drone.nose()
	var best: Dictionary = {}
	var best_height := -1.0
	var ahead_only := true
	for pass_index in range(2):
		for entry in candidates:
			var to_target: Vector3 = entry["position"] - drone.position
			to_target.y = 0.0
			if ahead_only and to_target.normalized().dot(nose) < 0.5:
				continue
			if float(entry["height"]) > best_height:
				best_height = float(entry["height"])
				best = entry
		if not best.is_empty():
			break
		ahead_only = false
	if best.is_empty():
		return
	drone.assign_target(int(best["handle"]), best["position"])


func _release_bomb(drone) -> void:
	if projectile_manager == null:
		return
	var flight = BOMB_FLIGHT.new()
	_bomb_sequence += 1
	var round_data: RefCounted = projectile_manager.acquire_round()
	round_data.initialise(
		_bomb_sequence,
		drone.position,
		drone.velocity.normalized() if not drone.velocity.is_zero_approx() else Vector3.DOWN,
		flight.release_velocity(drone.velocity),
		false,
		_bomb_profile,
		"bomb"
	)
	round_data.flight = flight
	projectile_manager.spawn(round_data)
	bomb_released.emit(round_data)


func _register(drone) -> void:
	hit_index.add_entity(drone.id, AABB(drone.position - HIT_HALF_EXTENTS, HIT_HALF_EXTENTS * 2.0))


func _spawn_visual(drone) -> Node3D:
	var anchor := Node3D.new()
	anchor.name = "Drone_%d" % drone.id
	add_child(anchor)
	var model: Node3D = JET_SCENE.instantiate()
	anchor.add_child(model)
	# Same measure-and-scale the hero jet uses, so the GLB's native scale is
	# never a magic number here either.
	var bounds := _bounds_relative_to(anchor)
	if bounds.size.z > 0.001:
		model.scale = Vector3.ONE * (DRONE_WINGSPAN_M / bounds.size.z)
	for child in model.find_children("*", "Node3D", true, false):
		if String(child.name).to_lower().contains("landingon"):
			(child as Node3D).visible = false
	return anchor


func _place_visual(drone) -> void:
	var anchor: Node3D = _visuals.get(drone.id)
	if anchor == null or not is_instance_valid(anchor):
		return
	anchor.global_position = drone.position
	var nose: Vector3 = drone.velocity.normalized() if not drone.velocity.is_zero_approx() else drone.nose()
	var right := nose.cross(Vector3.UP)
	if right.is_zero_approx():
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(nose).normalized()
	var attitude := Basis(nose, up, right).orthonormalized()
	anchor.global_basis = attitude.rotated(nose, drone.bank())


func _bounds_relative_to(root: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		var relative := root.global_transform.affine_inverse() * instance.global_transform
		var transformed: AABB = relative * instance.get_aabb()
		bounds = transformed if not found else bounds.merge(transformed)
		found = true
	return bounds
```

- [ ] **Step 5: Run to verify it passes**

Expected: `DRONE_FIELD_TEST_PASS`. Also run `tests/world_hit_query_test.gd` to confirm the query change broke nothing:

```bash
cd /root/OpenStrike && timeout 60 /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/world_hit_query_test.gd 2>&1 | grep -oE "_TEST_PASS" | head -1
```

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/drone_field.gd scripts/world/world_hit_query.gd tests/drone_field_test.gd
git commit -m "Field the drones, and let every projectile hit them

Ten mini-Raptors, each with an AABB that follows it every frame in the same
entity index the launchers use, so shells and rockets hit drones with no new
collision code. Targets come off the building index -- the tallest thing
ahead -- and bombs go out through the projectile manager, so they strike
buildings the way a shell does."
```

---

### Task 6: Radar scope

**Files:**
- Create: `scripts/ui/radar_scope.gd`
- Test: `tests/radar_scope_test.gd`

**Interfaces:**
- Consumes: `Drone.State` (Task 3).
- Produces: `RadarScope` (`Control`) with static `blip_offset(world_offset: Vector3, heading: float, range_m: float, radius_px: float) -> Vector2` (screen offset from scope centre, +y down, clamped to the rim), static `is_on_rim(world_offset: Vector3, range_m: float) -> bool`, static `colour_for_state(state: int) -> Color`; instance `set_contacts(player_position: Vector3, heading: float, drones: Array) -> void`; constants `RADAR_RANGE_M` 4000, `SCOPE_RADIUS_PX` 90.

- [ ] **Step 1: Write the failing test**

Create `tests/radar_scope_test.gd`:

```gdscript
extends SceneTree

## Nose-up: a contact dead ahead is at the top whatever the heading, and a
## contact on the right is on the right. Beyond range it pins to the rim so a
## drone is never simply absent -- it is always at least a direction.

const SCOPE := preload("res://scripts/ui/radar_scope.gd")
const DRONE := preload("res://scripts/entities/drone.gd")


func _init() -> void:
	var range_m: float = SCOPE.RADAR_RANGE_M
	var radius: float = SCOPE.SCOPE_RADIUS_PX

	# Heading 0 is nose along -Z. A contact 2000 m ahead sits at the top.
	var ahead: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -2000.0), 0.0, range_m, radius)
	if ahead.y >= 0.0 or absf(ahead.x) > 0.5:
		_fail("a contact dead ahead must be straight up, got %v" % ahead)
	if not is_equal_approx(ahead.length(), radius * 0.5):
		_fail("half range must sit at half radius, got %f" % ahead.length())

	# Same contact, but the aircraft has turned to face +X (heading pi/2).
	# It is now on the aircraft's LEFT, so it appears on the left.
	var turned: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -2000.0), PI * 0.5, range_m, radius)
	if turned.x >= 0.0 or absf(turned.y) > 0.5:
		_fail("after a right turn a contact that was ahead is on the left, got %v" % turned)

	# Beyond range pins to the rim, direction preserved.
	var far: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -9000.0), 0.0, range_m, radius)
	if not is_equal_approx(far.length(), radius):
		_fail("out of range must pin to the rim, got %f" % far.length())
	if far.y >= 0.0:
		_fail("a pinned contact keeps its direction")
	if not SCOPE.is_on_rim(Vector3(0.0, 0.0, -9000.0), range_m):
		_fail("out of range must report as on the rim")
	if SCOPE.is_on_rim(Vector3(0.0, 0.0, -2000.0), range_m):
		_fail("in range must not report as on the rim")

	# Altitude does not move a blip: this is a top-down scope.
	var high: Vector2 = SCOPE.blip_offset(Vector3(0.0, 3000.0, -2000.0), 0.0, range_m, radius)
	if not high.is_equal_approx(ahead):
		_fail("altitude must not displace a blip")

	# State drives colour, and every state has one.
	var seen := {}
	for state in DRONE.State.values():
		var colour: Color = SCOPE.colour_for_state(state)
		seen[colour.to_html()] = true
	if seen.size() < 4:
		_fail("inbound, attacking, evading and destroyed must be told apart by colour")

	print("RADAR_SCOPE_TEST_PASS")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /root/OpenStrike && timeout 60 /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/radar_scope_test.gd 2>&1 | grep -oE "RADAR_SCOPE_TEST_PASS|Failed to load script" | head -1
```

Expected: `Failed to load script`.

- [ ] **Step 3: Implement**

Create `scripts/ui/radar_scope.gd`:

```gdscript
extends Control

## A round air scope, aircraft at centre, nose up. Targets are blips whose
## screen position is their world offset rotated by minus the heading, so a
## contact ahead is at the top whatever way the aircraft points. Beyond range a
## blip pins to the rim as a chevron: a drone is never simply absent from the
## scope, it is always at least a direction.
##
## Drawn, not themed, like attack_reticle: no textures, scales with the
## viewport, and every element is a line or an arc.

const DRONE := preload("res://scripts/entities/drone.gd")

const RADAR_RANGE_M := 4000.0
const SCOPE_RADIUS_PX := 90.0
const MARGIN_PX := 24.0
const RING_COLOUR := Color(0.35, 0.9, 0.5, 0.55)
const BLIP_RADIUS_PX := 3.5

var _contacts: Array = []
var _player_position := Vector3.ZERO
var _heading := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Rotating the world offset by minus the heading puts the nose on -Z; screen
## y is down, and -Z is "up the screen", so the offset maps straight across.
static func blip_offset(world_offset: Vector3, heading: float, range_m: float, radius_px: float) -> Vector2:
	var flat := Vector2(world_offset.x, world_offset.z).rotated(-heading)
	var scaled := flat * (radius_px / maxf(range_m, 1.0))
	if scaled.length() > radius_px:
		scaled = scaled.normalized() * radius_px
	return scaled


static func is_on_rim(world_offset: Vector3, range_m: float) -> bool:
	return Vector2(world_offset.x, world_offset.z).length() > range_m


static func colour_for_state(state: int) -> Color:
	match state:
		DRONE.State.ATTACK_RUN:
			return Color(1.0, 0.72, 0.2)
		DRONE.State.EVADING:
			return Color(1.0, 0.3, 0.25)
		DRONE.State.DESTROYED:
			return Color(0.5, 0.5, 0.5, 0.6)
	return Color(0.92, 0.96, 1.0)


func set_contacts(player_position: Vector3, heading: float, drones: Array) -> void:
	_player_position = player_position
	_heading = heading
	_contacts = drones
	queue_redraw()


func _draw() -> void:
	var centre := Vector2(size.x - MARGIN_PX - SCOPE_RADIUS_PX, size.y - MARGIN_PX - SCOPE_RADIUS_PX)
	draw_circle(centre, SCOPE_RADIUS_PX, Color(0.02, 0.06, 0.04, 0.55))
	draw_arc(centre, SCOPE_RADIUS_PX, 0.0, TAU, 64, RING_COLOUR, 1.5)
	draw_arc(centre, SCOPE_RADIUS_PX * 0.5, 0.0, TAU, 48, RING_COLOUR * Color(1.0, 1.0, 1.0, 0.6), 1.0)
	# Own heading tick at the top, and the range label beside the outer ring.
	draw_line(centre + Vector2(0.0, -SCOPE_RADIUS_PX), centre + Vector2(0.0, -SCOPE_RADIUS_PX + 8.0), RING_COLOUR, 2.0)
	draw_string(
		get_theme_default_font(), centre + Vector2(SCOPE_RADIUS_PX - 34.0, -SCOPE_RADIUS_PX + 14.0),
		"%dKM" % int(RADAR_RANGE_M / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, RING_COLOUR
	)
	for drone in _contacts:
		var offset: Vector3 = drone.position - _player_position
		var at := centre + blip_offset(offset, _heading, RADAR_RANGE_M, SCOPE_RADIUS_PX)
		var colour := colour_for_state(drone.state)
		if is_on_rim(offset, RADAR_RANGE_M):
			# A chevron pointing outward: direction without a false range.
			var outward := (at - centre).normalized()
			var side := Vector2(-outward.y, outward.x)
			draw_polyline(PackedVector2Array([
				at - outward * 6.0 + side * 4.0, at, at - outward * 6.0 - side * 4.0
			]), colour, 1.5)
		else:
			draw_circle(at, BLIP_RADIUS_PX, colour)
```

- [ ] **Step 4: Run to verify it passes**

Expected: `RADAR_SCOPE_TEST_PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/radar_scope.gd tests/radar_scope_test.gd
git commit -m "Add the radar scope, nose up

A contact ahead is at the top whatever way the aircraft points. Beyond range
it pins to the rim as a chevron, so a drone is never simply absent -- it is
always at least a direction."
```

---

### Task 7: Bearing tape

**Files:**
- Create: `scripts/ui/bearing_tape.gd`
- Test: `tests/bearing_tape_test.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `BearingTape` (`Control`) with static `relative_bearing(world_offset: Vector3, heading: float) -> float` (radians, wrapped to ±π), static `tick_x(relative_bearing: float, half_width_degrees: float, half_width_px: float) -> float` (offset from tape centre, clamped), static `is_clamped(relative_bearing: float, half_width_degrees: float) -> bool`; instance `set_contacts(player_position, heading, drones) -> void`; constant `TAPE_HALF_WIDTH_DEGREES` 60.

- [ ] **Step 1: Write the failing test**

Create `tests/bearing_tape_test.gd`:

```gdscript
extends SceneTree

## The tape answers "which way do I turn" without looking down. A contact to
## the right is a tick to the right, proportionally, and one outside the tape
## clamps at the end with its side preserved.

const TAPE := preload("res://scripts/ui/bearing_tape.gd")


func _init() -> void:
	var half_deg: float = TAPE.TAPE_HALF_WIDTH_DEGREES
	var half_px := 300.0

	# Heading 0, nose along -Z. A contact at +X is 90 degrees right.
	var right := TAPE.relative_bearing(Vector3(1000.0, 0.0, 0.0), 0.0)
	if not is_equal_approx(right, PI * 0.5):
		_fail("a contact at +X from heading 0 is 90 right, got %f" % rad_to_deg(right))
	# Turn to face +X: it is now dead ahead.
	if absf(TAPE.relative_bearing(Vector3(1000.0, 0.0, 0.0), PI * 0.5)) > 0.001:
		_fail("facing the contact puts it at zero relative bearing")
	# Directly behind wraps to +/-180, not 540.
	var behind := TAPE.relative_bearing(Vector3(0.0, 0.0, 1000.0), 0.0)
	if absf(absf(behind) - PI) > 0.001:
		_fail("a contact behind is 180, got %f" % rad_to_deg(behind))

	# Thirty degrees right on a sixty-degree half tape is halfway to the end.
	var half := TAPE.tick_x(deg_to_rad(30.0), half_deg, half_px)
	if not is_equal_approx(half, half_px * 0.5):
		_fail("30 degrees must be half way along a 60 degree half tape, got %f" % half)
	if TAPE.tick_x(deg_to_rad(-30.0), half_deg, half_px) >= 0.0:
		_fail("left is negative")
	# Beyond the tape clamps, side preserved.
	if not is_equal_approx(TAPE.tick_x(deg_to_rad(150.0), half_deg, half_px), half_px):
		_fail("150 right clamps to the right end")
	if not is_equal_approx(TAPE.tick_x(deg_to_rad(-150.0), half_deg, half_px), -half_px):
		_fail("150 left clamps to the left end")
	if not TAPE.is_clamped(deg_to_rad(150.0), half_deg):
		_fail("150 must report as clamped")
	if TAPE.is_clamped(deg_to_rad(30.0), half_deg):
		_fail("30 must not report as clamped")

	print("BEARING_TAPE_TEST_PASS")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /root/OpenStrike && timeout 60 /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/bearing_tape_test.gd 2>&1 | grep -oE "BEARING_TAPE_TEST_PASS|Failed to load script" | head -1
```

Expected: `Failed to load script`.

- [ ] **Step 3: Implement**

Create `scripts/ui/bearing_tape.gd`:

```gdscript
extends Control

## A strip along the bottom of the cockpit view marked in degrees of relative
## bearing, centred on the nose. Each drone is a tick at its bearing; the
## closest carries its range. Outside the tape a contact clamps to the end with
## an arrow, so "turn hard left" is still readable.
##
## Cockpit only. The external views have the scope alone; a chase camera does
## not earn a HUD tape.

const TAPE_HALF_WIDTH_DEGREES := 60.0
const TAPE_HEIGHT_PX := 26.0
const BOTTOM_MARGIN_PX := 18.0
## Stops short of the scope in the bottom-right corner so the two never overlap.
const RIGHT_RESERVE_PX := 260.0
const LEFT_MARGIN_PX := 24.0
const COLOUR := Color(0.45, 1.0, 0.6, 0.85)

var _contacts: Array = []
var _player_position := Vector3.ZERO
var _heading := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


static func relative_bearing(world_offset: Vector3, heading: float) -> float:
	var absolute := atan2(world_offset.x, -world_offset.z)
	return wrapf(absolute - heading, -PI, PI)


static func tick_x(relative_bearing_radians: float, half_width_degrees: float, half_width_px: float) -> float:
	var fraction := rad_to_deg(relative_bearing_radians) / maxf(half_width_degrees, 0.001)
	return clampf(fraction, -1.0, 1.0) * half_width_px


static func is_clamped(relative_bearing_radians: float, half_width_degrees: float) -> bool:
	return absf(rad_to_deg(relative_bearing_radians)) > half_width_degrees


func set_contacts(player_position: Vector3, heading: float, drones: Array) -> void:
	_player_position = player_position
	_heading = heading
	_contacts = drones
	queue_redraw()


func _draw() -> void:
	var left := LEFT_MARGIN_PX
	var right := size.x - RIGHT_RESERVE_PX
	if right <= left + 40.0:
		return
	var centre_x := (left + right) * 0.5
	var half_px := (right - left) * 0.5
	var y := size.y - BOTTOM_MARGIN_PX - TAPE_HEIGHT_PX * 0.5
	draw_line(Vector2(left, y), Vector2(right, y), COLOUR * Color(1.0, 1.0, 1.0, 0.5), 1.0)
	# Graduations every 15 degrees, the nose marked.
	var step := 15.0
	var mark := -TAPE_HALF_WIDTH_DEGREES
	while mark <= TAPE_HALF_WIDTH_DEGREES + 0.001:
		var x := centre_x + tick_x(deg_to_rad(mark), TAPE_HALF_WIDTH_DEGREES, half_px)
		var tall := is_zero_approx(mark)
		draw_line(Vector2(x, y - (8.0 if tall else 4.0)), Vector2(x, y + (8.0 if tall else 4.0)), COLOUR, 1.5 if tall else 1.0)
		mark += step
	var closest = null
	var closest_range := INF
	for drone in _contacts:
		var offset: Vector3 = drone.position - _player_position
		var bearing := relative_bearing(offset, _heading)
		var x := centre_x + tick_x(bearing, TAPE_HALF_WIDTH_DEGREES, half_px)
		if is_clamped(bearing, TAPE_HALF_WIDTH_DEGREES):
			var direction := signf(bearing)
			draw_polyline(PackedVector2Array([
				Vector2(x - direction * 8.0, y - 6.0), Vector2(x, y), Vector2(x - direction * 8.0, y + 6.0)
			]), COLOUR, 1.5)
		else:
			draw_polyline(PackedVector2Array([
				Vector2(x - 5.0, y - 9.0), Vector2(x, y - 2.0), Vector2(x + 5.0, y - 9.0)
			]), COLOUR, 1.5)
		var range_m := offset.length()
		if range_m < closest_range:
			closest_range = range_m
			closest = Vector2(x, y)
	if closest != null:
		draw_string(
			get_theme_default_font(), (closest as Vector2) + Vector2(-16.0, -14.0),
			"%dM" % int(closest_range), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOUR
		)
```

- [ ] **Step 4: Run to verify it passes**

Expected: `BEARING_TAPE_TEST_PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/bearing_tape.gd tests/bearing_tape_test.gd
git commit -m "Add the cockpit bearing tape

Which way to turn, without looking down. A tick per drone at its relative
bearing, the closest labelled with range, and anything outside the tape
clamped to the end with its side preserved."
```

---

### Task 8: Clear the screen and wire the raid

Everything above is inert until the scene owns it. The mission panel is deleted, its one live line moves to a code-built HUD, the settings panel absorbs the rest, Y and B are unbound, and the raid starts when flight does.

**Files:**
- Modify: `scenes/main.tscn` — delete the `UI/Margin` subtree (lines 74-124)
- Modify: `scripts/ui/settings_panel.gd` — add input monitor toggle, restart raid, region/privacy text
- Modify: `scripts/input/gamepad_input.gd` — unbind Y and B
- Modify: `scripts/main.gd` — remove panel references, build the HUD, wire the raid
- Test: `tests/gamepad_input_test.gd` (update the Y/B assertions); full suite; scene smoke test

**Interfaces:**
- Consumes: everything from Tasks 1-7.
- Produces: a playable build.

- [ ] **Step 1: Unbind Y and B, and update the input test**

In `scripts/input/gamepad_input.gd` `_register_input_actions`, delete these two lines:

```gdscript
	_add_button_action(ACTION_FLIGHT_MODE, JoyButton.JOY_BUTTON_Y)
	_add_button_action(ACTION_SWITCH_AIRCRAFT, JoyButton.JOY_BUTTON_B)
```

and replace them with:

```gdscript
	# Y and B are deliberately unbound. Flight mode and switch-aircraft live in
	# the settings panel now, and both buttons are reserved for the lock-on
	# controls in the next phase.
```

Remove `ACTION_FLIGHT_MODE` and `ACTION_SWITCH_AIRCRAFT` from `BUTTON_ACTIONS` (an unregistered action polled every frame errors). Keep both constants; `main.gd` still names them in a dead branch this task deletes.

In `tests/gamepad_input_test.gd`, delete the two assertions:

```gdscript
	_assert_button(&"flight_mode_toggle", JoyButton.JOY_BUTTON_Y)
```
and the `switch_aircraft` one if present, and add in their place:

```gdscript
	# Y and B are reserved for lock-on. Nothing may claim them.
	for button in [JoyButton.JOY_BUTTON_Y, JoyButton.JOY_BUTTON_B]:
		for action in InputMap.get_actions():
			for event in InputMap.action_get_events(action):
				if event is InputEventJoypadButton and event.button_index == button:
					assert(false, "%s must stay unbound, %s claims it" % [button, action])
```

Run:
```bash
cd /root/OpenStrike && timeout 90 /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/gamepad_input_test.gd 2>&1 | grep -oE "GAMEPAD_INPUT_TEST_PASS" | head -1
```
Expected: `GAMEPAD_INPUT_TEST_PASS`.

- [ ] **Step 2: Extend the settings panel**

In `scripts/ui/settings_panel.gd`:

Add signals beside the existing ones:

```gdscript
signal input_monitor_toggled(enabled: bool)
signal raid_restarted
```

Add fields beside the existing `_stats_label`:

```gdscript
var _monitor_button: CheckButton
var _region_label: Label
```

In `_ready()`, after the `column.add_child(_heading("CONTROLS"))` block and before `GRAPHICS`, insert:

```gdscript
	column.add_child(_heading("RAID"))
	var restart := Button.new()
	restart.text = "RESTART RAID"
	restart.pressed.connect(func(): raid_restarted.emit())
	column.add_child(restart)

	column.add_child(_heading("HUD"))
	_monitor_button = CheckButton.new()
	_monitor_button.text = "INPUT MONITOR OVERLAY"
	_monitor_button.toggled.connect(func(on: bool): input_monitor_toggled.emit(on))
	column.add_child(_monitor_button)
```

And after the `STATUS` heading's `_stats_label`, insert:

```gdscript
	column.add_child(_heading("THEATRE INFO"))
	_region_label = Label.new()
	_region_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_region_label)
	var privacy := Label.new()
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.text = "Foreground location only. Coordinates are not saved.\nMap © OpenStreetMap contributors. Aerial © State of Queensland."
	column.add_child(privacy)
```

Add the accessor:

```gdscript
func set_region_text(text: String) -> void:
	_region_label.text = text
```

- [ ] **Step 3: Delete the mission panel from the scene**

In `scenes/main.tscn`, delete every node from `[node name="Margin" type="MarginContainer" parent="UI"]` through the end of `[node name="FlightModeButton" ...]` (lines 74-124 inclusive — the whole `UI/Margin` subtree). `AttackReticle`, `SettingsPanel`, `GamepadDiagnostic` and `ControllerOverlay` stay.

- [ ] **Step 4: Rebuild the HUD and wire the raid in main.gd**

Add preloads beside the others:

```gdscript
const DRONE_FIELD := preload("res://scripts/entities/drone_field.gd")
const RAID_MISSION := preload("res://scripts/entities/raid_mission.gd")
const RADAR_SCOPE := preload("res://scripts/ui/radar_scope.gd")
const BEARING_TAPE := preload("res://scripts/ui/bearing_tape.gd")
```

Replace these five `@onready` lines:

```gdscript
@onready var mission_panel: Control = $UI/Margin
@onready var status_label: Label = $UI/Margin/Panel/Content/Status
@onready var region_label: Label = $UI/Margin/Panel/Content/Region
@onready var demo_button: Button = $UI/Margin/Panel/Content/DemoButton
@onready var flight_mode_button: Button = $UI/Margin/Panel/Content/FlightModeButton
```

with:

```gdscript
@onready var ui_layer: CanvasLayer = $UI
## The one line of the old mission panel that was actually live. Built in code
## so the panel and its five dead labels could go.
var status_label: Label
var _mission_label: Label
var _settings_button: Button
var _radar: Control
var _tape: Control
var _drone_field: Node3D
var _mission := RAID_MISSION.new()
```

At the top of `_ready()`, **before** anything touches `status_label`, add:

```gdscript
	_build_hud()
```

Add the builder:

```gdscript
## What is left on screen while flying: a status line, the raid line, the
## radar, the tape in cockpit, and the way into settings. Everything the old
## panel showed is in settings now.
func _build_hud() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
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
	_settings_button.pressed.connect(_toggle_settings)
	row.add_child(_settings_button)

	_radar = RADAR_SCOPE.new()
	ui_layer.add_child(_radar)
	_tape = BEARING_TAPE.new()
	ui_layer.add_child(_tape)
	# The input monitor is opt-in from settings now, not a fixture.
	gamepad_diagnostic.get_parent().visible = false
```

Then, in `_ready()`, **delete** these lines:

```gdscript
	flight_mode_button.pressed.connect(_toggle_flight_mode)
	_refresh_flight_mode_button()
	demo_button.pressed.connect(_toggle_settings)
	demo_button.text = "SETTINGS"
	demo_button.visible = true
```

and add, after the existing `settings_panel.quality_cycled.connect(...)` line:

```gdscript
	settings_panel.input_monitor_toggled.connect(func(on: bool): gamepad_diagnostic.get_parent().visible = on)
	settings_panel.raid_restarted.connect(_start_raid)
	_mission.raid_ended.connect(_on_raid_ended)
```

Fix every remaining reference to the deleted nodes:

- `_apply_view_chrome()` becomes:
```gdscript
func _apply_view_chrome() -> void:
	# The tape is a cockpit instrument; the scope is always up.
	if _tape != null:
		_tape.visible = _is_cockpit_view()
```

- `_refresh_flight_mode_button()` becomes a text function and its two callers use it:
```gdscript
func _flight_mode_text() -> String:
	if _flying_jet:
		return "CONTROLS: FLY-BY-WIRE"
	if not ("flight_mode" in helicopter_anchor):
		return "CONTROLS: --"
	var arcade: int = helicopter_anchor.FlightMode.ARCADE
	return "CONTROLS: %s" % ("ARCADE" if int(helicopter_anchor.flight_mode) == arcade else "REALISTIC")
```
In `_toggle_flight_mode`, replace `_refresh_flight_mode_button()` + `settings_panel.set_flight_mode_text(flight_mode_button.text)` with `settings_panel.set_flight_mode_text(_flight_mode_text())`. In `_refresh_settings`, replace `settings_panel.set_flight_mode_text(flight_mode_button.text)` with `settings_panel.set_flight_mode_text(_flight_mode_text())`. Search for any other `_refresh_flight_mode_button()` call (there is one in `_switch_aircraft`) and replace it the same way.

- `region_label.text = ...` (three sites in `_on_region_selected` and `_load_streamed_region`) become `settings_panel.set_region_text(...)` with the same strings.

- In `_on_gamepad_action_pressed`, delete the `ACTION_SWITCH_AIRCRAFT` and `ACTION_FLIGHT_MODE` branches; the settings panel's signals already reach `_switch_aircraft` and `_toggle_flight_mode`.

- `_refresh_aircraft_button()` — read it; if it only sets `settings_panel.set_aircraft_text`, leave it; if it touches a deleted node, remove that line.

Wire the raid. In `_wire_cannon_systems`, after the existing `_hit_query.entity_index = launcher_field` line, add:

```gdscript
	_drone_field = DRONE_FIELD.new()
	_drone_field.name = "DroneField"
	add_child(_drone_field)
	_drone_field.projectile_manager = projectile_manager
	_drone_field.building_index = _building_hit_index
	_hit_query.secondary_entity_index = _drone_field
	_building_damage.building_damaged.connect(_on_building_damaged_for_raid)
```

Start the raid when flight starts. At the line `_camera_follow_enabled = true` (around 404), add immediately after:

```gdscript
	_start_raid()
```

Add the raid handlers:

```gdscript
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
```

Drive the field and the instruments each frame. In `_process`, after `_update_rockets(delta)`, add:

```gdscript
	_update_raid(delta)
```

```gdscript
func _update_raid(delta: float) -> void:
	if _drone_field == null or not _camera_follow_enabled:
		return
	var vehicle := _vehicle()
	var nose: Vector3 = vehicle.global_basis.x if _flying_jet else -vehicle.global_basis.z
	_drone_field.update(delta, vehicle.global_position, nose)
	var heading := atan2(nose.x, -nose.z)
	_radar.set_contacts(vehicle.global_position, heading, _drone_field.drones())
	if _tape.visible:
		_tape.set_contacts(vehicle.global_position, heading, _drone_field.drones())
```

Route drone hits. In `_on_projectile_impacted`, the existing ENTITY branch reads:

```gdscript
	elif hit_result.object_type == WORLD_HIT.ObjectKind.ENTITY:
		var explosion_position: Variant = launcher_field.destroy_launcher(hit_result.object_id)
		if explosion_position is Vector3:
			impact_fx.spawn_explosion(explosion_position)
			_play_destructive_hit_stop()
```

Replace it with:

```gdscript
	elif hit_result.object_type == WORLD_HIT.ObjectKind.ENTITY:
		# The two fields have disjoint id spaces, so whichever claims the id
		# is the one that was hit. A bomb striking its own drone is refused
		# below by weapon_source, or drones would shoot themselves down.
		var explosion_position: Variant = null
		if hit_result.object_id >= DRONE_FIELD.FIRST_ID:
			if round_data.weapon_source != "bomb":
				explosion_position = _drone_field.destroy_drone(hit_result.object_id)
				if explosion_position is Vector3:
					_mission.drone_destroyed()
					_mission_label.text = _mission.hud_line()
					_trail_renderer.begin_trail(hit_result.object_id)
		else:
			explosion_position = launcher_field.destroy_launcher(hit_result.object_id)
		if explosion_position is Vector3:
			impact_fx.spawn_explosion(explosion_position)
			_play_destructive_hit_stop()
```

Falling wreckage lays smoke. In `_update_rockets`' trail loop, drones are not projectiles, so add to `_update_raid` after `_drone_field.update(...)`:

```gdscript
	for drone in _drone_field.drones():
		if drone.state == DRONE_FIELD.DRONE.State.DESTROYED:
			_trail_renderer.push_point(drone.id, drone.position)
			if drone.position.y < _ground_height_at(drone.position) - 20.0:
				_trail_renderer.end_trail(drone.id)
```

(`DRONE_FIELD.DRONE` resolves because `drone_field.gd` declares `const DRONE`.)

Finally, delete the now-dead settings branch comment if it still references `flight_mode_button`, and grep to confirm nothing names a deleted node:

```bash
cd /root/OpenStrike && grep -n "mission_panel\|region_label\|demo_button\|flight_mode_button\|_refresh_flight_mode_button" scripts/main.gd
```

Expected: no output.

- [ ] **Step 5: Run the whole suite**

```bash
cd /root/OpenStrike && G=/root/godot-dist/Godot_v4.7.2-stable_linux.arm64
pass=0; fail=0
for f in tests/*_test.gd; do
  if timeout 200 $G --headless --script "$f" 2>&1 | grep -q "_PASS"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAILED: $(basename $f)"; fi
done
echo "passed $pass, failed $fail"
```

Expected: `passed 48, failed 0`.

- [ ] **Step 6: Smoke-test the real scene**

```bash
cd /root/OpenStrike && timeout 90 /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --quit-after 240 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Invalid call|Nonexistent|Cannot call|Node not found" | head
```

Expected: no output. `Node not found` is the one to watch for — it means a `$UI/Margin/...` reference survived.

- [ ] **Step 7: Build, verify, stage**

```bash
cd /root/OpenStrike
/root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --export-debug "Android" build/OpenStrike-raid.apk 2>&1 | tail -3
python3 -c "
import zipfile
f='build/OpenStrike-raid.apk'
z=zipfile.ZipFile(f); print('entries:', len(z.namelist()), 'bad:', z.testzip() or 'none')
print('signed:', b'APK Sig Block 42' in open(f,'rb').read())
"
cp build/OpenStrike-raid.apk /sdcard/Download/ && md5sum build/OpenStrike-raid.apk /sdcard/Download/OpenStrike-raid.apk
```

Expected: ~133 MB, `bad: none`, `signed: True`, matching MD5s.

- [ ] **Step 8: Commit**

```bash
git add scenes/main.tscn scripts/main.gd scripts/ui/settings_panel.gd scripts/input/gamepad_input.gd tests/gamepad_input_test.gd
git commit -m "Clear the screen, and start the raid

The mission panel and its five dead labels go; its one live line moves to a
code-built HUD beside the raid counter, the radar and the settings button.
Flight mode, switch-aircraft, region and privacy live in settings now, with an
on/off for the input monitor. Y and B are unbound for the lock-on to come.

Ten drones spawn at the seaward edge when flight starts, the field is stepped
from the same frame the camera uses, and a drone that any projectile hits
falls smoking through the phase 1 trail renderer."
```

- [ ] **Step 9: Device verification**

Headless cannot judge any of this. On the phone:

1. **The screen.** Only the status line, raid counter, radar, settings button — and the tape in cockpit. If the old panel is still there, `Node not found` was missed.
2. **Radar sense.** Turn right; blips that were ahead must move left. If they move right, the sign in `blip_offset`'s rotation is wrong.
3. **Can you catch one?** Cruise is 95 m/s against your 134 corner. If you cannot, `DRONE_CRUISE_MPS` is too high.
4. **Can you hit one?** This is the "best in class" question and the one I most expect to need tuning. If they are impossible: raise `JINK_INTERVAL` (they jink less), lower `DRONE_DASH_MPS`, or widen `HIT_HALF_EXTENTS`. If they are trivial: the reverse.
5. **Do they bomb?** Fly away from them and watch a building start smoking. If no drone ever releases, check `wants_target()` — it needs `_near_city` true, which needs `city_centre` at the actual city.
6. **Framerate** with ten drones, their bombs and a full rocket salvo. Same knobs as phase 1 if it bites.

---

## Self-review

**Spec coverage.** Drones with state machine and kinematic flight → Task 3. Attack runs, target choice, bombs → Tasks 1, 2, 5. Evasion rules (break away, dash, jink, drop, abort) → Task 3, each asserted. Destruction, AABB removal, falling with a trail → Tasks 5 and 8. Mission with win/lose/restart → Task 4, restart button in Task 8. HUD removal and settings absorption, input-monitor toggle → Task 8. Radar scope, nose-up, rim chevrons, state colours → Task 6. Bearing tape, cockpit-only, clamped ends → Task 7 and `_apply_view_chrome` in Task 8. Y and B freed → Task 8. Mini-Raptor mesh with measured scale → Task 5. `world_hit_query` second source → Task 5. `buildings_near` → Task 1.

**Type consistency.** `Drone.update(delta, player_position, player_nose, city_centre, rng) -> bool` is defined in Task 3 and called that way in Task 5. `drone.id`, `drone.state`, `drone.position` are read by Tasks 5, 6, 7, 8 as defined in Task 3. `RaidMission.building_damaged(building_id, accumulated)` matches the `building_damaged(building_id, accumulated, relative_height)` signal it is fed from in Task 8, with the third argument dropped. `DroneField.destroy_drone` returns `Variant` (Vector3 or null) exactly as `launcher_field.destroy_launcher` does, so the impact handler treats both alike. `secondary_entity_index` is named identically in Task 5's query change and Task 8's wiring.

**Known soft spots.** Task 8 Step 4 is the largest single edit in the plan and touches a 1,300-line file in a dozen places; the `grep` at its end is the check that nothing was missed. The city centre is passed as `Vector3.ZERO`, which is right for the packaged Surfers theatre where the launchers sit near the origin, and is the first thing to change if drones never enter `ATTACK_RUN` in another theatre.
