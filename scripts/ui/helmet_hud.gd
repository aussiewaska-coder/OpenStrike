extends Control

## The visor.
##
## Two families of symbol, and the contrast between them is the whole effect.
## CONFORMAL symbols -- horizon, pitch ladder, flight path marker, target boxes
## -- are world points run through `unproject_position`, so they stay welded to
## the world while the view swings. SCREEN-FIXED symbols -- the speed, altitude
## and heading tapes -- do not move at all. Swing the view and half the glass
## slides while half stays put, which is what a helmet does and a panel cannot.
##
## Drawn, not themed, like the rest of this HUD: no textures, every element a
## line, an arc or a polygon.

const HUD := preload("res://scripts/ui/hud_projection.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

const GREEN := Color(0.45, 1.0, 0.6)
const AMBER := Color(1.0, 0.72, 0.25)
const HOSTILE_RED := Color(1.0, 0.22, 0.18)
const LINE_WIDTH := 1.4
const LOCK_LINE_WIDTH := 2.4
const LABEL_SIZE := 12

const BOX_MAX_PX := 44.0
const BOX_MIN_PX := 7.0
## The range at which a box has shrunk to its floor.
const BOX_FALLOFF_M := 6000.0

const TAPE_MARGIN_PX := 26.0
const TAPE_HEIGHT_PX := 190.0
const FPM_RADIUS_PX := 8.0
const EDGE_MARGIN_PX := 34.0
const LADDER_LABEL_SIZE := 15
const LADDER_INNER_DEGREES := 2.0
const LADDER_OUTER_DEGREES := 11.0

var _camera: Camera3D
var _cockpit_view := true
var _velocity := Vector3.ZERO
var _boxed: Array = []
var _locked := {}
var _closure := 0.0
var _instruments := {}
var _seeker := {}


func set_seeker_state(state: Dictionary) -> void:
	_seeker = state
	queue_redraw()


func _lock_colour() -> Color:
	if TRACKER.is_airborne(_locked):
		return HOSTILE_RED
	return AMBER


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func box_half_extent_px(range_m: float) -> float:
	var t := clampf(range_m / BOX_FALLOFF_M, 0.0, 1.0)
	return lerpf(BOX_MAX_PX, BOX_MIN_PX, t)


static func closure_text(mps: float) -> String:
	return "%+d" % roundi(mps)


static func kind_label(kind: int) -> String:
	match kind:
		TRACKER.Kind.AIR_JET:
			return "JET"
		TRACKER.Kind.AIR_DRONE:
			return "DRONE"
		TRACKER.Kind.GROUND_LAUNCHER:
			return "SAM"
		TRACKER.Kind.BUILDING:
			return "BLDG"
		TRACKER.Kind.GROUND_POINT:
			return "GND"
	return "UNKNOWN"


func set_state(
	camera: Camera3D,
	velocity: Vector3,
	boxed: Array,
	locked: Dictionary,
	closure_mps: float,
	instruments: Dictionary
) -> void:
	_camera = camera
	_velocity = velocity
	_boxed = boxed
	_locked = locked
	_closure = closure_mps
	_instruments = instruments
	queue_redraw()


func _draw() -> void:
	if _camera == null:
		return
	if _cockpit_view:
		_draw_visor()
		_draw_horizon()
		_draw_ladder()
		_draw_flight_path_marker()
		_draw_boresight()
		_draw_tapes()
	_draw_boxes()
	_draw_lock()


func set_cockpit_view(enabled: bool) -> void:
	_cockpit_view = enabled
	queue_redraw()


## A world point becomes a screen point, or null when it is behind the camera.
func _screen(world: Vector3):
	if _camera.is_position_behind(world):
		return null
	return _camera.unproject_position(world)


func _draw_horizon() -> void:
	_draw_attitude_arc(0.0, -65.0, -LADDER_INNER_DEGREES, Color(GREEN, 0.68), 32)
	_draw_attitude_arc(0.0, LADDER_INNER_DEGREES, 65.0, Color(GREEN, 0.68), 32)


## Solid climb bars and dashed dive bars, with major ticks hooked toward the
## horizon. Constant-elevation arcs preserve the attitude under head movement.
func _draw_ladder() -> void:
	for degrees in HUD.ladder_degrees():
		if is_zero_approx(degrees):
			continue
		var centre = _screen(HUD.far_point(_camera.global_position, HUD.ladder_direction(_camera.global_basis, degrees)))
		if centre == null or HUD.visor_alpha(centre, size) < 0.02:
			continue
		var major := int(absf(degrees)) % 10 == 0
		var outer := LADDER_OUTER_DEGREES if major else 7.0
		var colour := Color(GREEN, 0.78 if major else 0.38)
		for side in [-1.0, 1.0]:
			var start: float = LADDER_INNER_DEGREES * side
			var end: float = outer * side
			if degrees > 0.0:
				_draw_attitude_arc(degrees, start, end, colour)
			else:
				for step in range(3):
					var t0 := float(step) / 3.0
					var t1 := t0 + 0.22
					_draw_attitude_arc(degrees, lerpf(start, end, t0), lerpf(start, end, t1), colour, 3)
			if not major:
				continue
			var tip = _arc_screen(degrees, end)
			var hook = _arc_screen(degrees - signf(degrees) * 1.0, end)
			if tip != null and hook != null:
				_draw_attitude_line(tip, hook, colour)
			var label_at = _arc_screen(degrees, end + side * 2.1)
			if label_at != null:
				var alpha := HUD.visor_alpha(label_at, size)
				var label := "%+d" % int(degrees)
				var width := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LADDER_LABEL_SIZE).x
				var text_position: Vector2 = label_at + Vector2(-width * 0.5, 5.0)
				draw_string_outline(ThemeDB.fallback_font, text_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LADDER_LABEL_SIZE, 2, Color(0.02, 0.08, 0.05, colour.a * alpha * 0.75))
				draw_string(ThemeDB.fallback_font, text_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LADDER_LABEL_SIZE, Color(GREEN, colour.a * alpha))


## Project a point on the attitude sphere for a hook or label.
func _arc_screen(pitch: float, azimuth: float):
	var direction := HUD.pitch_arc(_camera.global_basis, pitch, azimuth, azimuth, 1)[0]
	return _screen(HUD.far_point(_camera.global_position, direction))


func _draw_attitude_arc(pitch: float, start: float, end: float, colour: Color, segments := 8) -> void:
	var previous = null
	for direction in HUD.pitch_arc(_camera.global_basis, pitch, start, end, segments):
		var at = _screen(HUD.far_point(_camera.global_position, direction))
		if previous != null and at != null:
			_draw_attitude_line(previous, at, colour)
		previous = at


func _draw_attitude_line(a: Vector2, b: Vector2, colour: Color) -> void:
	var alpha := HUD.visor_alpha((a + b) * 0.5, size)
	if alpha < 0.01 or a.distance_to(b) > size.length() * 0.25:
		return
	draw_line(a, b, Color(0.02, 0.08, 0.05, colour.a * alpha * 0.55), LINE_WIDTH + 1.5, true)
	draw_line(a, b, Color(colour, colour.a * alpha), LINE_WIDTH, true)


func _draw_visor() -> void:
	# Faint peripheral arcs suggest the inside of a visor without distorting
	# the scene, target positions or the flight-path marker.
	var radius := size * Vector2(0.45, 0.47)
	for side in [0.0, PI]:
		var points := PackedVector2Array()
		for index in range(33):
			var angle: float = side + lerpf(-0.72, 0.72, float(index) / 32.0)
			points.append(size * 0.5 + Vector2(cos(angle), sin(angle)) * radius)
		draw_polyline(points, Color(GREEN, 0.12), 1.0, true)


## The winged circle: where the aircraft is actually going, which is not where
## the nose is pointing. The single most convincing symbol on the glass.
func _draw_flight_path_marker() -> void:
	var direction: Vector3 = HUD.flight_path_direction(_velocity, _camera.global_basis)
	var at = _screen(HUD.far_point(_camera.global_position, direction))
	if at == null:
		return
	var colour := Color(GREEN, 0.95)
	draw_arc(at, FPM_RADIUS_PX, 0.0, TAU, 20, colour, LINE_WIDTH)
	draw_line(at + Vector2(-FPM_RADIUS_PX, 0.0), at + Vector2(-FPM_RADIUS_PX - 9.0, 0.0), colour, LINE_WIDTH)
	draw_line(at + Vector2(FPM_RADIUS_PX, 0.0), at + Vector2(FPM_RADIUS_PX + 9.0, 0.0), colour, LINE_WIDTH)
	draw_line(at + Vector2(0.0, -FPM_RADIUS_PX), at + Vector2(0.0, -FPM_RADIUS_PX - 7.0), colour, LINE_WIDTH)


func _draw_boresight() -> void:
	var nose := -_camera.global_basis.z
	var at = _screen(HUD.far_point(_camera.global_position, nose))
	if at == null:
		return
	var colour := Color(GREEN, 0.45)
	draw_line(at + Vector2(-6.0, 0.0), at + Vector2(6.0, 0.0), colour, LINE_WIDTH)
	draw_line(at + Vector2(0.0, -6.0), at + Vector2(0.0, 6.0), colour, LINE_WIDTH)


func _draw_boxes() -> void:
	var locked_handle := int(_locked.get("handle", -1)) if not _locked.is_empty() else -1
	for c in _boxed:
		if int(c["handle"]) == locked_handle:
			continue
		var position: Vector3 = c["position"]
		var at = _screen(position)
		if at == null:
			continue
		var range_m := _camera.global_position.distance_to(position)
		var half := box_half_extent_px(range_m)
		var colour := Color(HOSTILE_RED if TRACKER.is_airborne(c) else GREEN, 0.7)
		draw_rect(Rect2((at as Vector2) - Vector2(half, half), Vector2(half, half) * 2.0), colour, false, LINE_WIDTH)
		draw_string(
			ThemeDB.fallback_font,
			(at as Vector2) + Vector2(-half, half + LABEL_SIZE + 2.0),
			"%d" % roundi(range_m),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, colour
		)


## The lock is loud, and when it goes off-screen it becomes a chevron on the
## edge rather than nothing. The scope already makes that promise about its rim
## contacts; the glass makes the same one.
func _draw_lock() -> void:
	if _locked.is_empty():
		return
	var position: Vector3 = _locked["position"]
	var range_m := _camera.global_position.distance_to(position)
	var at = _screen(position)
	var viewport := Rect2(Vector2.ZERO, size)
	if at == null or not viewport.has_point(at):
		_draw_lock_chevron(position, range_m)
		return
	var centre: Vector2 = at
	var half := maxf(box_half_extent_px(range_m), 14.0)
	var colour := _lock_colour()
	# Diamond.
	draw_polyline(PackedVector2Array([
		centre + Vector2(0.0, -half), centre + Vector2(half, 0.0),
		centre + Vector2(0.0, half), centre + Vector2(-half, 0.0),
		centre + Vector2(0.0, -half),
	]), colour, LOCK_LINE_WIDTH)
	# Corner brackets, outside the diamond.
	var bracket := half + 8.0
	for corner in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		var c: Vector2 = centre + corner * bracket
		draw_line(c, c - Vector2(corner.x * 7.0, 0.0), colour, LOCK_LINE_WIDTH)
		draw_line(c, c - Vector2(0.0, corner.y * 7.0), colour, LOCK_LINE_WIDTH)
	if not _seeker.is_empty() and int(_seeker.get("handle", -1)) == int(_locked["handle"]):
		var ready := bool(_seeker.get("ready", false))
		var progress := float(_seeker.get("progress", 0.0))
		var seeker_colour := HOSTILE_RED if ready else AMBER
		if progress > 0.0:
			draw_arc(centre, bracket + 5.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, seeker_colour, LOCK_LINE_WIDTH, true)
		var seeker_text := String(_seeker.get("fire_label", "MISSILE LOCK - FIRE")) if ready else String(_seeker.get("status", "ACQUIRING"))
		draw_string(ThemeDB.fallback_font, centre + Vector2(-bracket, bracket + 24.0), seeker_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE + 1, seeker_colour)
	var label := "%s  %d m  %s" % [
		kind_label(int(_locked["kind"])), roundi(range_m), closure_text(_closure)
	]
	var contact_name := String(_locked.get("name", ""))
	if not contact_name.is_empty():
		label = "%s  %s" % [contact_name, label]
	draw_string(
		ThemeDB.fallback_font, centre + Vector2(bracket + 6.0, 4.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE + 1, colour
	)


func _draw_lock_chevron(position: Vector3, range_m: float) -> void:
	var colour := _lock_colour()
	var centre := size * 0.5
	var to_target: Vector3 = position - _camera.global_position
	var local: Vector3 = _camera.global_basis.inverse() * to_target
	var direction := Vector2(local.x, -local.y)
	if local.z > 0.0:
		# Behind: the sideways sense is preserved, but it is astern.
		direction = Vector2(-local.x, -local.y)
	if direction.length_squared() < 1e-6:
		direction = Vector2.DOWN
	direction = direction.normalized()
	var edge := centre + direction * (minf(size.x, size.y) * 0.5 - EDGE_MARGIN_PX)
	var side := Vector2(-direction.y, direction.x)
	draw_polyline(PackedVector2Array([
		edge - direction * 10.0 + side * 7.0, edge, edge - direction * 10.0 - side * 7.0,
	]), colour, LOCK_LINE_WIDTH)
	draw_string(
		ThemeDB.fallback_font, edge - direction * 26.0 + Vector2(-14.0, 0.0),
		"%d" % roundi(range_m), HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, colour
	)


## Screen-fixed, and that is the point: they do not swing, so the conformal
## symbols read as conformal by contrast.
func _draw_tapes() -> void:
	if _instruments.is_empty():
		return
	var font := ThemeDB.fallback_font
	var speed_knots := float(_instruments.get("speed_mps", 0.0)) * 1.94384
	var altitude := float(_instruments.get("altitude_m", 0.0))
	var heading := float(_instruments.get("heading_degrees", 0.0))
	var middle := size.y * 0.5
	var margin := maxf(TAPE_MARGIN_PX, size.x * 0.13)
	_draw_tape(Vector2(margin, middle), "%d" % roundi(speed_knots), "KT", true)
	_draw_tape(Vector2(size.x - margin, middle), "%d" % roundi(altitude), "M", false)
	# Heading across the top, boxed at the nose.
	var top := Vector2(size.x * 0.5, maxf(TAPE_MARGIN_PX, size.y * 0.14))
	var heading_arc := PackedVector2Array()
	for index in range(33):
		var x := lerpf(-140.0, 140.0, float(index) / 32.0)
		heading_arc.append(top + Vector2(x, 10.0 + pow(x / 140.0, 2.0) * 12.0))
	draw_polyline(heading_arc, Color(GREEN, 0.5), LINE_WIDTH, true)
	for offset in range(-60, 61, 15):
		var x: float = top.x + float(offset) * 2.2
		var bend := pow((x - top.x) / 140.0, 2.0) * 12.0
		draw_line(Vector2(x, top.y + 6.0 + bend), Vector2(x, top.y + 14.0 + bend), Color(GREEN, 0.5), LINE_WIDTH)
	var heading_text := "%03d" % (int(roundi(heading)) % 360)
	draw_rect(Rect2(top + Vector2(-22.0, -10.0), Vector2(44.0, 18.0)), Color(GREEN, 0.9), false, LINE_WIDTH)
	draw_string(font, top + Vector2(-17.0, 4.0), heading_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE + 1, GREEN)
	# G and Mach beneath the speed tape.
	var readout := Vector2(margin, middle + minf(TAPE_HEIGHT_PX, size.y * 0.38) * 0.5 + 22.0)
	draw_string(font, readout, "G %.1f" % float(_instruments.get("g_load", 1.0)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, Color(GREEN, 0.8))
	draw_string(font, readout + Vector2(0.0, LABEL_SIZE + 4.0), "M %.2f" % float(_instruments.get("mach", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, Color(GREEN, 0.8))


func _draw_tape(anchor: Vector2, value: String, unit: String, left: bool) -> void:
	var font := ThemeDB.fallback_font
	var half := minf(TAPE_HEIGHT_PX, size.y * 0.38) * 0.5
	var colour := Color(GREEN, 0.5)
	var direction := 1.0 if left else -1.0
	var rail := PackedVector2Array()
	for index in range(25):
		var t := lerpf(-1.0, 1.0, float(index) / 24.0)
		rail.append(anchor + Vector2(t * t * 14.0 * direction, t * half))
	draw_polyline(rail, colour, LINE_WIDTH, true)
	for step in range(-4, 5):
		var y: float = anchor.y + float(step) * (half / 4.0)
		var length := 10.0 if step % 2 == 0 else 5.0
		var x := anchor.x + pow(float(step) / 4.0, 2.0) * 14.0 * direction
		draw_line(Vector2(x, y), Vector2(x + length * direction, y), colour, LINE_WIDTH)
	var box := Rect2(anchor + Vector2(-4.0 if left else -56.0, -11.0), Vector2(60.0, 22.0))
	draw_rect(box, Color(GREEN, 0.9), false, LINE_WIDTH)
	draw_string(font, box.position + Vector2(5.0, 16.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE + 2, GREEN)
	draw_string(font, box.position + Vector2(5.0, 32.0), unit, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE - 2, Color(GREEN, 0.7))
