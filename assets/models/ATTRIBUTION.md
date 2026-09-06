# 3D Asset Attribution

## F-22 Raptor - Fighter Jet - Free

- Creator: [bohmerang](https://sketchfab.com/bohmerang)
- Source: [Sketchfab model 508de5c48845456bb033fb267ebe1d1e](https://sketchfab.com/3d-models/f-22-raptor-fighter-jet-free-508de5c48845456bb033fb267ebe1d1e)
- License: [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)

The model and its textures are distributed under that license. OpenStrike
scales the model, stows its landing gear, and attaches gameplay components at
runtime.

## F-117 Nighthawk

- Source: Sketchfab (the glTF scene node is named `Sketchfab_model`)
- Creator: UNKNOWN -- needs filling in before release
- License: UNKNOWN -- needs filling in before release

Imported 2026-09-05. 107,757 triangles across 36 primitives and 33 materials,
with 79 separate 1024 px textures. Bounds are 16.00 x 10.43 x 2.92 m against a
real aircraft of 20.09 m long and 13.20 m span, so the model is about 0.79
scale and needs roughly 1.26 applied if it is ever flown.

## Boeing E-3A Sentry AWACS

- Source: Sketchfab (the glTF scene node is named `Sketchfab_model`)
- Creator: UNKNOWN -- needs filling in before release
- License: UNKNOWN -- needs filling in before release

Imported 2026-09-05. 58,704 triangles across 14 surfaces with 8 textures.
Bounds are 46.43 x 44.50 x 13.78 m against a real 46.61 m long, 44.42 m span
and 12.60 m high, so it is true scale and needs none applied. The landing gear
is modelled down and is not on a separate node, so an airborne one will have
its wheels out until the gear meshes are identified and hidden.

Both were imported with `compress/mode=2`. Left at Godot's default lossless
mode they would have held 421 MB and 150 MB of VRAM respectively; as ETC2 they
hold 52.7 MB and 18.7 MB. See docs/2026-09-05-dusk-lights-and-texture-memory.md
for what uncompressed textures cost this project once already.

## F-35 Lightning II

- Creator: [bohmerang](https://sketchfab.com/bohmerang)
- Source: [Sketchfab F-35 Lightning II](https://sketchfab.com/3d-models/f-35-lightning-ii-fighter-jet-free-b1ab1c0090e34b0fbfe667e706023e6d)
- License: [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)

Imported from the user's downloaded GLB, preserved in
`assets/models/f35_lightning.glb`. OpenStrike scales it, selects the gear-up
parts, clears the canopy and attaches a single engine plume at runtime.
