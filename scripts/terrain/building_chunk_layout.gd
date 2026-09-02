class_name BuildingChunkLayout
extends RefCounted


static func source_chunk(terrain_chunk: Vector2i, offset: Vector2i) -> Vector2i:
	return terrain_chunk - offset


static func path_for(directory: String, terrain_chunk: Vector2i, offset: Vector2i) -> String:
	var source := source_chunk(terrain_chunk, offset)
	if directory.is_empty() or source.x < 0 or source.y < 0:
		return ""
	return "%s/%d_%d.json" % [directory, source.x, source.y]


## Source building grids can cover a smaller, denser area than the terrain.
## Returns every source file overlapping one terrain chunk's world-space bounds.
static func source_chunks_for_bounds(
	bounds: Rect2,
	source_world_size: float,
	source_chunk_count: int
) -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []
	if source_world_size <= 0.0 or source_chunk_count <= 0:
		return chunks
	var half := source_world_size * 0.5
	var clipped_start := Vector2(
		maxf(bounds.position.x, -half),
		maxf(bounds.position.y, -half)
	)
	var clipped_end := Vector2(
		minf(bounds.end.x, half),
		minf(bounds.end.y, half)
	)
	if clipped_start.x >= clipped_end.x or clipped_start.y >= clipped_end.y:
		return chunks
	var size := source_world_size / float(source_chunk_count)
	var first := Vector2i(
		clampi(int(floor((clipped_start.x + half) / size)), 0, source_chunk_count - 1),
		clampi(int(floor((clipped_start.y + half) / size)), 0, source_chunk_count - 1)
	)
	var last := Vector2i(
		clampi(int(floor((clipped_end.x - 0.001 + half) / size)), 0, source_chunk_count - 1),
		clampi(int(floor((clipped_end.y - 0.001 + half) / size)), 0, source_chunk_count - 1)
	)
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			chunks.append(Vector2i(x, z))
	return chunks
