extends SceneTree
## Pre-download: a tiny two-chunk theatre must land its chunk textures and
## elevation grid on disk, so every later pass reads entirely from cache with
## no network. Uses the gov source so it runs without a Mapbox token.

const SMOKE_HEIGHTFIELD := "user://map_cache/height_precache_smoke_z12_r65_s0_skadi.bin"


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var client: Node = root.get_node("TileClient")
	var region := {
		"id": "precache_smoke",
		"center_latitude": -28.0023,
		"center_longitude": 153.431,
		"world_size_m": 3000.0,
		"chunk_count": 2,
		"elevation_zoom": 12,
		"heightfield_resolution": 65,
		"elevation_smoothing": 0,
		"elevation_server": "skadi",
		"imagery_server": "qld",
	}
	# Warm pass: allowed to hit the network, and must leave the theatre cached.
	await client.precache_region(region, 512)
	if not FileAccess.file_exists(SMOKE_HEIGHTFIELD):
		print("PRECACHE_TEST_FAIL: elevation grid never reached the cache")
		quit(1)
		return
	# Cold-network pass: everything the theatre needs is on disk now, so a
	# second pre-download must be pure cache reads.
	var hits_before := int(client.cache_hits)
	var fetches_before := int(client.network_fetches)
	await client.precache_region(region, 512)
	var new_fetches := int(client.network_fetches) - fetches_before
	if new_fetches > 0:
		print("PRECACHE_TEST_FAIL: ", new_fetches, " network fetches on the cached pass")
		quit(1)
		return
	print("PRECACHE_TEST_PASS (offline pre-download: %d cache reads)" % [
		int(client.cache_hits) - hits_before,
	])
	quit(0)
