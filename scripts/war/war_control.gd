extends RefCounted

## Who holds the theatre's regions, and where that puts the front.
##
## The geography is `war_regions.gd`'s; this is the situation laid over it. Phase
## 3 was asked for test ownership, so the numbers here are seeded from the
## opening situation each region is authored with rather than simulated -- they
## exist so the map has something honest to draw and so the WarDirector of Phase 5
## has an interface to take over rather than a rendering path to rewrite. It has
## taken over: `war_director.gd` computes the campaign and writes it back through
## `set_owner` and `set_measures`, and this module still owns the one thing nobody
## else should -- who a district belongs to, and the line derived from that.
##
## The front line is derived here, from the edges two opposing regions already
## agree they share. Nothing in the map draws a line by hand, which is what makes
## it move when territory changes instead of drifting out of date.

signal changed(id: String)

const FRIENDLY := "FRIENDLY"
const ENEMY := "ENEMY"
const CONTESTED := "CONTESTED"
const NEUTRAL := "NEUTRAL"
const OWNERS := [FRIENDLY, ENEMY, CONTESTED, NEUTRAL]

## The mock situation each owner implies. `ground` and `air` are the fraction of
## the district held, so a contested region is genuinely mixed rather than a
## third colour, and the rest are the staff quantities the brief lists.
const SEED := {
	FRIENDLY: {"ground": 0.85, "air": 0.9, "supply": 0.8, "infrastructure": 0.75, "intel": 0.6},
	ENEMY: {"ground": 0.12, "air": 0.08, "supply": 0.35, "infrastructure": 0.4, "intel": 0.2},
	CONTESTED: {"ground": 0.45, "air": 0.5, "supply": 0.4, "infrastructure": 0.35, "intel": 0.4},
	NEUTRAL: {"ground": 0.5, "air": 0.25, "supply": 0.5, "infrastructure": 0.1, "intel": 0.1},
}

## The two owners that fight. Contested ground is neither: it is where they meet.
const BLOCS := [FRIENDLY, ENEMY]

## The measured fields of a RegionState. `owner` and `id` are not in it: who holds a
## district is `set_owner`'s decision, and letting a measure set rewrite it would put
## two writers on the one field the front line is derived from.
const MEASURES := [
	"air_control", "ground_control", "supply", "infrastructure", "intel_level",
]

var _regions: RefCounted
var _owners := {}
var _states := {}
var _front := []
var _front_stale := true


## Take the geography, and the opening situation authored into it.
func setup(regions: RefCounted) -> void:
	_regions = regions
	_owners = {}
	_states = {}
	for region in regions.regions():
		_seed(String(region["id"]), String(region["owner"]), float(region["value"]))
	_front_stale = true


func owner_of(id: String) -> String:
	return String(_owners.get(id, NEUTRAL))


## The RegionState the brief asks every region to carry.
func state_of(id: String) -> Dictionary:
	return _states.get(id, {})


func ids() -> Array:
	return _owners.keys()


func held_by(owner: String) -> int:
	var count := 0
	for id in _owners:
		if String(_owners[id]) == owner:
			count += 1
	return count


## Move a district. Returns false when nothing moved, so a caller cannot make the
## map blink over a report that changed nothing.
func set_owner(id: String, owner: String) -> bool:
	if not _owners.has(id) or owner == String(_owners.get(id, "")):
		return false
	if owner not in OWNERS:
		return false
	_seed(id, owner, float(_regions.region(id)["value"]))
	_front_stale = true
	changed.emit(id)
	return true


## Publish measured values for a district, from a layer that has actually computed
## them. `set_owner` seeds from the situation an owner *implies*, which is the right
## opening number and the wrong one once a war has been running for an hour; this is
## how the simulation writes its answers over the top without inventing a second
## place for the map to read from. Only the fields named are touched, and a report
## that changes nothing is reported as nothing so a caller cannot make the map blink.
func set_measures(id: String, measures: Dictionary) -> bool:
	if not _states.has(id):
		return false
	var state: Dictionary = _states[id]
	var moved := false
	for field in MEASURES:
		if not measures.has(field):
			continue
		var value := _ratio(float(measures[field]))
		if is_equal_approx(value, float(state[field])):
			continue
		state[field] = value
		moved = true
	# Which way the line is leaning is read out of ground control, so a district whose
	# ground battle has swung has to be re-derived even when nobody crossed it.
	if moved:
		_front_stale = true
	return moved


## Where the ground battle is: every edge two regions agree they share, between
## owners that are not on the same side. Each entry is the segment itself, its
## middle, and the direction the pressure runs, all in world metres.
func front() -> Array:
	if _regions == null:
		return []
	if not _front_stale:
		return _front
	_front = _derive_front(_regions)
	_front_stale = false
	return _front


func _seed(id: String, owner: String, value: float) -> void:
	var seed: Dictionary = SEED.get(owner, SEED[NEUTRAL])
	_owners[id] = owner
	# What a district is worth decides how hard it is held: the same owner in a
	# valley nobody drives through is not the owner at the airfield.
	var weight := clampf(value, 0.0, 1.0)
	_states[id] = {
		"id": id,
		"owner": owner,
		"air_control": _ratio(float(seed["air"]) * (0.75 + 0.25 * weight)),
		"ground_control": _ratio(float(seed["ground"]) * (0.75 + 0.25 * weight)),
		"supply": _ratio(float(seed["supply"])),
		"infrastructure": _ratio(float(seed["infrastructure"]) * (0.5 + weight)),
		"intel_level": _ratio(float(seed["intel"])),
	}


## Everything in this module that claims to measure something measures a ratio,
## so a seed that rounds past a whole district is still one whole district.
func _ratio(value: float) -> float:
	return clampf(value, 0.0, 1.0)


## Walks the shared edges once per pair. A FRIENDLY/ENEMY edge is the front; an
## edge with a contested district on exactly one side is where the fight is
## coming from, so the renderer can show a contested region as active ground
## rather than as a third colour. Two contested neighbours are the same mixed
## situation on both sides, and two districts of one bloc share a road, not a
## front -- neither draws a line.
func _derive_front(geography) -> Array:
	var segments := []
	var adjacency: Dictionary = geography.adjacency()
	for id in adjacency:
		var here := String(id)
		var ours := owner_of(here)
		if ours == NEUTRAL:
			continue
		for other in adjacency[id]:
			var there := String(other)
			if there <= here:
				continue
			var theirs := owner_of(there)
			if theirs == NEUTRAL or theirs == ours:
				continue
			if ours == CONTESTED and theirs == CONTESTED:
				continue
			var kind := "FRONT" if (ours in BLOCS and theirs in BLOCS) else "CONTACT"
			# Pressure runs downhill: from whichever side holds its district
			# harder toward the side that holds it less, which is the direction
			# the line moves if nobody interferes.
			var ours_strength := float(state_of(here)["ground_control"])
			var theirs_strength := float(state_of(there)["ground_control"])
			var strong := here if ours_strength >= theirs_strength else there
			var weak := there if strong == here else here
			var toward: Vector2 = (geography.region(weak)["centre"] as Vector2) \
				- (geography.region(strong)["centre"] as Vector2)
			for segment in (adjacency[id][other] as Array):
				var a: Vector2 = segment[0]
				var b: Vector2 = segment[1]
				var along := b - a
				var normal := Vector2(-along.y, along.x).normalized()
				if normal.dot(toward) < 0.0:
					normal = -normal
				segments.append({
					"a": a,
					"b": b,
					"middle": (a + b) * 0.5,
					"pressure": normal,
					"kind": kind,
					"from": strong,
					"to": weak,
					"length": along.length(),
				})
	return segments
