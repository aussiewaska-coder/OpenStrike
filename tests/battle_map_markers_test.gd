extends SceneTree

## Who the map draws at each zoom: that clustering groups what is close, keeps
## what is alone, never loses a track, holds its labels steady while the camera
## moves, and does none of that work twice for the same information.

const MARKERS := preload("res://scripts/battle_map/battle_map_markers.gd")
const LAYERS := preload("res://scripts/battle_map/battle_map_layers.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

var failed := false


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _project(world: Vector2) -> Vector2:
	return world * 0.02 + Vector2(450, 300)


func _track(
	handle: int, kind: int, at: Vector3, velocity := Vector3.ZERO
) -> Dictionary:
	return TRACKER.contact(handle, kind, at, velocity, "T%02d" % handle)


## Four aircraft forming up, a launcher out on its own, and a parked column of
## armour. Each of the three sits inside one cluster cell of its own.
func _contacts() -> Array:
	return [
		_track(11, TRACKER.Kind.AIR_JET, Vector3(200, 400, 300), Vector3(0, 0, -240)),
		_track(12, TRACKER.Kind.AIR_JET, Vector3(900, 380, 620), Vector3(0, 0, -240)),
		_track(13, TRACKER.Kind.AIR_DRONE, Vector3(1400, 90, 1200), Vector3(60, 0, -180)),
		_track(14, TRACKER.Kind.AIR_JET, Vector3(500, 420, 1100), Vector3(-30, 0, -250)),
		_track(21, TRACKER.Kind.GROUND_LAUNCHER, Vector3(24000, 40, 24000)),
		_track(31, TRACKER.Kind.GROUND_POINT, Vector3(9000, 30, -6000)),
		_track(32, TRACKER.Kind.GROUND_POINT, Vector3(9400, 30, -6600)),
	]


func _run() -> void:
	_check_tactical_shows_every_track()
	_check_regional_groups_without_losing_any()
	_check_theatre_folds_the_formation()
	_check_a_group_reports_what_is_inside_it()
	_check_labels_survive_a_sweep_and_stay_bounded()
	_check_nothing_is_recomputed_for_free()
	_check_a_moved_track_moves_the_group()
	_check_a_formation_on_a_cell_line()
	_check_a_wide_formation_is_one_marker()
	_check_tapping_a_group()
	if not failed:
		print("BATTLE_MAP_MARKERS_TEST_PASS")
	quit(1 if failed else 0)


func _individuals(items: Array) -> int:
	var count := 0
	for item in items:
		if bool(item["individual"]):
			count += 1
	return count


func _groups(items: Array) -> Array:
	var found := []
	for item in items:
		if not bool(item["individual"]):
			found.append(item["group"])
	return found


func _check_tactical_shows_every_track() -> void:
	var markers := MARKERS.new()
	var items := markers.markers(_contacts(), LAYERS.Level.TACTICAL)
	check(items.size() == 7, "at tactical range every track is drawn as itself, got %d" % items.size())
	check(_individuals(items) == 7, "and none of them is folded into a group")
	check(markers.live_groups().is_empty(), "a tactical view has no group markers to tap")
	var handles := {}
	for item in items:
		handles[int(item["contact"]["handle"])] = true
	for wanted in [11, 12, 13, 14, 21, 31, 32]:
		check(handles.has(wanted), "handle %d must still be on the map" % wanted)


func _check_regional_groups_without_losing_any() -> void:
	var markers := MARKERS.new()
	var items := markers.markers(_contacts(), LAYERS.Level.REGIONAL)
	var groups := _groups(items)
	check(groups.size() == 2,
		"the four aircraft and the two armour form up; the launcher does not, got %d" % groups.size())
	for group in groups:
		check(bool(group["air"]) == (int(group["count"]) == 4),
			"a group of four moving jets is an air group")
	# Nothing disappears on the way out: seven tracks are still accounted for.
	var accounted := 0
	for group in groups:
		accounted += int(group["count"])
	accounted += _individuals(items)
	check(accounted == 7, "regional clustering must still account for all seven tracks, got %d" % accounted)
	check(_individuals(items) == 1, "a lone launcher stays a lone contact at regional range")
	check(
		bool(items[items.size() - 1]["individual"]),
		"a lone track must be painted over the groups, not underneath them")


func _check_theatre_folds_the_formation() -> void:
	var markers := MARKERS.new()
	var items := markers.markers(_contacts(), LAYERS.Level.THEATRE)
	check(_individuals(items) == 1, "the launcher is one SAM, not a formation, even over a theatre")
	check(items.size() == 3, "at 16 km cells the jets and the armour are two groups and the launcher is itself, got %d" % items.size())
	var accounted := 0
	for group in _groups(items):
		accounted += int(group["count"])
	check(accounted == 6, "and every remaining track is still inside a report, got %d" % accounted)


func _check_a_group_reports_what_is_inside_it() -> void:
	var markers := MARKERS.new()
	var items := markers.markers(_contacts(), LAYERS.Level.REGIONAL)
	var air := _air_of(items)
	check(not air.is_empty(), "the air group must be there")
	var handles := markers.handles_of(air)
	handles.sort()
	check(handles == [11, 12, 13, 14],
		"a group carries the tracker's own handles, got %s" % [handles])
	var expected := (Vector3(200, 400, 300) + Vector3(900, 380, 620)
		+ Vector3(1400, 90, 1200) + Vector3(500, 420, 1100)) / 4.0
	check((air["centroid"] as Vector3).distance_to(expected) < 0.01,
		"the marker sits on the centroid of what it stands for")
	check(air["altitude_m"] > 419.0, "the ceiling of the formation is its highest track")
	var heading: float = air["heading"]
	check(heading > PI * 1.5 or heading < PI * 0.25,
		"a group flying north reports a northerly heading, got %.2f" % heading)
	var ground := {}
	for group in _groups(items):
		if not bool(group["air"]):
			ground = group
	check(is_nan(ground["heading"]), "a stationary group has no heading to claim")
	check(
		int(ground["kind"]) == TRACKER.Kind.GROUND_POINT,
		"a formation of parked armour is titled as ground, not as the first track in the array")


func _check_labels_survive_a_sweep_and_stay_bounded() -> void:
	var markers := MARKERS.new()
	var contacts := _contacts()
	var named := {}
	for group in _groups(markers.markers(contacts, LAYERS.Level.REGIONAL)):
		named[String(group["label"])] = group
	check(named.size() == 2, "two groups, two distinct call signs, got %d" % named.size())
	# Grouping answers a question about the ground, not about the camera, so
	# sweeping the view across a hundred empty cells must neither rename anything
	# nor count up into the hundreds.
	for step in range(6):
		if step % 2 == 1:
			contacts[4]["position"] = Vector3(24000.0 + step * 40000.0, 40, 24000.0)
		for group in _groups(markers.markers(contacts, LAYERS.Level.REGIONAL)):
			var label := String(group["label"])
			check(named.has(label), "a group keeps its call sign while the map moves, lost %s" % label)
			var digits := label.reverse().split(" ", false)[0]
			check(digits.is_valid_int() and int(digits) <= 4,
					"group numbers stay in the range of groups actually on the map, got %s" % label)
	contacts[4]["position"] = Vector3(24000, 40, 24000)
	var swept := markers.markers(contacts, LAYERS.Level.THEATRE)
	check(swept.size() <= 4, "sweeping the map must not accumulate markers, got %d" % swept.size())


func _check_nothing_is_recomputed_for_free() -> void:
	var markers := MARKERS.new()
	var contacts := _contacts()
	var items := markers.markers(contacts, LAYERS.Level.REGIONAL)
	check(items.size() == 3, "regional gives two groups and a lone launcher")
	# The same ground at the same density cannot have changed its answer, so the
	# second call must be a cache hit rather than a rebuild.
	var again := markers.markers(contacts, LAYERS.Level.REGIONAL)
	check(again == items, "unchanged contacts must be answered from the cache")


func _check_a_moved_track_moves_the_group() -> void:
	var markers := MARKERS.new()
	var contacts := _contacts()
	var before := _air_of(markers.markers(contacts, LAYERS.Level.REGIONAL))
	check(int(before["count"]) == 4, "the formation starts as four")
	# The records are pooled, so anything wanted for comparison has to be copied
	# out before the next call rewrites it -- that is the whole point.
	var was: Vector3 = before["centroid"]
	contacts[0]["position"] = Vector3(60000, 400, 60000)
	var items := markers.markers(contacts, LAYERS.Level.REGIONAL)
	var after := _air_of(items)
	check(int(after["count"]) == 3,
		"a jet that flew out of the cell leaves a formation of three, got %d" % int(after["count"]))
	check(
		was.distance_to(after["centroid"] as Vector3) > 100.0,
		"and the marker moves to where the rest of the formation actually is")
	var accounted := _individuals(items)
	for group in _groups(items):
		accounted += int(group["count"])
	check(accounted == 7, "the runner is still on the map as something, got %d of 7" % accounted)


func _air_of(items: Array) -> Dictionary:
	for group in _groups(items):
		if bool(group["air"]):
			return group
	return {}


func _check_a_formation_on_a_cell_line() -> void:
	# Cells are world-aligned so a group keeps its identity while the camera pans,
	# and the price is that a formation straddling a cell line arrives as two
	# buckets. A cluster therefore reaches across the line; what may not happen is
	# the pair either overlapping as two markers or dropping a track.
	var markers := MARKERS.new()
	var straddling := [
		_track(41, TRACKER.Kind.GROUND_POINT, Vector3(-200, 30, 0)),
		_track(42, TRACKER.Kind.GROUND_POINT, Vector3(200, 30, 0)),
	]
	var items := markers.markers(straddling, LAYERS.Level.REGIONAL)
	var groups := _groups(items)
	check(groups.size() == 1 and _individuals(items) == 0,
		"a pair either side of a cell line is one marker, got %d groups and %d tracks"
		% [groups.size(), _individuals(items)])
	check(int(groups[0]["count"]) == 2, "and it counts both of them")
	check(markers.handles_of(groups[0]) == [41, 42], "with the tracker's own handles inside it")
	# The same pair fed over in the other order must give the same answer.
	var reversed := _groups(markers.markers(_rev(straddling), LAYERS.Level.REGIONAL))
	check(reversed.size() == 1 and int(reversed[0]["count"]) == 2,
		"and the clustering must not depend on the order the tracker handed them over in")
	var more := _strung_out()
	for run in range(4):
		var swept := markers.markers(more, LAYERS.Level.REGIONAL)
		var accounted := _individuals(swept)
		for group in _groups(swept):
			accounted += int(group["count"])
		check(accounted == 6, "a chain of lone cells must still account for all six, got %d" % accounted)
		more = _rev(more)


## A formation wide enough to span two cells but nowhere near wide enough to read
## as two clusters: it must come back as one marker, not as two overlapping ones
## with a pilot guessing which is which.
func _check_a_wide_formation_is_one_marker() -> void:
	var markers := MARKERS.new()
	var flight := []
	for step in range(4):
		flight.append(_track(
			60 + step, TRACKER.Kind.AIR_JET, Vector3(-2600.0 + step * 1600.0, 400, 200),
			Vector3(0, 0, -200)))
	var items := markers.markers(flight, LAYERS.Level.REGIONAL)
	check(_individuals(items) == 0, "a four-ship is not drawn as its parts, got %d" % _individuals(items))
	check(items.size() == 1, "and not as two clusters side by side, got %d" % items.size())
	var handles := markers.handles_of(_groups(items)[0])
	handles.sort()
	check(handles == [60, 61, 62, 63], "one marker, all four tracks inside it, got %s" % [handles])


func _rev(items: Array) -> Array:
	var copy := []
	for index in range(items.size() - 1, -1, -1):
		copy.append(items[index])
	return copy


## A line of lone tracks, one per cell, to check that merging across cell lines
## never loses or duplicates anything however the array is ordered.
func _strung_out() -> Array:
	var contacts := []
	for step in range(6):
		contacts.append(_track(50 + step, TRACKER.Kind.GROUND_POINT, Vector3(step * 7000.0, 30, 0)))
	return contacts


func _check_tapping_a_group() -> void:
	var markers := MARKERS.new()
	var items := markers.markers(_contacts(), LAYERS.Level.REGIONAL)
	var air := _air_of(items)
	var project := Callable(self, "_project")
	var on: Vector2 = _project.call(Vector2(air["centroid"].x, air["centroid"].z))
	check(markers.group_at(on, project, 24.0) == air,
		"a tap on a group marker finds that group")
	var handles := markers.handles_of(markers.group_at(on, project, 24.0))
	handles.sort()
	check(handles == [11, 12, 13, 14],
		"and the tap hands back the same handles the tactical view would have drawn")
	check(markers.group_at(on + Vector2(4000, 0), project, 24.0).is_empty(),
		"a tap on empty ground is not a group")
