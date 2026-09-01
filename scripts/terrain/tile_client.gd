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
## Counted so the on-screen diagnostic can say whether imagery is coming off the
## disk, off the network, or not arriving at all.
var cache_hits := 0
var network_fetches := 0
var failures := 0


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


## What the map cache holds. Nothing prunes it and nothing reported it, so a
## corridor flown end to end could put a gigabyte on the device unannounced.
func cache_report() -> Dictionary:
	var directory := DirAccess.open(CACHE_DIR)
	if directory == null:
		return {"files": 0, "bytes": 0}
	var files := 0
	var bytes := 0
	for name in directory.get_files():
		var file := FileAccess.open(_cache_path(name), FileAccess.READ)
		if file == null:
			continue
		bytes += file.get_length()
		file.close()
		files += 1
	return {"files": files, "bytes": bytes}


## Empties the cache. Everything is re-fetchable, so this only costs bandwidth.
func clear_cache() -> int:
	var directory := DirAccess.open(CACHE_DIR)
	if directory == null:
		return 0
	var removed := 0
	for name in directory.get_files():
		if directory.remove(name) == OK:
			removed += 1
	return removed


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
		cache_hits += 1
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
		failures += 1
		push_warning("Map request failed (result %d, HTTP %d): %s" % [result, status, url])
		return PackedByteArray()
	network_fetches += 1
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
	# NSW SIX refuses anything over 1024, which left the southern half of the
	# corridor at a fraction of Queensland's detail. Ask for it as a grid of
	# 1024 requests and stitch them instead of accepting the cap.
	if use_nsw and pixels > NSW_MAX_PX:
		var per_side: int = clampi(int(ceil(float(pixels) / float(NSW_MAX_PX))), 2, 4)
		var tiled := await fetch_aerial_grid(bounds, NSW_MAX_PX, per_side, "nsw")
		if tiled != null:
			return tiled
	var size_px: int = mini(pixels, NSW_MAX_PX if use_nsw else QLD_MAX_PX)
	var bbox := "%f,%f,%f,%f" % [
		float(bounds["west"]), float(bounds["south"]),
		float(bounds["east"]), float(bounds["north"]),
	]
	# The requested pixel aspect must match the box's aspect *in degrees*, not on
	# the ground. A region box is square in metres, which at this latitude is
	# 1.13 times wider than tall in degrees; asking for a square image made the
	# service quietly widen the latitude span to match and report the adjusted
	# extent in a field nothing read. The imagery then covered 4.8 km more than
	# the mesh believed, displacing everything by up to a kilometre and leaving
	# neighbouring chunks disagreeing with each other. Mapping the returned
	# image across the mesh's 0..1 UVs undoes the pixel-aspect difference, so
	# nothing downstream has to know.
	var request := MapTiles.request_pixels(bounds, size_px)
	var width_px := request.x
	var height_px := request.y
	var query := "bbox=%s&bboxSR=4326&imageSR=4326&size=%d,%d&format=jpg&f=image" % [bbox, width_px, height_px]
	var base := NSW_IMAGE_URL if use_nsw else QLD_IMAGE_URL
	# The size is part of the key, so imagery cached under the old square
	# request is not reused.
	var cache_name := "aerial_%s_%s_%dx%d.jpg" % [
		"nsw" if use_nsw else "qld", bbox.replace(",", "_").replace(".", "p"), width_px, height_px,
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
	return await _texture_from(image)


## Uploading aerial imagery uncompressed costs 12 MB per 2048 px chunk; ETC2
## takes that to 2 MB for about 70 ms of CPU, which is what makes a near/far
## detail ladder affordable at all. Falling back to uncompressed is fine -- it
## only costs memory.
func _texture_from(image: Image) -> ImageTexture:
	# The mipmap build and the compression run on a worker thread. Together they
	# cost 73 ms at 2048 px and 188 ms at 4096, measured on device, and on the
	# main thread that is a visible freeze every time a chunk lands -- which is
	# precisely when flying fast, because that is when chunks land. Only the
	# texture upload, which must be on the main thread, stays here.
	var prepared := Image.new()
	prepared.copy_from(image)
	var task := WorkerThreadPool.add_task(_prepare_image.bind(prepared), true)
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return ImageTexture.create_from_image(prepared)


## Runs on a worker thread. Falling back to uncompressed only costs memory.
func _prepare_image(image: Image) -> void:
	image.generate_mipmaps()
	image.compress(Image.COMPRESS_ETC2, Image.COMPRESS_SOURCE_SRGB)


## Fetches a box as a grid of sub-requests and stitches them.
##
## Two limits make this necessary. NSW SIX refuses anything over 1024 px, and
## Queensland's ImageServer answers 4100 px happily for a 3 km chunk but returns
## HTTP 500 for the whole 36 km corridor -- the cap is on the request, not on the
## ground it covers, so asking for several smaller boxes gets past both.
func fetch_aerial_grid(
	bounds: Dictionary, per_tile_px: int, per_side: int, server: String = "qld"
) -> ImageTexture:
	var north: float = bounds["north"]
	var south: float = bounds["south"]
	var west: float = bounds["west"]
	var east: float = bounds["east"]
	var mosaic: Image = null
	var tile_size := Vector2i.ZERO
	for row in range(per_side):
		for column in range(per_side):
			var cell := {
				"north": lerpf(north, south, float(row) / float(per_side)),
				"south": lerpf(north, south, float(row + 1) / float(per_side)),
				"west": lerpf(west, east, float(column) / float(per_side)),
				"east": lerpf(west, east, float(column + 1) / float(per_side)),
			}
			var texture: ImageTexture = await fetch_aerial(cell, per_tile_px, server)
			if texture == null:
				return null
			var tile := texture.get_image()
			if tile == null:
				return null
			tile.decompress()
			tile.convert(Image.FORMAT_RGB8)
			if mosaic == null:
				tile_size = Vector2i(tile.get_width(), tile.get_height())
				mosaic = Image.create(tile_size.x * per_side, tile_size.y * per_side, false, Image.FORMAT_RGB8)
			mosaic.blit_rect(
				tile,
				Rect2i(Vector2i.ZERO, tile_size),
				Vector2i(column * tile_size.x, row * tile_size.y)
			)
	if mosaic == null:
		return null
	return await _texture_from(mosaic)
