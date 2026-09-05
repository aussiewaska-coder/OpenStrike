extends SceneTree

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var panel = load("res://scripts/ui/settings_panel.gd").new()
	root.add_child(panel)
	var main = load("res://scripts/main.gd").new()
	main.settings_panel = panel
	panel.open_changed.connect(main._on_settings_open_changed)
	panel.set_aircraft_text("AIRCRAFT: F-22 RAPTOR")
	panel.set_flight_mode_text("CONTROLS: FLY-BY-WIRE")
	panel.set_quality_text("GRAPHICS: BALANCED")
	panel.set_time_text("TIME: AFTERNOON")
	panel.set_weather_text("WEATHER: CLEAR")
	panel.set_cache_report(127, 182000000)
	panel.set_region_text("Surfers Paradise — Gold Coast, Queensland")
	panel.set_status("F-22 cockpit · 900 m altitude")
	var regions := []
	for index in range(12):
		regions.append({"id": str(index), "display_name": "Surfers Paradise %d" % index, "subtitle": "Gold Coast · Coastline and hinterland"})
	panel.populate_theatres(regions, "0")
	panel.open_panel()
	await process_frame
	await process_frame
	check(root.gui_get_focus_owner() != null and panel.is_ancestor_of(root.gui_get_focus_owner()), "opening settings must focus a menu control for the gamepad")
	check(panel._aircraft_button.size.y >= 48, "aircraft selector must be a usable touch target")
	check(panel.process_mode == Node.PROCESS_MODE_ALWAYS, "settings must remain usable when flight is paused")
	check(panel.z_index > 0, "settings must draw above the flight HUD")
	check(paused, "opening settings must pause flight")
	var zoom: float = main._camera_zoom
	var view: int = main._jet_view
	main._on_gamepad_action_pressed(&"camera_zoom_in")
	main._on_gamepad_action_pressed(&"target_next")
	main._on_gamepad_action_pressed(&"track_target")
	check(main._camera_zoom == zoom and main._jet_view == view and not main._tracker.tracking_view, "menu navigation must not zoom, switch cameras or lock targets")
	panel._select_page(1)
	await process_frame
	await process_frame
	var last: Button = panel._theatre_box.get_child(panel._theatre_box.get_child_count() - 1)
	last.grab_focus()
	await process_frame
	await process_frame
	check(panel._scroll.scroll_vertical > 0, "gamepad focus must scroll long theatre lists into view")
	check(panel._scroll.get_global_rect().intersects(last.get_global_rect()), "focused theatre must be visible")
	var first_id: int = panel._theatre_box.get_child(0).get_instance_id()
	panel.populate_theatres(regions, "0")
	check(first_id == panel._theatre_box.get_child(0).get_instance_id() and root.gui_get_focus_owner() == last, "refreshing settings must preserve theatre controls and focus")
	panel._select_page(2)
	panel._tabs[2].grab_focus()
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	root.push_input(down)
	await process_frame
	check(root.gui_get_focus_owner() == panel._quality_button, "D-pad/arrow down from a section must enter its controls")
	var changes := [0]
	panel.quality_cycled.connect(func(): changes[0] += 1)
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	root.push_input(accept)
	accept = accept.duplicate()
	accept.pressed = false
	root.push_input(accept)
	await process_frame
	check(changes[0] == 1, "accept must activate the focused setting exactly once")
	var weapon: int = main._weapons.current
	main._on_gamepad_action_released(&"weapon_cycle", 0.1)
	check(not panel.visible and not paused, "a short X press must close settings and resume flight")
	check(main._weapons.current == weapon, "closing settings must not cycle the weapon")
	panel.open_panel()
	var gamepad := root.get_node("GamepadInput")
	gamepad._paused_for_controller = true
	panel.close_panel()
	check(paused, "closing settings must preserve the disconnected-controller pause")
	panel.open_panel()
	gamepad._set_active_controller(0)
	check(paused, "reconnecting a controller must not resume flight behind settings")
	panel.close_panel()
	check(not paused, "Resume must work after a controller reconnect")
	gamepad.active_device = -1
	gamepad._had_controller = false
	panel.open_panel()
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	root.push_input(cancel)
	check(not panel.visible and not paused, "B/Escape must close the menu and restore flight")
	panel.open_panel()
	panel._select_page(0)
	# Layout must stay usable on short landscape screens and portrait phones.
	for viewport_size in [Vector2i(640, 360), Vector2i(360, 640), Vector2i(1280, 720)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		await process_frame
		await process_frame
		check(panel.size.is_equal_approx(Vector2(viewport_size)), "settings must follow viewport resizing")
		check(panel.get_global_rect().encloses(panel._resume_button.get_global_rect()), "Resume must stay entirely on screen")
		for tab in panel._tabs:
			check(panel.get_global_rect().encloses(tab.get_global_rect()), "every section tab must remain reachable")
		for page in range(4):
			panel._select_page(page)
			await process_frame
			await process_frame
			check(panel._scroll.size.y >= 80, "the content viewport must retain usable height")
			for control in panel._pages[page].find_children("*", "BaseButton", true, false):
				var bounds: Rect2 = control.get_global_rect()
				check(bounds.position.x >= 0 and bounds.end.x <= panel.size.x + 0.1, "setting controls must not overflow horizontally")
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--visual-out=") and DisplayServer.get_name() != "headless" and viewport_size.x == 640 and page in [0, 1]:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(arg.trim_prefix("--visual-out=").trim_suffix(".png") + "-small-%d.png" % page)
	panel._select_page(0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--visual-out=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(arg.trim_prefix("--visual-out="))
	panel.close_panel()
	panel.free()
	main.free()
	if not failed:
		print("SETTINGS_PANEL_TEST_PASS")
	quit(1 if failed else 0)
