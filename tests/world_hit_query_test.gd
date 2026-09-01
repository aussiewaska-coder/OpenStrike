extends SceneTree

# Terrain precision (spec section 79) and building-before-terrain ordering
# (spec section 80).

const QUERY := preload("res://scripts/world/world_hit_query.gd")
const INDEX := preload("res://scripts/terrain/building_hit_index.gd")
const RESOLVER := preload("res://scripts/world/world_surface_resolver.gd")
const SURFACES := preload("res://scripts/world/surface_types.gd")


func _initialize() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0
	# A hill rising eastward past x = 100.
	var slope := func(x: float, _z: float) -> float: return maxf(0.0, (x - 100.0) * 0.5)

	var resolver: RefCounted = RESOLVER.new()
	resolver.configure(flat, -1000.0)

	var flat_query: RefCounted = QUERY.new()
	flat_query.configure(flat, null, resolver, -1000.0)

	# Descending round on flat ground: the crossing must be precise, not
	# quantised to the 40 m the coarse step would give.
	var descent: RefCounted = flat_query.query_segment(Vector3(0.0, 5.0, 0.0), Vector3(40.0, -5.0, 0.0))
	assert(descent != null and descent.hit, "descending round must strike flat ground")
	assert(absf(descent.position.y) < 0.05, "impact y should be ~0, got %f" % descent.position.y)
	assert(absf(descent.position.x - 20.0) < 0.2, "impact x should be ~20, got %f" % descent.position.x)
	assert(descent.normal.is_equal_approx(Vector3.UP), "flat ground normal must be up")

	# A level round above flat ground must not report a hit.
	assert(flat_query.query_segment(Vector3(0.0, 5.0, 0.0), Vector3(40.0, 5.0, 0.0)) == null, "level round must miss")

	# Sloped ground must produce a tilted normal, not Vector3.UP.
	var slope_query: RefCounted = QUERY.new()
	slope_query.configure(slope, null, resolver, -1000.0)
	var graze: RefCounted = slope_query.query_segment(Vector3(100.0, 20.0, 0.0), Vector3(180.0, 18.0, 0.0))
	assert(graze != null and graze.hit, "the round must climb into the slope")
	assert(graze.normal.x < -0.1, "slope normal must lean away from the rising ground")
	assert(not graze.normal.is_equal_approx(Vector3.UP), "slope normal must not be straight up")

	# A building standing in front of a hill wins.
	var index: RefCounted = INDEX.new()
	index.add_chunk(0, [{
		"osm_id": 7, "x": 40.0, "z": 0.0, "height": 30.0,
		"footprint": [[30.0, -10.0], [50.0, -10.0], [50.0, 10.0], [30.0, 10.0]],
	}], slope)
	var ordered: RefCounted = QUERY.new()
	ordered.configure(slope, index, resolver, -1000.0)
	var blocked: RefCounted = ordered.query_segment(Vector3(0.0, 15.0, 0.0), Vector3(200.0, 5.0, 0.0))
	assert(blocked != null and blocked.building_id == 7, "the building must stop the round before the hill")

	# Passing above the same building, the hill takes the hit instead.
	var over: RefCounted = ordered.query_segment(Vector3(0.0, 60.0, 0.0), Vector3(300.0, 20.0, 0.0))
	assert(over != null and over.hit and over.building_id == 0, "clearing the roof must yield a terrain hit")

	# Water only exists where the ground is genuinely below sea level.
	var sea_query: RefCounted = QUERY.new()
	var seabed := func(x: float, _z: float) -> float: return -20.0 if x > 50.0 else 30.0
	var sea_resolver: RefCounted = RESOLVER.new()
	sea_resolver.configure(seabed, 0.0)
	sea_query.configure(seabed, null, sea_resolver, 0.0)
	var splash: RefCounted = sea_query.query_segment(Vector3(100.0, 5.0, 0.0), Vector3(110.0, -5.0, 0.0))
	assert(splash != null and splash.surface_type == SURFACES.Surface.WATER, "must splash over the seabed")
	var hilltop: RefCounted = sea_query.query_segment(Vector3(0.0, 5.0, 0.0), Vector3(10.0, -5.0, 0.0))
	assert(hilltop != null and hilltop.surface_type != SURFACES.Surface.WATER, "dry land must not splash")

	print("WORLD_HIT_QUERY_TEST_PASS")
	quit()
