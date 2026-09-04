extends Control

## A round air scope, aircraft at centre, nose up. Targets are blips whose
## screen position is their world offset rotated by minus the heading, so a
## contact ahead is at the top whatever way the aircraft points. Beyond range a
## blip pins to the rim as a chevron: a contact is never simply absent from the
## scope, it is always at least a direction.
##
## The scope makes two different fades, and they are unrelated. The BODY fades
## to its rim, so the instrument dissolves into the view instead of sitting on
## it as a disc -- that is a look. A BLIP fades with its range, because a
## contact at nine kilometres is not known as well as one at two -- that is a
## claim. Deliberately no per-frame positional jitter: jitter that moves every
## frame reads as a bug, not as uncertainty.
##
## Drawn, not themed: no textures, scales with the viewport, and every element
## is a line, an arc or a polygon.

signal range_changed(metres: float)

const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

const SCOPE_RADIUS_PX := 90.0
const MARGIN_PX := 24.0
const RING_COLOUR := Color(0.35, 0.9, 0.5, 0.55)
const BLIP_RADIUS_PX := 3.5
const LOCK_COLOUR := Color(1.0, 0.72, 0.25)

## Translucent at the middle, gone at the rim.
const SCOPE_CENTRE_ALPHA := 0.45
const BLIP_MIN_ALPHA := 0.35
## Past this fraction of the range a blip is a ring rather than a dot.
const BLIP_SOFT_FRACTION := 0.6
const SWEEP_PERIOD_S := 2.5
## How long a contact stays lit after the sweep has crossed it.
const SWEEP_GLOW_S := 0.45
const BODY_SEGMENTS := 48

var _contacts: Array = []
var _player_position := Vector3.ZERO
var _heading := 0.0
var _locked_handle := -1
var _range_index: int = TRACKER.DEFAULT_RANGE_INDEX
var _sweep := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(true)


func _process(delta: float) -> void:
	_sweep = fmod(_sweep + delta / SWEEP_PERIOD_S, 1.0)
	queue_redraw()


func scope_centre() -> Vector2:
	return Vector2(size.x - MARGIN_PX - SCOPE_RADIUS_PX, size.y - MARGIN_PX - SCOPE_RADIUS_PX)


## Only the disc belongs to the scope. Everywhere else the tap falls through to
## the target lock underneath, which is the whole reason this override exists.
func _has_point(point: Vector2) -> bool:
	return point.distance_to(scope_centre()) <= SCOPE_RADIUS_PX


func _gui_input(event: InputEvent) -> void:
	var pressed := (
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or (event is InputEventMouseButton
			and (event as InputEventMouseButton).pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	)
	if pressed:
		cycle_range()
		accept_event()


func range_m() -> float:
	return TRACKER.RADAR_RANGES_M[_range_index]


func cycle_range() -> float:
	_range_index = (_range_index + 1) % TRACKER.RADAR_RANGES_M.size()
	range_changed.emit(range_m())
	queue_redraw()
	return range_m()


static func blip_offset(world_offset: Vector3, heading: float, range_m: float, radius_px: float) -> Vector2:
	var flat := Vector2(world_offset.x, world_offset.z).rotated(-heading)
	var scaled := flat * (radius_px / maxf(range_m, 1.0))
	if scaled.length() > radius_px:
		scaled = scaled.normalized() * radius_px
	return scaled


static func is_on_rim(world_offset: Vector3, range_m: float) -> bool:
	return Vector2(world_offset.x, world_offset.z).length() > range_m


static func blip_alpha(range_m: float, scope_range_m: float) -> float:
	var t := clampf(range_m / maxf(scope_range_m, 1.0), 0.0, 1.0)
	return lerpf(1.0, BLIP_MIN_ALPHA, t)


static func colour_for_kind(kind: int) -> Color:
	match kind:
		TRACKER.Kind.AIR_JET:
			return Color(1.0, 0.45, 0.35)
		TRACKER.Kind.AIR_DRONE:
			return Color(1.0, 0.78, 0.35)
		TRACKER.Kind.GROUND_LAUNCHER:
			return Color(1.0, 0.35, 0.6)
		TRACKER.Kind.BUILDING:
			return Color(0.6, 0.85, 1.0)
		TRACKER.Kind.GROUND_POINT:
			return Color(0.8, 0.9, 1.0)
	return Color(0.92, 0.96, 1.0)


func set_contacts(player_position: Vector3, heading: float, contacts: Array, locked_handle: int) -> void:
	_player_position = player_position
	_heading = heading
	_contacts = contacts
	_locked_handle = locked_handle
	queue_redraw()


func _draw() -> void:
	var centre := scope_centre()
	_draw_body(centre)
	draw_arc(centre, SCOPE_RADIUS_PX, 0.0, TAU, 64, RING_COLOUR, 1.5)
	draw_arc(centre, SCOPE_RADIUS_PX * 0.5, 0.0, TAU, 48, RING_COLOUR * Color(1.0, 1.0, 1.0, 0.6), 1.0)
	draw_line(centre + Vector2(0.0, -SCOPE_RADIUS_PX), centre + Vector2(0.0, -SCOPE_RADIUS_PX + 8.0), RING_COLOUR, 2.0)
	_draw_sweep(centre)
	draw_string(
		ThemeDB.fallback_font, centre + Vector2(SCOPE_RADIUS_PX - 40.0, -SCOPE_RADIUS_PX + 14.0),
		"%dKM" % int(range_m() / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, RING_COLOUR
	)
	_draw_contacts(centre)


## A triangle fan whose per-vertex alpha falls to nothing at the rim. No
## shader, no texture, one call -- which is what `draw_polygon`'s vertex
## colours are for.
func _draw_body(centre: Vector2) -> void:
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	points.append(centre)
	colours.append(Color(0.05, 0.14, 0.09, SCOPE_CENTRE_ALPHA))
	for i in range(BODY_SEGMENTS + 1):
		var angle := TAU * float(i) / float(BODY_SEGMENTS)
		points.append(centre + Vector2(cos(angle), sin(angle)) * SCOPE_RADIUS_PX)
		colours.append(Color(0.05, 0.14, 0.09, 0.0))
	draw_polygon(points, colours)


func _draw_sweep(centre: Vector2) -> void:
	var angle := _sweep * TAU - PI * 0.5
	for i in range(6):
		var trail := angle - float(i) * 0.06
		var alpha := 0.35 * (1.0 - float(i) / 6.0)
		draw_line(centre, centre + Vector2(cos(trail), sin(trail)) * SCOPE_RADIUS_PX, Color(0.5, 1.0, 0.7, alpha), 1.5)


func _draw_contacts(centre: Vector2) -> void:
	var scope_range := range_m()
	for c in _contacts:
		var offset: Vector3 = (c["position"] as Vector3) - _player_position
		var at := centre + blip_offset(offset, _heading, scope_range, SCOPE_RADIUS_PX)
		var kind := int(c["kind"])
		var range_m_to := Vector2(offset.x, offset.z).length()
		var colour := colour_for_kind(kind)
		colour.a = blip_alpha(range_m_to, scope_range) * _sweep_glow(offset)
		if is_on_rim(offset, scope_range):
			var outward := (at - centre).normalized()
			var side := Vector2(-outward.y, outward.x)
			draw_polyline(PackedVector2Array([
				at - outward * 6.0 + side * 4.0, at, at - outward * 6.0 - side * 4.0
			]), colour, 1.5)
		elif kind == TRACKER.Kind.GROUND_LAUNCHER:
			# Ground threats are carets, so a SAM is never mistaken for a jet.
			draw_polyline(PackedVector2Array([
				at + Vector2(-4.5, 3.5), at + Vector2(0.0, -4.0), at + Vector2(4.5, 3.5)
			]), colour, 1.5)
		elif range_m_to > scope_range * BLIP_SOFT_FRACTION:
			draw_arc(at, BLIP_RADIUS_PX, 0.0, TAU, 12, colour, 1.2)
		else:
			draw_circle(at, BLIP_RADIUS_PX, colour)
		if int(c["handle"]) == _locked_handle:
			draw_arc(at, BLIP_RADIUS_PX + 5.0, 0.0, TAU, 20, LOCK_COLOUR, 1.8)


## A contact brightens as the sweep crosses its bearing and dims again behind
## it. This is the animation, and it is one subtraction.
func _sweep_glow(offset: Vector3) -> float:
	var bearing := Vector2(offset.x, offset.z).rotated(-_heading).angle() + PI * 0.5
	var swept := fmod(_sweep * TAU - bearing + TAU * 2.0, TAU)
	var since := swept / TAU * SWEEP_PERIOD_S
	if since > SWEEP_GLOW_S:
		return 1.0
	return lerpf(1.6, 1.0, since / SWEEP_GLOW_S)
