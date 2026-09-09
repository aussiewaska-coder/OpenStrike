# FA18F GitHub asset assessment

Inspected `assets/models/FA18F_RAAF_Gunmetal_GearUp.glb` from `origin/main`
after commit `30c2847` became available. Git blob:
`d2f4a4413dd48aeb1cbeb1b60384e2b9229d4346`.

This is a usable static aircraft asset with simpler integration than the
bundled F-117. No game integration or device performance test was performed
as part of this assessment.

Verified directly from the GLB and a fresh Godot 4.7.2 import:

- 25,352,688 bytes, valid glTF 2.0 GLB, embedded textures, no required extensions.
- Six active mesh instances, 31,021 active triangles. The file contains 49,910
  triangles in total, including disconnected gear-down assemblies.
- Named airframe, canopy, cockpit, HUD, landingOff and rails groups.
- landingOn and landingOnLight are disconnected from the active scene.
- Imported axes already match OpenStrike: +X nose, +Y up, Z wingspan.
- Unscaled bounds: 182.862 long, 130.359 span, 40.640 high. Normalize physical
  dimensions in the airframe profile; do not use these as metres unchanged.
- Three embedded 4096 x 4096 PNG textures; prepare phone texture sizes/import
  compression before judging runtime performance.
- No animations or skins. The primary airframe is one mesh; moving flaps,
  rudders and stabilators require splitting geometry and placing hinges.

Remaining integration: airframe profile and flight tuning; scale; nose camera;
explicit weapon and exhaust mounts; model selection; orientation and switching
regressions; rendered flight and phone checks. The F-22's geometry-specific
control-surface and exhaust rig must not be applied unchanged.

Actual Godot renders:

- `build/validation/fa18f-github-top.png`
- `build/validation/fa18f-github-bottom.png`

Provenance recorded in GLB metadata: author bohmerang; source Sketchfab model
447caa975f534554a83f70f0877b73fb; license field `CC-BY-NC-SA-4.0`.
