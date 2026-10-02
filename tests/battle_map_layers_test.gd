extends SceneTree

## The semantic zoom state on its own: where the levels begin and end, that the
## boundaries do not flicker, that content fades rather than switching, and that
## a layer with nothing behind it is reported rather than drawn from thin air.

const LAYERS := preload("res://scripts/battle_map/battle_map_layers.gd")

var failed := false


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# A previous interrupted run may have left panel state behind, and this file
	# is what the level and fade assertions are measured against.
	DirAccess.remove_absolute(LAYERS.SETTINGS_FILE)
	_check_levels()
	_check_hysteresis()
	_check_a_pinch_walks_the_levels_once()
	_check_fades_are_gradual_and_finish()
	_check_sourceless_layers_never_draw()
	_check_toggles_and_persistence()
	DirAccess.remove_absolute(LAYERS.SETTINGS_FILE)
	if not failed:
		print("BATTLE_MAP_LAYERS_TEST_PASS")
	quit(1 if failed else 0)


func _levels() -> LAYERS:
	var layers: LAYERS = LAYERS.new()
	return layers


func _check_levels() -> void:
	check(LAYERS.level_for(1000.0) == LAYERS.Level.TACTICAL, "a 1 km view is a tactical view")
	check(LAYERS.level_for(15000.0) == LAYERS.Level.REGIONAL, "15 km is regional")
	check(LAYERS.level_for(40000.0) == LAYERS.Level.THEATRE, "40 km is theatre")
	check(
		LAYERS.level_name(LAYERS.Level.THEATRE) == "THEATRE",
		"the levels must be able to say what they are")


## Inside the hysteresis bands the answer depends on where the map already is, so
## a pinch held on a boundary cannot make two different sets of content alternate.
func _check_hysteresis() -> void:
	var middle := (LAYERS.TACTICAL_ENTER + LAYERS.TACTICAL_EXIT) * 0.5
	check(
		LAYERS.level_for(middle, LAYERS.Level.TACTICAL) == LAYERS.Level.TACTICAL,
		"zooming out but staying inside the band must stay tactical")
	check(
		LAYERS.level_for(middle, LAYERS.Level.REGIONAL) == LAYERS.Level.REGIONAL,
		"zooming in but staying inside the band must stay regional")
	var band := (LAYERS.REGIONAL_ENTER + LAYERS.REGIONAL_EXIT) * 0.5
	check(
		LAYERS.level_for(band, LAYERS.Level.THEATRE) == LAYERS.Level.THEATRE,
		"the theatre band must hold its level the same way")
	check(
		LAYERS.level_for(band, LAYERS.Level.REGIONAL) == LAYERS.Level.REGIONAL,
		"a regional view pulled to the same range must stay regional")
	check(
		LAYERS.level_for(LAYERS.TACTICAL_EXIT + 1.0, LAYERS.Level.TACTICAL)
		== LAYERS.Level.REGIONAL,
		"leaving the band must change the level")


func _check_a_pinch_walks_the_levels_once() -> void:
	var layers := _levels()
	var seen := []
	var last := -1
	var metres := 1000.0
	while metres <= 40000.0:
		layers.tick(1.0 / 60.0, metres)
		if layers.level() != last:
			seen.append(layers.level())
			last = layers.level()
		metres *= 1.05
	check(
		seen == [LAYERS.Level.TACTICAL, LAYERS.Level.REGIONAL, LAYERS.Level.THEATRE],
		"a steady zoom out must pass through each density exactly once, got %s" % [seen])
	seen = []
	last = -1
	metres = 40000.0
	while metres >= 1000.0:
		layers.tick(1.0 / 60.0, metres)
		if layers.level() != last:
			seen.append(layers.level())
			last = layers.level()
		metres /= 1.05
	check(
		seen == [LAYERS.Level.THEATRE, LAYERS.Level.REGIONAL, LAYERS.Level.TACTICAL],
		"zooming back in must undo the same three steps, got %s" % [seen])


func _check_fades_are_gradual_and_finish() -> void:
	var layers := _levels()
	check(layers.alpha(&"sweep") == 1.0, "the sweep belongs to the tactical view it starts in")
	layers.tick(1.0 / 60.0, 15000.0)
	var first := layers.alpha(&"sweep")
	check(
		first < 1.0 and first > 0.5,
		"a drawn layer must fade out rather than vanish, got %.3f" % first)
	var frames := 1
	var seconds := 1.0 / 60.0
	while layers.visible(&"sweep") and frames < 200:
		layers.tick(1.0 / 60.0, 15000.0)
		frames += 1
		seconds += 1.0 / 60.0
	check(frames > 8 and frames < 60, "a fade must take a few tenths of a second, took %d" % frames)
	check(seconds > 0.1 and seconds < 1.0, "and that must be in seconds, not frames: %.2f" % seconds)
	for settle in range(4):
		layers.tick(1.0 / 60.0, 15000.0)
	check(layers.alpha(&"sweep") == 0.0, "a fade must land exactly on zero, not on an asymptote")
	check(layers.level() == LAYERS.Level.REGIONAL, "and the level it faded into is regional")
	check(layers.alpha(&"contacts") == 1.0, "contacts survive a level change untouched")


## The war layers are declared so the panel has one list to build from, but until
## a director feeds them they must stay invisible and must not be toggled into an
## empty promise.
func _check_sourceless_layers_never_draw() -> void:
	var layers := _levels()
	for id in [&"territory", &"air_control", &"radar", &"sam", &"ground", &"missions", &"intelligence"]:
		check(not layers.has_source(id), "%s has no source yet" % [id])
		for metres in [1000.0, 15000.0, 40000.0]:
			layers.tick(0.5, metres)
			check(layers.alpha(id) == 0.0, "%s must not appear at %.0f m" % [id, metres])
		check(not layers.toggle(id), "toggling %s must be refused while it has no data" % [id])
	check(layers.toggle(&"contacts"), "a layer that has data must be toggleable")
	check(layers.toggle(&"contacts"), "and back on again")
	check(layers.is_enabled(&"contacts"), "a double toggle leaves the default state")


func _check_toggles_and_persistence() -> void:
	var layers := _levels()
	layers.tick(0.5, 1000.0)
	check(layers.visible(&"places"), "place names are on by default")
	layers.toggle(&"places")
	var away := 0
	while layers.visible(&"places") and away < 200:
		layers.tick(1.0 / 60.0, 1000.0)
		away += 1
	check(away > 3, "switching a layer off must fade it, not cut it")
	var reopened := _levels()
	check(not reopened.is_enabled(&"places"),
		"the panel state must come back with the next map instance")
	check(reopened.alpha(&"places") == 0.0, "and a reopened map must start settled, not mid-fade")
	reopened.toggle(&"places")
	var back := 0
	while reopened.alpha(&"places") < 1.0 and back < 200:
		reopened.tick(1.0 / 60.0, 1000.0)
		back += 1
	check(reopened.alpha(&"places") == 1.0, "switching a layer back on must fade it in")
