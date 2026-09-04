# Helmet HUD and targeting, phase 1: the visor, the lock, and the jets that come looking

Date: 2026-09-04. Renderer: Godot 4.7.2, GL Compatibility, Android. Branch: `look-polish`.

## Goal

Fly the F-22 as if you were wearing an F-35 pilot's helmet. Symbology is painted on the
visor, not on a fixed panel: look 40 degrees left and the horizon stays level with the real
horizon, the pitch ladder stays canted with the world, and the box around a jet stays on the
jet. Everything in front of you that matters is boxed. Press one and it becomes yours -- the
lock -- and the radar, the tapes and the guns all agree about it. And there is something up
there worth locking: squadrons of enemy Raptors that come looking for you.

## Facts the design rests on

- There is no head tracker on a phone. The helmet feel does not come from tracking the head;
  it comes from **symbology welded to the world while the view swings**. Free look already
  exists (`external_free_look.gd`, `main.gd:_free_look`), and it is the input this design
  dresses.
- `Camera3D.unproject_position` plus `is_position_behind` is the whole conformal primitive,
  and `main.gd:1082` already uses it for the single orbit-target marker. This phase turns one
  marker into a symbology system.
- The HUD is drawn, never themed: no textures, no fonts beyond the fallback, every element a
  line, an arc or a polygon. `attack_reticle.gd` and `radar_scope.gd` both say so in their
  headers, and this phase keeps that rule. It is also why the scope can be made translucent
  cheaply -- `draw_polygon` takes per-vertex colours.
- Enemy aircraft are **kinematic, not aerodynamic**. `drone.gd` states the reason and it still
  holds: ten flight models on a phone are paid for in framerate. Enemy Raptors inherit that
  decision.
- `drone_field.gd` already preloads the F-22 glb and spawns it as a visual. Enemy jets need no
  new asset pipeline.
- Player envelope, from `aero_model.gd`: corner speed 134 m/s, drag divergence 180 m/s, load
  limit 9 g, afterburner 1.10 g of thrust. Enemy jets are tuned against these numbers so a
  merge is a contest.

## What already exists, and is reused

| Thing | File | How this phase uses it |
| --- | --- | --- |
| Screen tap to a world point | `main.gd:1047-1073` | becomes the lock gesture, not just an orbit target |
| Building resolution from a ray | `building_hit_index.gd` | buildings become lockable contacts |
| Ground resolution from a ray | `ground_ray.gd` | bare ground becomes a lockable point |
| Round nose-up scope with rim chevrons | `radar_scope.gd` | upgraded, not replaced |
| SPD / AGL / HDG / throttle readouts | `attack_reticle.gd` | move to the visor as tapes |
| Drone state machine and evasion | `drone.gd` | the shape enemy Raptors are built to |
| Drone spawning, hit index, destruction | `drone_field.gd` | enemy squadrons reuse the whole path |
| SAM sites already in the world | `launcher_field.gd` | become lockable ground threats |
| Q1, Soul and Ocean towers | `hero_towers.gd` | become named lockable buildings |
| Weapon gating built for more weapons | `weapon_selection.gd` | untouched this phase; phase 2 adds the entry |

## Decisions taken in conversation

- **Conformal, not panel.** World symbols are world-anchored; only the tapes are screen-fixed.
  That split is the design, and it is what real HMDS does.
- **Two tiers of target state.** Everything trackable in view gets a thin, quiet box.
  One target at a time is locked, by pressing it, and is drawn loudly.
- **The radar is translucent and fades to its rim**, so it dissolves into the view instead of
  sitting on it as a disc.
- **Two different fades.** The scope body fades to the edge (a look); contacts fade with range
  (a claim about certainty). They are unrelated and both are in.
- **Targets come first.** Enemy Raptors are in this phase, not a later one. A radar with
  nothing on it is not worth building twice.
- **Enemy jets do not shoot back in phase 1.** They hunt, merge, and fight for position. The
  player's gun and rockets already exist and a gun kill on a manoeuvring Raptor is the fight
  worth having first. Weapons, threat warning and a player damage model are phase 3.

## Architecture

One new pure object is the seam. `TargetTracker` owns the answer to "what is out there and
which one is mine", and the visor, the radar and the weapons all read it. Nothing else holds
target state.

```
drone_field ─┐
enemy_squadron ─┤
launcher_field ─┼─→ TargetTracker ─┬─→ HelmetHud   (boxes, lock diamond, closure)
building index ─┤   (pure, tested)  ├─→ RadarScope  (blips, locked ring)
ground ray ─────┘                   └─→ cannon/rocket aim (locked point)
```

`TargetTracker` is a `RefCounted` with no node dependencies, in the same family as
`sky_state.gd`, `weather_state.gd` and `flight_math.gd`: it takes numbers, returns numbers, and
is tested headless. `HelmetHud` and `RadarScope` are `Control`s that draw what it says.

### 1. The visor (`scripts/ui/helmet_hud.gd`, new)

Replaces `attack_reticle.gd`'s glass duties. The reticle keeps the gunsight, pipper and hit
markers -- it earns those and they are already correct -- and loses the instrument block, which
becomes tapes.

**Conformal symbols.** A symbol at world point `P` draws at `camera.unproject_position(P)` and
is skipped when `camera.is_position_behind(P)`. Directions are turned into points by walking a
long way down them (`CONFORMAL_DISTANCE_M`, 50 km, comfortably inside the 30 km far plane's
projection maths since it is only ever unprojected, never rendered).

- **Horizon line.** Take the camera's forward, flatten it to the horizontal plane, normalise:
  that is `level_forward`. Project `camera_position + (level_forward ± level_right) *
  CONFORMAL_DISTANCE_M` and draw the line between the two. It cants correctly under roll and
  sits correctly under pitch for free, because it is the actual horizon.
- **Pitch ladder.** Bars every 5 degrees from -90 to +90. A bar at elevation θ is
  `level_forward` rotated by θ about `level_right`; project a far point down it, draw a bar of
  fixed screen length, canted to match the horizon's screen angle, labelled with its degrees.
  Climb bars solid; **dive bars dashed with ends turned down toward the ground**, which is what
  real ladders do and is the cheapest way to make it read as authentic.
- **Flight Path Marker.** The winged circle, at the projection of `camera_position +
  velocity.normalized() * CONFORMAL_DISTANCE_M`. Where the aircraft is actually going, which
  is not where the nose points, and is the single most convincing symbol on the visor. Parks
  at boresight below `FPM_MIN_SPEED_MPS`.
- **Boresight cross.** Small fixed cross at the projection of the nose direction.
- **Target boxes.** One thin box per tracked contact, side length falling off with range
  between `BOX_MAX_PX` and `BOX_MIN_PX`, range in metres beneath it. Capped at
  `MAX_TRACKED_BOXES` nearest contacts so a squadron plus a city does not become noise.
- **The lock.** A diamond with corner brackets, drawn at twice the weight, with range, closure
  rate in metres per second (`+` closing, `-` opening) and the contact's name or class. When
  the locked contact is off-screen, a chevron pins to the screen edge in its direction with the
  range beside it, so the lock is never simply invisible -- the same promise `radar_scope`
  already makes about rim contacts.

**Screen-fixed symbols.** Speed tape left, altitude tape right, heading tape across the top,
each a ruled strip with a boxed current value. G-load and Mach beneath the speed tape. These do
not swing with the view, and that contrast is exactly what sells the conformal symbols as
conformal.

Colour is HMDS green (`Color(0.45, 1.0, 0.6)`, already `attack_reticle.sight_colour`) with the
lock in amber (`Color(1.0, 0.72, 0.25)`, already the existing target colour). No fills, no
shadows, line width 1.0 to 2.0.

### 2. The lock (`scripts/targeting/target_tracker.gd`, new, pure)

A contact is a dictionary with a stable `handle`, a `kind`
(`AIR_JET`, `AIR_DRONE`, `GROUND_LAUNCHER`, `BUILDING`, `GROUND_POINT`), `position`,
`velocity`, and `name`. Sources push their contacts in each frame; the tracker does the rest.

- `update(contacts, camera_position, camera_basis, delta)` -- refreshes, drops the stale.
- `tracked()` -- **all-aspect**: every contact inside the current track range, nearest first.
  This is what the radar draws; a scope that only saw forward would not be a scope.
- `boxed()` -- `tracked()` narrowed to the forward cone `TRACK_CONE_DEGREES` and capped at
  `MAX_TRACKED_BOXES`. This is what the visor boxes. The visor and the scope therefore agree
  about what exists and disagree only about what is worth drawing on the glass.
- `set_range(metres)` -- the track range **follows the scope's selected range**, so cycling the
  radar out to 40 km genuinely reveals contacts rather than redrawing the same 10 km of them at
  a smaller scale.
- `lock_at(ray_origin, ray_direction, world_hit)` -- the press. Picks the tracked contact with
  the smallest angle to the ray, if that angle is under `LOCK_TOLERANCE_DEGREES`. Otherwise
  falls back to `world_hit` and locks a building or a bare ground point, which is how "press a
  building" and "press the dirt" both work through one gesture.
- `cycle_lock()` -- next tracked contact. The gamepad needs a way in; there is a controller in
  the box.
- **Lock persistence.** A lock survives leaving the forward cone. It breaks only on
  destruction, on leaving the **largest** range in `RADAR_RANGES_M`, or on being cleared --
  deliberately not the currently selected range, because zooming the scope in to 5 km must not
  throw away a lock you are holding at 8. A lock that dropped every time you manoeuvred, or
  every time you changed scale, would be worse than no lock, and real locks do not behave that
  way.
- `closure_of(handle)` -- `-(relative_velocity · line_of_sight_unit)`.

Static and headless-testable throughout, in the manner of `radar_scope.blip_offset` and
`bearing_tape.relative_bearing`.

### 3. The radar (`scripts/ui/radar_scope.gd`, upgraded)

- **Range.** `RADAR_RANGE_M` stops being a constant. Default **10 km**, cycling
  5 / 10 / 20 / 40 on press, with the current range labelled as it already is.
- **Press to cycle.** The scope currently sets `MOUSE_FILTER_IGNORE` across a full-rect
  Control, so today it can never be pressed. It moves to `MOUSE_FILTER_STOP` **and** gains a
  `_has_point()` override returning true only inside the scope circle. Both changes are needed:
  the filter lets it receive input at all, and `_has_point` confines that to the disc so every
  tap outside the scope still reaches the lock gesture underneath.
- **Translucent, fading to the rim.** The body becomes a triangle fan drawn with
  `draw_polygon`'s per-vertex colours: alpha `SCOPE_CENTRE_ALPHA` at the centre falling to zero
  at the rim. No shader, no texture, one call.
- **Accuracy fade with range.** A contact's blip alpha falls from 1.0 to `BLIP_MIN_ALPHA` as
  its range approaches the scope range, and beyond `BLIP_SOFT_FRACTION` of the range it is
  drawn as a soft ring rather than a filled dot. Deliberately no per-frame positional jitter:
  jitter that changes every frame reads as a bug, not as uncertainty.
- **The sweep.** A line rotating at `SWEEP_PERIOD_S`, drawn as a short trailing wedge, and a
  contact brightens briefly as the sweep crosses its bearing. This is the animation, and it is
  three lines of code.
- **Glyphs by kind.** Air contacts stay dots; ground threats are carets; the locked contact
  carries a ring. Rim chevrons for out-of-range contacts survive unchanged -- that behaviour is
  already right.

### 4. Enemy Raptors (`scripts/entities/enemy_jet.gd`, `scripts/entities/enemy_squadron.gd`)

Built to `drone.gd`'s shape, with a jet's numbers and an air-to-air brain.

States: `INGRESS` → `PURSUIT` → `MERGE` → `EVADE` → `EGRESS` → `DESTROYED`.

- **Spawn.** A squadron of 2 to 4, on a random bearing, at `SPAWN_RANGE_M` and between
  `SPAWN_ALTITUDE_MIN_M` and `SPAWN_ALTITUDE_MAX_M`. Formation is fixed offsets from a lead
  (line abreast at `FORMATION_SPACING_M`), which is enough to read as a formation from a
  cockpit.
- **Pursuit.** Turn to an intercept lead on the player, close at dash speed.
- **Merge.** Inside `MERGE_RANGE_M`, manoeuvre for the player's six rather than for a shot.
  With no weapons this phase, position *is* the threat, and a Raptor sliding onto your tail is
  legible without a single round being fired.
- **Evade.** Reuses `drone.gd`'s threat logic exactly -- pointed at, inside `THREAT_RANGE`,
  inside `THREAT_CONE_DEGREES` -- and breaks away, jinking on a timer so it cannot be led.
- **Egress.** After `EGRESS_SECONDS` without an advantage, extend away and despawn, so a fight
  the player refuses does not accumulate jets forever.
- Destruction, hit index registration and visual spawning all go through `drone_field.gd`'s
  existing machinery.

## Data flow

Each frame, `main.gd`:

1. gathers contacts from `drone_field`, `enemy_squadron`, `launcher_field`
2. `target_tracker.update(contacts, camera.global_position, camera.global_basis, delta)`
3. `helmet_hud.set_state(camera, velocity, target_tracker.boxed(), locked, closure, instruments)`
4. `radar_scope.set_contacts(player_position, heading, target_tracker.tracked(), locked_handle)`
5. cannon and rocket aim read `target_tracker.locked_position()` where they read
   `_orbit_target_point()` today

On a screen press, `_unhandled_input` rays as it does now, then calls
`target_tracker.lock_at(...)` with both the ray and the world hit, and keeps setting the orbit
target from the resulting lock so the camera behaviour that exists today is preserved.

## Constants to start from

| Constant | Value | Why |
| --- | --- | --- |
| `CONFORMAL_DISTANCE_M` | 50000 | far enough to read as infinity, only ever unprojected |
| `TRACK_RANGE_M` | follows the scope | 10000 at the default index; see `RADAR_RANGES_M` |
| `TRACK_CONE_DEGREES` | 60 | what a visor plausibly boxes |
| `LOCK_TOLERANCE_DEGREES` | 4 | forgiving on a phone, not so wide it grabs the wrong jet |
| `MAX_TRACKED_BOXES` | 12 | a squadron plus landmarks, not a city |
| `FPM_MIN_SPEED_MPS` | 20 | below this the velocity vector is noise |
| `PITCH_LADDER_STEP_DEGREES` | 5 | standard |
| `RADAR_RANGES_M` | [5000, 10000, 20000, 40000] | default index 1 |
| `SCOPE_CENTRE_ALPHA` | 0.45 | translucent, fading to 0 at the rim |
| `BLIP_MIN_ALPHA` | 0.35 | distant but never absent |
| `BLIP_SOFT_FRACTION` | 0.6 | beyond this a blip is a ring |
| `SWEEP_PERIOD_S` | 2.5 | slow enough to read |
| `ENEMY_CRUISE_MPS` | 200 | above the player's corner speed |
| `ENEMY_DASH_MPS` | 380 | a chase is a chase |
| `ENEMY_TURN_RATE` | 0.32 rad/s | near the player's, so the merge is a contest |
| `SPAWN_RANGE_M` | 16000 | appears on radar before it appears in the canopy |
| `SPAWN_ALTITUDE_MIN_M` / `MAX_M` | 2000 / 6000 | above the corridor, below the ceiling |
| `FORMATION_SPACING_M` | 300 | reads as a formation from a cockpit |
| `MERGE_RANGE_M` | 2500 | where pursuit becomes a knife fight |
| `SQUADRON_SIZE` | 2 to 4 | |

Every number here is a starting point to be tuned on the phone, not a result.

## Testing

Pure and headless, in the manner of `solar_position_test.gd` and `sky_state_test.gd`:

- `target_tracker_test.gd` -- tracking cone admits and rejects; nearest-angle lock selection;
  fallback to a world hit when nothing is close enough; lock persists outside the cone; lock
  breaks on destruction and on range; closure sign is positive closing and negative opening;
  `cycle_lock` wraps; `boxed()` is a subset of `tracked()`; `set_range` widens what `tracked()`
  returns.
- `helmet_projection_test.gd` -- horizon, ladder and FPM screen positions against a synthetic
  camera basis: level flight puts the horizon across the middle; 30 degrees of roll cants it 30
  degrees; a climbing velocity puts the FPM above the horizon.
- `radar_scope_test.gd` -- range cycling wraps; `_has_point` is true inside the circle and
  false outside; blip alpha falls monotonically with range; existing `blip_offset` and
  `is_on_rim` tests still pass.
- `enemy_jet_test.gd` -- state transitions on range and threat; evasion breaks away from the
  player's nose, never toward it; egress fires after the timeout.

The suite grep must look for `ERROR:` as well as `PASS`. `aero_model`, `bomb_flight`, `drone`
and `trail_buffer` print `PASS` after an assertion error on HEAD; those four are pre-existing
and not this phase's to fix.

On the device, via `tools/telemetry_cmd.py '{"screenshot": true}'`: level flight, 45 degrees of
roll, a climb, a squadron inbound on radar at each of the four ranges, a lock held through a
hard turn, and the lock chevron with the target off-screen.

## Deliberately not in this phase

- Enemy weapons, radar warning receiver, player damage. Phase 3.
- Guided missiles, air-to-air or ground. Phase 2, where `weapon_selection.gd` gains its entry.
- Head tracking. There is no hardware for it.
- Multiple simultaneous locks, and any notion of a track file that survives a break of contact.
- Looking through the airframe, the DAS trick. It is cheap and it is tempting, but it is a
  camera change, not a HUD change, and it belongs to whoever next touches `jet_camera.gd`.
