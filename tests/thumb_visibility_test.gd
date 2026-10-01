extends SceneTree
## The sticks must actually reach the screen once the splash closes. v11 shipped
## them permanently invisible: only the splash's show path asked the HUD to
## re-check what was covering it, so the hide left the sticks switched off, and
## with them hidden every press fell through to tap-to-lock.

func _init() -> void:
	call_deferred("run")


func run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for frame in range(4):
		await process_frame
	var failures: Array[String] = []
	game._set_thumb_controls(true)
	if game._startup == null or not game._startup.visible:
		failures.append("the splash should still be up while the theatre is chosen")
	if game._thumb.visible:
		failures.append("the sticks must stay under the splash")
	game._startup.hide_panel()
	await process_frame
	if not game._thumb.visible:
		failures.append("the sticks must appear the moment the splash closes")
	if not game._thumb.is_visible_in_tree():
		failures.append("the sticks are visible but not in the tree")
	game.settings_panel.visible = true
	await process_frame
	if game._thumb.visible:
		failures.append("the sticks must hide behind the settings panel")
	game.settings_panel.visible = false
	await process_frame
	if not game._thumb.visible:
		failures.append("the sticks must come back when the settings panel closes")

	# Two fingers: a second pointer must not be swallowed by the first grab.
	var first: InputEvent = InputEventScreenTouch.new()
	first.index = 3
	first.position = game._thumb.flight.get_global_rect().get_center()
	first.pressed = true
	game._thumb.flight._input(first)
	if game._thumb.flight.get("_pointer_id") != 3:
		failures.append("the left stick did not take the finger in its corner")

	game._tap_lock_enabled = false
	if game._tap_lock_allowed():
		failures.append("taps must stop locking a target in controller-free mode")
	game._tap_lock_enabled = true
	if not game._tap_lock_allowed():
		failures.append("the Settings toggle must hand tap-to-lock back")

	for note in failures:
		print("THUMB_VISIBILITY_TEST_FAIL: " + note)
	if not failures.is_empty():
		quit(1)
		return
	print("THUMB_VISIBILITY_TEST_PASS")
	quit(0)
