# Cockpit helmet HUD

The pitch ladder previously used horizon reference points directly beside the
camera, at zero projection depth in level flight. When those points could not
project, the bars fell back to a horizontal screen direction, losing their bank.
Helmet instruments also drew in every camera mode.

The ladder now uses constant-elevation arcs on a sphere around the pilot. It
follows the world horizon through pitch, bank and head movement, with subtle
curvature away from the centre. Major bars have signed labels on both sides and
hooks toward the horizon; descent bars are dashed. Smaller intermediate bars,
soft peripheral fading and dark outlines reduce clutter while preserving
contrast against bright sky. The instrument rails curve gently, sit farther
inside the screen, and accompany faint visor-edge arcs.

Main's existing view-chrome update enables helmet instruments only in the F-22
and Apache cockpit views. External modes retain contact boxes and lock cues.
The flight-path marker and target cues retain their world projection.

`helmet_view_test.gd` exercises the production view switch for every jet mode
and Apache chase, orbit and cockpit modes. It checks curvature, bank response,
finite sphere directions at vertical attitudes and peripheral fading. Its
optional `--visual-out` argument renders level, banked and external fixtures
with the real Compatibility renderer for inspection.

Validation: the complete headless suite passed, 71/71 tests. Level, banked and
external fixtures were rendered and visually inspected with Compatibility.
