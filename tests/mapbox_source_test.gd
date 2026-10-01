extends SceneTree
## Locks the Mapbox path: tile URL shape, zoom selection, the Mercator ->
## lat/lon resample math, and — when a token is present on the device — one
## live fetch over Surfers Paradise that must return real detail, not a
## blank frame or a misaligned photo.

const CORRIDOR_LATITUDE := -28.08
const CORRIDOR_LONGITUDE := 153.365
const SURFERS_NORTH := -27.9913
const SURFERS_SOUTH := -28.0133
const SURFERS_WEST := 153.42
const SURFERS_EAST := 153.442


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var client: Node = root.get_node("TileClient")
	assert(client != null)

	# Chunk geometry decides the zoom: pick the sharpest zoom whose tile grid
	# fits inside the requested pixel size, so the tile count (and the bill)
	# never exceeds the old gov request. A 2.5 km chunk is 5x5 z15 tiles =
	# 2560 px (too wide for 2048), so z15 there buys ~1.5 m/px; z17 fits only
	# a 4096 px near-tier request.
	var chunk := {
		"north": SURFERS_NORTH, "south": SURFERS_SOUTH,
		"west": SURFERS_WEST, "east": SURFERS_EAST,
	}
	assert(client.mapbox_zoom_for(chunk, 2048) == 15)
	assert(client.mapbox_zoom_for(chunk, 1024) == 14)
	assert(client.mapbox_zoom_for(chunk, 4096) == 16)
	assert(client.mapbox_grid_size(chunk, 15) == Vector2i(3, 3))
	var overview := MapTiles.region_bounds(CORRIDOR_LATITUDE, CORRIDOR_LONGITUDE, 50000.0)
	assert(client.mapbox_zoom_for(overview, 2048) <= 14)

	# Mercator cross-check against independently computed tile numbers: z16
	# over Surfers Paradise is column 60699, and the beachfront sits at row
	# 38082 — the scheme Mapbox serves, not a flipped one.
	var tiles := MapTiles.tile_range(chunk, 16)
	assert(int(tiles["x0"]) == 60697)
	assert(int(tiles["columns"]) == 5)
	assert(int(tiles["y1"]) == 38083)
	var lon_span_tiles := MapTiles.tile_x(SURFERS_EAST, 16) - MapTiles.tile_x(SURFERS_WEST, 16)
	var lat_span_tiles := MapTiles.tile_y(SURFERS_SOUTH, 16) - MapTiles.tile_y(SURFERS_NORTH, 16)
	assert(absf(lat_span_tiles / lon_span_tiles - 1.0 / cos(deg_to_rad(-28.0))) < 0.01)

	# The retina suffix must lead the extension: ".../16/1/1.png@2x" 404s.
	var url: String = client.MAPBOX_URL % [16, 60699, 38082, "tok"]
	assert(url.contains("/16/60699/38082@2x.png?access_token=tok"))

	# The override is device-level: "auto" keeps whatever the catalog says.
	var saved_override: String = client.imagery_override
	client.imagery_override = "mapbox"
	assert(client.effective_server("qld") == "mapbox")
	client.imagery_override = "auto"
	assert(client.effective_server("nsw") == "nsw")
	client.imagery_override = saved_override

	if not client.mapbox_ready():
		print("MAPBOX_SOURCE_TEST_PASS (no token on device; offline assertions only)")
		quit(0)
		return

	client.imagery_override = "mapbox"
	var image: Image = await client.fetch_mapbox_image(chunk, 1024)
	client.imagery_override = saved_override
	if image == null:
		print("MAPBOX_SOURCE_TEST_FAIL: live fetch returned nothing")
		quit(1)
		return
	assert(image.get_width() >= 1000)
	assert(not client._is_blank_frame(image))

	# SkyPoint is a 230 m tower on a block of dark glass and bright balconies;
	# a 1024 px view of its neighbourhood cannot be flat.
	var minimum := 1.0
	var maximum := 0.0
	for sample in range(0, image.get_width() * image.get_height(), 97):
		var x := sample % image.get_width()
		var y := int(sample / image.get_width())
		var luminance := image.get_pixel(x, y).get_luminance()
		minimum = minf(minimum, luminance)
		maximum = maxf(maximum, luminance)
	assert(maximum - minimum > 0.25)
	print("MAPBOX_SOURCE_TEST_PASS (live tile %.0fm/px, contrast %.2f)" % [
		MapTiles.metres_per_pixel(CORRIDOR_LATITUDE, client.mapbox_zoom_for(chunk, 1024)),
		maximum - minimum,
	])
	quit(0)
