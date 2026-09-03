extends SceneTree

## The loop: drones down against buildings lost. Win at zero drones, lose at
## the threshold, and a restart puts it all back.

const MISSION := preload("res://scripts/entities/raid_mission.gd")


func _init() -> void:
	var mission = MISSION.new()
	var outcomes: Array[bool] = []
	mission.raid_ended.connect(func(won: bool) -> void: outcomes.append(won))

	mission.start(3)
	if mission.drones_remaining != 3 or mission.ended:
		_fail("start sets the drone count and clears ended")
	mission.drone_destroyed()
	mission.drone_destroyed()
	if mission.ended:
		_fail("one drone left is not a win")
	mission.drone_destroyed()
	if not mission.ended or not mission.won:
		_fail("zero drones is a win")
	if outcomes != [true]:
		_fail("raid_ended must fire once with true, got %s" % [outcomes])

	# Loss. Each building needs BUILDING_LOST_AT accumulated damage, and it
	# must be counted once however many more hits it takes.
	mission.start(10)
	outcomes.clear()
	for building in range(MISSION.RAID_FAILS_AT):
		mission.building_damaged(building, MISSION.BUILDING_LOST_AT * 0.5)
		if mission.buildings_lost != building:
			_fail("half the lost threshold must not count as lost")
		mission.building_damaged(building, MISSION.BUILDING_LOST_AT)
		mission.building_damaged(building, MISSION.BUILDING_LOST_AT * 3.0)
	if mission.buildings_lost != MISSION.RAID_FAILS_AT:
		_fail("each building lost counts exactly once, got %d" % mission.buildings_lost)
	if not mission.ended or mission.won:
		_fail("losing the threshold of buildings is a loss")
	if outcomes != [false]:
		_fail("raid_ended must fire once with false, got %s" % [outcomes])
	if mission.hud_line().find("DRONES 10") < 0:
		_fail("the HUD line must show drones remaining, got '%s'" % mission.hud_line())
	if mission.hud_line().find("%d/%d" % [MISSION.RAID_FAILS_AT, MISSION.RAID_FAILS_AT]) < 0:
		_fail("the HUD line must show buildings lost over the limit, got '%s'" % mission.hud_line())

	# After the end nothing moves the counters.
	mission.drone_destroyed()
	if mission.drones_remaining != 10:
		_fail("a finished raid must not keep counting")

	print("RAID_MISSION_TEST_PASS")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
