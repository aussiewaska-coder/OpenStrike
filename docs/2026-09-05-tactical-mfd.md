# Tactical MFD and waypoint guidance

Y opens and closes the tactical map. The action is also available in the custom
controller mapper. Flight pauses for planning; the radar sweep remains animated.
Closing the display preserves other pause reasons, including a disconnected
controller. Map input cannot also fire weapons, move the camera or open Settings.

The north-up map shows ownship, known enemy contacts, selected weapon lock and
the remaining waypoint route. The top keys select fixed 1, 2, 5, 10, 20 and 40 km
ranges. Pinch or mouse wheel zoom continuously; drag pans and Ownship restores
following. Side controls select Satellite, Simple and Terrain displays. A subtle
scanline treatment, vignette, range rings and rotating sweep provide the MFD look.

Satellite reuses the loaded theatre aerial overview and resident detail textures.
Simple uses elevation-derived land/water shading and contour lines; Terrain adds
height tinting and shaded relief. Both use the existing elevation grid. Missing
layers display a labelled tactical grid instead of invented geographic detail.
No new imagery provider or download queue is introduced. Closing the map releases
its texture references so it cannot prevent normal terrain cache eviction.

Tap a contact to select its existing tracker handle and weapon lock. Selection
does not force camera tracking. Destroyed contacts and contacts outside the
existing 40 km lock limit cannot be selected. Radar styling does not add a new
detection simulation: it displays the game's known contact positions.

Add WP switches taps to route plotting, with up to twelve points inside the
theatre. Next WP skips the current leg; Clear route removes the route. A point
completes within 250 horizontal metres, regardless of flight altitude. Navigation
is separate from weapon targeting and is cleared on a theatre change. The route
lasts for the current session; it is not saved to disk.

A cyan waypoint marker, off-screen direction arrow, distance and compass bearing
remain available in cockpit and every external view. The edge marker leaves
space for the persistent navigation readout.

Validation: the complete headless suite passed, 73/73 tests. Targeted map,
tracker and mapper tests passed again after final changes. Coverage includes
Y toggle, independent pause reasons, input isolation, contact locking, projection
and picking at multiple ranges, pinch and drag without accidental taps, route
progression, bounds and 640×360, 360×640 and 1280×720 layouts. Compatibility-rendered
fixtures were inspected for all styles and waypoint cues ahead and behind.
Visual fixtures use synthetic elevation and optionally a cached aerial tile;
they test rendering, not geographic alignment of those two fixture layers.
Physical touchscreen and Bluetooth hardware were not exercised in this run.
