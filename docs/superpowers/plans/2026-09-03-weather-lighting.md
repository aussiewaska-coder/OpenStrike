# Weather and Lighting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The best arcade-flight sky, clouds, sea, weather and night this renderer can give, on top of the day cycle already built.

**Architecture:** One set of global shader uniforms (`os_*`) is the seam: `DayCycle` writes sun, tint, night and sky colours; `Weather` writes coverage, wind, shadow strength and wetness. A shared shader include defines the one cloud density function that the sky, the terrain (shadows) and the cloud deck all sample, so clouds, their shadows and the deck line up. Pure state modules are headless-tested; nodes stay thin; every visual claim is checked by a device screenshot through `tools/telemetry_cmd.py`.

**Tech Stack:** Godot 4.7.2 GDScript and gdshader, GL Compatibility, Android arm64.

**Spec:** `docs/superpowers/specs/2026-09-03-weather-lighting-design.md`

## Global Constraints

- GL Compatibility only: no volumetric fog, SSR, decals, GPU particles, PhysicalSky, AgX/ACES.
- Terrain stays unshaded; all its lighting is painted in its shader.
- Linear tonemap. Fog aerial perspective stays at 0.6 (1.0 bands on device). Far plane 30 km, fog density 0.0001 (device-chosen).
- Test command shape: `/root/godot-dist/Godot_v4.7.2-stable_linux.arm64 --headless --script tests/<name>_test.gd`, pass marker `<NAME>_TEST_PASS`.
- Smoke: `--headless --quit-after 300` must show no `SCRIPT ERROR` other than the pre-existing trail_renderer empty-mesh one.
- No commits from tasks unless the user asks; the working tree is the checkpoint.

---

### Task 1: Shader globals and noise textures

**Files:**
- Modify: `project.godot` (add `[shader_globals]`)
- Create: `textures/cloud_noise.tres`, `textures/water_normal.tres`
- Create: `shaders/os_clouds.gdshaderinc`

**Produces:** globals `os_cloud_noise` (sampler2D), `os_water_normal` (sampler2D), `os_cloud_wind` (vec2 m), `os_cloud_coverage`, `os_cloud_shadow`, `os_wet`, `os_night` (floats), `os_terrain_tint`, `os_sky_horizon`, `os_sun_dir`, `os_sun_color` (vec3). Include function `float os_cloud_density(vec2 world_xz)` and `float os_cloud_lit(vec2 world_xz, float density)`.

- [ ] Add to `project.godot`:
```
[shader_globals]

os_cloud_noise={"type": "sampler2D", "value": "res://assets/textures/cloud_noise.tres"}
os_water_normal={"type": "sampler2D", "value": "res://assets/textures/water_normal.tres"}
os_cloud_wind={"type": "vec2", "value": Vector2(0, 0)}
os_cloud_coverage={"type": "float", "value": 0.45}
os_cloud_shadow={"type": "float", "value": 0.35}
os_wet={"type": "float", "value": 0.0}
os_night={"type": "float", "value": 0.0}
os_terrain_tint={"type": "vec3", "value": Vector3(1, 1, 1)}
os_sky_horizon={"type": "vec3", "value": Vector3(0.78, 0.88, 0.96)}
os_sun_dir={"type": "vec3", "value": Vector3(0.5, 0.7, -0.5)}
os_sun_color={"type": "vec3", "value": Vector3(0.9, 0.88, 0.85)}
```
- [ ] Noise textures: seamless 512 px FastNoiseLite FBM, 5 octaves; the water one `as_normal_map = true`, `bump_strength = 6`.
- [ ] Include file: coverage threshold from `os_cloud_coverage`, cloud scale 6000 m, second octave at 3.1×; `os_cloud_lit` samples 400 m toward the sun and returns 0.3..1.
- [ ] Smoke run: globals resolve, no shader errors.

### Task 2: Terrain shader with tint, cloud shadows, sea and night lights

**Files:**
- Create: `shaders/terrain_imagery.gdshader`
- Modify: `scripts/terrain/streamed_terrain.gd` (chunk material creation and the four texture/uv touchpoints; remove `set_tint`/`tint`)
- Modify: `scripts/world/day_cycle.gd` (write `os_terrain_tint` global instead of calling `set_tint`)
- Modify: `scripts/main.gd` (telemetry `terrain_tint` from day cycle; `terrain_tint` knob writes the global)

**Produces:** `StreamedTerrain._set_chunk_texture(chunk, texture, uv_scale: Vector2, uv_offset: Vector2)`; chunk dict gains `"texture"`.

- [ ] Shader (unshaded, cull_disabled): uniforms `imagery`, `uv_scale`, `uv_offset`, `sea_level_m = 0.75`, `lights_density = 0.12`. Fragment: imagery × `os_terrain_tint` × `(1 - os_cloud_shadow * os_cloud_density(world.xz))`; sea where vertex world y ≤ sea level: normal from two scrolling `os_water_normal` reads (60 m and 23 m tiles), Blinn-Phong glitter with `os_sun_dir`, Fresnel toward `os_sky_horizon`; night lights: `os_night × step(1 - lights_density, hash noise) × sodium` on land only.
- [ ] Streamer: one `Shader` preload; each chunk gets a `ShaderMaterial`; helper replaces the StandardMaterial3D property writes at lines ~243, ~358, ~468, ~503.
- [ ] Smoke run; headless probe reads `detail_report` still works.

### Task 3: Sky shader

**Files:**
- Create: `shaders/atmosphere_sky.gdshader`
- Modify: `scenes/main.tscn` (Sky uses a ShaderMaterial; `process_mode = 2` incremental, `radiance_size = 1`)
- Modify: `scripts/world/day_cycle.gd` (set shader params `sky_top_color`, `sky_horizon_color`; write `os_sky_horizon`, `os_sun_dir`, `os_sun_color`, `os_night` globals)
- Modify: `scripts/main.gd` (sky knobs use `set_shader_parameter`)

- [ ] Gradient by `EYEDIR.y`; sun disc (HDR 4.0) + glow around `LIGHT0_DIRECTION`, moon-sized when `os_night > 0.5`; stars by hash when night; clouds by `os_cloud_density` at the ray's intersection with the deck altitude using `POSITION`, faded near horizon, and hidden inside the 30 km radius the deck covers when the camera is below the deck.
- [ ] Smoke run.

### Task 4: Cloud deck

**Files:**
- Create: `scripts/world/cloud_deck.gd`, `shaders/cloud_deck.gdshader`
- Modify: `scenes/main.tscn` (node `CloudDeck` child of Main, `camera_path`)

- [ ] 60 km PlaneMesh at `altitude_m = 1800`, follows camera XZ; shader unshaded, alpha = density × distance fade (20–30 km) × band fade (|camera y − altitude| < 150 m); colour lit by `os_cloud_lit` and `os_sun_color`.
- [ ] Smoke run.

### Task 5: Facades follow the world

**Files:**
- Modify: `shaders/building_facade.gdshader`

- [ ] `col *= os_terrain_tint`; `ROUGHNESS = mix(rough, 0.15, os_wet)`; wall windows: cell = floor(uv × 3), hash(cell, v_col.rgb) > 0.55 lit; `EMISSION = os_night × lit × vec3(1.0, 0.85, 0.6) × 1.2`.
- [ ] Smoke run.

### Task 6: Weather state and node, rain, lightning, settings

**Files:**
- Create: `scripts/world/weather_state.gd`, `tests/weather_state_test.gd`, `scripts/world/weather.gd`
- Modify: `scenes/main.tscn` (node `Weather`), `scripts/ui/settings_panel.gd` (WEATHER button + `weather_cycled`), `scripts/main.gd` (wire, telemetry, knob), `scripts/world/day_cycle.gd` (`sun_multiplier`, `fog_multiplier`)

- [ ] Test first: presets map to targets (CLEAR coverage < OVERCAST < STORM; RAIN wet 1); `step` moves each value toward the target and never overshoots; `lightning_delay` within 4..15.
- [ ] Node: lerps current toward target at 1/20 s, writes `os_cloud_coverage`, `os_cloud_shadow`, `os_wet`, advances `os_cloud_wind` by `wind_mps`; sets day cycle multipliers and calls `refresh()` when they change; `CPUParticles3D` rain box under the camera with `emitting = rain_rate > 0`; STORM lightning spikes sun and ambient energy for two frames.
- [ ] Settings button, telemetry fields `weather`, `cloud_coverage`, command knobs `weather`, `cloud_coverage`.

### Task 7: Glow, adjustments, lens flare

**Files:**
- Modify: `scenes/main.tscn` (glow, adjustments), `scripts/main.gd` (flare update, knobs)
- Create: `shaders/lens_flare.gdshader`, `scripts/world/lens_flare.gd`

- [ ] Environment: `glow_enabled = true`, `glow_hdr_threshold = 0.98`, `glow_intensity = 0.5`, `adjustment_enabled = true`, contrast 1.08, saturation 1.05.
- [ ] Flare: `ColorRect` full-screen, additive canvas shader with `sun_uv`, `strength`; node updates from `camera.unproject_position` each frame; zero when the sun is behind the camera or `os_night` is on.
- [ ] Smoke run, then device screenshots.

### Task 8: Device verification

- [ ] Build, copy to Downloads, and with the game running: screenshots of REAL, NOON, DUSK, NIGHT, CLEAR, OVERCAST, STORM; fps in F-22 wide view; tune with the command channel; bake final numbers into the scene and state modules.
