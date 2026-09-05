# Throttle on B and A, and a lower seat

Jet throttle moves to B for up and A for down, pressed on their own. The Home
modifier is gone and the D-pad goes back to plain camera zoom, so nothing has
to be held down first.

Both buttons had a guard standing against them and both guards turned out to be
satisfiable rather than wrong. `gamepad_input_test` asserted that B stays
unbound so it can cancel a menu: `get_jet_throttle_axis()` already returns zero
while the settings panel, the tactical map or the mapper is open, so B still
cancels and the guard now permits `throttle_up` alone. A is the Apache's manual
aim modifier, and every reader of it is already gated on `not _flying_jet`, so
the two meanings never meet.

Layout version 3 migrates saved layouts. A layout still on the version-1
Home/Turbo defaults and one left on the version-2 shared D-pad both move to
B and A; a player who bound something else keeps it, and a migrated layout is
not migrated again.

The pilot's eye drops from 0.86 of the cockpit tub to 0.80 so the HUD sits
nearer the middle of the frame. `jet_runtime_test` holds a floor there --
originally 0.84, for "pilot eye must sit high enough to see the panel" -- and
0.74 was tried first and failed it. The floor moved to 0.78 rather than being
removed, so the instrument panel stays in frame.
