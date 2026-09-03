extends RefCounted

# Collision representation for the OSM buildings that BuildingMesh batches into
# an ArrayMesh per terrain chunk. The render side stays batched; nothing here
# creates a StaticBody3D, so a chunk's footprints cost a dictionary each instead
# of a physics node each (spec section 20).
#
# Buildings stream: streamed_terrain.gd loads a chunk's footprints when it goes
# detailed and drops them when it falls behind, so this mirrors that lifecycle
# rather than indexing a region in one shot. Base heights come from the same
# sample_mesh_height callable BuildingMesh used, or the facade the round strikes
# would not be the facade the player sees.

const SURFACES := preload("res://scripts/world/surface_types.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")

const CELL_SIZE := 200.0

# Handle -> building. A dictionary rather than an array because chunks are
# released out of order and stable handles keep the cell lists valid.
var buildings: Dictionary = {}

var _cells: Dictionary = {}
var _chunk_handles: Dictionary = {}
var _next_handle := 1


func building_count() -> int:
	return buildings.size()


func has_chunk(chunk_key: int) -> bool:
	return _chunk_handles.has(chunk_key)


func clear() -> void:
	buildings.clear()
	_cells.clear()
	_chunk_handles.clear()


func remove_chunk(chunk_key: int) -> void:
	if not _chunk_handles.has(chunk_key):
		return
	for handle: int in _chunk_handles[chunk_key]:
		if not buildings.has(handle):
			continue
		_unregister_cells(buildings[handle])
		buildings.erase(handle)
	_chunk_handles.erase(chunk_key)


func add_chunk(chunk_key: int, building_records: Array, height_sampler: Callable) -> void:
	if _chunk_handles.has(chunk_key):
		remove_chunk(chunk_key)
	var handles := PackedInt32Array()
	for index in range(building_records.size()):
		var record: Dictionary = building_records[index]
		var footprint_data: Array = record.get("footprint", [])
		if footprint_data.size() < 3:
			continue
		var footprint := PackedVector2Array()
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for point: Array in footprint_data:
			var vertex := Vector2(float(point[0]), float(point[1]))
			footprint.append(vertex)
			minimum = minimum.min(vertex)
			maximum = maximum.max(vertex)
		var anchor_x := float(record.get("x", 0.0))
		var anchor_z := float(record.get("z", 0.0))
		# Must match procedural_terrain.gd's base exactly or rounds will strike
		# a facade that is not where the player sees it.
		var base_height := float(height_sampler.call(anchor_x, anchor_z))
		var building_height := float(record.get("height", 7.5))
		var handle := _next_handle
		_next_handle += 1
		var building := {
			"id": int(record.get("osm_id", index)),
			"handle": handle,
			"chunk_key": chunk_key,
			"footprint": footprint,
			"base_height": base_height,
			"building_height": building_height,
			"top_height": base_height + building_height,
			"minimum": minimum,
			"maximum": maximum,
			"wall_surface": _wall_surface(building_height),
			"roof_surface": _roof_surface(building_height),
			"damage": 0.0,
		}
		buildings[handle] = building
		handles.append(handle)
		_register_cells(building)
	_chunk_handles[chunk_key] = handles


func query_segment(from: Vector3, to: Vector3) -> RefCounted:
	var nearest: RefCounted = null
	var tested := {}
	for cell in _segment_cells(from, to):
		if not _cells.has(cell):
			continue
		for handle: int in _cells[cell]:
			if tested.has(handle) or not buildings.has(handle):
				continue
			tested[handle] = true
			var candidate := _intersect_building(buildings[handle], from, to)
			if candidate != null and (nearest == null or candidate.t < nearest.t):
				nearest = candidate
	return nearest


func apply_damage(handle: int, amount: float) -> float:
	if not buildings.has(handle):
		return 0.0
	buildings[handle]["damage"] = float(buildings[handle]["damage"]) + amount
	return float(buildings[handle]["damage"])


func _wall_surface(building_height: float) -> int:
	# Towers on the Gold Coast strip are curtain glass; low stock is rendered
	# concrete. Replaced by compiled material data once the world pipeline emits it.
	return SURFACES.Surface.GLASS if building_height >= 45.0 else SURFACES.Surface.CONCRETE


func _roof_surface(building_height: float) -> int:
	return SURFACES.Surface.CONCRETE if building_height >= 18.0 else SURFACES.Surface.ROOF_TILE


func _register_cells(building: Dictionary) -> void:
	var minimum: Vector2 = building["minimum"]
	var maximum: Vector2 = building["maximum"]
	for cell_x in range(int(floor(minimum.x / CELL_SIZE)), int(floor(maximum.x / CELL_SIZE)) + 1):
		for cell_z in range(int(floor(minimum.y / CELL_SIZE)), int(floor(maximum.y / CELL_SIZE)) + 1):
			var key := Vector2i(cell_x, cell_z)
			if not _cells.has(key):
				_cells[key] = PackedInt32Array()
			var occupants: PackedInt32Array = _cells[key]
			occupants.append(int(building["handle"]))
			_cells[key] = occupants


func _unregister_cells(building: Dictionary) -> void:
	var minimum: Vector2 = building["minimum"]
	var maximum: Vector2 = building["maximum"]
	var handle := int(building["handle"])
	for cell_x in range(int(floor(minimum.x / CELL_SIZE)), int(floor(maximum.x / CELL_SIZE)) + 1):
		for cell_z in range(int(floor(minimum.y / CELL_SIZE)), int(floor(maximum.y / CELL_SIZE)) + 1):
			var key := Vector2i(cell_x, cell_z)
			if not _cells.has(key):
				continue
			var occupants: PackedInt32Array = _cells[key]
			var at := occupants.find(handle)
			if at >= 0:
				occupants.remove_at(at)
			if occupants.is_empty():
				_cells.erase(key)
			else:
				_cells[key] = occupants


func _segment_cells(from: Vector3, to: Vector3) -> Array[Vector2i]:
	# Projectile segments are one simulation step long (~16 m at 805 m/s), so a
	# bounding-box sweep touches one or two cells and needs no DDA.
	var cells: Array[Vector2i] = []
	var min_x := int(floor(minf(from.x, to.x) / CELL_SIZE))
	var max_x := int(floor(maxf(from.x, to.x) / CELL_SIZE))
	var min_z := int(floor(minf(from.z, to.z) / CELL_SIZE))
	var max_z := int(floor(maxf(from.z, to.z) / CELL_SIZE))
	for cell_x in range(min_x, max_x + 1):
		for cell_z in range(min_z, max_z + 1):
			cells.append(Vector2i(cell_x, cell_z))
	return cells


func _intersect_building(building: Dictionary, from: Vector3, to: Vector3) -> RefCounted:
	var base_height: float = building["base_height"]
	var top_height: float = building["top_height"]
	if minf(from.y, to.y) > top_height or maxf(from.y, to.y) < base_height:
		return null
	var minimum: Vector2 = building["minimum"]
	var maximum: Vector2 = building["maximum"]
	if maxf(from.x, to.x) < minimum.x or minf(from.x, to.x) > maximum.x:
		return null
	if maxf(from.z, to.z) < minimum.y or minf(from.z, to.z) > maximum.y:
		return null

	var footprint: PackedVector2Array = building["footprint"]
	var best_t := INF
	var best_normal := Vector3.UP
	var best_zone := ""
	var best_wall := -1

	# Roof plane.
	var height_delta := to.y - from.y
	if absf(height_delta) > 0.0000001:
		var roof_t := (top_height - from.y) / height_delta
		if roof_t >= 0.0 and roof_t <= 1.0:
			var roof_point := from.lerp(to, roof_t)
			if _point_in_polygon(Vector2(roof_point.x, roof_point.z), footprint):
				best_t = roof_t
				best_normal = Vector3.UP
				best_zone = "roof"

	# Vertical walls, one extruded quad per footprint edge.
	var from_flat := Vector2(from.x, from.z)
	var to_flat := Vector2(to.x, to.z)
	for edge_index in range(footprint.size()):
		var a := footprint[edge_index]
		var b := footprint[(edge_index + 1) % footprint.size()]
		var wall_t := _segment_parameter(from_flat, to_flat, a, b)
		if wall_t < 0.0 or wall_t > 1.0 or wall_t >= best_t:
			continue
		var wall_y := from.y + height_delta * wall_t
		if wall_y < base_height or wall_y > top_height:
			continue
		var edge := b - a
		# Matches the facade normal procedural_terrain.gd hands the renderer.
		var normal := Vector3(edge.y, 0.0, -edge.x).normalized()
		if normal.dot(to - from) > 0.0:
			normal = -normal
		best_t = wall_t
		best_normal = normal
		best_zone = "wall"
		best_wall = edge_index

	if best_t > 1.0:
		return null

	var result: RefCounted = HIT.new()
	result.hit = true
	result.t = best_t
	result.position = from.lerp(to, best_t)
	result.normal = best_normal
	result.distance = from.distance_to(result.position)
	result.object_type = HIT.ObjectKind.BUILDING
	# object_id is the index handle (stable, survives streaming); building_id is
	# the OSM id the damage system and any future save data care about.
	result.object_id = int(building["handle"])
	result.building_id = int(building["id"])
	result.hit_zone = best_zone
	result.wall_index = best_wall
	result.surface_type = int(building["roof_surface"] if best_zone == "roof" else building["wall_surface"])
	var building_height: float = building["building_height"]
	result.relative_height = clampf(
		(result.position.y - base_height) / maxf(building_height, 0.001), 0.0, 1.0
	)
	return result


func _segment_parameter(from: Vector2, to: Vector2, edge_a: Vector2, edge_b: Vector2) -> float:
	# Returns how far along `from -> to` the wall edge is crossed, or -1.
	var ray := to - from
	var edge := edge_b - edge_a
	var denominator := ray.cross(edge)
	if absf(denominator) < 0.0000001:
		return -1.0
	var offset := edge_a - from
	var ray_t := offset.cross(edge) / denominator
	var edge_t := offset.cross(ray) / denominator
	if edge_t < 0.0 or edge_t > 1.0:
		return -1.0
	return ray_t


func _point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	var inside := false
	var count := polygon.size()
	var previous := count - 1
	for current in range(count):
		var a := polygon[current]
		var b := polygon[previous]
		if (a.y > point.y) != (b.y > point.y):
			var crossing := (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
			if point.x < crossing:
				inside = not inside
		previous = current
	return inside


## Every building whose footprint centre lies within `radius` of `centre`, with
## its height. Drones choose attack targets from this; the cell grid is not
## used because a 2.5 km entry range spans most of the city anyway and a plain
## scan of a few hundred records is cheaper than assembling cell lists.
func buildings_near(centre: Vector2, radius: float) -> Array:
	var found: Array = []
	var radius_squared := radius * radius
	for handle in buildings:
		var building: Dictionary = buildings[handle]
		var footprint_centre: Vector2 = (building["minimum"] + building["maximum"]) * 0.5
		if footprint_centre.distance_squared_to(centre) > radius_squared:
			continue
		found.append({
			"handle": int(handle),
			"position": Vector3(footprint_centre.x, float(building["top_height"]), footprint_centre.y),
			"height": float(building["building_height"]),
		})
	return found
