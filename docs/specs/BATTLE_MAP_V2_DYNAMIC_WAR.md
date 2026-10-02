OPENSTRIKE — BATTLE MAP V2 + DYNAMIC WAR
OBJECTIVE
Upgrade OpenStrike from a sequence of combat encounters into a persistent regional air/ground war.
DO NOT rewrite working flight, weapon, targeting, terrain, aircraft, SAM or enemy combat systems.
The strategic system sits ABOVE the existing combat simulation.
Core loop:
BATTLE MAP
→ inspect current war
→ receive/select mission
→ inspect primary/secondary targets
→ plan route
→ launch/fly
→ existing OpenStrike combat
→ mission outcome changes persistent world
→ Blue/Red AI reacts
→ territory/front line changes
→ new missions generated
The player must feel that they are participating in a battle already happening around them rather than loading isolated missions.
---
1. BATTLE MAP V2 — HIGHEST PRIORITY
The existing tactical map is useful but must be substantially upgraded.
The new Battle Map becomes one of the principal interfaces of OpenStrike.
It must support:
pan
smooth continuous zoom
terrain tilt
map rotation
animated target focus
semantic zoom
selectable world entities
territory rendering
front lines
bases
radar/SAM coverage
aircraft tracks
ground forces
active battles
mission assignments
primary/secondary targets
route planning
intelligence information
Do NOT implement this as a completely disconnected strategy-game map.
It represents the SAME OpenStrike world and SAME entities.
---
2. MAP CAMERA
Create a dedicated BattleMapCameraController.
Required camera modes:
TOP DOWN
Near-orthographic tactical view.
PERSPECTIVE
Camera can tilt toward the horizon to inspect terrain.
Camera pitch approximately:
0° overhead
through
~60° tilted
Do not allow camera inversion.
Controls must be smooth and inertial rather than stepping between fixed positions.
Android gestures
ONE FINGER DRAG
Pan map.
PINCH
Continuous zoom.
TWO-FINGER VERTICAL DRAG
Tilt map.
TWO-FINGER ROTATION
Rotate map bearing.
DOUBLE TAP ENTITY
Focus and smoothly zoom toward entity.
DOUBLE TAP TERRAIN
Zoom toward tapped geographic location.
TAP
Select entity.
TAP EMPTY TERRAIN
Deselect.
Mouse/debug controls
LMB drag = pan
Wheel = zoom
RMB vertical drag = tilt
RMB horizontal drag = rotate
Double click = focus
Controller
Keep map fully usable with Bluetooth controller.
Left stick = pan.
Right stick = rotate/tilt.
D-pad up/down = zoom.
R3 = reset orientation / north-up.
Existing map open/close binding remains.
---
3. CAMERA ANIMATION
Never instantly teleport the map camera when selecting strategic objects.
Selecting:
mission
base
aircraft
SAM
ground formation
battle
sector
should smoothly interpolate camera position, altitude/zoom and orientation.
Example:
Player selects:
MISSION HAMMER 21
Camera flies from theatre overview toward the target sector and frames:
enemy airbase
SAM coverage
primary target
player ingress direction.
Aim for approximately 0.4–1 second depending on travel distance.
---
4. SEMANTIC ZOOM
Zoom level determines information density.
Do not simply make every icon smaller/larger.
LEVEL A — THEATRE
Show:
territorial control
front lines
major airbases
major ground bases
major battles
air superiority
mission markers
major aircraft formations
Hide individual tactical objects.
LEVEL B — REGIONAL
Show:
airbases
radar installations
SAM sites
ground formations
supply locations
known aircraft groups
active missions
battle direction
important infrastructure
LEVEL C — TACTICAL
Show:
individual aircraft
individual known targets
SAM units
radars
ground vehicles/formations
waypoints
weapon-relevant contacts
assigned targets
Reuse existing tactical-map functionality where appropriate.
Transitions between levels should fade/merge rather than visibly switch screens.
---
5. 3D TERRAIN MAP
Where technically practical, Battle Map should use OpenStrike terrain/elevation rather than presenting a completely flat map.
At tilted angles the player should understand:
mountains
valleys
coast
urban areas
terrain masking opportunities.
Do NOT render the full expensive flight scene at full fidelity.
Use simplified terrain/material/LOD suitable for Android.
The map should remain responsive.
Target:
60 FPS desirable.
30 FPS absolute minimum on target Android hardware.
---
6. TERRITORY
Do NOT use hundreds of hexagons.
Divide the theatre into approximately 15–40 meaningful geographic regions.
Examples for the current theatre could follow actual geographic areas already represented by OpenStrike.
Every region has:
region_id
display_name
polygon/boundary
owner
air_control
ground_control
supply
infrastructure
intel_level
strategic_value
Owner enum:
FRIENDLY
ENEMY
CONTESTED
NEUTRAL
Example:
RegionState:
{
id: "gold_coast_south",
owner: CONTESTED,
air_control: 0.61,
ground_control: 0.43,
supply: 0.72,
infrastructure: 0.81,
intel_level: 0.68
}
---
7. TERRITORY VISUALISATION
Territory should appear as translucent geographic overlays.
BLUE = friendly.
RED = enemy.
Neutral should be subdued.
Contested territory should visually communicate mixed control rather than simply becoming another solid colour.
Avoid giant opaque overlays hiding satellite/terrain imagery.
Territory should feel like military command-map information laid over the real terrain.
---
8. FRONT LINE
Generate a visual front line between opposing controlled areas.
It does not need military-grade GIS precision.
It needs to:
follow regional control
move when territory changes
clearly communicate where the ground battle is happening.
Add directional pressure indicators where useful.
Example:
BLUE FORCE >>> FRONT <<< RED FORCE
A contested region should visually appear active.
---
9. STRATEGIC WORLD OBJECTS
Create persistent strategic objects.
Initial types:
AIRBASE
FORWARD_BASE
RADAR
SAM_SITE
COMMAND_POST
SUPPLY_DEPOT
GROUND_FORCE
BRIDGE/INFRASTRUCTURE
AIRCRAFT_GROUP
Each object should have at minimum:
id
type
faction
world_position
region_id
health
operational_state
strategic_value
discovered
intel_confidence
Objects must correspond to actual world locations.
When possible, use existing OpenStrike entities rather than creating duplicate fake entities.
---
10. AIRBASES
Airbases are particularly important.
Airbase state affects enemy/friendly air operations.
Properties:
runway operational state
fuel/supply
aircraft capacity
aircraft currently available
radar support
damage
repair progress
Destroying/damaging an airbase should reduce operations originating from that base.
Do not permanently eliminate an airbase after one bomb unless the relevant infrastructure is actually sufficiently damaged.
Allow gradual repair.
---
11. AIR SUPERIORITY
Each region has an air_control value.
Suggested range:
-1.0 = complete enemy control
0.0 = contested
+1.0 = complete friendly control
Air control changes based on:
fighter presence
fighter losses
radar coverage
SAM coverage
airbase capability
successful CAP
successful interception
AWACS/intelligence if implemented later.
Display this graphically on the Battle Map.
Do not require the player to understand the numeric value.
---
12. GROUND WAR
Keep ground warfare deliberately abstract at strategic scale.
Ground forces move between neighbouring regions.
Their effectiveness depends on:
force strength
supply
air superiority
enemy strength
recent air strikes
infrastructure.
The player DOES NOT micromanage battalions.
The ground war exists to create meaningful aviation missions.
Typical sequence:
Blue ground offensive begins.
Enemy armour blocks advance.
WarDirector generates CAS mission.
Player destroys armour.
Enemy ground strength falls.
Blue ground simulation advances.
Region becomes contested.
Later Blue captures region.
Front line moves.
---
13. WARDIRECTOR
Create a central strategic simulation manager.
Suggested:
scripts/war/war_director.gd
Responsibilities:
maintain world state
tick strategic simulation
calculate regional control
manage faction resources
update battles
process losses
update damaged facilities
repair facilities
manage air superiority
manage ground advances
request mission generation
save/load campaign state
Do NOT put map rendering inside WarDirector.
WarDirector owns DATA.
BattleMap displays DATA.
Combat systems modify DATA.
---
14. STRATEGIC SIMULATION TICK
Do not run expensive strategic decisions every frame.
Use a strategic tick.
Example:
5–15 seconds realtime.
Each tick:
update active regional battles
update air superiority
update ground pressure
update supply
update repairs
evaluate strategic objectives
update intelligence
allow commanders to make decisions
generate/cancel missions where appropriate.
The exact timing should be configurable.
---
15. BLUE AND RED COMMANDERS
Create lightweight AI commanders.
Initially DO NOT use an external LLM.
Use utility scoring.
Each commander evaluates possible objectives.
Example objective types:
DEFEND_REGION
CAPTURE_REGION
GAIN_AIR_SUPERIORITY
DEFEND_AIRBASE
SUPPRESS_SAM
DESTROY_RADAR
INTERDICT_SUPPLY
SUPPORT_GROUND_ATTACK
INTERCEPT_AIRCRAFT
Score candidate objectives using battlefield state.
Example concept:
score =
strategic_value
× urgency
× vulnerability
× available_force
× commander_priority
Highest-scoring objectives become active operations.
This makes Red respond dynamically without needing scripted mission sequences.
---
16. AGENTIC FEEL WITHOUT LLM DEPENDENCY
The commanders should appear intentional.
Example:
Player repeatedly attacks enemy airbase.
Red detects:
airbase strategic importance high
airbase damage increasing
Blue aircraft repeatedly entering region
local fighter strength low.
Red response may be:
redirect fighter CAP
increase intercept missions
protect surviving radar
move/activate SAM coverage
reduce offensive operations elsewhere.
This produces "agentic warfare" through world-state reasoning.
Architecture should permit an optional higher-level LLM commander later, but gameplay must NOT require network AI.
---
17. MISSION DIRECTOR
Create:
scripts/war/mission_director.gd
Missions are generated FROM strategic objectives.
Mission types initially:
CAP
INTERCEPT
ESCORT
SEAD
STRIKE
CAS
AIRBASE_DEFENCE
GROUND_INTERDICTION
Avoid building dozens of mission types initially.
These eight are enough to create significant variation.
---
18. MISSION OBJECT
Suggested data:
Mission:
{
id,
callsign,
type,
faction,
region_id,
primary_target,
secondary_targets,
priority,
status,
briefing,
threat_level,
strategic_effect,
created_at,
expires_at
}
Mission status:
AVAILABLE
ASSIGNED
ACTIVE
SUCCESS
PARTIAL
FAILED
EXPIRED
---
19. MISSIONS APPEAR ON THE MAP
Do NOT primarily use a conventional mission-list menu.
Missions appear geographically.
Example:
HAMMER 21
SEAD
PRIORITY
Player selects it.
Map smoothly moves to objective.
Mission information panel appears.
Example presentation:
HAMMER 21
SEAD
PRIMARY
Enemy SAM radar
SECONDARY
Launchers
REGION
Tweed Valley
THREAT
HIGH
CAP
Probable
STRATEGIC EFFECT
Opens corridor for Blue strike package.
Buttons:
ACCEPT
PLAN ROUTE
FLY
---
20. PRIMARY / SECONDARY TARGETS
Mission targets must be visible directly on map.
PRIMARY target gets distinctive marker.
SECONDARY targets use subordinate markers.
Selecting target opens intelligence card.
Example:
REDSTONE AIRBASE
ENEMY AIRBASE
Operational: 72%
Aircraft estimated: 8–14
Radar: ACTIVE
SAM protection: CONFIRMED
Intel confidence: 84%
ASSIGNED PRIMARY:
Command facility
SECONDARY:
Fuel storage
---
21. INTELLIGENCE SYSTEM
Do not give perfect omniscience.
Each enemy object has:
discovered
last_seen_time
intel_confidence
classification_confidence
Possible states:
UNKNOWN
SUSPECTED
DETECTED
IDENTIFIED
TRACKED
STALE
Aircraft tracks can disappear.
Old intelligence should become stale.
Radar/AWACS/friendly aircraft can refresh information.
This gives radar installations strategic meaning.
---
22. AIRCRAFT TRACKS / BVR MAP
Known airborne entities should appear as tracks.
At regional zoom:
RED GROUP R17
4 CONTACTS
At tactical zoom individual aircraft may appear if intelligence permits.
Example selection panel:
GROUP R17
Classification:
Fighter
Contacts:
4
Altitude:
24,000 ft
Heading:
217°
Track confidence:
78%
Last update:
4 sec
Allow:
ASSIGN TARGET
Where practical, this should reference the SAME target/entity used by existing OpenStrike targeting.
Do not create separate map-only target identities.
---
23. RADAR AND SAM COVERAGE
Map toggles/layers:
TERRITORY
AIR CONTROL
RADAR
SAM
GROUND FORCES
MISSIONS
INTELLIGENCE
SAM range displayed as translucent terrain/map coverage.
Radar coverage similarly displayed.
Do not permanently display every layer simultaneously.
The user should be able to declutter the map.
---
24. ROUTE PLANNING
Retain existing waypoint system but improve presentation.
Player can:
tap PLAN ROUTE
tap map to add waypoint
drag waypoint
delete waypoint
reorder if practical
see cumulative distance
see approximate terrain elevation
see known SAM/radar intersections.
Keep existing 12-waypoint limit initially unless architecture makes expansion trivial.
Mission target can automatically become final waypoint.
---
25. TARGET → COCKPIT CONTINUITY
This is critical.
If player selects:
PRIMARY TARGET: SAM RADAR
then launches mission, that identity should survive into gameplay.
Battle Map target ID
must correspond to
world target ID
which corresponds to
target-selection/radar/weapon systems.
Likewise destroyed targets must immediately update strategic state.
NO DUPLICATE FAKE TARGET DATABASE.
---
26. EXISTING ENEMY FLIGHT AI
Do not replace functioning enemy fighter AI.
Wrap it into higher-level tactical intent.
Strategic AI decides:
WHY aircraft are there.
Existing tactical AI decides:
HOW aircraft fight.
Desired high-level states:
PATROL
INTERCEPT
ESCORT
STRIKE
DEFEND
RTB
Once engaged, existing pursuit/defensive/dogfight logic continues.
Later tactical AI can be improved separately.
---
27. COMBAT OUTCOME → WAR STATE
Combat must affect campaign state.
Examples:
SAM destroyed
→ SAM object destroyed/damaged
→ coverage disappears/reduces
→ regional Blue air-control improves
→ strike missions become safer.
Radar destroyed
→ enemy detection capability reduced.
Enemy fighters destroyed
→ available enemy aircraft pool reduced.
Supply depot destroyed
→ enemy regional supply decreases.
Ground armour destroyed
→ ground-force strength decreases.
Airbase damaged
→ sortie generation reduced.
This causal chain is the entire reason the strategic layer exists.
---
28. PERSISTENCE
Campaign state must save.
Persist:
region ownership
air control
ground control
strategic-object health
destroyed objects
aircraft losses
ground-force strength
supply
active operations
campaign time
repair progress
player mission results.
Do not save transient particles/projectiles/etc.
Use a versioned save schema so later campaign changes do not immediately invalidate saves.
---
29. BATTLE MAP UI LAYOUT
Prioritise the MAP.
Do not cover Android screen with giant panels.
Suggested:
TOP LEFT
Campaign / theatre name
Blue/Red situation indicator
TOP RIGHT
Map layer controls
North/reset button
LEFT OR BOTTOM
Current assigned mission
RIGHT/BOTTOM DRAWER
Selected-object intelligence card
BOTTOM
ACCEPT / ROUTE / FLY contextual controls
Map remains visible behind UI.
Use collapsible panels on mobile.
---
30. VISUAL STYLE
Target aesthetic:
modern combat command interface
dark translucent panels
thin linework
clear military-style symbology
minimal unnecessary decoration
high contrast against satellite imagery.
Do NOT turn this into a generic mobile strategy-game interface.
It should visually belong to OpenStrike's cockpit/HUD presentation.
---
31. PERFORMANCE
Android remains primary.
Therefore:
pool map markers
batch overlays where practical
LOD strategic icons
do not instantiate expensive full aircraft scenes merely to display map tracks
avoid per-frame strategic calculations
avoid hundreds of Control nodes updating every frame
cache territory geometry
cache front-line geometry until state changes
update strategic information at sensible intervals.
Battle Map should remain usable with hundreds of abstract strategic entities even if only a subset are rendered at tactical zoom.
---
32. PROPOSED CODE ORGANISATION
Inspect the existing repo before creating files and adapt naming to existing conventions.
Conceptually:
scripts/war/
war_director.gd
faction_commander.gd
mission_director.gd
region_state.gd
strategic_object.gd
strategic_battle.gd
campaign_save.gd
scripts/battle_map/
battle_map_controller.gd
battle_map_camera.gd
battle_map_renderer.gd
battle_map_selection.gd
battle_map_intel_layer.gd
battle_map_strategy_layer.gd
battle_map_tactical_layer.gd
battle_map_mission_layer.gd
battle_map_route_layer.gd
data/war/
regions/
bases/
strategic_objects/
campaign_default/
Do not blindly create this structure if equivalent systems already exist.
Reuse before duplicating.
---
33. SIGNAL/EVENT ARCHITECTURE
Prefer signals/events over direct dependencies everywhere.
Useful events conceptually:
region_control_changed
strategic_object_damaged
strategic_object_destroyed
aircraft_destroyed
mission_created
mission_assigned
mission_completed
mission_failed
intel_updated
air_control_changed
front_line_changed
Battle Map listens to changes.
WarDirector does not manipulate UI.
---
34. IMPLEMENTATION ORDER
DO NOT ATTEMPT THE ENTIRE SYSTEM IN ONE PASS.
PHASE 1 — BATTLE MAP CAMERA
Upgrade current map.
Deliver:
smooth pan
continuous zoom
tilt
rotation
touch gestures
mouse debug controls
controller controls
focus animation
north/reset
stable Android behaviour.
Do not implement war simulation yet.
Acceptance:
I can open existing OpenStrike map and fluidly pan, pinch zoom, rotate and tilt around the existing Gold Coast/Tweed terrain.
Existing contacts/routes still work.
---
PHASE 2 — SEMANTIC MAP
Add:
theatre/regional/tactical zoom levels
marker clustering/visibility
map layer manager
selection card
smooth target focus.
Acceptance:
Zooming changes useful information rather than merely icon scale.
---
PHASE 3 — REGIONS
Create initial regional definitions.
Render:
Friendly
Enemy
Contested
Neutral
Add front line.
Use test/mock ownership initially.
Acceptance:
Battle Map clearly communicates territorial control while retaining underlying terrain visibility.
---
PHASE 4 — STRATEGIC OBJECTS
Integrate:
airbases
SAMs
radars
bases
ground formations
important infrastructure.
Connect existing world entities wherever possible.
Acceptance:
Selecting a strategic object on map resolves to meaningful world data.
---
PHASE 5 — WARDIRECTOR
Implement:
persistent region state
air control
ground control
simple strategic ticks
ground battles
facility damage
basic repairs.
Acceptance:
Run simulation without player.
Territory can naturally become contested/change ownership.
---
PHASE 6 — MISSION DIRECTOR
Generate missions from actual strategic conditions.
Acceptance example:
Enemy SAM prevents Blue operations.
WarDirector identifies problem.
MissionDirector generates SEAD mission.
Player accepts.
Existing SAM becomes primary target.
Player destroys it.
Mission succeeds.
War state changes.
Follow-up strike becomes possible.
---
PHASE 7 — AI COMMANDERS
Implement utility-based Blue and Red strategic decision-making.
Acceptance:
Repeated player behaviour causes understandable enemy responses rather than purely random missions.
---
PHASE 8 — CAMPAIGN PERSISTENCE
Save/load entire strategic state.
Acceptance:
Destroy airbase assets.
Quit.
Reload.
Damage and strategic consequences remain.
---
35. INITIAL DEMONSTRATION SCENARIO
Build ONE convincing vertical slice before expanding.
Three regions:
BLUE REGION
CONTESTED REGION
RED REGION
Red region contains:
1 airbase
1 radar
2 SAM positions
1 supply depot
1 ground force
Contested region contains opposing ground forces.
Initial situation:
Red has local air superiority.
Blue offensive is stalled.
WarDirector generates:
MISSION 1:
CAP / intercept enemy fighters.
Successful result improves air-control state.
Then:
MISSION 2:
SEAD against one SAM site.
Destroying SAM opens attack corridor.
Then:
MISSION 3:
Strike enemy supply depot / ground force.
Successful strike weakens Red ground control.
Blue forces advance.
Contested region changes to Blue.
Front line visibly moves.
THAT is the proof-of-concept.
If this loop feels good, expand the theatre.
---
36. IMPORTANT ENGINEERING RULES
Inspect existing implementation before changing architecture.
Do not replace working systems without a concrete reason.
Preserve current flight/combat gameplay.
No map-only duplicates of world targets.
Strategic AI runs independently of tactical dogfight AI.
Strategic simulation must be deterministic/debuggable enough to inspect why something happened.
Expose useful debug information.
Keep Android performance central.
Build incrementally and keep project runnable after every phase.
Add automated tests for strategic state transitions where practical.
---
37. DEBUG WAR OVERLAY
Add developer/debug panel showing:
simulation tick
region ownership
air-control values
ground-control values
commander objectives
active missions
aircraft resources
strategic-object state
reason mission was generated
reason territory changed.
Example:
RED COMMANDER
Objective:
DEFEND SOUTH REGION
Score:
0.82
Reason:
Airbase threatened + local air control declining.
Generated:
CAP R17
This is essential for debugging emergent behaviour.
---
38. DO NOT DO YET
Do not initially implement:
politics
economy
civilian simulation
naval warfare
logistics micromanagement
individual soldier simulation
hundreds of region types
LLM API dependency
complex reinforcement production trees
multiplayer
full RTS unit control.
OpenStrike is still a FLIGHT COMBAT GAME.
The strategic simulation exists to make every flight meaningful.
---
FINAL PLAYER EXPERIENCE
Player opens Battle Map.
The war is visibly happening.
Enemy aircraft are moving.
A contested region is under attack.
Red radar and SAM coverage protects an enemy-held corridor.
Blue commander assigns a SEAD mission.
Player tilts the map, examines terrain, zooms into the target, examines SAM coverage and creates a low-altitude ingress route.
Player accepts.
Map identifies PRIMARY and SECONDARY targets.
Player launches.
Existing OpenStrike flight/combat systems take over.
Player terrain-masks toward target.
SAM launches.
Player destroys radar and escapes.
Battle Map reopens.
Radar is destroyed.
SAM coverage has changed.
Blue aircraft begin entering the previously protected region.
Air superiority begins moving toward Blue.
A strike mission against the enemy airbase becomes available.
The war has reacted to what the player actually did.
That is the target experience.
BEGIN BY INSPECTING THE CURRENT REPOSITORY AND IMPLEMENTING PHASE 1 ONLY. Do not start WarDirector until Battle Map camera/navigation is polished, tested and existing tactical-map functionality remains operational.