# Camera feedback — 2026-09-05

External pursuit and tracking views now smooth orbit direction separately from
radius, relative to the displayed aircraft position. World-position smoothing
previously added aircraft travel to the camera offset and cut inside the sphere
during turns. At constant speed and zoom, the production camera regression
measured pursuit distance varying from 4.738 to 46.528 m. It now holds 25.443 m;
track view holds approximately 95.090 m.

Both views aim at the aircraft centre throughout the orbit. Pitch input follows
the flight heading. Terrain clearance lifts the camera along the sphere where
possible; clearance takes priority when the entire sphere is too low. Speed and
explicit zoom continue to set the desired radius.

Sideways cockpit glances add up to six degrees of neck roll. Target tracking
uses the pilot's airframe reference and the same tilt without moving the target
off the viewing axis. An overhead target retains a stable orientation without
accumulating roll.

R3 now returns the view forward over 0.85 seconds, easing into and out of the
turn. Releasing tracking begins from the displayed camera orientation rather
than snapping to the stored manual look angle. New manual look takes over the
return; repeated R3 presses during the turn do not trigger aircraft recovery.
Changing jet views stops camera tracking and clears the previous look angle,
so returning to FPV looks straight ahead while weapon lock remains selected.

Lethal impacts remove the contact from the tracker immediately, releasing its
camera and weapon lock before another update can use the last live snapshot.
The production impact regression fails without that removal and passes with it.

Validation: 11 relevant camera, targeting, destruction, squadron and missile
tests passed. The camera motion and tracking tests also passed after the final
overhead-orientation adjustment. Motion coverage includes moving/stationary
aircraft, yaw wrap, diagonal pitch sweeps, terrain clearance, cockpit bank and
tracking accuracy. Physical controller feel and Android rendering still need an
on-device flight test.

After the R3 return and view-switch fixes, the complete headless suite passed:
68/68 tests. The camera regression also checks release from target tracking,
repeat R3 presses, manual takeover and both directions of view cycling.
