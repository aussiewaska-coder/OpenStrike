# OpenStrike handoff — 2026-09-05

Repo `/root/OpenStrike`, branch `look-polish` at `68e579c`, clean and pushed.
11 commits ahead of `main`. No PR opened. Suite **86/86**.

Everything below that has a written artifact is referenced, not repeated.

## Suggested skills

- **`superpowers:systematic-debugging`** — for the framerate and shadow items
  under Outstanding. Both are diagnosed-but-unproven; do not fix from the
  hypothesis alone.
- **`superpowers:brainstorming`** — before any new feature (Soul's geometry,
  F-117 effects or loadout, cloud volume). The F-117 work went spec → plan →
  execute and that shape worked.
- **`superpowers:executing-plans`** or **`subagent-driven-development`** — if a
  written plan is picked up.
- **`kiss`** — standing user preference. No speculative features.
- Do **not** invoke `androidclaw-learn-from-logs`; it is a different project.

## How to work on this

- Godot: `/root/godot-dist/Godot_v4.7.2-stable_linux.arm64`
- Suite: `GODOT_SILENCE_ROOT_WARNING=1 GODOT_BIN=/root/godot-dist/Godot_v4.7.2-stable_linux.arm64 tools/run_tests.sh`
  **Without `GODOT_BIN` every test exits 127 and it still prints a total** —
  that looks like a run but is a no-op.
- The runner rejects engine errors even on exit zero. A test printing PASS
  after an `ERROR:` line has failed.
- Headless does not compile shaders. After touching a `.gdshader`, validate on
  a real renderer or it ships broken. See README for the Xvfb/softpipe recipe;
  it is about 10 s a frame.
- After changing an asset or a `.import`, delete the matching
  `.godot/imported/` entries and run `--headless --import`, or the old
  resource is served. Adding a `class_name` needs the same to rebuild the
  global class cache.
- **Kill stale Godot processes between runs.** Killed test runs leave
  processes alive that starve the CPU and make everything mysteriously slow.
  Do not `pkill -f "Godot.*--script"` while your own run is going — it matches
  itself.
- Device loop: export `--export-debug "Android"` to `build/`, verify with
  `unzip -l`, copy to `/sdcard/Download/`.
- Live telemetry on `127.0.0.1:8787` while the game runs on the phone:
  `tools/read_telemetry.py` streams fps/draw calls/texture memory,
  `tools/telemetry_cmd.py '{"screenshot": true}' --out x.png` returns a real
  device frame, and `{"set": {...}}` tweaks fog, tonemap, sun, weather and
  time live. **The game draws no frames in the background**, so the socket
  drops the moment the user switches to the terminal — you cannot probe and
  chat at the same time.

## Delivered

Each has a change note in `docs/` with the reasoning and the measurements:

- `docs/2026-09-05-hero-tower-winding.md` — Q1 rendered see-through.
- `docs/2026-09-05-throttle-buttons-seat.md` — throttle on B/A, seat lowered.
- `docs/2026-09-05-dusk-lights-and-texture-memory.md` — black buildings at
  dusk, lights on the water, and the F-22's 256 MB of texture.
- `docs/2026-09-05-f117-flyable.md` — the Nighthawk.
- `3dassets/ATTRIBUTION.md` — the two new models.

F-117 spec and plan: `docs/superpowers/specs/2026-09-05-f117-flyable-design.md`
and `docs/superpowers/plans/2026-09-05-f117-flyable.md`.

Two reusable things worth knowing exist: `tools/fix_tower_winding.py`, and the
position-based `hide_landing_gear()` / `clarify_canopy_by_bounds()` in
`scripts/jet/jet_visuals.gd` for models whose parts have no useful names.

## Outstanding

### 1. Needs the user's eyes — three builds sit unflown on the phone

Nothing here can be settled from this side. In `/sdcard/Download/`:

- `OpenStrike-f117-2026-09-05.apk` — **does the F-117's nose point forward?**
  Two rotations give identical dimensions and differ by 180 degrees about the
  vertical. A backwards aeroplane passes every assertion in
  `tests/airframe_rigging_test.gd` and flies tail-first. If it is reversed,
  negate the first argument of `model_basis` in `Airframe.nighthawk()`.
- `OpenStrike-dusk-lights-mem-2026-09-05.apk` — do the buildings and the water
  look right? Open question in the change note: bare farmland is bright and
  ungreen, so paddocks may still light up. If they do, the tactical-map town
  anchors are already in the repo and can supply a radial mask.
- Cockpit height: `Airframe.cockpit_eye_height_fraction`, currently 0.80.
  `tests/jet_runtime_test.gd` holds a floor at 0.78 for seeing the instrument
  panel; 0.74 was tried and failed it.

### 2. Framerate — diagnosed, not solved

Measured over two device sessions: fps median 37 then 51 against 97-117 the
day before, `process_ms` median 32-37 with p90 75-83 and **spikes to 231 ms**,
on only ~600 draw calls. That is main-thread bound, not GPU.

Texture memory was pinned at 465 MB. That is now accounted for: 256 MB was the
F-22's three 4096 px textures imported lossless (fixed, now 32 MB) and ~224 MB
is ten terrain chunks at 2048 with mipmaps. `_apply_memory_budget()` in
`scripts/terrain/streamed_terrain.gd` carries its own device measurements in a
comment — 317 MB "stuttered badly", 104 MB held 111 fps, the budget targets
~150 MB — and it was doing its job while an asset outside its accounting spent
256 MB.

**Do not assume the texture fix cured the framerate.** Those textures were
resident the day before, when the same scene held 97-117 fps. Re-measure on
device first. The 231 ms spikes are unexplained; suspects not yet examined are
the low-altitude detail policy added in `be685a4` and the per-chunk building
build in `_ensure_chunk_buildings`.

### 3. Dusk shadow jitter — hypothesis only, never confirmed

User reported jitter on the aircraft's shadow in external views at dusk.
`scenes/main.tscn` has `directional_shadow_max_distance = 6500` with
`directional_shadow_split_1 = 0.025`, putting the first cascade over 162 m,
which would make shadow texels large enough to shimmer. Never seen in a frame.
Get a screenshot before changing anything.

### 4. Cloud volume

User asked for more volume in the clouds if performance allows. Not
investigated at all. `shaders/cloud_deck.gdshader`, `shaders/os_clouds.gdshaderinc`,
`scripts/world/cloud_deck.gd`. Given item 2, treat any cost as suspect.

### 5. Attribution is incomplete — blocks release

`3dassets/ATTRIBUTION.md` lists the F-117 and the E-3 with creator and licence
**UNKNOWN**. Both are Sketchfab models (their scene root is named
`Sketchfab_model`) but carry no embedded credit. The F-22 is CC BY-NC-SA, so
these likely carry terms as well. Ask the user for the two source URLs. Do not
invent them.

### 6. Smaller known gaps

- Soul is a 188-triangle slab with no crown, against Q1's 3985. A modelling
  gap, not a rendering defect. Deliberately left until the user looks at it
  with its shading now corrected.
- The F-117 has no moving control surfaces and no exhaust: `jet_effects.gd`
  does mesh surgery on Raptor geometry, so `has_jet_effects` is false for it.
  No cockpit interior — the model has none, and none was invented. No weapons
  or bomber loadout.
- The E-3 Sentry is imported and attributed but wired to nothing. Its gear is
  modelled down on unnamed nodes, so an airborne one flies with its wheels
  out. `jet_visuals.hide_landing_gear()` would solve it.

## Working agreements observed this session

- Verify on the device or in a render; green tests are not evidence that
  something looks right. Several conclusions this session were only settled by
  rendering — the tower winding, the F-117's missing cockpit interior, its
  opaque canopy, and the correct model basis.
- State plainly what was proven and what was only inferred. The framerate item
  above is the live example.
- The user works from a phone and writes tersely. Answer the question asked.
