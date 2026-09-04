extends SceneTree

## Nose-up: a contact dead ahead is at the top whatever the heading, and a
## contact on the right is on the right. Beyond range it pins to the rim so a
## contact is never simply absent -- it is always at least a direction. On top
## of that geometry the scope makes a claim about certainty: the further out a
## blip is, the fainter it is drawn.

const SCOPE := preload("res://scripts/ui/radar_scope.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")

var _failed := false


func _init() -> void:
	_geometry_is_nose_up()
	_out_of_range_pins_to_the_rim()
	_altitude_does_not_move_a_blip()
	_range_cycles_and_wraps()
	_blips_fade_with_range()
	_the_scope_only_takes_its_own_taps()
	_every_kind_has_a_colour()
	if _failed:
		return
	print("RADAR_SCOPE_TEST_PASS")
	quit()


func _geometry_is_nose_up() -> void:
	var range_m := 4000.0
	var radius: float = SCOPE.SCOPE_RADIUS_PX
	var ahead: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -2000.0), 0.0, range_m, radius)
	if ahead.y >= 0.0 or absf(ahead.x) > 0.5:
		_fail("a contact dead ahead must be straight up, got %v" % ahead)
	if not is_equal_approx(ahead.length(), radius * 0.5):
		_fail("half range must sit at half radius, got %f" % ahead.length())
	var turned: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -2000.0), PI * 0.5, range_m, radius)
	if turned.x >= 0.0 or absf(turned.y) > 0.5:
		_fail("after a right turn a contact that was ahead is on the left, got %v" % turned)


func _out_of_range_pins_to_the_rim() -> void:
	var range_m := 4000.0
	var radius: float = SCOPE.SCOPE_RADIUS_PX
	var far: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -9000.0), 0.0, range_m, radius)
	if not is_equal_approx(far.length(), radius):
		_fail("out of range must pin to the rim, got %f" % far.length())
	if far.y >= 0.0:
		_fail("a pinned contact keeps its direction")
	if not SCOPE.is_on_rim(Vector3(0.0, 0.0, -9000.0), range_m):
		_fail("out of range must report as on the rim")
	if SCOPE.is_on_rim(Vector3(0.0, 0.0, -2000.0), range_m):
		_fail("in range must not report as on the rim")


func _altitude_does_not_move_a_blip() -> void:
	var range_m := 4000.0
	var radius: float = SCOPE.SCOPE_RADIUS_PX
	var ahead: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -2000.0), 0.0, range_m, radius)
	var high: Vector2 = SCOPE.blip_offset(Vector3(0.0, 3000.0, -2000.0), 0.0, range_m, radius)
	if not high.is_equal_approx(ahead):
		_fail("altitude must not displace a blip: this is a top-down scope")


func _range_cycles_and_wraps() -> void:
	var scope = SCOPE.new()
	if not is_equal_approx(scope.range_m(), 10000.0):
		_fail("ten kilometres is the default, got %f" % scope.range_m())
	var seen := []
	for i in range(TRACKER.RADAR_RANGES_M.size()):
		seen.append(scope.cycle_range())
	if not is_equal_approx(scope.range_m(), 10000.0):
		_fail("cycling all the way round returns to the default, got %f" % scope.range_m())
	if seen.size() != TRACKER.RADAR_RANGES_M.size():
		_fail("every range must be reachable")
	scope.free()


## Fainter further out. A 10 km blip should not look as certain as a 2 km one.
func _blips_fade_with_range() -> void:
	var near: float = SCOPE.blip_alpha(1000.0, 10000.0)
	var far: float = SCOPE.blip_alpha(9000.0, 10000.0)
	if near <= far:
		_fail("a nearer contact must be drawn stronger, got %f then %f" % [near, far])
	if far < SCOPE.BLIP_MIN_ALPHA - 1e-6:
		_fail("distant but never absent, got %f" % far)
	if near > 1.0:
		_fail("alpha cannot exceed one, got %f" % near)


## The scope takes the taps inside its own disc and lets every other tap fall
## through to the lock gesture underneath.
func _the_scope_only_takes_its_own_taps() -> void:
	var scope = SCOPE.new()
	scope.size = Vector2(1280.0, 720.0)
	var centre = scope.scope_centre()
	if not scope._has_point(centre):
		_fail("the middle of the scope is the scope")
	if scope._has_point(centre + Vector2(SCOPE.SCOPE_RADIUS_PX * 2.0, 0.0)):
		_fail("outside the disc the tap belongs to the target lock")
	scope.free()


func _every_kind_has_a_colour() -> void:
	var seen := {}
	for kind in TRACKER.Kind.values():
		seen[SCOPE.colour_for_kind(kind).to_html()] = true
	if seen.size() < 3:
		_fail("jets, ground threats and structures must be told apart")


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
