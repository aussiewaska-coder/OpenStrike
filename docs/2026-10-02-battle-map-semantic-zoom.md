# Battle map semantics — 2 October 2026

Phase 2 of the Battle Map V2 brief. The camera that landed in Phase 1 stays as
it was; what changes is what the map has to say about the ground it is looking
at. Zooming out is now a different report rather than the same report smaller,
and the acceptance test for the phase is that a theatre frame and a tactical
frame of the same five-ship are not the same picture.

Nothing in flight, weapons, targeting, terrain streaming or enemy combat was
rewritten. The map still draws the tracker's own contacts, the streaming system
still publishes the same layer dictionary, and there is no second, map-only
target identity anywhere in this work.

## Three densities, one camera

`scripts/battle_map/battle_map_layers.gd` decides what level the map is at and
what each level is allowed to draw. TACTICAL below 6.5 km, REGIONAL to 24 km,
THEATRE above 29 km — and those are two-number boundaries on purpose. A single
threshold makes the map flip between two reports several times across one pinch,
which reads as the picture breaking rather than zooming. Each layer carries the
alpha it wants at each level and fades toward it, so a density change dissolves
one report into another instead of switching screens.

- **TACTICAL** draws every track as itself: symbol, name, kind colour, range
  rings, a 1000 m grid. This is the map a pilot shoots from.
- **REGIONAL** folds tracks that are close enough to be one formation into one
  marker and leaves a lone track alone. A four-ship is a report; a singleton is
  still itself.
- **THEATRE** keeps the same rule with a merge distance four times wider, so the
  formations that were separate reports out south become one, and what is left is
  mostly groups. A lone site a long way from anything is still one site, and
  naming it is not a lie about precision — "GROUND GROUP 1 · 1" is.

The level is named in the panel header and in the map's own border, so the
player can tell which kind of answer they are looking at.

## Clustering is a property of the ground

`scripts/battle_map/battle_map_markers.gd` buckets contacts into world-aligned
cells for the current density and merges neighbouring buckets with union-find
while their centroids stay within half a cell of each other. Two consequences
matter more than the algorithm:

The camera is not an input. Grouping depends on the contacts and the density, so
panning costs nothing, a formation does not re-cluster as it crosses the middle
of the screen, and what a tap selects does not depend on where the view happens
to be. The module owns no camera at all — it is handed a projection callable for
picking and nothing else.

Groups are pooled records keyed by their cell, so a patch of ground keeps its
number while it holds the same sort of thing. That pooling is also the phase's
one real bug: every live record is zeroed at the top of a rebuild, so a record
whose count had dropped to zero was handed out again while a cell still pointed
at it, and a theatre view drew seven tracks as ten. A record is free only when it
is empty *and* unregistered now.

A rebuild is gated by a signature over handles, rounded positions and velocities,
so a map that has not changed returns the same array without recomputing anything
— asserted directly, by identity, in `tests/battle_map_markers_test.gd`.

## A group is a report, not a target

The spec asked that the map reuse the existing target identity rather than
inventing one, and this is where that constraint bites. A group carries the
tracker's own handles. Tapping one selects it, opens its card and flies the
camera if asked — and does not lock a weapon, because "that formation" is not a
thing a missile can be given. `ASSIGN` on the card resolves the nearest member by
ground distance and emits the identical `contact_selected` signal a tactical tap
would, which reaches the same `main._select_map_contact` → `_tracker.select_contact`
path that has always owned the lock. `FLY TO` ends inside the tactical band, so
the members of the report become individually tappable tracks at the other end of
the glide — the same contract a double tap already had.

## The card

The selection card reports what the tracker actually knows: classification,
count, ceiling, how many members are moving, the mean course, ground range and
compass bearing from ownship, and the name `ASSIGN` would hand the weapon. Range
is measured over the ground with the wasted altitude printed beside it, not
folded into a slant-range number, so the distance and the target selection can
never disagree.

Fields the tracker cannot answer are not printed at all. The brief's example card
lists track confidence and last update; `target_tracker.gd` has no such state, so
neither does the card. An MFD that guesses is worse than one that says nothing.

It refreshes four times a second rather than every frame, clears when its subject
is shot down or the panel closes, and keeps a group's report alive as the camera
flies in by re-deriving the group from its label, falling back to the handles it
captured at the tap.

## Layers, and the ones that are empty

The same module carries the layer table — contacts, sweep, places, route, grid,
and the seven war layers the later phases will fill: territory, air control,
radar coverage, SAM coverage, ground forces, missions, intelligence. Each has a
`source` flag. The five with data behind them today toggle live and persist to
`user://map_layers.cfg`. The seven without are shown in the rail disabled and
labelled `· NONE`, and a tap on one says so in the status line rather than
drawing an empty overlay. Decluttering is a Phase 2 requirement; inventing
intelligence to fill the buttons is a Phase 3 job.

The Layers section sits at the head of the rail. A phone in landscape shows two
of its twenty-odd rows, and clutter is the reason anyone opens the panel.

## Validation

Headless suite: 135 of 135 tests pass, including the four that cover this phase —
`tests/battle_map_layers_test.gd` (the density ladder changes on hysteresis and
not on a single boundary, fades start and finish, a sourceless layer can never
be drawn, toggles persist), `tests/battle_map_markers_test.gd` (clustering groups
what is close and keeps what is alone, a group reports its members, a wide
formation straddling a cell line is still one marker, labels survive the tracks
moving and stay within their bound, an unchanged contact set returns the identical array, and
a tap reaches a formation), `tests/battle_map_zoom_test.gd` (what each density
draws and taps on the wired canvas, that layers genuinely declutter it, that a
group tap locks nothing, and that a double tap flies in far enough to open the
group it flew onto) and `tests/battle_map_card_test.gd` (the card's numbers
against hand-calculated values, that a formation is a report rather than a
target, the 4 Hz refresh, the card dying with its subject, and the layer rail
saying which of its buttons can do anything).

`tactical_mfd_test.gd` and `tactical_places_test.gd` still pass unmodified: the
canvas kept every property and method the shipped map addressed it with.

Two render checks run under a real Compatibility renderer, because headless never
compiles the map shader:

- `tools/check_battle_map.gd` gained a density section that draws the same six
  tracks at 40 km, 18 km and 2.6 km and asserts the *report* changes, printing
  each one: `AIR GROUP 1 of 6` at theatre, `AIR GROUP 1 of 5, SHEET` at regional —
  the lone jet folds into the formation only when the merge is wide enough to
  reach it — and six named tracks at tactical. The theatre and tactical frames are
  also compared pixel by pixel so that a rescaled picture cannot pass as a
  changed one. `BATTLE_MAP_RENDER_OK`.
- `tools/check_battle_map_terrain.gd` now asserts the tap a player actually makes,
  not just the raw picker: at each of its five camera states over GOLD COAST //
  TWEED CORRIDOR, every contact drawn on screen must be reachable — as itself, or
  as a member of the group its symbol was folded into. That is the property that
  keeps clustering from silently hiding a track. Cold, it reached the theatre in
  119 s and finished `BATTLE_MAP_TERRAIN_OK`.

The MFD panel's own visual capture (`tests/tactical_mfd_test.gd` with
`--visual-out=`, under xvfb) now selects a track and then a formation before it
photographs each viewport, so the frames show the card and the layer rail rather
than an empty panel. At 1280×720 the rail reads Contacts, Radar sweep, Place
names, Route, Tactical grid — live — then Territory, Air control, Radar coverage
and SAM coverage, each dimmed and marked `· NONE`.

## What this does not prove

No phone frame rate. Everything here is software-rendered desktop frames and
headless maths; the cost of a hundred tracks with a glide running on a Mali GPU
is unestablished, and is the first thing to measure against a real device.

No finger and no controller. The taps, glides and toggles are driven by synthetic
events.

And the war layers are honest emptiness: seven of the twelve are declared, named,
visible in the rail and refused on tap, with nothing behind them until the region
and WarDirector phases put something there. One cosmetic known issue survives
from the frames: at 640×360 a group's label can sit under an adjacent track's
name box, because markers do not yet push each other apart.
