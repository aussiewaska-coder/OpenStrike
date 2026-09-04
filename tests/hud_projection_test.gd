extends SceneTree

## The visor's symbols are world directions, not screen positions. Keeping the
## maths on this side of the line is what lets a head-up display be tested
## without a viewport: the Control only has to call unproject_position on what
## these functions return.

const HUD := preload("res://scripts/ui/hud_projection.gd")

var _failed := false


func _init() -> void:
	_horizon_is_level_whatever_the_attitude()
	_horizon_spans_the_view()
	_climb_bars_are_above_and_dive_bars_below()
	_the_ladder_covers_the_sphere()
	_the_flight_path_marker_follows_the_velocity()
	_a_parked_aircraft_puts_the_marker_on_the_nose()
	if _failed:
		return
	print("HUD_PROJECTION_TEST_PASS")
	quit()


## Whatever the aircraft is doing, the horizon is at the aircraft's altitude.
## The cant you see on the glass comes from the camera, not from this.
func _horizon_is_level_whatever_the_attitude() -> void:
	var origin := Vector3(0.0, 1500.0, 0.0)
	for attitude in [
		Basis.IDENTITY,
		Basis(Vector3.FORWARD, deg_to_rad(45.0)),
		Basis(Vector3.RIGHT, deg_to_rad(30.0)),
	]:
		var points: Array = HUD.horizon_points(attitude, origin)
		for p in points:
			if not is_equal_approx((p as Vector3).y, origin.y):
				_fail("the horizon must sit at the camera's altitude, got %f" % (p as Vector3).y)


func _horizon_spans_the_view() -> void:
	var points: Array = HUD.horizon_points(Basis.IDENTITY, Vector3.ZERO)
	if points.size() != 2:
		_fail("a horizon is a line, so it is two points")
	var span: float = (points[0] as Vector3).distance_to(points[1] as Vector3)
	if not is_equal_approx(span, HUD.CONFORMAL_DISTANCE_M * 2.0):
		_fail("the horizon must reach past anything drawn, got %f" % span)


## Godot's forward is -Z and up is +Y. A climb bar points up.
func _climb_bars_are_above_and_dive_bars_below() -> void:
	var up: Vector3 = HUD.ladder_direction(Basis.IDENTITY, 30.0)
	if up.y <= 0.0:
		_fail("the +30 bar must point above the horizon, got %v" % up)
	var down: Vector3 = HUD.ladder_direction(Basis.IDENTITY, -30.0)
	if down.y >= 0.0:
		_fail("the -30 bar must point below the horizon, got %v" % down)
	var level: Vector3 = HUD.ladder_direction(Basis.IDENTITY, 0.0)
	if not is_zero_approx(level.y):
		_fail("the zero bar is the horizon itself, got %v" % level)
	if not is_equal_approx(up.length(), 1.0):
		_fail("directions must be unit length")


func _the_ladder_covers_the_sphere() -> void:
	var degrees: PackedFloat32Array = HUD.ladder_degrees()
	if degrees[0] > -90.0 or degrees[degrees.size() - 1] < 90.0:
		_fail("the ladder must run from straight down to straight up")
	if not is_equal_approx(degrees[1] - degrees[0], HUD.PITCH_LADDER_STEP_DEGREES):
		_fail("bars must be evenly spaced")


## Where the jet is actually going, which is not where the nose points.
func _the_flight_path_marker_follows_the_velocity() -> void:
	var climbing := Vector3(0.0, 100.0, -200.0)
	var marker: Vector3 = HUD.flight_path_direction(climbing, Basis.IDENTITY)
	if marker.y <= 0.0:
		_fail("a climbing jet puts the marker above the horizon, got %v" % marker)
	if not marker.is_equal_approx(climbing.normalized()):
		_fail("the marker is the velocity, normalised")


func _a_parked_aircraft_puts_the_marker_on_the_nose() -> void:
	var marker: Vector3 = HUD.flight_path_direction(Vector3(0.0, 0.0, -1.0), Basis.IDENTITY)
	if not marker.is_equal_approx(Vector3(0.0, 0.0, -1.0)):
		_fail("below the speed floor the marker parks on the boresight, got %v" % marker)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
