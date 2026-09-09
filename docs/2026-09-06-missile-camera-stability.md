# Missile camera stability and lock HUD

The weapon view jumped because its camera followed the latest simulation point while MissileFX displayed an interpolated point. A second discontinuity switched the camera's up axis near vertical flight. Following raw velocity also made steering changes abrupt.

## Reproduction and isolation

`tests/projectile_camera_stability_test.gd` runs the real projectile manager, MissileFX and weapon camera with alternating render/physics timing, then sweeps a missile through a vertical dive. Two baseline runs measured thousands of pixels of displacement (5,677 and 19,236 maximum) and a 90-degree orientation step. Changing only the camera's position source to match MissileFX reduced displacement to 0.026 pixels while leaving the 90-degree flip, isolating both causes.

## Change

- Model, camera and missile reticle share one clamped interpolation helper.
- Camera boom and aim use smooth angular following with bounded turn rates; the camera remains anchored to the displayed projectile so high speed cannot leave it behind.
- Up vectors are transported continuously through vertical flight. Target-aware lateral panning gives both weapon and destination context.
- Additional launches cannot take over an active weapon view. Impact pans briefly toward the hit before returning to the aircraft.
- A dedicated weapon HUD projects cyan missile brackets and a red target diamond using the weapon camera, with edge arrows for offscreen targets. Its top banner reports weapon, live lock state, target name and remaining range. Radar lock loss and destroyed contacts remove the lock indication; ground weapons explicitly report coordinate lock.

## Validation

After the fix, the timing regression measured 0.043 pixels maximum displacement and 1.528 degrees maximum orientation step during the dive. A full crossing-target pursuit kept both projectile and target onscreen for every sampled frame at 60 and 120 fps. Camera lifecycle tests cover further launches, impacts, expiry, pooled round reuse and return to the aircraft. HUD tests cover live radar/heat/coordinate state, destroyed targets, offscreen cues and impact. The production scene test checks the on-screen toggle, HUD visibility and restoration.

These are automated and software-renderer checks; physical-device feel still depends on device frame rate.
