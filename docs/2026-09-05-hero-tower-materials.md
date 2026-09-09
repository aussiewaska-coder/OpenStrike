# Dark landmark facades

Q1, Soul and Ocean still rendered dark after the winding repair. A Compatibility
render reproduced it, and inspecting the actual imported surfaces found no
NORMAL array, metallic=1 and a dark albedo multiplier on all three models.
Their StandardMaterial3D surfaces also never consumed the city's os_night
parameter, so they could not gain lit windows when the surrounding city did.

HeroTowers now prepares the three models when populated: it supplies
area-weighted normals from the repaired mesh and a nonmetallic facade shader.
The shader retains each original texture and UV array, uses the shared night
and wetness parameters, and places emission inside the texture's window bays
(eight columns for Q1/Ocean, six for Soul, three rows in each). Roof-facing
surfaces do not emit. Original imported resources are left intact.

The earlier winding write-up overstates what the repair verified: winding
made the shell visible, but the importer did not generate lighting normals.
A solid-mesh test alone could not establish that the facade was correctly lit.

Validation:

- The new hero_tower_materials_test failed on all three original models, then
  passed with normals, retained textures/UVs and the runtime material binding.
- Five targeted tests passed: materials, corridor landmarks, hero placement,
  building mesh and lighting wiring.
- tools/check_hero_tower_render.gd renders the original models, repaired day,
  repaired night without emission, and repaired night with emission using
  Compatibility. It compares pixels inside each projected tower boundary.
  Q1/Soul/Ocean had 8835/11765/18120 brighter daytime pixels and
  1577/1865/2913 lit-window pixels respectively. All three passed.

Run the pixel check with a graphics display, for example:

```sh
GALLIUM_DRIVER=softpipe LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a \
  "$GODOT_BIN" --audio-driver Dummy --path . \
  --rendering-method gl_compatibility --script tools/check_hero_tower_render.gd
```

Images are saved as /tmp/towers-{baseline,fixed-day,fixed-night-unlit,fixed-night}.png.
The repaired APK still needs the player's final device look after installation.
