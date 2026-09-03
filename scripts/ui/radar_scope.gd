extends Control

## A round air scope, aircraft at centre, nose up. Targets are blips whose
## screen position is their world offset rotated by minus the heading, so a
## contact ahead is at the top whatever way the aircraft points. Beyond range a
## blip pins to the rim as a chevron: a drone is never simply absent from the
## scope, it is always at least a direction.
##
## Drawn, not themed, like attack_reticle: no textures, scales with the
## viewport, and every element is a line or an arc.

const DRONE := preload("res://scripts/entities/drone.gd")

const RADAR_RANGE_M := 4000.0
const SCOPE_RADIUS_PX := 90.0
const MARGIN_PX := 24.0
const RING_COLOUR := Color(0.35, 0.9, 0.5, 0.55)
const BLIP_RADIUS_PX := 3.5

var _contacts: Array = []
var _player_position := Vector3.ZERO
var _heading := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Rotating the world offset by minus the heading puts the nose on -Z; screen
## y is down, and -Z is "up the screen", so the offset maps straight across.
static func blip_offset(world_offset: Vector3, heading: float, range_m: float, radius_px: float) -> Vector2:
	var flat := Vector2(world_offset.x, world_offset.z).rotated(-heading)
	var scaled := flat * (radius_px / maxf(range_m, 1.0))
	if scaled.length() > radius_px:
		scaled = scaled.normalized() * radius_px
	return scaled


static func is_on_rim(world_offset: Vector3, range_m: float) -> bool:
	return Vector2(world_offset.x, world_offset.z).length() > range_m


static func colour_for_state(state: int) -> Color:
	match state:
		DRONE.State.ATTACK_RUN:
			return Color(1.0, 0.72, 0.2)
		DRONE.State.EVADING:
			return Color(1.0, 0.3, 0.25)
		DRONE.State.DESTROYED:
			return Color(0.5, 0.5, 0.5, 0.6)
	return Color(0.92, 0.96, 1.0)


func set_contacts(player_position: Vector3, heading: float, drones: Array) -> void:
	_player_position = player_position
	_heading = heading
	_contacts = drones
	queue_redraw()


func _draw() -> void:
	var centre := Vector2(size.x - MARGIN_PX - SCOPE_RADIUS_PX, size.y - MARGIN_PX - SCOPE_RADIUS_PX)
	draw_circle(centre, SCOPE_RADIUS_PX, Color(0.02, 0.06, 0.04, 0.55))
	draw_arc(centre, SCOPE_RADIUS_PX, 0.0, TAU, 64, RING_COLOUR, 1.5)
	draw_arc(centre, SCOPE_RADIUS_PX * 0.5, 0.0, TAU, 48, RING_COLOUR * Color(1.0, 1.0, 1.0, 0.6), 1.0)
	# Own heading tick at the top, and the range label beside the outer ring.
	draw_line(centre + Vector2(0.0, -SCOPE_RADIUS_PX), centre + Vector2(0.0, -SCOPE_RADIUS_PX + 8.0), RING_COLOUR, 2.0)
	draw_string(
		get_theme_default_font(), centre + Vector2(SCOPE_RADIUS_PX - 34.0, -SCOPE_RADIUS_PX + 14.0),
		"%dKM" % int(RADAR_RANGE_M / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, RING_COLOUR
	)
	for drone in _contacts:
		var offset: Vector3 = drone.position - _player_position
		var at := centre + blip_offset(offset, _heading, RADAR_RANGE_M, SCOPE_RADIUS_PX)
		var colour := colour_for_state(drone.state)
		if is_on_rim(offset, RADAR_RANGE_M):
			# A chevron pointing outward: direction without a false range.
			var outward := (at - centre).normalized()
			var side := Vector2(-outward.y, outward.x)
			draw_polyline(PackedVector2Array([
				at - outward * 6.0 + side * 4.0, at, at - outward * 6.0 - side * 4.0
			]), colour, 1.5)
		else:
			draw_circle(at, BLIP_RADIUS_PX, colour)
