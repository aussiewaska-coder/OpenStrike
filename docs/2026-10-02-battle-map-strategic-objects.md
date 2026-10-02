# What the war is fought over — 2 October 2026

Phase 4 of the Battle Map V2 brief. Phase 1 gave the map a camera, phase 2 made it
change what it *says* as you pull back, phase 3 put districts under it. This puts
the things those districts are contested *for* on the ground: airfields, launcher
sites, landmarks — each one at a position the world already publishes, and each one
selectable down to the entity it corresponds to.

The acceptance line is "selecting a strategic object on map resolves to meaningful
world data", and it is the reason nothing here is authored as a map symbol. The
flight, weapon, targeting, terrain, SAM and enemy-combat systems were not rewritten;
this phase reads them.

## Three sources the world already had

`scripts/war/war_objects.gd` builds its table out of things that exist for their own
sake:

- **Airfields** come from `runways.gd`. Every strip authored for the theatre is
  grouped by its ICAO code, and each aerodrome becomes one object whose `detail`
  carries its own runways — real ends, real headings, real lengths in metres. The
  position is the ARP the airport table publishes, so the symbol sits on the field
  the jet lands on.
- **SAM sites** come from `launcher_layout.gd`, the same layout
  `launcher_field.gd` scatters its launchers from. The sites are therefore at the
  positions hostiles actually spawn at, and their faction is the enemy's whatever the
  districts around them say — the opening layout puts enemy sites behind ground the
  war layer reports as friendly, which is a fact about this campaign rather than a
  bug to smooth over.
- **Landmarks** come from `hero_towers.gd`, at the lat/lon the terrain places the
  buildings from.

That is the whole set. The brief's nine types are declared, and six of them — forward
base, radar, command post, supply depot, ground force, aircraft group — have nothing
in this world to correspond to yet, so the table contains none of them and the map
draws none. The types are slots for the WarDirector to fill from entities it can
point at, not placeholders full of round numbers. `BRIDGE/INFRASTRUCTURE` is named
`INFRASTRUCTURE` because this theatre has no authored crossing, and a bridge is an
example of a class rather than the class.

## An id that cannot be mistaken for an entity

Launcher entities count from 1, drones from 100 000 and enemy jets from 200 000, so
strategic ids start at `FIRST_ID = 300000`, above every band. That is not tidiness:
the card shows a tracker handle for a site that has one, and an id that could be read
as an entity would let the map offer to lock something that does not exist.

A site with launchers standing at it carries those launchers' own entity ids in
`handles`. There is no second identity for the same SAM anywhere in this phase, which
is what makes the target chain work without a bridge: tapping the drawn site while a
launcher is alive under the finger answers with the *contact*, because the canvas asks
contacts first, and `ASSIGN TARGET` on the card takes the nearest of the site's live
handles and emits the same `contact_selected` signal a contact tap uses — through
`main._select_map_contact` into the real tracker, one lock path and it is the existing
one. With no live handle the card refuses in words
(`NO LIVE TRACK AT THIS OBJECT · ASSIGN needs a contact`). An airfield or a tower is
not shootable either, so its card says the same rather than quietly locking something
that does not exist.

## Every derived field, and where it came from

The brief's required fields are all present, and none of them is a number this table
invented:

| field | source |
| --- | --- |
| `region_id` | `war_regions.region_at(world_position)` — the district the ground is in |
| `intel_confidence` | that district's `intel_level` from `war_control` |
| `strategic_value` | a per-type `WEIGHT` scaled by the district's own authored value |
| `faction` | FRIENDLY for the aerodrome table's own airfields, ENEMY for the launcher layout's sites, the holding district's owner for a landmark |
| `health`, `operational_state` | the live bindings below |
| `source` | a string naming the file and record it was built from, shown on the card |

Two consequences worth stating: an object outside the district lattice gets `region_id`
empty and is rated at the middle of the scale rather than on nothing, and intel is a
property of the ground, so two sites in the same district are watched equally.

## What "still standing" means when the world is the only authority

`bind_launchers(positions)` is handed `launcher_field.launcher_positions()` — the truth
about which sites have a launcher at them — and matches handles to a site by the name
prefix the field gives its own clusters. Something reporting in makes the site seen,
sets health as launchers-live over the strongest it has ever been seen at, and gives it
`INTACT` or `DAMAGED`. Nothing reporting in, having once been seen, is `DESTROYED` at
health zero. Nothing ever seen is `UNCONFIRMED`: still on the map at the layout's
position, because a site the authored layout puts there is a fact about the route, but
drawn faint so it cannot look as certain as one with something standing at it.

The strongest-ever yardstick is what makes `DAMAGED` reachable at all. This field's
clusters hold one launcher each, so a ratio against the planned count could only ever
be 1.0 or 0.0, and "one launcher of two" was not a state the code could express.

`bind_structures(hit_index, damage)` asks the real building hit index for a vertical
ray at each landmark's own coordinate and measures what comes back against the world's
only published damage scale — the accumulated structural damage at which a building
starts to smoke. Half of it is the smoke point, twice it is nothing left standing. When
the chunk is not streamed in, the ray finds nothing and the object reports the authored
structure with `streamed: false` and no damage claimed, and the card says
`FOOTPRINT NOT STREAMED` rather than guessing.

## Drawn as ground, not as decals

`scripts/battle_map/battle_map_strategy.gd` decides nothing about the war; it is handed
the registry, the canvas's projection and the ground the camera can see, and returns
screen geometry. Three shapes a thumb can tell apart at a dozen pixels: a ring with its
real pavement across it for an airfield, a nose-up triangle for a site, an arch for a
structure — same blue and red as the control areas under them, so a symbol and the
ground it stands on cannot disagree about who holds what.

The pavement is drawn in world metres and projected like any other ground line, which
is the one thing on this map that says how long a strip actually is: lean the camera and
the runway foreshortens with the terrain instead of sliding over it. Glyphs are kept
upright, because a symbol is a report rather than a mark painted on the ground.

What the density rule does for this layer is drop names, not objects — the brief's
planning loop wants the pilot to fly *into* a site and keep seeing what it is. At
theatre range only objects at or above `THEATRE_LABEL_VALUE` are called out, nothing
below `DRAWN_VALUE` gets a symbol at all, and the type line appears under the name only
in the close view. Hundreds of abstract entities stay usable because the cull box and
the value floor say so, not because the renderer is fast.

## The card reads the world

Selecting an object opens the same panel the contacts use, filled from the registry
record and the district under it: `COOLANGATTA AIRPORT · AIRBASE · FRIENDLY`, the
strip count with the longest runway's own designator, length and heading
(`1 STRIP · 14 2492 m · HDG 140°`), the LAT/LON the ARP unwinds to, the holding
district by name, and the `source` line saying which file the row came from. A site
with launchers reporting in reads `1 LAUNCHER OF 1 · TRACK 7` and keeps
`ASSIGN TARGET` live; an unseen one reads `NOTHING SEEN HERE · POSITION FROM THE
LAYOUT`; a tower whose chunk is not resident reads `FOOTPRINT NOT STREAMED`. The
card refreshes through the map's own handle on the registry, so a site that stops
reporting between the tap and the next tick is not shown as what it was when the
finger came down.

## Cadence

One registry build per theatre load, geometry cached in the module, and the two live
bindings run when the map opens and at the same 1 Hz the panel already refreshes its
layer references at — never per frame. Drawing is culled to `_visible_ground()` plus
the value floor, so a dense theatre costs glyphs only for the ground on screen. No
strategic calculation happens while flying with the panel shut.

## Validation

Headless, the full suite is **139/139**. (`battle_map_controller_test.gd` needed one
solo re-run for the exit-time `1 resources still in use` line, which has been failing
intermittently for other tests in this repository as long as the suite has existed; the
test itself passes.)

`tests/war_objects_test.gd` is new, and every row in it is checked against
the thing it was built from rather than against the code that built it: the airfield's
lat/lon is the aerodrome table's ARP, its strip ends are 2 % apart from the length the
runway row publishes, the sites are at the centres `SITES.clusters_for` hands the
launcher field, the landmarks are at the hero towers' own coordinates, and each
`region_id` is what `war_regions.region_at` says about that point. The §9 field set is
asserted present with ids above `FIRST_ID` and no id handed out twice, the coordinate
round trip is under a metre, `strategic_value` is bounded by its type's `WEIGHT`, and
`intel_confidence` equals the district's `intel_level` from `war_control`. The
launcher lifecycle goes INTACT → DAMAGED (one of two ever seen) → DESTROYED →
UNCONFIRMED on a fresh theatre; the structure binding runs through the **real**
`BuildingDamageSystem` with a live hit index, including the answer from a chunk that is
not streamed in. Sydney is loaded with no geography at all and must report empty
districts, neutral towers, zero confidence and YSSY's three strips without disturbing
the corridor that was already loaded.

`tests/battle_map_strategy_test.gd` drives the real MFD and canvas over the corridor
registry: symbols land exactly on `world_to_screen`, red and blue follow faction, an
unconfirmed site is drawn at 0.38 of the layer's alpha, the cull box and the value
floor decide what is drawn rather than a special case, a tap gives the live contact
where one stands and the object otherwise, and the card's exact strings are asserted —
including `NO LIVE TRACK` on the refusal to assign an airfield, and `ASSIGN TARGET` on
a site producing the tracker's own `[21]`.

`tools/check_battle_map_terrain.gd` grew a strategic section after the territory one,
photographing the same camera with the layer handed a registry and without:

```
territory: changed=0.652 detail=0.0754->0.0599 luminance=0.244->0.284
war: districts=32 hatch=117 edges=20 chevrons=4 wash=0.17
objects: registry=10 regional symbols=10 changed=0.0187 detail=0.0599->0.0611
objects: theatre symbols=10/10 worth drawing, named=1 unconfirmed=6
airfield: OOL · longest strip drawn 288 px at 0.11538 px per metre = 2493 m, authored 2492 m
objects: lean painted=30 whole frame=0.0009
objects: tapped CITY NORTH SITE (SAM SITE) source=launcher_layout.gd · CITY NORTH district=surfers state=UNCONFIRMED
```

The territory line is the Phase 3 measurement repeated, unchanged, which is the point of
running the two overlays in one pass: `BATTLE_MAP_TERRAIN_OK` now covers the camera, the
densities, the districts and the objects over the same streamed theatre. The frames are
`/tmp/bmt4-m_objects_unmarked.png` through `-s_objects_selected.png` — the layer reported
empty, the same camera with a registry handed over, the theatre view, the airfield at
2.6 km, that lean with the layer off and on, and the site a tap resolved.

The corridor's table is ten objects: one aerodrome, six launcher sites and three
high-rise landmarks. None falls below the drawing floor, so all ten are symbolled at
theatre range and exactly one is named — the airfield, the only object both confirmed
and above the 0.6 labelling threshold; the six sites are unconfirmed positions, drawn
faint and checked to be faint at `alpha × 0.38`. The frame gains 1.9 % of its pixels
and the picture's own luminance spread goes *up* rather than down, because line work
over imagery adds edges instead of covering them.

Two of those numbers are the acceptance itself. The drawn runway at 2.6 km came out
288 px at 0.11538 px per metre, which unwinds to 2 493 m against the 2 492 m the
aerodrome table publishes: the map is drawing the actual strip, in ground metres,
through the same projection as the terrain. And the end-to-end tap ran on
`CITY NORTH SITE` — chosen as the worthiest object the exercise's own tracks stay off
of — which came back with `launcher_layout.gd · CITY NORTH` in district `surfers`, in
state `UNCONFIRMED`. The one place a tap *cannot* select an object is the airfield, and
that is the priority rule rather than a hole: the corridor's gazetteer puts its
COOLANGATTA AIRPORT label on the ARP to the metre, so this run's synthetic track stands
exactly there, and a live contact is what a tap must give.

The lean is measured rather than admired. With the layer off and on at the same tilted
camera, the batch's drawn point still sits within a pixel of `world_to_screen` of the
record it came from and is still tappable there, and the toggle changes pixels in the
symbol's own neighbourhood -- 30 of them at a two-pixel sample, which is the ring and
the pavement and not much else, because the label's dark backing over dark imagery is
below the difference threshold the frame comparisons use. The honest conclusion is that
the *geometric* assertions are what prove the overlay is welded to the ground; the pixel
count only proves it reaches the screen. A whole-frame fraction would have said nothing
useful either way: one glyph is 0.0009 of a 900×600 map.

## What this does not prove

No simulation, same as the districts under it. An object's state changes because a
launcher was shot down or because the player's own gun found a tower, and not because a
battle happened somewhere; an `UNCONFIRMED` site stays unconfirmed for a whole sortie
unless something reports in at it.

Three of the brief's nine types are all this world can currently answer for. A radar
station, a supply depot, a command post, a formation on the ground and an enemy airbase
need entities that exist for their own sake before they can be on the map, and until the
WarDirector can point at one, the honest statement is `· NONE`.

The structure binding only answers where the chunk is streamed in, so most of a theatre's
skyline reports `streamed: false` until you fly at it — the right answer, but it means a
tower's `DESTROYED` is something the player causes rather than something observed at
range.

No phone frame rate. Everything here is headless maths and software-rendered desktop
frames. The shape worth measuring on a device is the theatre view — ten glyphs, one
projected runway, and a value floor that keeps the count down as the registry grows --
and the 1 Hz binding pass, which is where a real campaign with hundreds of objects would
first show the caching working or not working.
