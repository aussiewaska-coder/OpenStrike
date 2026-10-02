# Battle map camera — 1 October 2026

Phase 1 of the Battle Map V2 brief: the map a pilot already uses keeps every
contact, label and route it had, and gains a camera that can be thrown around.
Nothing in flight, weapons, targeting, terrain streaming or enemy combat was
rewritten for this.

## What the map does now

Pan is continuous and a finger drag grabs the ground rather than sliding the
viewport under it, so terrain stays under the thumb that took it. Zoom is
continuous between 500 m and 80 km and keeps the ground under the pinch (or
under the cursor for a wheel) in place. The map leans from flat to 60° toward
the horizon and rotates freely; 60° is the ceiling because past it the ground
crowds onto the horizon line and stops reading as a map. A flick releases into
a glide that decays to rest, and a double tap — or a double click — flies the
camera onto what was under it over 0.4–1.0 s depending on distance. There is no
teleport anywhere in the panel: the range keys glide too.

Android gets one-finger pan, pinch zoom, two-finger vertical drag for tilt,
two-finger twist for rotation, double-tap focus, tap select and tap-empty
deselect. Mouse gets left-drag pan, wheel zoom, right-drag tilt and rotate,
double-click focus. A Bluetooth controller gets left-stick pan, right-stick
rotate and tilt, D-pad zoom and R3 for north-up-and-ownship, and while the map
is open only those two buttons reach the game: Y still closes it, nothing else
does. A finger on the map outranks a deflected stick.

## Structure

`scripts/battle_map/battle_map_view.gd` owns camera state and its smoothing,
`scripts/battle_map/battle_map_gestures.gd` turns pointer events into requests
to that camera, and `scripts/ui/tactical_map_canvas.gd` keeps doing what it
always did: composing the two, feeding them the layers the streaming system
publishes, and drawing contacts, places and routes through the same projection
the terrain shader uses. The canvas still exposes `centre`, `range_m`,
`bearing`, `tilt`, `follow_player`, `set_range` and `set_state`, so the MFD
frame, the cockpit display and the shipped tests address it exactly as before.
`set_range` stays immediate — smoothness comes from the fling decay and the
focus glide, not from easing every zoom, which is what kept the pre-existing
map tests passing untouched.

The projection is a pinhole camera over the ground plane, worked in "map
space": metres right and down the screen before the bearing rotation. Depth is
`range / PERSPECTIVE − map_y · sin(tilt)`. At tilt 0 that is algebraically
identical to the flat map that shipped, and the shader weights its relief by
`sin(tilt)` for the same reason, so CPU-drawn symbols and GPU-drawn terrain
stay pixel-aligned looking straight down. `PERSPECTIVE = tan(fov_y/2) = 0.268`
is a deliberately long focal: a wide angle bends the near ground out from under
the player's own symbol.

Every screen point past the horizon has no ground answer, so projection returns
an infinite value rather than a mirror image, and each consumer — picking,
labels, grid, route, detail quads — has to check. The visible-ground box used
for the tilted grid widens a horizon-less corner by four ranges instead of the
whole theatre, which at 50 km and a 100 m grid would be five hundred invisible
lines a frame.

## What was kept

Terrain, imagery, elevation, buildings, contacts, target handles, waypoint
count and route logic are the existing systems. The map pulls the same
`tactical_map_layers()` dictionary it always did; no imagery is downloaded or
duplicated for it, and no second target list exists. A tap on a contact still
selects the existing tracker handle and weapon lock. A tap on empty ground in
waypoint mode still drops a waypoint — which is why the second press of a
double click is suppressed rather than also selecting.

## Validation

Headless suite: 129 of 130 tests pass. The one failure is `jet_audio_test.gd`
printing `ERROR: 1 resources still in use at exit` for
`assets/audio/jet_engine_loop.ogg` after every assertion in it passed — a
pre-existing teardown flake documented in AGENTS.md — it has landed on
`tactical_mfd_test.gd`, `thumb_visibility_test.gd` and
`battle_map_controller_test.gd` in earlier runs, on about one run in four, and
it is not caused by this work. `tactical_mfd_test.gd` and
`tactical_places_test.gd` pass unmodified, which is the point of keeping the
canvas' old property surface.

Three new tests cover the new code: `tests/battle_map_view_test.gd` (the
projection is identical to the flat map at tilt 0, project/unproject round-trips
across tilt and bearing, limits, anchored zoom, a drag pinning the ground, fling
decay, the 0.4–1.0 s focus glide), `tests/battle_map_gestures_test.gd` (each
touch and mouse gesture, including that a held two-finger lean does not
compound, that a pinch neither drifts nor zooms from a vertical slide, and that
a double click does not also select) and `tests/battle_map_controller_test.gd`
(sticks belong to the aircraft while the map is closed and to the map while it
is open, the two-button allow-list, and R3 returning to north-up without moving
the flight camera).

Two render checks run under a real Compatibility renderer (`xvfb-run` plus
llvmpipe), because headless does not compile shaders:

- `tools/check_battle_map.gd` draws a synthetic island so the camera's reach is
  checked without HTTP: seven landscape states plus a portrait one at maximum
  lean, each asserted to contain drawn pixels rather than an empty backdrop, and
  the far ground asserted to crowd toward the horizon as the map leans.
- `tools/check_battle_map_terrain.gd` streams the real GOLD COAST // TWEED
  CORRIDOR theatre through `streamed_terrain.load_region()` and points the
  camera at it. It renders satellite overhead, satellite at 30° and 60°, terrain
  at 30°, simple at 40 km, a close view with 12–16 streamed detail chunks
  resident, and a portrait view at maximum lean. Each state is asserted to have
  drawn ground, to invert `world_to_screen` through `screen_to_world` at every
  town the theatre knows, and to still return a contact's handle when tapped
  where that contact is drawn. Cold, with imagery to fetch, the theatre reaches
  the map in 67 s; with a warm `user://map_cache` in 34 s. Both runs finished
  `BATTLE_MAP_TERRAIN_OK`.

The frames confirm the geography lines up: ownship on the Surfers Paradise
spawn with the Broadwater and the motorsport park inland, Burleigh Heads to the
south, Helensvale and Nerang to the west, and Coolangatta Airport and Tweed
Heads to the north in the 40 km view — with the 50 km theatre ending in a
straight edge beyond them, as it should. At 60° the coastline runs to a horizon
and the grid, range rings, labels and route stay attached to the ground they
name.

Two things this did not measure. There is no phone frame rate figure: these are
software-rendered desktop frames, and the map's cost on a Mali GPU at 60 Hz is
unestablished. And no physical touchscreen or Bluetooth controller was
exercised — the gestures and the pad path are covered by synthetic events in
the headless tests, which is not the same as a finger.

One pre-existing artifact is more visible under a lean than it was flat: a
streamed detail chunk is modulated by a flat `Color(0.72, 0.88, 0.81)` while the
overview goes through the map shader, so over dark ocean the two do not match
and the chunk edge shows. The shipped map modulated detail the same way, so
this is not a change from this work; matching the two is a separate piece.

