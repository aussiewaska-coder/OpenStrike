# Enemy return fire and lingering strike fires

The defensive-combat update supersedes the missile limits, warnings and damage
balance below; see `2026-09-06-defensive-combat.md`.

Enemy Raptors acquire a shot inside a 35-degree forward cone, between 350 m
and 6.5 km. They need 1.5 seconds of continuous acquisition and reload for nine
seconds. Existing tail pursuit, climbing breaks, descending breaks and scissors
remain active; defensive evasion interrupts acquisition. Their break direction
now follows the incoming threat. Departed and destroyed pilots stop firing.

SAM sites acquire only strictly above 500 feet (152.4 m) **above local terrain**,
inside 8.5 km. Acquisition takes 2.5 seconds, reload takes twelve seconds.
Buildings and terrain ridges block sight lines. Descending below the floor,
masking the radar or destroying its site breaks missile guidance after the
seeker's 0.65-second loss tolerance. Air missiles use independent heat seekers.
Both use the existing finite-turn, powered missile flight and swept collisions.
At most four hostile missiles fly concurrently, with a 2.2-second launch gap.

A separate hostile projectile pool prevents friendly collisions, player kill
credit, or accidental entry into the player's weapon camera. Hostile missiles
share the world smoke trail renderer and missile models. Smoke emission follows
motor burn; existing smoke fades after burnout, impact or expiry.

The red ENEMY LOCK / MISSILE INBOUND indicator remains present in aircraft and
weapon views, with a direction arrow and range to the nearest closing missile.
The pulse interval falls from 0.95 seconds at 6 km to 0.16 seconds at contact.
An original synthesized two-frequency warning tone shares that pulse clock.
Passed/receding missiles stop driving the inbound alarm. Missile hits remove
34 hull points; the third triggers the existing crash/recovery sequence and
recovery restores the hull. Combat currently follows the jet encounter mode.
Switching aircraft, losing the aircraft or loading a theatre clears threats.

Unguided and guided bombs leave sustained fire and buoyant, drifting smoke on
land and buildings. Ground missiles, rockets and destroyed SAMs also ignite
sites. Ground smoke emits for 60 seconds, buildings for 100 seconds; flames
stop at 70% of that duration and smoke already emitted fades over 14 seconds.
Building emitters are 2.6 times larger. Nearby repeated hits renew a fire.
Sixteen sites cap cost; the oldest is recycled when full. Air and water hits
do not leave ground fires. Theatre changes clear all sustained effects.

Checks: enemy_combat_test, enemy_combat_runtime_test and strike_fire_test cover
altitude boundaries, terrain masking, guidance loss, air/SAM interceptions,
60/120 Hz simulation, warning cadence/audio, damage/recovery, effect persistence
and pooling. Existing dogfight, ground-attack, missile, guided-ground, projectile
camera and trail tests cover integration. tools/check_enemy_combat.gd renders
phone-size warning and fire captures using the Compatibility renderer.

Android artifact: `build/OpenStrike-enemy-combat-2026-09-06.apk`, also copied to
`/sdcard/Download/`. APK signature and ZIP CRC verified; both copies have SHA-256
`990ea9c910734e02b4d8a47c5e59904eba4f77ff4f4e4f7ab0e5034141d003a3`.
Rendered captures are in `build/validation/enemy-combat.png` and
`build/validation/strike-fires.png`. Device flight/performance and audible tone
balance still need a phone playtest.

The engine audio cleanup moves playback off its private bus before retiring
that bus. Headless combat tests mute the unrelated engine loop (covered by the
separate audio tests) and explicitly drain warning playback before shutdown.
The final combat, ground-attack and dogfight runtime checks pass without engine
errors. Enemy-combat, sustained-fire, seeker, guided-ground, projectile-camera,
trail and audio checks also pass.
