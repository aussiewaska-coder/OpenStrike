# High-G wing condensation

Player jets and manoeuvring enemy Raptors now have soft wing condensation and paired wingtip vortex trails. Visibility follows speed, positive load and angle of attack, with smooth onset and release. The enemy flight model is kinematic, so its change in velocity supplies a visual load estimate. This is a game-scale effect; the moisture factor is currently a fixed artistic setting, not a simulated humidity measurement.

The emitters are measured from the installed, visible aircraft geometry, including the Nighthawk's different model orientation. Curved, noise-shaded sheets sit over each wing. The wake retains its world-space birth positions and rolls outward, drifts downward, expands and fades over four seconds. The two sides curl in opposite directions. New emission stops when the aircraft unloads, slows or crashes. Launch/respawn clears history and large position discontinuities cannot create map-spanning streaks.

Only the effect consumes the interpolated display pose: aircraft attitude, camera and flight physics are untouched. Each aircraft has two wing-sheet draws and a single trail draw. Both trails sample at 30 Hz, retain at most 128 points each and have bounded catch-up after frame hitches. Pausing or disabling the aircraft pauses its effect; removing a jet also removes its rig.

Validation: demand gates, 30/60/120 fps density, fixed history limits, drift/curl, release expiry, teleport reset, rigid aircraft pose, all four actual aircraft meshes, enemy turns and destruction cleanup. Existing effects, enemy squadron, aircraft-cycle and jet-audio runtime tests pass. Software-rendered F-35 and F-117 checks confirm the wing placement and tip attachment.

Render checks: `tools/check_wing_vapor.gd`, optionally with `-- --f117`.
