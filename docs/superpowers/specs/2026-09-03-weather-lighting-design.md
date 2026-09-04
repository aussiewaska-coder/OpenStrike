# Weather and lighting — design

Date: 2026-09-03. Renderer: Godot 4.7.2, GL Compatibility, Android. Research brief with sources: https://claude.ai/code/artifact/fb6c071f-2d0c-4daf-b762-60db12bc82a1

## Goal

The best arcade-flight look this renderer can give: a real sky with sun glare and clouds, cloud shadows drifting over the map, a sea with a sun glitter path, haze that dissolves the horizon, dusk and night that change the whole picture, and weather states. Everything is shader and parameter work; no new render passes beyond glow.

## Facts the design rests on

- The terrain is an aerial photograph drawn **unshaded**. The sun never lights it. Dusk and night are painted onto it as a tint, cloud shadows as a darkening, city lights as an emissive mask. Buildings and aircraft are lit normally.
- Proven on the phone: `PhysicalSkyMaterial` renders near black (godot#84441); AgX and ACES wash the photo out. Linear tonemap plus `Adjustments` contrast is the ceiling.
- Not available: volumetric fog, SSR, decals, GPU particles (draw nothing, silently).
- Budget rule: low base cost, high scaling cost. Per-pixel sky work and full-screen passes are what hurt.

## Already built (uncommitted at time of writing)

`solar_position.gd` (real sun from theatre lat/lon + clock), `sky_state.gd` (one elevation → light curve), `day_cycle.gd` (node; REAL/NOON/DUSK/NIGHT), terrain `set_tint`, exponential fog, and a telemetry command channel with device screenshots (`tools/telemetry_cmd.py`).

## Architecture

One set of **global shader uniforms** is the seam between the sky, the ground, the buildings and the cloud deck, so every surface agrees about the same clouds, wind and night:

| global uniform | type | written by |
| --- | --- | --- |
| `os_cloud_noise` | sampler2D (seamless FBM) | project setting, static |
| `os_cloud_wind` | vec2, metres of drift | `Weather` each frame |
| `os_cloud_coverage` | float 0..1 | `Weather` (lerped preset) |
| `os_cloud_shadow` | float 0..1 | `Weather` |
| `os_night` | float 0..1 | `DayCycle` |
| `os_terrain_tint` | vec3 | `DayCycle` |
| `os_wet` | float 0..1 | `Weather` |

Scripts stay thin: `sky_state.gd` and a new pure `weather_state.gd` hold the numbers and are headless-tested; `day_cycle.gd` and `weather.gd` nodes apply them.

### 1. Horizon
Camera far to ~30 km so the 25 km corridor is never clipped; fog density chosen live on device so the terrain edge is fully hazed before the far plane; fog colour = sky horizon colour (already). Depth precision is the risk; verified by the live probe, baked into `main.tscn`.

### 2. Terrain shader (`shaders/terrain_imagery.gdshader`)
Replaces the per-chunk `StandardMaterial3D`. Unshaded. Uniforms per chunk: `imagery`, `uv_scale`, `uv_offset` (same contract the streamer uses today). Fragment:
- albedo = imagery × `os_terrain_tint`
- × cloud shadow: `1 - os_cloud_shadow * cloud(world_xz)` where `cloud()` samples `os_cloud_noise` at `(world_xz + os_cloud_wind) / cloud_scale` and applies the same coverage threshold as the sky
- **sea**: where vertex height ≤ `sea_level_m`: two scrolling normal maps from `os_cloud_noise`'s companion normal texture, Blinn-Phong glitter from the sun direction uniform, Fresnel blend to sky horizon colour. No mask, no second mesh: the elevation grid is the mask
- **night lights**: `os_night × lights_mask × sodium colour` where the mask is a high-frequency noise thresholded so it reads as scattered lights; only above sea level
Fog applies as before (unshaded materials still receive fog).

### 3. Sky shader (`shaders/atmosphere_sky.gdshader`)
`shader_type sky`, `use_half_res_pass`. Full-res pass: gradient from `sky_top/sky_horizon/ground` uniforms (fed by `sky_state`), sun disc with Mie-style glow around `LIGHT0_DIRECTION` (moon: same code, smaller and dimmer when `os_night` > 0.5), stars faded in by `os_night`. Half-res pass: cirrus (one stretched noise read, high on the dome) and cumulus (two octaves of `os_cloud_noise` projected on a dome, coverage threshold from `os_cloud_coverage`, sun-facing edge lit by `LIGHT0_COLOR`). Composite `HALF_RES_COLOR` over the gradient. `Sky.process_mode = INCREMENTAL`, `radiance_size = 64` so wind animation does not cost a cubemap per frame.

### 4. Cloud deck (`scripts/world/cloud_deck.gd` + `shaders/cloud_deck.gdshader`)
One 60 km quad at `deck_altitude_m` (default 1800) that follows the camera in XZ. Alpha from the same cumulus function, so it matches the sky's clouds and the ground's shadows. Depth-faded near intersections. `Weather` bumps fog density while the camera is inside the band. Honest limit: a flat sheet up close.

### 5. Buildings
`building_facade.gdshader` multiplies albedo by `os_terrain_tint` so walls darken with the ground, lowers roughness by `os_wet`, and at night emits warm light from a per-window hash on wall layers, scaled by `os_night`.

### 6. Glow, sun glare, lens flare
`Environment.glow_enabled`, threshold above 1.0; the sun disc is written above 1.0 so it blooms; afterburner and rocket motors already emit. Lens flare: a `CanvasItem` additive shader on a full-screen `ColorRect`, sun screen position from `Camera3D.unproject_position`, faded when the sun is behind the camera or below the horizon. No occlusion test (from the air it is rarely occluded).

### 7. Weather (`scripts/world/weather_state.gd` pure, `scripts/world/weather.gd` node)
Presets CLEAR, OVERCAST, RAIN, STORM as targets for: cloud coverage, sun energy multiplier, fog density multiplier, cloud shadow strength, wet, rain rate. The node lerps toward the target over ~20 s and writes globals. Rain: `CPUParticles3D` box parented to the camera (GPU particles are invisible here), rate from the state. Lightning: in STORM, a random 4–15 s timer spikes sun and ambient energy for two frames. Settings gets a WEATHER button; telemetry reports and the command channel sets it.

### 8. Colour
Linear tonemap. `Environment.adjustment_enabled` with contrast ~1.08 and saturation ~1.05 tuned live.

## Not in scope
Sun shafts (full-screen radial blur): last on the brief, only if frame time allows after measuring on device. Volumetric anything. SSR.

## Testing
Pure modules headless: `sky_state`, `weather_state` (preset targets, lerp monotonicity, lightning timing bounds), `solar_position`. Node wiring by the existing headless probe pattern. Every visual claim is verified by a device screenshot through `tools/telemetry_cmd.py` before it is called done; frame time from telemetry `fps` in the F-22 wide view is the budget gate.
