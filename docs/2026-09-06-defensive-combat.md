# Forgiving missile combat and defensive controls

The initial combat build allowed four missiles, gave little time to recover,
and used the player's powerful seekers against the player. Fatal damage also
zeroed aircraft velocity while leaving the cockpit camera in place. A production
hit replay reproduced the frozen aircraft and unchanged camera.

Hostile attacks now allow one missile at a time. Spawn, aircraft changes and
recovery give twenty seconds without acquisition, followed by a full acquisition
period. After a missile impacts or expires there is a ten-second breather before
another acquisition begins. Aircraft acquire for four seconds without afterburner
(2.5 seconds at full reheat); SAM acquisition is longer for stealth jets. One hit
removes 25 hull points, leaving the aircraft flyable after three hits.

Relative arcade radar/heat signatures are assigned to the F-22, F-35, F-117 and
Super Hornet. Stealth reduces SAM acquisition range and extends acquisition time.
Fast flight across a radar's line of sight can break a weak radar return; terrain
masking and the existing strict 500 ft AGL SAM floor still apply. These are game
balance values, not real aircraft radar-cross-section data. Afterburner increases
heat acquisition range and seeker attraction. The F-117 has no reheat bonus.

Hostile missiles have their own 5.5 g turn limit, 45-degree seeker cone, 650 m/s
speed cap, 16-second flight envelope, smaller fuse and shorter lead prediction.
The player's missile defaults are preserved. A timed break can cause a real
trajectory miss or loss of seeker contact; the evasion test compares the same
straight and turning flights at 60 and 120 Hz.

The on-screen COUNTERMEASURES button deploys six visible flare/chaff decoys from
one charge. Eight charges, a 2.5-second salvo cooldown and one replenished charge
every ten seconds keep it usable. Heat seekers compare decoy attraction with the
player's heat/aspect: cutting afterburner helps a flare win. Chaff can seduce a
radar seeker against a weak/stealth return or while beaming. Decoy acquisition
takes time; it does not delete missiles. A missile hitting a decoy cannot damage
the player. A fresh salvo should be used as the missile closes, with a break turn.

R3 opens an aircraft-relative view of the nearest incoming missile. Repeated
presses move through the captured nearest-first sequence, then return to the
original aircraft camera. With one missile, the second press returns. Expiry or
impact returns automatically. Flight controls and the player's target lock are
preserved. Without incoming missiles the existing R3 behavior remains available.
The player's weapon camera, settings and tactical map coordinate with this view.

Warnings sit at bottom center. Visible missile brackets follow the actual 3D
camera projection and grow with proximity. Offscreen arrows have shaded faces,
altitude-sensitive screen placement, range, and a BEHIND label for rear threats.
Hit feedback includes an orange flash and an explosion at the aircraft. Fatal
hits switch to an external view of a rolling, falling, burning aircraft for four
seconds before recovery. R3 cannot cancel that destruction view into a frozen
cockpit. Recovery clears the wreck effect and restores countermeasures and grace.

Verification: enemy_combat_test, missile_evasion_test, threat_view_test and the
production enemy_combat_runtime_test cover timing, limits, seekers, decoys,
stealth, afterburner, trajectories, camera cycling, screen layout, hit/recovery
and the on-screen button. Existing player missile, projectile camera, aircraft,
dogfight, ground-strike and sustained-fire checks cover regressions.
`tools/check_defensive_combat.gd` captures the HUD, incoming view and hit effects
using the actual scene on the Compatibility renderer.

Android build: `build/OpenStrike-defensive-combat-2026-09-06.apk`, copied to `/sdcard/Download/` after APK signature and CRC verification. SHA-256: `5710afd9161908b10cb3350b8e72108785c46e3117272cc6517a13661ab6d253`.

Software-rendered captures: `build/validation/defensive-combat.png`, `incoming-view.png` and `hit-explosion.png`. Device flight feel and audio balance still need a phone playtest.
