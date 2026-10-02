# The war, on its own clock — 2 October 2026

Phase 5 of the Battle Map V2 brief. Phases 1 to 4 gave the map a camera, a density
rule, districts with a derived front line, and the objects the fighting happens over.
None of it moved. This is the part that moves it while nobody is watching: a strength
for each side in every district, the battles the front implies, what each side has to
fight with, what the fighting takes off the buildings it passes, and how slowly that
comes back.

The acceptance line is *"run simulation without player — territory can naturally become
contested/change ownership"*, and §13's rule is the reason the module is 1 040 lines and
not a scene: **WarDirector owns DATA, BattleMap displays DATA, combat systems modify
DATA.** It extends `RefCounted`, has no node, no camera, no Control, no draw call, and no
per-frame work of any kind. It writes its answers through `war_control.gd` and
`war_objects.gd` — the two tables the map was already reading — so the territory layer
needed no new code path to start drawing ground that had moved.

## What owns what

Three modules, and exactly one of them is new.

`war_control.gd` owns who holds a district and the front that follows from it.
`war_objects.gd` owns what stands where, and the live bindings that decide whether a
launcher site has anything at it. The director owns the campaign numbers — presence,
air, supply, losses, battles, and the airbase operating model — and its only route out is
`set_owner`/`set_measures` on the first and `refresh_airbases`/`refresh_situation` on the
second. It reads `war_objects` for site health and never writes it: the launcher field is
the truth about its own launchers.

That single-ownership rule is what makes `damage_facility` refuse. It takes a registry id
and damages it only if the director models that object itself, which today means airfields.
Ask it to damage a launcher site and it returns `false`, because a site's launchers are the
field's to lose; ask it about an id above or below the registry and it returns `false`
rather than seating a stranger. There is no second table of strategic targets anywhere in
this phase, so there is nothing to fall out of step with the world.

## The clock, and what a tick costs

§14 asks for a strategic tick of 5–15 s of realtime, never per frame. `TICK_MIN 5.0`,
`TICK_MAX 15.0`, `TICK_DEFAULT 8.0`, adjustable with `set_tick_length`, which clamps.

`main.gd` hands it the frame time from `_process` and nothing else:

```gdscript
func _update_war(delta: float) -> void:
	if not _war.advance(delta):
		return
	_bind_launcher_state()
	var vehicle := _vehicle()
	if vehicle != null:
		_war.report_sighting(
			WAR_CONTROL.FRIENDLY,
			Vector2(vehicle.global_position.x, vehicle.global_position.z), 1.0)
```

`advance` accumulates and answers `false` until the clock rolls over, so the campaign runs
on the theatre's own seconds — with the battle map shut, and with no aircraft in the air at
all. Everything it does on a tick boundary is a *lookup*, never a calculation about the
frame: which launchers are still standing, where the aircraft is. Both are collected in the
tick that asked for them and read by the next one, which on an eight second clock is not
late by anything a campaign can notice.

Measured on this hardware, 200 ticks of a 32-district corridor with ten objects, six sites
and their launchers bound: **1.75 ms minimum, 1.97 median, 2.07 at p90, 3.64 worst**, at
which point the derived front still has five fights in it. Two milliseconds every eight
seconds is not a frame budget event; the brief's "avoid per-frame strategic calculations"
is satisfied by the tick existing, not by caching the arithmetic away. (The same 200 ticks
clocked 2.10/2.27/2.41/3.12 with two more campaigns running in the same process, which is
why the figure quoted is from a run of its own.)

Three hazards showed up in the wiring rather than in the tests, and all are now closed.
`advance` used to return `true` forever for a war that had never been seated, which turned
every frame into a tick of nothing; it returns `false` until `setup` has succeeded. And
`setup` used to validate before clearing, so a theatre it refused left the *previous*
theatre's districts seated — one war fighting over another map's ground. It now empties
itself first and stays empty on a refusal. And the same trap sat one layer below it, in
`war_regions.load_theatre`, which for the whole of phase 3 had kept the old lattice on a
refusal — correctly, as long as the only caller was a map that would not draw a null
geography, and wrong the moment a campaign could be seated on whatever the caller still held.
The corridor's own tests caught it by failing; the geography now clears before it validates,
and the loader in `main.gd` hands the director the same nulls it hands the map, so an
unauthored theatre gets a war that refuses to start rather than one fighting over the ground
it was last shown.

## One tick, in seven stages

`tick()` runs `_gather, _operate, _air, _fight, _reinforce, _settle, _publish`, in that
order, and the order is the argument: evidence is credited and decays first; the airfields
work out what they can fly before the air is computed; the air is computed before anyone
attacks across it; the fighting decides who is in contact, which is what reinforcement is
not allowed to thin; and only once the ground has moved is the map told. `under_fire` is
reset before the first stage, so it is always this tick's heat and never a running total.

`ticked`, `region_changed(id, owner, previous)`, `battle_opened`, `battle_closed(battle,
outcome)` and `facility_changed` are the announcements. `region_changed` fires only when
`war_control.set_owner` reports an actual move, which is what keeps a caller from making
the map blink over a report that changed nothing.

## Ground is held by being stood on

A district carries one presence per side, as a share of itself. The ground balance is the
difference between them — `blue − red`, in shares of the district, scaled by how much of the
district anybody is standing on at all. Three thresholds decide when that number is allowed
to change who owns a district, and each of them exists because of something the campaign did
before it was there.

`PRESENT_MIN 0.05` — below it, a side is not meaningfully in the district, and a district
neither side is in keeps the ground it had. Open country is not a trophy.

`OCCUPY_AT 0.5` — the contest is taken at full measure by half. Ground has to be occupied to
be conquered; whichever fraction happened to survive a battle cannot claim a town nobody is
standing in.

`OWNED_MIN 0.25` and `OWNED_KEEP 0.10` are the two that were found rather than designed. The
first version of this module derived ownership from the *ratio* between the sides, on the
argument that a ratio is what says who leans which way. It is also scale-free, and a
scale-free number cannot tell an occupation from a rearguard action. Measured on one
corridor district on a live front: across 200 ticks the defender held between a third and a
half of the ground the whole time, the attacker's share moved between 7 % and 18 %, and the
ratio of those two crossed the threshold that changes a district's colour **27 times** — and
before the weighting existed at all, 62 times, a tick apart. The defence never wavered. The
fraction of a token swung, and the map blinked.

So a district where both sides are standing in strength is contested whatever the balance
says, and it comes back out of that state only when the weaker claim has been driven under
`OWNED_KEEP` — someone has actually been cleared out. Entering contested costs 0.25 of the
other side's presence; leaving costs 0.10 of it, the same asymmetry the balance bands have
(`CONTESTED_BAND 0.35` to enter, `CONTESTED_HOLD 0.5` to leave), because the failure mode is
the same one: a single threshold is a knife edge, and a front's hot districts sit on it. The
seeded minority presences in the opening situation are 0.15 and 0.12, so both floors are
above them and no district is reclassified by the rule written to stop reclassifying them.

The third fix is deliberately late rather than clever. `SETTLE_TICKS 3` means a district
adopts a new owner only once the same candidate has held for three consecutive ticks, and
the delay sits in the *state* — `own["owner"]` is what `war_control` is told and what the
next tick's attacks are argued from — not in the announcement alone. That distinction is the
whole point: ownership feeds back into who attacks where, so a sector that flickers across
the boundary is flickering its own orders, and filtering only the report would have left the
war blinking while the map sat still. What is given up is three ticks of a front's news,
twenty-four seconds on the default clock. What is bought is that a district which crosses
the line and falls back inside a tick never reaches the player at all.

Two consequences are worth naming. A district is now *lost* by the defender being driven
under the floor, not by the attacker climbing to it — an offensive that is only bleeding the
other side cannot paint the map. And with the ratio gone, the published share and the
simulated balance agree exactly: at full occupation `share_of(g)` returns the holding side's
own presence, which is what the first tick of the corridor asserts district by district.

## Who owns the air

§11's −1..+1, per district, published on the 0..1 share axis the district states were
seeded with — 0.5 is the contested middle. That is the only place a signed simulation and
an unsigned renderer meet, and it happens once, in `share_of`/`_balance_of`, so nothing
translates twice.

The target the balance is steered toward (`AIR_RATE 0.35` per tick) is built from what can
actually fly there. Each airfield contributes sorties to its own district at full weight
and to the districts touching it at `COVER_NEAR 0.55` — adjacency rather than an invented
radius, because the lattice already knows what is next to what and no file in this
repository says how far a fighter's cover reaches in kilometres. Each surviving launcher
site subtracts `SITE_DENIAL 0.7` weighted by the health `war_objects` binds from the real
field. Whoever holds the ground holds some of the air above it (`GROUND_AIR 0.35`), and if
neither side has anything in the sky the balance falls back on the ground at half weight:
holding dirt is a weaker claim to the air than flying over it.

`air_superiority(faction)` averages that over the districts, and the two sides' shares
divide the same sky to within rounding — asserted, because a "35 % / 65 %" pair that sums
to 0.9 would mean the model has somewhere else the air goes.

## Battles, and how one ends

The front is `war_control`'s derived data, so battles are fought along edges the renderer
is already drawing — no second list of who faces whom. For every ordered pair along every
edge, one side attacks ground the other holds, and the assault is its own presence times
its air cover there, its supply, the district's value, the length of the front it is
attacking across and a small random spread; the defence is what the defender has, less the
air the attacker holds, times the infrastructure under it. `odds` and `intensity` fall out
of that.

Two decisions in there are the reason the campaign behaves like a front rather than like a
dice roll. The first is that **a front bleeds whether or not anyone is attacking**: each
side loses what the *other* side put in, scaled by `ATTRITION 0.035` and by a fatigue term
that grows with the battle's momentum and floors at 0.3. It is the artillery line, the raid
on the outpost, the convoy that did not arrive — and it is the only way ground changes hands
with nobody issuing orders, which is the acceptance. Costs being symmetric, an offensive
that cannot take ground quickly is the offensive that stops. The second is that only an
engagement past `STALE_AT 0.02` intensity moves ground at all, and it moves it by the amount
it is winning by, so a district goes contested before it goes friendly and nothing skips
across the band.

A battle is retired when it stops being fought, and the reason it stopped goes with it:
`SUCCESS` if the attacker now holds the target, `PARTIAL` if it is standing in it, `FAILED`
otherwise, with `EXHAUSTED` after `BATTLE_LIMIT 40` ticks and `CONTACT` for a sector that
is held at a cost. Those records are what Phase 6 will be handed, through
`active_battles()` — hardest fight first, and `reports()` is that list, because a mission
director should be given the war's own statement of where it is going rather than a list of
missions.

## An economy that can stall but not freeze

Supply was the phase's last problem and its most instructive one. Three tunings, tried in
order, produced: a blue landslide to 27 districts against 2 with the pool pinned at 1.00
while red sat at its floor (because assault, drive and garrison all read supply, so a
1.00-versus-0.25 gap is a rout, not a war); then both sides pinned at the floor with
ownership frozen from tick 20 to tick 200 — a photograph of a front, which is the same
failure in the other direction.

The table that works earns from three directions and spends in two. A side draws a fixed
allowance (`SUPPLY_BASE`) from the war effort behind it, which is what keeps a side that
has lost its rear area in the fight instead of dissolving; it earns from ground behind its
own line (`SUPPLY_INCOME` × the value of districts it holds that nobody is shooting at),
which is what conquest is for; and it rebuilds on a tick that spent nothing
(`SUPPLY_RECOVER`), which is what a quiet front is for. Against that it pays for every
district it holds (`SUPPLY_UPKEEP 0.002`), more the further its presence reaches past its own
line (`SUPPLY_LINE`), and outright for every assault (`SUPPLY_FIGHT`). Upkeep was 0.006 until
the frozen-front photograph above: twenty districts then cost 0.12 a tick, which is more than
those same twenty can earn back between battles, so that tuning stalled on arithmetic rather
than on the war — and the change that set the front moving again was halving the standing
cost, not raising any of the earnings. And the floor is
0.5, not 0: every coefficient read out of supply is between its floor value and its
full-stock value, so an exhausted side fights at about two-thirds tempo rather than
stopping — which is the difference between a campaign that pauses to refit and one that
freezes.

Ground on a live front earns nothing and still has to be fed, so a side that has taken more
districts than it can hold is poorer for them and slows down. That is the only thing in this
model that can make anything stop, and it is a consequence of the front line rather than a
timeout anyone sets.

## Fields: §10's gradual repair

A field's capacity is a staff estimate off the one published fact about it — `AIRFRAME_BASE
4` plus one airframe per 500 m of its longest strip, so the corridor's 2 492 m runway
generates eight aircraft and Sydney's 3 962 m eleven. Damage is a number; sorties are what
is left of the field times what it can fly; the state falls out of the damage, with
`DAMAGED_AT 0.2` and `OUT_OF_ACTION 0.75` as the two thresholds.

What is parked is seated at the full capacity, not at capacity times the stock figure the
district was seeded with. That sounds like a rounding choice and was a real bug: the first
thing `_operate` does on the first tick is recompute the complement from the damage, so a
field seated at seven of eight loses one aircraft on a tick in which nothing happened to it,
and the map is allowed to say so. A seat has to agree with the model's own next line.

Repair is `REPAIR_RATE 0.03` scaled by the holding side's supply and by how much of the air
above the field it owns, and neither term can take the rate to nothing — a crew with a
shovel and no fuel still works. Fighting in a district takes `RAIL_WEAR 0.006` of scaled
heat off everything standing in it, and `INFRA_WEAR 0.3` off the district's infrastructure,
which comes back at `INFRA_REPAIR 0.16`. That is §10's rule as written: no field is
eliminated by one bomb, and a shelled ramp reads DAMAGED, a cratered runway OUT OF ACTION,
and both come back unless the district stays under fire.

The wear-versus-repair balance is measured, and it is worth knowing that the corridor's one
airbase sits on the line and never once went out of action across 200 ticks: repair
outpaces what a settling front can do to it. A 0.35 hit lands as damage 0.329 and five of
eight aircraft on the very next tick — the wear is applied by the tick, not by the call —
reads `DAMAGED` until tick 16, and is whole again, damage gone and all eight parked, at
tick 29. Sixteen ticks is just over two minutes of the campaign's own clock, which is the
§10 answer: a field is knocked out of the fight for a while by one bomb, and is not ended
by it.

## What the flying world can say to it

Two verbs, both cheap, both at a tick boundary.

`report_sighting(faction, at, weight)` is a position, because a position is what a flight
has. Which district that is, is this module's question to answer, and it answers it with the
same `region_at` the map uses — so a pilot's track and a card's district row cannot
disagree. A sighting buys `SIGHTING_INTEL` immediately and joins an evidence pool that
decays at `EVIDENCE_DECAY 0.55` per tick, which is the difference between intelligence and
a survey: flying over a district three times tells you more than flying over it once, and
tells you nothing twelve hours later. Nothing about a sighting changes the ground. It is
the whole seam combat systems have with this module, and it is the reason the intel figure
on the map is a fact about a route rather than a constant.

`damage_facility(object_id, amount)` is the other one, and it refuses anything it does not
model.

## What the campaign did with nobody in it

200 ticks of the default eight second clock — about 27 minutes of realtime, or a
half-hour's sortie — with the launcher sites bound and no aircraft anywhere. F is friendly
districts, E enemy, C contested; `sup` is supply; `air` is each side's share of the
theatre's airspace; `bat` is fights open of fights so far; `loss` is ground lost, blue
then red.

```
t001   F17 E7  C7 | sup B0.83 R0.50 | air B0.47 R0.53 | bat  3/36 | loss  0.3/ 0.4
t010   F14 E8  C9 | sup B0.50 R0.50 | air B0.33 R0.67 | bat 11/34 | loss  2.6/ 3.1
t030   F16 E8  C7 | sup B0.93 R0.50 | air B0.33 R0.67 | bat  8/16 | loss  5.0/ 6.2
t060   F16 E8  C7 | sup B1.00 R0.50 | air B0.35 R0.65 | bat  6/13 | loss  8.0/ 8.9
t100   F16 E10 C5 | sup B1.00 R0.55 | air B0.35 R0.65 | bat  1/9  | loss 11.9/12.3
t150   F16 E9  C6 | sup B1.00 R0.50 | air B0.34 R0.66 | bat  6/16 | loss 17.1/16.7
t200   F16 E9  C6 | sup B1.00 R0.50 | air B0.34 R0.66 | bat  5/14 | loss 22.2/21.0
```

**37 ownership announcements across 12 of the 32 districts**, and the busiest single sector
— `tweed_heads` — was announced 11 times, which on a 200-tick run is one move every 18
ticks, or one move every two and a half minutes of a war. The first tick continues the
situation the player was shown rather than replacing it (`F17 E7 C7`, which is what the
corridor seeds). Red takes ground early — `F14 E8 C9` at t010, its best of the run, with
nine districts in play at once and the air balance against blue from tick one — blue is
back to sixteen held by t030 and keeps all sixteen for the remaining fifteen minutes while
red's count wanders between eight and ten. That is what contested means in
practice: the sector is not undecided because nobody has worked it out, it is undecided
because both sides keep being in it.

The last columns are the interesting ones. Losses end within a few units of each other
after 27 minutes of a war nobody is directing, both sides still hold ground, five fights
are still open to draw, and blue's supply runs to 1.00 on its rear areas while red sits on
its 0.50 floor for the whole run and only climbs to 0.55 when the front goes quiet. Red
being pinned at the floor is the difference between this and the frozen photograph the
first tuning produced: at the floor an exhausted side still fights at about two-thirds
tempo, so the war spends itself down to a stalemate that keeps bleeding instead of
stopping. It is a campaign that fights, stalls, refits and resumes, not a race to one
colour.

Blue's 0.34 share of the airspace is not a bias in the model; it is the corridor's own
geography. Six surviving SAM sites at 0.7 denial each, against one eight-aircraft field, is
a theatre the enemy flies in. Run the identical campaign with nothing at those sites —
`bind_launchers([])`, which is what the map says before a hostile has ever spawned — and
blue takes 0.71 of the sky, finishes **F17 E6 C8** rather than F16 E9 C6, and the whole run
settles: 25 announcements over 13 districts with the busiest sector moving three times.
The air defence is what keeps this a two-sided war, and it is also what keeps it nervous.
That is an emergent fact about this model, discovered rather than authored, and it is the
argument Phase 6 needs for SEAD: the campaign already knows which districts it cannot fly
in, and `active_battles()` will say so.

## Validation

Headless, the full suite is **138/140** on a back-to-back run and 140/140 with the two red
files re-run on their own against the identical build. Both failures are the same thing: the
exit-time `ERROR: 1 resources still in use at exit` that lands on whichever main-scene test
the jet engine's audio stream happens to be holding when the resource cache is cleared — this
run it was `battle_map_controller_test.gd` and `jet_audio_test.gd`. `war_director_test.gd`
passes clean, as do the three other war module tests and the six battle-map ones, on the
build that carries the ownership and refusal rules above. The flake was measured rather than
assumed, because "the new module is probably making the tests slow" is
exactly the story a two-millisecond tick cannot support. Five iterations, four main-scene
tests, two builds — the shipped wiring, and the same file with the single `_update_war(delta)`
call removed: **war wired in, 10 failures of 20 runs; war removed, 11 of 20.** The
distributions are the same, the failing test moves around between runs, and every one of
those runs printed its `*_TEST_PASS` line first. `--verbose` puts the held resource at
`assets/audio/jet_engine_loop.ogg::OggPacketSequence` with ten leaked ObjectDB instances,
which is Godot's audio teardown under the headless driver, and the phase that first
recorded it was phase 4.

`tests/war_director_test.gd` is new — nine sections, all of them over the real corridor's
32 districts:

- *the clock* — 420 frames of a sixtieth of a second must produce no tick at all, and the
  eighth second must produce exactly one, with the clock reading `TICK_DEFAULT` after it.
  (It advances `1.1` there, because 420 × 1/60 is 6.999999999999998 in binary and a check
  that lands two femtoseconds short of its own tick is testing floating point, not a clock.)
- *the opening survives the first tick* — every published share equals what the director
  computed, in both balances, before the campaign has said anything; the sea district is not
  in the war at all; every battle has two sides and none is over water.
- *the line moves with nobody flying* — the acceptance. 900 s produces 20+ ticks, at least
  one district becomes contested and at least one changes bloc, every announcement agrees
  with the map's current owner for that district (a district can move twice, so it is the
  *last* thing said that has to match), at least one battle closes with a stated outcome,
  the front is still drawable and both blocs still hold ground — and no single district is
  announced in more than an eighth of the ticks, which is the guard that the fix described
  above stays fixed. It is written as a rate rather than a count on purpose: nine changes in
  112 ticks is a front, and the same nine in 40 would not be, while the pathological run
  this was added for — 62 announcements of one sector in 200 ticks — fails either way.
- *the measures stay honest* — every field `RegionState` lists is finite and in 0..1 after
  a campaign, `state["owner"]` equals `owner_of`, the accounted district total is 32, and
  ground the war has no part in is still what the situation seeded it as, weighted — a
  district's opening numbers are not naive constants but the `0.75 + 0.25 × value` shape
  `war_control._seed()` applies, which is the expectation the test had to learn.
- *the air belongs to whoever can fly* — the same district measured with the sites
  unreported and then reported reads strictly more hostile (`surviving SAM sites must be
  felt in the airspace`), a destroyed airfield cannot hold the air it used to, and the two
  superiority shares divide one sky.
- *a field recovers* — capacity from its own pavement, a 0.35 hit reads DAMAGED and not
  DESTROYED, fewer aircraft but not none, and repair runs all the way to damage zero with
  the complement re-derived from the damage on every tick (`what is parked must be what the
  damage leaves`). That last clause is what caught the seat bug: the loop used to stop at the
  first `INTACT`, which is a threshold at 0.2 rather than a healed field, so it exited at
  damage 0.189 with six of eight parked and reported success. A 0.95 hit, which does put it
  out of action, still heals.
- *the campaign repeats itself* — two directors over their own copies of the theatre, same
  seed, identical campaign; a third with a different seed, not.
- *the world can report* — twelve sightings raise that district's intel above an identical
  war that saw nothing, and it reaches the map; a site and an unknown id are both refused; a
  fresh director carries no connections from the last one.
- *a theatre with no objects* — the war runs, the line still moves, and it publishes exactly
  what it computed, because the corridor with its registry is not the only case. Sydney with
  no geography, and `setup` with no situation, are both refused.

`tests/war_regions_test.gd` grew one section of its own for the hazard the wiring exposed:
`_check_refusal_leaves_nothing` loads the corridor, refuses Sydney, and then asserts that
nothing answers any more — not `regions()`, not `region("coolangatta")`, not `region_at`,
not `adjacency()` — and that the corridor loads again afterwards, a refusal being no injury.
The test that used to assert the opposite ("the refusal must leave the loaded theatre
standing") was written when the only reader of a geography was a map that would not draw a
null one.

`tools/check_battle_map_terrain.gd` grew a third war section, and it is the one that proves
the ownership rule in pixels rather than in a dictionary: the same camera, territory on,
shot twice to measure its own noise floor, then a director seated on the very tables the
canvas is drawing, run 112 ticks, then the same camera asked again. Re-run after the
refusal fix above, which is the run quoted here (`/tmp/bmt7`); the floor came back at
`0.0000` and the campaign moved 11.2 % of the frame anyway.

```
territory: changed=0.645 detail=0.0759->0.0601 luminance=0.244->0.284
war: districts=32 hatch=117 edges=20 chevrons=4 wash=0.17
campaign: ticks=112 moved=5/32 repainted=0.1117 noise=0.0000
objects: registry=10 regional symbols=10 changed=0.0174 detail=0.0586->0.0598
airfield: OOL · longest strip drawn 288 px at 0.11538 px per metre = 2493 m, authored 2492 m
```

Five of 32 districts had changed hands, and 11.2 % of the sampled pixels were different —
with the camera, the overlay, the toggles and the cached imagery all untouched, so there is
nothing else in the frame that could have moved. The two lines above it are the Phase 3 and
Phase 4 measurements repeating unchanged, which is the point of running all three overlays
in one pass: `BATTLE_MAP_TERRAIN_OK` now covers the camera, the districts, a campaign that
moved them, and the objects on the ground. `/tmp/bmt6-m_territory_opening.png` and
`-n_territory_after_campaign.png` are the pair.

Note what that run's director had: no registry. `_war_layers` builds its geography and
situation for the map, and this section seats a campaign on exactly those two, so the pixel
change comes from districts and the derived front alone — which is also the "theatre with
nothing standing in it" case, proved twice.

## What this does not prove

**No commander and no missions.** The brief's §13 forbids putting strategy in here, and
this module obeys: it decides who holds what and what it cost, never what to do about it.
`active_battles()` and `reports()` exist for Phase 7 to rank and Phase 6 to fly.

**Nothing shoots back at the campaign from the cockpit.** A SAM site's health changes
because a real round arrived at a real launcher, and a tower's because the player's gun
found it; the war reads both and causes neither. `damage_facility` has one caller — the
test — because there is no strike record to route yet. That is Phase 6's loop, and the seam
is deliberately two functions wide.

**A cold start is an unwatched theatre.** `_hostiles_enabled` is a runtime toggle, off until
the settings panel turns it on, so at boot `launcher_positions()` reports nothing and every
site reads UNCONFIRMED at zero health — which is the `F17 E6 C8` cold campaign above, not
the balanced one. It is the right kind of answer (the war declines to deny air with launchers it
has no evidence of) and the wrong first impression, and how much of the enemy's posture the
campaign should assume before a single hostile spawns is a Phase 6 question about
intelligence rather than a Phase 5 question about arithmetic.

**No persistence and no phone numbers.** The state lives in memory for the length of the
session, which is Phase 8 — `snapshot()` already returns tick, districts, ownership counts,
open fights, superiority, supply, losses and every field's operating model, so the save
layer has something to write. Every measurement here is headless maths and software-rendered
desktop frames; a two millisecond tick on llvmpipe is not a statement about a Snapdragon,
though "no per-frame strategic calculation, one 2 ms pass every eight seconds" is the shape
a device would survive.
