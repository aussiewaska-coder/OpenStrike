# F/A-18F Super Hornet and twin afterburners

Added the committed FA18F_RAAF_Gunmetal_GearUp.glb from origin/main to the
working aircraft set. The new build starts in the Super Hornet; the aircraft
selector retains the Raptor, Nighthawk and Apache.

The Hornet has its own game-feel flight profile, uses the existing forward
flight/control and nose-camera fixes, and keeps the asset's gear-up scene.
Two measured underwing rail positions supply the weapon mounts. Control
surfaces remain static; F-22-specific mesh splitting is not applied.

Jet effects now accept airframe-specific nozzle origins and plume radius.
Hornet nozzle centres were measured from the model's exhaust petal geometry:
(-56.35, 1.32, +/-4.93) in imported model-root units. Installed model scale
converts these to the aircraft frame, with a 0.34 m plume radius. Flame roots
remain at each nozzle as length changes. Both flames and lights respond to
spooled afterburner power and extinguish at military power or on a crash.
Raptor plume origins and control-surface behaviour remain covered by its tests.

All three Hornet textures have a 2048-pixel import limit for Android. The
original GitHub GLB is preserved unchanged.

Validation:

- Eleven test files passed: Hornet flight/effects; Raptor effects; aircraft
  cycling; runtime visuals and repeated model replacement across all jets;
  actual game startup; weapon ownership; airframe scaling; point tracking;
  F-117 gear; forward-flight controls; gun attachment.
- Neutral Hornet flight over 15 simulated seconds stayed airborne at 891.59 m
  from a 900 m launch, with forward velocity aligned to its nose.
- Identical 15-second power runs reached 174.54 m/s at military power and
  223.94 m/s in afterburner, verifying that flames accompany real extra thrust.
- Real model renders inspected at build/validation/fa18f-afterburners.png and
  fa18f-nozzle-alignment.png show both flames seated at the engine exits.

These are automated flight and rendered rig checks; on-device performance
and handling remain to be confirmed with the APK.

The final APK also includes the requested brighter lighting: AFTERNOON replaces
the old dusk label at 16.85 solar hours, exactly 45 minutes earlier, and is the
default. SUNRISE is a new appended mode at 7.15 solar hours. Existing mode IDs
remain stable. Six lighting/settings/startup tests passed, including higher sun
and brighter terrain at both preset hours in March, June, September and
December over the Gold Coast. Combined with the aircraft checks, 16 distinct
test files passed.
