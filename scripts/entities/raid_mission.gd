extends RefCounted

## The loop the raid gives the player: drones down against buildings lost.
##
## "Lost" is the mission's word, not the damage system's. building_damage_system
## only knows about smoke, at 420 accumulated; a building is lost here at twice
## a bomb, so one bomb smokes it and a second finishes it.

signal raid_ended(won: bool)

const RAID_FAILS_AT := 5
## Twice a bomb's structural damage of 320.
const BUILDING_LOST_AT := 640.0

var drones_remaining := 0
var buildings_lost := 0
var buildings_hit := 0
var ended := false
var won := false

var _lost: Dictionary = {}
var _hit: Dictionary = {}


func start(drone_count: int) -> void:
	drones_remaining = drone_count
	buildings_lost = 0
	buildings_hit = 0
	ended = false
	won = false
	_lost.clear()
	_hit.clear()


func drone_destroyed() -> void:
	if ended:
		return
	drones_remaining = maxi(drones_remaining - 1, 0)
	if drones_remaining == 0:
		_finish(true)


## Fed from building_damage_system.building_damaged. Accumulated is the total
## the damage system has recorded for that building, so this is idempotent
## per building: it counts a loss once however many more hits land.
func building_damaged(building_id: int, accumulated: float) -> void:
	if ended:
		return
	if not _hit.has(building_id):
		_hit[building_id] = true
		buildings_hit += 1
	if accumulated >= BUILDING_LOST_AT and not _lost.has(building_id):
		_lost[building_id] = true
		buildings_lost += 1
		if buildings_lost >= RAID_FAILS_AT:
			_finish(false)


func hud_line() -> String:
	if ended:
		return "RAID %s -- DRONES %d  BUILDINGS %d/%d" % [
			"REPELLED" if won else "FAILED", drones_remaining, buildings_lost, RAID_FAILS_AT
		]
	return "DRONES %d  BUILDINGS %d/%d" % [drones_remaining, buildings_lost, RAID_FAILS_AT]


func _finish(victory: bool) -> void:
	ended = true
	won = victory
	raid_ended.emit(victory)
