extends SceneTree

## The renderer's own logic: the camera-facing side vector, the global segment
## cap, and reclaiming finished trails. The ImmediateMesh itself is not asserted
## -- headless has no camera, and a vertex buffer proves nothing about whether
## the smoke looks like smoke. That part is a device check.

const RENDERER := preload("res://scripts/effects/trail_renderer.gd")
const TRAIL := preload("res://scripts/effects/trail_buffer.gd")


func _init() -> void:
	_side_faces_the_camera()
	_degenerate_segments_make_no_geometry()
	_the_cap_holds()
	_finished_trails_are_reclaimed()
	print("TRAIL_RENDERER_TEST_PASS")
	quit()


## The ribbon must present its face to the viewer, so the side vector is
## perpendicular both to the segment and to the direction to the eye.
func _side_faces_the_camera() -> void:
	var segment := Vector3(1.0, 0.0, 0.0)
	var to_eye := Vector3(0.0, 0.0, 1.0)
	var side: Vector3 = RENDERER.strip_side(segment, to_eye, 3.0)
	if absf(side.dot(segment)) > 0.001:
		_fail("the ribbon's width must be perpendicular to its length")
	if absf(side.dot(to_eye)) > 0.001:
		_fail("the ribbon's width must be perpendicular to the view direction")
	if not is_equal_approx(side.length(), 3.0):
		_fail("the side vector must carry the half width, got %f" % side.length())


## Seen exactly end-on the cross product collapses. Emitting that quad gives
## zero-area geometry or NaNs; it must be refused instead.
func _degenerate_segments_make_no_geometry() -> void:
	var along := Vector3(1.0, 0.0, 0.0)
	var collapsed: Vector3 = RENDERER.strip_side(along, along, 3.0)
	if not collapsed.is_zero_approx():
		_fail("an end-on segment must produce no width, got %v" % collapsed)
	var nothing: Vector3 = RENDERER.strip_side(Vector3.ZERO, Vector3(0.0, 0.0, 1.0), 3.0)
	if not nothing.is_zero_approx():
		_fail("a zero-length segment must produce no width")


func _the_cap_holds() -> void:
	var renderer = RENDERER.new()
	# Twelve trails, each long enough on its own to threaten the cap.
	for id in range(12):
		renderer.begin_trail(id)
		for step in range(600):
			renderer.push_point(id, Vector3(float(step) * TRAIL.SEGMENT_METRES, float(id), 0.0))
	if renderer.total_segments() > RENDERER.MAX_TRAIL_SEGMENTS:
		_fail("the segment cap must hold, got %d over %d" % [
			renderer.total_segments(), RENDERER.MAX_TRAIL_SEGMENTS
		])
	if renderer.total_segments() == 0:
		_fail("capping must shorten trails, not delete them")
	renderer.free()


func _finished_trails_are_reclaimed() -> void:
	var renderer = RENDERER.new()
	renderer.begin_trail(1)
	renderer.push_point(1, Vector3.ZERO)
	renderer.push_point(1, Vector3(TRAIL.SEGMENT_METRES * 2.0, 0.0, 0.0))
	if renderer.active_trail_count() != 1:
		_fail("a started trail must be active")
	renderer.end_trail(1)
	if renderer.active_trail_count() != 1:
		_fail("smoke must outlive the rocket that laid it")
	# Age everything well past the lifetime.
	renderer.age_trails(TRAIL.LIFETIME_SECONDS * 3.0)
	if renderer.active_trail_count() != 0:
		_fail("a finished trail must free its slot, %d left" % renderer.active_trail_count())
	renderer.free()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
