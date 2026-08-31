extends Control

## Gunsight for the attack close-up.
##
## Everything is drawn rather than themed, so the sight scales with the viewport
## and carries no textures. Alpha is driven by the attack zoom blend, so the
## sight is absent in tactical view and full strength at the tightest close-up.

@export var sight_colour := Color(0.45, 1.0, 0.6)
@export var arm_length := 18.0
@export var arm_gap := 7.0
@export var pipper_radius := 9.0
@export var line_width := 2.0
@export var readout_offset := Vector2(34.0, -10.0)
@export var readout_size := 15.0

var _alpha := 0.0
var _pipper := Vector2.ZERO
var _has_pipper := false
var _range_text := "--"
var _time_text := "--"
var _instruments := PackedStringArray()
var _target := Vector2.ZERO
var _has_target := false
var _target_range := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `solution` is the ballistics result, empty when there is no firing solution.
func set_solution(alpha: float, pipper: Vector2, has_pipper: bool, solution: Dictionary) -> void:
	_alpha = clampf(alpha, 0.0, 1.0)
	_pipper = pipper
	_has_pipper = has_pipper
	if solution.is_empty():
		_range_text = "--"
		_time_text = "--"
	else:
		_range_text = "%d m" % roundi(float(solution.get("range", 0.0)))
		_time_text = "%.1f s" % float(solution.get("time", 0.0))
	queue_redraw()


## Cockpit instruments. There is no panel in the cockpit view, so airspeed,
## height and collective have to be on the glass: with the rotor model, a pilot
## who cannot see the collective cannot hold a hover.
func set_instruments(
	speed_knots: float,
	altitude_agl: float,
	collective: float,
	heading_degrees: float
) -> void:
	_instruments = PackedStringArray([
		"SPD  %3d kt" % roundi(speed_knots),
		"AGL  %4d m" % roundi(altitude_agl),
		"COL  %3d %%" % roundi(collective * 100.0),
		"HDG  %03d" % (int(roundi(heading_degrees)) % 360),
	])
	queue_redraw()


func hide_instruments() -> void:
	if _instruments.is_empty():
		return
	_instruments = PackedStringArray()
	queue_redraw()


## The picked ground point the aircraft can orbit. Drawn independently of the
## gunsight, which is faded by zoom -- the target is just as useful in a wide
## chase view as in the attack close-up.
func set_target(screen_position: Vector2, on_screen: bool, range_m: float) -> void:
	_target = screen_position
	_has_target = on_screen
	_target_range = range_m
	queue_redraw()


func clear_target() -> void:
	if not _has_target:
		return
	_has_target = false
	queue_redraw()


func clear() -> void:
	if is_zero_approx(_alpha) and not _has_pipper:
		return
	_alpha = 0.0
	_has_pipper = false
	queue_redraw()


func _draw() -> void:
	if _has_target:
		var target_colour := Color(1.0, 0.72, 0.25)
		var arm := 11.0
		draw_line(_target + Vector2(-arm, 0.0), _target + Vector2(0.0, -arm), target_colour, line_width)
		draw_line(_target + Vector2(0.0, -arm), _target + Vector2(arm, 0.0), target_colour, line_width)
		draw_line(_target + Vector2(arm, 0.0), _target + Vector2(0.0, arm), target_colour, line_width)
		draw_line(_target + Vector2(0.0, arm), _target + Vector2(-arm, 0.0), target_colour, line_width)
		draw_string(
			ThemeDB.fallback_font,
			_target + Vector2(arm + 6.0, 4.0),
			"%d m" % roundi(_target_range),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			roundi(readout_size),
			target_colour
		)
	if _alpha <= 0.001:
		return
	var colour := Color(sight_colour, sight_colour.a * _alpha)
	var centre := size * 0.5
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(
			centre + direction * arm_gap,
			centre + direction * (arm_gap + arm_length),
			colour,
			line_width
		)
	draw_rect(Rect2(centre - Vector2.ONE, Vector2.ONE * 2.0), colour)
	if _has_pipper:
		draw_arc(_pipper, pipper_radius, 0.0, TAU, 24, colour, line_width)
		draw_line(_pipper - Vector2(0.0, pipper_radius + 5.0), _pipper - Vector2(0.0, pipper_radius), colour, line_width)
	var font := ThemeDB.fallback_font
	var origin := centre + readout_offset
	draw_string(font, origin, "RNG  %s" % _range_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, roundi(readout_size), colour)
	draw_string(font, origin + Vector2(0.0, readout_size + 6.0), "TOF  %s" % _time_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, roundi(readout_size), colour)
	var line := Vector2(28.0, size.y - 28.0 - float(_instruments.size() - 1) * (readout_size + 6.0))
	for reading in _instruments:
		draw_string(font, line, reading, HORIZONTAL_ALIGNMENT_LEFT, -1.0, roundi(readout_size), colour)
		line.y += readout_size + 6.0
