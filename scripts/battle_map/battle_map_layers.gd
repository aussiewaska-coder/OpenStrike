extends RefCounted

## The semantic zoom state: which of the three information densities the map is
## showing, which layers that implies, and the fade between them.
##
## Zooming is supposed to change what is *useful* rather than how big the icons
## are, so a level is a decision about information, not a scale. The thresholds
## carry hysteresis: a pinch held on a boundary must not make the map flicker
## between two different sets of content, which is also why the levels are named
## for what they are for -- a theatre view, a regional view, a tactical view.

enum Level {THEATRE, REGIONAL, TACTICAL}

## Half-range in metres. THEATRE above REGIONAL_EXIT, REGIONAL in between,
## TACTICAL below TACTICAL_ENTER; the gaps are the hysteresis.
const REGIONAL_ENTER := 24000.0
const REGIONAL_EXIT := 29000.0
const TACTICAL_ENTER := 6500.0
const TACTICAL_EXIT := 8000.0
## Layer fades are in seconds, not frames, so a slow phone crosses the boundary
## at the same rate as a fast one.
const FADE_RATE := 9.0

## Every layer the map can draw, the levels that show it, and whether anything
## can feed it yet. The war layers are declared with no source so that the
## toggle list, the persistence and the level matrix have one truth, and a later
## phase fills a slot rather than inventing one -- a layer with no source is
## reported as unavailable instead of being drawn from made-up data.
const LAYERS := [
	{"id": &"contacts", "label": "Contacts", "levels": [0, 1, 2], "source": true},
	{"id": &"sweep", "label": "Radar sweep", "levels": [2], "source": true},
	{"id": &"places", "label": "Place names", "levels": [0, 1, 2], "source": true},
	{"id": &"route", "label": "Route", "levels": [0, 1, 2], "source": true},
	{"id": &"grid", "label": "Tactical grid", "levels": [0, 1, 2], "source": true},
	{"id": &"territory", "label": "Territory", "levels": [0, 1], "source": false},
	## Objects are drawn at every density, unlike the war's own washes: the brief's
	## planning loop wants the pilot to fly *into* a site and keep seeing what it is,
	## and it is the labels that come off at theatre range rather than the symbols.
	## What a dense view drops is the objects the value table says are not worth a
	## symbol, which is what keeps the layer usable at hundreds of them.
	{"id": &"objects", "label": "Strategic objects", "levels": [0, 1, 2], "source": false},
	{"id": &"air_control", "label": "Air control", "levels": [0], "source": false},
	{"id": &"radar", "label": "Radar coverage", "levels": [1, 2], "source": false},
	{"id": &"sam", "label": "SAM coverage", "levels": [1, 2], "source": false},
	{"id": &"ground", "label": "Ground forces", "levels": [0, 1], "source": false},
	{"id": &"missions", "label": "Missions", "levels": [0, 1], "source": false},
	{"id": &"intelligence", "label": "Intelligence", "levels": [0, 1], "source": false},
]

const SETTINGS_FILE := "user://map_layers.cfg"

var _level: int = Level.TACTICAL
var _alphas := {}
var _enabled := {}
var _sources := {}


func _init() -> void:
	load_settings()
	for layer in LAYERS:
		var id: StringName = layer["id"]
		_alphas[id] = _target(id)


## Advance the fades. Called once a frame while the map is open; it is a handful
## of float lerps and no allocation.
func tick(delta: float, metres: float) -> void:
	_level = level_for(metres, _level)
	var step := clampf(delta * FADE_RATE, 0.0, 1.0)
	for layer in LAYERS:
		var id: StringName = layer["id"]
		var toward := _target(id)
		var now: float = _alphas[id]
		if now == toward:
			continue
		# Snap the last couple of percent, or a layer would spend its whole life
		# easing toward a number it can never quite reach.
		_alphas[id] = toward if absf(toward - now) < 0.02 else now + (toward - now) * step


## The level a range asks for, keeping the previous one inside the hysteresis
## band. `was` is the level the map is currently showing.
static func level_for(metres: float, was := -1) -> int:
	if metres <= TACTICAL_ENTER or (was == Level.TACTICAL and metres < TACTICAL_EXIT):
		return Level.TACTICAL
	if metres >= REGIONAL_EXIT or (was == Level.THEATRE and metres > REGIONAL_ENTER):
		return Level.THEATRE
	return Level.REGIONAL


static func level_name(level: int) -> String:
	return ["THEATRE", "REGIONAL", "TACTICAL"][clampi(level, 0, 2)]


func level() -> int:
	return _level


func alpha(id: StringName) -> float:
	return float(_alphas.get(id, 0.0))


func visible(id: StringName) -> bool:
	return float(_alphas.get(id, 0.0)) > 0.02


## A layer that is switched on and has data to draw, at this level.
func _target(id: StringName) -> float:
	if not bool(_enabled.get(id, true)) or not has_source(id):
		return 0.0
	for layer in LAYERS:
		if layer["id"] == id:
			return 1.0 if int(_level) in (layer["levels"] as Array) else 0.0
	return 0.0


func label(id: StringName) -> String:
	for layer in LAYERS:
		if layer["id"] == id:
			return String(layer["label"])
	return String(id)


## Whether anything can feed this layer. The authored table says what a layer
## would need and the map says what it has: a war theatre with regions loaded
## reports territory available, and one without reports it empty rather than
## drawing an overlay out of nothing.
func has_source(id: StringName) -> bool:
	if _sources.has(id):
		return bool(_sources[id])
	for layer in LAYERS:
		if layer["id"] == id:
			return bool(layer["source"])
	return false


## The map's report on a layer's data. Coming online does not switch the layer on
## by itself: the pilot's persisted preference is already in `_enabled`, so a
## layer that was left alone while it was empty starts from whatever they set.
func set_source(id: StringName, available: bool) -> void:
	_sources[id] = available


func clear_sources() -> void:
	_sources = {}


func ids() -> Array:
	var result := []
	for layer in LAYERS:
		result.append(layer["id"])
	return result


func is_enabled(id: StringName) -> bool:
	return bool(_enabled.get(id, true))


## Returns false when the layer has nothing behind it, so the panel can say so
## rather than toggling a layer that will never draw.
func toggle(id: StringName) -> bool:
	if not has_source(id):
		return false
	_enabled[id] = not is_enabled(id)
	save_settings()
	return true


func save_settings() -> void:
	var config := ConfigFile.new()
	for id in ids():
		config.set_value("layers", String(id), is_enabled(id))
	config.save(SETTINGS_FILE)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) != OK:
		return
	# Read every layer, including the ones with nothing behind them yet: a
	# territory switch thrown off in one theatre should still be off when the next
	# theatre finally has regions to draw.
	for layer in LAYERS:
		var id: StringName = layer["id"]
		_enabled[id] = bool(config.get_value("layers", String(id), true))
