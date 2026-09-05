# Home throttle combination and corridor landmarks

Hold Home/Guide and press D-pad up/down to increase/decrease jet throttle.
Home alone and D-pad alone leave throttle unchanged. Plain D-pad up/down keeps
camera zoom. Zoom events are suppressed in jet flight while Home is held;
releasing Home before the D-pad cannot generate an extra zoom press. Settings
and tactical-map navigation remain isolated from flight input.

The controller mapper exposes a separate throttle modifier plus the two
throttle directions. Layout version 2 migrates the previous Home/Turbo defaults
to this combination while preserving other custom assignments. Versioned custom
layouts reload without being migrated repeatedly.

Q1, Soul and Ocean disappeared because their layout accepted only
`au_qld_surfers`, while startup now selects the enclosing 50 km
`au_gold_coast_tweed_corridor`. The models and coordinates were present, but
`populate()` received an empty layout. Both theatres now share the same landmark
layout and OSM visual-suppression points. Unrelated theatres still spawn none.

The failing corridor regression initially spawned zero towers. After the fix,
it instantiates all three real GLBs, verifies visible geometry at the corridor's
converted coordinates and ground height, matches their suppression positions,
and verifies cleanup on theatre change. Controller checks cover combination
routing through the real action dispatcher, release ordering, persistent
throttle, menus and saved-layout migration. Existing hero, map-footprint,
location-selection, controller-mapper and tactical-map checks also pass.
