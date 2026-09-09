extends SceneTree
const VIEW := preload("res://scripts/camera/threat_camera.gd")
const ROUND := preload("res://scripts/weapons/cannon_round.gd")
const WARNING := preload("res://scripts/ui/threat_warning.gd")
var failed := false
func _init(): call_deferred("run")
func run():
	root.size = Vector2i(960, 540)
	var original := Camera3D.new()
	root.add_child(original)
	var view := VIEW.new()
	view.aircraft_camera = original
	root.add_child(view)
	var player := Node3D.new()
	root.add_child(player)
	var rounds := []
	for distance in [3000, 500, 1500]:
		var missile := ROUND.new()
		missile.sequence = distance
		missile.position = Vector3(0, 100, -distance)
		rounds.append(missile)
	for expected in [500, 1500, 3000]:
		view.cycle(rounds, player.position)
		view.update(0.1, rounds, player)
		check(view.sequence == expected and view.camera.current, "R3 cycles incoming missiles nearest first")
	view.cycle(rounds, player.position)
	check(not view.watching and original.current, "R3 returns after the final incoming missile")
	view.cycle(rounds, player.position)
	view.update(0.1, [], player)
	check(not view.watching and original.current, "impact/expiry returns automatically without a stale pooled reference")
	var warning := WARNING.new()
	root.add_child(warning)
	warning.size = root.get_visible_rect().size
	warning._camera = original
	check(warning.warning_rect().position.y >= warning.size.y * 0.75 and warning.warning_rect().end.y <= warning.size.y, "warning sits bottom centre inside a phone screen")
	var front := warning.missile_marker(Vector3(0, 0, -1000))
	var rear := warning.missile_marker(Vector3(400, 100, 1000))
	check(not front.edge and Vector2(front.point).distance_to(original.unproject_position(Vector3(0, 0, -1000))) < 2, "visible missile marker is anchored to actual 3D camera projection")
	check(rear.edge and rear.behind, "rear missile has an edge arrow and explicit behind cue")
	warning.free()
	view.free()
	original.free()
	player.free()
	if not failed: print("THREAT_VIEW_TEST_PASS")
	quit(1 if failed else 0)
func check(ok: bool, message: String):
	if not ok:
		failed = true
		push_error(message)
