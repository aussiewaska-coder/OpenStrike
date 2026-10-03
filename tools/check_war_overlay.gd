extends SceneTree

## §37's pixel check: does the switch in Settings put the campaign on the screen?
##
## `tests/war_report_test.gd` proves the overlay and the telemetry socket agree on the text, but it
## does that headless, where nothing is laid out and nothing is drawn. What only a real frame can
## answer is whether §37's panel is legible over a live world at a phone's size, whether it survives
## a real layout pass, and whether the checkbox on the Display page is wired all the way to the
## handler that shows it. So run this with a real renderer:
##
##   xvfb-run -a -s "-screen 0 900x600x24" \
##     $GODOT_BIN --path . --rendering-driver opengl3 --script \
##     tools/check_war_overlay.gd -- --out=/tmp/war_overlay
##
## It boots the scene the game ships with and presses the same START the player presses, so the
## theatre streams for real: a cold map cache makes this slow, and there is nothing faked in the
## picture. The frames land in --out= for a person to look at, and every claim below is measured off
## them rather than off the nodes that drew them.

const SWITCH_TEXT := "Debug war overlay"
const DISPLAY_PAGE := 2
## The theatre streams over the network the first time anyone flies there.
const LOAD_MILLISECONDS := 240000
## Longer than the overlay's own 0.5 s refresh, so a frame taken after waiting this is a frame the
## overlay had its say in.
const PAINT_SECONDS := 0.9
## A panel this thin on the screen is a panel nobody can read on a phone.
const MIN_PANEL_FRACTION := 0.35

var failed := false


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _run() -> void:
	var out := "/tmp/war_overlay"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	if DisplayServer.get_name() == "headless":
		push_error("Headless draws nothing; run this under a real renderer.")
		quit(1)
		return
	root.size = Vector2i(900, 600)
	root.content_scale_size = Vector2(900, 600)
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._jet_audio.set_volume(0.0, false)
	await process_frame
	print("booted; awaiting startup=%s pending theatre=%s" % [
		bool(main.get("_awaiting_startup")), String(main.get("_pending_region").get("id", ""))])
	main._on_startup_start()
	var report: RefCounted = main.get("_war_report")
	var deadline: int = Time.get_ticks_msec() + LOAD_MILLISECONDS
	while not report.is_ready() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(report.is_ready(), "the war never seated itself; §37 has nothing to read out")
	if failed:
		quit(1)
		return
	var overlay: Control = main.get("_war_overlay")
	_check(overlay != null, "the production scene never builds the overlay")
	# Whichever way the developer left the switch, start from the position the game boots into.
	_check(overlay.visible == bool(main.call("_load_ui_flag", "war_overlay", false)),
		"the overlay's first frame does not agree with the switch that remembers it")
	if overlay.visible:
		main._on_war_overlay_toggled(false)
		await process_frame
	var hidden := await _capture(out, "a_off")
	await _press_switch(main)
	# The campaign moves on its own clock and the overlay on its own, so comparing the two texts
	# needs the war held still for the length of one refresh; otherwise this line is a race that
	# happens to pass most of the time.
	paused = true
	await create_timer(PAINT_SECONDS).timeout
	var shown := await _capture(out, "b_on")
	var rect: Rect2 = overlay.get_global_rect()
	_check(overlay.visible, "the Display switch changed nothing on the screen")
	_check(rect.size.x > 0.0 and rect.size.y > 0.0, "the overlay was laid out to draw nothing")
	var label := _find_label(overlay)
	_check(label != null, "the overlay paints no text at all")
	if label != null:
		var painted := String(label.text)
		print("painted %d lines, %d characters" % [painted.count("\n") + 1, painted.length()])
		_check(painted == String(report.text()), "the screen is showing a campaign the socket is not")
		_check(painted.contains("HELD"), "the panel lost the ownership line it exists to show")
	# The claim is about these pixels: the panel must be ink where the world was a moment ago.
	var inside := _changed(hidden, shown, rect)
	_check(inside > MIN_PANEL_FRACTION,
		"switching the panel over changed only %.3f of the pixels it covers" % inside)
	var screen := Rect2(Vector2.ZERO, Vector2(root.size.x, root.size.y))
	_check(screen.has_point(rect.position), "the panel starts off the top-left of the screen")
	_check(rect.end.x <= screen.end.x + 1.0,
		"the panel runs %d px off the right hand edge" % int(rect.end.x - screen.end.x))
	# A phone held sideways is the screen this is debugged on, so measure the spill rather than
	# discovering it later in a screenshot somebody has to squint at.
	print("panel %s on a %dx%d screen%s" % [rect, root.size.x, root.size.y,
		"" if rect.end.y <= screen.end.y else "  SPILLS %d px below" % int(rect.end.y - screen.end.y)])
	paused = false
	await _press_switch(main)
	var off_again := await _capture(out, "c_off")
	_check(not overlay.visible, "a second press of the switch did not put the panel away")
	_check(_changed(shown, off_again, rect) > MIN_PANEL_FRACTION,
		"the panel is still inked after it was switched off")
	await create_timer(0.3).timeout
	main.free()
	if failed:
		print("WAR_OVERLAY_RENDER_FAILED")
		quit(1)
	else:
		print("WAR_OVERLAY_RENDER_OK")
		quit(0)


## Press the switch the way a player reaches it: open Settings, walk to the Display tab, toggle the
## button, and get the menu out of the way so the next frame is the game rather than the menu.
func _press_switch(main: Node3D) -> void:
	main.settings_panel.open_panel()
	await process_frame
	var tabs: Array = main.settings_panel.get("_tabs")
	_check(tabs.size() > DISPLAY_PAGE, "Settings has no Display tab to hold the switch")
	tabs[DISPLAY_PAGE].pressed.emit()
	await process_frame
	var button := _find_switch(main.settings_panel)
	_check(button != null, "Settings / Display has no \"%s\" switch" % SWITCH_TEXT)
	if button == null:
		return
	# The same state change a finger makes, and the same one the panel's own signal rides on.
	button.set_pressed(not button.is_pressed())
	await process_frame
	main.settings_panel.close_panel()
	await process_frame


func _find_switch(node: Node) -> CheckButton:
	for child in node.find_children("*", "CheckButton", true, false):
		if String((child as CheckButton).text) == SWITCH_TEXT:
			return child
	return null


func _find_label(node: Node) -> Label:
	for child in node.get_children():
		if child is Label:
			return child
		var found := _find_label(child)
		if found != null:
			return found
	return null


## One drawn frame, saved and handed back for comparison.
func _capture(out: String, name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(_has_pixels(image), "%s must render something, not an empty backdrop" % name)
	_check(image.save_png("%s-%s.png" % [out, name]) == OK, "%s must save" % name)
	return image


## The fraction of sampled pixels inside `rect` that two frames disagree about.
func _changed(one: Image, two: Image, rect: Rect2) -> float:
	if one == null or two == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return 0.0
	var x0 := clampi(int(rect.position.x), 0, one.get_width())
	var y0 := clampi(int(rect.position.y), 0, one.get_height())
	var x1 := clampi(int(rect.end.x), 0, one.get_width())
	var y1 := clampi(int(rect.end.y), 0, one.get_height())
	var samples := 0
	var different := 0
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var at := Vector2i(x, y)
			var mine := one.get_pixelv(at)
			var theirs := two.get_pixelv(at)
			samples += 1
			if absf(mine.r - theirs.r) + absf(mine.g - theirs.g) + absf(mine.b - theirs.b) > 0.06:
				different += 1
	return float(different) / float(maxi(samples, 1))


func _has_pixels(image: Image) -> bool:
	var seen := {}
	var luminance := 0.0
	var samples := 0
	for step in range(0, image.get_width() * image.get_height(), 997):
		var at := Vector2(step % image.get_width(), step / image.get_width())
		var colour := image.get_pixelv(at)
		luminance += colour.get_luminance()
		samples += 1
		seen[colour.to_html(false)] = true
		if samples > 4000:
			break
	return samples > 0 and luminance / float(samples) > 0.01 and seen.size() > 8
