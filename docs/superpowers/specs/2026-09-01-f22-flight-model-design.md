# F-22 flight model

An assisted arcade flight model for a fixed-wing aircraft, flown over the same
Gold Coast theatre as the helicopter. The target is Ace Combat accessibility
with convincing weight, banking and energy loss — not DCS.

The aircraft is a second playable test bed over the existing world, which is
what proves the terrain and streaming layers carry both low-altitude rotor
combat and high-speed fixed-wing flight without a second map.

## Scope

In scope: the flight model, control mapping, camera behaviour, airframe feel
and HUD instruments.

Out of scope, deliberately: vapour effects, contrails, afterburner plume,
control-surface animation, gear and flap animation, and weapon work. Tuning a
lift/drag/thrust balance and building particle effects in the same branch makes
both harder, and the airframe GLB has no separable control surfaces to animate
regardless.

Also out of scope, and recorded here because it is a real defect this work
exposes rather than causes: `streamed_terrain.gd` sets
`near_detail_speed_limit := 45.0`, and the jet's slowest cruise is twice that.
The jet will therefore never receive near-detail imagery, and `detail_radius_m
:= 6000.0` is roughly 23 seconds of flying at top speed. Low passes will look
coarser than the helicopter's until the streaming layer is given a fixed-wing
budget.

## Aircraft

`3dassets/f-22_raptor_-_fighter_jet_-_free.glb`.

The model is exactly ten times real scale: at `scale = 0.1` the wingspan
measures 13.561 m against the real 13.56 m, and the length 18.995 m against
18.92 m. The controller derives the scale from the measured wingspan rather
than hardcoding it, so replacing the asset does not silently change the
aircraft's size.

Its axes match the Apache's: **nose `+X`, up `+Y`, right wing `+Z`**. Every
existing consumer — the cannon muzzle, the cockpit transform, the follow
camera — already assumes `+X` is forward, so none of them need changing.

Unlike the Apache, the GLB carries a cockpit interior (`canopy`, `cockpit`,
`hud`, `instrGlass`) and separate gear-up and gear-down meshes
(`landingOff`, `landingOn`). The cockpit camera therefore sits at a real pilot
station behind the HUD mesh, instead of floating ahead of the nose as the
Apache's does. The gear meshes are noted for a later branch; this one leaves
the gear-up mesh visible.

## Architecture

The split mirrors the helicopter's, because the pattern is already established
and because it keeps the entire flight model provable without running the game:

| File | Kind | Responsibility |
|---|---|---|
| `scripts/jet/aero_model.gd` | pure statics | Lift coefficient against angle of attack, drag polar, thrust spool, control authority against dynamic pressure, load-limited pitch rate |
| `scripts/jet/flight_assist.gd` | pure statics | Bank hold, angle-of-attack limiter, turn coordination, boundary turn-back |
| `scripts/jet/airframe_feel.gd` | pure statics | Buffet, high-speed vibration, post-manoeuvre oscillation |
| `scripts/jet/jet_controller.gd` | `Node3D` | Owns state, integrates forces, drives the visual |

`aero_model.gd` is to `jet_controller.gd` what `rotor_model.gd` is to
`helicopter_controller.gd`: the coefficients and their sources live in the
model, and the controller only integrates them.

### The structural difference from the helicopter

`helicopter_controller.gd` keeps only `rotation.y` on the anchor and applies
pitch and roll to the visual as decoration. The jet cannot do this. Bank has to
be real, because tilting the lift vector is the only thing that turns the
aircraft. `jet_controller.gd` therefore owns a full three-axis `Basis` on the
anchor.

## Flight model

Body axes come from the anchor basis: nose `basis.x`, up `basis.y`, right wing
`basis.z`.

```
v_body = basis.inverse() * velocity
alpha  = atan2(-v_body.y, v_body.x)              # angle of attack
beta   = atan2( v_body.z, v_body.x)              # sideslip

accel  = nose * thrust                           # spooled, never instant
       + up * lift_authority * v^2 * Cl(alpha)
       - v_hat * (Cd0 + k * Cl^2) * v^2 * drag_authority
       + Vector3.DOWN * GRAVITY
```

The aerodynamic constants are folded: `0.5 * rho * S / m` becomes a single
`lift_authority`, so the model yields acceleration directly and there is one
number to tune per axis rather than four.

### What falls out of this rather than being scripted

Turning needs no turn code. Stick left commands a roll rate, the aircraft
banks, the lift vector tilts, and its horizontal component accelerates the
aircraft into the turn. Easing the stick lets the assist hold the bank. That
chain is the difference between an aircraft and a spaceship, and it is a
consequence of the four lines above.

Three further behaviours come from single terms:

- **High-G turns bleed speed** — `k * Cl^2` is induced drag. Pulling G raises
  the lift coefficient, which raises drag quadratically.
- **Overspeed is more responsive but turns wider** — the load limiter caps
  pitch rate at `n = v * omega / g <= g_limit`, so the same stick gives a lower
  pitch rate at higher speed.
- **Low speed is mushy** — control authority scales with dynamic pressure, so
  it collapses as speed falls.

### Degraded low-speed state

There is no departure. Flight assist is always on, per the design decision.

Below roughly 110 m/s the aircraft enters a degraded state that is emergent
rather than scripted: control authority falls with `v^2`, buffet ramps up, and
lift can no longer hold the aircraft's weight, so the nose mushes and the
aircraft sinks. Recovery is to unload and let it accelerate.

The lift coefficient curve still falls off past the stall angle, so the model
can express a stall. The angle-of-attack limiter simply prevents the aircraft
reaching it. Removing the limiter is the only change a later departure model
would need.

### Speed envelope

Roughly 90 to 260 m/s, or about 175 to 500 knots on the HUD. Deliberately
compressed against the real aircraft: at true F-22 speeds the 36 km corridor is
a sixty-second dash, low-level flight is unflyable on a phone stick, and the
terrain streaming cannot stay ahead of the aircraft. At this envelope a
corridor crossing takes two to four minutes and the coastline stays readable.

## Flight assist

- **Bank holds; it does not auto-level.** With the stick centred, roll rate
  damps to zero and the bank stays where the pilot left it.
- **Pitch holds flight-path angle** with the stick centred, rather than
  snapping to the horizon.
- **Angle-of-attack limiter** caps commanded pitch rate so alpha never reaches
  the stall angle.
- **Load limiter** at 9 G.
- **Turn coordination** drives yaw toward `g * tan(bank) / v` and washes out
  sideslip. The right stick keeps free look and adds only fine yaw trim.

## Boundaries

- **Ground** — hull contact against `sample_height_world` ends the run. The
  aircraft respawns airborne at the same horizontal position, at cruise speed,
  heading preserved.
- **Corridor edge** — nothing happens inside `world_half_extent()` less the
  margin. Past it, the HUD warns and the assist applies a roll-and-yaw bias
  back toward the centre, ramping with depth past the margin. There is no wall;
  a hard clamp at 260 m/s stops the aircraft dead.
- **Ceiling** — soft. Thrust and lift degrade above roughly 6000 m rather than
  the aircraft striking a limit.

## Controls

Bindings are per-vehicle. The helicopter's mapping is untouched.

| Input | Jet | Helicopter |
|---|---|---|
| Left stick | Pitch and roll | Flight vector |
| Right stick | Free look while R1 held; fine yaw trim otherwise | Yaw and collective |
| L2 / R2 | Throttle down / up; R2 past the detent is afterburner | Camera orbit sweep |
| R1 | Free look, held | unchanged |
| L3 | Cannon | unchanged |
| L1 | Rockets | unchanged |

Throttle takes the analog triggers rather than L1/R1 because proportional
throttle and an afterburner detent need an analog axis, and because the orbit
sweep those triggers currently carry has no fixed-wing meaning. `L1` and `R1`
keep the meanings the player already learned on the helicopter.

Throttle commands a target thrust, not a speed. Airspeed is what thrust and
drag settle on.

## Camera

The existing follow camera is extended, not replaced, and the additions are
gated on the active vehicle.

- The camera's up vector lags the airframe's up. One lag constant produces both
  the horizon banking and the roll lag.
- Field of view widens with speed; trailing distance grows slightly with it.
- `airframe_feel.gd` drives buffet near high angle of attack, airframe
  vibration with dynamic pressure, and a decaying pitch oscillation after hard
  manoeuvres — applied to the visual node exactly as `airframe_motion.gd` is
  today.

## Vehicle selection

`main.tscn` gains a `JetAnchor` beside `HelicopterAnchor`. One is active at a
time and the settings panel chooses.

`main.gd` currently names `helicopter_anchor` directly in around twenty places.
Rather than a broad refactor, it gains a single `_active_vehicle` accessor that
`_focus_position`, `_update_cockpit_camera`, `_update_instruments`,
`_orbit_target_point` and the cannon wiring route through. This is the smallest
change that lets two vehicles exist; it is not an invitation to restructure
`main.gd`.

The Grumman F-14D in `3dassets/` is out of scope. The selection layer would
carry it as a third entry without further structural work.

## HUD

`attack_reticle.set_instruments` gains a fixed-wing variant showing speed in
knots, altitude, heading, throttle percentage with afterburner state, current
load factor and angle of attack. Collective has no meaning for the jet and is
dropped from that variant.

## Testing

The pure modules are tested headless, in the established `SceneTree` style.

| Test | Asserts |
|---|---|
| `tests/aero_model_test.gd` | Lift coefficient rises to the stall angle then falls; induced drag follows `Cl^2`; thrust spools monotonically toward its command; load-limited pitch rate *decreases* as speed rises; control authority follows dynamic pressure |
| `tests/flight_assist_test.gd` | Bank holds with the stick centred; the limiter never permits alpha past the stall angle; coordinated yaw equals `g * tan(bank) / v`; turn-back bias is exactly zero inside the margin and grows monotonically outside it |
| `tests/jet_controls_test.gd` | Integration: a full roll-and-pull from level flight produces a turn *and* loses speed |

There is no Godot binary on the development machine, so these are written to be
run by hand:

```
godot --headless --script tests/aero_model_test.gd
```

The curve behaviour is validated numerically in a throwaway Python harness
before being transcribed to GDScript, so the constants that ship are checked
rather than merely plausible. The harness is scratch and is not kept.
