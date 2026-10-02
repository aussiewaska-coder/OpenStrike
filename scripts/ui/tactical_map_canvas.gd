extends Control

## The battle map's drawing surface. It owns no camera maths and no gesture
## logic -- it holds a BattleMapView for the first and a BattleMapGestures for
## the second, feeds them the terrain layers the streaming system publishes, and
## draws contacts, places and routes through the same projection the terrain
## shader uses, so a symbol sits on the ground it names.

signal contact_selected(handle: int)
signal group_selected(handles: Array, title: String, centroid: Vector3)
## A tap landed on a thing the war is fought over rather than on a track. The id is
## the registry's own strategic id, and the card goes back to the registry with it,
## so a site whose launcher moves or dies is refreshed rather than frozen at the
## moment the finger came down.
signal strategic_selected(id: int)
signal waypoint_requested(position: Vector2)
signal range_changed(metres: float)
signal level_changed(level: int)
## The war layers arrived, moved or went away. The panel's layer rail disables
## what has nothing behind it, so it has to hear about this and not wait for the
## next zoom change to notice.
signal war_changed

const MAP_SHADER := preload("res://shaders/tactical_map.gdshader")
const VIEW := preload("res://scripts/battle_map/battle_map_view.gd")
const GESTURES := preload("res://scripts/battle_map/battle_map_gestures.gd")
const LEVELS := preload("res://scripts/battle_map/battle_map_layers.gd")
const MARKERS := preload("res://scripts/battle_map/battle_map_markers.gd")
const TERRITORY := preload("res://scripts/battle_map/battle_map_territory.gd")
const STRATEGY := preload("res://scripts/battle_map/battle_map_strategy.gd")
const RADAR := preload("res://scripts/ui/radar_scope.gd")
const GREEN := Color(0.40, 0.91, 0.73)
const CYAN := Color(0.38, 0.92, 1.0)
const AMBER := Color(1, 0.78, 0.32)
## Held controller motion, in pixels or radians per second. Deliberately slower
## than a finger: a thumb on a stick has no velocity to throw.
const PAD_PAN_PIXELS_PER_SECOND := 620.0
const PAD_SPIN_RATE := 1.5
const PAD_LEAN_RATE := 0.85
const PAD_ZOOM_RATE := 1.1
const SWEEP_SECONDS := 3.5
const SWEEP_TRAIL := 12
const PICK_PIXELS := 24.0
## A group marker is bigger than a track, so it is forgiven a wider tap.
const GROUP_PICK_PIXELS := 30.0
const GRID_SAMPLES := 8

var add_waypoint := false
var map_style := 1
var player := Vector3.ZERO
var heading := 0.0
var contacts: Array = []
var locked := -1
var route: RefCounted
var layers := {}
## What the map shows at this zoom, and how the tracks fold into groups. Both are
## RefCounted state, not nodes: the map may be open or closed a hundred times a
## sortie and neither the fades nor the marker pool should be rebuilt when it is.
var semantic := LEVELS.new()
var cluster := MARKERS.new()
## The war layers, when a theatre has anything to say about the ground. Like the
## clustering this is RefCounted state: the outlines are built once per region and
## only projected per frame.
var territory := TERRITORY.new()
## The things the war is fought over, when this theatre has any. Same shape as the
## territory: RefCounted state built once per region, projected per frame, and a
## layer that reports itself empty rather than drawing symbols with nothing behind
## them.
var strategy := STRATEGY.new()
var _view := VIEW.new()
var _gestures := GESTURES.new()
var _items: Array = []
var _project := Callable()
var _reported_level := -1
var _height_source: Image
var _height_texture: ImageTexture
var _material: ShaderMaterial
var _sweep := 0.0
var _reported_range := 0.0

var centre: Vector2:
	get:
		return _view.centre
	set(value):
		_view.centre = value

var range_m: float:
	get:
		return _view.range_m
	set(value):
		_view.set_range(value)

var follow_player: bool:
	get:
		return _view.follow_player
	set(value):
		_view.follow_player = value

var bearing: float:
	get:
		return _view.bearing
	set(value):
		_view.set_bearing(value)

var tilt: float:
	get:
		return _view.tilt
	set(value):
		_view.settle()
		_view.tilt = clampf(value, 0.0, VIEW.TILT_MAX)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(100, 100)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.show_behind_parent = true
	_material = ShaderMaterial.new()
	_material.shader = MAP_SHADER
	backdrop.material = _material
	add_child(backdrop)
	_gestures.setup(_view)
	_gestures.tapped.connect(select_at)
	_gestures.double_tapped.connect(_focus_at)
	resized.connect(_update_shader)
	_update_shader()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_sweep = fposmod(_sweep + delta * TAU / SWEEP_SECONDS, TAU)
	_poll_controller(delta)
	_glide_to_player(delta)
	_view.tick(delta)
	semantic.tick(delta, _view.range_m)
	_report_range()
	_report_level()
	_update_shader()
	queue_redraw()


## The camera as the clustering needs it, filled in place rather than rebuilt:
## this runs every frame the map is open.
func _project_ground(world: Vector2) -> Vector2:
	return _view.project(world)


## A reusable handle on the projection. The clustering module owns no camera, so
## it is handed this instead of a view it would only have to interpret.
func _projector() -> Callable:
	if not _project.is_valid():
		_project = Callable(self, "_project_ground")
	return _project


func pixels_per_metre() -> float:
	_sync_viewport()
	return _view.pixels_per_metre()


func world_to_screen(world: Vector2) -> Vector2:
	_sync_viewport()
	return _view.project(world)


func screen_to_world(point: Vector2) -> Vector2:
	_sync_viewport()
	return _view.unproject(point)


func set_range(metres: float, anchor := Vector2(-1, -1)) -> void:
	_sync_viewport()
	_view.set_range(metres, anchor)
	# `set_range` is the immediate entry point, so the information density moves
	# with it rather than easing in behind a frame the caller never gave us.
	semantic.tick(1.0, _view.range_m)
	_report_range()
	_report_level()
	_update_shader()
	queue_redraw()


## The range keys fly the camera to a distance instead of cutting to it, which
## keeps the terrain readable across the change.
func animate_range(metres: float) -> void:
	_sync_viewport()
	_view.begin_glide({"range": metres})
	queue_redraw()


func recenter() -> void:
	_sync_viewport()
	_view.settle()
	_view.follow_player = true
	_view.centre = Vector2(player.x, player.z)
	_update_shader()
	queue_redraw()


## Levels the map back to north-up and overhead, and puts the ownship back under
## the middle of it. The camera glides; it never teleports.
func reset_view() -> void:
	_sync_viewport()
	_view.follow_player = true
	_view.begin_glide({"centre": Vector2(player.x, player.z), "bearing": 0.0, "tilt": 0.0})
	queue_redraw()


func focus_world(world: Vector2, metres := -1.0) -> void:
	_sync_viewport()
	_view.focus_world(world, metres)
	queue_redraw()


func focus_contact(handle: int) -> void:
	for contact in contacts:
		if int(contact.handle) == handle:
			var world: Vector3 = contact.position
			_focus_ground(Vector2(world.x, world.z))
			return


## The same flight a contact gets, for a thing that stands still: an airfield or a
## site is worth flying the camera onto, and it is not worth arriving on top of.
func focus_object(world: Vector2) -> void:
	_sync_viewport()
	_focus_ground(world)


## What the map is drawing for the contacts layer right now: the formations and
## lone tracks this zoom shows. The panel needs it for the selection card, and it
## is the same call the draw makes -- cached, so asking twice in a frame costs a
## hash rather than a recluster.
func markers() -> Array:
	return cluster.markers(contacts, semantic.level())


## What the map is actually showing under this point: a single track at tactical
## range, a formation above that, or nothing. The clustering already knows the
## level, so a group that is not drawn here cannot be tapped here either.
func marker_at(point: Vector2) -> Dictionary:
	if not semantic.visible(&"contacts"):
		return {}
	_sync_viewport()
	markers()
	var group := cluster.group_at(point, _projector(), GROUP_PICK_PIXELS)
	if not group.is_empty():
		return {"group": group, "handles": cluster.handles_of(group), "title": String(group["label"])}
	var handle := contact_at(point)
	if handle >= 0:
		return {"handle": handle}
	return {}


func set_state(position: Vector3, yaw: float, items: Array, lock_handle: int, navigation: RefCounted) -> void:
	player = position
	heading = yaw
	contacts = items
	locked = lock_handle
	route = navigation
	if _view.follow_player:
		_view.centre = Vector2(position.x, position.z)
	_update_shader()
	queue_redraw()


func set_layers(data: Dictionary) -> void:
	layers = data
	var source: Image = data.get("height")
	if source != _height_source:
		_height_source = source
		_height_texture = ImageTexture.create_from_image(source) if source != null and not source.is_empty() else null
	_update_shader()
	queue_redraw()


## The war: which districts the theatre is divided into and who holds them. Either
## side of it may be null when a theatre has no regions authored, and the territory
## layer then reports itself empty to the toggle panel instead of drawing nothing.
func set_war(regions: RefCounted, control: RefCounted) -> void:
	territory.load(regions, control)
	semantic.set_source(&"territory", territory.is_ready())
	war_changed.emit()
	queue_redraw()


## The strategic objects of the theatre being flown, or null for one that has none.
## Objects come from `war_objects.gd`, which builds them out of the world's own
## sources, and the live bindings run in there rather than here: the map is told, and
## asks through `strategic_object` when a card needs the current state.
func set_objects(objects: RefCounted) -> void:
	strategy.load(objects)
	semantic.set_source(&"objects", strategy.is_ready())
	war_changed.emit()
	queue_redraw()


## The live record for a selected object, or an empty Dictionary once it is gone.
func strategic_object(id: int) -> Dictionary:
	return strategy.of(id)


## What the map would select under this point if it were tapped: a symbol the objects
## layer is actually drawing here. Contacts answer first, so a launcher standing at a
## site is the thing you get when you tap it -- the site is the bigger picture, and
## the pilot asked for the shootable one.
func strategic_at(point: Vector2) -> Dictionary:
	if not semantic.visible(&"objects"):
		return {}
	_sync_viewport()
	return strategy.pick(point, _projector())


func _focus_at(point: Vector2) -> void:
	var marker := marker_at(point)
	if marker.has("group"):
		var centroid: Vector3 = marker["group"]["centroid"]
		# A formation is worth flying onto, and it is only worth flying onto if
		# the flight ends where its individual tracks become individual tracks.
		focus_group(centroid)
		return
	if marker.has("handle"):
		focus_contact(int(marker["handle"]))
		return
	var object := strategic_at(point)
	if not object.is_empty():
		# Flying the camera onto an airfield or a site is the planning gesture the
		# brief asks for, and it stops short of the tactical band: the object is a
		# place, and the ground around it is the reason the pilot went in.
		_focus_ground(object["world_position"])
		return
	_sync_viewport()
	_focus_ground(screen_to_world(point))


## Fly the camera onto a formation, close enough that its members are drawn and
## tapped as the separate tracks they are. The same contract a double tap has.
func focus_group(centroid: Vector3) -> void:
	_sync_viewport()
	_focus_ground(Vector2(centroid.x, centroid.z), true)


## Focal point of a focus move: close in on the object, but never so far that
## the surrounding terrain -- the thing being planned against -- leaves the map.
## `tight` pulls the arrival inside the tactical band, which is what a formation
## needs in order to open up into the tracks it stands for.
func _focus_ground(world: Vector2, tight := false) -> void:
	var metres := clampf(_view.range_m * 0.34, VIEW.MIN_RANGE, _view.range_m)
	if tight:
		metres = clampf(minf(metres, LEVELS.TACTICAL_ENTER * 0.8), VIEW.MIN_RANGE, _view.range_m)
	_view.focus_world(world, metres)


func _glide_to_player(delta: float) -> void:
	if not _view.follow_player or _view.is_gliding():
		return
	_view.centre = Vector2(player.x, player.z)


func _report_range() -> void:
	if is_equal_approx(_reported_range, _view.range_m):
		return
	_reported_range = _view.range_m
	range_changed.emit(_view.range_m)


## The panel wants to know when the map has changed what it shows, not every time
## the number under it wobbles, so the level is reported the way the range is.
func _report_level() -> void:
	var level := semantic.level()
	if level == _reported_level:
		return
	_reported_level = level
	level_changed.emit(level)


func _sync_viewport() -> void:
	_view.set_viewport_size(size)


func _poll_controller(delta: float) -> void:
	var pad := get_node_or_null("/root/GamepadInput")
	if pad == null:
		return
	if _gestures.engaged:
		# A finger on the map outranks a stick that is still deflected.
		return
	var pan: Vector2 = pad.get_map_pan_vector()
	var look: Vector2 = pad.get_map_look_vector()
	var zoom: float = pad.get_map_zoom_axis()
	_sync_viewport()
	if pan != Vector2.ZERO:
		_view.follow_player = false
		_view.pan_pixels(pan * PAD_PAN_PIXELS_PER_SECOND * delta)
	if look.x != 0.0:
		# The stick turns the camera, so the ground swings the other way; a drag
		# grabs the ground and moves it with the finger. Both read as natural.
		_view.rotate_by(look.x * PAD_SPIN_RATE * delta)
	if look.y != 0.0:
		_view.tilt_by(-look.y * PAD_LEAN_RATE * delta)
	if zoom != 0.0:
		_view.follow_player = false
		_view.set_range(_view.range_m * exp(zoom * PAD_ZOOM_RATE * delta))


func _update_shader() -> void:
	if _material == null:
		return
	_sync_viewport()
	var world_size := maxf(float(layers.get("world_size_m", 50000)), 1.0)
	_material.set_shader_parameter("centre_world", _view.centre)
	_material.set_shader_parameter("world_size", world_size)
	_material.set_shader_parameter("focal", _view.focal_pixels())
	_material.set_shader_parameter("view_distance", _view.view_distance())
	_material.set_shader_parameter("tilt_sine", sin(_view.tilt))
	_material.set_shader_parameter("tilt_cosine", cos(_view.tilt))
	_material.set_shader_parameter("bearing_cosine", cos(_view.bearing))
	_material.set_shader_parameter("bearing_sine", sin(_view.bearing))
	_material.set_shader_parameter("viewport_size", _view.viewport_size)
	_material.set_shader_parameter("map_style", map_style)
	_material.set_shader_parameter("has_aerial", layers.get("aerial") != null)
	_material.set_shader_parameter("aerial", layers.get("aerial"))
	_material.set_shader_parameter("has_elevation", _height_texture != null)
	_material.set_shader_parameter("elevation", _height_texture)
	var metadata: Dictionary = layers.get("metadata", {})
	_material.set_shader_parameter("elevation_min", float(metadata.get("elevation_min_m", 0.0)))
	_material.set_shader_parameter("elevation_max", float(metadata.get("elevation_max_m", 1000.0)))
	if _height_source != null:
		_material.set_shader_parameter("elevation_texel", Vector2.ONE / Vector2(_height_source.get_size()))


func contact_at(point: Vector2) -> int:
	_sync_viewport()
	var nearest := -1
	var distance := PICK_PIXELS
	for contact in contacts:
		var world: Vector3 = contact.position
		var at := _view.project(Vector2(world.x, world.z))
		if not at.is_finite() or not Rect2(Vector2.ZERO, size).has_point(at):
			continue
		var separation := at.distance_to(point)
		if separation < distance:
			distance = separation
			nearest = int(contact.handle)
	return nearest


func select_at(point: Vector2) -> void:
	if add_waypoint:
		waypoint_requested.emit(screen_to_world(point))
		return
	var marker := marker_at(point)
	if marker.has("handle"):
		contact_selected.emit(int(marker["handle"]))
		return
	if marker.has("group"):
		# A formation is not a target and must not silently lock one. The card is
		# what a tap buys; ASSIGN TARGET on the card is what reaches the weapon.
		var centroid: Vector3 = marker["group"]["centroid"]
		group_selected.emit(marker["handles"], String(marker["title"]), centroid)
		return
	var object := strategic_at(point)
	if not object.is_empty():
		strategic_selected.emit(int(object["id"]))


func _gui_input(event: InputEvent) -> void:
	var before_centre := _view.centre
	var before_range := _view.range_m
	_sync_viewport()
	var claimed := _gestures.feed(event, Time.get_ticks_msec())
	if not claimed:
		return
	# Any move that carries the view away from the aircraft ends the follow.
	# A tap moves nothing, so it leaves the map still tracking ownship.
	if _view.centre != before_centre or _view.range_m != before_range:
		_view.follow_player = false
	accept_event()


func cancel_gesture() -> void:
	_gestures.cancel()


func _text(at: Vector2, text: String, colour := GREEN, font_size := 13) -> void:
	draw_string_outline(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color(0.01, 0.035, 0.04, 0.9))
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)


func _ground_point(world: Vector2) -> Vector2:
	return _view.project(world)


## Screen angle of a ground point away from ownship. Measured in map space, so
## the radar sweep glow stays pinned to the map as it turns.
func _map_bearing_to(world: Vector2) -> float:
	var offset := _view.world_to_map(world - Vector2(player.x, player.z))
	return atan2(offset.x, -offset.y)


## Ground-space line, sampled so the part that runs past the horizon simply
## stops rather than sweeping a stray chord across the map.
func _draw_ground_line(from: Vector2, to: Vector2, colour: Color, width: float) -> void:
	var previous := _ground_point(from)
	for step in range(1, GRID_SAMPLES + 1):
		var fraction := float(step) / float(GRID_SAMPLES)
		var next := _ground_point(from.lerp(to, fraction))
		if previous.is_finite() and next.is_finite() and previous.distance_to(next) < maxf(size.x, size.y) * 2.0:
			draw_line(previous, next, colour, width, true)
		previous = next


func _draw_ground_circle(at: Vector2, radius: float, colour: Color, width: float) -> void:
	var previous := _ground_point(at + Vector2(radius, 0.0))
	for step in range(1, 49):
		var angle := float(step) / 48.0 * TAU
		var next := _ground_point(at + Vector2(sin(angle), -cos(angle)) * radius)
		if previous.is_finite() and next.is_finite() and previous.distance_to(next) < maxf(size.x, size.y) * 2.0:
			draw_line(previous, next, colour, width, true)
		previous = next


func _visible_ground() -> Rect2:
	var lowest := Vector2(INF, INF)
	var highest := Vector2(-INF, -INF)
	# A corner that looks past the horizon has no ground answer, but the grid it
	# would have bounded does keep going. Four ranges out, grid lines are down to
	# a pixel, so that is as far as the box is widened instead of the whole
	# theatre -- which at 50 km and a 100 m grid would be five hundred lines a
	# frame, drawn to be invisible.
	var reach := maxf(_view.range_m, 1.0) * 4.0
	for corner in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y), size * 0.5]:
		var world := _view.unproject(corner)
		if not world.is_finite():
			world = Vector2(signf(corner.x - size.x * 0.5) * reach, -reach)
		lowest = Vector2(minf(lowest.x, world.x), minf(lowest.y, world.y))
		highest = Vector2(maxf(highest.x, world.x), maxf(highest.y, world.y))
	if not lowest.is_finite() or not highest.is_finite():
		return Rect2()
	# A Rect2 is a position and a size, not two corners: the theatre's own box runs
	# from -half to +half, which is an extent of a whole world size. Written the
	# other way this clipped every view to the north-west quarter of the theatre,
	# so anything east or south of the centre was culled before it could be drawn.
	var half := maxf(float(layers.get("world_size_m", 50000)), 1.0) * 0.5
	return Rect2(lowest, highest - lowest).intersection(
		Rect2(-Vector2.ONE * half, Vector2.ONE * half * 2.0))


func _draw() -> void:
	if _material == null:
		return
	_sync_viewport()
	# First, under everything else: the control areas are the ground's own
	# furniture, and the grid, the symbols and the labels all have to read on top
	# of them rather than through them.
	var held := semantic.alpha(&"territory")
	if held > 0.0:
		_draw_territory(held)
	## Objects go over the control areas and under the tracks: what is standing on
	## the ground belongs to the ground, and the live things flying over it are the
	## ones that have to stay readable.
	var objects := semantic.alpha(&"objects")
	if objects > 0.0:
		_draw_objects(objects)
	var origin := _ground_point(Vector2(player.x, player.z))
	var step := pow(10.0, floor(log(_view.range_m) / log(10.0)))
	var grid := semantic.alpha(&"grid")
	if grid > 0.0:
		if _view.bearing == 0.0 and _view.tilt == 0.0:
			_draw_flat_grid(step, grid)
		else:
			_draw_ground_grid(step, _visible_ground(), grid)
	var detection := semantic.alpha(&"sweep")
	if origin.is_finite() and detection > 0.0:
		for fraction in [0.5, 1.0]:
			_draw_ground_circle(
				Vector2(player.x, player.z), _view.range_m * fraction, Color(GREEN, 0.24 * detection), 1)
		_draw_sweep(detection)
	_draw_details()
	var places := semantic.alpha(&"places")
	if places > 0.0:
		_draw_places(places)
	var route_alpha := semantic.alpha(&"route")
	if route_alpha > 0.0:
		_draw_route(route_alpha)
	var tracks := semantic.alpha(&"contacts")
	if tracks > 0.0:
		_draw_contacts(tracks)
	if origin.is_finite():
		var nose := Vector2(sin(heading - _view.bearing), -cos(heading - _view.bearing))
		var side := Vector2(-nose.y, nose.x)
		draw_colored_polygon(PackedVector2Array([origin + nose * 12, origin - nose * 8 + side * 7, origin - nose * 4, origin - nose * 8 - side * 7]), CYAN)
		_text(origin + Vector2(13, 20), "OWN", CYAN, 12)
	_draw_border(step)


## The control areas, their boundaries, the hatch on contested ground and the
## line between the two sides -- all of it screen geometry the territory module
## has already culled to the visible ground and projected through this map's own
## camera, so nothing here decides where a border runs.
func _draw_territory(alpha: float) -> void:
	var batch: Dictionary = territory.batch(_projector(), _visible_ground(), alpha, _view.pixels_per_metre())
	for fill in batch["fills"]:
		draw_colored_polygon(fill["path"], fill["colour"])
	for edge in batch["edges"]:
		draw_polyline(edge["path"], edge["colour"], float(edge["width"]), true)
	for mark in batch["front"]:
		draw_line(mark["a"], mark["b"], mark["colour"], float(mark["width"]), true)
		if mark.has("arrow"):
			draw_colored_polygon(mark["arrow"], mark["colour_arrow"])


## The objects the registry says this theatre has, as symbols on the ground they are
## at. Every path here is screen geometry the strategy module built from the map's own
## projection, so nothing below decides where an airfield is or how long its runway
## is -- it only strokes what it was told.
func _draw_objects(alpha: float) -> void:
	var level := semantic.level()
	for item in strategy.batch(_projector(), _visible_ground(), alpha, level, _view.pixels_per_metre()):
		for strip in item["strips"]:
			draw_line(strip[0], strip[1], item["strip_colour"], float(item["strip_width"]), true)
		var at: Vector2 = item["at"]
		var reach := float(item["reach"])
		var colour: Color = item["colour"]
		draw_circle(at, reach + 2.0, item["backing"])
		for path in item["paths"]:
			draw_polyline(path, colour, float(item["width"]), true)
		var label := String(item["label"])
		if label.is_empty():
			continue
		var width := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(at + Vector2(reach + 4, -9), Vector2(width + 6, 18)), Color(0.015, 0.025, 0.03, 0.78 * alpha))
		_text(at + Vector2(reach + 6, 4), label, colour.lerp(Color.WHITE, 0.55), 12)
		if String(item["sub"]).is_empty():
			continue
		_text(at + Vector2(reach + 6, 18), String(item["sub"]), Color(colour, 0.8), 11)


func _draw_flat_grid(step: float, alpha: float) -> void:
	var line := Color(GREEN, 0.10 * alpha)
	var corner := screen_to_world(Vector2.ZERO)
	var end := screen_to_world(size)
	for x in range(int(floor(corner.x / step)), int(ceil(end.x / step)) + 1):
		var at := world_to_screen(Vector2(x * step, 0)).x
		draw_line(Vector2(at, 0), Vector2(at, size.y), line, 1)
	for z in range(int(floor(corner.y / step)), int(ceil(end.y / step)) + 1):
		var at := world_to_screen(Vector2(0, z * step)).y
		draw_line(Vector2(0, at), Vector2(size.x, at), line, 1)


func _draw_ground_grid(step: float, view: Rect2, alpha: float) -> void:
	if not view.has_area():
		return
	var line := Color(GREEN, 0.10 * alpha)
	for x in range(int(floor(view.position.x / step)), int(ceil(view.end.x / step)) + 1):
		_draw_ground_line(Vector2(x * step, view.position.y), Vector2(x * step, view.end.y), line, 1)
	for y in range(int(floor(view.position.y / step)), int(ceil(view.end.y / step)) + 1):
		_draw_ground_line(Vector2(view.position.x, y * step), Vector2(view.end.x, y * step), line, 1)


func _draw_sweep(alpha: float) -> void:
	for index in range(SWEEP_TRAIL):
		var angle := _sweep - float(index) * 0.025
		var reach := Vector2(sin(angle), -cos(angle)) * _view.range_m * 2.0
		_draw_ground_line(
			Vector2(player.x, player.z),
			Vector2(player.x, player.z) + reach,
			Color(GREEN, 0.23 * (1.0 - float(index) / float(SWEEP_TRAIL)) * alpha),
			2)


func _draw_details() -> void:
	if map_style != 0:
		return
	for tile in layers.get("details", []):
		var bounds: Rect2 = tile.bounds
		var corners := PackedVector2Array([
			_ground_point(bounds.position),
			_ground_point(Vector2(bounds.end.x, bounds.position.y)),
			_ground_point(bounds.end),
			_ground_point(Vector2(bounds.position.x, bounds.end.y)),
		])
		var usable := true
		for corner in corners:
			if not corner.is_finite():
				usable = false
		if not usable:
			continue
		var uvs := PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)])
		var tint := Color(0.72, 0.88, 0.81)
		var colours := PackedColorArray([tint, tint, tint, tint])
		draw_polygon(corners, colours, uvs, tile.texture)


func _draw_route(alpha: float) -> void:
	if route == null:
		return
	var previous := _ground_point(Vector2(player.x, player.z))
	for index in range(route.points.size()):
		var point: Vector3 = route.points[index]
		var at := _ground_point(Vector2(point.x, point.z))
		if previous.is_finite() and at.is_finite():
			draw_dashed_line(previous, at, Color(CYAN, 0.75 * alpha), 1.5, 7)
		previous = at
		if not at.is_finite():
			continue
		draw_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)), Color(CYAN, alpha), false, 2)
		_text(at + Vector2(10, -10), "WP %02d" % [route.completed + index + 1], Color(CYAN, alpha))


## What the map shows of the same contacts at this zoom. Below the tactical band
## every track is a track; above it the tracks fold into the formations a pilot
## actually plans against, and the number of things drawn falls while the amount
## of information per thing rises. The labels say what they are: four contacts in
## one marker read as a group of four, not as one icon that got smaller.
func _draw_contacts(alpha: float) -> void:
	_items = markers()
	var area := Rect2(Vector2.ZERO, size).grow(28)
	for item in _items:
		if bool(item["individual"]):
			_draw_track(item["contact"], area, alpha)
		else:
			_draw_group(item["group"], area, alpha)


func _draw_track(contact: Dictionary, area: Rect2, alpha: float) -> void:
	var world: Vector3 = contact["position"]
	var at := _ground_point(Vector2(world.x, world.z))
	if not at.is_finite() or not area.has_point(at):
		return
	var glow := 1.0 - clampf(fposmod(_sweep - _map_bearing_to(Vector2(world.x, world.z)), TAU) / 1.2, 0, 1)
	var colour := RADAR.colour_for_kind(int(contact["kind"]))
	colour.a = (0.82 + glow * 0.18) * alpha
	draw_circle(at, 7, Color(0.015, 0.025, 0.03, 0.85 * alpha))
	draw_circle(at, 4.5, colour)
	if glow > 0:
		draw_arc(at, 7 + (1.0 - glow) * 7, 0, TAU, 24, Color(colour, glow * 0.5 * alpha), 1, true)
	if int(contact["handle"]) == locked:
		draw_rect(Rect2(at - Vector2(11, 11), Vector2(22, 22)), Color(AMBER, alpha), false, 2)
	var label := String(contact.get("name", "CONTACT"))
	var width := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_rect(Rect2(at + Vector2(8, -10), Vector2(width + 5, 19)), Color(0.015, 0.025, 0.03, 0.78 * alpha))
	_text(at + Vector2(10, 5), label, colour.lerp(Color.WHITE, 0.60), 12)


## A formation: the count it stands for, what sort of thing it is, which way it is
## going, and the tracker's own handles inside it if the pilot wants one. The
## diamond is what says "more than one thing" before the number is readable.
func _draw_group(group: Dictionary, area: Rect2, alpha: float) -> void:
	var centroid: Vector3 = group["centroid"]
	var at := _ground_point(Vector2(centroid.x, centroid.z))
	if not at.is_finite() or not area.has_point(at):
		return
	var count := int(group["count"])
	var colour: Color = RADAR.colour_for_kind(int(group["kind"]))
	colour.a = alpha
	var reach := 9.0 + minf(float(count), 12.0) * 0.7
	var diamond := PackedVector2Array([
		at + Vector2(0, -reach),
		at + Vector2(reach, 0),
		at + Vector2(0, reach),
		at + Vector2(-reach, 0),
		at + Vector2(0, -reach),
	])
	draw_colored_polygon(diamond.slice(0, 4), Color(colour, 0.30 * alpha))
	draw_polyline(diamond, Color(colour, 0.95 * alpha), 1.5, true)
	var course: float = group["heading"]
	if not is_nan(course):
		var nose := Vector2(sin(course - _view.bearing), -cos(course - _view.bearing))
		draw_line(at, at + nose * (reach + 10), Color(colour, 0.9 * alpha), 2, true)
	if _group_holds_lock(group):
		draw_rect(Rect2(at - Vector2(reach + 5, reach + 5), Vector2(reach * 2 + 10, reach * 2 + 10)),
			Color(AMBER, alpha), false, 2)
	var title := "%s · %d" % [String(group["label"]), count]
	var width := ThemeDB.fallback_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_rect(Rect2(at + Vector2(reach + 4, -18), Vector2(width + 6, 20)), Color(0.015, 0.025, 0.03, 0.78 * alpha))
	_text(at + Vector2(reach + 6, -4), title, colour.lerp(Color.WHITE, 0.55), 12)
	if bool(group["air"]):
		var detail := "FL%03d" % int(round(float(group["altitude_m"]) / 30.48))
		if not is_nan(course):
			detail += "  %03d°" % int(round(rad_to_deg(course)))
		_text(at + Vector2(reach + 6, 10), detail, Color(colour, 0.8 * alpha), 11)


## Whether the locked handle is one of the tracks inside this group, so a lock
## survives the zoom that folded it in rather than silently detaching.
func _group_holds_lock(group: Dictionary) -> bool:
	if locked < 0:
		return false
	for contact in group["members"]:
		if int(contact["handle"]) == locked:
			return true
	return false


func _draw_border(step: float) -> void:
	var degrees := rad_to_deg(_view.bearing)
	var north := "N ↑" if absf(_shortest(_view.bearing)) < 0.02 else "N %03d°" % int(round(degrees))
	_text(Vector2(12, 23), "%s  /  TILT %02d°" % [north, int(round(rad_to_deg(_view.tilt)))], GREEN)
	_text(
		Vector2(12, size.y - 14),
		"%s  ·  RANGE %.1f km  ·  GRID %.0f m" % [
			LEVELS.level_name(semantic.level()), _view.range_m / 1000, step],
		GREEN, 12)
	if map_style == 0 and layers.get("aerial") == null:
		_text(Vector2(12, 44), "AERIAL NOT LOADED · TACTICAL GRID", AMBER, 12)
	elif map_style != 0 and _height_texture == null:
		_text(Vector2(12, 44), "ELEVATION NOT LOADED · TACTICAL GRID", AMBER, 12)
	for y in range(0, int(size.y), 4):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0.02, 0.02, 0.065), 1)
	draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), Color(GREEN, 0.35), false, 2)


static func _shortest(angle: float) -> float:
	return fposmod(angle + PI, TAU) - PI


## Keep geographic labels readable during pan/zoom/tilt. They never participate
## in contact picking: aircraft, threats and route input retain their own meaning.
func place_labels() -> Array:
	_sync_viewport()
	var result := []
	var occupied: Array[Rect2] = []
	var own := _ground_point(Vector2(player.x, player.z))
	if own.is_finite():
		occupied.append(Rect2(own - Vector2(16, 16), Vector2(68, 46)))
	var font_size := 12 if size.x < 500 else 13
	var font := ThemeDB.fallback_font
	var area := Rect2(Vector2(8, 50), Vector2(maxf(size.x - 16, 1), maxf(size.y - 86, 1)))
	for place in layers.get("places", []):
		var at := _ground_point(place.position)
		if not at.is_finite() or not Rect2(Vector2.ZERO, size).has_point(at):
			continue
		var lines: Array = [String(place.name)]
		if place.has("subtitle"):
			lines.append(String(place.subtitle))
		var width := 0.0
		for line in lines:
			width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		var extent := Vector2(width + 10, lines.size() * (font_size + 4) + 6)
		var chosen := Rect2()
		for level in range(7):
			for direction in [1.0, -1.0]:
				var offset := Vector2(12 if direction > 0 else -extent.x - 12, -extent.y - 8 - level * (extent.y + 3))
				if level % 2 == 1:
					offset.y = 10 + (level / 2) * (extent.y + 3)
				var label_origin := at + offset
				label_origin.x = clampf(label_origin.x, area.position.x, maxf(area.position.x, area.end.x - extent.x))
				label_origin.y = clampf(label_origin.y, area.position.y, maxf(area.position.y, area.end.y - extent.y))
				var rect := Rect2(label_origin, extent)
				var overlaps := false
				for taken in occupied:
					if rect.grow(3).intersects(taken):
						overlaps = true
						break
				if not overlaps:
					chosen = rect
					break
			if chosen.has_area():
				break
		if not chosen.has_area():
			# Crowded overview: search free label rows, retaining a leader to
			# the true position instead of dropping a town behind another name.
			var best := INF
			for y in range(int(area.position.y), int(area.end.y - extent.y) + 1, font_size + 6):
				for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
					var rect := Rect2(Vector2(lerpf(area.position.x, maxf(area.position.x, area.end.x - extent.x), fraction), y), extent)
					var overlaps := false
					for taken in occupied:
						if rect.grow(3).intersects(taken):
							overlaps = true
							break
					var separation := rect.get_center().distance_squared_to(at)
					if not overlaps and separation < best:
						best = separation
						chosen = rect
		if chosen.has_area():
			occupied.append(chosen)
			result.append({"at": at, "rect": chosen, "lines": lines, "font_size": font_size, "airport": place.get("airport", false)})
	return result


func _draw_places(alpha: float) -> void:
	for label in place_labels():
		var at: Vector2 = label.at
		var rect: Rect2 = label.rect
		var colour := AMBER if label.airport else Color(0.72, 0.86, 0.80)
		colour.a = alpha
		var edge := Vector2(clampf(at.x, rect.position.x, rect.end.x), clampf(at.y, rect.position.y, rect.end.y))
		draw_line(at, edge, Color(colour, 0.45 * alpha), 1, true)
		if label.airport:
			draw_circle(at, 9, Color(0.01, 0.03, 0.03, 0.9 * alpha))
			draw_arc(at, 8, 0, TAU, 24, colour, 1.5, true)
			draw_line(at + Vector2(-3, -5), at + Vector2(3, 5), colour, 3, true)
		else:
			draw_circle(at, 3, colour)
		draw_rect(rect, Color(0.01, 0.035, 0.04, 0.82 * alpha))
		for i in range(label.lines.size()):
			_text(rect.position + Vector2(5, 4 + label.font_size + i * (label.font_size + 4)), label.lines[i], colour, label.font_size)
