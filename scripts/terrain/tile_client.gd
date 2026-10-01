extends Node
## Downloads and disk-caches the map layers OpenStrike streams: elevation
## (Terrarium or Copernicus GLO-30 tiles), state-government aerial imagery, and
## -- when the device holds a Mapbox token -- Mapbox Satellite, which is far
## sharper over the Australian coast. Everything fetched is written under
## user://map_cache, so a theatre needs the network only the first time it is
## flown, and a whole theatre can be pre-downloaded from Settings.
##
## Downloads funnel through four HTTPRequest lanes with a shared disk cache,
## so parallel fetches never download the same tile twice. Elevation for the
## whole 50 km corridor is only ~42 tiles; imagery is the hungry one.

signal load_progress(done: int, total: int, message: String)

const CACHE_DIR := "user://map_cache"
const TERRARIUM_URL := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"
const QLD_IMAGE_URL := "https://spatial-img.information.qld.gov.au/arcgis/rest/services/Basemaps/LatestStateProgram_AllUsers/ImageServer/exportImage"
const NSW_IMAGE_URL := "https://maps.six.nsw.gov.au/arcgis/rest/services/public/NSW_Imagery/MapServer/export"
## Mapbox satellite, @2x for 512 px tiles. The retina suffix goes *before* the
## extension — "/16/1/1.png@2x" is a 404. PNG names return JPEG bytes (ffd8ff
## verified from the device), which is what _decode_image expects.
const MAPBOX_URL := "https://api.mapbox.com/v4/mapbox.satellite/%d/%d/%d@2x.png?access_token=%s"
const MAPBOX_TILE_PX := 512
## Deepest zoom Mapbox reliably serves over Australian metros.
const MAPBOX_MAX_ZOOM := 17
## A single request wider than this many tiles is a bounds bug, not a theatre.
const MAPBOX_MAX_REQUEST_TILES := 4096
## Device-level imagery choice, written by the Settings storage page. The
## token lives outside the repo and outside the APK.
const SETTINGS_FILE := "user://map_settings.cfg"
const TOKEN_FILE := "user://secrets.cfg"
## Copernicus GLO-30 on the same open-data bucket as Terrarium: one gzipped
## SRTM-style .hgt per degree cell, 3601x3601 signed int16 big-endian.
const SKADI_URL := "https://s3.amazonaws.com/elevation-tiles-prod/skadi/%s/%s.hgt.gz"
const SKADI_CELL_SIDE := 3601
const SKADI_CELL_BYTES := SKADI_CELL_SIDE * SKADI_CELL_SIDE * 2

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

var _https: Array[HTTPRequest] = []
var _lane_busy: Array[bool] = []
## Four parallel download lanes. The whole 50 km theatre used to queue
## through one HTTPRequest, so the last of a dozen detail tiles arrived a
## dozen fetches late -- by which time the aircraft had moved on.
const FETCH_LANES := 4
## Counted so the on-screen diagnostic can say whether imagery is coming off the
## disk, off the network, or not arriving at all.
var cache_hits := 0
var network_fetches := 0
var failures := 0
## Whether runtime texture compression is actually available. The editor ships
## the ETC2 compressor; the Android export template does not, and Image.compress
## fails there without raising. Believing it worked cost 317 MB of texture memory
## on device against a 75 MB budget, which is what the frame rate was paying for.
var compression_available := true
var _compression_probed := false
## Mapbox access token. Never committed and never baked into the APK: read
## from user://secrets.cfg (written by Settings) or, for testing on this box
## only, a plain /root/.mapbox_token file.
var mapbox_token := ""
## "auto" keeps the catalog's server; "mapbox"/"qld"/"nsw" override it.
var imagery_override := "auto"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	_load_secrets()
	_load_map_settings()
	for lane in range(FETCH_LANES):
		var http := HTTPRequest.new()
		http.timeout = REQUEST_TIMEOUT_S
		http.use_threads = true
		add_child(http)
		_https.append(http)
		_lane_busy.append(false)


func _load_secrets() -> void:
	var file := FileAccess.open(TOKEN_FILE, FileAccess.READ)
	if file != null:
		var config := ConfigFile.new()
		if config.load(TOKEN_FILE) == OK:
			mapbox_token = String(config.get_value("mapbox", "token", "")).strip_edges()
	if mapbox_token.is_empty():
		mapbox_token = OS.get_environment("OPENSTRIKE_MAPBOX_TOKEN").strip_edges()
	if mapbox_token.is_empty():
		# A plain side file for testing without the settings UI. On Android the
		# app's own user:// dir is tried first; the debug-build external path
		# lets a token be pushed to shared storage.
		for candidate in ["user://mapbox_token.txt", "/root/.mapbox_token",
				"/storage/emulated/0/Download/.mapbox_token"]:
			var raw := FileAccess.open(candidate, FileAccess.READ)
			if raw != null:
				mapbox_token = raw.get_line().strip_edges()
				if not mapbox_token.is_empty():
					break


func _load_map_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) == OK:
		imagery_override = String(config.get_value("imagery", "server", "auto"))


func save_map_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("imagery", "server", imagery_override)
	config.save(SETTINGS_FILE)


## Whether a usable Mapbox token is present.
func mapbox_ready() -> bool:
	return not mapbox_token.is_empty()


## The server a fetch should actually use, after the device override. When
## Mapbox is unavailable the callers degrade to the theatre's gov source via
## their `fallback` parameter, so a missing token costs sharpness, not the map.
func effective_server(requested: String) -> String:
	return requested if imagery_override == "auto" else imagery_override


func _acquire() -> int:
	while true:
		for lane in range(_https.size()):
			if not _lane_busy[lane]:
				_lane_busy[lane] = true
				return lane
		await get_tree().process_frame
	return -1


func _release(lane: int) -> void:
	_lane_busy[lane] = false


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


## Pre-download of a whole theatre: the same chunk-sized requests the terrain
## makes in flight, asked for up front so every texture is already on disk
## when the aircraft arrives. Requests go through the identical fetch path,
## so what is cached here is exactly what streaming looks up later.
signal precache_finished(cancelled: bool)

var precache_cancelled := false
var _precache_running := false


## Tile count and rough megabytes a pre-download would cost, for the UI to
## show before anything is fetched.
func precache_estimate(region: Dictionary, detail_px: int) -> Dictionary:
	var bounds := MapTiles.region_bounds(
		float(region.get("center_latitude", 0.0)),
		float(region.get("center_longitude", 0.0)),
		float(region.get("world_size_m", 50000.0))
	)
	var chunks := int(region.get("chunk_count", 20))
	var per_chunk := mapbox_grid_size(_chunk_bounds(bounds, chunks, 0, 0), mapbox_zoom_for(_chunk_bounds(bounds, chunks, 0, 0), detail_px))
	var tiles := per_chunk.x * per_chunk.y * chunks * chunks
	# ~120 KB an average satellite tile; the ocean ones are smaller.
	return {"tiles": tiles, "megabytes": float(tiles) * 0.12}


func _chunk_bounds(bounds: Dictionary, chunks: int, cx: int, cz: int) -> Dictionary:
	return {
		"north": lerpf(float(bounds["north"]), float(bounds["south"]), float(cz) / float(chunks)),
		"south": lerpf(float(bounds["north"]), float(bounds["south"]), float(cz + 1) / float(chunks)),
		"west": lerpf(float(bounds["west"]), float(bounds["east"]), float(cx) / float(chunks)),
		"east": lerpf(float(bounds["west"]), float(bounds["east"]), float(cx + 1) / float(chunks)),
	}


func cancel_precache() -> void:
	precache_cancelled = true


func precache_region(region: Dictionary, detail_px := 2048) -> void:
	if _precache_running:
		return
	_precache_running = true
	precache_cancelled = false
	var region_id := String(region.get("id", "region"))
	var chunks := int(region.get("chunk_count", 20))
	var bounds := MapTiles.region_bounds(
		float(region.get("center_latitude", 0.0)),
		float(region.get("center_longitude", 0.0)),
		float(region.get("world_size_m", 50000.0))
	)
	var server := String(region.get("imagery_server", "qld"))
	var total := chunks * chunks + 1
	var done := 0
	load_progress.emit(0, total, "Pre-downloading %s" % region_id)
	await fetch_heightfield(
		region_id, bounds,
		int(region.get("elevation_zoom", 12)),
		int(region.get("heightfield_resolution", 1025)),
		int(region.get("elevation_smoothing", 0)),
		String(region.get("elevation_server", "terrarium"))
	)
	done += 1
	for cz in range(chunks):
		for cx in range(chunks):
			if precache_cancelled:
				break
			await fetch_aerial_image(_chunk_bounds(bounds, chunks, cx, cz), detail_px, server, server)
			done += 1
			load_progress.emit(done, total, "Pre-downloading %d/%d" % [done, total])
			await get_tree().process_frame
		if precache_cancelled:
			break
	_precache_running = false
	precache_finished.emit(precache_cancelled)
	precache_cancelled = false


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
	var lane := await _acquire()
	var http: HTTPRequest = _https[lane]
	var started := http.request(url)
	if started != OK:
		_release(lane)
		push_warning("Map request could not start (%d): %s" % [started, url])
		return PackedByteArray()
	var outcome: Array = await http.request_completed
	_release(lane)
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
## Terrarium is a surface model, not a bare-earth one: over Surfers Paradise its
## samples sit on the roofs of the towers, so a beach that is flat in life
## arrives as a ridge of spikes. A few box-blur passes take the buildings out
## while leaving the landform -- the headland, the river channel, the escarpment
## -- intact. Buildings are drawn separately from OSM footprints, so nothing real
## is lost by taking them out of the ground.
static func _smooth_heights(heights: PackedFloat32Array, side: int, passes: int) -> PackedFloat32Array:
	var current := heights
	for _pass in range(passes):
		var next := PackedFloat32Array()
		next.resize(current.size())
		for j in range(side):
			for i in range(side):
				var total := 0.0
				for dj in range(-1, 2):
					for di in range(-1, 2):
						total += current[clampi(j + dj, 0, side - 1) * side + clampi(i + di, 0, side - 1)]
				next[j * side + i] = total / 9.0
		current = next
	return current


func fetch_heightfield(
	region_id: String, bounds: Dictionary, zoom: int, resolution: int,
	smoothing_passes := 0, elevation_server := "terrarium"
) -> Dictionary:
	var cache_name := "height_%s_z%d_r%d_s%d_%s.bin" % [
		region_id, zoom, resolution, smoothing_passes, elevation_server
	]
	var cached := _read_cache(cache_name)
	if cached.size() == (resolution * resolution + 2) * 4:
		return _heightfield_from_buffer(cached, resolution)

	# Two samplers, one grid loop: Terrarium's RGB PNG tiles at the Web Mercator
	# zoom, or Copernicus GLO-30 degree cells (skadi) at their native 30 m.
	var sample: Callable
	var tiles := MapTiles.tile_range(bounds, zoom)
	var mosaic: Image = null
	var total := 0
	if elevation_server == "skadi":
		var cells := await _fetch_skadi_cells(bounds)
		if cells.is_empty():
			return {}
		total = cells.size()
		sample = func(u: float, v: float) -> float:
			return _sample_skadi_cells(cells, MapTiles.longitude_at(bounds, u), MapTiles.latitude_at(bounds, v))
	else:
		var columns := int(tiles["columns"])
		var rows := int(tiles["rows"])
		mosaic = Image.create(columns * MapTiles.TILE_PX, rows * MapTiles.TILE_PX, false, Image.FORMAT_RGB8)
		total = columns * rows
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
		var data := mosaic.get_data()
		var mosaic_width := mosaic.get_width()
		var mosaic_height := mosaic.get_height()
		var origin_x := float(tiles["x0"])
		var origin_y := float(tiles["y0"])
		sample = func(u: float, v: float) -> float:
			var latitude := MapTiles.latitude_at(bounds, v)
			var longitude := MapTiles.longitude_at(bounds, u)
			var pixel_y := (MapTiles.tile_y(latitude, zoom) - origin_y) * float(MapTiles.TILE_PX)
			var pixel_x := (MapTiles.tile_x(longitude, zoom) - origin_x) * float(MapTiles.TILE_PX)
			return _sample_terrarium(data, mosaic_width, mosaic_height, pixel_x, pixel_y)

	var heights := PackedFloat32Array()
	heights.resize(resolution * resolution)
	var minimum := INF
	var maximum := -INF
	for j in range(resolution):
		for i in range(resolution):
			var elevation := maxf(
				sample.call(float(i) / float(resolution - 1), float(j) / float(resolution - 1)),
				ELEVATION_FLOOR_M
			)
			heights[j * resolution + i] = elevation
			minimum = minf(minimum, elevation)
			maximum = maxf(maximum, elevation)
		if j % 32 == 0:
			load_progress.emit(j, resolution, "Building elevation grid")
			await get_tree().process_frame

	if smoothing_passes > 0:
		heights = _smooth_heights(heights, resolution, smoothing_passes)
		minimum = INF
		maximum = -INF
		for value in heights:
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)

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


## Copernicus GLO-30 (skadi): one signed-int16 big-endian 3601x3601 grid per
## degree cell, fetched from the same open-data bucket as Terrarium and cached
## raw. Newer and more consistent than the SRTM Terrarium renders; still 30 m
## class, so it refines the landform rather than resolving buildings.
func _fetch_skadi_cells(bounds: Dictionary) -> Dictionary:
	var cells := {}
	for lat_floor in range(int(floor(float(bounds["south"]))), int(floor(float(bounds["north"]))) + 1):
		for lon_floor in range(int(floor(float(bounds["west"]))), int(floor(float(bounds["east"]))) + 1):
			var cell_name := ("S%d" % absi(lat_floor) if lat_floor < 0 else "N%d" % lat_floor) + "E%d" % lon_floor
			var cache_name := "skadi_%s.hgt" % cell_name
			var raw := _read_cache(cache_name)
			if raw.size() != SKADI_CELL_BYTES:
				var gzipped := await fetch_bytes(
					SKADI_URL % [cell_name.left(3), cell_name], "raw_" + cell_name + ".hgt.gz"
				)
				if gzipped.is_empty():
					continue
				raw = gzipped.decompress_dynamic(SKADI_CELL_BYTES, FileAccess.COMPRESSION_GZIP)
				if raw.size() != SKADI_CELL_BYTES:
					push_warning("Skadi cell %s decompressed to %d bytes" % [cell_name, raw.size()])
					continue
				_write_cache(cache_name, raw)
			cells[cell_name] = raw
	return cells


func _skadi_elevation(cell: PackedByteArray, row: int, column: int) -> float:
	var index := (clampi(row, 0, SKADI_CELL_SIDE - 1) * SKADI_CELL_SIDE + clampi(column, 0, SKADI_CELL_SIDE - 1)) * 2
	var raw := int(cell[index]) << 8 | int(cell[index + 1])
	return float(raw - 65536 if raw > 32768 else raw)


## Bilinear sample of the degree-cell grid at a coordinate. Cells meet exactly
## on the degree lines, so sampling each point inside its own cell keeps the
## seams continuous. Large negatives are voids; they read as sea level.
func _sample_skadi_cells(cells: Dictionary, longitude: float, latitude: float) -> float:
	var lat_floor := int(floor(latitude))
	var lon_floor := int(floor(longitude))
	var cell_name := ("S%d" % absi(lat_floor) if lat_floor < 0 else "N%d" % lat_floor) + "E%d" % lon_floor
	if not cells.has(cell_name):
		lat_floor += 1
		cell_name = ("S%d" % absi(lat_floor) if lat_floor < 0 else "N%d" % lat_floor) + "E%d" % lon_floor
		if not cells.has(cell_name):
			return 0.0
	var cell: PackedByteArray = cells[cell_name]
	var fx := (longitude - float(lon_floor)) * float(SKADI_CELL_SIDE - 1)
	# Rows run north to south in the file.
	var fy := (1.0 - (latitude - float(lat_floor))) * float(SKADI_CELL_SIDE - 1)
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var value := lerpf(
		lerpf(_skadi_elevation(cell, y0, x0), _skadi_elevation(cell, y0, x0 + 1), tx),
		lerpf(_skadi_elevation(cell, y0 + 1, x0), _skadi_elevation(cell, y0 + 1, x0 + 1), tx),
		ty
	)
	return 0.0 if value < -1000.0 else value


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
## `fallback` names the gov service used when a Mapbox request misses.
## Tile count across a box at a zoom (fractional span rounded up), both axes.
static func mapbox_grid_size(bounds: Dictionary, zoom: int) -> Vector2i:
	var across := int(ceil(MapTiles.tile_x(float(bounds["east"]), zoom) - MapTiles.tile_x(float(bounds["west"]), zoom)))
	var down := int(ceil(MapTiles.tile_y(float(bounds["south"]), zoom) - MapTiles.tile_y(float(bounds["north"]), zoom)))
	return Vector2i(maxi(across, 1), maxi(down, 1))


## Zoom whose 512 px grid covers the box in at most `pixels` native tiles on
## either axis, preferring the sharpest such zoom; MAPBOX_MAX_ZOOM with an
## upscale when nothing fits. Sharper-than-native only resamples, so the tile
## count (and the Mapbox bill) stays bounded by the requested pixel size.
static func mapbox_zoom_for(bounds: Dictionary, pixels: int) -> int:
	for zoom in range(MAPBOX_MAX_ZOOM, 8, -1):
		var grid := mapbox_grid_size(bounds, zoom)
		if maxi(grid.x, grid.y) * MAPBOX_TILE_PX <= pixels:
			return zoom
	return MAPBOX_MAX_ZOOM


## Pixel span to resample to: the grid's native size, kept within the caller's
## budget so a cap-zoom fetch cannot return an oversized image.
static func mapbox_output_pixels(bounds: Dictionary, pixels: int) -> int:
	var grid := mapbox_grid_size(bounds, mapbox_zoom_for(bounds, pixels))
	return mini(maxi(maxi(grid.x, grid.y) * MAPBOX_TILE_PX, pixels), pixels * 2)


func fetch_mapbox_image(bounds: Dictionary, pixels: int) -> Image:
	if not mapbox_ready():
		return null
	var zoom := mapbox_zoom_for(bounds, pixels)
	var tiles := MapTiles.tile_range(bounds, zoom)
	var columns := int(tiles["columns"])
	var rows := int(tiles["rows"])
	if columns * rows > MAPBOX_MAX_REQUEST_TILES:
		return null
	var mosaic := Image.create(columns * MAPBOX_TILE_PX, rows * MAPBOX_TILE_PX, false, Image.FORMAT_RGB8)
	var any := false
	var total := columns * rows
	var done := 0
	for row in range(rows):
		for column in range(columns):
			var tile_x := int(tiles["x0"]) + column
			var tile_y := int(tiles["y0"]) + row
			var cache_name := "aerial_mapbox_z%d_%d_%d.png" % [zoom, tile_x, tile_y]
			var body := await fetch_bytes(
				MAPBOX_URL % [zoom, tile_x, tile_y, mapbox_token], cache_name
			)
			done += 1
			load_progress.emit(done, total, "Streaming Mapbox imagery %d/%d" % [done, total])
			if body.is_empty():
				continue
			var tile := await _decode_image(body)
			if tile == null:
				continue
			tile = tile.duplicate()
			tile.decompress()
			tile.convert(Image.FORMAT_RGB8)
			mosaic.blit_rect(tile, Rect2i(0, 0, MAPBOX_TILE_PX, MAPBOX_TILE_PX), Vector2i(column * MAPBOX_TILE_PX, row * MAPBOX_TILE_PX))
			any = true
	if not any:
		return null
	var output_px := mapbox_output_pixels(bounds, pixels)
	var request := MapTiles.request_pixels(bounds, output_px)
	var output := Image.create(request.x, request.y, false, Image.FORMAT_RGB8)
	_resample_mercator_to_latlon(mosaic, tiles, zoom, bounds, output)
	return output


## Mercator tile mosaic -> linear lat/lon grid, the UV space the mesh samples.
## Indexed byte reads; get_pixel() would allocate per sample. Runs on the
## caller's thread — for 4096² output this is ~30 ms, so keep it out of
## per-frame paths (detail uploads are already paced to one per frame).
func _resample_mercator_to_latlon(
	mosaic: Image, tiles: Dictionary, zoom: int, bounds: Dictionary, out: Image
) -> void:
	var src := mosaic.get_data()
	var src_width := mosaic.get_width()
	var src_height := mosaic.get_height()
	var out_width := out.get_width()
	var out_height := out.get_height()
	var origin_x := float(tiles["x0"])
	var origin_y := float(tiles["y0"])
	var tiles_across := float(1 << zoom)
	var tile_px := float(MAPBOX_TILE_PX)
	for j in range(out_height):
		var latitude := MapTiles.latitude_at(bounds, float(j + 0.5) / float(out_height))
		var pixel_y := (1.0 - asinh_of_tan(latitude) / PI) / 2.0 * tiles_across * tile_px - origin_y * tile_px
		var y0i := clampi(int(floor(pixel_y)), 0, src_height - 1)
		var y1i := mini(y0i + 1, src_height - 1)
		var fy := clampf(pixel_y - float(y0i), 0.0, 1.0)
		for i in range(out_width):
			var longitude := MapTiles.longitude_at(bounds, float(i + 0.5) / float(out_width))
			var pixel_x := ((longitude + 180.0) / 360.0 * tiles_across - origin_x) * tile_px
			var x0i := clampi(int(floor(pixel_x)), 0, src_width - 1)
			var x1i := mini(x0i + 1, src_width - 1)
			var fx := clampf(pixel_x - float(x0i), 0.0, 1.0)
			var row_a := y0i * src_width
			var row_b := y1i * src_width
			var ia := row_a + x0i
			var ib := row_a + x1i
			var ja := row_b + x0i
			var jb := row_b + x1i
			# Image.set_data() is a no-op for uncompressed images in this engine
			# build (verified: writes never reach the pixels), so set per pixel.
			out.set_pixel(i, j, Color(
				lerpf(
					lerpf(float(src[ia * 3]), float(src[ib * 3]), fx),
					lerpf(float(src[ja * 3]), float(src[jb * 3]), fx), fy) / 255.0,
				lerpf(
					lerpf(float(src[ia * 3 + 1]), float(src[ib * 3 + 1]), fx),
					lerpf(float(src[ja * 3 + 1]), float(src[jb * 3 + 1]), fx), fy) / 255.0,
				lerpf(
					lerpf(float(src[ia * 3 + 2]), float(src[ib * 3 + 2]), fx),
					lerpf(float(src[ja * 3 + 2]), float(src[jb * 3 + 2]), fx), fy) / 255.0
			))


static func asinh_of_tan(latitude_deg: float) -> float:
	return MapTiles.asinh_of(tan(deg_to_rad(clampf(latitude_deg, -85.05112878, 85.05112878))))


## Aerial imagery for a latitude/longitude box, requested in EPSG:4326 so the
## returned image is linear in lat/lon and shares the heightfield's UV space.
## `fallback` names the gov service used when a Mapbox request misses.
func fetch_aerial(bounds: Dictionary, pixels: int, server: String = "qld", fallback := "qld") -> ImageTexture:
	server = effective_server(server)
	if server == "mapbox":
		var mb := await fetch_mapbox_image(bounds, pixels)
		if mb != null:
			var prepared := await _texture_from(mb)
			if prepared != null:
				return prepared
		return await fetch_aerial(bounds, pixels, fallback, fallback)
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
	var texture := await _texture_from_jpeg(body, bbox)
	if texture == null and not use_nsw:
		# Queensland answers HTTP 200 with a solid-black frame outside its
		# coverage (verified over Sydney). Treat it as a miss, not a photo.
		return await fetch_aerial(bounds, pixels, "nsw")
	return texture


## Uploading aerial imagery uncompressed costs 12 MB per 2048 px chunk; ETC2
## takes that to 2 MB for about 70 ms of CPU, which is what makes a near/far
## detail ladder affordable at all. Falling back to uncompressed is fine -- it
## only costs memory.
## Decoding a 2048 px JPEG costs 30 to 46 ms, measured from the device's own
## telemetry, and on the main thread that is a stutter every time a chunk lands.
## The decode joins the mipmap build and the format conversion on the worker, so
## only the upload stays on the main thread.
func _texture_from_jpeg(body: PackedByteArray, label: String) -> ImageTexture:
	var image := await _decode_image(body)
	if image == null:
		push_warning("Aerial imagery did not decode for %s" % label)
		return null
	return ImageTexture.create_from_image(image)


## Same decode without the upload: detail chunks prepare on the worker and
## hand the terrain a finished Image, so it can pace GPU uploads to one per
## frame instead of stalling whenever several chunks land together.
func _decode_image(body: PackedByteArray) -> Image:
	var result := {"image": null}
	var task := WorkerThreadPool.add_task(_decode_and_prepare.bind(body, result), true)
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return result["image"]


## Image-returning twin of fetch_aerial for the paced detail pipeline. Null
## means miss (network, decode or blank frame), never a black tile.
func fetch_aerial_image(bounds: Dictionary, pixels: int, server: String = "qld", fallback := "qld") -> Image:
	server = effective_server(server)
	if server == "mapbox":
		var mb := await fetch_mapbox_image(bounds, pixels)
		if mb != null:
			return mb
		return await fetch_aerial_image(bounds, pixels, fallback, fallback)
	var use_nsw := server == "nsw"
	if use_nsw and pixels > NSW_MAX_PX:
		var per_side: int = clampi(int(ceil(float(pixels) / float(NSW_MAX_PX))), 2, 4)
		var mosaic := await fetch_aerial_mosaic(bounds, NSW_MAX_PX, per_side, "nsw")
		if mosaic == null:
			return null
		var stitched := Image.new()
		stitched.copy_from(mosaic)
		var grid_task := WorkerThreadPool.add_task(_prepare_image.bind(stitched), true)
		while not WorkerThreadPool.is_task_completed(grid_task):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(grid_task)
		return stitched
	var size_px: int = mini(pixels, NSW_MAX_PX if use_nsw else QLD_MAX_PX)
	var bbox := "%f,%f,%f,%f" % [
		float(bounds["west"]), float(bounds["south"]),
		float(bounds["east"]), float(bounds["north"]),
	]
	var request := MapTiles.request_pixels(bounds, size_px)
	var width_px := request.x
	var height_px := request.y
	var query := "bbox=%s&bboxSR=4326&imageSR=4326&size=%d,%d&format=jpg&f=image" % [bbox, width_px, height_px]
	var base := NSW_IMAGE_URL if use_nsw else QLD_IMAGE_URL
	var cache_name := "aerial_%s_%s_%dx%d.jpg" % [
		"nsw" if use_nsw else "qld", bbox.replace(",", "_").replace(".", "p"), width_px, height_px,
	]
	var body := await fetch_bytes("%s?%s" % [base, query], cache_name)
	if body.is_empty():
		return null
	var image := await _decode_image(body)
	if image == null and not use_nsw:
		return await fetch_aerial_image(bounds, pixels, "nsw")
	return image


## Runs on a worker thread.
func _decode_and_prepare(body: PackedByteArray, result: Dictionary) -> void:
	var image := Image.new()
	if image.load_jpg_from_buffer(body) != OK:
		return
	if _is_blank_frame(image):
		return
	_prepare_image(image)
	result["image"] = image


## Out-of-coverage answers decode fine but carry no photo: every pixel
## identical. Sample a spread so a real frame (sea included) never matches.
static func _is_blank_frame(image: Image) -> bool:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return true
	var first := image.get_pixel(0, 0)
	for sample in range(64):
		var probe := image.get_pixel(
			int(float(sample) * float(width) / 64.0) % width,
			int(float(sample) * float(height) / 64.0) % height
		)
		if absf(probe.r - first.r) + absf(probe.g - first.g) + absf(probe.b - first.b) > 0.004:
			return false
	return true


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
	if compression_available:
		if image.compress(Image.COMPRESS_ETC2, Image.COMPRESS_SOURCE_SRGB) == OK:
			return
		compression_available = false
	# Without a compressor, RGB565 is the only saving available at run time:
	# two bytes a pixel against three, and no module required.
	image.convert(Image.FORMAT_RGB565)


## Fetches a box as a grid of sub-requests and stitches them.
##
## Two limits make this necessary. NSW SIX refuses anything over 1024 px, and
## Queensland's ImageServer answers 4100 px happily for a 3 km chunk but returns
## HTTP 500 for the whole 50 km corridor -- the cap is on the request, not on the
## ground it covers, so asking for several smaller boxes gets past both.
func fetch_aerial_grid(
	bounds: Dictionary, per_tile_px: int, per_side: int, server: String = "qld", fallback := "qld"
) -> ImageTexture:
	var mosaic := await fetch_aerial_mosaic(bounds, per_tile_px, per_side, server, fallback)
	if mosaic == null:
		return null
	return await _texture_from(mosaic)


## Grid stitch without the upload, for the paced detail pipeline.
func fetch_aerial_mosaic(
	bounds: Dictionary, per_tile_px: int, per_side: int, server: String = "qld", fallback := "qld"
) -> Image:
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
			var tile := await fetch_aerial_image(cell, per_tile_px, server, fallback)
			if tile == null:
				return null
			tile = tile.duplicate()
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
	return mosaic
