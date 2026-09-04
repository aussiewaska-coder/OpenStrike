# F-22 weapons, phase 1: trails, rockets, weapon selection

Status: design approved, not yet implemented.
Scope: phase 1 of four. Phases 2-4 are listed at the end and are out of scope here.

## What this phase delivers

Unguided rocket salvos off the F-22, thick persistent smoke behind them, and a
weapon selector on X. The trail renderer built here is the keystone: guided
missiles, the afterburner plume, wingtip vortices and damage smoke all reuse it,
which is why it is designed once and properly rather than grown per effect.

## What already exists, and is not rebuilt

Worth stating plainly, because most of the weapon chain is already here and the
temptation is to write a second one alongside it.

- `projectile_manager.gd` — fixed-step integration, round pooling, and a
  **continuous segment hit query** so a fast round cannot tunnel through a
  facade between steps. Rockets get this by joining it, not by copying it.
- `cannon_weapon.gd` — trigger edge handling, rate limiting, dispersion, and a
  `round_fired` signal the FX layer already listens to.
- `ballistics.gd` — gravity and drag integration, shared with the HUD pipper so
  the reticle and the round agree.
- `impact_fx_manager.gd`, `cannon_fx.gd` — impact and muzzle effects.
- Screen-tap targeting (`main.gd:752`) — raycasts the terrain heightfield to a
  ground point and marks it on the reticle. Phase 3's guided missiles fly at
  this, which is why they are cheap.

## Trail renderer

`scripts/effects/trail_renderer.gd`, a single `MeshInstance3D` holding one
`ImmediateMesh`.

### Why one merged mesh

Every live trail in the world is rebuilt into **one** mesh each frame, giving
one draw call and one material no matter how many rockets are up. The
alternatives were an emitter node per rocket (N draw calls, and mobile drivers
disagree about trail geometry) or pooled billboard puffs, which need hundreds of
quads per trail to stop reading as beads. Neither gets thick continuous smoke
cheaply, and this is the effect the whole phase is for.

It also matches how this codebase already works: `cannon_fx` pools plain
`MeshInstance3D` quads by hand, and the project deliberately hand-rolls
fixed-step simulation rather than using the physics server.

### Structure

A trail is a ring buffer of breadcrumbs. Each breadcrumb is a position and the
time it was laid down; nothing else is needed, because width and alpha are
functions of age rather than stored state.

```
Trail:
  points: PackedVector3Array   # ring buffer
  ages:   PackedFloat32Array
  head, count
  source_id                    # the rocket that owns it
  emitting                     # false once the motor is out or the round is dead
```

Breadcrumbs are laid by **distance travelled, not by frame**, so trail density
does not change with framerate and a hitching phone does not produce a
gap-toothed trail. `TRAIL_SEGMENT_METRES` is the spacing.

### Building the strip

Each pair of consecutive breadcrumbs becomes a camera-facing quad. The quad's
half-width is perpendicular to both the segment direction and the direction to
the camera, so the ribbon always presents its face to the viewer:

```
segment  = normalize(p[i+1] - p[i])
to_eye   = normalize(camera_position - p[i])
side     = normalize(cross(segment, to_eye)) * width(age)
```

`width(age)` grows from a tight `TRAIL_BIRTH_WIDTH` at the nozzle to
`TRAIL_MAX_WIDTH` as the smoke billows. Alpha is written per-vertex and fades to
zero at `TRAIL_LIFETIME_SECONDS`, so trails dissolve rather than vanish.

Degenerate cases: a segment shorter than a millimetre, or one seen exactly
end-on so the cross product collapses, is skipped rather than emitting a
zero-area or NaN quad.

### Material

One `StandardMaterial3D`, unshaded, `BILLBOARD_DISABLED` (the geometry already
faces the camera), alpha blended, depth-write off, no shadows, and
`cull_mode = DISABLED` so a trail is visible from both sides. Vertex colour
supplies the fade.

Depth-write off means trails do not sort against each other. Two crossing trails
will blend rather than one occluding the other. This is the normal trade for
soft smoke and is accepted deliberately.

### Budget

`MAX_TRAIL_SEGMENTS` caps the total across all trails. When the cap is reached
the oldest breadcrumbs are retired early, so the effect degrades by shortening
trails rather than by dropping frames. Starting values, to be tuned on device:

| constant | start | meaning |
|---|---|---|
| `TRAIL_SEGMENT_METRES` | 2.5 | breadcrumb spacing |
| `TRAIL_LIFETIME_SECONDS` | 4.5 | how long smoke lingers |
| `TRAIL_BIRTH_WIDTH` | 0.6 m | width at the nozzle |
| `TRAIL_MAX_WIDTH` | 7.0 m | width when fully billowed |
| `MAX_TRAIL_SEGMENTS` | 2400 | hard ceiling, all trails |

2400 segments is 9600 vertices in one draw call. That is a small mesh; the
expected cost is fill rate from overlapping translucent quads, not geometry,
which is why width and lifetime are the two knobs to pull if the device
struggles.

## Rocket flight

### Per-round flight models

`projectile_manager._advance_round` currently calls the shared `ballistics`
instance directly. It changes to call the flight model **the round carries**:

```
var stepped: Array = round_data.flight.advance(
    round_data.position, round_data.velocity, fixed_step, round_data.age
)
```

`ballistics.gd` gains the trailing `age` parameter and ignores it, so shells are
unaffected and the HUD pipper keeps solving with the same object. Rockets carry
a `rocket_flight.gd` instead.

This keeps one copy of the pooling, the fixed-step accumulator and — the part
that matters most — the continuous segment hit query. A second manager would
mean a second copy of the anti-tunnelling logic, and that is precisely the code
that must not drift.

**Expiry must move with it.** `_advance_round` currently retires a round using
`ballistics.maximum_flight_seconds` and `ballistics.maximum_range`, which are
shell numbers: a rocket judged by them would die at 4 km and 20 s regardless of
its own motor. Both bounds are read from the round's flight model alongside
`advance`, so each projectile type carries its own envelope.

The **fixed step stays global**, taken from the shared ballistics as it is now.
Two projectile types stepping on different clocks would need two accumulators
and would make the hit query's segment endpoints mean different things per type,
for no benefit at these flight durations.

### The rocket's flight model

`scripts/weapons/rocket_flight.gd`, static functions in the style of
`aero_model.gd`, with the reasoning recorded beside the constants.

Two phases:

- **Boost.** For `MOTOR_BURN_SECONDS` the motor adds thrust along the rocket's
  own heading. The rocket accelerates hard and flies fairly straight, because
  thrust dominates gravity.
- **Coast.** The motor cuts and the rocket becomes ballistic — gravity and drag
  only, the same terms `ballistics.gd` already uses.

The visible consequence, and the reason for modelling it at all: a rocket
salvoed at a distant target climbs away fast, then noticeably droops once the
motor is out. Smoke is laid during both phases but the trail is dense under
boost and thin during coast, which is what makes a salvo legible.

Launch velocity inherits the aircraft's velocity plus a small ejection impulse,
so rockets do not appear to stop dead relative to a 175 m/s aircraft.

## Rocket weapon

`scripts/weapons/rocket_pod.gd`, modelled on `cannon_weapon.gd`.

- Reads `GamepadInput.is_rockets_firing()` (L1, already bound, currently read by
  nothing).
- Fires only when the rocket weapon is selected and the jet is the active
  vehicle.
- **Ripple fire**: holding L1 launches one rocket every `RIPPLE_INTERVAL`
  seconds, alternating between left and right hardpoints, rather than emptying
  the pod in a frame. The alternation is what makes a salvo look like a salvo.
- A finite magazine (`POD_CAPACITY`). It **reloads automatically** once empty,
  after `RELOAD_SECONDS`, and firing is refused during that window. There is no
  manual reload button: the controller has no free face button left, and an
  automatic pause gives the weapon a rhythm without asking the player to manage
  it. The HUD shows rounds remaining, and RELOADING while it runs.
- Emits `rocket_fired` for the FX layer, mirroring `round_fired`.

Hardpoints are placed from the measured airframe bounds, the same way
`_attach_fixed_gun_mount` derives the muzzle, so swapping the GLB cannot leave
rockets launching from inside the fuselage.

## Weapon selection

`scripts/weapons/weapon_selection.gd` — a small enum and a cycle function, with
no knowledge of the weapons themselves:

```
enum Weapon {CANNON, ROCKETS}
```

Phase 3 adds `MISSILES` to the same enum and nothing else changes.

The selector gates which weapon responds to its trigger. The cannon keeps L3 and
rockets keep L1; selection decides which is live, so a wrong selection is
visible immediately rather than silently swallowing the trigger.

The current weapon is shown on the HUD status line.

### X, and what happens to settings

X is currently `ACTION_SETTINGS`. It becomes:

- **Tap X** — cycle weapon.
- **Hold X for `SETTINGS_HOLD_SECONDS` (0.5s)** — open settings.

This needs a release event, which the input layer does not have:
`gamepad_input._process` only emits `action_pressed` from
`Input.is_action_just_pressed`. It gains a matching `action_released` signal and
per-action hold timing, which is a small, general addition rather than a
special case for X.

The settings panel also remains reachable from the on-screen SETTINGS button,
which already exists and is always visible, so a mistimed hold never locks the
player out of settings.

## Data flow

```
L1 held ──> rocket_pod (if ROCKETS selected)
                │ acquires a pooled round, attaches rocket_flight
                ▼
        projectile_manager ── fixed step ──> rocket_flight.advance()
                │                                   │
                │ segment hit query                 │ breadcrumb every 2.5 m
                ▼                                   ▼
        impact_fx_manager                    trail_renderer
                                                    │
                                             one ImmediateMesh, one draw call
```

## Testing

Headless, in the established pattern — pure functions tested directly, and
behaviour tested by stepping the real code rather than a copy of it.

| file | asserts |
|---|---|
| `tests/trail_renderer_test.gd` | breadcrumbs spaced by distance not frames; width grows and alpha fades with age; the segment cap retires oldest first and is never exceeded; degenerate and end-on segments emit no geometry |
| `tests/rocket_flight_test.gd` | boost accelerates along heading; motor cutoff at the stated time; coast matches ballistic fall; launch velocity inherits the aircraft's |
| `tests/rocket_pod_test.gd` | ripple interval spacing; hardpoint alternation; magazine empties and reloads; nothing fires when the cannon is selected |
| `tests/weapon_selection_test.gd` | cycles and wraps; phase 3's third weapon slots in without changing the cycle |
| `tests/gamepad_input_test.gd` | tap versus hold discrimination; a tap never opens settings and a hold never cycles |

Device verification is required for the things headless cannot see: whether the
trail reads as smoke, and what the framerate does with a full salvo up. Frame
cost is measured before phases 3 and 4 add three more trail sources.

## Deliberately not in this phase

- **Guided missiles** (phase 3) — the enum and the trail are built so this is
  additive.
- **Gun juice** (phase 2) — impact spectacle, heavier tracers, lingering muzzle
  smoke, recoil and shake.
- **Afterburner plume, wingtip vortices, damage smoke** (phase 4) — all three
  are the trail renderer pointed at a different source.
- **Rocket damage and destruction.** Rockets impact and produce effects through
  the existing `impact_fx_manager`; balancing what they destroy is phase 2's
  business once there is something worth destroying them with.
