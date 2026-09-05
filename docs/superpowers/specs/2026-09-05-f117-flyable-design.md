# F-117 Nighthawk as a second flyable jet

## Goal

Make the imported F-117 a selectable, flyable aircraft with a cockpit view and
aerodynamics of its own, without changing how the F-22 flies.

## What already exists

`jet_controller.gd` flies a jet. `aero_model.gd` supplies the aerodynamics as
285 lines of `static func` with twenty `const` coefficients baked in, all of
them the Raptor's. `flight_assist.gd`, `jet_controller.gd` and three test files
call those statics across 82 sites. `main.gd` holds a single
`const JET_SCENE := preload(...f-22...)` and a `_flying_jet` boolean that
toggles between the jet and the Apache.

The formulas themselves are generic aerodynamics -- lift slope, induced drag,
wave drag, load limit, spool. Only the coefficients are aircraft-specific.
Nothing needs new physics; the constants need an owner.

## Approach

`AeroModel` becomes instantiable, constructed from an `Airframe` profile that
carries the coefficients. Chosen over threading a profile argument through all
82 call sites, and over applying scale factors to the Raptor's curves -- the
latter cannot express "no afterburner" or a subsonic drag rise, which is most
of what distinguishes the two aircraft.

## Components

### `scripts/jet/airframe.gd` (new)

A `RefCounted` holding one aircraft's numbers, with named constructors
`Airframe.raptor()` and `Airframe.nighthawk()`. It carries both the aero
coefficients that are `const` in `aero_model.gd` today and the handling
numbers that are `@export` on `jet_controller` today, so one aircraft is
described in one place:

- Lift: `cl_slope`, `stall_alpha_degrees`, `cl_decay_degrees`,
  `post_stall_alpha_degrees`
- Drag: `cd0`, `k_induced`, `cd_wave`, `drag_divergence_mps`, `cd_stalled`,
  `cd_stall_full_degrees`
- Airframe: `aero_authority`, `side_force_coefficient`, `load_limit_g`
- Thrust: `thrust_military_g`, `thrust_afterburner_g`, `thrust_idle_g`
- Control: `control_authority_floor`, `thrust_vector_authority`,
  `maximum_roll_rate`, `maximum_pitch_rate`, `maximum_rudder_yaw_rate`,
  `control_response`
- Envelope: `minimum_display_speed`, `maximum_display_speed`,
  `service_ceiling_m`, `maximum_throttle`, `afterburner_travel`
- Rigging: `scene_path`, `reference_wingspan_m`, `hull_clearance_m`,
  `model_basis`, `cockpit_seat_fraction`, `cockpit_eye_height_fraction`,
  `cockpit_pitch_degrees`, `has_jet_effects`, `display_name`

`GRAVITY` stays a true constant in `aero_model.gd`. `corner_speed_mps` stays
derived, computed per profile from `load_limit_g`, `aero_authority` and
`cl_max`.

### `scripts/jet/aero_model.gd` (changed)

Constants become instance variables assigned from the profile in `_init`.
Every `static func` becomes an instance method; the bodies do not change.
The 82 call sites become a mechanical `AERO.` to `_aero.` rename.

`jet_controller` builds its `AeroModel` when its airframe is set and passes it
to `flight_assist`, which currently reaches for the statics directly.

### `main.gd` (changed)

`_flying_jet` keeps its meaning -- jet or helicopter. A `_jet_index` selects
which jet, and `_switch_aircraft()` cycles Raptor, Nighthawk, Apache instead of
toggling two. `JET_SCENE` is replaced by the profile's `scene_path`. The
settings AIRCRAFT button and the status line read `display_name`.

## The Nighthawk's numbers

The repo states plainly that this is game-tuned assisted flight with a
compressed speed envelope and does not claim measured F-22 handling. These
values therefore scale the Raptor's tuned numbers by the ratio between the two
real aircraft, and each one records that ratio in a comment. They are not
presented as measured F-117 coefficients.

| Quality | Raptor | Nighthawk | Basis |
|---|---|---|---|
| `thrust_military_g` | 0.55 | 0.31 | real T/W 0.47 against 0.82 |
| `thrust_afterburner_g` | 1.10 | 0.31 | the F-117 has no afterburner |
| `load_limit_g` | 9.0 | 6.0 | real airframe limits |
| `drag_divergence_mps` | 180 | 130 | Mach 0.92 flat out, no supercruise |
| `maximum_display_speed` | 260 | 200 | subsonic |
| `cl_slope` | 4.6 | 3.6 | 67.5-degree swept faceted wing |
| `maximum_roll_rate` | 1.8 | 0.9 | notably sluggish in roll |
| `thrust_vector_authority` | 0.38 | 0.0 | no vectoring nozzles |

`thrust_afterburner_g` equalling `thrust_military_g` is what makes the
afterburner inert; no separate flag is introduced. `thrust_vector_authority`
at zero makes the both-triggers gesture an airbrake only, which is already the
level-flight behaviour, so no branch is needed in the input path.

The intended feel: slow to roll, slow to accelerate, bleeding energy badly in
a turn, unable to run from anything.

## Rigging the model

**Orientation.** `_scale_to_reference()` measures `bounds.size.z` as the
wingspan. The Raptor imports X-long with its span on Z, so this works. The
F-117 imports Y-long and Z-thin -- 10.43 x 16.00 x 2.92 -- so the same code
would read 2.92 m as its wingspan and scale the aircraft roughly five times too
large. The profile therefore carries a `model_basis` applied to the visual root
before measuring, normalising every aircraft to length on X, span on Z and up
on Y, with the nose pointing the same way along X as the Raptor's does -- the
Raptor's own basis is identity, so it defines the convention. A test asserts
both aircraft satisfy it, including that the nose is forward rather than
reversed; the F-117's basis is found against that test rather than guessed
here.

**Scale.** No special case. Once oriented, `reference_wingspan_m` of 13.20
scales the F-117 correctly through the existing path.

**Cockpit.** The model has no interior. Rendering from the seat point shows the
inside of the canopy facets and the back of the exterior skin -- no seat, no
panel, no consoles. `_measure_cockpit()` looks for a node named `cockpit` and
falls back to whole-airframe bounds; the F-117's parts are all `Object_N`, so
it takes the fallback, and the seat fractions are tuned against a render. The
view is the seat point, the aircraft's own faceted canopy frame, and the
existing drawn helmet HUD, which `main.gd` already enables for jet cockpit
views. No interior is modelled.

**Canopy.** `JET_VISUALS.clarify_canopy()` matches on the node name `canopy`
and will no-op here. The canopy is identifiable by geometry instead: the part
spanning the top of the forward fuselage, 1406 triangles, bounded roughly
(-0.54, 0.56, 0.16) to (0.54, 2.24, 1.07) in model units. Selection is by
position and extent, not by that triangle count.

**Gear.** Modelled down, on unnamed nodes, as on the Sentry. The gear parts sit
below the fuselage underside and are hidden by that test. Flying with the wheels
out would be the first thing reported, and hiding them is cheap.

**Effects.** `jet_effects.gd` partitions the Raptor's trailing wing panels into
ailerons by mesh surgery and attaches exhaust plumes to its nozzles. That is
Raptor geometry. `has_jet_effects` is false for the Nighthawk, so it gets no
moving control surfaces and no plumes. Giving it its own is separate work.

## Testing

- `aero_model_test.gd` keeps every current assertion, constructing with
  `Airframe.raptor()`. This is the regression proof that the F-22's flight is
  unchanged, and it must pass before any Nighthawk value is written.
- `flight_assist_test.gd` and `jet_controls_test.gd` likewise switch to an
  instance without changing expectations.
- A new comparative test: from the same speed and stick input, the Nighthawk's
  turn radius is larger than the Raptor's, it loses more speed through the
  turn, its afterburner produces no thrust above military, and its vectoring
  authority is zero.
- A new rigging test: both profiles measure length on X and span on Z after
  `model_basis`; the F-117 scales to a 13.20 m span; its cockpit point lies
  inside the canopy bounds; its gear meshes are hidden.
- Shaders are untouched, so the headless suite is sufficient; the softpipe
  renderer is still used to eyeball the cockpit framing.

## Out of scope

New weapons or a bomber loadout. Moving control surfaces or exhaust effects for
the F-117. A modelled cockpit interior. Any change to the Apache.

## Risks

The 82-site rename is mechanical but wide; the existing tests are what keep it
honest, which is why they are converted first and must stay green throughout.
The Nighthawk's numbers are derived, not measured, and will want a device pass
to confirm the aircraft is unpleasant to fly in the intended way rather than
simply unpleasant.
