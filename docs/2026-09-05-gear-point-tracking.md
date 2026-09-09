# F-117 gear stow and controller point tracking

The height-only gear filter hid three low meshes but left the struts and two
wheels visible. The two wheels share Object_30 with cockpit glass, so hiding
that whole material group would also remove the glass. The bundled F-117 now
has a dedicated rig, selected through Airframe.landing_gear_rig. It hides the
gear-only meshes, removes wheel triangles from a private copy of Object_30,
and rotates the three hanging doors inward around their upper edges.

The visual bounds helper now combines transforms before applying the AABB,
so a rotated aircraft does not inflate its local bounds.

R1/track-target starts a contact lock only when a visible contact is within
4 degrees of the centre ray. Existing airborne-cluster cycling is preserved.
When no contact is selected, the same action pins the ray's terrain, water or
building intersection and tracks it. A ray into empty sky pins a fixed world
point 5 km ahead. Point locks use the existing fallback contact, HUD and weapon
lock state; they survive contact refreshes. A later selection can acquire an
actual aircraft, and R3 releases view tracking while retaining the lock.
Screen taps retain their existing weapon-lock behaviour.

Validation:

- New production gear and point-tracking tests both failed before the fix.
- Gear test verifies actual rendered triangle heights at level and rotated
  attitudes, preserved cockpit glass, and an unchanged imported scene.
  Lowest visible geometry is now the belly at -0.726 m, rather than wheels at
  -2.158 m. Object_30 retains 1,540 glass/detail triangles.
- Point test invokes the real gamepad action and verifies terrain intersection,
  a fixed position while moving, camera convergence, R3 release, peripheral
  contact rejection, sky fallback, subsequent bogie acquisition and buildings.
- Thirteen relevant test files pass, including aircraft replacement, rigging,
  target clusters, destruction, manual tracking handoff and forward flight.
- Before/after renders of the real GLB are in
  build/validation/f117-gear-before.png and f117-gear-after.png.
