extends SceneTree

## Every full-screen HUD control draws from its own `size`: the helmet centres
## its symbology on `size * 0.5`, the tape hangs off `size.y`, the scope sits in
## from `size.x`. A control that ends up zero-sized draws its instruments in
## the wrong place and leaves the radar unhittable, so presses fall past it
## to the bare-screen target lock.
##
## `set_anchors_preset()` alone rewrites the offsets to PRESERVE the control's
## current rect, which for a fresh control is nothing. Filling the parent takes
## `set_anchors_and_offsets_preset()`. This test pins that difference.

const FULL_RECT_UI := {
	"helmet_hud": "res://scripts/ui/helmet_hud.gd",
	"bearing_tape": "res://scripts/ui/bearing_tape.gd",
	"radar_scope": "res://scripts/ui/radar_scope.gd",
}

var _failed := false


func _init() -> void:
	# Awaited, not merely called: the check waits on frames, and an unawaited
	# coroutine would return at its first `await` and let this print a pass
	# before a single control had been measured.
	await _full_screen_ui_fills_the_screen()
	if _failed:
		return
	print("HUD_LAYOUT_TEST_PASS")
	quit()


func _full_screen_ui_fills_the_screen() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	# A control known to be laid out correctly, so the expected size is measured
	# rather than assumed -- headless and windowed runs disagree about it.
	var reference := Control.new()
	layer.add_child(reference)
	reference.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var made := {}
	for name in FULL_RECT_UI:
		var script: GDScript = load(FULL_RECT_UI[name])
		var node: Control = script.new()
		layer.add_child(node)
		made[name] = node
	await process_frame
	await process_frame
	var expected: Vector2 = reference.size
	if expected.is_zero_approx():
		_fail("the reference control measured nothing, so the test proves nothing")
		return
	for name in made:
		var node: Control = made[name]
		if not node.size.is_equal_approx(expected):
			_fail("%s must fill the screen at %v, got %v" % [name, expected, node.size])


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
