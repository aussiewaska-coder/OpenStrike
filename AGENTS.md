# OpenStrike — agent notes

Godot 4.7.2 (4.7.2.stable), Compatibility renderer, GDScript. Android (ARM64)
is the primary platform; Bluetooth controller required for play. Web is a
secondary target. `project.godot` + `export_presets.cfg` at root.

## Run / test

```sh
godot --editor --path .        # import in editor first
godot --path .                 # run after import
GODOT_BIN=/path/to/godot tools/run_tests.sh
```

## On-device build (this box)

This box = Debian 13 (trixie) proot on an ARM phone (`aarch64`,
`/root/OpenStrike`). Do NOT use `pkg` here (Termux-native only); use `apt`.
`gh` is preinstalled but its token has only `repo` scope (no `workflow`).

- Godot: `~/tools/godot/Godot_v4.7.2-stable_linux.arm64`
- Export templates: installed at `~/.local/share/godot/export_templates/4.7.2.stable`
- Android SDK: `/root/android-sdk` (`ANDROID_HOME`/`ANDROID_SDK_ROOT`), has
  `build-tools;34.0.0` + `platforms;android-34`
- Keystore: `/root/keystores/openstrike-release.keystore` (user/pass in
  `export_presets.cfg`, debug build signs automatically)

**CRITICAL — no on-device Gradle builds.** Android SDK `aapt2`/build-tools
are x86_64-only and cannot execute on aarch64
(`cannot execute: required file not found` → `:processStandardDebugResources`
fails, `AAPT2 daemon startup failed`). On-device APKs must use the
non-Gradle exporter:

- `export_presets.cfg`: `gradle_build/use_gradle_build=false` and REMOVE the
  `gradle_build/target_sdk="34"` line (Godot errors: target SDK can only be
  overridden with Gradle enabled).
- Trade-off: the Kotlin `android/location_plugin` is excluded, so GPS
  auto-region is unavailable — the startup splash defaults to the first
  installed theatre (was: manual Settings pick).
- `android/build/` is gitignored. Stale content causes recursive
  `android/build/src/main/assets/android/...` nesting and stray `.import`
  files under `android/build/res/` that break Gradle (`file name must end
  with .xml or .png`). If doing a Gradle export anywhere, wipe it first and
  pass `--install-android-build-template` on the export command.

```sh
mkdir -p build/android
~/tools/godot/Godot_v4.7.2-stable_linux.arm64 --headless --path . --import
~/tools/godot/Godot_v4.7.2-stable_linux.arm64 --headless --path . \
  --export-debug "Android" build/android/OpenStrike.apk
cp build/android/OpenStrike.apk /sdcard/Download/
```

Long, quiet build (10–20 min, Gradle phase logs nothing). Run in background
with a log file (`nohup ... > /tmp/godot-export.log 2>&1 &`) and poll with
`tail`; do NOT restart on silence. `adb` also cannot run here (x86_64-only).

## Numbered releases (2026-09-20 session)

- `VERSION` holds the build number. `tools/export_apk.sh [N]` bumps it (or
  uses N), stamps `version/code` + `version/name="0.1.N"` into
  `export_presets.cfg`, imports, exports `build/android/OpenStrike-vN.apk`,
  copies to `/sdcard/Download/` + `/sdcard/OpenStrike-latest.apk`.
- Map cache (`user://map_cache`) survives APK updates (same package/sig,
  rising version code). Only uninstall / Clear data / Clear map cache refetches.

## Theatres (2026-09-20: Sydney added)

- `data/regions/catalog.json` now ships Gold Coast + `au_nsw_sydney_harbour`
  (same 50 km footprint: 50000 m, 20 chunks, 1025 heightfield, NSW imagery).
- Region entry fields incl. `imagery_server` (`qld`|`nsw`), `buildings_dir`,
  spawn lat/lon/yaw. Detail chunks MUST use the region's server
  (`streamed_terrain._imagery_server`): Queensland answers HTTP 200 with a
  **solid-black frame** outside coverage — `tile_client` blank-guard treats
  uniform frames as a miss and falls back to NSW.
- OSM buildings: Overpass via `tools/sydney_map_query.overpassql` + 4×4 cell
  fetch (`/tmp/fetch_sydney.py` pattern); dense cells 504 → quarter/eighth
  splits. Merge dedupes by way id, then
  `tools/build_streamed_buildings.py --latitude -33.87 --longitude 151.20
  --world-size 36000 --chunks 24`. Sydney = ~170k buildings / 409 chunks /
  38 MB. Lakemba patch (r2c1b3/b4) was still backfilling at handoff.
- Map places: `scripts/ui/map_places.gd` (bounds-filtered, safe to extend).
- Sydney heroes are **procedural** (`scripts/entities/sydney_landmarks.gd`:
  Bridge/OperaHouse/Centrepoint, true-scale, y=0 grounded), wired via
  `"procedural": true` in `hero_towers.gd`. No GLBs exist for them.
- Test rule: unknown theatre ids return no heroes/runways (see
  `hero_towers_test.gd`, `location_selection_test.gd`).

## Landing sim (2026-09-20)

- `jet_controller.gd`: `gear_down/flaps_down` + `_damaged` jam states,
  `rolling` ground-roll state, `toggle_gear/toggle_flaps`,
  `rotation_speed_mps()`, `launch_rolling()`. Limits: gear 120 m/s, flaps
  150 m/s, sink 6 m/s, bank 15°. Gear-up/hard/banked/water contact = crash.
- Gear visuals are reversible: named parts re-show, Nighthawk rig saves +
  restores doors/wheels mesh (`nighthawk_gear.deploy`), unnamed re-show via
  recorded nodes (`jet_visuals.hide_landing_gear(..., record)`).
- Roll: thrust − friction(2) − brakes(9, both triggers), rudder steering,
  pull back past Vr to lift off.
- Runways: `scripts/world/runways.gd` (YSSY 16R/16L/07, OOL 14, real
  headings/lengths, ARP-centred). Input: `landing_gear` (default Start),
  `flaps` (unassigned, remappable). Touch GEAR/FLAPS buttons in HUD.
- Startup splash (`scripts/ui/startup_panel.gd`): theatre/hostiles/
  airborne-or-runway/START. Overlay only, tree keeps flying behind it.
  MUST be `PROCESS_MODE_ALWAYS` — boot tree is paused until a controller
  connects and INHERIT controls freeze. Splash scrolls; START pinned bottom.
  `--shot` bypasses it. Default pending = first installed region (no GPS
  plugin on-device, no demo on Android).
- Engine glow: `jet_effects` red pipe cores (idle→military) under the blue
  burner plumes; crash cuts both.

## Streaming perf (2026-09-20)

- `tile_client`: 4 HTTP lanes, blank-frame guard, `fetch_aerial_image` (no
  upload) + `fetch_aerial_mosaic` for NSW>1024 grid stitch.
- `streamed_terrain`: lookahead ranking (8 s velocity lead), tiers
  4096/2048/1024 (`far_detail_chunks=8`, radius 9 km), `max_pending_detail=8`,
  **one GPU upload per frame** via `_upload_queue`/`_drain_uploads` (the
  jitter fix). Uncompressed-device budget test allows 14×2048² px.
- Near tier below 500 m AGL (was 300). Haze halved (`fog_density`
  0.000045, aerial 0.35); building tints 0.78–0.90 + 0.85 albedo scale
  (`building_facade.gdshader`, `pick_tint`).
- Test quirk: `--script` tests cannot compile-depend on autoload-name
  scripts (`TileClient`) — use `root.get_node("TileClient")`, and
  `load()` (not `preload()`) for `streamed_terrain.gd`. New `class_name`
  files need `--import` before tests see them. `InputMap.has_action`
  guards needed for new actions in headless runs.

## GitHub builds (currently removed)

`.github/workflows/` was deleted (`6ad997e`) in favor of on-device builds.
Git history has a working x86_64 debug workflow if ever needed: `c8be358`
(preinstalled SDK + `--install-android-build-template`) and `1b86879`
(caching for Godot/templates/Gradle/imports). Pushing ANY workflow file
requires a token with `workflow` scope — the stored `gh` token lacks it, so
`git push` of workflows is rejected; use a PAT (`repo`+`workflow`) or edit
the file in the GitHub web UI. Never paste PATs in chat; revoke after use.

## Runtime debugging without adb

- Telemetry: game serves loopback JSON on `127.0.0.1:8787` (see
  `scripts/debug/telemetry_server.gd`).
  - `python3 tools/read_telemetry.py --count 20` — sticks, throttle, speed,
    bank, theatre, tiles, camera-vs-aircraft yaw.
  - `python3 tools/telemetry_cmd.py '{"screenshot": true}' --out /tmp/shot.png`
- Camera follow (`_camera_follow_enabled`, `scripts/main.gd`) turns on only
  after `streamed_terrain.load_region()` succeeds. Static camera + flying jet
  = usually no region (`theatre: none`) or mid crash-recovery.
- `IMPACT -- RECOVERING` + parked camera = normal wreck sequence after a
  crash (e.g. 90°-bank dive); respawn prints `AIRBORNE` and snaps follow.
- `STREAM UNAVAILABLE` = terrain tiles need internet for uncached areas.
- Controls: left stick pitch/roll, B/A throttle up/down (holds), D-pad
  views/zoom, RB track, R3 recenter/missile views, X hold = settings.
