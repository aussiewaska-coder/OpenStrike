extends SceneTree
## Locks down the coordinate chain the streamed terrain depends on: region
## bounds -> tile range -> Mercator pixel -> elevation. Expected values were
## produced by sampling the live Terrarium mosaic for the Gold Coast corridor
## and checking them against known ground elevations.

const CORRIDOR_LATITUDE := -28.08
const CORRIDOR_LONGITUDE := 153.365
const CORRIDOR_SIZE_M := 50000.0


func _init() -> void:
	var bounds := MapTiles.region_bounds(CORRIDOR_LATITUDE, CORRIDOR_LONGITUDE, CORRIDOR_SIZE_M)
	assert(is_equal_approx(snappedf(float(bounds["north"]), 0.000001), -27.855422))
	assert(is_equal_approx(snappedf(float(bounds["south"]), 0.000001), -28.304578))
	assert(is_equal_approx(snappedf(float(bounds["west"]), 0.000001), 153.110461))
	assert(is_equal_approx(snappedf(float(bounds["east"]), 0.000001), 153.619539))

	# Square in metres, not in degrees: the longitude half-width carries 1/cos(lat).
	var north_south_km := (float(bounds["north"]) - float(bounds["south"])) * 111.32
	var east_west_km := (float(bounds["east"]) - float(bounds["west"])) * 111.32 * cos(deg_to_rad(CORRIDOR_LATITUDE))
	assert(absf(north_south_km - 50.0) < 0.1)
	assert(absf(east_west_km - 50.0) < 0.1)

	# The whole 50 km corridor is 42 elevation tiles at Terrarium z12.
	var tiles := MapTiles.tile_range(bounds, 12)
	assert(int(tiles["columns"]) == 6)
	assert(int(tiles["rows"]) == 7)
	assert(int(tiles["x0"]) == 3790)
	assert(int(tiles["y0"]) == 2378)

	# Surfers Paradise resolves to the tile actually serving that beachfront.
	assert(int(floor(MapTiles.tile_x(153.431, 12))) == 3793)
	assert(int(floor(MapTiles.tile_y(-28.0023, 12))) == 2380)

	# z12 matches SRTM's ~30 m native sampling; finer zooms only interpolate.
	assert(absf(MapTiles.metres_per_pixel(-28.0, 12) - 33.7449) < 0.001)

	# Placing a real coordinate inside the region, and reading it back.
	var uv := MapTiles.uv_of(bounds, -28.0023, 153.431)
	assert(absf(uv.x - 0.629646) < 0.00001)
	assert(absf(uv.y - 0.327009) < 0.00001)
	assert(absf(MapTiles.latitude_at(bounds, uv.y) - (-28.0023)) < 0.00001)
	assert(absf(MapTiles.longitude_at(bounds, uv.x) - 153.431) < 0.00001)

	# Mercator round trip.
	assert(absf(MapTiles.longitude_of_tile_x(MapTiles.tile_x(153.431, 12), 12) - 153.431) < 0.00001)
	assert(absf(MapTiles.latitude_of_tile_y(MapTiles.tile_y(-28.0023, 12), 12) - (-28.0023)) < 0.00001)

	# Terrarium packs signed metres as h = R*256 + G + B/256 - 32768.
	assert(is_equal_approx(MapTiles.decode_terrarium(Color8(128, 0, 0)), 0.0))
	assert(is_equal_approx(MapTiles.decode_terrarium(Color8(128, 100, 0)), 100.0))
	assert(is_equal_approx(MapTiles.decode_terrarium(Color8(127, 156, 0)), -100.0))


	# The imagery request must match the box's aspect in degrees. A square image
	# for a metres-square box made the service widen the extent by 4.8 km over
	# the corridor and report it in a field nothing read, displacing buildings
	# by up to a kilometre and leaving chunks disagreeing with each other.
	var corridor := MapTiles.region_bounds(-28.08, 153.365, CORRIDOR_SIZE_M)
	var request := MapTiles.request_pixels(corridor, 4100)
	var lon_span: float = corridor["east"] - corridor["west"]
	var lat_span: float = corridor["north"] - corridor["south"]
	if request.x > 4100 or request.y > 4100:
		push_error("request must stay inside the service limit, got %s" % request)
		quit(1)
	var requested_aspect := float(request.x) / float(request.y)
	var box_aspect := lon_span / lat_span
	if absf(requested_aspect - box_aspect) > 0.002:
		push_error("pixel aspect %f must match the box aspect %f" % [requested_aspect, box_aspect])
		quit(1)
	# A box that is taller than it is wide must shrink the width instead.
	var tall := {"west": 153.0, "east": 153.1, "south": -28.4, "north": -28.0}
	var tall_request := MapTiles.request_pixels(tall, 1024)
	if tall_request.y != 1024 or tall_request.x >= 1024:
		push_error("a tall box must cap the height, got %s" % tall_request)
		quit(1)
	print("MAP_TILES_TEST_PASS")
	quit()
