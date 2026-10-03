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

## High-resolution map sources (2026-10-01 session)

- `tile_client` imagery sources: `qld`/`nsw` (gov ArcGIS bbox exports) and
  `mapbox` (Satellite XYZ tiles). Mapbox URL must be `/z/x/y@2x.png` — the
  retina suffix leads the extension; `.png@2x` is a 404. Tiles arrive as JPEG
  bytes whatever the extension says, so they decode through `_decode_image`.
- Mapbox tiles are Web Mercator but the mesh UVs are linear lat/lon, so
  `fetch_mapbox_image` resamples the mosaic (`_resample_mercator_to_latlon`).
  `Image.set_data()` is a silent no-op in this engine build — write pixels
  with `set_pixel`.
- Zoom is chosen per request by `mapbox_zoom_for`: the sharpest zoom whose
  512 px grid fits the requested pixel size (2.5 km chunk: z15 at 2048 px,
  z16 at 4096). `MAPBOX_MAX_ZOOM = 17` (~0.6 m/px at -28°); deeper zooms only
  return upscaled pixels and many times the tiles.
- Token resolution order: `user://secrets.cfg [mapbox]token` (written by
  nothing yet — Settings shows the hint), `OPENSTRIKE_MAPBOX_TOKEN`,
  `user://mapbox_token.txt`, `/root/.mapbox_token`,
  `/storage/emulated/0/Download/.mapbox_token`. NEVER commit or export a
  token; `grep -rl "pk\.eyJ" --exclude-dir=.git .` must stay empty.
- Device-level override lives in `user://map_settings.cfg`
  (`[imagery] server=auto|gov|mapbox`), cycled from Settings → Storage; the
  catalog stays on gov sources so a repo checkout needs no token.
- Elevation: catalog `elevation_server` = `terrarium` | `skadi` (Copernicus
  GLO-30 degree `.hgt.gz`, int16 BE 3601², cached raw as `skadi_*.hgt`).
  Heightfield cache names carry the server suffix, so switching servers
  refetches the grid once.
- `precache_region(region, px)` walks the same chunk requests the terrain makes
  in flight (Settings → Storage → PRE-DOWNLOAD, with estimate + cancel). It must
  read every region key the same way `streamed_terrain.load_region` does — the
  heightfield cache name includes `elevation_server`, so a pre-download that
  defaults the server while the theatre asks for `skadi` fills a cache the game
  never reads.
- Building heights: `tools/backfill_building_heights.py` raises DEFAULT-height
  records only (≤18.5 m), needs ≥14 m relief on flat ground (≤8 m ring spread),
  ≥250 m² footprint on the 30 m grid; writes `"height_source": "dem"`. Pass
  `--dsm roof.asc` (state LiDAR via `gdal_translate -of AAIGrid`) for real
  per-building heights. Gold Coast +180 m max; Surfers towers already carry OSM
  tags.

## On-screen thumb sticks (2026-10-01)

- `scripts/ui/thumb_stick.gd` + `thumb_controls.gd`: left stick pitches and
  rolls, right stick looks, `THROTTLE +/−` are held at the bottom centre. The
  base jumps to wherever the thumb lands, and the grab is held in `_input`, not
  `_gui_input`, so a finger that slides off the corner keeps steering. Every
  claimed event must be consumed: `main.gd:_unhandled_input` locks a ground
  target on any press, which would otherwise fire under every drag.
- Thumb vectors enter at the `GamepadInput` getters, never at the controllers.
  The bigger deflection of pad-vs-stick wins, so a controller in use is not
  fought over by a stray thumb. Anything reading sticks asks
  `has_flight_input()` — `is_controller_ready()` is false on a phone with no
  pad, which is the exact case the sticks exist for.
- `set_thumb_controls(true)` clears the boot pause Android applies while waiting
  for a pad (see `_clear_controller` and `requires_controller_attention`).
  `main.gd` must call it before the attention check in `_ready`.
- A stick applies its own 0.14 dead zone, then `GamepadInput` applies the
  shared 0.18 one. Do not add a third.
- Persisted at `user://ui_settings.cfg` `[controls] thumb_sticks`; with no
  entry it follows `DisplayServer.is_touchscreen_available()`. Toggle:
  Settings → Display → HUD → "Thumb controls".
- Headless tests: `root.push_input(InputEventScreenTouch…)` does NOT reach a
  node's `_input` — the display server emits its own synthetic touch instead.
  Call `stick._input(event)` directly, the way `controller_mapper_test` feeds
  `_gui_input`.
- GDScript cannot infer a type from `ConfigFile.load_file()` or from an `or`
  expression: `var e := config.load_file(p)` and `var b := x or y` are parse
  errors. Annotate them `Error` and `bool`. (`ConfigFile` has `load`/`save`, not
  `load_file` — the parse stage will not tell you.)
- HUD overlays that panels can cover must re-check coverage from the covering
  panel's own `visibility_changed`, never from a call bolted onto one code path.
  v11 shipped the thumb sticks permanently invisible: `_update_thumb_visibility`
  ran when the splash *opened* and nowhere when it closed — and because a hidden
  stick ignores input, every press fell through to tap-to-lock as well.
  `tests/thumb_visibility_test.gd` is the regression.
- Tap-to-lock is off in controller-free mode (`_tap_lock_allowed`): a thumb
  reaching for a control must not grab an orbit target. Settings → Display →
  "Tap to lock target" restores it; the radar and the MFD still select contacts.

## Building heights (2026-10-01)

- The OSM extract writes a fallback when a way carries neither `height` nor
  `building:levels`, and three quarters of a theatre is that fallback: 78.7% of
  Sydney Harbour stood at exactly 7.5 m, so suburbs rendered as one flat plane
  of rooftops. `tools/infer_building_heights.py` restates every fallback height
  from the footprint's own area, the tagged heights nearby, and a jitter hashed
  from `osm_id`. Sydney went from 3 distinct heights among guesses to 148; the
  modal share is now 8.6%.
- **Provenance is readable off the stored number**, which is why no re-fetch
  was needed: the builder clamps `building:levels` to multiples of 3.15 m, so
  anything that is not exactly 7.5/11.0/18.0 came from a real tag and is used as
  reference data, never overwritten.
- A big footprint is not a tall building. Footprints over 8000 m2 with no tower
  nearby are warehouses, hangars and one mistagged airfield outline, and are
  capped at 9 m (7 m over 40,000 m2) — otherwise a 213,000 m2 way at Bankstown
  becomes a 20 m wall across three suburbs.
- Inference is per *theatre*, indexed before anything is rewritten: a CBD
  block's reference towers live in the chunk file to the east, not beside it in
  its own file.
- Idempotent by chunk marker `height_model`. Re-running is a no-op. Bumping the
  model version treats the previous pass's output as reference data, so
  `git checkout data/regions` first.
- `tests/building_height_test.gd` asserts against the shipped JSON: no single
  height may own more than 40% of a sampled theatre, and a theatre must contain
  both something over 60 m and something under 4 m. It exists because the
  render path is perfectly happy drawing a carpet of boxes and notices nothing.
- `tools/check_building_heights.gd` is the pixel half: it builds the real
  `BuildingMesh` for a set of chunk JSONs and photographs it, so a before/after
  pair is two directories of the same files (`git show HEAD:<path>` gives the
  old one). `--range=0.16` pulls the camera in far enough to read roof lines.
- Building meshes are **not** cached on device — only imagery and heightfields
  are, under `user://map_cache`. A new APK shows data changes immediately.

## Battle map camera (2026-10-01, Battle Map V2 phase 1)

- The map's camera lives in `scripts/battle_map/battle_map_view.gd`, its input in
  `battle_map_gestures.gd`; `tactical_map_canvas.gd` composes them and draws
  symbols through the same projection `shaders/tactical_map.gdshader` uses for
  the terrain. Keep that split — the canvas must not grow maths of its own.
- Pinhole over the ground plane, in "map space" (metres right/down, before
  bearing rotation): `depth = L − my·sin t`,
  `screen = size/2 + (mx, my·cos t)·F/depth`, `F = span/2/PERSPECTIVE`,
  `L = range/PERSPECTIVE`, `PERSPECTIVE = tan(fov_y/2) = 0.268`. **At tilt 0 this
  is algebraically identical to the old flat map.** Preserve that identity or the
  existing picking/anchoring assertions break.
- `bearing` is the camera heading: increasing turns right, which carries world
  content counter-clockwise on screen. Ownship nose draws at
  `sin(heading − bearing), −cos(heading − bearing)`.
- Two opposite contracts, and mixing them is the classic drift bug: a **drag or
  pinch grabs the ground** (`rotate_by(−twist)`, `pin_world`), a **stick, wheel or
  two-finger lean looks at it** (`pan_pixels` moves the viewpoint east when pushed
  right; the stick spins `+look.x`). Both read natural; each has one direction.
- Tilt caps at `TILT_MAX = PI/3` and may never invert: `map_offset_at_screen`
  returns `INF` above the horizon, so every projected point needs an
  `is_finite()` guard before it reaches `draw_rect`/`draw_polygon` (an INF
  vertex silently drops the whole polygon).
- Two-finger gesture = spread→zoom, inter-finger angle→spin, midpoint **vertical
  travel since the previous sample**→lean. `_pinch_point` stays fixed at the
  press midpoint and the grabbed ground is re-pinned there every event: that is
  what makes a vertical pair drag tilt *instead of* panning. Measuring travel
  from the press tilts harder every frame.
- `set_range` / `pan_pixels` are immediate; smoothness comes from fling inertia
  and the 0.4–1.0 s `begin_glide` focus animation (`FOCUS_MIN/MAX_SECONDS`).
  Existing tests assert instant range semantics — do not make zoom smoothing the
  default. `animate_range()` is the opt-in.
- The canvas keeps `centre`, `range_m`, `bearing`, `tilt`, `follow_player` as
  property proxies onto the view so `tactical_mfd_test.gd` and
  `tactical_places_test.gd` pass untouched. `_sync_viewport()` runs at the top of
  every geometry entry point because those tests set `map.size` directly and call
  methods without advancing a frame.
- Controller: `MAP_BUTTON_ACTIONS` (Y and R3) is the only allow-list that reaches
  `action_pressed` while the map is open, so no weapon or target button can fire
  through the panel. `get_map_pan_vector/get_map_look_vector/get_map_zoom_axis`
  return ZERO unless `_tactical_open`; `get_flight_vector` returns ZERO while it
  is open. The sticks change owner, they never share. R3 = `reset_view()`
  (north-up, overhead, ownship) and `main.gd` routes it before the map-visible
  early return.
- Android synthesises mouse events beside its touches; the 500 ms
  `MOUSE_BLOCK_MILLISECONDS` in the gesture module stops the map panning twice
  over. A double click's second *release* must not also emit `tapped`
  (`_mouse_double`) or flying onto a contact would drop a waypoint under it.
- `tactical_map.gdshader` is never compiled headless — a broken shader ships
  silently. Pixel check: `xvfb-run -a -s "-screen 0 900x600x24" $GODOT_BIN --path .
  --rendering-driver opengl3 --script tools/check_battle_map.gd -- --out=/tmp/bm`
  (llvmpipe works here). It renders every camera state and fails if a frame is
  empty. `flat` is reserved in GLSL, so name the level surface something else.
  Terrain relief is weighted by `sin(tilt)` so a top-down view stays pixel-equal
  to the CPU markers.
- New tests: `battle_map_view_test.gd` (projection round-trip, limits, anchoring,
  inertia, glide), `battle_map_gestures_test.gd` (every finger and mouse gesture),
  `battle_map_controller_test.gd` (production routing).
- Pre-existing suite flake, nothing to do with the map: any test that
  instantiates `main.tscn` can exit with
  `ERROR: 1 resources still in use at exit` naming
  `assets/audio/jet_engine_loop.ogg::OggPacketSequence` (seen ~20-30% of runs on
  `jet_audio_runtime`, `thumb_visibility` and `battle_map_controller`). Every
  check passed and the PASS line printed first. Stopping the player, nulling the
  stream and quitting a frame late were all measured and none of them fix it, so
  do not add a teardown workaround — re-run the single test before chasing it.
  `--verbose` prints which resource; that is how to tell this apart from a real
  leak.

## Battle map semantics (2026-10-02, Battle Map V2 phase 2)

- Zooming has to change what the map *says*, not how big its symbols are. Three
  densities -- THEATRE, REGIONAL, TACTICAL -- each with its own information set,
  in `scripts/battle_map/battle_map_layers.gd` (the density, the layer table and
  the persisted toggles) and `battle_map_markers.gd` (what to draw at each). The
  canvas composes both and owns no clustering maths of its own.
- Densities change on **hysteresis**, not thresholds: `TACTICAL_ENTER 6500` /
  `TACTICAL_EXIT 8000`, `REGIONAL_ENTER 24000` / `REGIONAL_EXIT 29000`. A single
  boundary makes the map flicker between two reports on consecutive frames of one
  pinch. Layer fades run at `FADE_RATE` toward the alpha the density asks for.
- Grouping is a property of the **ground**, not the camera: contacts are bucketed
  into world-aligned cells (`CELL_METRES`) and adjacent buckets merge by
  union-find while their centroids are within `cell * MERGE_FRACTION`. A cache
  signature of handles, rounded positions and velocities gates the rebuild, so a
  pan costs nothing and the same formation keeps its number as the map moves.
- `MIN_GROUP` is 2 at **every** density: a lone track stays itself. Theatre was
  once allowed to wrap a singleton in a report so it "would not vanish", which
  produced `GROUND GROUP 1 · 1` over a named SAM site — an individual is drawn
  and tappable at 40 km exactly as it is at 2 km, so nothing is lost.
- Group records are **pooled and reused**, which makes aliasing the failure mode
  to know: a record is free only when its count is zero *and* no cell is still
  `registered` to it. Every live record is zeroed at the top of a rebuild, so
  counting alone hands one formation's record to two markers -- the symptom was a
  theatre view double-counting seven tracks as ten.
- A headless `SceneTree` test never runs `_draw`, so nothing rebuilds the
  clusters by itself: call `map.markers()` before reading
  `map.cluster.live_groups()`, and copy `handles_of(group)` out *before* flying
  in, because the glide rewrites the pooled record.
- **No map-only target identity.** A group carries the tracker's own handles; a
  group tap selects and reports but never locks; `ASSIGN` emits the same
  `contact_selected` handle a tactical tap would, which reaches the weapon through
  `main._select_map_contact`. `FLY TO` ends inside the tactical band so the
  members become individually tappable -- the same contract as a double tap.
- The selection card prints only fields the tracker can answer. There is no
  track-confidence or last-update field anywhere in `target_tracker.gd`, so the
  card does not have one either; an MFD that guesses is worse than one that says
  nothing. Range is **ground** range, with the wasted altitude printed beside it
  rather than folded into the number, so `RNG` and `ASSIGN` can never disagree.
- The card refreshes at 4 Hz (`CARD_SECONDS`), not per frame, and clears when its
  subject is destroyed or the panel closes. War layers with no intelligence
  behind them are shown **disabled and labelled `· NONE`** rather than faked; the
  Layers section sits at the head of the rail because a phone landscape shows two
  of its twenty-odd rows and clutter is the reason to open it.
- `tools/check_battle_map.gd` photographs the same six tracks at each density and
  asserts the *report* changes: theatre says `AIR GROUP 1 of 6`, regional says
  `AIR GROUP 1 of 5, SHEET`, tactical names all six. Frames are also compared
  pixel-wise so a scale change cannot pass as a information change.
- Tests: `battle_map_layers_test.gd` (density hysteresis, layer table, persistence),
  `battle_map_markers_test.gd` (clustering, labels, cache, group picking),
  `battle_map_zoom_test.gd` (what each density draws and taps),
  `battle_map_card_test.gd` (card fields, refresh cadence, layer rail).

## Battle map regions and the front (2026-10-02, Battle Map V2 phase 3)

- Three modules, one direction of dependency: `scripts/war/war_regions.gd` (where
  the districts are), `scripts/war/war_control.gd` (who holds them, and the front
  that follows), `scripts/battle_map/battle_map_territory.gd` (what that looks
  like). The renderer holds no camera and no facts; the geography holds no
  ownership -- so Phase 5's WarDirector can replace `war_control`'s seeds with a
  simulation without touching either of the other two.
- No honeycomb: 32 districts from the coastline, the Broadwater, the river lines,
  the escarpment and the McPherson Range, named for places `map_places.gd` already
  knows. They are authored as **one shared lattice** (8 rows × 7 cells,
  `GRID`/`LATS`/`BORDER`/`SHORE` in `war_regions.gd`) so neighbours repeat the same
  corners and their common edge is identical to the metre. Gaps are impossible by
  construction, which is what lets the front be derived rather than maintained.
- Region polygons are world metres from `MAP_TILES.world_of` -- centred on zero,
  ±`world_size_m`/2 at the edges -- while the lattice tables are absolute
  lat/lon. `load_theatre()` clears **first** and then validates the theatre id, the
  centre keys and the bounds, so an unauthored theatre is refused and leaves no
  districts seated behind it: `scripts/war/war_director.gd` validates whatever
  tables it is handed, so a stale lattice is a campaign fighting over ground the
  world no longer contains. A second corridor needs its own authored grid.
- The front is data, not art: `front()` returns each shared segment whose two
  owners are not on the same side, with `kind` FRONT or CONTACT, a midpoint and a
  unit pressure normal pointing at the weaker hold; cached, invalidated by
  `set_owner`, and asserted in `war_control_test.gd` to move and to restore exactly.
  A CONTACT edge is drawn thin with no chevron -- the hatch already says that
  district is unsettled.
- Contested ground is **both claims at once**: two hatch families in world space,
  blue and red, placed by the same point-in-polygon rule the geography uses, over a
  thinner wash than a held district. Fills cap at alpha `WASH` 0.17 (contested
  0.07) because an overlay that hides the imagery is a choropleth, not a command
  map; the render check measures the imagery's detail before and after.
- `battle_map_layers.gd` gained a runtime source report (`set_source`/`has_source`)
  and `load_settings()` now reads **every** layer, so a toggle left alone while a
  layer was empty survives until its data arrives instead of being silently reset.
  `main.gd` calls `_tactical_mfd.map.set_war(regions, control)` -- or two nulls for
  a theatre with nothing authored -- beside the layer handover.
- Gotcha: `_visible_ground()` used to clamp with `Rect2(-half, half)`, which is a
  position **and a size**, so the theatre's box ended at its own centre and every
  cull dropped the ground east and south of it. A `Rect2` is pos+extent, and its
  printed `S:` is the size rather than the end corner -- print `.end` when a
  culling test disagrees with what you think the box covers. It hid because the
  flat default camera draws the screen-aligned grid instead of the ground grid
  this box feeds; `battle_map_zoom_test.gd` now asserts the far side of a theatre
  counts as visible.
- Tests: `war_regions_test.gd` (coverage sampled between lattice lines: no gaps, no
  overlaps; one ring per district; mutual adjacency with shared vertices; every
  gazetteer place inside its namesake district; the refusal for Sydney),
  `war_control_test.gd` (every field the brief's `RegionState` lists, the measures
  among them as ratios, the derived front, `set_owner` moving it and restoring it),
  and `battle_map_zoom_test.gd`'s new sections (the war arriving makes Territory
  switchable and gives it fills, hatch, chevrons and contact edges; the layer fades
  out below tactical; taking the war away makes the toggle refuse again).
- `tools/check_battle_map_terrain.gd` photographs the same camera with the overlay
  on and off and asserts the war is visible, the terrain's own detail survives it,
  the hatch and chevrons are in the batch, and switching the layer off returns the
  map that shipped before it.

## Strategic objects on the map (2026-10-02, Battle Map V2 phase 4)

- `scripts/war/war_objects.gd` builds the registry out of sources that exist for
  their own sake, and nothing else: **airfields from `runways.gd`** (one object per
  aerodrome, carrying its own authored strips, headings and lengths at the ARP the
  airport table publishes), **SAM sites from `launcher_layout.gd`** (the same layout
  `launcher_field.gd` scatters from, so a site is where hostiles actually spawn and
  its faction is the enemy's whatever the districts say), **landmarks from
  `hero_towers.gd`** (at the lat/lon the terrain places them). Six of the brief's
  nine types have nothing in this world to correspond to, so they are **declared and
  left unpopulated** and the layer reports `· NONE` rather than drawing an estimate.
- No duplicate target identity: strategic ids start at `FIRST_ID = 300000`, above the
  launcher (1+), drone (100000+) and jet (200000+) bands, because the card shows a
  tracker handle for a site that has one. A site carries the launcher field's **own
  entity ids** in `handles`; `tactical_map_canvas.select_at` asks contacts first, so a
  live launcher under the finger is what a tap gives, and `ASSIGN TARGET` routes
  through `contact_selected` into `main._select_map_contact` and the real tracker.
  Airfields and towers are not shootable: their card refuses `ASSIGN` **in words**
  (`NO LIVE TRACK`) instead of locking something that does not exist.
- Every derived field has an owner: `region_id` from `war_regions.region_at`,
  `intel_confidence` as that district's `intel_level`, `strategic_value` as a per-type
  `WEIGHT` scaled by the district's authored value, `source` naming the file the row
  came from. Ground outside the district lattice gets an empty `region_id` and the
  middle of the scale, not a made-up district.
- The two live bindings are the only state that changes by itself.
  `bind_launchers(positions)` matches the field's reports to a site by the name prefix
  it gives its own clusters; `bind_structures(hit_index, damage)` fires the real
  vertical ray at the landmark's coordinate and measures what comes back against
  `BuildingDamageSystem.SMOKE_THRESHOLD` (half = smoking, twice = nothing standing).
  A chunk that is not streamed answers with nothing, and the object says
  `streamed: false` and the card reads `FOOTPRINT NOT STREAMED` rather than claiming
  damage. `main.gd` runs both on map open and at the 1 Hz layer refresh, never per
  frame.
- Gotcha: `DAMAGED` was unreachable at this theatre's launcher density. Health was
  live-over-planned and a cluster holds one launcher, so the ratio could only be 1.0
  or 0.0. A site is now measured against `detail.strongest` -- the most launchers ever
  seen standing at it -- which is what makes "1 LAUNCHER OF 2" a state rather than a
  sentence.
- `UNCONFIRMED` is a real epistemic state, not a colour: a site the layout puts there
  that has never reported in is drawn at `STRATEGY.UNCONFIRMED` 0.38 of the layer's
  alpha, with a plain cross instead of its triangle, and is still selectable because
  the card is exactly where "nothing seen there" belongs.
- `scripts/battle_map/battle_map_strategy.gd` holds no camera and no facts: the canvas
  hands it its own projection and `_visible_ground()`. An airfield's **pavement is in
  world metres**, projected like any other ground line, so the map is the only place
  the brief's "objects must correspond to actual world locations" can be measured --
  the run check asserts the drawn strip is as long in pixels as the runway is in
  metres at the map's scale. Glyphs stay upright: a symbol is a report, not a decal.
- The density rule drops **names, not objects** (`levels: [0, 1, 2]`): the planning
  loop wants the pilot to fly *into* a site and keep seeing what it is. Below
  `DRAWN_VALUE` 0.3 nothing is symbolled at all and at theatre range only
  `THEATRE_LABEL_VALUE` 0.6 and above is named, which is what keeps hundreds of
  entities usable without a special case.
- Selection seam: canvas `signal strategic_selected(id)` + `set_objects(registry)`,
  `strategic_object(id)` for the card's live re-read, `focus_object` for FLY TO. The
  MFD card renders `COOLANGATTA AIRPORT · AIRBASE · FRIENDLY`, `1 STRIP · 14 2492 m ·
  HDG 140°` (the strip's own designator, its authored length and its heading), the
  ARP's LAT/LON, the holding district and the `source` line.
- Tests: `war_objects_test.gd` (every row traces to its source -- ARP lat/lon,
  `SITES.clusters_for` centres, hero lat/lon, strip ends against `RUNWAYS.threshold_latlon`;
  the §9 field set, id bands, a 1 m coordinate round trip, value bounded by `WEIGHT`,
  confidence equal to the district's `intel_level`; the launcher lifecycle INTACT →
  DAMAGED → DESTROYED → UNCONFIRMED; structure binding through the **real** damage
  system including the unstreamed answer; Sydney with no geography), and
  `battle_map_strategy_test.gd` (the layer coming online, symbols drawn exactly at
  `world_to_screen`, red/blue by faction, culling and the value floor, a tap resolving
  to contact-vs-object priority, the card's exact text, ASSIGN routing to the tracker's
  `[21]`, and a theatre with no objects refusing its own toggle).
- `tools/check_battle_map_terrain.gd`'s strategic pass is where the brief's "objects must
  correspond to actual world locations" is answered in pixels: the drawn OOL runway
  measures the authored 2 492 m at the map's own scale, every symbol sits within a pixel
  of `world_to_screen` of its record, the theatre names only what is both confirmed and
  above the labelling threshold (one of ten), and a tap on `CITY NORTH SITE` reaches the
  registry's own row with its `source` and district -- on an object the exercise's own
  tracks stay off of, because the corridor's gazetteer puts its COOLANGATTA AIRPORT
  label on the ARP to the metre and a live track standing there must win the tap, which
  the same pass asserts as the priority branch. Gotcha for any future single-glyph pixel
  check: `_changed()` is a *fraction of the frame*, which is right for a theatre-wide
  overlay (0.65 for territory, 0.017 for ten objects) and says nothing useful for one
  glyph after a lean (~0.001). `_painted(one, two, at, radius)` counts the differing
  samples in the symbol's own neighbourhood instead -- and dark backing over dark imagery
  never crosses the 0.06 RGB threshold, so for a single symbol the *geometric* assertions
  (drawn point within a pixel of `world_to_screen`, still tappable through the tilt) are
  what carry the claim and the pixel count only proves it reached the screen.

## The war director (2026-10-02, Battle Map V2 phase 5)

- `scripts/war/war_director.gd` is §13's data half and nothing more: persistent region
  state, air control, ground control, strategic ticks, ground battles, facility damage and
  repair. It owns no rendering — it reads no node, camera or canvas item, and
  `main.gd._update_war(delta)` only asks `advance(delta)`, which is a lookup plus one
  addition until the eight-second clock rolls over. BattleMap displays what
  `war_control`/`war_objects` hold; the director writes those two and no third thing. Full
  write-up: `docs/2026-10-02-battle-map-war-director.md`.
- One tick is seven stages in a fixed order — `_gather, _operate, _air, _fight, _reinforce,
  _settle, _publish` — and the order is the argument: evidence is credited and decays first,
  the fields work out what can fly before the air is computed, the air is computed before
  anyone attacks across it, the fighting decides who is in contact (which is what
  reinforcement may not thin), and only once the ground has moved is the map told.
- **A strategic tick costs about two milliseconds** (200 ticks of the corridor: 1.75 min,
  1.97 median, 2.07 p90, 3.64 worst) with 32 districts, ten objects, six sites and their
  launchers bound. §14's no-per-frame rule is satisfied by the tick existing; do not
  "optimise" it by caching arithmetic, and do not move any of it into `_process`.
- Gotcha: **a refusal must clear, not keep.** `war_director.setup` and
  `war_regions.load_theatre` both validate what they are handed and both now empty their
  own tables *first*, because a caller that survives a refusal keeps whatever was seated
  before it -- and the only thing that ever reads a geography is a campaign seated on it.
  `main.gd._load_streamed_region` hands the director the same nulls it hands the map for an
  unauthored theatre, so the war refuses to start rather than fighting over the last
  theatre's ground. Related: `advance()` returns `false` until `setup` has succeeded, or an
  unseated war ticks every frame forever.
- Gotcha, and the phase's real lesson: **ownership is a feedback loop.** Deriving a
  district's owner from the *ratio* of the two sides' presence made one hot corridor
  district cross the contested boundary 62 times in 200 ticks — reporting it taken changes
  who attacks it, which changes whether it is held, which changes the report. What fixed it,
  in this order: presence-weighted balance plus `OWNED_MIN 0.25` (both sides standing in
  strength ⇒ contested whatever the balance says), `OWNED_KEEP 0.10` hysteresis on leaving
  that state, and `SETTLE_TICKS 3` so a new owner must survive its own first three ticks.
  Final run: 37 announcements over 12 districts, busiest (`tweed_heads`) 11 — one move every
  18 ticks. `SETTLE_TICKS` delays the owner and nothing else; presences, balances and fights
  keep moving on all three ticks.
- Gotcha: a stalemate can be *too expensive* rather than too quiet. At
  `SUPPLY_UPKEEP 0.006` both pools pinned to the floor and ownership froze from tick 20 to
  200 — a photograph of a front, which is the same failure as a landslide in the other
  direction. Halving the standing cost to 0.002 is what made the front move again; the floor
  stays 0.5 on purpose so an exhausted side fights at about two-thirds tempo instead of
  stopping the war.
- Gotcha: `damage_facility()` queues into the facility's `wear` and the *tick* applies it.
  Reading `facility(id)` straight after the call returns damage 0 and looks like a refused
  hit. A 0.35 hit reads 0.329 with five of eight parked on the next tick, `DAMAGED` until
  tick 16, whole with its full complement at tick 29 — §10's "no field ended by one bomb".
- Gotcha: `registry.bind_launchers()` matches on `site + " "` as a name *prefix*, so a
  probe that invents launcher names binds nothing, silently produces zero air denial, and
  reports a misleadingly blue campaign. Name them after the site, as the launcher field
  does. Same trap in the data: the corridor's airbase type is `Type.AIRBASE`, not AIRFIELD.
- The seam with the flying world is two functions wide on purpose:
  `report_sighting(faction, world_position, weight)` — a *position*, because a position is
  what a flight has; the director finds the district with the map's own `region_at` so a
  pilot's track and a card's row cannot disagree — and `damage_facility`. Nothing about a
  sighting changes ground. There is no third verb yet: a strike record from the cockpit is
  Phase 6's loop, which is why `damage_facility` currently has one caller, the test.
- Measured, not authored: blue's share of the theatre's airspace is 0.34 with the six
  surviving SAM sites reported and 0.71 with `bind_launchers([])` (a cold start, which is
  what the map sees before any hostile has spawned), finishing F16 E9 C6 against F17 E6 C8.
  Six sites at 0.7 denial each outweigh one eight-aircraft field. That is Phase 6's SEAD
  argument arriving out of the model, and `active_battles()` is what will say it.
- `tools/check_battle_map_terrain.gd` grew `_campaign_drift`, the pixel proof: same camera,
  territory on, two frames to measure the noise floor (0.0008), a director seated on the
  very tables the canvas is drawing, 112 ticks, then the same camera asked again — 5/32
  districts moved and 11.2 % of the frame repainted, with the toggles, overlay and cached
  imagery untouched. Any future claim that the war reaches the screen belongs in this pass,
  and has to beat its own noise floor.
- Gotcha (`run_tests.sh`, again): an exit-time `ERROR:` fails a test that printed its
  `*_TEST_PASS` line. The suite is 139/140 and the red file moves — `--verbose` puts it at
  `assets/audio/jet_engine_loop.ogg::OggPacketSequence` with ten leaked ObjectDB instances.
  It was measured rather than blamed on this phase: war wired in, 10 failures of 20 runs;
  the same `main.gd` with the one `_update_war(delta)` call removed, 11 of 20. Do not
  "fix" it by touching audio.
- Gotcha (GDScript, and it bit twice in one phase): `%` binds tighter than `+`, so
  `print("a " + "b: %d" % [x, y])` formats only the second literal and raises `String
  formatting error: not all arguments converted`. Parenthesise the concatenation.
- `tests/war_director_test.gd` is nine sections over the real corridor's 32 districts,
  including the acceptance ("the line moves with nobody flying") and a rate-based churn
  guard (`busiest * 8 <= ticks`) so the 62-times pathology cannot come back unnoticed. The
  clock section advances `1.1` rather than `1.0` because 420 × 1/60 is 6.999999999999998 in
  binary — a check that lands two femtoseconds short of its own tick tests floating point,
  not a clock.

## AI commanders on top of the war (2026-10-03, Battle Map V2 phase 7)

- `scripts/war/faction_commander.gd` is §15 arrived at in data: two commanders, one per side,
  reading the director's published state, scoring the nine things a commander could be trying
  to do, and committing to the best few it can afford. The score is the brief's term for term —
  `strategic_value x urgency x vulnerability x available_force x commander_priority` — and all
  six printed factors multiply back to the score that ranked the operation, which is what
  allows §37's overlay to print a number beside a sentence. Doctrine is the only term in the
  product that is not a fact about the world; the band is narrow (0.80–1.30) so it settles a
  contest between near-equals and cannot put a quiet district on top by itself.
- **A turn of command costs about 1.8 ms** (200 ticks, 32 districts: 1.73 min, 1.77 median,
  1.83 p90, 2.23 worst). Two commanders and the enemy's own staff add roughly 4 ms to the
  eight-second strategic tick, which is the same order as the director's own 2 ms tick and
  three orders below a frame. §14's rule is untouched: nothing here is called from `_process`.
- Read-only, and measured rather than asserted: six commander turns move no district record,
  no facility and no resource total (string compare of the whole published table before and
  after), and there is not one `randf`/`randi` in the module. §13's two verbs into the war
  belong to the flying world; a commander that reported its own intentions as evidence would
  be inventing a fact about the sky, and a commander that needed a random number would be the
  scripted encounters §16 exists to replace.
- The pattern memory is the phase. The director decays a sighting on purpose (`EVIDENCE_DECAY
  0.55`), so a district the pilot has left stops being news within about five ticks — which
  means "repeated behaviour" cannot be read off the campaign at all, and slowing that decay to
  make a test pass would corrupt what the war knows. So the habit is kept here instead, where
  it can be as long-lived as a habit needs to be, keyed by the director's own district ids.
- Measured, and it retuned the constants twice: a tick of presence is worth **0.155** of habit
  weight, not 0.1, because the commander reads the fresh `+0.1` *and* the `0.055` tail the
  director left after decaying — hence `HABIT_FULL 2.4`. And the visit window has to outlast
  the weight it explains: at `PATTERN_WINDOW 20` the reason printed "worked TWEED HEADS in 0 of
  the last 20 ticks" while the habit was still 0.78/1.6, so the window is 32 and `SEEN_MIN` is
  0.08 (above the decay tail, below a real visit).
- The acceptance, measured on the corridor with one pilot flying into the enemy's richest
  district for 40 ticks and nobody else in the air: `INTERCEPT OVER TWEED HEADS`, score 0.4621,
  factors v 0.70 u 1.00 x 0.90 f 0.56 p 1.30 r 1.00, reason "FRIENDLY aircraft have worked
  TWEED HEADS in 32 of the last 32 ticks + they keep coming through here". Priority 1.45 over
  the worked ground against 0.72 everywhere else, effort 1.00 under the pilot against 0.00 over
  ground no operation stands on. Stop flying there and the war's own `seen` falls under
  `SEEN_MIN` in five ticks while the habit is still 0.78 at 25 — then the operation stands
  down, and after a full window of absence the pattern is dropped rather than kept forever.
- The A/B the whole phase is the claim for: same seed, same sightings, same eight questions,
  and the enemy's own board moves from `P2 0.318` to `P3 0.462` with the operation named on the
  mission record. With `set_commander(null)` the board is byte-for-byte the phase 6 board,
  which is what lets a theatre with no campaign still have missions to fly.
- One float crosses into the flying world: `enemy_squadron.intent`, from the foe commander's
  `effort_at` under the aircraft. §26 says wrap the tactical AI rather than replace it, so
  intent adds to the shipped rhythm instead of standing in for it — `randi_range(1, 2)` plus
  `round(intent * 2)` jets, breather `randf_range(30, 45) x (1 - 0.45 * intent)` floored at
  0.55 — and **negative intent means nobody is commanding**, which is every scenario and test
  written before the war existed, untouched. Moving SAM launchers, authoring enemy airframes
  or having the commander write sightings were each ruled out: the first two rewrite working
  combat systems, the third uses the wrong verb for a coefficient that cannot be felt.
- `main.gd` seats four objects per theatre (own commander, foe commander, own staff, foe staff)
  and clears all four in `_load_streamed_region` beside the board, because a phase 5 refusal
  that keeps the last theatre's table now also keeps a *memory* of it. `_update_war` order is
  launchers, the pilot's own sighting, both commanders, both staffs — and inside the commander
  the trends snapshot before the levels are stored, because a difference measured against this
  tick is always zero.
- Gotcha: `faction_commander._war` is a duck-typed `RefCounted`, so the readiness gate has to be
  in `available_force()` itself. The debug overlay and a future save file read a commander that
  refused its theatre, and an unguarded `_war.supply` is `Invalid call. Nonexistent function
  'supply' in base 'Nil'`. Same reason `priority_for` answers 1.0 and `effort_at` answers 0.0
  when nothing is seated: an unseated commander must be indistinguishable from no commander.
- Gotcha: the preload consts in `main.gd` are named `MISSION_STAFF` and `COMMANDER`, and those
  are the only spellings usable as type annotations there. Copying `staff: MISSIONS` out of a
  test parses as `Could not find type "MISSIONS" in the current scope`.
- Gotcha (test hygiene, and it made a false pass): `enemy_squadron.jets()` returns the live
  array, so `for jet in squadron.jets(): squadron.destroy_jet(jet.id)` erases out from under
  the walk, leaves a wingman standing, and then reads that survivor as the next wave. Iterate
  `.duplicate()` and assert `jet_count() == 0` before starting the clock. Every bound in
  `_check_intent_reaches_the_squadron` is the shortest or longest of the band rather than a
  roll, so no run of it can fail by being unlucky.
- Blue's commander never raises INTERCEPT, and that is a fact about the world rather than a
  bug: nothing in the corridor reports `seen[ENEMY]`, because the enemy flies its own patterns
  and the campaign is not told about them. It is documented in the module rather than faked
  with an invented sighting.
- `tools/probe_commander.gd` measured all of the above and is deleted: the constants are set off
  numbers, and the numbers are in this file.
- `tests/faction_commander_test.gd` is nine sections over the real corridor — the refusals, no
  intercept without a pattern, the acceptance, memory outliving news, discounting elsewhere,
  writing nothing, determinism, the A/B on the staff's board, and the bound on the squadron's
  wave. Suite: 141/143 with only the two known exit-flake files red (`f22_startup_test`,
  `jet_audio_runtime_test`), which flake 2 of 6 runs here against the 10 of 20 recorded in
  phase 5, and both print their `*_TEST_PASS` line first.

## The campaign in a file (2026-10-03, Battle Map V2 phase 8)

`scripts/war/campaign_save.gd` (§32's name) is the only thing in the project that touches the
disk for the war: version 2, `user://campaign_save.json`, `capture`/`apply` over the six
strategic modules and `write`/`read`/`exists`/`erase` around the file. Every module owns its own
shape through a new `export_state()`/`import_state()` pair — the director's is districts, battles,
contact edges, facility fields, purses, losses, tick/elapsed/length/seed; each commander's is its
operations, focus, habit windows and the last reading it differences against; each staff's is its
cards, callsign counters and serial. The save layer therefore has to know six names and nothing
about their contents, which is what §28's "later campaign changes do not immediately invalidate
saves" actually buys.

- Version 2 is `war_objects`' launcher-site memory, which the §35 demonstration below needed. An
  airfield's damage was always recoverable from the war (it owns the facility table and publishes
  it back over the map), but a site's health is a function of how many launchers the flying world
  is reporting at it, and launchers are gone the moment the mission is — so the campaign came back
  with every site intact and re-denied the air it had just been taught was clear. What is stored
  is the field's *last report* (`health`/`operational_state`/`discovered`/`seen`/`strongest`), not
  a launcher list: an entity id is as transient as a round in the air, and §28 says this layer does
  not save those. The field outranks the memory on its next report, exactly as it outranks it on
  every other tick. `objects` is applied first because the sites' cover is a fact the war reads;
  the war publishes its own airfields over the registry's afterwards.

- The whole of §28's list is covered, and the derivation is why some of it is not stored: airbase
  health *is* strategic-object health and destroyed-object state, `aircraft` at the ramp *is*
  aircraft losses, `presence` *is* ground-force strength, mission `status`/`outcome` *is* the
  player's results. Nothing transient is written, and no position is: the registry re-authors
  every field, site and tower from the region's own data, so a save carrying a `Vector2` would be
  a second copy of a fact (§25) — and `JSON.stringify`, already used by the telemetry server,
  cannot encode one anyway.
- Reload goes back through the module's own front door: `import_state` ends with `_publish()`,
  which is the one place the war writes the control table and the registry. An earlier draft
  hand-rolled `refresh_situation()` + `refresh_airbases()` at the end of the read; that is the
  same fact with two authors, and the second author had the wrong argument shape (`refresh_airbases`
  wants a per-object dictionary, not the float that was passed).
- `apply()` rolls back. Five modules restored in sequence is five chances to stop halfway, and the
  first version did exactly that in the test: a swapped-faction board was refused *last*, by
  which time the war and both commanders had already taken the new state. Now each module's own
  `export_state()` is taken before it is overwritten and a later refusal replays those in reverse
  through `import_state`, so a refusal cannot leave a campaign made of two wars.
- Gotcha (found by the acceptance, not by reading): the owner guard rejected `CONTESTED`.
  `CONTROL.OWNERS` is the four-token list; `BLOCS` is only the two that fight, and a third of the
  corridor's districts are authored `CONTESTED`, so validating an owner against `BLOCS` refuses a
  perfectly good save. Use `OWNERS`.
- Gotcha: JSON has one number type. Every int comes back a float, and this campaign reads ints
  without converting — `%d` on a restored operation printed `3.0`, and an `object_id` of `4013.0`
  does not match the registry's `4013`. Each module therefore has a `SAVED_WHOLE` list and coerces
  those terms on the way in.
- Gotcha: `war.facility(id)` hands out the live Dictionary. Two reads of one field are two names
  for the same numbers, so `damaged["damage"] > before["damage"]` in a test is comparing a table
  with itself and can never be true. `.duplicate(true)` on the "before" read.
- Gotcha: `String(value)` is not a general cast in 4.x — it raised `Invalid call 'String'
  constructor` on region ids read out of a snapshot dictionary. `str(x) == str(y)` compares them
  fine.
- `damage_facility()` adds to `wear`; `_operate()` folds wear into damage on the next tick. A test
  that strikes a field and reads `damage` without ticking measures nothing, which is how the first
  draft of the acceptance passed while asserting nothing.
- Import is whole-or-nothing at every level: the director requires the file's districts to be
  exactly the seated 32, names a legal owner and carry every `SAVED_DISTRICT` term; a battle must
  carry its 15; a facility record its 9; each commander refuses a state written for the other
  faction, and so does each staff. `_table`/`_holds` return "no table" for a JSON value of the
  wrong shape so a hand-edited file is refused rather than crashed on halfway through.
- main.gd: `NOTIFICATION_WM_CLOSE_REQUEST` (capture, then quit) and
  `NOTIFICATION_APPLICATION_PAUSED` (capture — a phone that loses focus can lose its process a
  second later); `_restore_campaign()` runs at the end of seating, before the MFD is wired to the
  tables it is about to draw. It deliberately does **not** capture on a region swap: changing
  theatre inside a run is not the end of one, and a swap-time write would both overwrite the
  campaign a player quit with and leave a stale file behind in every headless test that swaps
  regions — the suite shares one `user://`.
- `tests/campaign_save_test.gd` is six sections: the acceptance (break a field, quit, rebuild every
  module from the corridor's data, apply, compare all nine facility terms plus every district term
  plus supply and losses and the clock, and check the *registry's* copy came back broken too),
  the decisions (both commanders' operations/scores/reasons/habits/focus, both boards' cards and
  serials, and the enemy's intent over the worked district — then eight more ticks to prove it is
  still commanding rather than playing back), the disk round trip (re-capture must be
  term-for-term identical, through the JSON text as well as the dictionary), the refusals (later
  version, foreign theatre, warless state, empty capture, erase), the rollback, and the unseated
  modules.

## The one convincing loop (2026-10-03, Battle Map V2 §35)

`tests/campaign_demo_test.gd` is §35's demonstration scenario, run over the corridor the game
actually ships with rather than over the three invented regions the brief sketches. It is not a test
of a module; it is the claim that a pilot's sortie reaches all the way down the chain to the front
line, phrased as something that can fail.

- The method is two campaigns — same seed (4242), same authored ground, same commanders, same
  staffs, same number of ticks — in one of which somebody flies. Phase 5 already established that
  the line moves with nobody flying at all, so "the ground changed" proves nothing without the
  counterfactual, and the simulation's determinism is what makes the counterfactual free: every
  difference between the two wars at the end is the sorties and nothing else.
- What it measures, over 240 ticks: six SEAD sorties, one per launcher site the corridor authors, at
  a gap of two ticks so the pilot has a campaign behind him rather than one busy minute. Over the
  district the chain started in — `surfers` — the flown war ends at 1.00 friendly air against the
  mirror's 0.19. `CLEAR_AIR` is 0.55 and `DENIED_AIR` 0.45, so the twins sit on opposite sides of
  the staff's own two lines, and the assertion is made against those constants rather than a figure
  invented in the test. Ground over the same district ends 0.89 against 0.80; five districts
  (`banora`, `lennbrook`, `neurum`, `pointer`, `tweed_heads`) belong to somebody different; and the
  war nobody flew is still offering the job that was flown. Blue holds 17 districts in both — the
  line moved in five places and did not, on balance, advance, which is what six sorties over a
  32-district front are worth and is recorded here rather than smoothed over.
- The quit lands at tick 12: the last site is down, the staff has written its success, and the air
  bought over it is 0.79. The reload comes back with the same owner, the same ground and air to
  the term, no launcher standing, the same cards carrying the same results — and then runs twelve
  more ticks and moves ground, which is the difference between a save and a recording of one. That
  is the campaign that needed the registry in the file (version 2, above): without the sites' last
  report, the reloaded war re-derived every launcher from an empty field, put the cover back and
  took the air away again.
- §35's order of battle is one the corridor does not have, and the third section is the honest
  version of the gap: it counts what `war_objects` really authors (6 launcher sites, airfields, and
  RADAR / SUPPLY_DEPOT / COMMAND_POST all exactly zero) and then asserts the consequence — across
  240 ticks the staff's board never once raises a STRIKE. A live launcher is a SEAD by §17's own
  rule and a dead one is not a target, so §35's MISSION 3 has nothing to be flown against in this
  theatre. INTERCEPT and GROUND_INTERDICTION cards do appear; a bomb package never does. Padding the
  theatre so the demonstration reads better is the thing that section exists to catch (§25, §38).
- Gotcha (the first draft passed while asserting nothing): the sortie helper rebuilt the launcher
  field from the whole authored site list every time it flew, which put every killed site straight
  back up. The campaign now carries a `standing` handle-to-name dictionary and a sortie erases from
  it, because the field's report is what the sites' health is derived from and a flown sortie has to
  still be flown the next tick.
- Gotcha: §33's board is a rolling window, so by tick 240 the cards the staff called off have been
  pushed out of it. Successes have to be accumulated while they are published (`_note` every turn),
  not reconstructed at the end.

## The debug read-out of the war (2026-10-03, Battle Map V2 §37)

`scripts/war/war_report.gd` answers §37's list — tick, ownership, air and ground control, what each
commander is doing, what each staff has on its board, the purse, object state, and why a mission or
a district changed — in one place, and the telemetry socket, the on-screen overlay and
`tests/war_report_test.gd` all read that one place. It was worth stating because `main.gd` already
carried a `_war_sample` and a `_command_sample` that answered eleven of the same questions a second
time: those are gone, and the delegate to `war_report.sample()`. A debug panel that disagrees with
the game about what the campaign is doing is worse than no panel, and two copies formatting the same
eleven answers is how that happens without anybody meaning it to.

- What the report does *not* do is measure anything or decide anything. Every value is one a module
  already publishes, nothing is written back, and nothing is smoothed or picked between: a district
  is printed with its signed balance (what the director fights over) *and* its 0..1 shares (what the
  control table publishes), because those are two different published facts and a panel that quietly
  chooses one is what makes an emergent bug unreadable.
- "Why the territory changed" is the only genuinely new surface, and it belongs to the director, not
  the panel: `_settle()` records a change into a bounded log (`CHANGE_KEEP := 8`) at the instant it
  latches an owner, with the reason naming the thresholds that actually fired — `"... turned to
  FRIENDLY after 3 settled ticks: FRIENDLY holds 0.60 of the ground against 0.05, a balance of +0.53
  past the 0.50 band, with the weaker side under the 0.10 ownership floor."` Written at flip time
  rather than reconstructed later, because §33's board is a rolling window and by then the numbers
  that flipped the district are gone.
- The saved row (`SAVED_CHANGE`) deliberately carries no district name: the registry's own record is
  the one author of what a place is called, so the report looks the name up when it prints (§25).
  `changes` is optional on import, so files written before §37 still load, and a row naming a
  district that is not on the map is refused.
- Held is counted over the regions the map knows and the rows printed beside it are the districts the
  war fights over, which are not the same set: this corridor authors 32 regions and seats 31
  districts, because `war_director._seat()` skips a region owned by NEUTRAL — open sea takes no part
  in a land war. The panel therefore says "over 31 of 32 regions" rather than reconciling the two
  into one number that would be a lie about a perfectly ordinary fact.
- `scripts/ui/war_debug_overlay.gd` is a code-built `PanelContainer` at `z_index 32`, mouse-ignored,
  hidden at boot, doing no work at all while hidden (no paint on `read_from`, `_process` returns
  early), refreshing every 0.5 s once shown. It is reached from Settings → Display → Developer →
  "Debug war overlay" and remembered through `_save_ui_flag("war_overlay")` — filed under that word
  on purpose, so a player on that page can see that nothing in it changes how the aircraft flies
  (§30).
- Measured on the shipped corridor, seed 4242, 120 ticks: 31 districts over 32 regions, held
  FRIENDLY 16 / ENEMY 10 / CONTESTED 5 / NEUTRAL 1, 17 front segments, 10 objects, 8 remembered
  changes (ticks 56, 74, 81, 98, 101, 105, 107, 113 — all of them `neurum` and `springbrook`, the
  two the commanders were actually fighting over), blue running 4 operations off 8 cards and red 4
  off 5, and the longest line exactly `PANEL_WIDTH` 100 columns.
- Gotchas: `war_control.front()`'s `pressure` is a Vector2, not the float the first draft cast;
  front rows go out as `[x, y]` pairs because a Vector2 has no JSON encoding the socket could
  carry;
  Godot's `visibility_changed` is *deferred*, so a test that shows the overlay and awaits a frame
  still sees the empty panel it started with — drive `_process(REFRESH_SECONDS)` instead; and
  truncating both sides of a screen-versus-socket comparison with `.left(40)` makes it pass for the
  wrong reason, which is how the "they disagree" failure was first misread as a real one.
- `tools/check_war_overlay.gd` is the pixel half: the headless test can prove the screen and the
  socket carry the same text, but only a drawn frame says whether that text is legible over a live
  world. It boots `scenes/main.tscn`, presses the same START the player presses (so the theatre
  streams for real — ~40 s cold), drives Settings → Display → the switch, and photographs the
  result: `xvfb-run -a -s "-screen 0 900x600x24" $GODOT_BIN --path . --rendering-driver opengl3
  --script tools/check_war_overlay.gd -- --out=/tmp/wov`. Measured on the shipped corridor at
  tick 0: 11 lines, 693 characters, a 560×215 plate at the top-left of a 900×600 screen, over half
  of whose pixels the switch visibly changes.
- Gotchas found by that check: Godot 4's `BaseButton` has no `toggle()` (the frame that should have
  proved the panel appeared instead aborted the script — use `set_pressed(not is_pressed())`), and
  comparing the overlay's text with the report's is a race unless the war is held still for one
  refresh, because the campaign ticks on its own clock and the panel on a faster one.
- `FAIL jet_audio_test.gd (exit 0)` — the documented "1 resources still in use at exit" flake — came
  up once in the §37 suite run (145/146). Re-running it alone reproduced it, and re-running it again
  identically passed, so per the rule above no teardown workaround was added. `--check-only` on
  `main.gd` always reports `Identifier not found: LocationService` because autoloads are invisible to
  it; that is true of HEAD too and is not a §37 regression.

## Real-theatre render check (2026-10-01)

- `tools/check_battle_map_terrain.gd` is the geographic half of the pixel check:
  it streams GOLD COAST // TWEED CORRIDOR through the production
  `streamed_terrain.load_region()` and drives the battle map camera over it.
  Same xvfb command as `check_battle_map.gd`, `-- --out=/tmp/bmt`. Cold it takes
  ~70 s to reach the map (mostly overview imagery); with a warm
  `user://map_cache` ~35 s, plus ~90 s more for detail chunks.
- It exists because `check_battle_map.gd` cannot supply the two things only a
  real theatre has: streamed `details` chunk quads, and geography to aim at.
  Each state asserts projection invertibility at every town, contact picking at
  each contact's own drawn position, and that the frame contains ground.
- `preload()` of a script that names an autoload (`TileClient`) fails to compile
  inside a `--script` run — the singletons exist by `_ready` but not by parse.
  `load("res://scripts/terrain/streamed_terrain.gd")` at runtime works, which is
  why the map's own tests do it that way. See the earlier "Test quirk" note.
- A `--script` run whose `_run` dies to a script error does **not** exit: the
  main loop keeps rendering at full CPU until the `timeout` fires, which looks
  exactly like a slow load. Send the output to a file and `tail` it
  (`> /tmp/x.log 2>&1`), never through `| tail` — a pipe buffers everything until
  the process ends, so a hang shows no progress at all. Print elapsed seconds
  with long-running steps.
- Detail chunk quads are modulated flat (`Color(0.72, 0.88, 0.81)`) while the
  overview goes through the map shader, so over dark ocean the chunk edge shows
  as a seam. Pre-existing (the shipped map did the same); more visible under a
  lean. Fixing it means matching the shader's satellite response, not the camera.

