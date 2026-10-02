extends RefCounted

## Strategic objects on the battle map: where the things the war is fought over
## actually stand, and what sort of thing each one is.
##
## Like the territory layer, this decides nothing. `war_objects.gd` says what the
## objects are and holds the live bindings that say what they are doing, and the map
## owns the camera and hands this the projection -- so a symbol sits on the ground it
## names at any tilt or bearing, and turning the map turns the runway with it instead
## of sliding a decal over the imagery.
##
## The symbols are line work, not art: a ring with its real pavement across it for an
## airfield, a nose-up triangle for a site, an arch for a structure. Three shapes a
## thumb can tell apart at a dozen pixels is the whole requirement, and the same blue
## and red the control areas are washed with is the same blue and red here, so a
## symbol and the ground under it cannot disagree about who holds what.
##
## What the density rule does for this layer is drop the names, not the objects: at
## theatre range the map is being read for the shape of the war, so only the things
## worth planning against are labelled. A site nothing has confirmed is drawn faint,
## because a position that has only ever been an estimate must not look as certain as
## one with something standing at it.

const OBJECTS := preload("res://scripts/war/war_objects.gd")
const LEVELS := preload("res://scripts/battle_map/battle_map_layers.gd")

const BLUE := Color(0.32, 0.72, 0.95)
const RED := Color(0.93, 0.30, 0.24)
const QUIET := Color(0.62, 0.72, 0.78)
const LINE := Color(0.95, 0.93, 0.85)

## How much a symbol nothing has confirmed is worth on screen. It is still drawn,
## because a site the authored layout puts there is a fact about the route even when
## no launcher has been seen at it -- it is just not allowed to look confirmed.
const UNCONFIRMED := 0.38
## The theatre is the map for the shape of the war, so a low-value object is not
## named there, and nothing below this value is drawn at all: hundreds of abstract
## entities have to stay usable, and the ones worth a symbol are the ones worth the
## planning.
const THEATRE_LABEL_VALUE := 0.6
const DRAWN_VALUE := 0.3
## A tap is generous on a phone and must still not grab a symbol off the ground it
## is standing on.
const PICK_PIXELS := 26.0
## The pavement is drawn in ground metres, so it needs a screen sanity check: a strip
## projected across the horizon lands in a pixel or leaves frame altogether.
const STRIP_MAX_PIXELS := 4000.0
const WIDTH := 1.5
const STRIP_WIDTH := 2.0
## The same measurement the front chevrons are sized by, so the war's marks and the
## war's symbols sit in one size band rather than two.
const GLYPH_PIXELS_PER_METRE := 300.0
const GLYPH_MIN := 5.0
const GLYPH_MAX := 11.0

var _source: OBJECTS
var _ready := false


## Take the registry. A null source, or a theatre with nothing in it, leaves the
## layer reporting itself empty, which is what the panel shows as · NONE rather than
## drawing a symbol table out of nothing.
func load(objects: RefCounted) -> void:
	clear()
	if objects == null or not objects.has_method("objects") or not objects.is_loaded():
		return
	_source = objects
	_ready = not _source.objects().is_empty()


func clear() -> void:
	_source = null
	_ready = false


func is_ready() -> bool:
	return _ready


## The live record behind an id. The card reads through this on its own timer, so a
## site that stops reporting between the tap and the next refresh is not shown as
## what it was when the finger came down.
func of(id: int) -> Dictionary:
	return _source.of(id) if _ready else {}


func count() -> int:
	return _source.count() if _ready else 0


## Draw-ready symbols, culled to the ground the map can currently see. `project` maps
## world metres to screen pixels and `pixels` is the map's scale.
func batch(project: Callable, view: Rect2, alpha: float, level: int, pixels: float) -> Array:
	var items := []
	if not _ready or alpha <= 0.01 or not view.has_area():
		return items
	var reach := clampf(pixels * GLYPH_PIXELS_PER_METRE, GLYPH_MIN, GLYPH_MAX)
	for record in _source.objects():
		var object: Dictionary = record
		if float(object["strategic_value"]) < DRAWN_VALUE or not _meets(object["world_position"], view):
			continue
		var at: Vector2 = project.call(object["world_position"])
		if not at.is_finite():
			continue
		var confirmed := bool(object["discovered"])
		var strength := alpha if confirmed else alpha * UNCONFIRMED
		var colour := _colour(String(object["faction"]))
		items.append({
			"id": int(object["id"]),
			"at": at,
			"reach": reach,
			"paths": _glyph(String(object["operational_state"]), object, at, reach),
			"strips": _pavement(object, project),
			"colour": Color(colour, strength),
			"backing": Color(0.015, 0.025, 0.03, 0.8 * strength),
			"width": WIDTH,
			"strip_colour": Color(LINE, 0.7 * strength),
			"strip_width": STRIP_WIDTH,
			"label": _label(object, level, confirmed),
			"sub": OBJECTS.type_name(object) if level == LEVELS.Level.TACTICAL else "",
		})
	return items


## The object under a screen point, or nothing. Nearest wins; two symbols stacked
## inside a pixel are settled by which of them the staff value says is worth flying
## for. A position nothing has confirmed is still selectable, because the card is
## exactly where "we have not seen one there" belongs.
func pick(at: Vector2, project: Callable) -> Dictionary:
	if not _ready:
		return {}
	var best := {}
	var closest := PICK_PIXELS
	for record in _source.objects():
		var object: Dictionary = record
		var projected: Vector2 = project.call(object["world_position"])
		if not projected.is_finite():
			continue
		var separation := projected.distance_to(at)
		if separation > closest:
			continue
		if not best.is_empty() and separation > closest - 1.0 \
				and float(object["strategic_value"]) <= float(best["strategic_value"]):
			continue
		closest = separation
		best = object
	return best


## The glyph as polylines in screen space, kept upright whatever the map is doing:
## a symbol is a report about the ground, not a mark painted on it. A site that has
## never been confirmed gets a plain circle instead of its triangle, so the difference
## is in the shape and not only in the alpha.
static func _glyph(state: String, object: Dictionary, at: Vector2, reach: float) -> Array:
	var type := int(object["type"])
	if state == OBJECTS.UNCONFIRMED:
		return [PackedVector2Array([
			at + Vector2(-reach * 0.7, 0), at + Vector2(reach * 0.7, 0),
		]), PackedVector2Array([
			at + Vector2(0, -reach * 0.7), at + Vector2(0, reach * 0.7),
		])]
	var glyph := _shape(int(object["type"]), at, reach)
	# A thing the world has stopped reporting is still on the map where it was, and
	# struck through so it cannot be mistaken for one that is still standing there.
	if state == OBJECTS.DESTROYED:
		glyph.append(PackedVector2Array([
			at + Vector2(-reach, -reach), at + Vector2(reach, reach),
		]))
		glyph.append(PackedVector2Array([
			at + Vector2(-reach, reach), at + Vector2(reach, -reach),
		]))
	return glyph


static func _shape(type: int, at: Vector2, reach: float) -> Array:
	if type == OBJECTS.Type.AIRBASE:
		return [_ring(at, reach)]
	if type == OBJECTS.Type.SAM_SITE:
		var apex := at + Vector2(0, -reach)
		var left := at + Vector2(-reach * 0.92, reach * 0.66)
		var right := at + Vector2(reach * 0.92, reach * 0.66)
		return [
			PackedVector2Array([apex, left, right, apex]),
			PackedVector2Array([at + Vector2(0, reach * 0.3), at + Vector2(0, -reach * 0.25)]),
		]
	if type == OBJECTS.Type.INFRASTRUCTURE:
		var arch := PackedVector2Array()
		for step in range(9):
			var angle := PI * float(step) / 8.0
			arch.append(at + Vector2(cos(angle), -sin(angle)) * reach)
		return [
			arch,
			PackedVector2Array([at + Vector2(-reach, 0), at + Vector2(-reach, reach * 0.7)]),
			PackedVector2Array([at + Vector2(reach, 0), at + Vector2(reach, reach * 0.7)]),
		]
	return [PackedVector2Array([
		at + Vector2(-reach, -reach), at + Vector2(reach, -reach),
		at + Vector2(reach, reach), at + Vector2(-reach, reach),
		at + Vector2(-reach, -reach),
	])]


## A circle as a polyline, so an airfield's ring is line work like everything else on
## this map rather than a filled disc sitting over the imagery.
static func _ring(at: Vector2, reach: float) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for step in range(13):
		var angle := TAU * float(step) / 12.0
		ring.append(at + Vector2(sin(angle), -cos(angle)) * reach)
	return ring


## The runways themselves, in world metres, projected like any other ground line. An
## airfield symbol with its real pavement through it is the one thing on this map that
## says how long the strip actually is.
func _pavement(object: Dictionary, project: Callable) -> Array:
	var strips := []
	if int(object["type"]) != OBJECTS.Type.AIRBASE:
		return strips
	for entry in (object["detail"]["strips"] as Array):
		var strip: Dictionary = entry
		var a: Vector2 = project.call(strip["a"])
		var b: Vector2 = project.call(strip["b"])
		if not a.is_finite() or not b.is_finite() or a.distance_to(b) > STRIP_MAX_PIXELS:
			continue
		strips.append([a, b])
	return strips


static func _colour(faction: String) -> Color:
	if faction == OBJECTS.ENEMY:
		return RED
	if faction == OBJECTS.FRIENDLY:
		return BLUE
	return QUIET


static func _label(object: Dictionary, level: int, confirmed: bool) -> String:
	if level == LEVELS.Level.THEATRE and (not confirmed or float(object["strategic_value"]) < THEATRE_LABEL_VALUE):
		return ""
	return String(object["name"])


## A symbol belongs to a point rather than an area, so the view is grown by more than
## a glyph before the test: the ground the camera can see is measured at the horizon,
## and a symbol just off the edge of that box can still be on screen.
func _meets(at: Vector2, view: Rect2) -> bool:
	return Rect2(
		view.position - Vector2.ONE * 2000.0,
		view.size + Vector2.ONE * 4000.0).has_point(at)
