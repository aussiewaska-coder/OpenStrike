# Air defence, phase A: the raid, the radar, and the HUD they live in

Status: design approved in conversation, not yet implemented.
Scope: phase A of two. Phase B (lock-on, camera follow, guided missile, and
lock-triggered evasion) is listed at the end and is out of scope here.
Builds on: `2026-09-02-jet-weapons-phase1-design.md` (rockets, trails, weapon
selection) — which is implemented on `jet-weapons-phase1` and unflown.

## What this phase delivers

A reason to fly. Ten drones arrive over the Gold Coast and begin attack runs on
its buildings. The player's job is to shoot them down before they bomb the
skyline. A radar scope shows where they are, a cockpit bearing tape shows which
way to turn, and a mission line counts drones left against buildings lost.

The screen is cleared to do it. Every overlay goes except the settings button;
what they showed moves into the settings panel, including an on/off for the
input-monitoring readout.

## What already exists, and is reused

- `launcher_field.gd` — spawns ground targets, owns an `EntityHitIndex`, and
  answers `query_segment` for the projectile manager. The drone field is built
  in its image. `world_hit_query.gd` is what composes the terrain, building and
  entity queries into one answer for a segment; it gains the drone field as a
  second entity source, so every projectile in the game can hit a drone with no
  new collision code.
- `entity_hit_index.gd` — AABB segment queries. Static today; phase A refreshes
  bounds per frame for movers (decision recorded below).
- `building_hit_index.gd` — per-building handles with `apply_damage(handle,
  amount)`. Bombs damage buildings through the same path shells do.
- `building_damage_system.gd` — `building_damaged` and `building_smoking`
  signals, which the mission counter listens to.
- `settings_panel.gd` — the panel that absorbs the retired overlays.
- `attack_reticle.gd` — the HUD `Control`; the radar and tape become siblings
  of it under `UI`.

## Decisions taken in conversation

- **Two phases**, this one first, because the radar needs something to show and
  evasion-on-lock needs a lock to exist.
- **Moving targets refresh their AABB every frame** in the existing
  `EntityHitIndex`, rather than getting a separate sphere index. Ten entities
  re-registering per frame costs nothing, and it keeps one collision path where
  a second would drift. This is the same argument that kept rockets inside
  `projectile_manager`.
- **Kinematic flight** for drones. Attitude is derived from the path so they
  bank into turns and look like aircraft; there is no aerodynamics. Nobody can
  tell a drone is obeying a drag polar, and ten more flight models on a phone
  would be paid for with framerate.

## The raid

### Drones

`scripts/entities/drone.gd` (one drone's state and behaviour) and
`scripts/entities/drone_field.gd` (the manager, mirroring `launcher_field`).

Ten drones spawn at the theatre edge on the seaward side, at altitude, and fly
in. The raid runs in whichever theatre is loaded; the Gold Coast is the Surfers
Paradise region, which is the packaged demo location and the one this is tuned
for. In a theatre with no buildings the drones have nothing to bomb and the
raid cannot be lost, which is acceptable rather than a case to special-case. Each has:

- a **position, velocity and heading**, integrated kinematically
- a **cruise speed** below the F-22's, so the player can always catch one, and
  a **dash speed** for evasion that is briefly above it, so a chase is a chase
- a **turn rate** cap, so they arc rather than pivot
- a **state**: `INBOUND`, `ATTACK_RUN`, `EVADING`, `EGRESS`, `DESTROYED`
- a **target building** handle, chosen when it enters `ATTACK_RUN`

Attitude for rendering is derived: nose along velocity, bank proportional to
lateral acceleration, capped.

The mesh is the **F-22 GLB the player flies, scaled down** — a mini Raptor. The
asset is already in the build, it is already an aircraft from every angle, and
it means a drone silhouette against the sky reads instantly. Each drone
instantiates `JET_SCENE`, measures its wingspan the way `jet_controller.gd`
does, and scales to `DRONE_WINGSPAN_M`, so the size is a number rather than a
guess at the GLB's native scale. Landing gear is stowed the same way. The
cockpit interior and gun mount are not attached; a drone has no pilot station.

### Attack runs

A drone in `INBOUND` flies toward the city. On reaching `ATTACK_ENTRY_RANGE`
of any building it picks a target: the **tallest building within its forward
cone**, so raids go for the skyline rather than a car park. This needs one new
accessor on `building_hit_index.gd`:

```
func buildings_near(centre: Vector2, radius: float) -> Array  # [{handle, position, height}]
```

It then flies a straight run at the target. At `BOMB_RELEASE_RANGE` it
releases a **bomb** — a projectile with a `bomb_flight.gd` model (gravity and
drag only; a bomb is a shell with no muzzle velocity) fired through the same
`projectile_manager`, so it uses the same segment hit query and hits the same
building index as everything else. On impact, `apply_damage` is called with
`BOMB_DAMAGE`, which is enough to take a building from clean to smoking in one
hit and to destroy it in two.

After release the drone enters `EGRESS`, climbs, turns seaward, and after
`EGRESS_SECONDS` re-enters `INBOUND` to pick another target. A drone that is
never shot down keeps bombing.

### Evasion, best in class

Evasion is what makes them worth chasing. A drone evades when it is
**threatened**, which in this phase means:

- the player is within `THREAT_RANGE`, **and**
- the player's nose is within `THREAT_CONE_DEGREES` of the drone, **and**
- the player is closing (range decreasing)

That is what a real drone's warning receiver would tell it, and it means the
player is evaded for *pointing at* a drone, not merely for being nearby. Phase
B adds "locked" as a fourth, stronger trigger.

When threatened, the drone:

1. **Breaks** — a hard turn at its full turn rate, **perpendicular to the
   player's approach and away from the player's turn direction**, so the player
   has to reverse. A turn toward the player is never chosen: that is a
   head-on, and the drone loses it.
2. **Dashes** — speed goes to dash for `DASH_SECONDS`.
3. **Jinks** — while evading, heading gets a random reversal every
   `JINK_INTERVAL` seconds, so a drone cannot be led with a steady deflection.
4. **Drops** — if it has altitude to spare, it trades some for speed, and it
   will go below the player, which is where a gun-armed fighter least wants to
   follow.

Evasion runs for `EVADE_SECONDS` after the threat clears, then the drone
returns to whatever it was doing. A drone on an attack run that is threatened
**aborts the run** — it does not press through the player's guns to bomb. This
is deliberate: it means a pilot who gets on a drone's tail *saves the building
without firing a shot*, and shooting it down is what stops it coming back.

### Destruction

A drone is destroyed when any projectile — shell, rocket, or in phase B
missile — hits its AABB. The impact goes through `impact_fx.spawn_explosion`,
the drone enters `DESTROYED`, its AABB is removed, and it falls under gravity
with a trail from the phase 1 renderer until it hits the ground. The mission
counter decrements.

### Mission

`scripts/entities/raid_mission.gd`, a `RefCounted` holding the loop:

- `drones_remaining`, `buildings_lost`, `buildings_hit`
- `RAID_FAILS_AT` buildings lost ends the raid as a loss
- zero drones remaining ends it as a win
- `raid_ended(won: bool)` signal
- a restart puts ten fresh drones at the edge

The HUD line reads `DRONES 7  BUILDINGS 2/5` and turns red on a loss.

## The HUD

### What is removed

Every overlay except the settings button. Concretely, from `UI`:

- The mission panel (`Margin/Panel`) with its title, status, region, privacy,
  demo and flight-mode buttons — **gone**. The status line moves into the new
  HUD; region and privacy move into settings; flight-mode and switch-aircraft
  become settings toggles.
- `GamepadDiagnostic` — **gone from the default screen**, present only when
  the settings toggle turns it on. This is the "input monitoring overlay".
- `ControllerOverlay` — **kept**, because it is not a decoration: it is the
  "connect a controller" gate and it already hides itself when one is present.

What remains on screen while flying: the attack reticle, the radar, the tape
(cockpit only), a single-line status/mission readout, and the settings button.

### Settings absorbs

Added to `settings_panel.gd`, alongside what it already has:

- Flight mode toggle (was Y)
- Switch aircraft (was B)
- Region and privacy text (was the mission panel)
- **Input monitor** on/off, driving `GamepadDiagnostic.visible`
- Restart raid

Y and B are unbound after this and reserved for phase B's lock controls.

### Radar scope

`scripts/ui/radar_scope.gd`, a `Control` drawn with `_draw()`.

A round scope, bottom-right, aircraft at centre, **nose up**. Targets are
blips whose screen position is the target's world offset from the aircraft,
rotated by minus the aircraft's heading, scaled by `RADAR_RANGE_M`. Blips
outside the range sit pinned to the rim as chevrons, so a drone is never simply
absent — it is always at least a direction.

Two range rings, the outer labelled. Blip colour by state: white inbound, amber
on an attack run, red evading, grey destroyed-and-falling. The player's own
heading is a tick at the top. Buildings do not appear; this is an air scope.

Always shown while flying, in every view.

### Bearing tape

`scripts/ui/bearing_tape.gd`, a `Control` drawn with `_draw()`.

A horizontal strip along the **bottom edge** of the cockpit view, as chosen,
marked in degrees of relative bearing and centred on the nose. It spans the
bottom-left and centre and stops short of the scope in the bottom-right corner,
so the two never overlap. Each drone is a tick on the tape at its
bearing, with the closest labelled with its range. A drone outside the tape's
±`TAPE_HALF_WIDTH_DEGREES` sits clamped at the end with an arrow. This is what
answers "which way do I turn" without looking down at the scope.

**Cockpit only.** External views have the scope alone, per the decision.

## Data flow

```
drone_field (10 drones, kinematic) ──── refresh AABB ───> entity_hit_index
        │                                                        ▲
        │ bomb release                                           │ query_segment
        ▼                                                        │
projectile_manager ── bomb_flight ── impact ──> building_hit_index.apply_damage
        │                                               │
        │ shell / rocket impact on a drone              │ building_damaged
        ▼                                               ▼
   drone DESTROYED ──────────────────────────> raid_mission ──> HUD line
                                                    │
drone positions + states ──> radar_scope, bearing_tape (draw each frame)
```

## Constants to start from

| constant | value | why |
|---|---|---|
| `DRONE_COUNT` | 10 | as asked |
| `DRONE_WINGSPAN_M` | 5.5 | about 40% of the Raptor's 13.56 — clearly smaller, still an aircraft |
| `DRONE_CRUISE_MPS` | 95 | below the F-22's 134 corner speed, so it can always be caught |
| `DRONE_DASH_MPS` | 150 | briefly above the F-22's cruise, so a chase is a chase |
| `DRONE_TURN_RATE` | 0.9 rad/s | tighter than the F-22 at speed, looser than it at corner |
| `ATTACK_ENTRY_RANGE` | 2500 m | picks a target from well outside the city |
| `BOMB_RELEASE_RANGE` | 350 m | close enough that the run is committed |
| `BOMB_DAMAGE` | 0.6 | smoking in one, destroyed in two |
| `THREAT_RANGE` | 1400 m | roughly gun-plus-rocket reach |
| `THREAT_CONE_DEGREES` | 25 | pointing at it, not merely near it |
| `DASH_SECONDS` | 4.0 | |
| `JINK_INTERVAL` | 1.6 s | shorter than the time to settle a lead |
| `EVADE_SECONDS` | 5.0 | after the threat clears |
| `EGRESS_SECONDS` | 12.0 | before it comes back for more |
| `RAID_FAILS_AT` | 5 | buildings lost |
| `RADAR_RANGE_M` | 4000 | the theatre's useful half-width |
| `TAPE_HALF_WIDTH_DEGREES` | 60 | |

## Testing

| file | asserts |
|---|---|
| `tests/drone_test.gd` | a threatened drone turns away from the player, never toward; it dashes; jinks reverse; it aborts an attack run when threatened; unthreatened it resumes |
| `tests/drone_field_test.gd` | ten spawn at the edge; AABBs follow positions frame to frame; a segment through a drone hits it; a destroyed drone is removed from the index |
| `tests/bomb_flight_test.gd` | no thrust, falls under gravity, envelope is its own |
| `tests/raid_mission_test.gd` | counts down on kill; counts up on building loss; win at zero drones; loss at the threshold; restart resets |
| `tests/radar_scope_test.gd` | blip position rotates with heading (nose-up); out-of-range blips pin to the rim; colour follows state |
| `tests/bearing_tape_test.gd` | tick position is relative bearing; out-of-tape targets clamp with direction preserved |
| `tests/building_hit_index_test.gd` (extend) | `buildings_near` returns handles inside the radius with heights |

Device verification: whether the drones read as aircraft, whether the evasion
is *fun* — a drone that is impossible to hit is as bad as one that is trivial —
and framerate with ten drones, their bombs, and up to fourteen rocket trails at
once.

## Deliberately not in this phase

- **Lock-on, camera follow, guided missile** — phase B. Y and B are freed here
  for it.
- **Lock as an evasion trigger** — phase B, alongside the lock.
- **Drones that shoot back** — you chose evasive-but-unarmed.
- **Gun juice, afterburner plume, vortices, damage smoke columns** — the
  earlier phases 2 and 4, still queued. Bombed buildings smoke through the
  *existing* `building_smoking` path only.
