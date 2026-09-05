extends SceneTree

## The aircraft control walks three now, not two, and each jet arrives with
## its own airframe rather than sharing the Raptor's.

const AIRFRAME := preload("res://scripts/jet/airframe.gd")

func _init(): call_deferred("_run")

func _run():
	var main = load("res://scripts/main.gd").new()
	assert(main.JET_PROFILES.size() == 2, "two jets are selectable")
	assert(String(main.JET_PROFILES[0].display_name) == "F-22 RAPTOR")
	assert(String(main.JET_PROFILES[1].display_name) == "F-117 NIGHTHAWK")
	assert(main.JET_PROFILES[0].scene_path != main.JET_PROFILES[1].scene_path,
		"and they are not the same aeroplane wearing two names")

	# Walk the cycle by hand, exercising the same index the switch moves.
	var seen: Array[String] = []
	for step in 4:
		seen.append(main.current_aircraft_name())
		if main._flying_jet and main._jet_index + 1 < main.JET_PROFILES.size():
			main._jet_index += 1
		elif main._flying_jet:
			main._flying_jet = false
		else:
			main._flying_jet = true
			main._jet_index = 0
	assert(seen == ["F-22 RAPTOR", "F-117 NIGHTHAWK", "AH-64D APACHE", "F-22 RAPTOR"],
		"cycle must be Raptor, Nighthawk, Apache, and round again, got %s" % str(seen))
	main.free()
	print("AIRCRAFT_CYCLE_TEST_PASS")
	quit()
