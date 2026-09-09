# Random enemy dogfights

While flying a jet, a flight of 2–4 enemy Raptors arrives after eight seconds.
They start 4.5–6.5 km away in the forward sector, near the player's altitude,
inside the default radar range. After all aircraft are destroyed or depart,
another flight arrives after a random 12–22 second breather. Only one flight
is active at a time. Changing theatre resets encounters and the kill count.

Pilots vary in speed, turn rate and jink timing. Their evasive styles are a
descending break, reversing scissors, or a climbing break. They pursue the
player's actual six and react to closing missiles aimed at them within 4.5 km,
even outside the gun-threat cone. Terrain sampling supplies clearance. Evasion
changes the flight path; it does not grant immunity or use a random hit roll.
Enemy return fire is now enabled; see `2026-09-06-enemy-combat.md` for acquisition, missile warnings and damage.

Air contacts and the selected target use red HUD symbols. With a missile
selected, an amber acquisition arc fills around the target. A completed red
ring and `MISSILE LOCK - FIRE` indicate seeker readiness. Cooldown, reload,
lost contacts and seeker limits suppress that cue. The weapon line shows live
hostiles and kills. A destroyed aircraft retires its visual, collision entry
and target contact; repeated impacts cannot count it twice.

Default controls: X / Square cycles weapons; RB / R1 tracks the looked-at
target; LB / L1 fires the selected missile; L3 fires the cannon. A screen tap
also selects a target. Controller remapping still applies. Heat seekers are
fire-and-forget; radar missiles require retaining the selected target lock.

## Assets and off-the-shelf AI

This uses the existing bundled F-22 GLB and its existing attribution in
`assets/models/ATTRIBUTION.md`; no new model download is required. Full 3D models
provide readable banking and silhouette changes during a close pass.

[Beehave](https://github.com/bitbrain/beehave) is a Godot behavior-tree addon
with a visual debugger, and [LimboAI](https://github.com/limbonaut/limboai)
offers behavior trees and hierarchical state machines. Both are options if
the encounter AI grows; the current small flight extends the existing state
machine and adds no plugin dependency. They provide AI structure rather than
a ready-made aircraft flight model or dogfighting tactics.

## Verification

`tests/dogfight_test.gd` exercises repeat waves after kills and departures,
duplicate-hit accounting, terrain clearance, missile-threat discrimination,
tail pursuit, and live missile interceptions of all three evasive styles with
both seekers at 60 and 120 Hz. `tests/missile_test.gd` covers acquisition,
cooldown, reload, lock loss and the HUD readiness data.
`tests/dogfight_runtime_test.gd` verifies the production encounter, tracker,
hardpoint launch, impact routing, HUD readiness and kill readout together.

`tools/check_dogfight.gd` renders the enemy models with acquiring, ready and
offscreen reticles to `/tmp/openstrike-dogfight-*.png`.

On a software-rendered Linux host:

```sh
GALLIUM_DRIVER=softpipe LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a "$GODOT_BIN" \
  --path . --audio-driver Dummy --rendering-method gl_compatibility \
  --script res://tools/check_dogfight.gd
```
