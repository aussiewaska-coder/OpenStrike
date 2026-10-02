extends RefCounted

## The battle map's camera: where it looks, how far in, which way is up and how
## far it leans toward the horizon. Owns that state and the smoothing on it, and
## nothing else -- no contacts, no controls, no drawing.
##
## The projection is a pinhole camera over the ground plane, worked in "map
## space": metres measured right and down the screen, before the bearing
## rotation. Tilt is the only thing that makes it perspective -- at tilt 0 the
## depth term is constant, so the result is algebraically identical to a flat
## map and nothing that was measured on the old one moves.

const MIN_RANGE := 500.0
const MAX_RANGE := 80000.0
## 60 degrees. Past that the ground crowds onto the horizon and stops reading as
## a map, so the camera never inverts.
const TILT_MAX := PI / 3.0
## tan(fov_y / 2). A long focal on purpose: a wide angle bends the near ground
## away from under the player's own symbol, which reads as distortion.
const PERSPECTIVE := 0.268
const GLIDE_RATE := 6.5
const GLIDE_STOP_PIXELS := 1.5
const GLIDE_STOP_RADIANS := 0.004
const FOCUS_MIN_SECONDS := 0.4
const FOCUS_MAX_SECONDS := 1.0

## Scale is set by the shorter axis, so a portrait phone sees the same kilometres
## as the landscape it was tuned on.
var viewport_size := Vector2(1000.0, 700.0)
var centre := Vector2.ZERO
var range_m := 10000.0
var bearing := 0.0
var tilt := 0.0
var follow_player := true
var _drift := Vector2.ZERO
var _spin := 0.0
var _lean := 0.0
var _glide := {}
var _glide_elapsed := 0.0
var _glide_seconds := 0.0


func span_pixels() -> float:
	return maxf(minf(viewport_size.x, viewport_size.y), 1.0)


func pixels_per_metre() -> float:
	return span_pixels() / (range_m * 2.0)


func focal_pixels() -> float:
	return span_pixels() * 0.5 / PERSPECTIVE


## Distance from the camera to the point the map is centred on.
func view_distance() -> float:
	return range_m / PERSPECTIVE


func set_viewport_size(size: Vector2) -> void:
	viewport_size = Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))


func world_to_map(offset: Vector2) -> Vector2:
	var cosine := cos(bearing)
	var sine := sin(bearing)
	return Vector2(offset.x * cosine + offset.y * sine, -offset.x * sine + offset.y * cosine)


func map_to_world(offset: Vector2) -> Vector2:
	var cosine := cos(bearing)
	var sine := sin(bearing)
	return Vector2(offset.x * cosine - offset.y * sine, offset.x * sine + offset.y * cosine)


func metres_at(world: Vector2) -> Vector2:
	return world_to_map(world - centre)


## Pixels per ground metre at one point. It grows with distance, which is what
## compresses the far terrain once the map is tilted.
func pixels_per_metre_at(world: Vector2) -> float:
	var depth := view_distance() - metres_at(world).y * sin(tilt)
	if depth <= 0.0:
		return 0.0
	return focal_pixels() / depth


## Screen position of a ground point, or an infinite value when the point has
## passed the horizon and there is no screen position for it.
func project(world: Vector2) -> Vector2:
	var map := metres_at(world)
	var depth := view_distance() - map.y * sin(tilt)
	if depth <= 0.0:
		return Vector2.INF
	var scale := focal_pixels() / depth
	return viewport_size * 0.5 + Vector2(map.x, map.y * cos(tilt)) * scale


func unproject(point: Vector2) -> Vector2:
	return centre + map_to_world(map_offset_at_screen(point))


## The map-space offset a screen point looks at. Independent of the centre: the
## camera only ever slides along the ground, so depth is a function of tilt.
func map_offset_at_screen(point: Vector2) -> Vector2:
	var along := (point - viewport_size * 0.5) / focal_pixels()
	var cosine := cos(tilt)
	var sine := sin(tilt)
	var denominator := cosine + along.y * sine
	if denominator <= 0.0:
		return Vector2.INF
	var down := along.y * view_distance() / denominator
	return Vector2(along.x * (view_distance() - down * sine), down)


## Puts a ground point under a screen point. Every drag and pinch is this, which
## is what keeps the terrain a finger grabbed under that finger.
func pin_world(world: Vector2, point: Vector2) -> void:
	var map := map_offset_at_screen(point)
	if not map.is_finite():
		return
	centre = world - map_to_world(map)


func tick(delta: float) -> bool:
	if delta <= 0.0:
		return false
	if not _glide.is_empty():
		_glide_elapsed += delta
		var progress := clampf(_glide_elapsed / maxf(_glide_seconds, 0.001), 0.0, 1.0)
		var eased := progress * progress * (3.0 - 2.0 * progress)
		centre = (_glide["from_centre"] as Vector2).lerp(_glide["to_centre"], eased)
		range_m = exp(lerpf(log(_glide["from_range"]), log(_glide["to_range"]), eased))
		bearing = _glide["from_bearing"] + _shortest_arc(_glide["from_bearing"], _glide["to_bearing"]) * eased
		tilt = lerpf(_glide["from_tilt"], _glide["to_tilt"], eased)
		if progress >= 1.0:
			_glide.clear()
		_clamp_state()
		return true
	var decay := exp(-GLIDE_RATE * delta)
	var moved := false
	if _drift.length() * pixels_per_metre() > GLIDE_STOP_PIXELS:
		centre -= map_to_world(_drift * delta)
		_drift *= decay
		moved = true
	else:
		_drift = Vector2.ZERO
	if absf(_spin) > GLIDE_STOP_RADIANS:
		bearing += _spin * delta
		_spin *= decay
		moved = true
	else:
		_spin = 0.0
	if absf(_lean) > GLIDE_STOP_RADIANS:
		tilt += _lean * delta
		_lean *= decay
		moved = true
	else:
		_lean = 0.0
	_clamp_state()
	return moved


func settle() -> void:
	_drift = Vector2.ZERO
	_spin = 0.0
	_lean = 0.0
	_glide.clear()


func is_gliding() -> bool:
	return not _glide.is_empty()


## Move the viewpoint, not the ground: pushing right looks east and new terrain
## arrives from the right edge. A drag is the opposite contract and uses drag().
func pan_pixels(offset: Vector2) -> void:
	settle()
	centre += map_to_world(offset / pixels_per_metre())


## A drag. `grab` is the ground point under the finger and `point` where the
## finger is now, so the map never slides out from under the touch.
func drag(grab: Vector2, point: Vector2) -> void:
	pin_world(grab, point)


func scale_zoom(factor: float, anchor := Vector2(-1, -1)) -> void:
	set_range(range_m / factor, anchor)


## Anchored zoom. `anchor` is the screen point whose ground location must
## survive the change; by default the middle of the view stays still.
func set_range(metres: float, anchor := Vector2(-1, -1)) -> void:
	settle()
	var at := viewport_size * 0.5 if anchor.x < 0.0 or anchor.y < 0.0 else anchor
	var held := unproject(at)
	range_m = clampf(metres, MIN_RANGE, MAX_RANGE)
	centre += held - unproject(at)
	_clamp_state()


func rotate_by(radians: float) -> void:
	settle()
	bearing += radians
	_clamp_state()


func tilt_by(radians: float) -> void:
	settle()
	tilt = clampf(tilt + radians, 0.0, TILT_MAX)


## A fling: screen pixels/second for the pan, radians/second for the rest. The
## glide above carries the map to rest from here.
func fling(pan_velocity: Vector2, spin: float, lean: float) -> void:
	_drift = pan_velocity / pixels_per_metre()
	_spin = spin
	_lean = lean


func begin_glide(parameters: Dictionary, seconds := -1.0) -> void:
	var to_centre: Vector2 = parameters.get("centre", centre)
	var to_range: float = clampf(parameters.get("range", range_m), MIN_RANGE, MAX_RANGE)
	var to_tilt: float = clampf(parameters.get("tilt", tilt), 0.0, TILT_MAX)
	var screens := to_centre.distance_to(centre) / maxf(range_m * 2.0, 1.0)
	var zooms := absf(log(maxf(to_range, 1.0) / maxf(range_m, 1.0)))
	if seconds < 0.0:
		seconds = clampf(FOCUS_MIN_SECONDS + screens * 0.35 + zooms * 0.2, FOCUS_MIN_SECONDS, FOCUS_MAX_SECONDS)
	_glide = {
		"from_centre": centre, "to_centre": to_centre,
		"from_range": range_m, "to_range": to_range,
		"from_bearing": bearing, "to_bearing": parameters.get("bearing", bearing),
		"from_tilt": tilt, "to_tilt": to_tilt,
	}
	_glide_elapsed = 0.0
	_glide_seconds = seconds
	_drift = Vector2.ZERO
	_spin = 0.0
	_lean = 0.0


func focus_world(world: Vector2, metres := -1.0, to_bearing := NAN, to_tilt := NAN, seconds := -1.0) -> void:
	follow_player = false
	var parameters := {"centre": world}
	if metres > 0.0:
		parameters["range"] = metres
	if not is_nan(to_bearing):
		parameters["bearing"] = to_bearing
	if not is_nan(to_tilt):
		parameters["tilt"] = to_tilt
	begin_glide(parameters, seconds)


func level_out() -> void:
	begin_glide({"bearing": 0.0, "tilt": 0.0})


func set_bearing(radians: float) -> void:
	settle()
	bearing = radians
	_clamp_state()


func _clamp_state() -> void:
	range_m = clampf(range_m, MIN_RANGE, MAX_RANGE)
	tilt = clampf(tilt, 0.0, TILT_MAX)
	bearing = fposmod(bearing, TAU)


static func _shortest_arc(from: float, to: float) -> float:
	return fposmod(to - from + PI, TAU) - PI
