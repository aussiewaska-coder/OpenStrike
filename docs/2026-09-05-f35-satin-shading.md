# F-35 satin finish and stable exterior shading

Live telemetry and a screenshot reproduced the report on the Android
Compatibility renderer in pursuit view under low afternoon sun. The existing
world sun covers 6,500 metres. A controlled comparison of shadows off, normal
mapping off, a 120-metre shadow range and changed bias isolated the mottled
patches to shadow reception: disabling the normal map left the patches, while
a short shadow range sharpened them.

The F-35 now opts into a per-instance exterior finish. Its body and closed
gear doors receive a 0.35-strength clearcoat with 0.28 coat roughness and a
0.9 multiplier on the existing roughness map. Its original colour, normal,
metalness and roughness textures remain in place. This uses Godot's material
clearcoat feature, rather than adding another shell of aircraft geometry.

The exterior no longer receives the coarse world shadow map. This trades
exterior self-shadows for stable close-range mobile shading. Direct sunlight,
ambient lighting and specular response remain active, and the aircraft still
casts shadows into the world. Global shadow settings and the city are unchanged.
This avoids a second high-resolution shadow light on the phone. The cockpit,
canopy and shared imported material are not given the body finish. F-22/F-18
materials and the F-117 camera exception remain as before.

References for material behaviour and shadow-map bias/range:
- https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html#class-basematerial3d-property-clearcoat-enabled
- https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html

The new runtime finish test failed on both exterior surfaces before the fix.
Six targeted test files passed afterward: finish/material isolation, F-35
flight/effects, all jet cockpit positions, aircraft switching/orientation,
canopy treatment and landmark materials. The real Compatibility pixel check
in tools/check_f35_finish.gd compares the original, stable matte, satin, and
satin with its shadow casters temporarily removed. The sun stays in the same
shadow-enabled rendering path throughout that comparison. Toggling the sun's
shadow_enabled property itself changes the Compatibility lighting pass and
produces a broad brightness difference, making it an invalid self-shadow test.
The final 960×540 check passed with 10,491 brighter finish pixels and only four
shadow-affected pixels (including the untreated cockpit), down from the original
visible patches. Images are saved
to /tmp/f35-finish-*.png.

Additional comparisons tried 52 m and 78 m first cascades, lower normal bias,
and disabled shadow pancaking. These sharpen some edges but don't cover the
full pursuit zoom range reliably: the camera can reach about 100 m. The targeted
material workaround is therefore deliberate, with the self-shadow tradeoff
stated above. It is not a claim that the engine's shadow renderer was repaired.
