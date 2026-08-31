# OpenStrike

Native Android isometric helicopter-combat proof of concept built with Godot
4.7. The current slice proves location-aware selection of a packaged,
real-elevation terrain region without requiring live GIS access during play.

## What works

- Foreground-only Android location access through `OpenStrikeLocation`.
- Nearest prepared-region selection without saving raw coordinates.
- Editor fallback to the Surfers Paradise, Gold Coast demo theatre.
- A packaged 4 km x 4 km heightmap derived from NASA SRTM elevation data.
- Offline OpenStreetMap building positions and Gold Coast shoreline geometry.
- Runtime terrain mesh generation and loading of the supplied helicopter GLB.
- Native Android Bluetooth/HID gamepad discovery and hot-plug handling.
- Abstract dual-stick, shoulder-button, stick-click and D-pad controls with
  configurable dead-zone/response values.
- Automatic pause on controller disconnect and automatic resume after reconnect.

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

### MVP controller map

| Control | Action |
| --- | --- |
| Left stick up/down | Fly forward/backward |
| Left stick left/right | Strafe left/right |
| Right stick left/right | Rotate/yaw |
| Right stick up/down | Climb/descend |
| L2 / R2 | Rotate camera right/left |
| R1 | Cannon |
| L1 | Rockets |
| R3 | Toggle tactical / low-angle travel follow camera |
| L3 | Context/extraction |
| D-pad left/right | Previous/next target |
| D-pad up/down | Camera zoom in/out |

## Location privacy

The plug-in requests foreground location only. It does not request background
location, transmit location, or persist raw latitude/longitude. Location
updates stop as soon as a prepared theatre has been selected. If permission is
declined, the game remains usable with a manually selected prepared region.

## Rebuild the demo heightmap

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
