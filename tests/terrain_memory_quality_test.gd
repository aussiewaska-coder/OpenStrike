extends SceneTree

func _init(): call_deferred("run")
func run():
	var client = root.get_node("TileClient")
	var previous: bool = client.compression_available
	client.compression_available = false
	var terrain = load("res://scripts/terrain/streamed_terrain.gd").new()
	terrain._apply_memory_budget()
	assert(terrain.near_detail_texture_px == 4096, "uncompressed phones must retain the sharp low-altitude tier")
	assert(terrain.near_detail_chunks == 1, "only one expensive close tile may be resident")
	var pixels: int = terrain.near_detail_texture_px ** 2 + (terrain.max_detail_chunks - 1) * terrain.detail_texture_px ** 2
	assert(pixels <= 10 * 2048 ** 2, "sharp nearby imagery must fit the previous uncompressed resident budget")
	terrain.free()
	client.compression_available = previous
	print("TERRAIN_MEMORY_QUALITY_TEST_PASS")
	quit()
