extends RefCounted

## Territory on the battle map: who holds what ground, and where that puts the
## line between them.
##
## This module decides nothing about the war -- `war_regions.gd` says where the
## districts are, `war_control.gd` says who holds them and derives the front --
## and it owns no camera: it is handed the map's projection, the same way the
## clustering is, so the overlays sit on the ground they describe at any tilt or
## bearing.
##
## The fills are deliberately thin. A control area that hides the satellite
## imagery under it is a choropleth, not a command map: what a pilot wants from
## the overlay is to know which side this terrain belongs to while still reading
## the terrain itself. So a held district is a wash you can see the coast
## through, a boundary is a stroke, and contested ground is both sides' claim
## laid across each other rather than a third colour invented for the occasion.

const BLUE := Color(0.32, 0.72, 0.95)
const RED := Color(0.93, 0.30, 0.24)
const QUIET := Color(0.62, 0.72, 0.78)
const LINE := Color(0.95, 0.93, 0.85)
const REGIONS := preload("res://scripts/war/war_regions.gd")
const CONTROL := preload("res://scripts/war/war_control.gd")

## The wash over a held district. A contested one gets less of it, because there
## the claim is the information rather than the control.
const WASH := 0.17
const CONTESTED_WASH := 0.07
const FRONT_WIDTH := 2.5
const EDGE_WIDTH := 1.0

## The two hatch families that make contested ground read as fought-over: two
## directions in world space, so the cross stays welded to the district as the
## map turns rather than sliding over it.
const HATCH_A := Vector2(0.94, 0.34)
const HATCH_B := Vector2(-0.34, 0.94)
## Rows per district, and dashes per row. Enough to see the pattern at theatre
## range, few enough that a phone is not stroking a net over half the screen.
const HATCH_ROWS := 5
const HATCH_DASHES := 7
const HATCH_FILL := 0.55


## Typed as the scripts themselves rather than RefCounted so the map can read a
## district's owner as the String it is; the panel hands these over as sources
## that may be null, which is what `load` checks for.
var _regions: REGIONS
var _control: CONTROL
var _shapes := []
var _ready := false


## Take the geography and the situation over it. Ownership is expected to change
## under an open map, and nothing here caches it: the frame after a district
## moves is drawn in its new colour, because the colour is looked up as it draws.
func load(regions: RefCounted, control: RefCounted) -> void:
	clear()
	if regions == null or control == null or not regions.is_loaded():
		return
	_regions = regions
	_control = control
	_build()
	_ready = not _shapes.is_empty()


func clear() -> void:
	_regions = null
	_control = null
	_shapes = []
	_ready = false


func is_ready() -> bool:
	return _ready


## The district under a world point, which is what lets the selection card say
## what country a target is standing in.
func region_at(point: Vector2) -> Dictionary:
	return _regions.region_at(point) if _ready else {}


## Who holds the district a point stands in, right now, or an empty string when the
## theatre has no regions or the point is outside them. The card asks this rather than
## reaching through the map into the control module: ownership is the one thing here
## that changes while the map is open.
func holder_at(point: Vector2) -> String:
	if not _ready:
		return ""
	var region: Dictionary = _regions.region_at(point)
	return String(_control.owner_of(String(region["id"]))) if not region.is_empty() else ""


## Draw-ready batches, culled to the ground the map can currently see.
## `project` maps world metres to screen pixels and `pixels` is the map's scale,
## which is what the chevrons are measured against.
func batch(project: Callable, view: Rect2, alpha: float, pixels: float) -> Dictionary:
	var fills := []
	var edges := []
	var marks := []
	if not _ready or alpha <= 0.01 or pixels <= 0.0 or not view.has_area():
		return {"fills": fills, "edges": edges, "front": marks}
	for shape in _shapes:
		if not _meets(shape["bounds"] as Rect2, view):
			continue
		var screen := _project(shape["polygon"] as PackedVector2Array, project)
		if screen.is_empty():
			continue
		var owner: String = _control.owner_of(String(shape["id"]))
		var colour := _colour(owner)
		var contested := owner == _control.CONTESTED
		fills.append({"path": screen, "colour": Color(colour, (CONTESTED_WASH if contested else WASH) * alpha)})
		edges.append({"path": screen, "colour": Color(colour, 0.55 * alpha), "width": EDGE_WIDTH})
		if contested:
			for dash in _hatch(shape, HATCH_A, project):
				edges.append({"path": dash, "colour": Color(BLUE, 0.5 * alpha), "width": 1.0})
			for dash in _hatch(shape, HATCH_B, project):
				edges.append({"path": dash, "colour": Color(RED, 0.5 * alpha), "width": 1.0})
	for segment in _control.front():
		var mark := _front_mark(segment, project, view, pixels, alpha)
		if not mark.is_empty():
			marks.append(mark)
	return {"fills": fills, "edges": edges, "front": marks}


## Outlines and bounding boxes, in world metres. None of it depends on the camera
## or on who holds what, so it is built once per theatre.
func _build() -> void:
	_shapes = []
	for region in _regions.regions():
		var polygon: PackedVector2Array = region["polygon"]
		if polygon.is_empty():
			continue
		var bounds := Rect2(polygon[0], Vector2.ZERO).grow(0.0)
		for point in polygon:
			# Grown by hand: an outline can run either way from its first corner,
			# and a box that starts as a point has no extent to expand into.
			bounds = bounds.expand(point)
		_shapes.append({
			"id": String(region["id"]),
			"name": String(region["name"]),
			"polygon": polygon,
			"bounds": bounds,
			"centre": region["centre"] as Vector2,
		})


func _colour(owner: String) -> Color:
	if owner == _control.FRIENDLY:
		return BLUE
	if owner == _control.ENEMY:
		return RED
	return QUIET


## A district counts as visible when its box touches the ground on screen, plus a
## margin: the map is perspective, so an outline can enter frame from beyond the
## edge its bounding box was tested against.
func _meets(bounds: Rect2, view: Rect2) -> bool:
	return bounds.intersects(Rect2(
		view.position - Vector2.ONE * 2000.0, view.size + Vector2.ONE * 4000.0))


## Projected outline, or empty when any corner looks past the horizon: a fill
## stretched across ground the camera cannot reach would smear the map.
func _project(polygon: PackedVector2Array, project: Callable) -> PackedVector2Array:
	var screen := PackedVector2Array()
	for point in polygon:
		var at: Vector2 = project.call(point)
		if not at.is_finite():
			return PackedVector2Array()
		screen.append(at)
	return screen


## Short strokes laid along `direction` across the district, kept inside it by the
## same crossing rule the geography uses, so a claim never spills out of the
## ground it is claimed over. The dashes are placed in world metres and projected
## one at a time, which is what makes them terrain furniture rather than a screen
## pattern: turning the map turns the hatch with it.
func _hatch(shape: Dictionary, direction: Vector2, project: Callable) -> Array:
	var dashes := []
	var polygon: PackedVector2Array = shape["polygon"]
	var centre: Vector2 = shape["centre"]
	var bounds: Rect2 = shape["bounds"]
	var across := Vector2(-direction.y, direction.x)
	var reach := maxf(bounds.size.length(), 1.0) * 0.5
	var step := maxf(bounds.size.length(), 1.0) / float(HATCH_ROWS + 1)
	for row in range(1, HATCH_ROWS + 1):
		# Each row runs along the district's own middle, offset sideways: starting
		# the walk from the centre means a narrow district loses its ends rather
		# than its middle, which is the part the eye reads as the pattern.
		var origin := centre + across * (float(row) - float(HATCH_ROWS + 1) * 0.5) * step
		var slot := 0
		for index in range(-HATCH_DASHES, HATCH_DASHES + 1):
			var at := origin + direction * (float(index) + 0.5) * step
			var end := at + direction * step * HATCH_FILL
			if at.distance_to(centre) > reach or not _inside(polygon, at) or not _inside(polygon, end):
				continue
			var a: Vector2 = project.call(at)
			var b: Vector2 = project.call(end)
			if not a.is_finite() or not b.is_finite() or a.distance_to(b) > 3000.0:
				continue
			dashes.append(PackedVector2Array([a, b]))
			slot += 1
	return dashes


func _inside(polygon: PackedVector2Array, point: Vector2) -> bool:
	var inside := false
	var count := polygon.size()
	for i in range(count):
		var a := polygon[i]
		var b := polygon[(i + 1) % count]
		if (a.y > point.y) != (b.y > point.y):
			if point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x:
				inside = not inside
	return inside


## The line itself, and which way it is being pushed. A blue-against-red edge is
## the front and gets a chevron; an edge against contested ground is where the
## fight is heading, so it is drawn faint and left unmarked -- the hatch on the
## far side already says the district is not settled.
func _front_mark(segment: Dictionary, project: Callable, view: Rect2, pixels: float, alpha: float) -> Dictionary:
	var middle: Vector2 = segment["middle"]
	if not _meets(Rect2(middle - Vector2.ONE * 100.0, Vector2.ONE * 200.0), view):
		return {}
	var a: Vector2 = project.call(segment["a"])
	var b: Vector2 = project.call(segment["b"])
	var at: Vector2 = project.call(middle)
	if not a.is_finite() or not b.is_finite() or not at.is_finite() or a.distance_to(b) < 1.0:
		return {}
	var front := String(segment["kind"]) == "FRONT"
	var mark := {
		"a": a,
		"b": b,
		"colour": Color(LINE, (0.85 if front else 0.4) * alpha),
		"width": FRONT_WIDTH if front else 1.0,
	}
	if not front:
		return mark
	# The pressure direction is a ground vector, so it is projected the same way
	# a point is: two places on the ground, and the screen tells us the angle.
	var toward: Vector2 = project.call(middle + (segment["pressure"] as Vector2) * 500.0)
	if not toward.is_finite() or at.distance_to(toward) < 0.5:
		return mark
	var reach := clampf(pixels * 300.0, 5.0, 13.0)
	mark["arrow"] = _chevron(at, (toward - at).normalized(), reach)
	mark["colour_arrow"] = Color(_colour(_control.owner_of(String(segment["to"]))), 0.9 * alpha)
	return mark


func _chevron(at: Vector2, direction: Vector2, reach: float) -> PackedVector2Array:
	var side := Vector2(-direction.y, direction.x)
	return PackedVector2Array([
		at + direction * reach,
		at - direction * reach * 0.5 + side * reach * 0.6,
		at - direction * reach * 0.5 - side * reach * 0.6,
	])
