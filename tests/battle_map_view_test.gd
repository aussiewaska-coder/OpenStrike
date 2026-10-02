extends SceneTree

## The battle map camera on its own: the projection, its inverse, the limits and
## the smoothing. Nothing here needs a scene, a renderer or a controller, which
## is the point -- the maths has to be provable without a phone in the loop.

const VIEW := preload("res://scripts/battle_map/battle_map_view.gd")

var failed := false


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _init() -> void:
	call_deferred("_run")


func _camera() -> VIEW:
	var view: VIEW = VIEW.new()
	view.viewport_size = Vector2(900, 600)
	view.range_m = 10000.0
	return view


func _run() -> void:
	_check_flat_map_is_unchanged()
	_check_projection_round_trip()
	_check_tilt_compresses_the_far_ground()
	_check_bearing_turns_the_world()
	_check_limits_hold()
	_check_anchor_zoom()
	_check_drag_pins_the_ground()
	_check_inertia_settles()
	_check_focus_glide()
	if not failed:
		print("BATTLE_MAP_VIEW_TEST_PASS")
	quit(1 if failed else 0)


func _check_flat_map_is_unchanged() -> void:
	var view := _camera()
	var ppm: float = view.pixels_per_metre()
	check(is_equal_approx(ppm, 600.0 / 20000.0), "the shorter axis must set the scale")
	for world in [Vector2.ZERO, Vector2(1234, -5678), Vector2(-9000, 9000)]:
		var expected: Vector2 = Vector2(450, 300) + (world - view.centre) * ppm
		check(view.project(world).distance_to(expected) < 0.001, "a level map must project exactly as the flat one did")


func _check_projection_round_trip() -> void:
	var view := _camera()
	for tilt in [0.0, 0.2, VIEW.TILT_MAX]:
		for bearing in [0.0, 0.7, PI, -1.9]:
			view.set_bearing(bearing)
			view.settle()
			view.tilt = tilt
			for world in [Vector2(400, -900), Vector2(-12000, 3000), Vector2(50, 50)]:
				var on_screen := view.project(world)
				check(on_screen.is_finite(), "a ground point inside the theatre must always have a screen position")
				var back := view.unproject(on_screen)
				check(back.distance_to(world) < 0.01, "picking must invert the projection at tilt %.2f bearing %.2f" % [tilt, bearing])


func _check_tilt_compresses_the_far_ground() -> void:
	var view := _camera()
	view.tilt = VIEW.TILT_MAX
	var centre_scale: float = view.pixels_per_metre()
	var far: float = view.pixels_per_metre_at(view.centre + Vector2(0, -10000))
	var near: float = view.pixels_per_metre_at(view.centre + Vector2(0, 4000))
	check(far < centre_scale and near > centre_scale, "tilting must crowd the far ground and spread the near ground")
	# The camera may never invert: nothing above the horizon may resolve to ground.
	check(not view.map_offset_at_screen(Vector2(450, -100000)).is_finite(), "a ray above the horizon must have no ground answer")


func _check_bearing_turns_the_world() -> void:
	var view := _camera()
	var east := Vector2(5000, 0)
	var at_zero := view.project(east)
	view.set_bearing(PI * 0.5)
	var at_quarter := view.project(east)
	check(at_zero.distance_to(Vector2(450 + 5000 * view.pixels_per_metre(), 300)) < 0.001, "east must sit right of centre north-up")
	check(at_quarter.x < 460 and at_quarter.y < 300, "turning the camera right must carry east around toward the top of the map")
	view.set_bearing(TAU - 0.01)
	check(view.bearing > PI, "bearing must stay wound to a single turn")


func _check_limits_hold() -> void:
	var view := _camera()
	view.set_range(1.0)
	check(view.range_m == VIEW.MIN_RANGE, "zoom must stop at the closest view")
	view.set_range(9999999.0)
	check(view.range_m == VIEW.MAX_RANGE, "zoom must stop at the widest view")
	view.tilt_by(-1.0)
	check(view.tilt == 0.0, "the map must not tilt past overhead")
	view.tilt_by(10.0)
	check(is_equal_approx(view.tilt, VIEW.TILT_MAX), "the map must stop before the camera inverts")


func _check_anchor_zoom() -> void:
	var view := _camera()
	for tilt in [0.0, 0.4, VIEW.TILT_MAX]:
		view.settle()
		view.tilt = tilt
		var anchor := Vector2(120, 480)
		var held := view.unproject(anchor)
		view.set_range(2000.0, anchor)
		check(view.unproject(anchor).distance_to(held) < 0.01, "zooming about a point must keep that ground under it at tilt %.2f" % tilt)


func _check_drag_pins_the_ground() -> void:
	var view := _camera()
	view.tilt = 0.5
	var grab := view.unproject(Vector2(300, 200))
	view.drag(grab, Vector2(640, 430))
	check(view.project(grab).distance_to(Vector2(640, 430)) < 0.01, "the ground a drag started on must end under the finger")
	view.set_bearing(0.0)
	view.tilt = 0.0
	var before := view.centre
	var scale := view.pixels_per_metre()
	view.pan_pixels(Vector2(100, 0))
	check(view.centre.distance_to(before + Vector2(100, 0) / scale) < 0.001, "pushing the view right must slide the camera east")


func _check_inertia_settles() -> void:
	var view := _camera()
	view.fling(Vector2(900, 0), 2.0, 0.4)
	var travelled := 0.0
	var start := view.centre
	for frame in range(120):
		view.tick(1.0 / 60.0)
		travelled = start.distance_to(view.centre)
	check(travelled > 1000.0, "a fling must carry the map well past the release point")
	check(travelled < 6000.0, "a fling must run out rather than coast forever")
	view.tick(1.0)
	var resting := view.centre
	for frame in range(60):
		view.tick(1.0 / 60.0)
	check(view.centre == resting and view.tilt <= VIEW.TILT_MAX, "the camera must come to rest")


func _check_focus_glide() -> void:
	var view := _camera()
	view.set_bearing(2.0)
	view.tilt = 0.0
	view.begin_glide({"tilt": 0.3})
	check(view.is_gliding(), "a commanded move must animate rather than teleport")
	var fractions := []
	for frame in range(60):
		view.tick(1.0 / 60.0)
		fractions.append(view.tilt / 0.3)
		if not view.is_gliding():
			break
	check(is_equal_approx(view.tilt, 0.3), "a glide must arrive at its target")
	check(fractions[5] > 0.0 and fractions[5] < 0.35, "a glide must ease in rather than jump")
	check(fractions.size() >= 24 and fractions.size() <= 60, "a tilt change must take a sensible fraction of a second")
	view.set_bearing(0.0)
	view.focus_world(Vector2(30000, -30000), 1500.0)
	var seconds := 0.0
	while view.is_gliding() and seconds < 3.0:
		view.tick(1.0 / 60.0)
		seconds += 1.0 / 60.0
	check(seconds >= VIEW.FOCUS_MIN_SECONDS and seconds <= VIEW.FOCUS_MAX_SECONDS + 0.02, "a long focus move must take between 0.4 and 1 second")
	check(view.centre.distance_to(Vector2(30000, -30000)) < 1.0 and view.range_m > 1499.0, "the focus must land on the objective at the requested range")
	check(not view.follow_player, "flying the camera onto an objective must release ownship follow")
	view.settle()
	view.set_bearing(1.4)
	view.tilt = 0.9
	view.level_out()
	seconds = 0.0
	while view.is_gliding() and seconds < 2.0:
		view.tick(1.0 / 60.0)
		seconds += 1.0 / 60.0
	check(is_equal_approx(view.bearing, 0.0) and is_equal_approx(view.tilt, 0.0), "levelling out must return the map to north-up and overhead")
