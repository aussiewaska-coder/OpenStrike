extends SceneTree
## The situation layer: owners come from the authored opening, the front is
## derived from the edges the regions agree they share, and moving a district has
## to move the line rather than leave it drawn where it used to be.

const WAR_REGIONS := preload("res://scripts/war/war_regions.gd")
const WAR_CONTROL := preload("res://scripts/war/war_control.gd")
const CORRIDOR := {
	"id": "au_gold_coast_tweed_corridor",
	"center_latitude": -28.08,
	"center_longitude": 153.365,
	"world_size_m": 50000.0,
}

var _regions := WAR_REGIONS.new()
var _control := WAR_CONTROL.new()
var _signals := []


func _init() -> void:
	assert(_regions.load_theatre(CORRIDOR), "the test needs a loaded theatre")
	_control.setup(_regions)
	_control.changed.connect(func(id: String) -> void: _signals.append(id))
	_check_seeded()
	_check_states()
	_check_front()
	_check_moved()
	print("WAR_CONTROL_TEST_PASS")
	quit()


## The opening situation is the one the geography was authored with, and both
## sides hold ground.
func _check_seeded() -> void:
	assert(_control.owner_of("coolangatta") == WAR_CONTROL.FRIENDLY,
		"the airfield must start friendly")
	assert(_control.owner_of("tweed_heads") == WAR_CONTROL.ENEMY,
		"and Tweed Heads must start enemy, or there is no front to draw")
	assert(_control.owner_of("nobody") == WAR_CONTROL.NEUTRAL,
		"a region that does not exist holds nothing")
	assert(_control.held_by(WAR_CONTROL.FRIENDLY) >= 8, "the blue side must hold the south coast")
	assert(_control.held_by(WAR_CONTROL.ENEMY) >= 6, "and the red side must have crossed the border")
	assert(_control.held_by(WAR_CONTROL.CONTESTED) >= 4,
		"and a belt between them must be contested, got %d" % _control.held_by(WAR_CONTROL.CONTESTED))
	assert(_control.ids().size() == _regions.regions().size(), "every region must be seated")


## The staff fields the brief lists, and none of them invented per frame.
func _check_states() -> void:
	for id in _control.ids():
		var state: Dictionary = _control.state_of(id)
		for field in ["id", "owner", "air_control", "ground_control", "supply",
				"infrastructure", "intel_level"]:
			assert(state.has(field), "%s state must carry %s" % [id, field])
		for field in ["air_control", "ground_control", "supply", "infrastructure", "intel_level"]:
			var value := float(state[field])
			assert(value >= 0.0 and value <= 1.0, "%s %s must be a ratio, got %f" % [id, field, value])
		assert(String(state["owner"]) == _control.owner_of(id),
			"%s state and owner table must agree" % id)
	var contested: Dictionary = _control.state_of("guelph")
	assert(_control.owner_of("guelph") == WAR_CONTROL.CONTESTED, "the valley must start mixed")
	assert(float(contested["ground_control"]) > 0.15 and float(contested["ground_control"]) < 0.85,
		"a contested district must be neither held nor lost, got %f" % float(contested["ground_control"]))


## Where the line is, and that it is made of the regions' own shared edges.
func _check_front() -> void:
	var segments := _control.front()
	assert(not segments.is_empty(), "the two sides must meet somewhere")
	var fronts := 0
	var contacts := 0
	for segment in segments:
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		assert(a.distance_to(b) > 100.0, "a front segment must be a real length")
		assert(not (segment["pressure"] as Vector2).is_zero_approx(),
			"and must point somewhere")
		assert(String(segment["from"]) != String(segment["to"]), "a front needs two sides")
		assert(String(segment["kind"]) in ["FRONT", "CONTACT"], "only two kinds of edge")
		if String(segment["kind"]) == "FRONT":
			fronts += 1
		else:
			contacts += 1
		var ours := _control.owner_of(String(segment["from"]))
		var theirs := _control.owner_of(String(segment["to"]))
		if String(segment["kind"]) == "FRONT":
			assert([ours, theirs].count(WAR_CONTROL.FRIENDLY) == 1
					and [ours, theirs].count(WAR_CONTROL.ENEMY) == 1,
				"a front edge must be blue against red, got %s/%s" % [ours, theirs])
		else:
			assert([ours, theirs].count(WAR_CONTROL.CONTESTED) == 1,
				"a contact edge must run along contested ground, got %s/%s" % [ours, theirs])
	assert(fronts > 0 and contacts > 0,
		"the map needs both a line of contact and contested flanks, got %d and %d" % [fronts, contacts])
	assert(_control.front().size() == segments.size(), "an unchanged situation must not re-derive")


## The acceptance test for the whole module: the line has to follow the ground.
func _check_moved() -> void:
	var before := _edge_set(_control.front())
	assert(before.has("coolangatta/tweed_heads"),
		"the airfield must start on the line, got %s" % [str(before.keys())])
	assert(not _control.set_owner("tweed_heads", WAR_CONTROL.ENEMY),
		"and taking a district from the side that already holds it must report no change")
	_signals = []
	assert(_control.set_owner("tweed_heads", WAR_CONTROL.FRIENDLY),
		"taking the town across must be a change")
	assert(_signals == ["tweed_heads"],
		"and must announce exactly the district that moved, got %s" % [str(_signals)])
	var after := _edge_set(_control.front())
	assert(not after.has("coolangatta/tweed_heads"),
		"the edge the blue side just took off red cannot still be the line")
	assert(after.has("tweed_heads/kingscliff"),
		"and the line must reappear where the town still faces red, got %s" % [str(after.keys())])
	assert(_control.set_owner("tweed_heads", WAR_CONTROL.ENEMY), "restore the opening situation")
	assert(_edge_set(_control.front()) == before,
		"and the derived front must come back exactly as it was")


func _edge_set(segments: Array) -> Dictionary:
	var set := {}
	for segment in segments:
		set["%s/%s" % [segment["from"], segment["to"]]] = true
	return set
