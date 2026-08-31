# OpenStrike

Native Android isometric helicopter-combat proof of concept built with Godot
4.7. Terrain comes in two forms: small **packaged** theatres that ship inside
the APK, and large **streamed** theatres that pull real elevation and aerial
imagery from public map services and cache them to disk.

## What works

- Foreground-only Android location access through `OpenStrikeLocation`.
- Nearest prepared-region selection without saving raw coordinates.
- Editor fallback to the Surfers Paradise, Gold Coast demo theatre.
- A packaged 4 km x 4 km heightmap derived from NASA SRTM elevation data.
- A streamed 36 km Gold Coast / Tweed corridor reaching 25 km inland and south
  to Tweed Heads, at roughly 10 cm aerial imagery near the aircraft.
- Offline OpenStreetMap building positions and Gold Coast shoreline geometry
  (packaged theatres only).
- Runtime terrain mesh generation and loading of the supplied helicopter GLB.
- Native Android Bluetooth/HID gamepad discovery and hot-plug handling.
- Abstract dual-stick, shoulder-button, stick-click and D-pad controls with
  configurable dead-zone/response values.
- Automatic pause on controller disconnect and automatic resume after reconnect.

## Theatres

`data/regions/catalog.json` lists every installed theatre. An entry with
`"streamed": true` is fetched at run time; anything else loads packaged assets.
The two currently shipped overlap — the packaged Surfers box sits inside the
streamed corridor — so the on-screen **SWITCH THEATRE** button cycles between
them.

| | Surfers Paradise | Gold Coast / Tweed corridor |
| --- | --- | --- |
| Size | 4 km | 36 km |
| Source | packaged in the APK | streamed and cached |
| Elevation | SRTM crop, ~16 m/px | Terrarium z12, ~34 m/px |
| Imagery | one 4096 px aerial | ~1.5 m/px near the aircraft |
| Relief | 62 m | 1096 m |
| Buildings | 2,373 OSM footprints | none yet |

## Streamed theatres

The elevation grid for a whole region is small — the 36 km corridor is 30
Terrarium tiles, under a megabyte — so it is fetched once and kept resident,
and every height query reads from it.

Imagery is the opposite problem. Covering 36 km at the imagery's true 10 cm
resolution would need a 360,000 pixel texture, so the region is split into a
grid of chunks (12 x 12 by default, 3 km each). Every chunk starts on a single
region-wide overview image; the sixteen chunks nearest the aircraft are then
re-textured at full detail and released again as it flies on. Chunk meshes all
carry region-wide UVs, and a detailed chunk just remaps its slice back over
0..1 with the material's `uv1_scale` / `uv1_offset`.

Sources, all free and none needing an API key:

- **Elevation** — Mapzen/Terrarium tiles from AWS Open Data
  `elevation-tiles-prod`, decoded as `R*256 + G + B/256 - 32768` metres.
  Zoom 12 is ~34 m/px, which matches SRTM's ~30 m native sampling; higher
  zooms only interpolate and are not worth the bandwidth.
- **Imagery** — the Queensland Government `LatestStateProgram_AllUsers` image
  service, which resolves individual people on the beach and covers the whole
  corridor including across the NSW border. NSW SIX is wired as a fallback for
  areas Queensland does not carry; it caps requests at 1024 px where Queensland
  allows 4100.

Both are requested in EPSG:4326 so the returned images are linear in
latitude/longitude and share one UV space with the elevation grid.

Everything fetched is written to `user://map_cache` and re-read on later
launches, so an area needs the network only the first time it is flown. The
`INTERNET` permission is enabled in `export_presets.cfg` for this reason.

**This is the one place OpenStrike departs from being fully offline.** A
packaged theatre still needs no network at all. A streamed theatre needs
connectivity the first time you fly a given piece of ground; after that the
cache serves it. There is no pre-download step yet, so flying somewhere new
with no signal shows the overview imagery rather than detail.

### Known gaps

- No pre-caching: new ground needs signal the first time.
- No buildings in streamed theatres. Scaling the packaged approach to the
  corridor means roughly 120,000 OpenStreetMap footprints, which needs a
  filtering pass that has not been designed yet.
- Terrarium carries occasional single-pixel voids — the corridor has two,
  inland near Advancetown Lake, reading below -700 m. `ELEVATION_FLOOR_M` in
  `tile_client.gd` clamps them off; genuine negatives here are dredged canals
  no deeper than about -20 m and open ocean reads a flat 0.

## Run in Godot

Open this directory in Godot 4.7.2 and run `scenes/main.tscn`. Desktop/editor
runs automatically select the demo region.

For Android export, install the Godot Android build template, enable Gradle
build in the Android preset, and leave the `OpenStrikeLocation` editor plugin
enabled. The AAR files are already packaged under
`addons/OpenStrikeLocation/bin`.

Pair the Bluetooth controller in Android system settings before starting the
game. OpenStrike uses Godot's standard Android joypad path, so it does not need
Bluetooth scanning permissions. The in-game diagnostic panel shows the detected
controller name, both stick vectors, and L1/R1/L3 state.

Sticks follow the DJI Mode 2 layout — throttle and yaw on the left, cyclic on
the right — and the aircraft flies like a drone in position hold: the stick
commands a speed rather than a push, so centring it brakes hard and stops
instead of coasting, and the airframe's tilt is derived from the speed it is
actually carrying. Altitude is still commanded as height above the terrain
rather than an absolute hold, so the aircraft rides the contour.

### MVP controller map

| Control | Action |
| --- | --- |
| Left stick up/down | Throttle: climb/descend |
| Left stick left/right | Yaw left/right |
| Right stick up/down | Cyclic: fly forward/backward |
| Right stick left/right | Cyclic: strafe left/right |
| L2 / R2 | Tactical view: orbit the camera. Travel view: sweep around a locked ground point |
| R1 | Cannon |
| L1 | Rockets |
| R3 | Toggle tactical / low-angle travel follow camera |
| L3 | Context/extraction |
| D-pad left/right | Previous/next target |
| D-pad up/down | Camera zoom in/out, continuing into the attack close-up |

### Camera

Zooming in past the tactical range enters the attack close-up: the camera
continues to close, but its height falls away faster than its distance, so it
sinks from a top-down view to roughly 19 m behind and 9 m above the aircraft
while the field of view widens from 42 to 78 degrees for forced perspective. A
minimum ground clearance keeps the low camera out of rising terrain.

The attack close-up also carries a gunsight, faded in on the same blend. The
model is an AH-64D, so the round is the M230's 30 mm: 805 m/s at the muzzle,
losing speed exponentially, with gravity doing the rest. The sight marches that
round from the muzzle along the nose until it crosses the terrain height field,
and shows the result as a continuously computed impact point — a pipper where
the rounds will land, with the slant range and time of flight beside the
crosshair. Past 4 km with no ground crossing there is no firing solution, and
the pipper and readouts blank rather than guess. No weapon fires yet, so these
figures are a sight, not a firing solution; every one of them is an export to
replace when a real cannon lands.

The airframe drifts. In a hover it wanders on three sines at unrelated rates —
about 0.6 m of vertical bob and a degree of sway — and a change of velocity
rocks it harder, so acceleration and braking are visible in the attitude. The
drift rides on the visual child rather than the anchor, leaving terrain
following and the world clamps untouched, but the camera and the gunsight both
track the visual: the drift moves the aim, and holding a pipper on a target is
real stick work.

In travel view (R3), L2/R2 no longer steer the trailing heading. The first
deflection drops a pivot on the ground beneath the aircraft and locks it to the
world; the camera then sweeps around that point and keeps looking at it, so the
helicopter can fly out of frame mid-sweep. Releasing the trigger hands the
sweep's final heading back to the follow camera.

## Tests

Head-less `SceneTree` scripts, run one at a time:

```sh
godot --headless --script tests/map_tiles_test.gd
godot --headless --script tests/height_field_test.gd
godot --headless --script tests/terrain_sampling_test.gd
godot --headless --script tests/helicopter_controls_test.gd
godot --headless --script tests/gamepad_input_test.gd
godot --headless --script tests/camera_orbit_lock_test.gd
godot --headless --script tests/camera_zoom_profile_test.gd
godot --headless --script tests/ballistics_test.gd
godot --headless --script tests/airframe_motion_test.gd
```

`map_tiles_test.gd` pins the coordinate chain — region bounds, tile range,
Mercator round trip and Terrarium decoding — against values sampled from the
live mosaic and checked against known ground elevations (Surfers Paradise
beach 8 m, Hinze Dam 83 m, Springbrook 635 m, Tweed Heads 7 m).

## Location privacy

The plug-in requests foreground location only. It does not request background
location, transmit location, or persist raw latitude/longitude. Location
updates stop as soon as a prepared theatre has been selected. If permission is
declined, the game remains usable with a manually selected prepared region.

Streamed imagery is requested by map tile and bounding box, never by device
position, so the map services are not told where the player is.

## Rebuild the packaged heightmap

Download `S29E153.hgt.gz` from the source URL recorded in the region metadata,
then run:

```sh
python3 tools/build_terrain.py S29E153.hgt.gz \
  data/regions/au_qld_mt_coot_tha/region.json \
  --latitude -28.0023 --longitude 153.4310 \
  --output data/regions/au_qld_mt_coot_tha/heightmap.png
```

`tools/build_map_features.py` converts a bounded Overpass JSON extract into the
packaged building and coastline files. Map geometry is © OpenStreetMap
contributors and licensed under ODbL; see `data/regions/ATTRIBUTION.md`.

Note that `build_terrain.py` reads a single HGT tile and clamps samples that
fall outside it. The packaged Surfers box spans latitude -27.9843 to -28.0203
and so crosses the boundary between `S28E153` and `S29E153`; its northern edge
is therefore clamped rather than true elevation. Streamed theatres do not have
this problem — they mosaic every tile the region touches.
