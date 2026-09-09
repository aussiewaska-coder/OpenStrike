extends SceneTree
const DAY := preload("res://scripts/world/day_cycle.gd")
func _init(): call_deferred("_run")
func _run():
	var day := DAY.new()
	root.add_child(day)
	day.set_process(false)
	assert(day.mode == DAY.Mode.DUSK and day.mode_name() == "AFTERNOON", "startup should offer readable afternoon lighting")
	for month in [3, 6, 9, 12]:
		var midnight := float(Time.get_unix_time_from_datetime_string("2026-%02d-05T00:00:00" % month)) - DAY.DEMO_LONGITUDE / 15.0 * 3600.0
		for mode in [DAY.Mode.DUSK, DAY.Mode.SUNRISE]:
			var hour: float = DAY.MODE_HOURS[mode]
			var old_hour := 17.6 if mode == DAY.Mode.DUSK else 6.4
			var old_angles: Vector2 = DAY.SOLAR.sun_angles(DAY.DEMO_LATITUDE, DAY.DEMO_LONGITUDE, midnight + old_hour * 3600)
			var new_angles: Vector2 = DAY.SOLAR.sun_angles(DAY.DEMO_LATITUDE, DAY.DEMO_LONGITUDE, midnight + hour * 3600)
			var old_state: Dictionary = DAY.SKY.for_elevation(old_angles.x)
			var new_state: Dictionary = DAY.SKY.for_elevation(new_angles.x)
			print("DAYLIGHT month=%d mode=%d sun=%.2f->%.2f tint=%.3f->%.3f" % [month, mode, old_angles.x, new_angles.x, old_state.terrain_tint.get_luminance(),new_state.terrain_tint.get_luminance()])
			assert(absf(hour-old_hour) == 0.75, "preset must move exactly 45 minutes toward daylight")
			assert(new_angles.x > old_angles.x, "both morning and afternoon presets must raise the sun")
			assert(new_state.terrain_tint.get_luminance() > old_state.terrain_tint.get_luminance(), "terrain must become brighter in each season")
	day.mode = DAY.Mode.REAL
	var seen := []
	for i in range(5):
		seen.append(day.mode_name())
		day.cycle_mode()
	assert(seen == ["REAL CLOCK", "NOON", "AFTERNOON", "NIGHT", "SUNRISE"], "settings cycling must expose the new sunrise and retain existing modes")
	assert(day.mode == DAY.Mode.REAL, "time modes must wrap")
	day.free()
	print("DAYLIGHT_PRESETS_TEST_PASS")
	quit()
