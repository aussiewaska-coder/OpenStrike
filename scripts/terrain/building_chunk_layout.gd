class_name BuildingChunkLayout
extends RefCounted


static func source_chunk(terrain_chunk: Vector2i, offset: Vector2i) -> Vector2i:
	return terrain_chunk - offset


static func path_for(directory: String, terrain_chunk: Vector2i, offset: Vector2i) -> String:
	var source := source_chunk(terrain_chunk, offset)
	if directory.is_empty() or source.x < 0 or source.y < 0:
		return ""
	return "%s/%d_%d.json" % [directory, source.x, source.y]
