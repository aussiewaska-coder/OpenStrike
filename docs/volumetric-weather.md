# Volumetric weather

CloudDeck integrates finite, world-space rounded cloud volumes, clipped against
opaque scene depth and the 1000–2600 m altitude band. Weather coverage, wind,
lighting, rain and lightning still come from the shared weather controller.

The economy default uses 48 quadratically spaced view intervals out to 8 km.
Clouds fade from 4.4 km to the range limit. Lighting is height-based, without
traced self-shadowing or fine noise erosion. No volume noise texture is generated.
Optional shadow sampling can be enabled through configure_quality or telemetry;
zero shadow samples is the default. Mobile 3D resolution remains 0.75.

Candidates are spaced 1500 m apart, with occasional empty cells, displaced centres,
varied axes and rounded profiles. Bank altitude varies gradually across the map;
each cloud has an independent altitude offset and thickness. Full cloud thickness
ranges from 240 to 736 m, within the shared altitude envelope. Wider overlapping puffs blend into banks.
The largest radius plus centre displacement remains below one cell, keeping
the four-candidate neighborhood continuous across cell boundaries. Stable per-cloud opacity switches
between thin and dense bodies, with additional small variation. Profiles have
broad soft edges, and raised crowns have been removed.

## Validation

Run tools/run_tests.sh with tests/weather_state_test.gd and
tests/weather_runtime_test.gd. tools/check_weather.gd captures the production
weather fixture using a real Compatibility renderer. The
 tools/check_volumetric_cloud_depth.gd render check verifies foreground clipping
and finite altitude extent. These checks do not measure phone FPS or establish
motion quality. Transparent objects are absent from the opaque depth texture;
precipitation and other ordinary transparent effects render after clouds.


## Cloud layers

Clear weather combines the lower 1–2.6 km cumulus banks with a translucent
cirrus sheet at 6.5 km. The cirrus sheet uses two stretched coverage-texture
samples in the sky shader, with world-space camera parallax and a horizon fade;
it is a background approximation, without volumetric immersion. When flying
above cirrus, its compositing against lower clouds is approximate.

As coverage transitions from rain to storm, selected bank cells develop a
rising body and shallow anvil, contained below 5.6 km. These reuse the existing
48-sample pass. The wider storm interval and extra density work can increase
cost, so unchanged sample count does not imply unchanged FPS. Weather immersion
and rain still use the lower bank's approximate coverage/altitude envelope.

Options → Display → Weather cycles Clear, Overcast, Rain and Storm. Time of day
is a separate control on the same page. Storm towers follow the weather transition;
there is no separate cloud-type menu. Cloud layers use a stylized economical
model, not a meteorological simulation.

The sky implementation uses Godot's camera POSITION input:
https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/sky_shader.html
