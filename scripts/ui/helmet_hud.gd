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
const LINE_WIDTH := 1.4
const LOCK_LINE_WIDTH := 2.4
const LABEL_SIZE := 12

const BOX_MAX_PX := 44.0
const BOX_MIN_PX := 7.0
## The range at which a box has shrunk to its floor.
const BOX_FALLOFF_M := 6000.0

const LADDER_HALF_LENGTH_PX := 46.0
const LADDER_GAP_PX := 16.0
const TAPE_MARGIN_PX := 26.0
const TAPE_HEIGHT_PX := 190.0
const FPM_RADIUS_PX := 8.0
const EDGE_MARGIN_PX := 34.0

var _camera: Camera3D
var _velocity := Vector3.ZERO
var _boxed: Array = []
var _locked := {}
var _closure := 0.0
var _instruments := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


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
	_draw_horizon()
	_draw_ladder()
	_draw_flight_path_marker()
	_draw_boresight()
	_draw_boxes()
	_draw_lock()
	_draw_tapes()


## A world point becomes a screen point, or null when it is behind the camera.
func _screen(world: Vector3):
	if _camera.is_position_behind(world):
		return null
	return _camera.unproject_position(world)


func _draw_horizon() -> void:
	var points: Array = HUD.horizon_points(_camera.global_basis, _camera.global_position)
	var a = _screen(points[0])
	var b = _screen(points[1])
	if a == null or b == null:
		return
	draw_line(a, b, Color(GREEN, 0.85), LINE_WIDTH)


## Climb bars solid, dive bars dashed with their ends turned down toward the
## ground. That is what a real ladder does, and it is the cheapest way to tell
## a climb from a dive at a glance.
func _draw_ladder() -> void:
	var basis := _camera.global_basis
	var origin := _camera.global_position
	var along := _horizon_direction()
	var down := Vector2(-along.y, along.x)
	for degrees in HUD.ladder_degrees():
		if is_zero_approx(degrees):
			continue
		var centre = _screen(HUD.far_point(origin, HUD.ladder_direction(basis, degrees)))
		if centre == null:
			continue
		var climbing := degrees > 0.0
		var colour := Color(GREEN, 0.6)
		for side in [-1.0, 1.0]:
			var inner: Vector2 = centre + along * (LADDER_GAP_PX * side)
			var outer: Vector2 = centre + along * (LADDER_HALF_LENGTH_PX * side)
			if climbing:
				draw_line(inner, outer, colour, LINE_WIDTH)
			else:
				# Dashed: three short strokes rather than one line.
				for step in range(3):
					var t0 := float(step) / 3.0
					var t1 := t0 + 0.22
					draw_line(inner.lerp(outer, t0), inner.lerp(outer, t1), colour, LINE_WIDTH)
				# The turned-down end, on dive bars only.
				draw_line(outer, outer + down * 7.0, colour, LINE_WIDTH)
		draw_string(
			ThemeDB.fallback_font,
			centre + along * (LADDER_HALF_LENGTH_PX + 6.0) + Vector2(0.0, 4.0),
			"%d" % int(absf(degrees)),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, colour
		)


## The screen direction the horizon runs along, so ladder bars cant with it.
func _horizon_direction() -> Vector2:
	var points: Array = HUD.horizon_points(_camera.global_basis, _camera.global_position)
	var a = _screen(points[0])
	var b = _screen(points[1])
	if a == null or b == null:
		return Vector2.RIGHT
	var delta: Vector2 = (b as Vector2) - (a as Vector2)
	return delta.normalized() if delta.length_squared() > 1e-6 else Vector2.RIGHT


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
		draw_rect(Rect2((at as Vector2) - Vector2(half, half), Vector2(half, half) * 2.0), Color(GREEN, 0.7), false, LINE_WIDTH)
		draw_string(
			ThemeDB.fallback_font,
			(at as Vector2) + Vector2(-half, half + LABEL_SIZE + 2.0),
			"%d" % roundi(range_m),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, Color(GREEN, 0.7)
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
	# Diamond.
	draw_polyline(PackedVector2Array([
		centre + Vector2(0.0, -half), centre + Vector2(half, 0.0),
		centre + Vector2(0.0, half), centre + Vector2(-half, 0.0),
		centre + Vector2(0.0, -half),
	]), AMBER, LOCK_LINE_WIDTH)
	# Corner brackets, outside the diamond.
	var bracket := half + 8.0
	for corner in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]:
		var c: Vector2 = centre + corner * bracket
		draw_line(c, c - Vector2(corner.x * 7.0, 0.0), AMBER, LOCK_LINE_WIDTH)
		draw_line(c, c - Vector2(0.0, corner.y * 7.0), AMBER, LOCK_LINE_WIDTH)
	var label := "%s  %d m  %s" % [
		kind_label(int(_locked["kind"])), roundi(range_m), closure_text(_closure)
	]
	var contact_name := String(_locked.get("name", ""))
	if not contact_name.is_empty():
		label = "%s  %s" % [contact_name, label]
	draw_string(
		ThemeDB.fallback_font, centre + Vector2(bracket + 6.0, 4.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE + 1, AMBER
	)


func _draw_lock_chevron(position: Vector3, range_m: float) -> void:
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
	]), AMBER, LOCK_LINE_WIDTH)
	draw_string(
		ThemeDB.fallback_font, edge - direction * 26.0 + Vector2(-14.0, 0.0),
		"%d" % roundi(range_m), HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, AMBER
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
	_draw_tape(Vector2(TAPE_MARGIN_PX, middle), "%d" % roundi(speed_knots), "KT", true)
	_draw_tape(Vector2(size.x - TAPE_MARGIN_PX, middle), "%d" % roundi(altitude), "M", false)
	# Heading across the top, boxed at the nose.
	var top := Vector2(size.x * 0.5, TAPE_MARGIN_PX)
	draw_line(top + Vector2(-140.0, 10.0), top + Vector2(140.0, 10.0), Color(GREEN, 0.5), LINE_WIDTH)
	for offset in range(-60, 61, 15):
		var x: float = top.x + float(offset) * 2.2
		draw_line(Vector2(x, top.y + 6.0), Vector2(x, top.y + 14.0), Color(GREEN, 0.5), LINE_WIDTH)
	var heading_text := "%03d" % (int(roundi(heading)) % 360)
	draw_rect(Rect2(top + Vector2(-22.0, -10.0), Vector2(44.0, 18.0)), Color(GREEN, 0.9), false, LINE_WIDTH)
	draw_string(font, top + Vector2(-17.0, 4.0), heading_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE + 1, GREEN)
	# G and Mach beneath the speed tape.
	var readout := Vector2(TAPE_MARGIN_PX, middle + TAPE_HEIGHT_PX * 0.5 + 22.0)
	draw_string(font, readout, "G %.1f" % float(_instruments.get("g_load", 1.0)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, Color(GREEN, 0.8))
	draw_string(font, readout + Vector2(0.0, LABEL_SIZE + 4.0), "M %.2f" % float(_instruments.get("mach", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE, Color(GREEN, 0.8))


func _draw_tape(anchor: Vector2, value: String, unit: String, left: bool) -> void:
	var font := ThemeDB.fallback_font
	var half := TAPE_HEIGHT_PX * 0.5
	var colour := Color(GREEN, 0.5)
	draw_line(anchor + Vector2(0.0, -half), anchor + Vector2(0.0, half), colour, LINE_WIDTH)
	var direction := 1.0 if left else -1.0
	for step in range(-4, 5):
		var y: float = anchor.y + float(step) * (half / 4.0)
		var length := 10.0 if step % 2 == 0 else 5.0
		draw_line(Vector2(anchor.x, y), Vector2(anchor.x + length * direction, y), colour, LINE_WIDTH)
	var box := Rect2(anchor + Vector2(-4.0 if left else -56.0, -11.0), Vector2(60.0, 22.0))
	draw_rect(box, Color(GREEN, 0.9), false, LINE_WIDTH)
	draw_string(font, box.position + Vector2(5.0, 16.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE + 2, GREEN)
	draw_string(font, box.position + Vector2(5.0, 32.0), unit, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_SIZE - 2, Color(GREEN, 0.7))
