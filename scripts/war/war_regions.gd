extends RefCounted

## The theatre's regions: what they are called, where they end, and which ones
## touch. This is the geographic half of the war; who holds them is
## `war_control.gd`'s business and what they look like is
## `battle_map_territory.gd`'s.
##
## The brief says not to lay hundreds of hexagons over the map, so the regions
## here follow the things a pilot would recognise: the coastline, the
## Broadwater, the Nerang and Coomera river lines, the escarpment west of the
## ranges and the state border along the McPherson Range. They are named for the
## districts they cover.
##
## The boundaries are a command-map tessellation, not cadastral, electoral or
## survey boundaries. The town coordinates come from `map_places.gd`; the coast,
## river and border lines are approximations of public chart and gazetteer data,
## and where a line runs between two recognisable places is this file's
## invention. What the test insists on is that the places the game already knows
## fall inside the region they are named for.
##
## Every region is a set of cells in one shared lattice, so two neighbouring
## regions repeat the same lattice points and their common edge is identical to
## the metre. That is what lets the front line be derived from the data instead
## of being drawn by hand, and what makes a gap between regions impossible.

## The lattice above is in absolute coordinates, so it is one theatre's table and
## not a generator. A second theatre needs its own authored regions; until one
## exists it reports none, which is why the territory layer says "no intelligence
## behind it" instead of drawing Tweed Heads over Botany Bay.
const THEATRE := &"au_gold_coast_tweed_corridor"

const MAP_TILES := preload("res://scripts/terrain/map_tiles.gd")

## Latitude lines, north to south: nine lines, eight rows of cells. The first and
## last overshoot the theatre's own edges by a few metres so the lattice covers
## the ground completely -- a district that stops short of the edge would leave
## the map asking what country the last pixel is in. Index BORDER_ROW is the
## state border, which is not a latitude line at all but a range crest, so it is
## replaced per column below and the value here is never read.
const LATS := [
	-27.8550, -27.9200, -27.9670, -28.0150, -28.0550, -28.1150, -28.1702,
	-28.2400, -28.3050,
]
const BORDER_ROW := 6

## The state border at each longitude line: due west from the Tweed mouth, then
## along the crest of the McPherson Range, which dips south under the coast
## towns before swinging back.
const BORDER := [
	-28.2150, -28.2100, -28.2000, -28.1900, -28.1800, -28.1720, -28.1702,
	-28.1702,
]

## Longitude of the coastline at each latitude line. The Gold Coast shore swings
## east at Point Danger and again at Tugun, which is why the inland grid is
## measured back from it rather than from a fixed meridian: a column that follows
## the coast keeps the coastal districts whole as the land narrows. It is charted
## a few hundred metres seaward of the beach, so that the whole of a spit like
## Burleigh Head counts as the district behind it rather than as ocean.
const SHORE := [
	153.4250, 153.4600, 153.4400, 153.4500, 153.4520, 153.4700, 153.5600,
	153.5900, 153.6100,
]
const SHORE_COLUMN := 6

## How far back from the shoreline each inland column sits, in degrees of
## longitude, west to east. Index SHORE_COLUMN is the shore itself; the two ends
## are the theatre's edges and do not follow it.
const COLUMN_OFFSETS := [-1.0, -0.230, -0.175, -0.120, -0.075, -0.035, 0.0, -1.0]
const WEST_EDGE := 153.1104
const EAST_EDGE := 153.6196

## Eight rows of seven cells, north to south, west to east. Each token is a
## region key below; `sea` is the ocean and takes no part in the land war. The
## columns are belts: the ranges, the hinterland, the river line, the suburbs,
## the built-up corridor and the coastal strip.
const GRID := [
	"lamington   beaudesert  coomera     helensvale  pines       pointer     sea",
	"lamington   beaudesert  coomera     helensvale  pines       pointer     sea",
	"tamborine   beaudesert  coomera     nerang      robina      surfers     sea",
	"tamborine   neurum      carrara     gold_creek  southport   broadbeach  sea",
	"springbrook neurum      advancetown guelph      mudgeeraba  burleigh    sea",
	"springbrook lennbrook   currumbin   currumbin   coolangatta coolangatta sea",
	"macpherson  lennbrook   tweed_west  banora      tweed_heads tweed_heads sea",
	"macpherson  cudgera     bilabil     kings_forest kingscliff  kingscliff  sea",
]

## Region key -> what the map calls it, who holds it when the war starts and what
## it is worth. `owner` is the opening situation, which `war_control.gd` seeds
## from and the war layers of later phases compute over. `value` is what the
## district is worth to whoever is fighting for it: an airfield and the resort
## strip outrank a range crest.
const REGIONS := {
	"lamington": {"name": "LAMINGTON", "owner": "FRIENDLY", "value": 0.3},
	"beaudesert": {"name": "BEAUDESERT ROAD", "owner": "FRIENDLY", "value": 0.35},
	"coomera": {"name": "COOMERA", "owner": "FRIENDLY", "value": 0.42},
	"helensvale": {"name": "HELENSVALE", "owner": "FRIENDLY", "value": 0.72},
	"pines": {"name": "OAKDALE // THE PINES", "owner": "FRIENDLY", "value": 0.4},
	"pointer": {"name": "POINTER // THE SPIT", "owner": "CONTESTED", "value": 0.22},
	"tamborine": {"name": "TAMBORINE MOUNTAIN", "owner": "FRIENDLY", "value": 0.4},
	"neurum": {"name": "NEURUM", "owner": "CONTESTED", "value": 0.28},
	"nerang": {"name": "NERANG", "owner": "FRIENDLY", "value": 0.75},
	"robina": {"name": "ROBINA", "owner": "FRIENDLY", "value": 0.52},
	"surfers": {"name": "SURFERS PARADISE", "owner": "FRIENDLY", "value": 0.85},
	"carrara": {"name": "CARRARA", "owner": "FRIENDLY", "value": 0.48},
	"gold_creek": {"name": "GOLD CREEK", "owner": "FRIENDLY", "value": 0.46},
	"southport": {"name": "SOUTHPORT // BROADWATER", "owner": "FRIENDLY", "value": 0.68},
	"broadbeach": {"name": "BROADBEACH", "owner": "FRIENDLY", "value": 0.5},
	"springbrook": {"name": "SPRINGBROOK", "owner": "CONTESTED", "value": 0.32},
	"advancetown": {"name": "ADVANCETOWN", "owner": "CONTESTED", "value": 0.3},
	"guelph": {"name": "GUELPH", "owner": "CONTESTED", "value": 0.26},
	"mudgeeraba": {"name": "MUDGEERABA", "owner": "FRIENDLY", "value": 0.5},
	"burleigh": {"name": "BURLEIGH HEADS", "owner": "FRIENDLY", "value": 0.58},
	"lennbrook": {"name": "LENNBROOK", "owner": "CONTESTED", "value": 0.25},
	"currumbin": {"name": "CURRUMBIN VALLEY", "owner": "FRIENDLY", "value": 0.45},
	"coolangatta": {"name": "COOLANGATTA // OOL", "owner": "FRIENDLY", "value": 0.8},
	"macpherson": {"name": "MCPHERSON RANGE", "owner": "CONTESTED", "value": 0.2},
	"tweed_west": {"name": "TWEED WEST", "owner": "ENEMY", "value": 0.3},
	"banora": {"name": "BANORA POINT", "owner": "ENEMY", "value": 0.34},
	"tweed_heads": {"name": "TWEED HEADS", "owner": "ENEMY", "value": 0.7},
	"cudgera": {"name": "CUDGERA", "owner": "ENEMY", "value": 0.24},
	"bilabil": {"name": "BILABIL", "owner": "ENEMY", "value": 0.26},
	"kings_forest": {"name": "KINGS FOREST", "owner": "ENEMY", "value": 0.28},
	"kingscliff": {"name": "KINGSCLIFF", "owner": "ENEMY", "value": 0.32},
	"sea": {"name": "TASMAN SEA", "owner": "NEUTRAL", "value": 0.0},
}

var _regions := []
var _by_id := {}
var _adjacent := {}
var _corners := {}
var _bounds := {}
var _world_size := 50000.0
var _loaded := false


## Build the regions for one catalog entry. Returns false when the theatre has
## no region definitions, which is what keeps the territory layer reporting
## "no intelligence behind it" rather than drawing an empty overlay.
func load_theatre(region: Dictionary) -> bool:
	# Emptied before anything is validated, for the same reason `WarDirector.setup`
	# is: a theatre this refuses must leave no districts seated behind it, or the
	# next map loads with the previous theatre's front still drawn over it.
	_regions = []
	_by_id = {}
	_adjacent = {}
	_corners = {}
	_bounds = {}
	_loaded = false
	if not region.has("center_latitude") or not region.has("center_longitude"):
		return false
	if StringName(String(region.get("id", ""))) != THEATRE:
		return false
	var candidate_size := float(region.get("world_size_m", 50000.0))
	var candidate_bounds: Dictionary = MAP_TILES.region_bounds(
		float(region["center_latitude"]), float(region["center_longitude"]), candidate_size)
	if candidate_bounds.is_empty():
		return false
	_world_size = candidate_size
	_bounds = candidate_bounds
	var cells := _grid_cells()
	# Walked from the grid rather than the table, so a district named in GRID but
	# never authored shows up as a hole in the map instead of passing unnoticed.
	for key in cells:
		var info: Dictionary = REGIONS.get(key, {})
		if info.is_empty():
			continue
		var owned: Array = cells[key]
		var rings: Array = _rings_of(owned)
		_regions.append({
			"id": key,
			"name": String(info["name"]),
			"owner": String(info["owner"]),
			"value": float(info["value"]),
			"cells": owned,
			"polygon": rings[0] if not rings.is_empty() else PackedVector2Array(),
			"rings": rings.size(),
			"centre": _centre_of(owned),
		})
	for entry in _regions:
		_by_id[String(entry["id"])] = entry
	_adjacent = _adjacency()
	_loaded = not _regions.is_empty()
	return _loaded


func is_loaded() -> bool:
	return _loaded


func regions() -> Array:
	return _regions


func region(id: String) -> Dictionary:
	return _by_id.get(id, {})


## The region a world-metre point sits in, or an empty Dictionary for ground
## outside the theatre.
func region_at(point: Vector2) -> Dictionary:
	for entry in _regions:
		if _contains(entry["polygon"] as PackedVector2Array, point):
			return entry
	return {}


## Region id -> the ids it shares a boundary with, and for each of them the
## shared segments in world metres, so the front line can be drawn from this
## table without re-deriving anything.
func adjacency() -> Dictionary:
	return _adjacent


static func _latitude_of(row: int, column: int) -> float:
	return float(BORDER[column]) if row == BORDER_ROW else float(LATS[row])


static func _longitude_of(row: int, column: int) -> float:
	if column == 0:
		return WEST_EDGE
	if column == COLUMN_OFFSETS.size() - 1:
		return EAST_EDGE
	return float(SHORE[row]) + float(COLUMN_OFFSETS[column])


## A lattice corner as a real coordinate. Rows and columns are indices rather
## than positions so that two regions meeting on a corner cannot disagree about
## where it is.
static func _lattice(row: int, column: int) -> Vector2:
	return Vector2(_latitude_of(row, column), _longitude_of(row, column))


## The same corner in world metres, cached because a lattice point is asked for
## by up to four regions and the conversion is the same every time.
func _corner_at(at: Vector2i) -> Vector2:
	var key := at.y * 100 + at.x
	if not _corners.has(key):
		_corners[key] = MAP_TILES.world_of(
			_bounds, _lattice(at.y, at.x).x, _lattice(at.y, at.x).y, _world_size)
	return _corners[key]


func _cell_corners(cell: Vector2i) -> Array:
	var column := cell.x
	var row := cell.y
	return [
		Vector2i(column, row), Vector2i(column + 1, row),
		Vector2i(column + 1, row + 1), Vector2i(column, row + 1),
	]


## An edge by its two corners, undirected: the same two corners seen from
## opposite sides must collide.
static func _edge_key(from: Vector2i, to: Vector2i) -> String:
	return "%d,%d-%d,%d" % [
		mini(from.x, to.x), mini(from.y, to.y), maxi(from.x, to.x), maxi(from.y, to.y)]


## The perimeter of a set of cells: every edge used by exactly one cell in the
## set is on the boundary and the rest are interior, so chaining the boundary
## edges walks the region's outline. The cell sets in GRID are contiguous by
## construction, which is what makes one ring the whole answer; the count is
## kept per region so a district that quietly came apart into two blobs is
## visible to the test rather than drawn with a piece missing.
func _rings_of(cells: Array) -> Array:
	var uses := {}
	for cell in cells:
		var ring := _cell_corners(cell as Vector2i)
		for i in range(4):
			var key := _edge_key(ring[i], ring[(i + 1) % 4])
			uses[key] = int(uses.get(key, 0)) + 1
	var next_at := {}
	for cell in cells:
		var ring := _cell_corners(cell as Vector2i)
		for i in range(4):
			var from: Vector2i = ring[i]
			var to: Vector2i = ring[(i + 1) % 4]
			if int(uses[_edge_key(from, to)]) == 1:
				if not next_at.has(from):
					next_at[from] = []
				next_at[from].append(to)
	var rings := []
	while not next_at.is_empty():
		var path := PackedVector2Array()
		var start: Vector2i = next_at.keys()[0]
		var at := start
		while next_at.has(at):
			var onward: Array = next_at[at]
			next_at.erase(at)
			path.append(_corner_at(at))
			at = onward[0]
			if at == start:
				break
		# Closed, so a polyline draws the perimeter without the caller repeating
		# the first corner by hand.
		if not path.is_empty():
			path.append(path[0])
		rings.append(path)
	return rings


## Mean of every corner of every cell, weighted by how often it appears, so an
## L-shaped district reports a centre that is still inside it rather than the
## middle of its bounding box.
func _centre_of(cells: Array) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for cell in cells:
		for corner in _cell_corners(cell as Vector2i):
			total += _corner_at(corner as Vector2i)
			count += 1
	if count == 0:
		return Vector2.ZERO
	return total / float(count)


func _grid_cells() -> Dictionary:
	var cells := {}
	for row in GRID.size():
		var tokens := String(GRID[row]).split(" ", false)
		for column in tokens.size():
			var key := String(tokens[column])
			if not cells.has(key):
				cells[key] = []
			cells[key].append(Vector2i(column, row))
	return cells


func _owner_of_cell(row: int, column: int) -> String:
	if row >= GRID.size():
		return ""
	var tokens := String(GRID[row]).split(" ", false)
	return String(tokens[column]) if column < tokens.size() else ""


## Every pair of cells that share a lattice edge, in both directions, with the
## edge itself as a world-metre segment. Two regions that meet along several
## edges accumulate several segments, which is exactly what a front line that
## follows the ground wants.
func _adjacency() -> Dictionary:
	var table := {}
	for row in GRID.size():
		var tokens := String(GRID[row]).split(" ", false)
		for column in tokens.size():
			var here := String(tokens[column])
			for step in [Vector2i(1, 0), Vector2i(0, 1)]:
				var there := _owner_of_cell(row + step.y, column + step.x)
				if there.is_empty() or there == here:
					continue
				var segment := [
					_corner_at(Vector2i(column + step.x, row + step.y)),
					_corner_at(Vector2i(column + step.x + (1 - step.x), row + step.y + (1 - step.y))),
				]
				for pair in [[here, there], [there, here]]:
					if not table.has(pair[0]):
						table[pair[0]] = {}
					var neighbours: Dictionary = table[pair[0]]
					if not neighbours.has(pair[1]):
						neighbours[pair[1]] = []
					neighbours[pair[1]].append(segment)
	return table


## Even-odd test. The crossing is only counted when the edge straddles the
## point's latitude, which is also what keeps the divisor away from zero.
static func _contains(polygon: PackedVector2Array, point: Vector2) -> bool:
	var inside := false
	var count := polygon.size()
	for i in range(count):
		var a := polygon[i]
		var b := polygon[(i + 1) % count]
		if (a.y > point.y) != (b.y > point.y):
			if point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x:
				inside = not inside
	return inside
