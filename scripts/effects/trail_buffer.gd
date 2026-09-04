extends RefCounted

## One trail's worth of breadcrumbs, and the curves that turn their age into a
## width and an alpha. No mesh, no node, no camera -- all of that belongs to
## trail_renderer.gd, and none of it is where the bugs are.
##
## Breadcrumbs are laid by DISTANCE TRAVELLED, never once per frame. Per-frame
## laying makes trail density a function of framerate: a phone that hitches
## draws a gap-toothed trail, and one running fast wastes vertices on a dense
## stub. Distance spacing gives the same smoke either way.

## Breadcrumb spacing. Smaller is smoother and costs vertices linearly.
const SEGMENT_METRES := 2.5
## How long smoke lingers before it is gone.
const LIFETIME_SECONDS := 4.5
## Width at the nozzle, where the smoke has not spread yet.
const BIRTH_WIDTH := 0.6
## Width once fully billowed.
const MAX_WIDTH := 7.0

## Points and the times they were laid. Parallel packed arrays rather than an
## array of structs: this is rebuilt into a mesh every frame, and packed arrays
## keep that loop out of the allocator.
var points := PackedVector3Array()
var birth_times := PackedFloat32Array()
## False once the rocket that owned this is dead. The smoke it already laid
## keeps ageing -- a trail that vanished with its rocket would be worse than no
## trail at all.
var emitting := true

var _last_point := Vector3.ZERO
var _has_last := false


## Lays a breadcrumb if the source has travelled far enough since the last one.
## Returns whether one was actually laid.
func push(point: Vector3, now: float) -> bool:
	if not emitting:
		return false
	if not _has_last:
		_has_last = true
		_last_point = point
		points.append(point)
		birth_times.append(now)
		return true
	if _last_point.distance_to(point) < SEGMENT_METRES:
		return false
	_last_point = point
	points.append(point)
	birth_times.append(now)
	return true


## Retires everything older than the lifetime. Breadcrumbs are laid in order, so
## the dead ones are always a prefix and this is a single slice.
func advance_age(now: float) -> void:
	var alive := 0
	while alive < birth_times.size() and now - birth_times[alive] > LIFETIME_SECONDS:
		alive += 1
	if alive == 0:
		return
	points = points.slice(alive)
	birth_times = birth_times.slice(alive)


func stop_emitting() -> void:
	emitting = false


## A trail is finished when it is no longer emitting and its last breadcrumb has
## aged out, at which point the renderer can reclaim the slot.
func is_finished(now: float) -> bool:
	if emitting:
		return false
	if birth_times.is_empty():
		return true
	return now - birth_times[birth_times.size() - 1] > LIFETIME_SECONDS


## Quads are drawn between consecutive breadcrumbs, so a lone point is no
## segments and two points are one.
func segment_count() -> int:
	return maxi(points.size() - 1, 0)


func point_at(index: int) -> Vector3:
	return points[index]


func age_at(index: int, now: float) -> float:
	return now - birth_times[index]


## Smoke billows fast at first and then settles, so the width curve is a square
## root rather than a line.
static func width_for_age(age: float) -> float:
	var fraction := clampf(age / LIFETIME_SECONDS, 0.0, 1.0)
	return lerpf(BIRTH_WIDTH, MAX_WIDTH, sqrt(fraction))


## Alpha holds up early -- fresh smoke is opaque -- then falls away. Squaring
## the remaining life keeps the trail solid behind the rocket and lets the far
## end dissolve instead of ending on a visible edge.
static func alpha_for_age(age: float) -> float:
	var remaining := clampf(1.0 - age / LIFETIME_SECONDS, 0.0, 1.0)
	return remaining * remaining
