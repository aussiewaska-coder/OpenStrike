extends SceneTree

## Nose-up: a contact dead ahead is at the top whatever the heading, and a
## contact on the right is on the right. Beyond range it pins to the rim so a
## drone is never simply absent -- it is always at least a direction.

const SCOPE := preload("res://scripts/ui/radar_scope.gd")
const DRONE := preload("res://scripts/entities/drone.gd")


func _init() -> void:
	var range_m: float = SCOPE.RADAR_RANGE_M
	var radius: float = SCOPE.SCOPE_RADIUS_PX

	# Heading 0 is nose along -Z. A contact 2000 m ahead sits at the top.
	var ahead: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -2000.0), 0.0, range_m, radius)
	if ahead.y >= 0.0 or absf(ahead.x) > 0.5:
		_fail("a contact dead ahead must be straight up, got %v" % ahead)
	if not is_equal_approx(ahead.length(), radius * 0.5):
		_fail("half range must sit at half radius, got %f" % ahead.length())

	# Same contact, but the aircraft has turned to face +X (heading pi/2).
	# It is now on the aircraft's LEFT, so it appears on the left.
	var turned: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -2000.0), PI * 0.5, range_m, radius)
	if turned.x >= 0.0 or absf(turned.y) > 0.5:
		_fail("after a right turn a contact that was ahead is on the left, got %v" % turned)

	# Beyond range pins to the rim, direction preserved.
	var far: Vector2 = SCOPE.blip_offset(Vector3(0.0, 0.0, -9000.0), 0.0, range_m, radius)
	if not is_equal_approx(far.length(), radius):
		_fail("out of range must pin to the rim, got %f" % far.length())
	if far.y >= 0.0:
		_fail("a pinned contact keeps its direction")
	if not SCOPE.is_on_rim(Vector3(0.0, 0.0, -9000.0), range_m):
		_fail("out of range must report as on the rim")
	if SCOPE.is_on_rim(Vector3(0.0, 0.0, -2000.0), range_m):
		_fail("in range must not report as on the rim")

	# Altitude does not move a blip: this is a top-down scope.
	var high: Vector2 = SCOPE.blip_offset(Vector3(0.0, 3000.0, -2000.0), 0.0, range_m, radius)
	if not high.is_equal_approx(ahead):
		_fail("altitude must not displace a blip")

	# State drives colour, and every state has one.
	var seen := {}
	for state in DRONE.State.values():
		var colour: Color = SCOPE.colour_for_state(state)
		seen[colour.to_html()] = true
	if seen.size() < 4:
		_fail("inbound, attacking, evading and destroyed must be told apart by colour")

	print("RADAR_SCOPE_TEST_PASS")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
