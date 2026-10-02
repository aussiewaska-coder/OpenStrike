extends SceneTree

## The pixel check for the battle map camera. Headless cannot compile the map
## shader, so run this with a real Compatibility renderer -- xvfb plus softpipe
## works -- and look at the frames in --out= (default /tmp/battle_map):
##
##   xvfb-run -a -s "-screen 0 900x600x24" \
##     $GODOT_BIN --path . --rendering-driver opengl3 --script \
##     tools/check_battle_map.gd -- --out=/tmp/battle_map
##
## Every camera state the gesture layer can reach gets a frame, and each frame
## is checked for actually having been drawn: a shader that fails to compile or
## projects the ground away from the screen renders an empty backdrop, which
## looks fine until someone compares two frames.

const CANVAS := preload("res://scripts/ui/tactical_map_canvas.gd")
const VIEW := preload("res://scripts/battle_map/battle_map_view.gd")
const LEVELS := preload("res://scripts/battle_map/battle_map_layers.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const SIDE := 256

var failed := false


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _run() -> void:
	var out := "/tmp/battle_map"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	if DisplayServer.get_name() == "headless":
		push_error("Headless cannot compile the map shader; run this under a real renderer.")
		quit(1)
		return
	root.size = Vector2i(900, 600)
	root.content_scale_size = Vector2(900, 600)
	var map := CANVAS.new()
	root.add_child(map)
	map.size = Vector2(900, 600)
	map.set_layers(_terrain())
	map.set_state(Vector3(600, 40, -400), 0.6, _contacts(), -1, null)
	map.follow_player = false
	# Tilt 0 must look exactly like the map that shipped before it; the rest is
	# what the new camera adds.
	for state in [
		{"name": "a_overhead", "tilt": 0.0, "bearing": 0.0, "range": 12000.0, "style": 1},
		{"name": "b_lean_30", "tilt": 0.52, "bearing": 0.0, "range": 12000.0, "style": 1},
		{"name": "c_lean_60_turn_45", "tilt": VIEW.TILT_MAX, "bearing": 0.785, "range": 9000.0, "style": 1},
		{"name": "d_lean_60_turn_200", "tilt": 1.0, "bearing": -3.5, "range": 6000.0, "style": 1},
		{"name": "e_imagery_lean", "tilt": 0.7, "bearing": 0.4, "range": 3000.0, "style": 0},
		{"name": "f_close_lean", "tilt": 0.9, "bearing": 1.2, "range": 700.0, "style": 1},
		{"name": "g_wide", "tilt": 0.35, "bearing": -0.9, "range": 40000.0, "style": 2},
	]:
		map.centre = Vector2(600, -400)
		map.map_style = int(state["style"])
		map.bearing = float(state["bearing"])
		map.tilt = float(state["tilt"])
		map.set_range(float(state["range"]))
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = await _capture(out, String(state["name"]))
		_check(_has_pixels(image), "%s must render ground, not an empty backdrop" % state["name"])
		print("%s-%s.png ppm=%.5f tilt=%.2f bearing=%.2f" % [out, state["name"], map.pixels_per_metre(), map.tilt, map.bearing])
	# The Phase 2 promise, in pictures. Zooming out has to change what the map
	# says about the same ground, so the same five-ship is drawn at each density
	# and the frames are compared in pixels as well as looked at: three sizes of
	# the same picture would pass a glance and fail this.
	map.map_style = 1
	map.bearing = 0.0
	map.tilt = 0.0
	map.set_state(Vector3(600, 40, -400), 0.6, _flight(), -1, null)
	map.follow_player = false
	var frames := {}
	for density in [
		{"name": "i_theatre", "metres": 40000.0, "level": LEVELS.Level.THEATRE, "groups": 1, "tracks": 0},
		{"name": "j_regional", "metres": 18000.0, "level": LEVELS.Level.REGIONAL, "groups": 1, "tracks": 1},
		{"name": "k_tactical", "metres": 2600.0, "level": LEVELS.Level.TACTICAL, "groups": 0, "tracks": 6},
	]:
		map.centre = Vector2(600, -400)
		map.set_range(float(density["metres"]))
		await process_frame
		await process_frame
		_check(
			int(map.semantic.level()) == int(density["level"]),
			"%s m must read as %s, got %s" % [
				density["metres"], LEVELS.level_name(int(density["level"])),
				LEVELS.level_name(map.semantic.level())])
		var groups := 0
		var tracks := 0
		var report := []
		for item in map.markers():
			if bool(item["individual"]):
				tracks += 1
				report.append(String(item["contact"]["name"]))
			else:
				groups += 1
				var group: Dictionary = item["group"]
				report.append("%s of %d" % [group["label"], int(group["count"])])
		_check(
			groups == int(density["groups"]) and tracks == int(density["tracks"]),
			"%s must draw %d formation markers and %d lone tracks, got %d and %d" % [
				density["name"], int(density["groups"]), int(density["tracks"]), groups, tracks])
		print("%s: %s -> %s" % [density["name"], LEVELS.level_name(map.semantic.level()), ", ".join(PackedStringArray(report))])
		frames[String(density["name"])] = await _capture(out, String(density["name"]))
	_check(
		_changed(frames["i_theatre"], frames["k_tactical"]) > 0.002,
		"a theatre frame must not be the tactical frame at another scale: %.5f of it changed"
		% _changed(frames["i_theatre"], frames["k_tactical"]))
	# A phone held upright puts the horizon inside the screen at max tilt, so the
	# grid has to survive corners that look at nothing.
	root.size = Vector2i(390, 844)
	root.content_scale_size = Vector2(390, 844)
	map.size = Vector2(390, 844)
	map.bearing = 0.6
	map.tilt = VIEW.TILT_MAX
	map.set_range(8000.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var portrait: Image = root.get_texture().get_image()
	_check(_has_pixels(portrait), "a portrait tilt must still render ground")
	_check(portrait.save_png("%s-h_portrait_lean.png" % out) == OK, "the portrait frame must save")
	print("%s-h_portrait_lean.png visible ground=%s" % [out, map._visible_ground()])
	# Leaning the camera must crowd the distant ground toward the horizon, which
	# is what lets a tilted view show more of the front than the flat one does.
	map.bearing = 0.0
	map.tilt = 0.0
	map.set_range(12000.0)
	var centre_line: Vector2 = map.size * 0.5
	var flat: float = map.world_to_screen(Vector2(600, -12000)).distance_to(centre_line)
	map.tilt = 1.0
	await process_frame
	var leaned: float = map.world_to_screen(Vector2(600, -12000)).distance_to(centre_line)
	_check(leaned < flat, "the far ground must crowd toward the horizon as the map leans")
	if failed:
		print("BATTLE_MAP_RENDER_FAILED")
		quit(1)
	else:
		print("BATTLE_MAP_RENDER_OK")
		quit(0)


## One drawn frame, saved and handed back for comparison. Measuring a picture
## that was never looked at proves nothing, and looking at one that was never
## measured proves nothing either.
func _capture(out: String, name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(_has_pixels(image), "%s must render something, not an empty backdrop" % name)
	_check(image.save_png("%s-%s.png" % [out, name]) == OK, "%s must save" % name)
	return image


## The fraction of sampled pixels two frames disagree about. Two densities that
## differ only in how large the same symbols are drawn cannot move much of the
## picture; a report that changes shape moves far more than this.
func _changed(one: Image, two: Image) -> float:
	if one == null or two == null:
		return 0.0
	var width := mini(one.get_width(), two.get_width())
	var height := mini(one.get_height(), two.get_height())
	var samples := 0
	var different := 0
	for y in range(0, height, 3):
		for x in range(0, width, 3):
			var at := Vector2i(x, y)
			var mine := one.get_pixelv(at)
			var theirs := two.get_pixelv(at)
			samples += 1
			if absf(mine.r - theirs.r) + absf(mine.g - theirs.g) + absf(mine.b - theirs.b) > 0.06:
				different += 1
	return float(different) / float(maxi(samples, 1))


## Six tracks: a five-ship tight enough to stay one report at every density,
## plus a lone jet far enough out that a theatre merges it into that report and a
## region does not. That split is the whole Phase 2 claim, so the frames have to
## show it rather than only the count.
func _flight() -> Array:
	return [
		TRACKER.contact(11, TRACKER.Kind.AIR_JET, Vector3(-300, 900, -700), Vector3(0, 0, -220), "LEAD"),
		TRACKER.contact(12, TRACKER.Kind.AIR_JET, Vector3(500, 950, -200), Vector3(0, 0, -220), "WING"),
		TRACKER.contact(13, TRACKER.Kind.AIR_DRONE, Vector3(-100, 300, 600), Vector3(60, 0, -180), "SCOUT"),
		TRACKER.contact(14, TRACKER.Kind.AIR_JET, Vector3(900, 1100, 800), Vector3(-30, 0, -240), "TRAIL"),
		TRACKER.contact(15, TRACKER.Kind.GROUND_LAUNCHER, Vector3(200, 20, 1200), Vector3.ZERO, "SAM"),
		TRACKER.contact(16, TRACKER.Kind.AIR_JET, Vector3(0, 700, 7400), Vector3(0, 0, -240), "SHEET"),
	]


func _has_pixels(image: Image) -> bool:
	var seen := {}
	var luminance := 0.0
	var samples := 0
	for step in range(0, image.get_width() * image.get_height(), 997):
		var pixel := Vector2(step % image.get_width(), step / image.get_width())
		var colour := image.get_pixelv(pixel)
		luminance += colour.get_luminance()
		samples += 1
		seen[colour.to_html(false)] = true
		if samples > 4000:
			break
	return samples > 0 and luminance / float(samples) > 0.01 and seen.size() > 8


func _terrain() -> Dictionary:
	var height := Image.create(SIDE, SIDE, false, Image.FORMAT_RF)
	var aerial := Image.create(SIDE, SIDE, false, Image.FORMAT_RGB8)
	for y in range(SIDE):
		for x in range(SIDE):
			var land := 0.18 + 0.42 * sin(float(x) * 0.031) * cos(float(y) * 0.022) \
				+ 0.25 * sin(float(x) * 0.008 + float(y) * 0.017)
			var sea := float(x) < 42.0 + 18.0 * sin(float(y) * 0.05)
			var relief := 0.0 if sea else maxf(0.0, land)
			height.set_pixel(x, y, Color(relief, 0.0, 0.0))
			aerial.set_pixel(x, y, Color(0.05, 0.16, 0.28) if sea else Color(
				0.14 + relief * 0.42, 0.26 + relief * 0.34, 0.12 + relief * 0.20))
	return {
		"world_size_m": 24000.0,
		"height": height,
		"aerial": ImageTexture.create_from_image(aerial),
		"metadata": {"elevation_min_m": -10.0, "elevation_max_m": 400.0},
		"places": [],
		"details": [],
	}


func _contacts() -> Array:
	return [
		TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(-2400, 900, -3200), Vector3.ZERO, "BANDIT 01"),
		TRACKER.contact(2, TRACKER.Kind.GROUND_LAUNCHER, Vector3(2600, 0, 1900), Vector3.ZERO, "SAM 02"),
		TRACKER.contact(3, TRACKER.Kind.BUILDING, Vector3(900, 0, -2600), Vector3.ZERO, "RALLY POINT"),
	]
