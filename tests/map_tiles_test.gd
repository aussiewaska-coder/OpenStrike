extends SceneTree
## Locks down the coordinate chain the streamed terrain depends on: region
## bounds -> tile range -> Mercator pixel -> elevation. Expected values were
## produced by sampling the live Terrarium mosaic for the Gold Coast corridor
## and checking them against known ground elevations.

const CORRIDOR_LATITUDE := -28.08
const CORRIDOR_LONGITUDE := 153.365
const CORRIDOR_SIZE_M := 36000.0


func _init() -> void:
	var bounds := MapTiles.region_bounds(CORRIDOR_LATITUDE, CORRIDOR_LONGITUDE, CORRIDOR_SIZE_M)
	assert(is_equal_approx(snappedf(float(bounds["north"]), 0.000001), -27.918304))
	assert(is_equal_approx(snappedf(float(bounds["south"]), 0.000001), -28.241696))
	assert(is_equal_approx(snappedf(float(bounds["west"]), 0.000001), 153.181732))
	assert(is_equal_approx(snappedf(float(bounds["east"]), 0.000001), 153.548268))

	# Square in metres, not in degrees: the longitude half-width carries 1/cos(lat).
	var north_south_km := (float(bounds["north"]) - float(bounds["south"])) * 111.32
	var east_west_km := (float(bounds["east"]) - float(bounds["west"])) * 111.32 * cos(deg_to_rad(CORRIDOR_LATITUDE))
	assert(absf(north_south_km - 36.0) < 0.1)
	assert(absf(east_west_km - 36.0) < 0.1)

	# The whole 36 km corridor is 30 elevation tiles at Terrarium z12.
	var tiles := MapTiles.tile_range(bounds, 12)
	assert(int(tiles["columns"]) == 6)
	assert(int(tiles["rows"]) == 5)
	assert(int(tiles["x0"]) == 3790)
	assert(int(tiles["y0"]) == 2379)

	# Surfers Paradise resolves to the tile actually serving that beachfront.
	assert(int(floor(MapTiles.tile_x(153.431, 12))) == 3793)
	assert(int(floor(MapTiles.tile_y(-28.0023, 12))) == 2380)

	# z12 matches SRTM's ~30 m native sampling; finer zooms only interpolate.
	assert(absf(MapTiles.metres_per_pixel(-28.0, 12) - 33.7449) < 0.001)

	# Placing a real coordinate inside the region, and reading it back.
	var uv := MapTiles.uv_of(bounds, -28.0023, 153.431)
	assert(absf(uv.x - 0.680064) < 0.00001)
	assert(absf(uv.y - 0.259734) < 0.00001)
	assert(absf(MapTiles.latitude_at(bounds, uv.y) - (-28.0023)) < 0.00001)
	assert(absf(MapTiles.longitude_at(bounds, uv.x) - 153.431) < 0.00001)

	# Mercator round trip.
	assert(absf(MapTiles.longitude_of_tile_x(MapTiles.tile_x(153.431, 12), 12) - 153.431) < 0.00001)
	assert(absf(MapTiles.latitude_of_tile_y(MapTiles.tile_y(-28.0023, 12), 12) - (-28.0023)) < 0.00001)

	# Terrarium packs signed metres as h = R*256 + G + B/256 - 32768.
	assert(is_equal_approx(MapTiles.decode_terrarium(Color8(128, 0, 0)), 0.0))
	assert(is_equal_approx(MapTiles.decode_terrarium(Color8(128, 100, 0)), 100.0))
	assert(is_equal_approx(MapTiles.decode_terrarium(Color8(127, 156, 0)), -100.0))

	print("MAP_TILES_TEST_PASS")
	quit()
