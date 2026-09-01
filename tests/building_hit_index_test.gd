extends SceneTree

const INDEX := preload("res://scripts/terrain/building_hit_index.gd")
const SURFACES := preload("res://scripts/world/surface_types.gd")


func _initialize() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var index: RefCounted = INDEX.new()
	index.add_chunk(0, [_square(1, 0.0, 0.0, 10.0, 20.0)], flat)

	# Front wall, fired along +X at half height.
	var front: RefCounted = index.query_segment(Vector3(-50.0, 10.0, 0.0), Vector3(50.0, 10.0, 0.0))
	assert(front != null and front.hit, "front wall must be hit")
	assert(is_equal_approx(front.position.x, -10.0), "front wall is at x = -10, got %f" % front.position.x)
	assert(front.hit_zone == "wall", "expected a wall hit")
	assert(front.normal.dot(Vector3.RIGHT) < 0.0, "wall normal must face the shooter")
	assert(is_equal_approx(front.relative_height, 0.5), "relative height must be mid-facade")

	# Side wall, fired along +Z.
	var side: RefCounted = index.query_segment(Vector3(0.0, 10.0, -50.0), Vector3(0.0, 10.0, 50.0))
	assert(side != null and side.hit and is_equal_approx(side.position.z, -10.0), "side wall must be hit")

	# Roof, fired straight down.
	var roof: RefCounted = index.query_segment(Vector3(0.0, 50.0, 0.0), Vector3(0.0, -5.0, 0.0))
	assert(roof != null and roof.hit and roof.hit_zone == "roof", "roof must be hit")
	assert(is_equal_approx(roof.position.y, 20.0), "roof sits at y = 20")
	assert(is_equal_approx(roof.relative_height, 1.0), "roof is the top of the building")

	# Complete miss, and a segment passing above the roof.
	assert(index.query_segment(Vector3(-50.0, 10.0, 100.0), Vector3(50.0, 10.0, 100.0)) == null, "must miss")
	assert(index.query_segment(Vector3(-50.0, 30.0, 0.0), Vector3(50.0, 30.0, 0.0)) == null, "must pass above")

	# Two buildings in line: the nearest one stops the round.
	var pair: RefCounted = INDEX.new()
	pair.add_chunk(0, [_square(1, 0.0, 0.0, 10.0, 20.0), _square(2, 120.0, 0.0, 10.0, 20.0)], flat)
	var nearest: RefCounted = pair.query_segment(Vector3(-50.0, 10.0, 0.0), Vector3(200.0, 10.0, 0.0))
	assert(nearest != null and nearest.building_id == 1, "the nearest building must win")

	# Tall stock reads as curtain glass, low stock as concrete.
	var tower: RefCounted = INDEX.new()
	tower.add_chunk(0, [_square(3, 0.0, 0.0, 10.0, 90.0)], flat)
	var facade: RefCounted = tower.query_segment(Vector3(-50.0, 40.0, 0.0), Vector3(50.0, 40.0, 0.0))
	assert(facade.surface_type == SURFACES.Surface.GLASS, "a 90 m tower facade should classify as glass")

	# Chunks stream: footprints arrive when a chunk goes detailed and must be
	# gone the moment it is released, or the cannon keeps hitting ghosts.
	var streaming: RefCounted = INDEX.new()
	streaming.add_chunk(11, [_square(10, 0.0, 0.0, 10.0, 20.0)], flat)
	streaming.add_chunk(22, [_square(20, 120.0, 0.0, 10.0, 20.0)], flat)
	assert(streaming.building_count() == 2, "both chunks must be indexed")
	assert(streaming.has_chunk(11) and streaming.has_chunk(22), "both chunks must be tracked")
	var before: RefCounted = streaming.query_segment(Vector3(-50.0, 10.0, 0.0), Vector3(200.0, 10.0, 0.0))
	assert(before != null and before.building_id == 10, "the near chunk's building must be hit")
	streaming.remove_chunk(11)
	assert(streaming.building_count() == 1, "releasing a chunk must drop its buildings")
	assert(not streaming.has_chunk(11), "the released chunk must be forgotten")
	var after: RefCounted = streaming.query_segment(Vector3(-50.0, 10.0, 0.0), Vector3(200.0, 10.0, 0.0))
	assert(after != null and after.building_id == 20, "the far building must now be the first hit")
	# Re-adding the same key must not duplicate.
	streaming.add_chunk(22, [_square(20, 120.0, 0.0, 10.0, 20.0)], flat)
	assert(streaming.building_count() == 1, "re-adding a chunk must replace, not duplicate")
	streaming.remove_chunk(22)
	assert(streaming.building_count() == 0, "an emptied index must hold nothing")
	assert(streaming.query_segment(Vector3(-50.0, 10.0, 0.0), Vector3(200.0, 10.0, 0.0)) == null, "empty index must miss")

	print("BUILDING_HIT_INDEX_TEST_PASS")
	quit()


func _square(osm_id: int, centre_x: float, centre_z: float, half: float, height: float) -> Dictionary:
	return {
		"osm_id": osm_id,
		"x": centre_x,
		"z": centre_z,
		"height": height,
		"footprint": [
			[centre_x - half, centre_z - half],
			[centre_x + half, centre_z - half],
			[centre_x + half, centre_z + half],
			[centre_x - half, centre_z + half],
		],
	}
