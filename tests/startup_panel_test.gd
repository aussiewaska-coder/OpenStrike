extends SceneTree

const PANEL := preload("res://scripts/ui/startup_panel.gd")


func _init(): call_deferred("_run")


func _run() -> void:
	var panel := PANEL.new()
	root.add_child(panel)
	var regions := [
		{"id": "au_gold_coast_tweed_corridor", "display_name": "GOLD COAST", "subtitle": "50 km"},
		{"id": "au_nsw_sydney_harbour", "display_name": "SYDNEY", "subtitle": "50 km"},
	]
	var picked := []
	panel.theatre_chosen.connect(func(id): picked.append(id))
	var modes := []
	panel.start_mode_changed.connect(func(airborne, runway): modes.append([airborne, runway]))
	var started := [false]
	panel.start_requested.connect(func(): started[0] = true)

	# No selection yet: START waits for location.
	panel.show_panel(regions, "", false, true, {})
	await process_frame
	assert(panel.visible, "splash shows on boot")
	assert(panel._start_button.disabled, "START waits for a theatre")
	assert(panel._theatre_box.get_child_count() == 2, "both theatres listed")

	# Sydney selected, airborne: runway picker stays hidden.
	panel.show_panel(regions, "au_nsw_sydney_harbour", false, true, {})
	await process_frame
	assert(not panel._start_button.disabled, "START arms once located")
	assert(not panel._runway_box.visible, "airborne start hides runways")

	# Theatre buttons choose.
	panel._theatre_box.get_child(1).pressed.emit()
	assert(picked == ["au_nsw_sydney_harbour"], "theatre press selects Sydney")

	# Runway mode lists Sydney's three strips.
	panel.show_panel(regions, "au_nsw_sydney_harbour", true, false, {"id": "16R"})
	await process_frame
	assert(panel._runway_box.visible, "runway mode shows the airport picker")
	assert(panel._runway_box.get_child_count() == 3, "Sydney lists three runways")
	panel._runway_box.get_child(0).pressed.emit()
	assert(modes.size() == 1 and not modes[0][0], "strip press picks runway start")
	assert(String(modes[0][1].get("id", "")) == "16R", "first strip is the longest runway")

	# Gold Coast has one strip; unknown theatres hide the picker.
	panel.show_panel(regions, "au_gold_coast_tweed_corridor", false, false, {})
	await process_frame
	assert(panel._runway_box.get_child_count() == 1, "Gold Coast lists one runway")
	panel.show_panel(regions, "nowhere", false, true, {})
	await process_frame
	assert(not panel._runway_button.visible, "no runways, no picker")

	panel._start_button.disabled = false
	panel._start_button.pressed.emit()
	assert(started[0], "START fires")
	panel.hide_panel()
	assert(not panel.visible, "START dismisses the splash")
	panel.free()
	print("STARTUP_PANEL_TEST_PASS")
	quit()
