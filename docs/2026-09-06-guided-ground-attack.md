# Guided ground attack and weapon camera

X / Square now cycles through cannon, rockets, heat seeker, radar missile,
guided bomb, and ground missile. R1 or a screen tap selects a ground site,
building or ground point. LB / L1 releases one guided weapon per press after
acquisition. Guided weapons share the four-round rack and seven-second reload.

- Guided bombs: unpowered, 4 km maximum horizontal release range, reduced to
  2.5 times height above the target. Require at least 150 m of height, 80 m/s
  speed and a target within 45 degrees of the forward horizontal direction.
- Ground missiles: powered, 8 km horizontal launch range, at least 40 m above
  the target and a 65-degree forward cone.
- Both reject targets within 150 m horizontally and airborne targets. Slant
  limits are 5 km for bombs and 9 km for ground missiles. Acquisition takes
  0.6 seconds. The HUD reports why a shot is unavailable and shows `RELEASE
  BOMB` or `MISSILE LOCK - FIRE` when ready.

Ground weapons capture the selected coordinates at launch. Switching the
selected target or camera afterward does not retarget them. Bombs retain the
carrier's velocity and steer with finite authority; missiles add motor thrust.
Both use swept world collision, including buildings and terrain, and finite
time/distance envelopes. Ground weapons carry structural building damage.
Bombs also have a 55 m blast against ground sites, blocked by intervening walls
and ridges. Enemy drone bombs retain their existing behaviour.

## Ground clusters

Six named groups contain up to four independently targetable launchers each:
CITY NORTH/CENTRAL/SOUTH and HINTERLAND NORTH/CENTRAL/SOUTH. The large Gold
Coast/Tweed corridor uses coordinate-based placement; smaller theatres use
positions scaled to their extent. These are fictional game targets.

Placement searches for dry, reasonably level sites inside the map boundary.
Packaged building footprints are checked before their visual chunks stream in,
so targets do not depend on the player's current building-detail radius.
Invalid positions are skipped instead of forcing targets into water or buildings.
All sites have collision, ground rings, named radar/map contacts and destruction.
The current cached corridor terrain produces all 24 targets across the six groups.

## On-screen MISSILE VIEW

The button below SETTINGS arms the camera before firing, or joins the latest
guided weapon already in flight. It follows missiles and guided bombs from
behind. Toggling off or pressing R3 returns immediately. Impact is shown for
0.8 seconds, then the aircraft view returns; expiry or a missing projectile
also returns safely. The toggle remains armed after automatic return for the
next shot. Aircraft changes, theatre changes and opening the tactical map
cancel the weapon view.

A separate Camera3D leaves the aircraft camera, its tracking target and flight
controls intact. Aircraft aiming overlays are hidden while watching the weapon;
screen taps and R1 cannot accidentally select through the hidden aircraft view.
The camera stores a projectile sequence rather than a pooled round reference.

## Verification

- `guided_ground_test.gd`: release limits, acquisition, damage profile,
  captured target coordinates, bomb energy, both weapons hitting sites at
  60/120 Hz, and nearer obstacles stopping the shot.
- `projectile_camera_test.gd`: arming, launch, manual return, impact hold,
  expiry, unrelated impacts, joining a flying weapon and pooled-round reuse.
- `ground_cluster_test.gd` and `launcher_field_test.gd`: grouping, names,
  boundaries, dry ground, building exclusion, collision and destruction.
- `ground_attack_runtime_test.gd`: production button, hardpoints, camera/HUD
  handoff, bomb blast, contact retirement and R3 return.
- `tools/check_ground_sites.gd`: cached corridor elevation and packaged
  building placement audit, without network requests.
- `tools/check_ground_attack_view.gd`: phone-size captures in
  `/tmp/openstrike-ground-{ready,following,returned}.png` using a real renderer.
