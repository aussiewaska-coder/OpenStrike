# F-22 Weapons Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unguided rocket salvos off the F-22 with thick persistent smoke trails, and a weapon selector on X.

**Architecture:** Rockets join the existing `projectile_manager` rather than getting a second one, by having each round carry its own flight model — this keeps one copy of the continuous segment hit query that stops fast rounds tunnelling through walls. Smoke is one `ImmediateMesh` rebuilt each frame holding every live trail as camera-facing quad strips, giving one draw call regardless of rocket count. Pure logic lives in `RefCounted` modules that headless tests drive directly; nodes stay thin.

**Tech Stack:** Godot 4.7.2, GDScript. No physics server, no `RigidBody3D` — this project hand-rolls fixed-step simulation deliberately.

**Spec:** `docs/superpowers/specs/2026-09-02-jet-weapons-phase1-design.md`

## Global Constraints

- Godot binary for all test runs: `/root/godot-dist/Godot_v4.7.2-stable_linux.arm64`
- Test command shape: `<godot> --headless --script tests/<name>_test.gd`
- Every test file is `extends SceneTree`, does its work in `_init()`, prints `<NAME>_TEST_PASS` on success and calls `quit()`. Failure goes through a `_fail()` helper that calls `push_error(message)` then `quit(1)`.
- A test "passes" only if `<NAME>_TEST_PASS` appears in stdout. A zero exit code alone is not proof — Godot exits 0 on some script errors.
- The full suite must stay green: 36 tests before this plan, 42 after.
- Comments explain **why**, not what. Where a constant was chosen because something failed without it, record that failure beside the constant. This matches the surrounding code and is not optional.
- No `TODO`/`FIXME` left in committed code.
- Trail tuning constants start at the spec's values: `TRAIL_SEGMENT_METRES` 2.5, `TRAIL_LIFETIME_SECONDS` 4.5, `TRAIL_BIRTH_WIDTH` 0.6, `TRAIL_MAX_WIDTH` 7.0, `MAX_TRAIL_SEGMENTS` 2400.

**Refinement on the spec:** the spec described `trail_renderer.gd` as one unit. This plan splits it into `trail_buffer.gd` (pure breadcrumb logic, headless-testable) and `trail_renderer.gd` (the node that owns buffers and builds the mesh). The mesh cannot be meaningfully asserted headless; the buffer logic is where every real bug will live.

---

### Task 1: Per-round flight models in the projectile manager

Rockets need powered flight, and `ballistics.advance()` is gravity plus drag. Rather than a second manager, each round carries its own flight model. Expiry bounds move with it — otherwise a rocket would be retired at the shell's 4 km and 20 s.

**Files:**
- Modify: `scripts/weapons/ballistics.gd:38` (advance signature), add envelope accessors
- Modify: `scripts/weapons/cannon_round.gd` (carry a flight model)
- Modify: `scripts/weapons/projectile_manager.gd:80-99` (`_advance_round`)
- Test: `tests/projectile_flight_model_test.gd` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: the flight-model contract every projectile type implements —
  `advance(point: Vector3, velocity: Vector3, delta: float, age: float) -> Array` returning `[next_point, next_velocity]`;
  `envelope_seconds() -> float`; `envelope_metres() -> float`.
  `CannonRound.flight` (a `RefCounted`, defaults to null meaning "use the manager's shared ballistics").

- [ ] **Step 1: Write the failing test**

Create `tests/projectile_flight_model_test.gd`:

```gdscript
extends SceneTree

## A round advances through the flight model it carries, and is retired by that
## model's envelope rather than the gun's. Without the second half, a rocket
## would die at the 30 mm shell's 4 km no matter what its motor could do.

const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")
const CANNON_ROUND := preload("res://scripts/weapons/cannon_round.gd")
const PROJECTILE_MANAGER := preload("res://scripts/weapons/projectile_manager.gd")


## A flight model that ignores physics entirely and marches +X at 100 m/s, so
## its effect is unmistakable against real ballistics.
class StubFlight:
	extends RefCounted
	var advance_calls := 0
	var last_age := -1.0

	func advance(point: Vector3, velocity: Vector3, delta: float, age: float) -> Array:
		advance_calls += 1
		last_age = age
		return [point + Vector3(100.0 * delta, 0.0, 0.0), velocity]

	func envelope_seconds() -> float:
		return 0.25

	func envelope_metres() -> float:
		return 100000.0


func _init() -> void:
	_ballistics_keeps_its_shape()
	_round_uses_its_own_flight()
	_round_expires_on_its_own_envelope()
	print("PROJECTILE_FLIGHT_MODEL_TEST_PASS")
	quit()


## The gun's own model must be unchanged: the HUD pipper solves with this exact
## object, so a drift here puts the reticle somewhere the shells do not go.
func _ballistics_keeps_its_shape() -> void:
	var ballistics = BALLISTICS.new()
	var without_age: Array = ballistics.advance(Vector3.ZERO, Vector3(100.0, 0.0, 0.0), 0.02)
	var with_age: Array = ballistics.advance(Vector3.ZERO, Vector3(100.0, 0.0, 0.0), 0.02, 3.0)
	if not (without_age[0] as Vector3).is_equal_approx(with_age[0]):
		_fail("the age argument must not change ballistic flight")
	if not is_equal_approx(ballistics.envelope_seconds(), ballistics.maximum_flight_seconds):
		_fail("ballistics must report its own flight-seconds envelope")
	if not is_equal_approx(ballistics.envelope_metres(), ballistics.maximum_range):
		_fail("ballistics must report its own range envelope")


func _round_uses_its_own_flight() -> void:
	var manager = PROJECTILE_MANAGER.new()
	manager.ballistics = BALLISTICS.new()
	var flight := StubFlight.new()
	var round_data = CANNON_ROUND.new()
	round_data.initialise(1, Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO, false, null, "test")
	round_data.flight = flight
	manager.spawn(round_data)
	manager.step(0.1)
	if flight.advance_calls == 0:
		_fail("the manager must advance a round through the flight model it carries")
	if round_data.position.x <= 0.0:
		_fail("the stub flight marches +X, so the round must have moved, got %f" % round_data.position.x)
	if flight.last_age < 0.0:
		_fail("the flight model must receive the round's age")


func _round_expires_on_its_own_envelope() -> void:
	var manager = PROJECTILE_MANAGER.new()
	manager.ballistics = BALLISTICS.new()
	var round_data = CANNON_ROUND.new()
	round_data.initialise(1, Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO, false, null, "test")
	round_data.flight = StubFlight.new()
	manager.spawn(round_data)
	# The stub's envelope is 0.25 s; the gun's is 20 s. Step past the former.
	for _i in range(40):
		manager.step(0.02)
	if not manager.active_rounds.is_empty():
		_fail("the round must retire on its own 0.25 s envelope, not the gun's 20 s")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/projectile_flight_model_test.gd 2>&1 | grep -v "^WARNING\|^Godot Engine\|at: setup2\|Telemetry"
```

Expected: FAIL — `Invalid call. Nonexistent function 'envelope_seconds'` (or a parse error on the 4-argument `advance`). It must NOT print `PROJECTILE_FLIGHT_MODEL_TEST_PASS`.

- [ ] **Step 3: Add the envelope accessors and the ignored age argument to ballistics**

In `scripts/weapons/ballistics.gd`, change the `advance` signature at line 38 and add the accessors after it:

```gdscript
## One integration step, trapezoidal like solve() below. Live rounds advance
## through this exact function, so a round cannot drift from the pipper.
## Returns [next_point, next_velocity].
##
## `age` is unused here and exists so that every projectile flight model shares
## one signature: a rocket's thrust depends on how long its motor has been
## burning, and a shell's does not.
func advance(point: Vector3, velocity: Vector3, delta: float, _age := 0.0) -> Array:
```

Then append to the same file:

```gdscript
## How long and how far this projectile may fly before the manager retires it.
## Read per round rather than per manager, because a rocket judged by the 30 mm
## shell's four kilometres would die with its motor still burning.
func envelope_seconds() -> float:
	return maximum_flight_seconds


func envelope_metres() -> float:
	return maximum_range
```

- [ ] **Step 4: Give the round a flight model slot**

In `scripts/weapons/cannon_round.gd`, add beside the other fields:

```gdscript
## The flight model this round advances through. Null means the manager's
## shared ballistics, which is what every 30 mm shell wants.
var flight: RefCounted = null
```

And in `initialise()`, add `flight = null` alongside the other resets, so a
pooled round cannot inherit the previous occupant's flight model. Place it
immediately after `weapon_source = source`.

- [ ] **Step 5: Advance and retire through the round's model**

In `scripts/weapons/projectile_manager.gd`, replace `_advance_round` (lines 80-99) with:

```gdscript
func _advance_round(round_data: RefCounted, fixed_step: float) -> bool:
	# Each round flies through the model it carries. A shell has none and takes
	# the shared ballistics; a rocket brings a motor. The manager stays the one
	# place that owns pooling and the swept hit query.
	var flight: RefCounted = round_data.flight if round_data.flight != null else ballistics
	var stepped: Array = flight.advance(
		round_data.position, round_data.velocity, fixed_step, round_data.age
	)
	var next_position: Vector3 = stepped[0]
	round_data.previous_position = round_data.position
	round_data.velocity = stepped[1]
	if hit_query != null:
		# Continuous segment intersection, so an 805 m/s round cannot tunnel
		# through a 16 m thick facade between steps.
		var result: RefCounted = hit_query.query_segment(round_data.position, next_position)
		if result != null and result.hit:
			round_data.position = result.position
			projectile_impacted.emit(result, round_data)
			return false
	round_data.distance += round_data.position.distance_to(next_position)
	round_data.position = next_position
	round_data.age += fixed_step
	if round_data.age >= flight.envelope_seconds() or round_data.distance >= flight.envelope_metres():
		projectile_expired.emit(round_data)
		return false
	return true
```

- [ ] **Step 6: Run the new test and the existing weapons tests**

```bash
cd /root/OpenStrike && G=/root/godot-dist/Godot_v4.7.2-stable_linux.arm64
for t in projectile_flight_model ballistics cannon_integration cannon_rate cannon_aim pipper_agreement; do
  printf "%-26s " "$t"
  $G --headless --script tests/${t}_test.gd 2>&1 | grep -oE "_PASS" | head -1
  echo
done
```

Expected: every line prints `_PASS`. `pipper_agreement` matters most — it is the test that proves the reticle and the shells still agree.

- [ ] **Step 7: Commit**

```bash
git add scripts/weapons/ballistics.gd scripts/weapons/cannon_round.gd \
        scripts/weapons/projectile_manager.gd tests/projectile_flight_model_test.gd
git commit -m "Let each round bring its own flight model

A rocket has a motor and a shell does not, but both want the pooling and the
swept hit query that stops a fast round tunnelling through a facade. So the
manager keeps those and asks the round how it flies, including how long and how
far it may fly -- judged by the gun's envelope a rocket would expire at four
kilometres with its motor still burning."
```

---

### Task 2: Rocket flight model

**Files:**
- Create: `scripts/weapons/rocket_flight.gd`
- Test: `tests/rocket_flight_test.gd` (create)

**Interfaces:**
- Consumes: the flight-model contract from Task 1.
- Produces: `RocketFlight` (`RefCounted`) with `advance(point, velocity, delta, age) -> Array`, `envelope_seconds() -> float`, `envelope_metres() -> float`, `launch_velocity(direction: Vector3, inherited: Vector3) -> Vector3`, `is_boosting(age: float) -> bool`, and constants `MOTOR_BURN_SECONDS`, `MOTOR_ACCELERATION`, `EJECTION_SPEED`, `DRAG_PER_SECOND`, `MAX_FLIGHT_SECONDS`, `MAX_RANGE_METRES`.

- [ ] **Step 1: Write the failing test**

Create `tests/rocket_flight_test.gd`:

```gdscript
extends SceneTree

## The rocket's whole character is in two phases: it accelerates hard and flies
## fairly straight while the motor burns, then droops once it is out. If the
## droop is not visible in a salvo, the model may as well be a shell.

const ROCKET := preload("res://scripts/weapons/rocket_flight.gd")


func _init() -> void:
	_boost_accelerates()
	_motor_cuts_out()
	_coast_falls()
	_launch_inherits_the_aircraft()
	_envelope_is_its_own()
	print("ROCKET_FLIGHT_TEST_PASS")
	quit()


func _boost_accelerates() -> void:
	var flight = ROCKET.new()
	if not flight.is_boosting(0.0):
		_fail("the motor must be lit at launch")
	var start := Vector3(120.0, 0.0, 0.0)
	var stepped: Array = flight.advance(Vector3.ZERO, start, 0.05, 0.0)
	var gained: float = (stepped[1] as Vector3).x - start.x
	if gained <= 0.0:
		_fail("the motor must add speed along the heading, gained %f" % gained)


func _motor_cuts_out() -> void:
	var flight = ROCKET.new()
	if flight.is_boosting(ROCKET.MOTOR_BURN_SECONDS + 0.01):
		_fail("the motor must cut out at the end of its burn")
	var fast := Vector3(300.0, 0.0, 0.0)
	var boosting: Array = flight.advance(Vector3.ZERO, fast, 0.05, 0.0)
	var coasting: Array = flight.advance(Vector3.ZERO, fast, 0.05, ROCKET.MOTOR_BURN_SECONDS + 1.0)
	if (boosting[1] as Vector3).x <= (coasting[1] as Vector3).x:
		_fail("a burning motor must leave the rocket faster than a dead one")


## Coasting is ballistic: gravity wins and the nose drops. This is the droop.
func _coast_falls() -> void:
	var flight = ROCKET.new()
	var level := Vector3(250.0, 0.0, 0.0)
	var stepped: Array = flight.advance(
		Vector3.ZERO, level, 0.05, ROCKET.MOTOR_BURN_SECONDS + 1.0
	)
	if (stepped[1] as Vector3).y >= 0.0:
		_fail("a coasting rocket must fall, got vy %f" % (stepped[1] as Vector3).y)


func _launch_inherits_the_aircraft() -> void:
	var flight = ROCKET.new()
	var carried := Vector3(0.0, 0.0, -175.0)
	var launched: Vector3 = flight.launch_velocity(Vector3(0.0, 0.0, -1.0), carried)
	if launched.length() <= carried.length():
		_fail("a rocket must leave faster than the aircraft carrying it")
	# Ejection alone is small: the motor, not the rail, is what makes it quick.
	if launched.length() > carried.length() + 60.0:
		_fail("the ejection impulse must be modest, got %f" % (launched.length() - carried.length()))


func _envelope_is_its_own() -> void:
	var flight = ROCKET.new()
	if flight.envelope_seconds() <= 0.0 or flight.envelope_metres() <= 0.0:
		_fail("a rocket must declare a positive envelope")
	if flight.envelope_metres() <= 4000.0:
		_fail("the rocket must outrange the 30 mm shell it no longer borrows limits from")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/rocket_flight_test.gd 2>&1 | grep -v "^WARNING\|^Godot Engine\|at: setup2\|Telemetry"
```

Expected: FAIL — `Failed to load script ... rocket_flight.gd`. Must not print `ROCKET_FLIGHT_TEST_PASS`.

- [ ] **Step 3: Write the flight model**

Create `scripts/weapons/rocket_flight.gd`:

```gdscript
extends RefCounted

## Powered flight for an unguided rocket, in two phases.
##
## Boost: the motor pushes along the rocket's own heading and dominates gravity,
## so the rocket flies nearly straight and gains speed fast. Coast: the motor is
## out and the rocket is a shell -- gravity and drag, the same terms
## ballistics.gd uses.
##
## The visible point of modelling it at all is the transition. A salvo climbs
## away hard, then noticeably droops when the motors quit, and that droop is
## what makes a salvo legible as rockets rather than as fast bullets.

const GRAVITY := 9.80665

## Short, like a real folding-fin aerial rocket. A long burn would flatten the
## trajectory into a laser and take the droop away with it.
const MOTOR_BURN_SECONDS := 1.6
## Along the heading, in m/s^2. Roughly 12 g, which takes a rocket ejected at
## 25 m/s to a few hundred by burnout.
const MOTOR_ACCELERATION := 118.0
## Off the rail before the motor lights. Deliberately small: the motor is what
## makes a rocket quick, and a big rail impulse reads as a railgun.
const EJECTION_SPEED := 25.0
## Slightly slicker than the 30 mm shell -- a fin-stabilised rocket is a better
## shape than a tumbling-averse spinning slug.
const DRAG_PER_SECOND := 0.055
## Its own envelope. Borrowing the gun's four kilometres would have retired a
## rocket with its motor still burning.
const MAX_FLIGHT_SECONDS := 26.0
const MAX_RANGE_METRES := 7000.0


func is_boosting(age: float) -> bool:
	return age < MOTOR_BURN_SECONDS


## Thrust along the current heading, then gravity and drag on everything.
func advance(point: Vector3, velocity: Vector3, delta: float, age := 0.0) -> Array:
	var next_velocity := velocity * exp(-DRAG_PER_SECOND * delta)
	if is_boosting(age) and not velocity.is_zero_approx():
		next_velocity += velocity.normalized() * MOTOR_ACCELERATION * delta
	next_velocity.y -= GRAVITY * delta
	# Trapezoidal, matching ballistics.advance, so rockets and shells integrate
	# the same way and a fast rocket does not out-run its own hit query.
	var next_point := point + (velocity + next_velocity) * 0.5 * delta
	return [next_point, next_velocity]


func launch_velocity(direction: Vector3, inherited_velocity: Vector3) -> Vector3:
	return direction.normalized() * EJECTION_SPEED + inherited_velocity


func envelope_seconds() -> float:
	return MAX_FLIGHT_SECONDS


func envelope_metres() -> float:
	return MAX_RANGE_METRES
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/rocket_flight_test.gd 2>&1 | grep -oE "ROCKET_FLIGHT_TEST_PASS|SCRIPT ERROR.*"
```

Expected: `ROCKET_FLIGHT_TEST_PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/weapons/rocket_flight.gd tests/rocket_flight_test.gd
git commit -m "Give the rocket a motor, and a moment when it quits

Boost along the heading while it burns, ballistic afterwards. The transition is
the point: a salvo climbs away hard and then droops, and that droop is what
reads as rockets rather than as very fast bullets."
```

---

### Task 3: Trail buffer

The pure half of the smoke system: where breadcrumbs go and when they die. Every real bug lives here, and none of it needs a GPU.

**Files:**
- Create: `scripts/effects/trail_buffer.gd`
- Test: `tests/trail_buffer_test.gd` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `TrailBuffer` (`RefCounted`) with `push(point: Vector3, now: float) -> bool`, `advance_age(now: float) -> void`, `segment_count() -> int`, `point_at(index: int) -> Vector3`, `age_at(index: int, now: float) -> float`, `stop_emitting() -> void`, `is_finished(now: float) -> bool`, `emitting: bool`; and the static curves `width_for_age(age: float) -> float`, `alpha_for_age(age: float) -> float`; constants `SEGMENT_METRES`, `LIFETIME_SECONDS`, `BIRTH_WIDTH`, `MAX_WIDTH`.

- [ ] **Step 1: Write the failing test**

Create `tests/trail_buffer_test.gd`:

```gdscript
extends SceneTree

## Breadcrumbs are laid by DISTANCE, never per frame. Laying them per frame
## makes trail density a function of framerate, so a hitching phone draws a
## gap-toothed trail and a fast one wastes vertices on a dense stub.

const TRAIL := preload("res://scripts/effects/trail_buffer.gd")


func _init() -> void:
	_spacing_is_by_distance()
	_width_grows_and_alpha_fades()
	_old_segments_retire()
	_finishes_after_the_last_breadcrumb_dies()
	print("TRAIL_BUFFER_TEST_PASS")
	quit()


func _spacing_is_by_distance() -> void:
	var trail = TRAIL.new()
	trail.push(Vector3.ZERO, 0.0)
	# A step far shorter than the spacing must not lay anything.
	var laid: bool = trail.push(Vector3(TRAIL.SEGMENT_METRES * 0.1, 0.0, 0.0), 0.01)
	if laid:
		_fail("a step shorter than the spacing must not lay a breadcrumb")
	# One beyond it must.
	if not trail.push(Vector3(TRAIL.SEGMENT_METRES * 1.5, 0.0, 0.0), 0.02):
		_fail("a step past the spacing must lay a breadcrumb")

	# Sixty small frames covering the same ground as six big ones must produce
	# the same trail. This is the framerate-independence claim, tested.
	var fine = TRAIL.new()
	for i in range(61):
		fine.push(Vector3(float(i) * 1.0, 0.0, 0.0), float(i) * 0.001)
	var coarse = TRAIL.new()
	for i in range(7):
		coarse.push(Vector3(float(i) * 10.0, 0.0, 0.0), float(i) * 0.01)
	if absf(fine.segment_count() - coarse.segment_count()) > 1:
		_fail("trail density must not depend on framerate, got %d against %d" % [
			fine.segment_count(), coarse.segment_count()
		])


func _width_grows_and_alpha_fades() -> void:
	if TRAIL.width_for_age(0.0) >= TRAIL.width_for_age(TRAIL.LIFETIME_SECONDS * 0.5):
		_fail("smoke must billow as it ages")
	if not is_equal_approx(TRAIL.width_for_age(0.0), TRAIL.BIRTH_WIDTH):
		_fail("a fresh breadcrumb must be born at the nozzle width")
	if TRAIL.width_for_age(TRAIL.LIFETIME_SECONDS * 4.0) > TRAIL.MAX_WIDTH + 0.001:
		_fail("billowing must stop at the maximum width")
	if TRAIL.alpha_for_age(0.0) <= TRAIL.alpha_for_age(TRAIL.LIFETIME_SECONDS * 0.9):
		_fail("smoke must thin as it ages")
	if TRAIL.alpha_for_age(TRAIL.LIFETIME_SECONDS + 0.1) > 0.0:
		_fail("smoke past its lifetime must be gone, not faint")


func _old_segments_retire() -> void:
	var trail = TRAIL.new()
	for i in range(40):
		trail.push(Vector3(float(i) * TRAIL.SEGMENT_METRES, 0.0, 0.0), float(i) * 0.05)
	var laid := trail.segment_count()
	if laid < 10:
		_fail("expected a long trail to test retirement, got %d" % laid)
	# Jump well past the lifetime; everything must age out.
	trail.advance_age(100.0)
	if trail.segment_count() != 0:
		_fail("every breadcrumb past its lifetime must retire, %d left" % trail.segment_count())


func _finishes_after_the_last_breadcrumb_dies() -> void:
	var trail = TRAIL.new()
	trail.push(Vector3.ZERO, 0.0)
	trail.push(Vector3(TRAIL.SEGMENT_METRES * 2.0, 0.0, 0.0), 0.1)
	trail.stop_emitting()
	if trail.is_finished(0.2):
		_fail("a dead rocket's smoke must linger, not vanish with it")
	if not trail.is_finished(TRAIL.LIFETIME_SECONDS + 1.0):
		_fail("the trail must eventually finish so its slot can be reused")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/trail_buffer_test.gd 2>&1 | grep -v "^WARNING\|^Godot Engine\|at: setup2\|Telemetry"
```

Expected: FAIL — `Failed to load script ... trail_buffer.gd`.

- [ ] **Step 3: Write the buffer**

Create `scripts/effects/trail_buffer.gd`:

```gdscript
extends RefCounted

## One trail's worth of breadcrumbs, and the curves that turn their age into a
## width and an alpha. No mesh, no node, no camera -- all of that belongs to
## trail_renderer.gd, and none of it is where the bugs are.
##
## Breadcrumbs are laid by DISTANCE TRAVELLED, never once per frame. Per-frame
## laying makes trail density a function of framerate: a phone that hitches
## draws a gap-toothed trail, and one running fast wastes vertices on a dense
## stub. Distance spacing gives the same smoke either way.

## Breadcrumb spacing. Smaller is smoother and costs vertices linearly.
const SEGMENT_METRES := 2.5
## How long smoke lingers before it is gone.
const LIFETIME_SECONDS := 4.5
## Width at the nozzle, where the smoke has not spread yet.
const BIRTH_WIDTH := 0.6
## Width once fully billowed.
const MAX_WIDTH := 7.0

## Points and the times they were laid. Parallel arrays rather than an array of
## structs: this is rebuilt into a mesh every frame and packed arrays keep that
## loop out of the allocator.
var points := PackedVector3Array()
var birth_times := PackedFloat32Array()
## False once the rocket that owned this is dead. The smoke it already laid
## keeps ageing -- a trail that vanished with its rocket would be worse than no
## trail at all.
var emitting := true

var _last_point := Vector3.ZERO
var _has_last := false


## Lays a breadcrumb if the source has travelled far enough since the last one.
## Returns whether one was actually laid.
func push(point: Vector3, now: float) -> bool:
	if not emitting:
		return false
	if not _has_last:
		_has_last = true
		_last_point = point
		points.append(point)
		birth_times.append(now)
		return true
	if _last_point.distance_to(point) < SEGMENT_METRES:
		return false
	_last_point = point
	points.append(point)
	birth_times.append(now)
	return true


## Retires everything older than the lifetime. Breadcrumbs are laid in order, so
## the dead ones are always a prefix and this is a single slice.
func advance_age(now: float) -> void:
	var alive := 0
	while alive < birth_times.size() and now - birth_times[alive] > LIFETIME_SECONDS:
		alive += 1
	if alive == 0:
		return
	points = points.slice(alive)
	birth_times = birth_times.slice(alive)


func stop_emitting() -> void:
	emitting = false


## A trail is finished when it is no longer emitting and its last breadcrumb has
## aged out, at which point the renderer can reclaim the slot.
func is_finished(now: float) -> bool:
	if emitting:
		return false
	if birth_times.is_empty():
		return true
	return now - birth_times[birth_times.size() - 1] > LIFETIME_SECONDS


## Quads are drawn between consecutive breadcrumbs, so a lone point is no
## segments and two points are one.
func segment_count() -> int:
	return maxi(points.size() - 1, 0)


func point_at(index: int) -> Vector3:
	return points[index]


func age_at(index: int, now: float) -> float:
	return now - birth_times[index]


## Smoke billows fast at first and then settles, so the width curve is a square
## root rather than a line.
static func width_for_age(age: float) -> float:
	var fraction := clampf(age / LIFETIME_SECONDS, 0.0, 1.0)
	return lerpf(BIRTH_WIDTH, MAX_WIDTH, sqrt(fraction))


## Alpha holds up early -- fresh smoke is opaque -- then falls away. Squaring
## the remaining life keeps the trail solid behind the rocket and lets the far
## end dissolve instead of ending in a visible edge.
static func alpha_for_age(age: float) -> float:
	var remaining := clampf(1.0 - age / LIFETIME_SECONDS, 0.0, 1.0)
	return remaining * remaining
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/trail_buffer_test.gd 2>&1 | grep -oE "TRAIL_BUFFER_TEST_PASS|SCRIPT ERROR.*"
```

Expected: `TRAIL_BUFFER_TEST_PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/effects/trail_buffer.gd tests/trail_buffer_test.gd
git commit -m "Lay smoke by the metre, not by the frame

Breadcrumbs spaced by distance travelled, so trail density does not change with
framerate -- a hitching phone would otherwise draw a gap-toothed trail. Width
and alpha are functions of age, so nothing per-segment needs storing beyond a
point and the moment it was laid."
```

---

### Task 4: Trail renderer

**Files:**
- Create: `scripts/effects/trail_renderer.gd`
- Test: `tests/trail_renderer_test.gd` (create)

**Interfaces:**
- Consumes: `TrailBuffer` from Task 3.
- Produces: `TrailRenderer` (`Node3D`) with `begin_trail(id: int) -> void`, `push_point(id: int, point: Vector3) -> void`, `end_trail(id: int) -> void`, `active_trail_count() -> int`, `total_segments() -> int`, and the static `strip_side(segment: Vector3, to_eye: Vector3, half_width: float) -> Vector3`; constant `MAX_TRAIL_SEGMENTS`.

- [ ] **Step 1: Write the failing test**

Create `tests/trail_renderer_test.gd`:

```gdscript
extends SceneTree

## The renderer's own logic: the camera-facing side vector, the global segment
## cap, and reclaiming finished trails. The ImmediateMesh itself is not asserted
## -- headless has no camera and a vertex buffer proves nothing about whether
## the smoke looks like smoke. That part is a device check.

const RENDERER := preload("res://scripts/effects/trail_renderer.gd")
const TRAIL := preload("res://scripts/effects/trail_buffer.gd")


func _init() -> void:
	_side_faces_the_camera()
	_degenerate_segments_make_no_geometry()
	_the_cap_holds()
	_finished_trails_are_reclaimed()
	print("TRAIL_RENDERER_TEST_PASS")
	quit()


## The ribbon must present its face to the viewer, so the side vector is
## perpendicular both to the segment and to the direction to the eye.
func _side_faces_the_camera() -> void:
	var segment := Vector3(1.0, 0.0, 0.0)
	var to_eye := Vector3(0.0, 0.0, 1.0)
	var side: Vector3 = RENDERER.strip_side(segment, to_eye, 3.0)
	if absf(side.dot(segment)) > 0.001:
		_fail("the ribbon's width must be perpendicular to its length")
	if absf(side.dot(to_eye)) > 0.001:
		_fail("the ribbon's width must be perpendicular to the view direction")
	if not is_equal_approx(side.length(), 3.0):
		_fail("the side vector must carry the half width, got %f" % side.length())


## Seen exactly end-on the cross product collapses. Emitting that quad gives
## zero-area geometry or NaNs; it must be refused instead.
func _degenerate_segments_make_no_geometry() -> void:
	var along := Vector3(1.0, 0.0, 0.0)
	var collapsed: Vector3 = RENDERER.strip_side(along, along, 3.0)
	if not collapsed.is_zero_approx():
		_fail("an end-on segment must produce no width, got %v" % collapsed)
	var nothing: Vector3 = RENDERER.strip_side(Vector3.ZERO, Vector3(0.0, 0.0, 1.0), 3.0)
	if not nothing.is_zero_approx():
		_fail("a zero-length segment must produce no width")


func _the_cap_holds() -> void:
	var renderer = RENDERER.new()
	# Twelve trails, each long enough on its own to threaten the cap.
	for id in range(12):
		renderer.begin_trail(id)
		for step in range(600):
			renderer.push_point(id, Vector3(float(step) * TRAIL.SEGMENT_METRES, float(id), 0.0))
	if renderer.total_segments() > RENDERER.MAX_TRAIL_SEGMENTS:
		_fail("the segment cap must hold, got %d over %d" % [
			renderer.total_segments(), RENDERER.MAX_TRAIL_SEGMENTS
		])
	if renderer.total_segments() == 0:
		_fail("capping must shorten trails, not delete them")


func _finished_trails_are_reclaimed() -> void:
	var renderer = RENDERER.new()
	renderer.begin_trail(1)
	renderer.push_point(1, Vector3.ZERO)
	renderer.push_point(1, Vector3(TRAIL.SEGMENT_METRES * 2.0, 0.0, 0.0))
	if renderer.active_trail_count() != 1:
		_fail("a started trail must be active")
	renderer.end_trail(1)
	if renderer.active_trail_count() != 1:
		_fail("smoke must outlive the rocket that laid it")
	# Age everything well past the lifetime.
	renderer.age_trails(TRAIL.LIFETIME_SECONDS * 3.0)
	if renderer.active_trail_count() != 0:
		_fail("a finished trail must free its slot, %d left" % renderer.active_trail_count())


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/trail_renderer_test.gd 2>&1 | grep -v "^WARNING\|^Godot Engine\|at: setup2\|Telemetry"
```

Expected: FAIL — `Failed to load script ... trail_renderer.gd`.

- [ ] **Step 3: Write the renderer**

Create `scripts/effects/trail_renderer.gd`:

```gdscript
extends Node3D

## Every live smoke trail in the world, in ONE ImmediateMesh rebuilt each frame.
##
## One draw call and one material however many rockets are up. The alternatives
## were an emitter node per rocket -- N draw calls, and mobile drivers disagree
## about trail geometry -- or pooled billboard puffs, which need hundreds of
## quads per trail before they stop reading as beads. Neither gets thick
## continuous smoke cheaply, and that is the whole point of the effect.
##
## It also matches the house style: cannon_fx pools plain MeshInstance3D quads
## by hand, and this project hand-rolls its simulation rather than reaching for
## the physics server.

const TRAIL_BUFFER := preload("res://scripts/effects/trail_buffer.gd")

## Hard ceiling across every trail. Reaching it shortens the oldest trails
## rather than dropping frames, so the effect degrades instead of the game.
## 2400 segments is 9600 vertices in one call -- trivial geometry. The real cost
## is fill rate from overlapping translucent quads, which is why width and
## lifetime are the knobs to pull if a device struggles, not this.
const MAX_TRAIL_SEGMENTS := 2400

@export var smoke_colour := Color(0.82, 0.82, 0.85)

var _mesh: ImmediateMesh
var _material: StandardMaterial3D
var _trails: Dictionary = {}
var _now := 0.0


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	_material = _make_material()
	material_override = _material
	# Smoke is world-space: it must not follow the aircraft that laid it.
	top_level = true
	global_transform = Transform3D.IDENTITY


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	# The geometry already faces the camera; billboarding it again would fight
	# the strip maths and spin every quad about its own centre.
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	# Depth-write off is the usual soft-smoke trade: trails blend with each
	# other instead of one occluding the next, which is what you want for smoke
	# and would be wrong for solid geometry.
	material.no_depth_test = false
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func begin_trail(id: int) -> void:
	_trails[id] = TRAIL_BUFFER.new()


func push_point(id: int, point: Vector3) -> void:
	var trail = _trails.get(id)
	if trail == null:
		return
	trail.push(point, _now)
	_enforce_cap()


## The rocket is gone; its smoke is not. The buffer stops taking breadcrumbs and
## ages out on its own.
func end_trail(id: int) -> void:
	var trail = _trails.get(id)
	if trail != null:
		trail.stop_emitting()


func active_trail_count() -> int:
	return _trails.size()


func total_segments() -> int:
	var total := 0
	for trail in _trails.values():
		total += trail.segment_count()
	return total


## Ages every trail to `now` and reclaims the finished ones. Separate from
## _process so the tests can drive time directly.
func age_trails(now: float) -> void:
	_now = now
	var finished: Array = []
	for id in _trails:
		var trail = _trails[id]
		trail.advance_age(now)
		if trail.is_finished(now):
			finished.append(id)
	for id in finished:
		_trails.erase(id)


func _process(delta: float) -> void:
	age_trails(_now + delta)
	_rebuild()


## Retires the oldest breadcrumbs until the total is back inside the cap. Ageing
## by one lifetime-step at a time would be gentler but can fail to converge; a
## direct trim cannot.
func _enforce_cap() -> void:
	var over := total_segments() - MAX_TRAIL_SEGMENTS
	if over <= 0:
		return
	for trail in _trails.values():
		if over <= 0:
			break
		var drop: int = mini(over, maxi(trail.segment_count() - 1, 0))
		if drop <= 0:
			continue
		trail.points = trail.points.slice(drop)
		trail.birth_times = trail.birth_times.slice(drop)
		over -= drop


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	var eye := camera.global_position
	var wrote_any := false
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for trail in _trails.values():
		if _write_trail(trail, eye):
			wrote_any = true
	_mesh.surface_end()
	if not wrote_any:
		_mesh.clear_surfaces()


func _write_trail(trail, eye: Vector3) -> bool:
	var segments := trail.segment_count()
	if segments <= 0:
		return false
	var wrote := false
	for index in range(segments):
		var near_point: Vector3 = trail.point_at(index)
		var far_point: Vector3 = trail.point_at(index + 1)
		var direction := far_point - near_point
		var near_side := strip_side(
			direction, eye - near_point, TRAIL_BUFFER.width_for_age(trail.age_at(index, _now)) * 0.5
		)
		var far_side := strip_side(
			direction,
			eye - far_point,
			TRAIL_BUFFER.width_for_age(trail.age_at(index + 1, _now)) * 0.5
		)
		if near_side.is_zero_approx() and far_side.is_zero_approx():
			continue
		var near_colour := smoke_colour
		near_colour.a = TRAIL_BUFFER.alpha_for_age(trail.age_at(index, _now))
		var far_colour := smoke_colour
		far_colour.a = TRAIL_BUFFER.alpha_for_age(trail.age_at(index + 1, _now))
		_quad(near_point, far_point, near_side, far_side, near_colour, far_colour)
		wrote = true
	return wrote


func _quad(
	near_point: Vector3,
	far_point: Vector3,
	near_side: Vector3,
	far_side: Vector3,
	near_colour: Color,
	far_colour: Color
) -> void:
	var a := near_point - near_side
	var b := near_point + near_side
	var c := far_point + far_side
	var d := far_point - far_side
	_mesh.surface_set_color(near_colour)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(near_colour)
	_mesh.surface_add_vertex(b)
	_mesh.surface_set_color(far_colour)
	_mesh.surface_add_vertex(c)

	_mesh.surface_set_color(near_colour)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(far_colour)
	_mesh.surface_add_vertex(c)
	_mesh.surface_set_color(far_colour)
	_mesh.surface_add_vertex(d)


## Half-width perpendicular to both the segment and the view direction, so the
## ribbon always turns its face to the camera. Returns zero for a degenerate
## segment or one seen exactly end-on, where the cross product collapses and the
## quad would be zero-area or NaN.
static func strip_side(segment: Vector3, to_eye: Vector3, half_width: float) -> Vector3:
	if segment.is_zero_approx() or to_eye.is_zero_approx():
		return Vector3.ZERO
	var side := segment.normalized().cross(to_eye.normalized())
	if side.length_squared() < 0.000001:
		return Vector3.ZERO
	return side.normalized() * half_width
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/trail_renderer_test.gd 2>&1 | grep -oE "TRAIL_RENDERER_TEST_PASS|SCRIPT ERROR.*"
```

Expected: `TRAIL_RENDERER_TEST_PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/effects/trail_renderer.gd tests/trail_renderer_test.gd
git commit -m "Draw every smoke trail in one mesh

One ImmediateMesh rebuilt per frame holding every live trail as camera-facing
quad strips: one draw call and one material however many rockets are up. A
segment cap trims the oldest smoke first, so a heavy salvo shortens trails
rather than dropping frames."
```

---

### Task 5: Weapon selection

**Files:**
- Create: `scripts/weapons/weapon_selection.gd`
- Test: `tests/weapon_selection_test.gd` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `WeaponSelection` (`RefCounted`) with `enum Weapon {CANNON, ROCKETS}`, `current: int`, `cycle() -> int`, `name_of(weapon: int) -> String`, signal `changed(weapon: int)`.

- [ ] **Step 1: Write the failing test**

Create `tests/weapon_selection_test.gd`:

```gdscript
extends SceneTree

## Selection knows nothing about the weapons themselves -- it is an enum and a
## cycle. Phase 3 adds MISSILES to the same enum and nothing here changes.

const SELECTION := preload("res://scripts/weapons/weapon_selection.gd")


func _init() -> void:
	var selection = SELECTION.new()
	if selection.current != SELECTION.Weapon.CANNON:
		_fail("the gun is the default weapon")

	var seen: Array[int] = []
	for _i in range(SELECTION.Weapon.size()):
		seen.append(selection.current)
		selection.cycle()
	if selection.current != SELECTION.Weapon.CANNON:
		_fail("cycling through every weapon must return to the first")
	if seen.size() != SELECTION.Weapon.size():
		_fail("the cycle must visit every weapon exactly once")
	for weapon in SELECTION.Weapon.values():
		if not seen.has(weapon):
			_fail("the cycle skipped weapon %d" % weapon)
		if selection.name_of(weapon).is_empty():
			_fail("every weapon needs a name for the HUD, %d has none" % weapon)

	# The signal is how the HUD learns, so it must actually fire.
	var fired: Array[int] = []
	selection.changed.connect(func(weapon: int) -> void: fired.append(weapon))
	selection.cycle()
	if fired.size() != 1:
		_fail("cycling must announce the new weapon exactly once, got %d" % fired.size())
	if fired[0] != selection.current:
		_fail("the announced weapon must be the current one")

	print("WEAPON_SELECTION_TEST_PASS")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/weapon_selection_test.gd 2>&1 | grep -v "^WARNING\|^Godot Engine\|at: setup2\|Telemetry"
```

Expected: FAIL — `Failed to load script ... weapon_selection.gd`.

- [ ] **Step 3: Write the selector**

Create `scripts/weapons/weapon_selection.gd`:

```gdscript
extends RefCounted

## Which weapon the trigger belongs to. Deliberately ignorant of the weapons
## themselves: adding phase 3's guided missiles means adding one enum entry.
##
## Selection gates rather than rebinds. The cannon keeps L3 and the rockets keep
## L1, and the selector decides which one is live, so a wrong selection shows up
## as a weapon that will not fire rather than as a trigger that does nothing.

signal changed(weapon: int)

enum Weapon {CANNON, ROCKETS}

var current: int = Weapon.CANNON


func cycle() -> int:
	current = (current + 1) % Weapon.size()
	changed.emit(current)
	return current


func name_of(weapon: int) -> String:
	match weapon:
		Weapon.CANNON:
			return "20MM"
		Weapon.ROCKETS:
			return "ROCKETS"
	return "UNKNOWN"
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/weapon_selection_test.gd 2>&1 | grep -oE "WEAPON_SELECTION_TEST_PASS|SCRIPT ERROR.*"
```

Expected: `WEAPON_SELECTION_TEST_PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/weapons/weapon_selection.gd tests/weapon_selection_test.gd
git commit -m "Add a weapon selector that gates rather than rebinds

The cannon keeps L3 and the rockets keep L1; selection decides which is live. A
wrong selection then reads as a weapon that will not fire, rather than as a
trigger that silently does nothing."
```

---

### Task 6: Tap versus hold on X

X is the settings panel today. It becomes a tap-to-cycle-weapons, hold-for-settings button, which needs a release event the input layer does not currently have.

**Files:**
- Modify: `scripts/input/gamepad_input.gd:5` (signals), `:67-72` (`_process`), `:327-344` (bindings)
- Test: `tests/gamepad_input_test.gd` (modify — append a new section)

**Interfaces:**
- Consumes: nothing.
- Produces: signal `action_released(action: StringName, held_seconds: float)`; `ACTION_WEAPON_CYCLE` bound to `JOY_BUTTON_X`; constant `SETTINGS_HOLD_SECONDS`; static `is_hold(held_seconds: float) -> bool`.

- [ ] **Step 1: Write the failing test**

Append to `tests/gamepad_input_test.gd`, and add the call to its `_init()`:

```gdscript
## X carries two jobs separated by time: a tap cycles weapons, a hold opens
## settings. The discrimination is a pure function of the hold duration, so it
## is testable without a controller.
func _tap_and_hold_are_distinguished() -> void:
	var input := preload("res://scripts/input/gamepad_input.gd")
	if input.is_hold(input.SETTINGS_HOLD_SECONDS + 0.05):
		pass
	else:
		_fail("a press past the threshold must count as a hold")
	if input.is_hold(input.SETTINGS_HOLD_SECONDS - 0.05):
		_fail("a press short of the threshold must count as a tap")
	if input.is_hold(0.0):
		_fail("an instant release must be a tap")
	# Half a second is about the longest a deliberate tap runs; much more and
	# the player cannot cycle weapons quickly in a fight.
	if input.SETTINGS_HOLD_SECONDS > 0.6:
		_fail("the hold threshold must stay short enough to cycle weapons quickly")
	if input.SETTINGS_HOLD_SECONDS < 0.3:
		_fail("a threshold this short would open settings on an ordinary tap")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/gamepad_input_test.gd 2>&1 | grep -v "^WARNING\|^Godot Engine\|at: setup2\|Telemetry"
```

Expected: FAIL — `Invalid call. Nonexistent function 'is_hold'`.

- [ ] **Step 3: Add the release signal, hold timing, and the X binding**

In `scripts/input/gamepad_input.gd`, beside the existing `action_pressed` signal at line 5:

```gdscript
signal action_released(action: StringName, held_seconds: float)
```

Add the action constant beside the others (near `ACTION_SETTINGS`):

```gdscript
## Tap cycles the weapon; holding the same button opens settings. X is the only
## button left, and settings is not something anyone reaches for mid-fight.
const ACTION_WEAPON_CYCLE := &"weapon_cycle"
## How long X must be held to mean settings rather than a weapon change.
const SETTINGS_HOLD_SECONDS := 0.45
```

Add `ACTION_WEAPON_CYCLE` to the `BUTTON_ACTIONS` array.

Add the hold-time store beside the other vars:

```gdscript
var _hold_started: Dictionary = {}
```

Replace `_process` (lines 67-72) with:

```gdscript
func _process(_delta: float) -> void:
	if active_device < 0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for action in BUTTON_ACTIONS:
		if Input.is_action_just_pressed(action):
			_hold_started[action] = now
			action_pressed.emit(action)
		elif Input.is_action_just_released(action):
			var started: float = _hold_started.get(action, now)
			_hold_started.erase(action)
			action_released.emit(action, now - started)
```

Add the discriminator:

```gdscript
## A press is a hold once it passes the threshold. Static so the decision can be
## tested without a controller attached.
static func is_hold(held_seconds: float) -> bool:
	return held_seconds >= SETTINGS_HOLD_SECONDS
```

Finally, rebind X in `_register_input_actions`. Replace the `ACTION_SETTINGS` line with:

```gdscript
	# X taps to cycle weapons and holds to open settings. Settings keeps its
	# on-screen button too, so a mistimed hold never locks anyone out of it.
	_add_button_action(ACTION_WEAPON_CYCLE, JoyButton.JOY_BUTTON_X)
```

Leave `ACTION_SETTINGS` declared and in `BUTTON_ACTIONS`, but bound to no
button — `main.gd` raises it from the hold in Task 7, and the on-screen button
still emits it.

- [ ] **Step 4: Run the input test**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/gamepad_input_test.gd 2>&1 | grep -oE "GAMEPAD_INPUT_TEST_PASS|SCRIPT ERROR.*"
```

Expected: `GAMEPAD_INPUT_TEST_PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/input/gamepad_input.gd tests/gamepad_input_test.gd
git commit -m "Give buttons a release event, and X two jobs

Tap X to cycle weapons, hold it for settings. The input layer only ever emitted
presses, so this adds a release signal carrying how long the button was down --
general, rather than a special case for one button. Settings keeps its
on-screen button, so a mistimed hold cannot lock anyone out of it."
```

---

### Task 7: Rocket pod

**Files:**
- Create: `scripts/weapons/rocket_pod.gd`
- Test: `tests/rocket_pod_test.gd` (create)

**Interfaces:**
- Consumes: `RocketFlight` (Task 2), `WeaponSelection.Weapon` (Task 5), `projectile_manager.acquire_round()`/`spawn()` (Task 1).
- Produces: `RocketPod` (`Node3D`) with properties `projectile_manager`, `carrier`, `hardpoints: Array[Node3D]`, `selection`, `rockets_remaining: int`, `is_reloading: bool`; methods `update(delta: float, trigger_held: bool) -> void`, `can_fire() -> bool`; signal `rocket_fired(round_data: RefCounted, hardpoint_index: int)`; constants `POD_CAPACITY`, `RIPPLE_INTERVAL`, `RELOAD_SECONDS`.

- [ ] **Step 1: Write the failing test**

Create `tests/rocket_pod_test.gd`:

```gdscript
extends SceneTree

## A salvo is a ripple, not a burst: rockets leave one at a time, alternating
## sides. Emptying the pod in a single frame gives one puff of smoke and no
## sense of a salvo at all.

const POD := preload("res://scripts/weapons/rocket_pod.gd")
const SELECTION := preload("res://scripts/weapons/weapon_selection.gd")
const PROJECTILE_MANAGER := preload("res://scripts/weapons/projectile_manager.gd")
const BALLISTICS := preload("res://scripts/weapons/ballistics.gd")


func _init() -> void:
	_ripples_rather_than_bursts()
	_alternates_hardpoints()
	_empties_and_reloads()
	_stays_silent_when_the_gun_is_selected()
	print("ROCKET_POD_TEST_PASS")
	quit()


func _build() -> Node3D:
	var manager = PROJECTILE_MANAGER.new()
	manager.ballistics = BALLISTICS.new()
	var pod = POD.new()
	pod.projectile_manager = manager
	pod.selection = SELECTION.new()
	pod.selection.current = SELECTION.Weapon.ROCKETS
	for index in range(2):
		var hardpoint := Node3D.new()
		hardpoint.position = Vector3(0.0, 0.0, -3.0 if index == 0 else 3.0)
		pod.add_child(hardpoint)
		pod.hardpoints.append(hardpoint)
	return pod


func _ripples_rather_than_bursts() -> void:
	var pod := _build()
	var fired := 0
	pod.rocket_fired.connect(func(_r, _h) -> void: fired += 1)
	# One long frame. A burst weapon would empty the pod here.
	pod.update(1.0, true)
	if fired == 0:
		_fail("holding the trigger must launch a rocket")
	if fired > 1:
		_fail("a single update must launch one rocket, got %d" % fired)

	fired = 0
	var elapsed := 0.0
	while elapsed < POD.RIPPLE_INTERVAL * 3.5:
		pod.update(0.02, true)
		elapsed += 0.02
	if fired < 3 or fired > 4:
		_fail("expected three or four rockets in three and a half intervals, got %d" % fired)


func _alternates_hardpoints() -> void:
	var pod := _build()
	var sides: Array[int] = []
	pod.rocket_fired.connect(func(_r, hardpoint: int) -> void: sides.append(hardpoint))
	for _i in range(4):
		pod.update(POD.RIPPLE_INTERVAL + 0.001, true)
	if sides.size() < 4:
		_fail("expected four launches, got %d" % sides.size())
	for index in range(1, sides.size()):
		if sides[index] == sides[index - 1]:
			_fail("consecutive rockets must leave from opposite hardpoints")


func _empties_and_reloads() -> void:
	var pod := _build()
	for _i in range(POD.POD_CAPACITY + 2):
		pod.update(POD.RIPPLE_INTERVAL + 0.001, true)
	if pod.rockets_remaining != 0:
		_fail("the pod must empty, %d left" % pod.rockets_remaining)
	if not pod.is_reloading:
		_fail("an empty pod must start reloading on its own")
	if pod.can_fire():
		_fail("a reloading pod must refuse to fire")
	pod.update(POD.RELOAD_SECONDS + 0.1, false)
	if pod.rockets_remaining != POD.POD_CAPACITY:
		_fail("the reload must refill the pod, got %d" % pod.rockets_remaining)
	if pod.is_reloading:
		_fail("the reload must finish")


func _stays_silent_when_the_gun_is_selected() -> void:
	var pod := _build()
	pod.selection.current = SELECTION.Weapon.CANNON
	var fired := 0
	pod.rocket_fired.connect(func(_r, _h) -> void: fired += 1)
	for _i in range(5):
		pod.update(POD.RIPPLE_INTERVAL + 0.001, true)
	if fired != 0:
		_fail("rockets must not fire while the gun is selected, got %d" % fired)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/rocket_pod_test.gd 2>&1 | grep -v "^WARNING\|^Godot Engine\|at: setup2\|Telemetry"
```

Expected: FAIL — `Failed to load script ... rocket_pod.gd`.

- [ ] **Step 3: Write the pod**

Create `scripts/weapons/rocket_pod.gd`:

```gdscript
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
	# Alternate before anything can fail, so a bad hardpoint cannot pin every
	# rocket to one wing.
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/rocket_pod_test.gd 2>&1 | grep -oE "ROCKET_POD_TEST_PASS|SCRIPT ERROR.*"
```

Expected: `ROCKET_POD_TEST_PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/weapons/rocket_pod.gd tests/rocket_pod_test.gd
git commit -m "Ripple rockets off alternating hardpoints

Rockets leave one at a time, alternating sides, because emptying the pod in a
frame gives one puff of smoke and no sense of a salvo. The pod holds fourteen
and reloads itself, since there is no free face button left to ask for it."
```

---

### Task 8: Wire it into the game

Everything above is inert until the scene owns it. This is the task where it becomes playable.

**Files:**
- Modify: `scenes/main.tscn` (two new nodes)
- Modify: `scripts/main.gd` — preloads at `:1-18`, state vars near `:113`, `_wire_cannon_systems` near `:1150`, `_on_gamepad_action_pressed` near `:941`, `_bind_cannon_to` near `:260`
- Modify: `scripts/jet/jet_controller.gd` — add hardpoint creation beside `_attach_fixed_gun_mount`
- Test: manual, on device (headless cannot assert this)

**Interfaces:**
- Consumes: everything from Tasks 1-7.
- Produces: a playable build.

- [ ] **Step 1: Add the scene nodes**

In `scenes/main.tscn`, after the existing `CannonFX` node declaration (line 203), add:

```
[node name="TrailRenderer" type="MeshInstance3D" parent="."]
script = ExtResource("trail_renderer")

[node name="RocketPod" type="Node3D" parent="."]
script = ExtResource("rocket_pod")
```

Add matching `[ext_resource]` entries at the top of the file alongside the
existing ones, following the exact `type="Script"` / `uid=` / `path=` / `id=`
shape those use. If the uid is unknown, load the scene once in the editor-less
importer to have Godot fill it:

```bash
cd /root/OpenStrike && /root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --editor --quit-after 2 2>&1 | tail -3
```

- [ ] **Step 2: Give the jet its hardpoints**

In `scripts/jet/jet_controller.gd`, beside `_attach_fixed_gun_mount`, add:

```gdscript
## Two wing hardpoints, placed from the measured airframe rather than from magic
## numbers, so swapping the GLB cannot leave rockets launching out of the
## fuselage. Same reasoning as the gun muzzle above.
func _attach_hardpoints() -> void:
	if _visual == null or not _hardpoints.is_empty():
		return
	var bounds := _measure_bounds()
	if bounds.size.is_zero_approx():
		return
	var span := bounds.size.z
	for side in [-1.0, 1.0]:
		var mount := Node3D.new()
		mount.name = "Hardpoint%s" % ("Left" if side < 0.0 else "Right")
		add_child(mount)
		mount.position = _visual.transform * Vector3(
			bounds.get_center().x,
			bounds.get_center().y - bounds.size.y * 0.15,
			side * span * 0.28
		)
		_hardpoints.append(mount)


func get_hardpoints() -> Array[Node3D]:
	return _hardpoints
```

Add the backing field beside `_gun_mount`:

```gdscript
var _hardpoints: Array[Node3D] = []
```

And call `_attach_hardpoints()` from `_find_visual()`, immediately after the
existing `_attach_fixed_gun_mount()` call.

- [ ] **Step 3: Wire the systems in main.gd**

Add preloads beside the existing ones at the top of `scripts/main.gd`:

```gdscript
const TRAIL_RENDERER := preload("res://scripts/effects/trail_renderer.gd")
const ROCKET_POD := preload("res://scripts/weapons/rocket_pod.gd")
const WEAPON_SELECTION := preload("res://scripts/weapons/weapon_selection.gd")
```

Add the onready handles beside `cannon_fx`:

```gdscript
@onready var trail_renderer: MeshInstance3D = $TrailRenderer
@onready var rocket_pod: Node3D = $RocketPod
```

Add state beside `_free_look`:

```gdscript
var _weapons := WEAPON_SELECTION.new()
```

In `_wire_cannon_systems`, after the existing `cannon_fx` wiring, add:

```gdscript
	rocket_pod.projectile_manager = projectile_manager
	rocket_pod.selection = _weapons
	rocket_pod.rocket_fired.connect(_on_rocket_fired)
	rocket_pod.magazine_changed.connect(_on_magazine_changed)
	_weapons.changed.connect(_on_weapon_changed)
```

Add the handlers:

```gdscript
## Each rocket gets a trail keyed by its sequence number, which is unique for
## the life of the round and is what the manager hands back on impact.
func _on_rocket_fired(round_data: RefCounted, _hardpoint_index: int) -> void:
	trail_renderer.begin_trail(round_data.sequence)


func _on_magazine_changed(remaining: int, capacity: int) -> void:
	if _weapons.current == WEAPON_SELECTION.Weapon.ROCKETS:
		status_label.text = (
			"RELOADING" if remaining == 0 else "ROCKETS %d/%d" % [remaining, capacity]
		)


func _on_weapon_changed(weapon: int) -> void:
	status_label.text = "WEAPON: %s" % _weapons.name_of(weapon)
```

- [ ] **Step 4: Feed the trails and drive the pod**

In `_physics_process` (or whichever method already steps per-frame systems —
follow the existing call order), add:

```gdscript
	if _flying_jet:
		var gamepad := get_node_or_null("/root/GamepadInput")
		var trigger: bool = gamepad != null and gamepad.is_rockets_firing()
		rocket_pod.carrier = jet_anchor
		if rocket_pod.hardpoints.is_empty() and jet_anchor.has_method("get_hardpoints"):
			rocket_pod.hardpoints = jet_anchor.get_hardpoints()
		rocket_pod.update(delta, trigger)
	# Live rockets lay smoke wherever they are now. Shells do not: at 625 RPM
	# they would swamp the segment cap and there is nothing to see anyway.
	for round_data in projectile_manager.active_rounds:
		if round_data.weapon_source == "rocket":
			trail_renderer.push_point(round_data.sequence, round_data.position)
```

Close the trail when a rocket dies, in both existing handlers. In
`_on_projectile_impacted`, and in a new connection to `projectile_expired`:

```gdscript
	if round_data.weapon_source == "rocket":
		trail_renderer.end_trail(round_data.sequence)
```

Connect the expiry signal beside the existing impact connection in
`_wire_cannon_systems`:

```gdscript
	projectile_manager.projectile_expired.connect(_on_projectile_expired)
```

```gdscript
## A rocket that runs out of fuel and range leaves its smoke behind to fade.
func _on_projectile_expired(round_data: RefCounted) -> void:
	if round_data.weapon_source == "rocket":
		trail_renderer.end_trail(round_data.sequence)
```

- [ ] **Step 5: Route X's tap and hold**

In `_on_gamepad_action_pressed`, replace the `ACTION_SETTINGS` branch with a
`ACTION_WEAPON_CYCLE` branch that does nothing on press (the decision belongs to
the release), and connect the new release signal in `_ready`:

```gdscript
	GamepadInput.action_released.connect(_on_gamepad_action_released)
```

```gdscript
## X carries two jobs, told apart by how long it was held. The decision waits
## for the release, because until the button comes up there is no way to know
## which one the player meant.
func _on_gamepad_action_released(action: StringName, held_seconds: float) -> void:
	if action != GamepadInput.ACTION_WEAPON_CYCLE:
		return
	if GamepadInput.is_hold(held_seconds):
		_toggle_settings()
	else:
		_weapons.cycle()
```

- [ ] **Step 6: Run the whole suite**

```bash
cd /root/OpenStrike && G=/root/godot-dist/Godot_v4.7.2-stable_linux.arm64
pass=0; fail=0
for f in tests/*_test.gd; do
  if $G --headless --script "$f" 2>&1 | grep -q "_PASS"; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); echo "FAILED: $(basename $f)"
  fi
done
echo "passed $pass, failed $fail"
```

Expected: `passed 42, failed 0`.

- [ ] **Step 7: Build and verify the APK**

```bash
cd /root/OpenStrike
/root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless \
  --export-debug "Android" build/OpenStrike-rockets.apk 2>&1 | tail -5
ls -la build/OpenStrike-rockets.apk
python3 -c "
import zipfile
z = zipfile.ZipFile('build/OpenStrike-rockets.apk')
print('entries:', len(z.namelist()), 'bad:', z.testzip() or 'none')
print('signed:', b'APK Sig Block 42' in open('build/OpenStrike-rockets.apk','rb').read())
"
cp build/OpenStrike-rockets.apk /sdcard/Download/
md5sum build/OpenStrike-rockets.apk /sdcard/Download/OpenStrike-rockets.apk
```

Expected: ~133 MB, `bad: none`, `signed: True`, matching MD5s. Note that the
"No project icon specified" error and the `adb` not-found line are both
pre-existing and harmless — the first is cosmetic, the second is Godot's
one-click deploy, not the export.

- [ ] **Step 8: Commit**

```bash
git add scenes/main.tscn scripts/main.gd scripts/jet/jet_controller.gd
git commit -m "Hang rockets on the F-22 and let them smoke

Wing hardpoints measured off the airframe, the pod driven from the jet's own
frame step, and a trail begun per rocket and closed when it impacts or expires.
Only rockets lay smoke: at 625 RPM the gun would swamp the segment cap, and
there is nothing to see behind a shell anyway."
```

- [ ] **Step 9: Device verification**

Headless cannot judge any of this. On the phone, check:

1. **Does the trail read as smoke** rather than as a flat ribbon? Look at a
   salvo from side-on and from directly behind — directly behind is where the
   camera-facing maths is most likely to look wrong.
2. **Framerate under a full 14-rocket salvo**, which is the worst case this
   phase can produce. Fill rate is the expected cost, so if it drops, reduce
   `TRAIL_LIFETIME_SECONDS` first and `TRAIL_MAX_WIDTH` second — not
   `MAX_TRAIL_SEGMENTS`, which only shortens trails.
3. **The droop.** Fire at something distant and watch for the moment the motors
   quit and the rockets fall away. If it is not visible, `MOTOR_BURN_SECONDS`
   is too long.
4. **X.** A quick tap must cycle weapons and never open settings; a deliberate
   hold must open settings every time.

Record what the framerate does before starting phase 3 or 4, since both add
further trail sources on top of this budget.

---

## Self-review

**Spec coverage.** Trail renderer → Tasks 3 and 4 (split into buffer and
renderer, noted at the top). Rocket flight → Task 2. Per-round flight models and
the expiry fix → Task 1. Rocket pod with ripple, hardpoints, magazine and
automatic reload → Task 7. Weapon selection → Task 5. X tap/hold and the
`action_released` addition → Tasks 6 and 8. Data flow → Task 8. Testing table →
one test file per task, six new files, matching the spec's five plus the
buffer/renderer split.

**Type consistency.** The flight-model contract is `advance(point, velocity,
delta, age)`, `envelope_seconds()`, `envelope_metres()` — defined in Task 1,
implemented by `RocketFlight` in Task 2, consumed in Task 7. `TrailBuffer`'s
`push`/`advance_age`/`stop_emitting`/`is_finished` are defined in Task 3 and
used unchanged in Task 4. `rocket_fired(round_data, hardpoint_index)` is emitted
in Task 7 and handled with that arity in Task 8. Trails are keyed on
`round_data.sequence` in Tasks 7 and 8 alike.

**Known soft spot.** Task 8 Step 1 edits `main.tscn` by hand. Godot `uid=`
values in `[ext_resource]` lines cannot be guessed; the importer command is
given to have Godot fill them, and if that proves awkward the fallback is to
create both nodes from code in `_ready()` instead, which needs no scene edit at
all.
