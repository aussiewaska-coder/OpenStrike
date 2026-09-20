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
  auto-region is unavailable — user must pick the prepared demo region
  manually in Settings (Surfers Paradise). Without a region: theatre `none`,
  no tiles, camera follow stays off, jet flies blind.
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
