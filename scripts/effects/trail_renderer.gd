extends MeshInstance3D

## Every live smoke trail in the world, in ONE ImmediateMesh rebuilt each frame.
##
## One draw call and one material however many rockets are up. The alternatives
## were an emitter node per rocket -- N draw calls, and mobile drivers disagree
## about trail geometry -- or pooled billboard puffs, which need hundreds of
## quads per trail before they stop reading as beads. Neither gets thick
## continuous smoke cheaply, and that is the whole point of the effect.
##
## It also matches the house style: cannon_fx pools plain MeshInstance3D quads
## by hand, and this project hand-rolls its simulation rather than reaching for
## the physics server.

const TRAIL_BUFFER := preload("res://scripts/effects/trail_buffer.gd")

## Hard ceiling across every trail. Reaching it shortens the oldest trails
## rather than dropping frames, so the effect degrades instead of the game.
## 2400 segments is 9600 vertices in one call -- trivial geometry. The real cost
## is fill rate from overlapping translucent quads, which is why width and
## lifetime are the knobs to pull if a device struggles, not this.
const MAX_TRAIL_SEGMENTS := 2400

@export var smoke_colour := Color(0.82, 0.82, 0.85)

var _mesh: ImmediateMesh
var _trails: Dictionary = {}
var _now := 0.0


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	material_override = _make_material()
	# Smoke is world-space: it must not follow the aircraft that laid it.
	top_level = true
	global_transform = Transform3D.IDENTITY


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	# The geometry already faces the camera; billboarding it again would fight
	# the strip maths and spin every quad about its own centre.
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	# Depth-write off is the usual soft-smoke trade: trails blend with each
	# other instead of one occluding the next, which is what you want for smoke
	# and would be wrong for solid geometry.
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func begin_trail(id: int) -> void:
	_trails[id] = TRAIL_BUFFER.new()


func push_point(id: int, point: Vector3) -> void:
	var trail = _trails.get(id)
	if trail == null:
		return
	# Only a breadcrumb that was actually laid can push the total over, and most
	# calls lay nothing -- rockets are asked every frame and answer every few
	# metres. Checking the cap regardless would scan every trail for nothing.
	if trail.push(point, _now):
		_enforce_cap()


## The rocket is gone; its smoke is not. The buffer stops taking breadcrumbs and
## ages out on its own.
func end_trail(id: int) -> void:
	var trail = _trails.get(id)
	if trail != null:
		trail.stop_emitting()


func active_trail_count() -> int:
	return _trails.size()


func total_segments() -> int:
	var total := 0
	for trail in _trails.values():
		total += trail.segment_count()
	return total


## Ages every trail to `now` and reclaims the finished ones. Separate from
## _process so the tests can drive time directly.
func age_trails(now: float) -> void:
	_now = now
	var finished: Array = []
	for id in _trails:
		var trail = _trails[id]
		trail.advance_age(now)
		if trail.is_finished(now):
			finished.append(id)
	for id in finished:
		_trails.erase(id)


func _process(delta: float) -> void:
	age_trails(_now + delta)
	_rebuild()


## Retires the oldest breadcrumbs until the total is back inside the cap. Ageing
## by a step at a time would be gentler but can fail to converge; a direct trim
## cannot.
func _enforce_cap() -> void:
	var over := total_segments() - MAX_TRAIL_SEGMENTS
	if over <= 0:
		return
	for trail in _trails.values():
		if over <= 0:
			break
		var drop: int = mini(over, maxi(trail.segment_count() - 1, 0))
		if drop <= 0:
			continue
		trail.points = trail.points.slice(drop)
		trail.birth_times = trail.birth_times.slice(drop)
		over -= drop


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	var wrote_any := false
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for trail in _trails.values():
		if _write_trail(trail, eye):
			wrote_any = true
	_mesh.surface_end()
	# An empty surface is still a surface; drop it rather than submit nothing.
	if not wrote_any:
		_mesh.clear_surfaces()


func _write_trail(trail, eye: Vector3) -> bool:
	var segments: int = trail.segment_count()
	if segments <= 0:
		return false
	var wrote := false
	for index in range(segments):
		var near_point: Vector3 = trail.point_at(index)
		var far_point: Vector3 = trail.point_at(index + 1)
		var direction := far_point - near_point
		var near_age: float = trail.age_at(index, _now)
		var far_age: float = trail.age_at(index + 1, _now)
		var near_side := strip_side(
			direction, eye - near_point, TRAIL_BUFFER.width_for_age(near_age) * 0.5
		)
		var far_side := strip_side(
			direction, eye - far_point, TRAIL_BUFFER.width_for_age(far_age) * 0.5
		)
		if near_side.is_zero_approx() and far_side.is_zero_approx():
			continue
		var near_colour := smoke_colour
		near_colour.a = TRAIL_BUFFER.alpha_for_age(near_age)
		var far_colour := smoke_colour
		far_colour.a = TRAIL_BUFFER.alpha_for_age(far_age)
		_quad(near_point, far_point, near_side, far_side, near_colour, far_colour)
		wrote = true
	return wrote


func _quad(
	near_point: Vector3,
	far_point: Vector3,
	near_side: Vector3,
	far_side: Vector3,
	near_colour: Color,
	far_colour: Color
) -> void:
	var a := near_point - near_side
	var b := near_point + near_side
	var c := far_point + far_side
	var d := far_point - far_side
	_mesh.surface_set_color(near_colour)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(near_colour)
	_mesh.surface_add_vertex(b)
	_mesh.surface_set_color(far_colour)
	_mesh.surface_add_vertex(c)

	_mesh.surface_set_color(near_colour)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(far_colour)
	_mesh.surface_add_vertex(c)
	_mesh.surface_set_color(far_colour)
	_mesh.surface_add_vertex(d)


## Half-width perpendicular to both the segment and the view direction, so the
## ribbon always turns its face to the camera. Returns zero for a degenerate
## segment or one seen exactly end-on, where the cross product collapses and the
## quad would be zero-area or NaN.
static func strip_side(segment: Vector3, to_eye: Vector3, half_width: float) -> Vector3:
	if segment.is_zero_approx() or to_eye.is_zero_approx():
		return Vector3.ZERO
	var side := segment.normalized().cross(to_eye.normalized())
	if side.length_squared() < 0.000001:
		return Vector3.ZERO
	return side.normalized() * half_width
