extends SceneTree

## The battle map over the real theatre. `check_battle_map.gd` draws a synthetic
## island so it can run without HTTP; this one streams the cached Gold Coast /
## Tweed elevation and imagery through the production terrain node and points the
## new camera at it, which is what the acceptance asks for: pan, pinch zoom,
## rotate and tilt over terrain that is actually geographic, with the contacts,
## place labels and streamed detail chunks still lined up on it.
##
##   xvfb-run -a -s "-screen 0 900x600x24" \
##     $GODOT_BIN --path . --rendering-driver opengl3 --script \
##     tools/check_battle_map_terrain.gd -- --out=/tmp/bmt
##
## `--out=` is a filename prefix: the frames land at /tmp/bmt-a_satellite_overhead.png
## and friends. Imagery comes from the same `user://map_cache` the game fills, so
## a warm cache makes this repeatable offline as long as the sizes asked for are
## cached.
##
## The last frames of the run belong to the war: the same camera shot with the
## territory layer on and off, and then the objects the war is fought over drawn
## on the ground they really stand on, so both overlays' claims -- control you can
## read without losing the terrain under it, and an airfield whose runway is as long
## in pixels as it is in metres -- are measured rather than eyeballed.

const CANVAS := preload("res://scripts/ui/tactical_map_canvas.gd")
const VIEW := preload("res://scripts/battle_map/battle_map_view.gd")
## `streamed_terrain.gd` names the TileClient autoload, which is not registered
## yet when a `--script` run preloads it, so the terrain arrives the way the
## map's own tests take it: by `load()`, once the singletons exist.
const TERRAIN := "res://scripts/terrain/streamed_terrain.gd"
const MAP_TILES := preload("res://scripts/terrain/map_tiles.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const NAVIGATION := preload("res://scripts/ui/tactical_navigation.gd")
const WAR_REGIONS := preload("res://scripts/war/war_regions.gd")
const WAR_CONTROL := preload("res://scripts/war/war_control.gd")
const WAR_OBJECTS := preload("res://scripts/war/war_objects.gd")
const WAR_DIRECTOR := preload("res://scripts/war/war_director.gd")
const STRATEGY := preload("res://scripts/battle_map/battle_map_strategy.gd")

var failed := false
var _started := Time.get_ticks_msec()


func _init() -> void:
	call_deferred("_run")


## The streaming phases are printed with their elapsed seconds so a slow run on
## a phone CPU can be told apart from a stuck one.
func _note(message: String) -> void:
	print("%5.1fs %s" % [float(Time.get_ticks_msec() - _started) / 1000.0, message])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _run() -> void:
	var out := "/tmp/battle_map_terrain"
	var region_id := "au_gold_coast_tweed_corridor"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
		elif argument.begins_with("--region="):
			region_id = argument.trim_prefix("--region=")
	if DisplayServer.get_name() == "headless":
		push_error("Headless cannot compile the map shader; run this under a real renderer.")
		quit(1)
		return
	root.size = Vector2i(900, 600)
	root.content_scale_size = Vector2(900, 600)
	var region := _region(region_id)
	if region.is_empty():
		push_error("Theatre %s is not in the region catalog." % region_id)
		quit(1)
		return
	var terrain = load(TERRAIN).new()
	root.add_child(terrain)
	terrain.status_changed.connect(_note)
	var world_size := float(region.get("world_size_m", 50000.0))
	var spawn := MAP_TILES.world_of(
		MAP_TILES.region_bounds(
			float(region.get("center_latitude", 0.0)), float(region.get("center_longitude", 0.0)), world_size),
		float(region.get("spawn_latitude", 0.0)), float(region.get("spawn_longitude", 0.0)), world_size)
	var focus := Node3D.new()
	root.add_child(focus)
	focus.global_position = Vector3(spawn.x, 900.0, spawn.y)
	await process_frame
	var loaded: bool = await terrain.load_region(region)
	_check(loaded, "the streamed theatre must load")
	if not loaded:
		print("BATTLE_MAP_TERRAIN_FAILED")
		quit(1)
		return
	terrain.set_focus(focus)
	var layers: Dictionary = terrain.tactical_map_layers()
	_note("theatre loaded: height=%s aerial=%s details=%d" % [
		str(layers.get("height")), layers.get("aerial") != null, layers.get("details", []).size()])
	var map := CANVAS.new()
	root.add_child(map)
	map.size = Vector2(900, 600)
	map.set_layers(layers)
	var route := NAVIGATION.new()
	for offset in [Vector2(3000, -2000), Vector2(9000, -6000), Vector2(14000, -3000)]:
		route.add(Vector3(spawn.x + offset.x, 700.0, spawn.y + offset.y))
	var contacts := _contacts(layers, spawn, world_size)
	map.set_state(focus.global_position, -0.26, contacts, int(contacts[0].handle), route)
	map.follow_player = false
	var grid: Image = layers.get("height")
	_check(grid != null and grid.get_width() >= 512, "the theatre elevation grid must reach the map")
	_check(layers.get("aerial") != null, "the theatre overview imagery must reach the map")
	var places: Array = layers.get("places", [])
	_check(places.size() >= 5, "the corridor place labels must reach the map")
	for state in [
		{"name": "a_satellite_overhead", "tilt": 0.0, "bearing": 0.0, "range": 12000.0, "style": 0},
		{"name": "b_satellite_lean_30", "tilt": 0.52, "bearing": 0.0, "range": 12000.0, "style": 0},
		{"name": "c_satellite_lean_60", "tilt": VIEW.TILT_MAX, "bearing": 0.785, "range": 9000.0, "style": 0},
		{"name": "d_terrain_lean_30", "tilt": 0.52, "bearing": -0.9, "range": 20000.0, "style": 2},
		{"name": "e_simple_wide", "tilt": 0.2, "bearing": 2.4, "range": 40000.0, "style": 1},
	]:
		map.centre = spawn
		map.map_style = int(state["style"])
		map.bearing = float(state["bearing"])
		map.tilt = float(state["tilt"])
		map.set_range(float(state["range"]))
		await _frame()
		_check(_round_trips(map, layers, world_size), "%s: screen_to_world must invert world_to_screen" % state["name"])
		var image: Image = root.get_texture().get_image()
		_check(_has_pixels(image), "%s must render the theatre, not an empty backdrop" % state["name"])
		_check(image.save_png("%s-%s.png" % [out, state["name"]]) == OK, "%s must save" % state["name"])
		_note("%s-%s.png ppm=%.5f tilt=%.2f bearing=%.2f labels=%d" % [
			out, state["name"], map.pixels_per_metre(), map.tilt, map.bearing, map.place_labels().size()])
		var drawn := []
		var reachable := {}
		for contact in contacts:
			var at: Vector2 = map.world_to_screen(Vector2(contact.position.x, contact.position.z))
			if not Rect2(Vector2.ZERO, map.size).grow(-12).has_point(at):
				continue
			_check(map.contact_at(at) == int(contact.handle),
				"%s: %s must still be selectable where it is drawn" % [state["name"], contact.get("name", "")])
			drawn.append(int(contact.handle))
			# The tap a player actually makes is the semantic one. Over a theatre a
			# track is inside a report rather than under the finger, so what has to
			# hold is that every drawn track is reachable -- as itself or as a
			# member of the group its symbol was merged into.
			var marker := map.marker_at(at)
			if marker.has("handles"):
				for handle in marker["handles"]:
					reachable[int(handle)] = true
			elif marker.has("handle"):
				reachable[int(marker["handle"])] = true
		_check(not drawn.is_empty(), "%s: at least one contact must be on the map at %.0f km" % [state["name"], float(state["range"]) / 1000.0])
		for handle in drawn:
			_check(bool(reachable.get(handle, false)),
				"%s: nothing may be drawn and untappable; handle %d is reachable by neither a track nor a group" % [
					state["name"], handle])
	# Streamed detail is the layer the synthetic fixture cannot supply: the canvas
	# textures real chunk quads through the same ground projection, so a lean has
	# to keep them on the terrain they belong to. The terrain asks for them the
	# same way it does in flight, and the MFD refreshes its layer references once
	# a second, so this waits on the same cadence rather than inventing one.
	for attempt in range(300):
		await process_frame
		if attempt % 30 == 29:
			layers = terrain.tactical_map_layers()
			map.set_layers(layers)
		if not layers.get("details", []).is_empty():
			break
	map.map_style = 0
	map.centre = spawn
	map.bearing = 0.3
	map.tilt = 0.6
	map.set_range(3000.0)
	await _frame()
	var close: Image = root.get_texture().get_image()
	_check(_has_pixels(close), "a close view must render ground")
	_check(close.save_png("%s-f_close_detail.png" % [out]) == OK, "the close frame must save")
	_note("detail chunks resident=%d" % layers.get("details", []).size())
	_check(not layers.get("details", []).is_empty(), "streamed detail chunks must reach the map")
	# A phone held upright at full lean puts the horizon on the screen.
	root.size = Vector2i(390, 844)
	root.content_scale_size = Vector2(390, 844)
	map.size = Vector2(390, 844)
	map.centre = spawn
	map.bearing = 0.6
	map.tilt = VIEW.TILT_MAX
	map.set_range(8000.0)
	await _frame()
	var portrait: Image = root.get_texture().get_image()
	_check(_has_pixels(portrait), "a portrait lean over the theatre must render ground")
	_check(portrait.save_png("%s-g_portrait_lean.png" % [out]) == OK, "the portrait frame must save")
	_check(_round_trips(map, layers, world_size), "portrait: the projection must still invert")
	# Leaning must crowd the distant ground toward the horizon, at the real 50 km
	# theatre size and not just at the synthetic fixture's 24 km.
	map.size = Vector2(900, 600)
	root.size = Vector2i(900, 600)
	map.bearing = 0.0
	map.tilt = 0.0
	map.set_range(20000.0)
	var centre_line: Vector2 = map.size * 0.5
	var flat: float = map.world_to_screen(spawn + Vector2(0, -20000)).distance_to(centre_line)
	map.tilt = 1.0
	await process_frame
	var leaned: float = map.world_to_screen(spawn + Vector2(0, -20000)).distance_to(centre_line)
	_check(leaned < flat, "the far ground must crowd toward the horizon as the map leans")
	await _war_layers(map, region, spawn, out)
	if failed:
		print("BATTLE_MAP_TERRAIN_FAILED")
		quit(1)
	else:
		print("BATTLE_MAP_TERRAIN_OK")
		quit(0)


func _frame() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


## The layer fades are in seconds, so waiting on a fixed number of frames is how
## a check says "let it settle" without assuming a frame rate.
func _hold(frames: int) -> void:
	for waiting in range(frames):
		await process_frame


## The war over the real theatre, in pixels.
##
## The frame taken before `set_war` is the control, and it is the whole point of
## doing this here: Territory has no source until the theatre's own regions are
## handed over, so the before frame is the map exactly as Phase 2 shipped it and
## the after frame differs from it by the overlay and nothing else. That is what
## lets the brief's "clearly communicates territorial control while retaining
## underlying terrain visibility" be measured instead of admired -- an overlay
## that hides the satellite imagery flattens the picture's detail, and one you
## can see the coast through does not.
func _war_layers(map: CANVAS, region: Dictionary, spawn: Vector2, out: String) -> void:
	map.map_style = 0
	map.bearing = 0.0
	map.tilt = 0.0
	map.centre = spawn
	map.set_range(18000.0)
	await _frame()
	var imagery: Image = root.get_texture().get_image()
	_check(
		map.semantic.alpha(&"territory") <= 0.01,
		"territory must stay silent until a war reaches the map")
	var geography := WAR_REGIONS.new()
	var situation := WAR_CONTROL.new()
	_check(
		geography.load_theatre(region),
		"the theatre's districts must load over the terrain they are drawn on")
	situation.setup(geography)
	map.set_war(geography, situation)
	_check(map.territory.is_ready(), "the territory layer must be drawn once the war is on it")
	_check(
		map.semantic.has_source(&"territory"),
		"a theatre with authored regions must not report Territory as empty")
	await _hold(40)
	_check(
		map.semantic.alpha(&"territory") > 0.9,
		"the overlay must reach full strength at regional density, got %.2f"
		% map.semantic.alpha(&"territory"))
	var war: Image = root.get_texture().get_image()
	_check(war.save_png("%s-h_territory_regional.png" % out) == OK, "the regional frame must save")
	var drawn := _changed(imagery, war)
	_check(
		drawn > 0.05,
		"the war must actually be on the map, not a layer that is nominally enabled: %.4f of the frame changed"
		% drawn)
	var before := _measure(imagery)
	var after := _measure(war)
	_check(
		after["detail"] > float(before["detail"]) * 0.6,
		"the terrain's own detail must survive the overlay: %.4f of it before, %.4f after" % [
			before["detail"], after["detail"]])
	_check(
		absf(float(after["luminance"]) - float(before["luminance"])) < 0.06,
		"a control wash must not repaint the theatre wholesale: %.3f before, %.3f after" % [
			before["luminance"], after["luminance"]])
	_note("territory: changed=%.3f detail=%.4f->%.4f luminance=%.3f->%.3f" % [
		drawn, before["detail"], after["detail"], before["luminance"], after["luminance"]])
	# What the module hands the canvas, counted where the culling has had its say:
	# claimed ground, contested ground carrying both claims at once, and a front
	# whose direction is drawn only where the two organised sides actually meet.
	# The front is wherever those sides meet, which is not necessarily in front of
	# the spawn, so the map is pointed at the fighting before asking whether it is
	# drawn.
	var meeting := Vector2.ZERO
	var genuine := 0
	for segment in situation.front():
		meeting += segment["middle"] as Vector2
		if String(segment["kind"]) == "FRONT":
			genuine += 1
	meeting /= float(maxi(situation.front().size(), 1))
	_check(genuine > 0, "the opening situation must put two organised sides face to face")
	map.centre = meeting
	map.set_range(40000.0)
	await _hold(40)
	var batch: Dictionary = map.territory.batch(
		map._projector(), map._visible_ground(), map.semantic.alpha(&"territory"),
		map.pixels_per_metre())
	var edges: Array = batch["edges"]
	var marks: Array = batch["front"]
	var dashes := 0
	for edge in edges:
		if (edge["path"] as PackedVector2Array).size() == 2:
			dashes += 1
	var arrows := 0
	var quiet := 0
	for mark in marks:
		if mark.has("arrow"):
			arrows += 1
		else:
			quiet += 1
	var widest := 0.0
	for fill in batch["fills"]:
		widest = maxf(widest, float((fill["colour"] as Color).a))
	_check(batch["fills"].size() >= 6, "the ground on screen must be claimed, got %d districts" % batch["fills"].size())
	_check(widest < 0.3, "a control area must be something the terrain shows through, got alpha %.2f" % widest)
	_check(dashes > 0, "contested ground must be hatched in both claims, got %d strokes" % dashes)
	_check(arrows > 0, "a blue-against-red border must show which way it is being pushed")
	_check(quiet > 0, "an edge against contested ground must be drawn without a chevron")
	_note("war: districts=%d hatch=%d edges=%d chevrons=%d wash=%.2f" % [
		batch["fills"].size(), dashes, marks.size(), arrows, widest])
	await _shot(out, "i_territory_theatre")
	# Leaning the camera must move the overlay with the ground it describes, so
	# the same tilt is shot twice and the only difference is the layer.
	map.set_range(12000.0)
	map.bearing = 0.5
	map.tilt = 0.7
	await _hold(40)
	_check(map.semantic.toggle(&"territory"), "Territory must be switchable while the war is on it")
	await _hold(40)
	var bare_lean: Image = await _shot(out, "j_territory_unmarked_lean")
	_check(map.semantic.toggle(&"territory"), "Territory must come back on")
	await _hold(40)
	var leaned: Image = await _shot(out, "k_territory_lean")
	_check(
		_changed(bare_lean, leaned) > 0.03,
		"the overlay must stay welded to the districts through a lean: %.4f changed"
		% _changed(bare_lean, leaned))
	# The two things the phase must not break: the war is a density of information,
	# so it goes away over the suburb view, and with the layer switched off the
	# map is the pre-war picture again to within the pixel noise.
	map.bearing = 0.0
	map.tilt = 0.0
	map.set_range(2600.0)
	await _hold(40)
	_check(
		map.semantic.alpha(&"territory") <= 0.02,
		"a tactical view is for the fight in front of you, not the war (%.2f)"
		% map.semantic.alpha(&"territory"))
	_check(
		map.territory.batch(
			map._projector(), map._visible_ground(), map.semantic.alpha(&"territory"),
			map.pixels_per_metre())["fills"].is_empty(),
		"nothing may be drawn for a layer the density has faded out")
	map.centre = spawn
	map.set_range(18000.0)
	await _hold(40)
	_check(map.semantic.toggle(&"territory"), "Territory must be switchable from the rail")
	await _hold(40)
	var hidden: Image = await _shot(out, "l_territory_off")
	_check(
		_changed(imagery, hidden) < 0.02,
		"switching the war off must return the map that shipped before it: %.4f still different"
		% _changed(imagery, hidden))
	# Left enabled, because the toggle persists and a check that leaves the layer
	# off would quietly change what the next run of the game draws.
	_check(map.semantic.toggle(&"territory"), "Territory must be left on")
	await _campaign_drift(map, spawn, out, geography, situation)
	await _strategic_layers(map, region, spawn, out, geography, situation)


## The war, moving the map it is drawn on.
##
## Everything above draws the situation the corridor was authored with. This is the
## Phase 5 claim in pixels: a director is seated on the same two tables the canvas
## already reads, run for a quarter of an hour of campaign time with nobody flying,
## and the same camera is asked again. The overlay is off, the camera is unmoved and
## the imagery is cached, so the only thing the two pictures can disagree about is
## ground that changed hands -- which makes one pixel count the whole data path,
## simulation through publishing through the territory layer, measured at once.
func _campaign_drift(
	map: CANVAS, spawn: Vector2, out: String,
	geography: WAR_REGIONS, situation: WAR_CONTROL) -> void:
	map.centre = spawn
	map.set_range(18000.0)
	await _hold(40)
	var opening: Image = await _shot(out, "m_territory_opening")
	# What the same camera says twice with nothing changed is this check's noise floor:
	# imagery tiles arriving late, the panel's own animation, dithering. Without it
	# "the frame differs" is unfalsifiable, because a frame always differs.
	map.queue_redraw()
	await _hold(40)
	var noise := _changed(opening, root.get_texture().get_image())
	var held := {}
	for record in geography.regions():
		var region: Dictionary = record
		held[String(region["id"])] = situation.owner_of(String(region["id"]))
	var campaign := WAR_DIRECTOR.new()
	_check(
		campaign.setup(situation, geography),
		"the campaign must seat on the theatre the map is looking at")
	var ticks := campaign.simulate(900.0)
	_check(ticks > 0, "a quarter of an hour must be several ticks, got %d" % ticks)
	var moved := 0
	for id in held:
		if situation.owner_of(String(id)) != String(held[id]):
			moved += 1
	_check(moved > 0, "the war must move the ground this map is drawn from")
	map.queue_redraw()
	await _hold(40)
	var later: Image = await _shot(out, "n_territory_after_campaign")
	var shifted := _changed(opening, later)
	_check(
		shifted > noise + 0.001,
		"districts that changed hands must be drawn as having changed them: %.5f of the frame moved, %.5f of it is the camera moving anyway"
		% [shifted, noise])
	_note("campaign: ticks=%d moved=%d/%d repainted=%.4f noise=%.4f" % [
		ticks, moved, held.size(), shifted, noise])


## The objects of the war, over the terrain they are made from.
##
## The registry is built from the same corridor the camera is looking at, which is
## the only way the brief's "objects must correspond to actual world locations" can
## be answered in pixels: an airfield symbol is right when its drawn pavement is as
## long as the runway is in metres at the map's own scale, and a tap on it gives back
## that airfield's record rather than whatever mark happens to be nearby. The before
## frame is shot with the war's own overlay already on, so everything the two frames
## disagree about is the symbol table and nothing else.
func _strategic_layers(
	map: CANVAS, region: Dictionary, spawn: Vector2, out: String,
	geography: WAR_REGIONS, situation: WAR_CONTROL) -> void:
	map.map_style = 0
	map.bearing = 0.0
	map.tilt = 0.0
	map.centre = spawn
	map.set_range(18000.0)
	await _hold(40)
	_check(not map.strategy.is_ready(), "nothing may be claimed for a registry the map has not been handed")
	_check(not map.semantic.has_source(&"objects"), "and the layer must say it is empty")
	_check(not map.semantic.toggle(&"objects"), "an empty layer refuses its toggle rather than pretending to switch")
	_check(_symbols(map).is_empty(), "and draws nothing")
	var bare: Image = await _shot(out, "m_objects_unmarked")
	var objects := WAR_OBJECTS.new()
	_check(
		objects.load_theatre(region, geography, situation),
		"the corridor must supply the airfields, sites and landmarks the brief names")
	map.set_objects(objects)
	_check(map.strategy.is_ready(), "the map must read the registry it was handed")
	_check(map.semantic.has_source(&"objects"), "a theatre with objects must not report the layer empty")
	await _hold(40)
	_check(
		map.semantic.alpha(&"objects") > 0.9,
		"objects are worth a symbol at every density, got %.2f" % map.semantic.alpha(&"objects"))
	var marked: Image = await _shot(out, "n_objects_regional")
	var drawn := _changed(bare, marked)
	_check(
		drawn > 0.004,
		"the objects must actually be on the map, not a layer nominally enabled: %.4f of the frame changed"
		% drawn)
	var before := _measure(bare)
	var after := _measure(marked)
	_check(
		after["detail"] > float(before["detail"]) * 0.8,
		"line work over the imagery must not flatten the terrain under it: %.4f before, %.4f after" % [
			before["detail"], after["detail"]])
	_check(
		absf(float(after["luminance"]) - float(before["luminance"])) < 0.04,
		"and must not repaint it either: %.3f before, %.3f after" % [
			before["luminance"], after["luminance"]])
	# A symbol is a report about one point of ground, so the check that matters over
	# real geography is that the drawn point and the registry's point project to the
	# same pixel -- the same test the contacts pass runs, against the terrain's own
	# streamed projection rather than a synthetic island.
	var items := _symbols(map)
	_check(
		not items.is_empty(),
		"over the regional view the corridor's objects must be on the map, got %d symbols" % items.size())
	for item in items:
		var object := map.strategic_object(int(item["id"]))
		_check(not object.is_empty(), "every drawn symbol reads back through its own id")
		if object.is_empty():
			continue
		_check(
			(map.world_to_screen(object["world_position"]) as Vector2).distance_to(
				item["at"] as Vector2) < 1.0,
			"%s must be drawn where it stands, not where the map guessed" % String(object["name"]))
		_check(not (item["paths"] as Array).is_empty(), "%s must have a glyph to draw" % String(object["name"]))
	_note("objects: registry=%d regional symbols=%d changed=%.4f detail=%.4f->%.4f" % [
		objects.count(), items.size(), drawn, before["detail"], after["detail"]])
	# The density rule for this layer drops names, not things: at theatre range the
	# map is read for the shape of the war, so only what is worth planning against is
	# labelled and only what is worth a symbol is drawn.
	map.set_range(40000.0)
	await _hold(40)
	var far := _symbols(map)
	var worth := 0
	for record in objects.objects():
		if float(record["strategic_value"]) >= STRATEGY.DRAWN_VALUE:
			worth += 1
	_check(far.size() > 0 and far.size() <= worth, "the theatre draws the objects worth drawing, got %d of %d" % [
		far.size(), worth])
	var named := 0
	var faint := 0
	for item in far:
		var object := map.strategic_object(int(item["id"]))
		_check(float(object["strategic_value"]) >= STRATEGY.DRAWN_VALUE,
			"nothing below the drawing floor may be symbolled at theatre range, got %s" % String(object["name"]))
		if not String(item["label"]).is_empty():
			named += 1
			_check(
				bool(object["discovered"]) and float(object["strategic_value"]) >= STRATEGY.THEATRE_LABEL_VALUE,
				"a name over the whole theatre is a promise about the ground, got %s" % String(item["label"]))
			_check(String(item["sub"]).is_empty(), "the type belongs under the name only in a close view")
		if not bool(object["discovered"]):
			faint += 1
			_check(
				absf(float((item["colour"] as Color).a) - map.semantic.alpha(&"objects") * STRATEGY.UNCONFIRMED)
				< 0.01,
				"a position that has only ever been an estimate must not look as certain as a seen one")
	await _shot(out, "o_objects_theatre")
	_note("objects: theatre symbols=%d/%d worth drawing, named=%d unconfirmed=%d" % [
		far.size(), worth, named, faint])
	await _check_the_airfield(map, objects, out, spawn)


## The airfield, measured. An aerodrome's longest strip is the one object whose drawn
## size can be checked against a published number, and flying onto it is the planning
## gesture the brief asks for: the war's own wash fades out of a tactical view and the
## thing flown for stays.
func _check_the_airfield(map: CANVAS, objects: WAR_OBJECTS, out: String, spawn: Vector2) -> void:
	var field := _airfield(objects)
	_check(not field.is_empty(), "the corridor must have an airfield to fly to")
	if field.is_empty():
		return
	map.centre = field["world_position"]
	map.set_range(2600.0)
	await _hold(40)
	_check(
		map.semantic.alpha(&"territory") <= 0.02,
		"a tactical view is for the ground in front of you, not the war (%.2f)"
		% map.semantic.alpha(&"territory"))
	_check(
		map.semantic.alpha(&"objects") > 0.9,
		"and the object is still drawn here (%.2f)" % map.semantic.alpha(&"objects"))
	var here := {}
	for item in _symbols(map):
		if int(item["id"]) == int(field["id"]):
			here = item
	_check(not here.is_empty(), "flying onto the airfield puts its symbol on the map")
	if here.is_empty():
		return
	var pixels := map.pixels_per_metre()
	var pavement := 0.0
	for strip in (here["strips"] as Array):
		var ends: Array = strip
		pavement = maxf(pavement, (ends[0] as Vector2).distance_to(ends[1] as Vector2))
	var longest := float(field["detail"]["longest_m"])
	_check(
		(here["strips"] as Array).size() == (field["detail"]["strips"] as Array).size(),
		"every authored strip of the aerodrome is drawn, got %d of %d" % [
			(here["strips"] as Array).size(), (field["detail"]["strips"] as Array).size()])
	_check(
		pavement > 0.0 and absf(pavement / pixels - longest) / longest < 0.05,
		"the drawn runway is the real one: %.0f px at %.5f px per metre is %.0f m, the strip is %.0f m" % [
			pavement, pixels, pavement / pixels, longest])
	_check(String(here["label"]) == String(field["name"]), "a close view names the place")
	_check(String(here["sub"]) == WAR_OBJECTS.type_name(field), "with its type under the name")
	_note("airfield: %s · longest strip drawn %.0f px at %.5f px per metre = %.0f m, authored %.0f m" % [
		String(field["detail"]["icao"]), pavement, pixels, pavement / pixels, longest])
	await _shot(out, "p_objects_airfield")
	# The map's own answer about the ground its symbol stands on. The exercise tracks
	# this run flies are parked on the corridor's own labels, and one of them stands on
	# the aerodrome itself -- which is the priority rule rather than a mistake: a live
	# track is what a tap must give, and the object is what the map says is drawn there.
	var at: Vector2 = map.world_to_screen(field["world_position"])
	var hit := map.strategic_at(at)
	_check(
		int(hit.get("id", -1)) == int(field["id"]),
		"the object answers where its symbol is drawn, got %s" % str(hit.get("name", "nothing")))
	var answers := {}
	map.strategic_selected.connect(func(id: int) -> void: answers["object"] = id)
	map.contact_selected.connect(func(handle: int) -> void: answers["contact"] = handle)
	map.select_at(at)
	var marker := map.marker_at(at)
	if marker.has("handle"):
		_check(
			int(answers.get("contact", -1)) == int(marker["handle"]),
			"a live track standing on the airfield is what the tap must give, got %s" % str(answers.keys()))
		_check(not answers.has("object"), "and the strategic layer must not steal a contact's tap")
	else:
		_check(not marker.has("group"), "a formation drawn over the aerodrome is a case this check cannot speak to")
		_check(
			int(answers.get("object", -1)) == int(field["id"]),
			"with nothing standing on it the tap selects the airfield, got %s" % str(answers.keys()))
	# Leaning the camera moves the ground under the symbol; the only thing that may
	# differ between the two lean frames is the layer, which is what "welded" means.
	map.bearing = 0.6
	map.tilt = 0.7
	await _hold(40)
	_check(map.semantic.toggle(&"objects"), "Objects must be switchable over the airfield")
	await _hold(40)
	var unmarked: Image = await _shot(out, "q_objects_lean_unmarked")
	_check(map.semantic.toggle(&"objects"), "Objects must come back on")
	await _hold(40)
	var leaned := {}
	for item in _symbols(map):
		if int(item["id"]) == int(field["id"]):
			leaned = item
	_check(not leaned.is_empty(), "the airfield must still be drawn through a lean")
	if not leaned.is_empty():
		var moved: Vector2 = map.world_to_screen(field["world_position"])
		_check(
			moved.distance_to(leaned["at"] as Vector2) < 1.0,
			"and welded to the ground the tilt moved")
		_check(not map.strategic_at(moved).is_empty(), "still tappable where the tilt put it")
	var marking: Image = await _shot(out, "r_objects_airfield_lean")
	# A symbol is a small thing on a whole-screen map, so the frame-wide fraction is
	# the wrong ruler here: what has to be true is that the layer paints a mark on the
	# ground the tilt moved the symbol onto, and that nothing else differs.
	var painted := _painted(unmarked, marking, map.world_to_screen(field["world_position"]), 220.0)
	_check(
		painted > 8,
		"the symbols must paint where the lean put them, not slide over the imagery: %d pixels differ"
		% painted)
	_note("objects: lean painted=%d whole frame=%.4f" % [
		painted, _changed(unmarked, marking)])
	await _tap_a_clear_object(map, objects, out)
	# Left as the game ships it: the registry handed over, the layer enabled, the
	# camera back on the spawn the run started from.
	_check(map.semantic.is_enabled(&"objects"), "Objects must be left on")
	map.bearing = 0.0
	map.tilt = 0.0
	map.centre = spawn
	map.set_range(18000.0)
	await _hold(20)


## What the objects layer would draw for the camera as it stands.
func _symbols(map: CANVAS) -> Array:
	return map.strategy.batch(
		map._projector(), map._visible_ground(), map.semantic.alpha(&"objects"),
		map.semantic.level(), map.pixels_per_metre())


## The aerodrome with the longest strip, which is the one object on this map a
## published length can be checked against.
func _airfield(objects: WAR_OBJECTS) -> Dictionary:
	var best := {}
	for record in objects.of_type(WAR_OBJECTS.Type.AIRBASE):
		var field: Dictionary = record
		if best.is_empty() or float(field["detail"]["longest_m"]) > float(best["detail"]["longest_m"]):
			best = field
	return best


## The selection seam end to end, on the ground the map owns. The airfield's own tap
## is answered by a live track, which proves the priority but not the object path, so
## the end-to-end check runs on the worthiest object the exercise's tracks stay off
## of: a tap where it is drawn must reach the card with the registry's own record --
## the source that row was built from and the district the ground under it belongs to.
func _tap_a_clear_object(map: CANVAS, objects: WAR_OBJECTS, out: String) -> void:
	var target := {}
	for record in objects.objects():
		var object: Dictionary = record
		var at: Vector2 = object["world_position"]
		var clear := true
		for contact in map.contacts:
			var standing: Vector3 = contact["position"]
			if Vector2(standing.x, standing.z).distance_to(at) < 2500.0:
				clear = false
				break
		if clear and (target.is_empty()
				or float(object["strategic_value"]) > float(target["strategic_value"])):
			target = object
	_check(
		not target.is_empty(),
		"the theatre must hold an object the exercise's own tracks stay off of, got %d" % objects.count())
	if target.is_empty():
		return
	map.bearing = 0.0
	map.tilt = 0.0
	map.centre = target["world_position"]
	map.set_range(2200.0)
	await _hold(40)
	var at: Vector2 = map.world_to_screen(target["world_position"])
	var answers := {}
	map.strategic_selected.connect(func(id: int) -> void: answers["id"] = id)
	map.select_at(at)
	_check(
		int(answers.get("id", -1)) == int(target["id"]),
		"tapping %s where it is drawn selects it, got %s" % [
			String(target["name"]), str(answers.get("id", "nothing"))])
	var resolved := map.strategic_object(int(answers.get("id", -1)))
	_check(
		int(resolved.get("id", -1)) == int(target["id"]),
		"and the id the signal carries reads back as the world record, not a copy of it")
	_check(
		String(resolved.get("source", "")) == String(target["source"]),
		"with the source the registry says the row came from, got %s" % String(resolved.get("source", "nothing")))
	_check(
		String(resolved.get("region_id", "x")) == String(target["region_id"]),
		"in the district the ground under it belongs to, got %s" % String(resolved.get("region_id", "none")))
	_check(
		String(resolved.get("name", "")) == String(target["name"])
		and String(resolved.get("operational_state", "")) == String(target["operational_state"]),
		"and the card's subject is the record itself, name and state included")
	await _shot(out, "s_objects_selected")
	_note("objects: tapped %s (%s) source=%s district=%s state=%s" % [
		String(target["name"]), WAR_OBJECTS.type_name(target), String(target["source"]),
		String(target["region_id"]), String(target["operational_state"])])


## One drawn frame, saved and handed back.
func _shot(out: String, name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(_has_pixels(image), "%s must render the theatre, not an empty backdrop" % name)
	_check(image.save_png("%s-%s.png" % [out, name]) == OK, "%s must save" % name)
	return image


## How many sampled pixels two frames disagree about inside a window around a point.
## `_changed` answers "is this overlay on the map" across a whole theatre; a single
## glyph needs the other question: is it painted where its ground now is.
func _painted(one: Image, two: Image, at: Vector2, radius: float) -> int:
	if one == null or two == null:
		return 0
	var width := mini(one.get_width(), two.get_width())
	var height := mini(one.get_height(), two.get_height())
	var different := 0
	for y in range(
			maxi(0, int(at.y - radius)), mini(height, int(at.y + radius)), 2):
		for x in range(
				maxi(0, int(at.x - radius)), mini(width, int(at.x + radius)), 2):
			var mine := one.get_pixelv(Vector2i(x, y))
			var theirs := two.get_pixelv(Vector2i(x, y))
			if absf(mine.r - theirs.r) + absf(mine.g - theirs.g) + absf(mine.b - theirs.b) > 0.06:
				different += 1
	return different


## The fraction of sampled pixels two frames disagree about.
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


## How much of the picture is doing work. `detail` is the average distance each
## sampled pixel's luminance sits from the frame's mean, which is what an opaque
## overlay destroys: solid colour over solid colour has none of it left, while a
## wash you can see the relief through keeps most of it.
func _measure(image: Image) -> Dictionary:
	var mean := 0.0
	var spread := 0.0
	var count := 0
	for step in range(0, image.get_width() * image.get_height(), 997):
		mean += image.get_pixelv(
			Vector2(step % image.get_width(), step / image.get_width())).get_luminance()
		count += 1
	mean /= float(maxi(count, 1))
	for step in range(0, image.get_width() * image.get_height(), 997):
		spread += absf(image.get_pixelv(
			Vector2(step % image.get_width(), step / image.get_width())).get_luminance() - mean)
	return {"luminance": mean, "detail": spread / float(maxi(count, 1))}


## Every label the theatre knows about, projected and read back at the current
## camera. A match means the symbols and the terrain under them agree.
func _round_trips(map: CANVAS, layers: Dictionary, world_size: float) -> bool:
	var worst := 0.0
	var points := [map.centre]
	for place in layers.get("places", []):
		points.append(place.position)
	for point in points:
		var at: Vector2 = map.world_to_screen(point)
		if not at.is_finite():
			continue
		worst = maxf(worst, map.screen_to_world(at).distance_to(point))
	return worst < maxf(world_size, 1.0) * 0.001


func _contacts(layers: Dictionary, spawn: Vector2, world_size: float) -> Array:
	# Named after the exercise, not the town they stand in: a contact that shares
	# a label with the place under it reads as a duplicated place name.
	var result := []
	var index := 0
	for place in layers.get("places", []):
		if result.size() >= 3:
			break
		var at: Vector2 = place.position
		if at.distance_to(spawn) < world_size * 0.04:
			continue
		index += 1
		result.append(TRACKER.contact(
			10 + index, TRACKER.Kind.BUILDING, Vector3(at.x, 0.0, at.y), Vector3.ZERO, "SITE %02d" % index))
	var bandit := spawn + Vector2(2400.0, -3200.0)
	result.append(TRACKER.contact(1, TRACKER.Kind.AIR_JET, Vector3(bandit.x, 900.0, bandit.y), Vector3.ZERO, "BANDIT 01"))
	return result


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


## The catalog the game would show, read through the same loader it uses.
func _region(region_id: String) -> Dictionary:
	var service := root.get_node_or_null("LocationService")
	var regions: Array = service.installed_regions() if service != null else []
	if regions.is_empty():
		var file := FileAccess.open("res://data/regions/catalog.json", FileAccess.READ)
		if file == null:
			return {}
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		regions = parsed["regions"] if typeof(parsed) == TYPE_DICTIONARY else []
	for region in regions:
		if String(region.get("id", "")) == region_id:
			return region
	return {}
