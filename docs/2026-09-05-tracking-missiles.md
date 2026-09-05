# Target tracking and guided weapons — 2026-09-05

## Controls

- R1 acquires the contact nearest the centre of the actual camera view and
  tracks its world position. Repeated presses cycle visible members of the
  original nearby air-target cluster (14 degrees / 3.5 km), not other groups
  around or behind the aircraft.
- Tapping a target locks weapons without camera tracking. Sky taps with no
  world hit are valid and no longer dereference a null hit result.
- R3 releases tracking and recentres while retaining weapon lock. Manual
  camera movement also releases tracking. Aircraft changes, crashes and
  theatre changes clear tracking/lock.
- A + right-stick up/down now adjusts persistent jet throttle. A + right stick
  retains helicopter manual view/aim. R1 no longer modifies either input.
- X cycles cannon / rockets / heat seeker / radar missile. Hold X opens
  settings. L1 fires the selected secondary weapon; L3 remains the cannon.

## Missile behavior

Heat seekers have a 6.5 km / 55-degree acquisition envelope and a 0.45-second
acquisition delay. Radar missiles have an 18 km / 65-degree envelope and a
0.85-second acquisition delay. Both need airborne contacts and minimum 100 m
separation. The HUD reports acquisition, readiness, ammunition and reload.

Heat seekers are fire-and-forget; radar seekers require the same selected lock
throughout flight. Each shot retains its original target handle. Invalid
guidance for more than 0.65 seconds permanently loses the seeker. Neither
weapon silently retargets when the player changes locks.

Shots inherit aircraft velocity, separate before motor ignition, accelerate,
lead moving contacts and turn at bounded rates. Long-range radar shots loft
and descend toward the intercept. Motor burnout leaves a coasting projectile.
An armed proximity fuse is checked against the actual swept world hit so a
nearer obstacle still stops the shot. Four shared missiles reload in seven
seconds; each shot requires a fresh trigger press. These are gameplay-tuned
models, not validated real-world seeker/aerodynamic simulations.

## Rendering and integration

Pooled missile/rocket bodies follow their simulated velocities. Motor glow
ends at burnout; distance-sampled smoke remains, widens and fades. Soft-edged,
noise-modulated ribbons share one draw call. Gun smoke uses a soft radial
texture, growth/fade curves and sustained-fire opacity. Removed an invalid
CPUParticles3D `amount_ratio` assignment, retained billboard scale and added
larger overlapping fire/smoke bursts. Enemy jets now participate in the world
hit query and impact damage routing. HUD contact boxing follows the tracked
camera, including targets away from the aircraft's normal forward view.
Turret aim reads the live lock position rather than a stale aircraft orbit point.

## Verification

- Full headless suite: 66/66 passed; final changed targeting/effect tests also
  rerun separately.
- Moving-target interception tested for both seekers at 60 and 120 Hz;
  acquisition, held-trigger gating, guidance loss, radar loft, motor cutoff,
  destroyed targets and obstacle-before-fuse ordering covered.
- Production camera methods tested for moving targets, same-cluster cycling,
  R3 release, off-nose HUD boxing and tap-lock with a null world hit.
- Compatibility OpenGL software-rendered effect fixture inspected at
  `/tmp/openstrike-guided-weapons-v3.png`.
- Main scene ran headlessly for 1,500 frames without script errors (shutdown
  reports an existing ObjectDB leak warning).

Physical Bluetooth controls, Android GPU appearance/performance and subjective
flight feel still require an on-device flight test. The packaged APK is a
debug-signed ARM64 build, not a release-store artifact.
