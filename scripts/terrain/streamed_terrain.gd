extends Node3D
## Terrain for a theatre far too large to hold as a single texture.
##
## The elevation grid for the whole region is small enough to keep resident
## (~24 Terrarium tiles for 36 km), so it is fetched once and every height
## query reads from it. Imagery is the opposite problem: 36 km of 10 cm aerial
## would be a 360,000 px image, so the region is split into a grid of chunks
## and only the chunks near the aircraft carry a detailed texture. Everything
## else shows a single region-wide overview until it is flown near.

signal status_changed(message: String)
signal region_ready()

## Chunks per side. Ground resolution is set by how much ground one texture has
## to cover, not by the texture size alone: at 12 the corridor's chunks were
## 3 km wide and 2048 px bought only 1.46 m/px. At 24 they are 1.5 km, so the
## same request buys twice the detail, and the near tier four times.
@export var chunk_count := 24
@export var chunk_resolution := 33         ## vertices per chunk edge
@export var elevation_zoom := 12           ## Terrarium zoom; 12 is ~34 m/px, SRTM's native scale
@export var heightfield_resolution := 513
## The overview is stitched rather than asked for in one piece: Queensland's
## ImageServer answers 4100 px for a chunk but 500s for a 36 km extent.
@export var overview_texture_px := 2048
@export var overview_grid_per_side := 2
@export var detail_texture_px := 2048
## The chunks right under the aircraft carry twice the detail of the rest.
## Compression is what makes the difference affordable: 4096 px costs about
## 10 MB compressed against 64 MB raw.
@export var near_detail_texture_px := 4096
@export var near_detail_chunks := 6
@export var detail_radius_m := 6000.0
@export var max_detail_chunks := 24
@export var detail_update_interval_s := 0.6

var _height_image: Image
var _metadata: Dictionary = {}
var _bounds: Dictionary = {}
var _chunks: Array = []
var _overview_texture: ImageTexture
var _focus: Node3D
var _update_accumulator := 0.0
var _pending_detail := {}
var _buildings_dir := ""


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
	var world_size := float(region.get("world_size_m", 36000.0))
	# A theatre may set its own grid: ground resolution depends on how much
	# ground one chunk texture covers, so a small area wants more, finer chunks
	# than the 36 km corridor does.
	chunk_count = int(region.get("chunk_count", chunk_count))
	var center_latitude := float(region.get("center_latitude", 0.0))
	var center_longitude := float(region.get("center_longitude", 0.0))
	_bounds = MapTiles.region_bounds(center_latitude, center_longitude, world_size)
	elevation_zoom = int(region.get("elevation_zoom", elevation_zoom))
	_buildings_dir = String(region.get("buildings_dir", ""))

	status_changed.emit("Streaming elevation for %s..." % region.get("display_name", region_id))
	TileClient.load_progress.connect(_on_tile_progress)
	var field: Dictionary = await TileClient.fetch_heightfield(
		region_id, _bounds, elevation_zoom, heightfield_resolution
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
		_metadata["elevation_max_m"] - _metadata["elevation_min_m"],
	])
	region_ready.emit()
	return true


## Half the region's width, which is how far the aircraft may fly from the
## centre. Theatres differ by an order of magnitude, so nothing downstream may
## assume a size.
func world_half_extent() -> float:
	return float(_metadata.get("world_size_m", 36000.0)) * 0.5


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
	var world_size := float(_metadata.get("world_size_m", 36000.0))
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
	var world_size := float(_metadata.get("world_size_m", 36000.0))
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
		for cx in range(chunk_count):
			var origin_x := -world_size * 0.5 + float(cx) * chunk_size
			var origin_z := -world_size * 0.5 + float(cz) * chunk_size
			var mesh := _build_chunk_mesh(origin_x, origin_z, chunk_size, spacing, world_size)
			var material := StandardMaterial3D.new()
			material.albedo_texture = _overview_texture
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
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
				"center": Vector2(origin_x + chunk_size * 0.5, origin_z + chunk_size * 0.5),
				"detailed": false,
				"buildings": null,
			})
		# Yield a frame per row so a 144-chunk build cannot trip Android's ANR.
		await get_tree().process_frame


func _build_chunk_mesh(
	origin_x: float, origin_z: float, chunk_size: float, spacing: float, world_size: float
) -> ArrayMesh:
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
	var mesh := ArrayMesh.new()
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
				var material: StandardMaterial3D = chunk["material"]
				if material != null and material.albedo_texture != null:
					under_px = material.albedo_texture.get_width()
				break
	return {
		"chunk_metres": chunk_metres,
		"chunks": _chunks.size(),
		"detailed": detailed,
		"pending": _pending_detail.size(),
		"under_detailed": under_detailed,
		"under_px": under_px,
	}


func _refresh_detail_chunks() -> void:
	var focus_xz := Vector2(_focus.global_position.x, _focus.global_position.z)
	var ranked: Array = []
	for chunk in _chunks:
		var distance: float = focus_xz.distance_to(chunk["center"])
		if distance <= detail_radius_m:
			ranked.append({"chunk": chunk, "distance": distance})
	ranked.sort_custom(func(a, b): return a["distance"] < b["distance"])
	var wanted := ranked.slice(0, max_detail_chunks)
	# Rank decides resolution: the nearest few get the high tier, the rest the
	# standard one, and a chunk that changes tier is re-fetched.
	for position in range(wanted.size()):
		var tier_px: int = near_detail_texture_px if position < near_detail_chunks else detail_texture_px
		wanted[position]["tier"] = tier_px

	var keep := {}
	for entry in wanted:
		keep[int(entry["chunk"]["index"])] = true
	# Drop detail that has fallen behind so texture memory stays bounded.
	for chunk in _chunks:
		if chunk["detailed"] and not keep.has(int(chunk["index"])):
			chunk["material"].albedo_texture = _overview_texture
			chunk["material"].uv1_scale = Vector3.ONE
			chunk["material"].uv1_offset = Vector3.ZERO
			chunk["detailed"] = false
			_release_chunk_buildings(chunk)
	for entry in wanted:
		var chunk: Dictionary = entry["chunk"]
		var tier: int = int(entry["tier"])
		_ensure_chunk_buildings(chunk)
		if _pending_detail.has(int(chunk["index"])):
			continue
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
	chunk["tier"] = requested_px
	var texture: ImageTexture = await TileClient.fetch_aerial(
		{"north": north, "south": south, "west": west, "east": east}, requested_px
	)
	_pending_detail.erase(key)
	if texture == null or not is_instance_valid(chunk["instance"]):
		return
	chunk["material"].albedo_texture = texture
	# Stretch this chunk's slice of the region-wide UV back over 0..1.
	chunk["material"].uv1_scale = Vector3(float(chunk_count), float(chunk_count), 1.0)
	chunk["material"].uv1_offset = Vector3(-float(cx), -float(cz), 0.0)
	chunk["detailed"] = true


## Buildings ship in the APK per chunk, so this needs no network -- it is the
## imagery that streams. One chunk is a few hundred footprints, cheap enough to
## build in place rather than spread over frames.
func _ensure_chunk_buildings(chunk: Dictionary) -> void:
	if _buildings_dir.is_empty() or chunk["buildings"] != null:
		return
	var path := "%s/%d_%d.json" % [_buildings_dir, int(chunk["cx"]), int(chunk["cz"])]
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Chunk building data is invalid: %s" % path)
		return
	var mesh := BuildingMesh.build((parsed as Dictionary).get("buildings", []), sample_mesh_height)
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.name = "Buildings_%d_%d" % [int(chunk["cx"]), int(chunk["cz"])]
	instance.mesh = mesh
	add_child(instance)
	chunk["buildings"] = instance


func _release_chunk_buildings(chunk: Dictionary) -> void:
	if chunk["buildings"] != null:
		if is_instance_valid(chunk["buildings"]):
			chunk["buildings"].queue_free()
		chunk["buildings"] = null


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
	_overview_texture = null
