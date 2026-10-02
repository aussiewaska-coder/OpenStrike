extends SceneTree

## The selection card: what a tap on the map has to tell the pilot, and what it
## has to be allowed to do about it. Every number here is measured from the
## tracker's own contacts, because a card that invented a field would be the one
## thing on an avionics display nobody could trust.

const MFD := preload("res://scripts/ui/tactical_mfd.gd")
const LEVELS := preload("res://scripts/battle_map/battle_map_layers.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const HUD := preload("res://scripts/ui/helmet_hud.gd")

const JET_A := 101
const JET_B := 102
const JET_C := 103
const JET_D := 104
const LONE := 301

var failed := false
var _asked: Array = []
var _mfd: MFD


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _note(handle: int) -> void:
	_asked.append(handle)


func _track(handle: int, kind: int, at: Vector3, velocity := Vector3.ZERO) -> Dictionary:
	return TRACKER.contact(handle, kind, at, velocity, "BANDIT %03d" % handle)


## Four aircraft close enough to be one report, and a fixed site far enough away
## to be its own. Nothing in the theatre is at the same place twice, so every
## number the card prints can be checked against a hand calculation.
func _contacts() -> Array:
	return [
		_track(JET_A, TRACKER.Kind.AIR_JET, Vector3(300, 900, -400), Vector3(0, 0, -200)),
		_track(JET_B, TRACKER.Kind.AIR_JET, Vector3(900, 1200, 1100), Vector3(0, 0, -210)),
		_track(JET_C, TRACKER.Kind.AIR_DRONE, Vector3(1300, 700, 1900), Vector3(60, 0, -160)),
		_track(JET_D, TRACKER.Kind.AIR_JET, Vector3(400, 1500, 2400), Vector3(-30, 0, -240)),
		_track(LONE, TRACKER.Kind.BUILDING, Vector3(14000, 60, -8000)),
	]


func _run() -> void:
	DirAccess.remove_absolute(LEVELS.SETTINGS_FILE)
	_mfd = MFD.new()
	root.add_child(_mfd)
	root.size = Vector2i(900, 600)
	# Sizes are stated rather than waited for: the map projects through its own
	# rect, and a layout pass that has not run yet would leave it at nothing.
	_mfd.size = Vector2(900, 600)
	_mfd.map.size = Vector2(900, 600)
	_mfd.contact_selected.connect(_note)
	_mfd.open_panel()
	_mfd.map.set_state(Vector3.ZERO, 0.0, _contacts(), -1, null)
	_check_an_individual_reads_its_own_numbers()
	_check_a_formation_is_a_report_not_a_target()
	_check_the_card_keeps_up()
	_check_the_card_dies_with_its_subject()
	_check_the_layers_say_what_they_can_do()
	DirAccess.remove_absolute(LEVELS.SETTINGS_FILE)
	_mfd.free()
	if not failed:
		print("BATTLE_MAP_CARD_TEST_PASS")
	quit(1 if failed else 0)


func _map() -> Control:
	return _mfd.map


func _settle(metres: float) -> void:
	_map().set_range(metres)
	for frame in range(20):
		_map()._process(1.0 / 60.0)
	_map().markers()


func _tap(world: Vector2) -> void:
	_map().select_at(_map().world_to_screen(world))


func _card() -> String:
	return String(_mfd._card_lines.text)


func _refresh() -> void:
	_mfd._card_elapsed = 0.0
	_mfd._process(MFD.CARD_SECONDS + 0.01)


func _check_an_individual_reads_its_own_numbers() -> void:
	_settle(2000.0)
	_asked.clear()
	_tap(Vector2(300, -400))
	check(_asked == [JET_A], "a tap on a single track is the selection request it always was, got %s" % [_asked])
	check(_mfd._card.visible, "and it opens a card")
	var text := _card()
	check(text.contains("BANDIT %03d" % JET_A), "the card is named for the track, got %s" % text)
	check(text.contains(HUD.kind_label(TRACKER.Kind.AIR_JET)), "and says what it is")
	# 300 m east and 400 m north of ownship: half a kilometre on a bearing of 037.
	check(text.contains("RNG   0.5 km"), "range is measured from ownship, got %s" % text)
	check(text.contains("BRG 037°"), "bearing is the compass angle to it, got %s" % text)
	check(text.contains("ALT 900 m"), "altitude is the track's own, got %s" % text)
	check(text.contains("SPD 200 m/s"), "and so is its speed")
	check(text.contains("TRK 000°"), "a track flying north reports a north course, got %s" % text)
	check(text.contains("UNLOCKED"), "the card admits the weapon does not have it")
	_asked.clear()
	_mfd._fly.pressed.emit()
	check(_map()._view.is_gliding(), "FLY TO flies the camera; it never cuts to it")
	var spins := 0
	while _map()._view.is_gliding() and spins < 300:
		_map()._process(1.0 / 60.0)
		spins += 1
	check(
		_map().centre.distance_to(Vector2(300, -400)) < 200.0,
		"and lands on the track that was on the card")
	check(_asked.is_empty(), "flying to a contact is not a second weapon request")


func _check_a_formation_is_a_report_not_a_target() -> void:
	_settle(20000.0)
	var air := {}
	for group in _map().cluster.live_groups():
		if bool(group["air"]):
			air = group
	check(not air.is_empty(), "at regional range the four are one formation")
	_asked.clear()
	var centroid: Vector3 = air["centroid"]
	_tap(Vector2(centroid.x, centroid.z))
	check(_asked.is_empty(), "tapping a formation must not lock anything, asked for %s" % [_asked])
	var text := _card()
	check(text.contains("4 TRACKS"), "the card reports how many tracks are inside it, got %s" % text)
	check(text.contains(String(air["label"])), "and calls it by the name on the marker")
	check(text.contains("CEILING 1 500 m"), "the ceiling is the highest track in it, got %s" % text)
	check(text.contains("MOVING 4/4"), "and it says how many of them are actually moving, got %s" % text)
	check(text.contains("BANDIT %03d" % JET_A), "and names the track ASSIGN would buy")
	_asked.clear()
	_mfd._assign.pressed.emit()
	check(_asked == [JET_A], "ASSIGN hands the nearest member to the weapon, got %s" % [_asked])


## The card is a live readout: a track that moves has to move on the card, and a
## formation that loses a member has to lose it on the card -- on an interval,
## not every frame.
func _check_the_card_keeps_up() -> void:
	var contacts: Array = _map().contacts
	contacts[3]["position"] = Vector3(60000, 900, 60000)
	_map().set_state(Vector3.ZERO, 0.0, contacts, JET_A, null)
	_refresh()
	var text := _card()
	check(text.contains("3 TRACKS"), "the formation lost a member and the card knows, got %s" % text)
	var held := _card()
	_mfd._process(MFD.CARD_SECONDS * 0.5)
	check(held == _card(), "the card refreshes on an interval, not every frame")
	# The same handles on the card are the handles the tactical view locks, so a
	# formation card and the target it dissolves into must never disagree.
	check(int(_map().locked) == JET_A, "the card reports the lock the world actually has")
	contacts[3]["position"] = Vector3(400, 1500, 2400)
	_map().set_state(Vector3.ZERO, 0.0, contacts, -1, null)
	_refresh()


func _check_the_card_dies_with_its_subject() -> void:
	_settle(2000.0)
	_tap(Vector2(300, -400))
	check(_mfd._card.visible, "the card is up")
	var contacts := _contacts()
	contacts.remove_at(0)
	_map().set_state(Vector3.ZERO, 0.0, contacts, -1, null)
	_refresh()
	check(not _mfd._card.visible, "a shot-down track must not keep reporting, got %s" % _card())
	_settle(20000.0)
	_tap(Vector2(14000, -8000))
	check(_card().contains("STATIONARY"), "a parked contact says so instead of claiming a speed")
	check(_card().contains(HUD.kind_label(TRACKER.Kind.BUILDING)), "and says what kind of thing it is")
	check(
		not _card().contains("TRACK HELD"),
		"and does not spend a second line saying the same thing about its course, got %s" % _card())
	_mfd.close_panel()
	check(not _mfd._card.visible, "and closing the map takes the card with it")


func _check_the_layers_say_what_they_can_do() -> void:
	var semantic: RefCounted = _map().semantic
	var drawn := 0
	var waiting := 0
	for id in semantic.ids():
		var button: Button = _mfd._layer_buttons[id]
		check(not button.text.is_empty(), "every layer has a key with a name on it")
		if semantic.has_source(id):
			drawn += 1
			check(not button.disabled, "%s can be switched" % id)
			continue
		waiting += 1
		check(button.disabled, "%s has nothing behind it and must not pretend" % id)
		check(button.text.ends_with("· NONE"), "%s says so on its key" % id)
		button.pressed.emit()
		check(semantic.is_enabled(id), "and pressing it changes nothing at all")
	check(
		drawn >= 4 and waiting >= 6,
		"the panel shows both what draws and what is still waiting, got %d and %d" % [drawn, waiting])
	var contacts: Button = _mfd._layer_buttons[&"contacts"]
	contacts.pressed.emit()
	check(not semantic.is_enabled(&"contacts"), "a real layer still switches off")
	check(not contacts.button_pressed, "and the key follows the map, not the other way round")
	contacts.pressed.emit()
	check(semantic.is_enabled(&"contacts"), "and back on")
	_settle(40000.0)
	check(
		String(_mfd._density_label.text).contains(LEVELS.level_name(LEVELS.Level.THEATRE)),
		"the header says which density the map is reading at, got %s" % _mfd._density_label.text)
	_settle(2000.0)
	check(
		String(_mfd._density_label.text).contains(LEVELS.level_name(LEVELS.Level.TACTICAL)),
		"and follows it back in")
