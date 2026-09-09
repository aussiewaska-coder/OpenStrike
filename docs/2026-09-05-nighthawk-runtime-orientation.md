# Nighthawk turns sideways during the visual update

`_scale_to_reference()` installed the Nighthawk's corrective model rotation,
but `_update_visual()` reset the visual's rotation to zero on every physics
frame. Its visible nose therefore became perpendicular to the flight-model
nose. The apparent pitch/roll axes were exchanged, and the cockpit eye moved
across the aircraft. Static rigging checks never called the production visual
update and could not catch this.

The production runtime regression measured a nose-alignment dot product of
0.000 for the Nighthawk after each update, versus 1.000 for the Raptor. Software
GL renders confirmed the actual mesh started pointing forward and rotated
sideways after `_update_visual()`. Preserving the installed model rotation keeps
both aircraft at 1.000 alignment; the new render shows the Nighthawk pointing
along the flight-direction arrow after the update too.

The production `_spawn_jet()` path also replaced `HeroJet` without rebinding
the surviving controller. Its visual pointer and effects still referred to
the retired Raptor, while the new Nighthawk never received its rigging. The
regression now exercises the actual spawn path for Raptor → Nighthawk → Raptor
and failed on both replacements before the fix. `refresh_visual()` now retires
the old effects and mounts and synchronously measures/rigs the new model.
Hardpoint-array identity is preserved for weapon owners sharing the array.

The camera now reads its nose/up axes from the interpolated flight anchor.
The visual's imported axes are not aircraft axes when a corrective rotation
is required. Position still follows the displayed aircraft, and cockpit
position retains the profile's model-space seat transform.

Telemetry also labelled every fixed-wing aircraft "F-22", including the
Nighthawk. It now reports `current_aircraft_name()`. The stream reader recognises
jet telemetry by its fields and prints the real aircraft name. Closed peers
are skipped before reading command bytes; reconnecting the logger during the
startup test exposed the previous closed-socket errors.

Twelve relevant tests passed: runtime visual alignment/replacement, static rigging,
Nighthawk cockpit, Raptor effects, camera interpolation, camera motion,
tracking/manual takeover, production startup, controller-event telemetry,
aircraft weapon ownership, gun attachment and flight runtime.
The runtime regression uses actual imported aircraft through production
physics updates and also checks seat stability and camera axes. Software GL
renders were inspected before and after the fix:

- `build/validation/f117-sideways-before.png`
- `build/validation/f117-forward-after.png`

The previous flight-response and sideslip changes did not address this visual
reset. The last recorded label "F-22" cannot be used to identify which jet was
being flown. The requested swapped controls remain in the current build.

Final APK: `OpenStrike-nose-forward-2026-09-05.apk`. Android export completed;
signature, ZIP integrity, ARM64 engine and changed compiled scripts were
verified. The build daemon was stopped after packaging. Installation and
on-device flight verification remain to be done by the user.
