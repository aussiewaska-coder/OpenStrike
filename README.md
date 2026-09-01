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

Imagery is compressed to ETC2 on arrival -- 12 MB per 2048 px chunk becomes
2 MB for about 70 ms of CPU -- which is what makes the detail ladder affordable:
the six chunks nearest the aircraft carry 4096 px (0.37 m/px), the rest of the
resident twenty-four carry 2048 px (0.73 m/px), and everything else shows the
region overview. Ground resolution is set by how much ground one texture has to
cover rather than by the texture size alone, which is why the corridor is split
into 24 chunks a side rather than 12: the same request buys twice the detail. Texture memory lands near 82 MB against 256 MB uncompressed.

The overview and any NSW imagery are stitched from a grid of smaller requests
rather than asked for in one piece. Both servers cap the request, not the ground
it covers: NSW SIX refuses more than 1024 px, and Queensland answers 4100 px for
a 3 km chunk but returns HTTP 500 for the whole 36 km corridor.

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

## 30 mm chin cannon

Hold R1 and the chin turret slews to wherever the camera centre is pointing,
within its articulation limits; L3 fires. A selected orbit target outranks the
view, and with neither the gun eases back to the nose. The turret aims at a
world point rather than a direction, so it corrects itself as the airframe
drifts underneath it, and it stops at its limit rather than firing through the
aircraft.

Rounds are individually simulated - 805 m/s, gravity, drag, and the
helicopter's own velocity inherited at launch - and are stopped by a swept
segment test against OSM building volumes and the terrain height field. No
round is a RigidBody3D and no building has a physics node: `BuildingHitIndex`
mirrors the batched render mesh as footprints in a spatial grid, streaming in
and out with the chunks that own them.

The attack reticle and the live rounds share one `Ballistics` instance and one
`BallisticProfile`, and integrate through the same `advance()`. The agreement
is asserted to within 5 cm in `tests/pipper_agreement_test.gd`, including with
the aircraft moving sideways.

Impact material comes from `WorldSurfaceResolver`: buildings, then water, then
a terrain lookup that reads the compiled splat weights when a theatre has them.
Nothing keeps a second hand-written material map, so if it looks like sand it
behaves like sand. Until the world pipeline emits splat masks,
`set_splat_provider()` is unset and provisional elevation banding stands in.

Tuning is in `scripts/weapons/ballistic_profile.gd`.

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

Two flight models, switched with the CONTROLS button. **Arcade** is the default
and the one to pick up and fly: the stick commands a speed and the aircraft
holds a set height above the terrain. **Realistic** is the rotor model below.

In realistic mode the aircraft is flown as a helicopter, not driven. There is no input that sets
a velocity: the cyclic tilts the rotor disc, thrust acts along the disc normal,
and the horizontal part of that thrust is the only thing that accelerates the
airframe. Collective sets thrust magnitude and holds its position rather than
springing back, and the torque it generates yaws the nose, so the pedals move
whenever the collective does. `scripts/helicopter/rotor_model.gd` carries the
aerodynamics and the sources for their numbers: effective translational lift
between 16 and 20 kt, transverse-flow shudder at 12-15 kt just below it, ground
effect within a rotor diameter of the surface, and vortex ring state on a
vertical descent below translational lift. A hard floor at the minimum terrain
clearance stops the model flying you into a hill.

### MVP controller map

| Control | Action |
| --- | --- |
| Left stick | Cyclic: tilts the rotor disc, which is what moves the aircraft |
| Right stick left/right | Pedals: anti-torque yaw |
| Right stick up/down | Collective: rotor thrust, and it stays where you put it |
| Tap the screen | Pick a ground point to orbit; tap the sky to clear it |
| L2 / R2 | With a target: fly the aircraft around it, nose held on it. Without one: orbit the camera |
| Left stick up/down, while orbiting | Close or widen the orbit, down to 100 m |
| Y | Switch controls: arcade / realistic |
| R1 (hold) | Free look: the right stick aims the camera, and the view holds until released |
| X | Settings |
| L3 | Fire the 30 mm chin cannon |
| L1 | Rockets |
| R3 | Cycle cockpit / chase / orbit view |
| A | Context/extraction |
| D-pad left/right | Previous/next target |
| D-pad up/down | Camera zoom in/out, continuing into the attack close-up |

Both texture compression and building-mesh construction run on worker threads.
Each cost tens to hundreds of milliseconds and both land exactly when the
aircraft is moving into new ground, so on the main thread they stuttered
precisely when it was worst. Settings carries a graphics preset -- performance,
balanced, quality -- which trades how many detailed chunks stay resident, since
that is the lever that matters on a phone.

### Views

R3 cycles three perspectives. **Cockpit** is the default and takes the
airframe's transform outright, so pitch, roll and rotor drift are felt rather
than smoothed away; the mission panel is hidden and the screen carries the HUD
alone -- sight, range and time of flight, with airspeed, height above ground,
collective and heading on the glass, because with this flight model a pilot who
cannot see the collective cannot hold a hover. **Chase** flies astern and
follows the nose. **Orbit** keeps its heading and is where L2/R2 sweep a locked
ground point.

### Target orbit

Tapping the screen marches a ray against the height field -- there are no
collision shapes under the streamed terrain -- and drops a target on the ground,
shown on the HUD with its range. The triggers then fly the aircraft around that
point rather than moving the camera, holding the nose on it, at whatever radius
the aircraft happened to be at when the trigger came in. The left stick works
that radius while the triggers sweep, so the aircraft can be walked in toward a
target without letting go of the circle, down to a 100 m minimum. The commanded
radius is leashed to the one being flown: without that the command runs away
from the airframe -- reading 100 m while the aircraft is still 235 m out -- and
releasing the stick leaves a long unexplained drift inward. A radial term pulls the
aircraft back onto the circle so the orbit does not spiral. Both flight models
fly it: arcade takes the commanded velocity directly, while the rotor model has
no way to be handed a velocity and instead tilts the disc toward the one it
wants.

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

## The F-22

A second playable aircraft over the same theatre, which is what proves the
world carries both low-altitude rotor combat and high-speed fixed-wing flight
without a second map. Switch with **B**, or from the settings panel.

The flight model is an assisted arcade one: a lift curve and a drag polar, with
a fly-by-wire layer between the stick and the aerodynamics. Nothing in it turns
the aircraft. The stick commands a roll rate, the aircraft banks, the lift
vector tilts, and its horizontal component is the only sideways force there is.
Ease off and the assist holds the bank rather than rolling upright, which is the
difference between an aircraft and a spaceship.

Three behaviours fall out of single terms rather than being scripted. Induced
drag goes as the square of the lift coefficient, so hard turns bleed speed. The
load limiter caps pitch rate at `n = v * omega / g`, so flying faster is crisper
but turns wider. Control authority follows dynamic pressure, so low speed is
mushy. Corner speed is not a chosen number either: it is where the wing's limit
and the airframe's limit cross, at 155 m/s.

The envelope is deliberately compressed to roughly 90-260 m/s. At true Raptor
speed the 36 km corridor is a sixty-second dash and the terrain cannot stream
ahead of the aircraft. The drag constants are compressed to match, so they are
game-feel numbers rather than F-22 numbers; what is preserved is the shape.

Throttle is on the analog triggers, because proportional throttle and an
afterburner detent need an analog axis, and the orbit sweep those triggers carry
for the helicopter has no fixed-wing meaning. L1, R1 and L3 keep the meanings
learned on the helicopter.

There is no departure. The angle-of-attack limiter eases off nose-up commands
near the stall and actively pushes past it, the bank ceiling tightens as the
aircraft slows to whatever the wing can still hold a level turn at, and the
theatre edge warns and turns the aircraft back rather than walling it. Running
out of speed still leaves the aircraft mushing and sinking; it just cannot be
made to depart.

Known limitation: `streamed_terrain.gd` suppresses near-detail imagery above
45 m/s, which the jet is always above, so low passes render coarser than the
helicopter's until the streaming layer is given a fixed-wing budget.

## Tests

Head-less `SceneTree` scripts, run one at a time:

```sh
godot --headless --script tests/map_tiles_test.gd
godot --headless --script tests/height_field_test.gd
godot --headless --script tests/terrain_sampling_test.gd
godot --headless --script tests/rotor_model_test.gd
godot --headless --script tests/target_orbit_test.gd
godot --headless --script tests/helicopter_controls_test.gd
godot --headless --script tests/building_mesh_test.gd
godot --headless --script tests/gamepad_input_test.gd
godot --headless --script tests/camera_orbit_lock_test.gd
godot --headless --script tests/camera_zoom_profile_test.gd
godot --headless --script tests/ballistics_test.gd
godot --headless --script tests/airframe_motion_test.gd
godot --headless --script tests/aero_model_test.gd
godot --headless --script tests/flight_assist_test.gd
godot --headless --script tests/jet_controls_test.gd
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
