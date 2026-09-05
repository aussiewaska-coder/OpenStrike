extends Node3D
## Terrain for a theatre far too large to hold as a single texture.
##
## The elevation grid for the whole region is small enough to keep resident
## (~42 Terrarium tiles for 50 km), so it is fetched once and every height
## query reads from it. Imagery is the opposite problem: 50 km of 10 cm aerial
## would be a 500,000 px image, so the region is split into a grid of chunks
## and only the chunks near the aircraft carry a detailed texture. Everything
## else shows a single region-wide overview until it is flown near.

signal status_changed(message: String)
signal region_ready()
## Mirrors the batched building mesh for collision. The renderer keeps its
## ArrayMesh; the cannon gets footprints it can intersect mathematically.
signal chunk_buildings_ready(chunk_key: int, records: Array, ground_height: Callable)
signal chunk_buildings_released(chunk_key: int)

const BUILDING_CHUNK_LAYOUT := preload("res://scripts/terrain/building_chunk_layout.gd")

## Chunks per side. Ground resolution is set by how much ground one texture has
## to cover, not by the texture size alone: at 12 the corridor's chunks were
## 3 km wide and 2048 px bought only 1.46 m/px. Twenty 2.5 km chunks keep the
## 50 km theatre within a 400-mesh mobile budget while retaining 1.22 m/px.
@export var chunk_count := 20
@export var chunk_resolution := 33         ## vertices per chunk edge
@export var elevation_zoom := 12           ## Terrarium zoom; 12 is ~34 m/px, SRTM's native scale
@export var heightfield_resolution := 513
## Box-blur passes over the elevation grid. Terrarium reads rooftops as ground,
## so a built-up theatre needs a couple; open country needs none.
@export var elevation_smoothing := 0
## The overview is stitched rather than asked for in one piece: Queensland's
## ImageServer answers 4100 px for a chunk but 500s for a 50 km extent.
@export var overview_texture_px := 2048
@export var overview_grid_per_side := 2
@export var detail_texture_px := 2048
## The chunks right under the aircraft carry twice the detail of the rest.
## Compression is what makes the difference affordable: 4096 px costs about
## 10 MB compressed against 64 MB raw.
@export var near_detail_texture_px := 4096
@export var near_detail_chunks := 3
## At speed, reserve the expensive near tier for the chunk directly underneath.
## Low-speed flight can keep the wider patch sharp.
@export var near_detail_speed_limit := 45.0
@export var near_detail_altitude_m := 300.0
var _low_detail_altitude := false
var _fast_detail_motion := false
@export var detail_radius_m := 6000.0
@export var max_detail_chunks := 16
@export var detail_update_interval_s := 0.6
## Requests are serialised through one HTTPRequest, so queueing a dozen only
## makes the last of them arrive a dozen fetches late -- by which time the
## aircraft has moved on. Ask for a few and re-rank as they land.
@export var max_pending_detail := 3

var _height_image: Image
var _metadata: Dictionary = {}
var _bounds: Dictionary = {}
## World XZ of every hero tower in the loaded region. BuildingMesh hides the
## OSM box under each; the hit index keeps it, so rounds still strike there.
var hero_suppress := PackedVector2Array()
var _chunks: Array = []
var _overview_texture: ImageTexture
var _focus: Node3D
var _update_accumulator := 0.0
var _pending_detail := {}
var _pending_buildings := {}
var _buildings_dir := ""
var _building_world_size_m := 0.0
var _building_chunk_count := 0


func _ready() -> void:
	set_process(false)


func set_focus(node: Node3D) -> void:
	_focus = node
	set_process(node != null)


## Streams a region described by a catalog entry. Awaits the network, so
## callers must await this too.
func load_region(region: Dictionary) -> bool:
	_clear_terrain()
	var region_id := String(region.get("id", "region"))
	var world_size := float(region.get("world_size_m", 50000.0))
	# A theatre may set its own grid: ground resolution depends on how much
	# ground one chunk texture covers, so a small area wants more, finer chunks
	# than the 50 km corridor does.
	chunk_count = int(region.get("chunk_count", chunk_count))
	heightfield_resolution = int(region.get("heightfield_resolution", heightfield_resolution))
	elevation_smoothing = int(region.get("elevation_smoothing", elevation_smoothing))
	var center_latitude := float(region.get("center_latitude", 0.0))
	var center_longitude := float(region.get("center_longitude", 0.0))
	_bounds = MapTiles.region_bounds(center_latitude, center_longitude, world_size)
	# Computed here, the moment the bounds exist, so no building chunk can
	# build before it knows which boxes a hero tower hides.
	hero_suppress = HeroTowers.suppress_points(
		String(region.get("id", "")),
		func(lat: float, lon: float) -> Vector2: return MapTiles.world_of(_bounds, lat, lon, world_size)
	)
	elevation_zoom = int(region.get("elevation_zoom", elevation_zoom))
	_buildings_dir = String(region.get("buildings_dir", ""))
	_building_world_size_m = float(region.get("building_world_size_m", world_size))
	_building_chunk_count = int(region.get("building_chunk_count", chunk_count))

	status_changed.emit("Streaming elevation for %s..." % region.get("display_name", region_id))
	TileClient.load_progress.connect(_on_tile_progress)
	var field: Dictionary = await TileClient.fetch_heightfield(
		region_id, _bounds, elevation_zoom, heightfield_resolution, elevation_smoothing
	)
	TileClient.load_progress.disconnect(_on_tile_progress)
	if field.is_empty():
		status_changed.emit("Elevation could not be streamed. Check the network and retry.")
		return false

	_height_image = field["image"]
	_metadata = {
		"world_size_m": world_size,
		"elevation_min_m": float(field["elevation_min_m"]),
		"elevation_max_m": float(field["elevation_max_m"]),
		"vertical_exaggeration": float(region.get("vertical_exaggeration", 1.0)),
	}

	status_changed.emit("Streaming overview imagery...")
	_overview_texture = await TileClient.fetch_aerial_grid(
		_bounds,
		overview_texture_px,
		overview_grid_per_side,
		String(region.get("imagery_server", "qld"))
	)

	status_changed.emit("Building terrain...")
	await _build_chunks(world_size)
	status_changed.emit("Theatre ready: %.0f km across, %.0f m of relief." % [
		world_size / 1000.0,
		(_metadata["elevation_max_m"] - _metadata["elevation_min_m"])
			* _metadata["vertical_exaggeration"],
	])
	region_ready.emit()
	return true


## Half the region's width, which is how far the aircraft may fly from the
## centre. Theatres differ by an order of magnitude, so nothing downstream may
## assume a size.
## A real coordinate as world metres, the way the spawn point is placed.
func world_from_coordinate(latitude: float, longitude: float) -> Vector2:
	return MapTiles.world_of(_bounds, latitude, longitude, float(_metadata.get("world_size_m", 50000.0)))


func world_half_extent() -> float:
	return float(_metadata.get("world_size_m", 50000.0)) * 0.5


func sample_height_world(world_x: float, world_z: float) -> float:
	return HeightField.sample(_height_image, _metadata, world_x, world_z)


## Height of the rendered triangle surface at a world position.
##
## sample_height_world() reads the heightfield bilinearly, but the mesh only
## carries a vertex every chunk_size/(chunk_resolution - 1) metres and
## interpolates linearly between them. Seating buildings on the bilinear value
## leaves them floating or buried wherever the two disagree: measured across the
## corridor's real footprints that is 0.4 m typically, 3.8 m at the 99th
## percentile and 35 m at worst. Sampling the surface the mesh actually draws
## makes the discrepancy zero by construction, with no extra vertices -- a
## denser mesh only shrinks the error, it never removes it.
func sample_mesh_height(world_x: float, world_z: float) -> float:
	if _chunks.is_empty():
		return sample_height_world(world_x, world_z)
	var world_size := float(_metadata.get("world_size_m", 50000.0))
	var chunk_size := world_size / float(chunk_count)
	var spacing := chunk_size / float(chunk_resolution - 1)
	var half := world_size * 0.5
	var cx: int = clampi(int((world_x + half) / chunk_size), 0, chunk_count - 1)
	var cz: int = clampi(int((world_z + half) / chunk_size), 0, chunk_count - 1)
	var origin_x := -half + float(cx) * chunk_size
	var origin_z := -half + float(cz) * chunk_size
	var fi := (world_x - origin_x) / spacing
	var fj := (world_z - origin_z) / spacing
	var i: int = clampi(int(fi), 0, chunk_resolution - 2)
	var j: int = clampi(int(fj), 0, chunk_resolution - 2)
	var a := fi - float(i)
	var b := fj - float(j)
	var h00 := sample_height_world(origin_x + float(i) * spacing, origin_z + float(j) * spacing)
	var h10 := sample_height_world(origin_x + float(i + 1) * spacing, origin_z + float(j) * spacing)
	var h01 := sample_height_world(origin_x + float(i) * spacing, origin_z + float(j + 1) * spacing)
	var h11 := sample_height_world(origin_x + float(i + 1) * spacing, origin_z + float(j + 1) * spacing)
	# Matches the index buffer's split: (tl, bl, tr) then (tr, bl, br).
	if a + b <= 1.0:
		return h00 + (h10 - h00) * a + (h01 - h00) * b
	return h11 + (h01 - h11) * (1.0 - a) + (h10 - h11) * (1.0 - b)


func get_spawn_position(clearance_m: float = 90.0) -> Vector3:
	var world := _spawn_world_xz()
	return Vector3(world.x, sample_height_world(world.x, world.y) + clearance_m, world.y)


func get_spawn_yaw_degrees(default_yaw: float = -35.0) -> float:
	return float(_metadata.get("spawn_yaw_degrees", default_yaw))


func _spawn_world_xz() -> Vector2:
	var world_size := float(_metadata.get("world_size_m", 50000.0))
	if _metadata.has("spawn_uv"):
		var uv: Vector2 = _metadata["spawn_uv"]
		return Vector2((uv.x - 0.5) * world_size, (uv.y - 0.5) * world_size)
	return Vector2.ZERO


## Places the spawn from a real coordinate rather than world metres, so a
## catalog entry can just name where the flight starts.
func set_spawn_from_coordinate(latitude: float, longitude: float, yaw_degrees: float) -> void:
	_metadata["spawn_uv"] = MapTiles.uv_of(_bounds, latitude, longitude)
	_metadata["spawn_yaw_degrees"] = yaw_degrees


func _build_chunks(world_size: float) -> void:
	var chunk_size := world_size / float(chunk_count)
	var spacing := chunk_size / float(chunk_resolution - 1)
	for cz in range(chunk_count):
		# A row of chunk meshes is built across the worker pool. Built on the
		# main thread this cost 212 to 460 ms a row on device -- the load
		# sequence ran at 3 to 5 frames a second until all 144 were done.
		var row: Array = []
		row.resize(chunk_count)
		var row_origin_z := -world_size * 0.5 + float(cz) * chunk_size
		var group := WorkerThreadPool.add_group_task(
			func(index: int) -> void:
				var task_origin_x := -world_size * 0.5 + float(index) * chunk_size
				row[index] = _build_chunk_surface(task_origin_x, row_origin_z, spacing, world_size),
			chunk_count,
			-1,
			true
		)
		while not WorkerThreadPool.is_group_task_completed(group):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_group_task_completion(group)
		for cx in range(chunk_count):
			var origin_x := -world_size * 0.5 + float(cx) * chunk_size
			var origin_z := row_origin_z
			var mesh := _mesh_from_surface(row[cx])
			var material := ShaderMaterial.new()
			material.shader = TERRAIN_SHADER
			var instance := MeshInstance3D.new()
			instance.name = "Chunk_%d_%d" % [cx, cz]
			instance.mesh = mesh
			instance.material_override = material
			add_child(instance)
			_chunks.append({
				"index": cz * chunk_count + cx,
				"cx": cx,
				"cz": cz,
				"instance": instance,
				"material": material,
				"texture": null,
				"center": Vector2(origin_x + chunk_size * 0.5, origin_z + chunk_size * 0.5),
				"detailed": false,
				"buildings": null,
			})
			_set_chunk_texture(_chunks.back(), _overview_texture, Vector2.ONE, Vector2.ZERO)
		await get_tree().process_frame


## Runs on a worker thread: samples the height field and lays out the surface
## arrays. Only turning those arrays into an ArrayMesh stays on the main thread.
func _build_chunk_surface(
	origin_x: float, origin_z: float, spacing: float, world_size: float
) -> Array:
	var side := chunk_resolution
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	for j in range(side):
		for i in range(side):
			var world_x := origin_x + float(i) * spacing
			var world_z := origin_z + float(j) * spacing
			heights[j * side + i] = sample_height_world(world_x, world_z)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(side * side)
	normals.resize(side * side)
	uvs.resize(side * side)
	for j in range(side):
		for i in range(side):
			var index := j * side + i
			var world_x := origin_x + float(i) * spacing
			var world_z := origin_z + float(j) * spacing
			vertices[index] = Vector3(world_x, heights[index], world_z)
			# Region-wide UV. A chunk that later gains its own texture reuses
			# these coordinates via the material's uv1 scale/offset.
			uvs[index] = Vector2(world_x / world_size + 0.5, world_z / world_size + 0.5)
			# Central differences over the chunk's own grid: no extra sampling.
			var west := heights[j * side + maxi(i - 1, 0)]
			var east := heights[j * side + mini(i + 1, side - 1)]
			var north := heights[maxi(j - 1, 0) * side + i]
			var south := heights[mini(j + 1, side - 1) * side + i]
			normals[index] = Vector3(west - east, 2.0 * spacing, north - south).normalized()

	var indices := PackedInt32Array()
	for j in range(side - 1):
		for i in range(side - 1):
			var top_left := j * side + i
			var top_right := top_left + 1
			var bottom_left := (j + 1) * side + i
			var bottom_right := bottom_left + 1
			indices.append_array([top_left, bottom_left, top_right, top_right, bottom_left, bottom_right])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _mesh_from_surface(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if arrays.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _process(delta: float) -> void:
	if _chunks.is_empty() or _focus == null:
		return
	_update_accumulator += delta
	if _update_accumulator < detail_update_interval_s:
		return
	_update_accumulator = 0.0
	_refresh_detail_chunks()


## What the streamer is actually doing, for the on-screen diagnostic: guessing
## at this from outside the device is how three rounds of "improvements" went
## unnoticed.
func detail_report(focus_position: Vector3) -> Dictionary:
	var world_size := float(_metadata.get("world_size_m", 0.0))
	var chunk_metres := world_size / float(maxi(chunk_count, 1))
	var detailed := 0
	var under_px := 0
	var under_detailed := false
	for chunk in _chunks:
		if chunk["detailed"]:
			detailed += 1
	var half := world_size * 0.5
	if world_size > 0.0:
		var cx: int = clampi(int((focus_position.x + half) / chunk_metres), 0, chunk_count - 1)
		var cz: int = clampi(int((focus_position.z + half) / chunk_metres), 0, chunk_count - 1)
		for chunk in _chunks:
			if int(chunk["cx"]) == cx and int(chunk["cz"]) == cz:
				under_detailed = bool(chunk["detailed"])
				if chunk["texture"] != null:
					under_px = chunk["texture"].get_width()
				break
	return {
		"chunk_metres": chunk_metres,
		"chunks": _chunks.size(),
		"detailed": detailed,
		"pending": _pending_detail.size(),
		"under_detailed": under_detailed,
		"under_px": under_px,
	}


## Three points on the trade between texture load and frame rate. Guessing at
## this from off-device is what cost the last few rounds, so it is a control
## rather than a constant.
enum Quality {PERFORMANCE, BALANCED, QUALITY}

var quality: Quality = Quality.BALANCED
## One shader for every chunk: the photo, tinted, shadowed by clouds, with
## the sea and the night lights painted in (see terrain_imagery.gdshader).
const TERRAIN_SHADER := preload("res://shaders/terrain_imagery.gdshader")


func set_quality(level: Quality) -> void:
	quality = level
	match level:
		Quality.PERFORMANCE:
			near_detail_chunks = 0
			max_detail_chunks = 10
			detail_texture_px = 2048
			near_detail_texture_px = 2048
		Quality.QUALITY:
			near_detail_chunks = 6
			max_detail_chunks = 24
			detail_texture_px = 2048
			near_detail_texture_px = 4096
		_:
			near_detail_chunks = 3
			max_detail_chunks = 16
			detail_texture_px = 2048
			near_detail_texture_px = 4096
	_apply_memory_budget()
	_refresh_detail_chunks()


## A 2048 px chunk is 2 MB compressed and 16.7 MB not. Without a compressor the
## same settings cost eight times the memory, so the resident set and the near
## tier have to come down to stay inside a phone's budget.
func _apply_memory_budget() -> void:
	if TileClient.compression_available:
		return
	# Measured on device: 317 MB of texture stuttered badly, 104 MB held 111
	# frames a second. 2048 px everywhere with ten chunks resident lands near
	# 150 MB, which spends the headroom between those two on detail rather than
	# leaving it unused. 4096 px is out without a compressor -- one such texture
	# alone is 45 MB.
	near_detail_texture_px = mini(near_detail_texture_px, 2048)
	detail_texture_px = mini(detail_texture_px, 2048)
	max_detail_chunks = mini(max_detail_chunks, 10)
	near_detail_chunks = mini(near_detail_chunks, 2)


## Points a chunk's shader at a texture, with the uv window a detail texture
## needs when it covers several chunks.
func _set_chunk_texture(chunk: Dictionary, texture: Texture2D, uv_scale: Vector2, uv_offset: Vector2) -> void:
	chunk["texture"] = texture
	var material: ShaderMaterial = chunk["material"]
	material.set_shader_parameter("imagery", texture)
	material.set_shader_parameter("has_imagery", texture != null)
	material.set_shader_parameter("uv_scale", uv_scale)
	material.set_shader_parameter("uv_offset", uv_offset)


func quality_name() -> String:
	return Quality.keys()[quality]


func _focus_speed() -> float:
	if _focus == null or not ("velocity" in _focus):
		return 0.0
	var velocity: Vector3 = _focus.velocity
	return Vector2(velocity.x, velocity.z).length()


func _refresh_detail_chunks() -> void:
	var focus_xz := Vector2(_focus.global_position.x, _focus.global_position.z)
	var ranked: Array = []
	for chunk in _chunks:
		var distance: float = focus_xz.distance_to(chunk["center"])
		if distance <= detail_radius_m:
			ranked.append({"chunk": chunk, "distance": distance})
	ranked.sort_custom(func(a, b): return a["distance"] < b["distance"])
	_apply_memory_budget()
	var wanted := ranked.slice(0, max_detail_chunks)
	# Rank decides resolution: the nearest few get the high tier, the rest the
	# standard one, and a chunk that changes tier is re-fetched.
	var agl := _focus.global_position.y - sample_height_world(_focus.global_position.x, _focus.global_position.z)
	_low_detail_altitude = agl < near_detail_altitude_m + (30.0 if _low_detail_altitude else 0.0)
	_fast_detail_motion = _focus_speed() > near_detail_speed_limit - (5.0 if _fast_detail_motion else 0.0)
	var moving_fast := _fast_detail_motion
	var near_count := mini(near_detail_chunks, 1) if moving_fast else near_detail_chunks
	for position in range(wanted.size()):
		var high_tier: bool = position < near_count and _low_detail_altitude
		wanted[position]["tier"] = near_detail_texture_px if high_tier else detail_texture_px

	var keep := {}
	for entry in wanted:
		keep[int(entry["chunk"]["index"])] = true
	# Drop detail that has fallen behind so texture memory stays bounded.
	for chunk in _chunks:
		if chunk["detailed"] and not keep.has(int(chunk["index"])):
			_set_chunk_texture(chunk, _overview_texture, Vector2.ONE, Vector2.ZERO)
			chunk["detailed"] = false
			_release_chunk_buildings(chunk)
	for entry in wanted:
		var chunk: Dictionary = entry["chunk"]
		var tier: int = int(entry["tier"])
		_ensure_chunk_buildings(chunk)
		if _pending_detail.has(int(chunk["index"])):
			continue
		if _pending_detail.size() >= max_pending_detail:
			break
		if chunk["detailed"] and int(chunk.get("tier", 0)) == tier:
			continue
		_request_chunk_detail(chunk, tier)


func _request_chunk_detail(chunk: Dictionary, tier_px: int = 0) -> void:
	var key := int(chunk["index"])
	_pending_detail[key] = true
	var cx: int = chunk["cx"]
	var cz: int = chunk["cz"]
	var north := lerpf(float(_bounds["north"]), float(_bounds["south"]), float(cz) / float(chunk_count))
	var south := lerpf(float(_bounds["north"]), float(_bounds["south"]), float(cz + 1) / float(chunk_count))
	var west := lerpf(float(_bounds["west"]), float(_bounds["east"]), float(cx) / float(chunk_count))
	var east := lerpf(float(_bounds["west"]), float(_bounds["east"]), float(cx + 1) / float(chunk_count))
	var requested_px: int = tier_px if tier_px > 0 else detail_texture_px
	var texture: ImageTexture = await TileClient.fetch_aerial(
		{"north": north, "south": south, "west": west, "east": east}, requested_px
	)
	_pending_detail.erase(key)
	if texture == null or not is_instance_valid(chunk["instance"]):
		return
	_set_chunk_texture(chunk, texture, Vector2(float(chunk_count), float(chunk_count)), Vector2(-float(cx), -float(cz)))
	# Stretch this chunk's slice of the region-wide UV back over 0..1.
	chunk["detailed"] = true
	chunk["tier"] = requested_px


## Buildings ship in the APK per chunk, so this needs no network -- it is the
## imagery that streams. One chunk is a few hundred footprints, cheap enough to
## build in place rather than spread over frames.
## Parsing a chunk's buildings and extruding them is heavy -- the busiest chunk
## here carries 171 footprints, each triangulated and walled -- and on the main
## thread it stalls the frame just as the chunk comes into range. It runs on a
## worker; only adding the finished mesh to the tree stays on the main thread.
func _ensure_chunk_buildings(chunk: Dictionary) -> void:
	if _buildings_dir.is_empty() or chunk["buildings"] != null:
		return
	var key := int(chunk["index"])
	if _pending_buildings.has(key):
		return
	var bounds := _terrain_chunk_bounds(int(chunk["cx"]), int(chunk["cz"]))
	var paths := _building_chunk_paths(bounds)
	if paths.is_empty():
		return
	_pending_buildings[key] = true
	var result := {"mesh": null, "records": []}
	var task := WorkerThreadPool.add_task(_build_buildings.bind(paths, bounds, result), true)
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_pending_buildings.erase(key)
	var mesh: ArrayMesh = result["mesh"]
	# The chunk may have fallen out of range, or been released, while this ran.
	if mesh == null or chunk["buildings"] != null or not chunk["detailed"]:
		return
	var instance := MeshInstance3D.new()
	instance.name = "Buildings_%d_%d" % [int(chunk["cx"]), int(chunk["cz"])]
	instance.mesh = mesh
	add_child(instance)
	chunk["buildings"] = instance
	chunk_buildings_ready.emit(key, result.get("records", []), sample_mesh_height)


## A coarse terrain chunk can overlap several files from the original denser
## building grid. The records keep world coordinates, so they can be regrouped
## at load without regenerating the packaged OSM extract.
func _building_chunk_paths(bounds: Rect2) -> Array[String]:
	var paths: Array[String] = []
	for source in BUILDING_CHUNK_LAYOUT.source_chunks_for_bounds(
		bounds,
		_building_world_size_m,
		_building_chunk_count
	):
		var path := BUILDING_CHUNK_LAYOUT.path_for(_buildings_dir, source, Vector2i.ZERO)
		if FileAccess.file_exists(path):
			paths.append(path)
	return paths


func _terrain_chunk_bounds(cx: int, cz: int) -> Rect2:
	var world_size := float(_metadata.get("world_size_m", 0.0))
	var size := world_size / float(maxi(chunk_count, 1))
	var half := world_size * 0.5
	return Rect2(Vector2(-half + cx * size, -half + cz * size), Vector2.ONE * size)


## Runs on a worker thread.
func _build_buildings(paths: Array[String], bounds: Rect2, result: Dictionary) -> void:
	var records: Array = []
	for path in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("Chunk building data is invalid: %s" % path)
			continue
		for record in (parsed as Dictionary).get("buildings", []):
			var point := Vector2(float(record.get("x", 0.0)), float(record.get("z", 0.0)))
			if bounds.has_point(point):
				records.append(record)
	result["records"] = records
	result["mesh"] = BuildingMesh.build(records, sample_mesh_height, hero_suppress, HeroTowers.SUPPRESS_RADIUS_M)


func _release_chunk_buildings(chunk: Dictionary) -> void:
	if chunk["buildings"] != null:
		if is_instance_valid(chunk["buildings"]):
			chunk["buildings"].queue_free()
		chunk["buildings"] = null
		chunk_buildings_released.emit(int(chunk["index"]))


func _on_tile_progress(done: int, total: int, message: String) -> void:
	status_changed.emit("%s (%d/%d)" % [message, done, total])


func _clear_terrain() -> void:
	for chunk in _chunks:
		_release_chunk_buildings(chunk)
		if is_instance_valid(chunk["instance"]):
			chunk["instance"].queue_free()
	_chunks.clear()
	_pending_detail.clear()
	_height_image = null
	_metadata = {}
	_bounds = {}
	hero_suppress = PackedVector2Array()
	_overview_texture = null
	_building_world_size_m = 0.0
	_building_chunk_count = 0


## Shared texture references: the MFD does not duplicate or download imagery.
func tactical_map_layers() -> Dictionary:
	var details := []
	for chunk in _chunks:
		if chunk.get("texture") != null and chunk.texture != _overview_texture:
			details.append({"bounds": _terrain_chunk_bounds(int(chunk.cx), int(chunk.cz)), "texture": chunk.texture})
	return {"world_size_m": float(_metadata.get("world_size_m", 50000.0)), "height": _height_image, "metadata": _metadata, "aerial": _overview_texture, "details": details}
