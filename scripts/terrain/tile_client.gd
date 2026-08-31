extends Node
## Downloads and disk-caches the two public map layers OpenStrike streams:
## Mapzen/Terrarium elevation tiles and Australian state-government aerial
## imagery. Everything fetched is written under user://map_cache, so a theatre
## needs the network only the first time it is flown.
##
## Requests are serialised through a single HTTPRequest. That keeps the cache
## and the await chain trivial to reason about; the whole 36 km corridor is
## only ~24 elevation tiles, so there is nothing here worth parallelising.

signal load_progress(done: int, total: int, message: String)

const CACHE_DIR := "user://map_cache"
const TERRARIUM_URL := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"
const QLD_IMAGE_URL := "https://spatial-img.information.qld.gov.au/arcgis/rest/services/Basemaps/LatestStateProgram_AllUsers/ImageServer/exportImage"
const NSW_IMAGE_URL := "https://maps.six.nsw.gov.au/arcgis/rest/services/public/NSW_Imagery/MapServer/export"

## Queensland's ImageServer accepts 7680x4100; NSW SIX returns HTTP 500
## ("Error: bytes") above 1024, so it has to be asked for less.
const QLD_MAX_PX := 4100
const NSW_MAX_PX := 1024
const REQUEST_TIMEOUT_S := 45.0

## The Terrarium mosaic carries occasional single-pixel voids. The Gold Coast
## corridor has two, both inland near Advancetown Lake, reading below -700 m;
## left alone they punch a spike through the mesh and stretch the normalised
## elevation range over nothing. Genuine negatives here are dredged canals and
## river channels no deeper than about -20 m, and open ocean reads a flat 0.
const ELEVATION_FLOOR_M := -30.0

var _http: HTTPRequest
var _busy := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT_S
	_http.use_threads = true
	add_child(_http)


func _acquire() -> void:
	while _busy:
		await get_tree().process_frame
	_busy = true


func _release() -> void:
	_busy = false


func _cache_path(cache_name: String) -> String:
	return "%s/%s" % [CACHE_DIR, cache_name]


func _read_cache(cache_name: String) -> PackedByteArray:
	var path := _cache_path(cache_name)
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	return file.get_buffer(file.get_length())


func _write_cache(cache_name: String, body: PackedByteArray) -> void:
	var file := FileAccess.open(_cache_path(cache_name), FileAccess.WRITE)
	if file != null:
		file.store_buffer(body)


## Cache-first GET. Returns an empty buffer on any failure; callers decide
## whether that is fatal or just a missing detail tile.
func fetch_bytes(url: String, cache_name: String) -> PackedByteArray:
	var cached := _read_cache(cache_name)
	if not cached.is_empty():
		return cached
	await _acquire()
	var started := _http.request(url)
	if started != OK:
		_release()
		push_warning("Map request could not start (%d): %s" % [started, url])
		return PackedByteArray()
	var outcome: Array = await _http.request_completed
	_release()
	var result := int(outcome[0])
	var status := int(outcome[1])
	var body: PackedByteArray = outcome[3]
	if result != HTTPRequest.RESULT_SUCCESS or status != 200 or body.is_empty():
		push_warning("Map request failed (result %d, HTTP %d): %s" % [result, status, url])
		return PackedByteArray()
	_write_cache(cache_name, body)
	return body


## Terrarium elevation for a region, resampled onto a square grid that is
## linear in latitude/longitude so it lines up with the aerial imagery.
##
## Returns {"image": Image (FORMAT_RF, normalised 0..1),
##          "elevation_min_m": float, "elevation_max_m": float}
## or an empty dictionary if no tile could be fetched.
func fetch_heightfield(region_id: String, bounds: Dictionary, zoom: int, resolution: int) -> Dictionary:
	var cache_name := "height_%s_z%d_r%d.bin" % [region_id, zoom, resolution]
	var cached := _read_cache(cache_name)
	if cached.size() == (resolution * resolution + 2) * 4:
		return _heightfield_from_buffer(cached, resolution)

	var tiles := MapTiles.tile_range(bounds, zoom)
	var columns := int(tiles["columns"])
	var rows := int(tiles["rows"])
	var mosaic := Image.create(columns * MapTiles.TILE_PX, rows * MapTiles.TILE_PX, false, Image.FORMAT_RGB8)
	var total := columns * rows
	var fetched := 0
	for row in range(rows):
		for column in range(columns):
			var tile_x := int(tiles["x0"]) + column
			var tile_y := int(tiles["y0"]) + row
			var url := TERRARIUM_URL % [zoom, tile_x, tile_y]
			var body := await fetch_bytes(url, "terrarium_%d_%d_%d.png" % [zoom, tile_x, tile_y])
			fetched += 1
			load_progress.emit(fetched, total, "Streaming elevation %d/%d" % [fetched, total])
			if body.is_empty():
				continue
			var tile := Image.new()
			if tile.load_png_from_buffer(body) != OK:
				push_warning("Terrarium tile did not decode: %s" % url)
				continue
			tile.convert(Image.FORMAT_RGB8)
			mosaic.blit_rect(
				tile,
				Rect2i(0, 0, MapTiles.TILE_PX, MapTiles.TILE_PX),
				Vector2i(column * MapTiles.TILE_PX, row * MapTiles.TILE_PX)
			)
	if fetched == 0:
		return {}

	# Index the raw bytes directly. get_pixel() per sample would allocate a
	# Color for each of the ~1M reads this loop performs.
	var data := mosaic.get_data()
	var mosaic_width := mosaic.get_width()
	var mosaic_height := mosaic.get_height()
	var origin_x := float(tiles["x0"])
	var origin_y := float(tiles["y0"])
	var heights := PackedFloat32Array()
	heights.resize(resolution * resolution)
	var minimum := INF
	var maximum := -INF
	for j in range(resolution):
		var v := float(j) / float(resolution - 1)
		var latitude := MapTiles.latitude_at(bounds, v)
		var pixel_y := (MapTiles.tile_y(latitude, zoom) - origin_y) * float(MapTiles.TILE_PX)
		for i in range(resolution):
			var u := float(i) / float(resolution - 1)
			var longitude := MapTiles.longitude_at(bounds, u)
			var pixel_x := (MapTiles.tile_x(longitude, zoom) - origin_x) * float(MapTiles.TILE_PX)
			var elevation := maxf(
				_sample_terrarium(data, mosaic_width, mosaic_height, pixel_x, pixel_y),
				ELEVATION_FLOOR_M
			)
			heights[j * resolution + i] = elevation
			minimum = minf(minimum, elevation)
			maximum = maxf(maximum, elevation)
		if j % 32 == 0:
			load_progress.emit(j, resolution, "Building elevation grid")
			await get_tree().process_frame

	var span := maxf(maximum - minimum, 1.0)
	var normalised := PackedFloat32Array()
	normalised.resize(resolution * resolution + 2)
	normalised[0] = minimum
	normalised[1] = maximum
	for index in range(heights.size()):
		normalised[index + 2] = (heights[index] - minimum) / span
	var encoded := normalised.to_byte_array()
	_write_cache(cache_name, encoded)
	return _heightfield_from_buffer(encoded, resolution)


func _heightfield_from_buffer(buffer: PackedByteArray, resolution: int) -> Dictionary:
	var values := buffer.to_float32_array()
	var image := Image.create(resolution, resolution, false, Image.FORMAT_RF)
	for j in range(resolution):
		for i in range(resolution):
			image.set_pixel(i, j, Color(values[2 + j * resolution + i], 0.0, 0.0))
	return {
		"image": image,
		"elevation_min_m": values[0],
		"elevation_max_m": values[1],
	}


func _terrarium_at(data: PackedByteArray, width: int, x: int, y: int) -> float:
	var index := (y * width + x) * 3
	return float(data[index]) * 256.0 + float(data[index + 1]) + float(data[index + 2]) / 256.0 - 32768.0


func _sample_terrarium(data: PackedByteArray, width: int, height: int, px: float, py: float) -> float:
	var x0 := clampi(int(floor(px)), 0, width - 1)
	var y0 := clampi(int(floor(py)), 0, height - 1)
	var x1 := mini(x0 + 1, width - 1)
	var y1 := mini(y0 + 1, height - 1)
	var fx := clampf(px - float(x0), 0.0, 1.0)
	var fy := clampf(py - float(y0), 0.0, 1.0)
	var top := lerpf(_terrarium_at(data, width, x0, y0), _terrarium_at(data, width, x1, y0), fx)
	var bottom := lerpf(_terrarium_at(data, width, x0, y1), _terrarium_at(data, width, x1, y1), fx)
	return lerpf(top, bottom, fy)


## Aerial imagery for a latitude/longitude box, requested in EPSG:4326 so the
## returned image is linear in lat/lon and shares the heightfield's UV space.
func fetch_aerial(bounds: Dictionary, pixels: int, server: String = "qld") -> ImageTexture:
	var use_nsw := server == "nsw"
	var size_px: int = mini(pixels, NSW_MAX_PX if use_nsw else QLD_MAX_PX)
	var bbox := "%f,%f,%f,%f" % [
		float(bounds["west"]), float(bounds["south"]),
		float(bounds["east"]), float(bounds["north"]),
	]
	var query := "bbox=%s&bboxSR=4326&imageSR=4326&size=%d,%d&format=jpg&f=image" % [bbox, size_px, size_px]
	var base := NSW_IMAGE_URL if use_nsw else QLD_IMAGE_URL
	var cache_name := "aerial_%s_%s_%d.jpg" % [
		"nsw" if use_nsw else "qld", bbox.replace(",", "_").replace(".", "p"), size_px,
	]
	var body := await fetch_bytes("%s?%s" % [base, query], cache_name)
	if body.is_empty() and not use_nsw:
		# Queensland's mosaic is the sharper source and covers most of the
		# corridor, but it thins out south of the border. NSW SIX backs it up.
		return await fetch_aerial(bounds, pixels, "nsw")
	if body.is_empty():
		return null
	var image := Image.new()
	if image.load_jpg_from_buffer(body) != OK:
		push_warning("Aerial imagery did not decode for bbox %s" % bbox)
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
