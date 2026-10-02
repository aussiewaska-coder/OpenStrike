# The theatre's regions — 2 October 2026

Phase 3 of the Battle Map V2 brief. Phases 1 and 2 gave the map a camera and made
it change what it *says* as you pull back; this puts the ground itself under it.
A district is now either ours, theirs, fought over, or nobody's, the line where
two organised sides meet is derived from that rather than drawn by hand, and the
whole thing is a wash you can still read the coastline through.

Nothing in flight, weapons, targeting, terrain streaming or enemy combat was
rewritten. The regions are a new layer of information over the theatre the game
already streams, not a second world to keep in sync with it — there is no
map-only target identity here, and the districts have no contact handles.

## Thirty-two districts, not a honeycomb

The brief forbids hundreds of hexagons and asks for 15–40 regions that follow
areas OpenStrike already represents. `scripts/war/war_regions.gd` therefore
starts from the coastline, the Broadwater, the Nerang and Coomera river lines,
the escarpment west of the ranges and the state border along the McPherson Range,
and names each district for a place the game already knows — `map_places.gd`
supplies COOLANGATTA, TWEED HEADS, NERANG, SURFERS PARADISE and the rest, so a
region is a thing a pilot would point at, not a grid cell with a code.

The geometry is one shared lattice: eight rows of seven cells between nine
latitude lines and eight longitude lines, with the border row replaced per column
by the crest of the range and the eastern column measured back from a shoreline
that is charted separately at every latitude, because the coast swings east at
Point Danger and again at Tugun and a fixed meridian would cut headlands in half.
Each region is a *set of cells*, so two neighbours repeat the same lattice points
and their common edge is identical to the metre. That is the property everything
else depends on: gaps are impossible by construction, and the front line can be
derived instead of maintained.

## The geography does not know who is winning

`scripts/war/war_control.gd` is the situation laid over that map of districts.
Phase 3 asked for test ownership, so the numbers are seeded — each district
carries the owner and `strategic_value` it is authored with, and the seed per
owner is the brief's own `RegionState`: `air_control`, `ground_control`, `supply`,
`infrastructure`, `intel_level`. Value scales the hold on ground and air, because
the same side holding a valley nobody drives through is not the side holding the
airfield.

The split matters for Phase 5. The renderer asks the geography where things are
and the control module who holds them; when the WarDirector arrives it calls
`set_owner` and reads `state_of`, and no rendering path is rewritten to put a
simulation behind them. `set_owner` returns false when nothing moved so the map
cannot blink over a report that changed nothing, and it emits `changed(id)` for
whatever is listening.

## The front is an edge, not a stroke

`front()` walks the adjacency table once per pair and returns every shared segment
whose two owners are not on the same side — in world metres, with its midpoint and
the direction the pressure runs. A friendly-against-enemy edge is a `FRONT`; an
edge with contested ground on exactly one side is a `CONTACT`, drawn faint and
left unarrowed, because the hatch on the far side already says that district is
not settled. Two contested neighbours are the same mixed situation on both sides
and two districts of one bloc share a road, not a front: neither draws a line.

Pressure runs downhill, from whichever side holds its district harder toward the
one that holds it less, and is projected as two points on the ground rather than
as an angle — so the chevron turns with the map. The result is cached and marked
stale by `set_owner`, which is what makes "the line moves when territory changes"
a property of the data instead of a promise: `tests/war_control_test.gd` takes
TWEED HEADS from ENEMY to FRIENDLY and asserts the coolangatta/tweed_heads segment
is gone, a tweed_heads/kingscliff one has appeared, and restoring the opening
situation reproduces the original front exactly.

## Drawing it without hiding it

`scripts/battle_map/battle_map_territory.gd` owns the look and no camera. It is
handed the map's projection and the ground the map can currently see, culls by
district bounds, and hands back screen geometry: fills, boundary strokes, hatch
dashes and front marks. The canvas draws it first, under everything else, so the
grid, the symbols and the place names all read on top of the war rather than
through it.

A held district is a wash at alpha 0.17 — the satellite imagery is the information
underneath, and an overlay that hides it is a choropleth, not a command map.
Contested ground takes less wash (0.07) and gets two families of short dashes
laid across each other in world space, one blue and one red, placed by the same
point-in-polygon rule the geography uses so a claim never spills out of the ground
it is claimed over. That is the brief's "mixed control rather than another solid
colour": both claims present at once, and the pattern belongs to the terrain, so
leaning the camera leans the hatch with it.

The line is drawn in near-white at 2.5 px for a front and 1 px at half strength
for a contact edge, with the chevron in the colour of the weaker side — where the
ground battle is, and which way it is going.

## One bug the phase found on its way in

The headless war check came back with front segments in the data and none on the
map, and tracing it turned up a `Rect2` built from two corners instead of a
position and a size in `tactical_map_canvas._visible_ground()`. The theatre's own
box ran from −25 km to +25 km, which as a *size* ended at the centre, so every
cull against it dropped everything east and south of ownship's middle: sixteen
districts on screen instead of thirty-two, seven front edges instead of twenty,
and not one chevron, because the river the front runs along is in the clipped
half. It had not shown up before because the ground grid it also feeds is skipped
entirely at the flat default camera. `_check_the_cull_box_reaches_the_ground_it_shows`
now asserts the far side of the theatre counts as visible, which is the smallest
possible test for "content silently goes missing at the edge of the map".

## A layer that can stop saying NONE

`battle_map_layers.gd` already carried the war layers with `source: false` so the
rail could show them disabled instead of faking intelligence. Territory now
reports its source at runtime: `set_source(id, available)`, called by the canvas's
`set_war`, and `load_settings()` reads every layer rather than only the ones with
data, so a toggle the pilot left alone while the layer was empty is honoured when
the data arrives instead of being silently reset. `main.gd` hands the panel the
corridor's districts when a theatre loads and `null` when it has none — a second
theatre with nothing authored gets an honest empty layer, not another coastline
drawn over it.

The war is also a density of information, which is what the level matrix was for:
territory belongs to THEATRE and REGIONAL and fades out below 6.5 km, where the
question in front of you is which aircraft, not who owns the country.

## Validation

Headless: `tests/war_regions_test.gd` and `tests/war_control_test.gd` are new, and
`tests/battle_map_zoom_test.gd` gained the war-arrives and cull-box sections. The
corridor's geometry is sampled on a 41 × 41 grid between the lattice lines and
must come back with no unclaimed ground and no overlap; every gazetteer place the
game already names has to sit inside the district it is named for; Sydney is
refused — and a refusal now also empties the tables rather than leaving the
corridor seated behind it, which is phase 5's finding, because `WarDirector.setup`
validates whatever lattice it is handed and a stale one is a campaign fighting over
ground the world no longer contains. The full suite is 137/137.

`tools/check_battle_map_terrain.gd` grew a war section that photographs the same
camera with the overlay on and off, and measures the pair:

```
territory: changed=0.651 detail=0.0754->0.0599 luminance=0.244->0.284
war: districts=32 hatch=117 edges=20 chevrons=4 wash=0.17
```

Sixty-five percent of the sampled pixels differ, so the war is on the map; the
picture's own luminance spread falls by a fifth rather than collapsing, which is
what "retains underlying terrain visibility" looks like as a number, and the mean
moves by 0.04, so the wash is not repainting the theatre. The batch the canvas is
handed covers all thirty-two districts with 117 hatch strokes across the contested
ones and twenty front edges, four of them carrying a chevron. The frames are
`/tmp/bmt-h_territory_regional.png` through `-l_territory_off.png`, and the last
one is the assertion that switching the layer off gives back the Phase 2 map to
within 2% of its pixels.

The same section asserts the density rule in pictures: at 2.6 km the layer has
faded to nothing, and at 12 km leaning the camera moves the hatch with the ground
it belongs to rather than sliding a screen pattern over it.

## What this does not prove

No simulation. The ownership is the authored opening situation, and nothing
changes it while you fly; the front moves because `set_owner` is called in a test,
not because a battle happened.

No phone frame rate. Everything here is software-rendered desktop frames and
headless maths. The shape worth measuring on a device is the theatre view:
thirty-two polygon fills, a hundred and fifty polylines of which most are
two-point hatch strokes, twenty front lines and four chevrons — and none of it at
all below the tactical boundary, which is the reason the density rule is worth
having.

And the districts are one theatre's table, in absolute coordinates. The refusal is
tested and the panel reports it, but a second corridor needs its own authored
regions before the war layer means anything there.
