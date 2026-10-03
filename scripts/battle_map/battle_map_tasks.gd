extends RefCounted

## The staff's board, on the ground.
##
## §19 is explicit that this is not a mission list: a job is offered where the thing it is
## about stands, so the mark goes on the objective and the card opens under a tap on it. The
## table itself lives in `mission_director.gd`, which decides what is worth flying at; this
## only projects what it decided, exactly the way `battle_map_strategy.gd` projects the
## registry's objects and never repeats a fact about them.
##
## A mission's position is the module's own answer, not a guess made here: an objective that
## exists in the registry is drawn at the ground it stands on, and an area job is drawn at the
## middle of the district it was offered over. So a mark cannot drift away from the thing it
## names, and a job whose objective has been destroyed leaves with it rather than staying as a
## suggestion.
##
## The four corner ticks are the shape of a request: they bracket something rather than
## symbolise it, because a track, a site and an airfield already have symbols on this map and a
## mission is a note about one of them. What a job is doing is told by the ticks closing in --
## offered, taken, flown, and settled -- and by the colour, with the callsign and the kind
## printed beside it since nobody can tell a SEAD from an interdiction by a diamond.

const MISSIONS := preload("res://scripts/war/mission_director.gd")
const LEVELS := preload("res://scripts/battle_map/battle_map_layers.gd")

const OFFER := Color(1.0, 0.78, 0.32)
const OURS := Color(0.38, 0.92, 1.0)
const FLOWN := Color(0.40, 0.91, 0.73)
const SETTLED := Color(0.62, 0.72, 0.78)
const BACKING := Color(0.015, 0.025, 0.03, 0.8)
const LINE := 1.5
## A tap on a job is a decision, not a survey, so the mark is forgiven a wider finger than a
## symbol: the bracket is bigger on screen than the point it is drawn at.
const PICK_PIXELS := 30.0
## Same band as the object glyphs and the front chevrons, so a mission mark sits in the war's
## own size range rather than in a size of its own.
const GLYPH_PIXELS_PER_METRE := 260.0
const GLYPH_MIN := 6.0
const GLYPH_MAX := 13.0

var _source: RefCounted
var _ready := false


## Take the staff's table, or clear it for a theatre with no war being run. Readiness is the
## table's own answer rather than the board's: a staff that has been seated but has not yet had
## a tick to raise a job has a layer with nothing on it, which is not the same thing as a layer
## with nothing behind it.
func load(tasks: RefCounted) -> void:
	_ready = tasks != null and tasks.has_method("board") \
		and tasks.has_method("position_of") and tasks.is_ready()
	_source = tasks if _ready else null


func clear() -> void:
	_source = null
	_ready = false


func is_ready() -> bool:
	return _ready


## The live record for a selected job, so a card opened on an offer reads what the board says
## now rather than what it said when the finger came down -- the offer may since have been
## taken, flown, or settled by somebody else.
func of(id: String) -> Dictionary:
	return _source.mission(id) if _ready else {}


func count() -> int:
	return _source.board().size() if _ready else 0


## Where a job's mark stands, from the table that raised it.
func position_of(id: String) -> Vector2:
	return _source.position_of(id) if _ready else Vector2.INF


## The entity the flying world answers to for this job's objective, or -1 for a tasking over
## ground rather than a point on it. The card needs it to hand the weapon the same lock the
## visor would have given, and `select_at` needs it to know when a bracket and a track under
## one finger are the same thing.
func entity_of(id: String) -> int:
	return _source.primary_entity(id) if _ready else -1


## Draw-ready marks, culled to the ground the map can see. `project` maps world metres to
## screen pixels, `pixels` is the map's scale and `level` decides how much of the label is
## printed.
func batch(project: Callable, view: Rect2, alpha: float, level: int, pixels: float) -> Array:
	var items := []
	if not _ready or alpha <= 0.01 or not view.has_area():
		return items
	var reach := clampf(pixels * GLYPH_PIXELS_PER_METRE, GLYPH_MIN, GLYPH_MAX)
	for record in _source.missions():
		var mission: Dictionary = record
		var status := String(mission["status"])
		# A job that has been settled stays on the map for the few ticks the staff keeps it, so
		# that the card the pilot opened can be seen to have been answered.
		var quiet := status in MISSIONS.CLOSED
		var at: Vector2 = _source.position_of(String(mission["id"]))
		if not at.is_finite() or not _meets(at, view):
			continue
		var projected: Vector2 = project.call(at)
		if not projected.is_finite():
			continue
		items.append({
			"id": String(mission["id"]),
			"at": projected,
			"reach": reach,
			"paths": _bracket(projected, reach, status),
			"colour": Color(_tint(status), alpha * (0.45 if quiet else 1.0)),
			"backing": Color(BACKING.r, BACKING.g, BACKING.b, 0.8 * alpha),
			"width": LINE,
			"label": _label(mission, level),
		})
	return items


## The job under a screen point, nearest first. Closed jobs answer too, because the map has
## only just drawn them and the pilot tapping at that spot is asking about the same fact.
func pick(at: Vector2, project: Callable) -> Dictionary:
	if not _ready:
		return {}
	var best := {}
	var closest := PICK_PIXELS
	for record in _source.missions():
		var mission: Dictionary = record
		var world: Vector2 = _source.position_of(String(mission["id"]))
		if not world.is_finite():
			continue
		var separation: float = project.call(world).distance_to(at)
		if separation > closest:
			continue
		if not best.is_empty() and separation > closest - 1.0 \
				and int(mission["priority"]) <= int(best["priority"]):
			continue
		closest = separation
		best = mission
	return best


## Corner ticks with the middle filled in once the job is ours, and closed in tight once it is
## being flown: the mark gets busier as the decision gets more expensive to leave alone.
static func _bracket(at: Vector2, reach: float, status: String) -> Array:
	var arm := reach * (0.62 if status == MISSIONS.ACTIVE else 1.0)
	var corner := reach * 0.42
	var paths := []
	for sign in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var here := at + (sign as Vector2) * arm
		paths.append(PackedVector2Array([
			here + Vector2(-(sign as Vector2).x * corner, 0),
			here,
			here + Vector2(0, -(sign as Vector2).y * corner),
		]))
	if status in [MISSIONS.ASSIGNED, MISSIONS.ACTIVE]:
		# A diamond rather than a disc: the filled shape is a tasking, and the map already uses
		# discs for nothing. Closed on itself, because the canvas strokes these as polylines.
		paths.append(PackedVector2Array([
			at + Vector2(0, -reach * 0.4), at + Vector2(reach * 0.4, 0),
			at + Vector2(0, reach * 0.4), at - Vector2(reach * 0.4, 0),
			at + Vector2(0, -reach * 0.4),
		]))
	return paths


static func _tint(status: String) -> Color:
	match status:
		MISSIONS.ASSIGNED:
			return OURS
		MISSIONS.ACTIVE:
			return FLOWN
		MISSIONS.SUCCESS:
			return FLOWN
		MISSIONS.PARTIAL, MISSIONS.FAILED, MISSIONS.EXPIRED:
			return SETTLED
	return OFFER


## The call sign and the job, and the priority at the densities where a pilot is choosing
## between offers rather than confirming where they are.
static func _label(mission: Dictionary, level: int) -> String:
	var text := "%s %s" % [
		String(mission["callsign"]), String(mission["type"])]
	if level == LEVELS.Level.THEATRE:
		return text
	return "%s · P%d" % [text, int(mission["priority"])]


## A mark is a point, so the visible box is grown by more than a glyph before the test, for the
## same reason the object symbols are: ground just over the horizon can still project on screen.
static func _meets(at: Vector2, view: Rect2) -> bool:
	var grown := view.grow(6000.0)
	return grown.has_point(at)
