extends SceneTree
class Focus:
	extends Node3D
	var velocity := Vector3.ZERO

func _init(): call_deferred("_run")
func _run():
	var terrain = load("res://tests/fixtures/detail_terrain.gd").new()
	var focus := Focus.new()
	root.add_child(focus)
	root.add_child(terrain)
	terrain._focus = focus
	for index in range(4):
		terrain._chunks.append({"index": index, "center": Vector2(index * 10, 0), "detailed": false})
	focus.position = Vector3(0, 1200, 0)
	focus.velocity = Vector3(175, 0, 0)
	terrain._refresh_detail_chunks()
	assert(terrain.requested == [4096,2048,2048,2048], "fast low pass keeps detail directly underneath")
	terrain.requested.clear()
	focus.velocity = Vector3(20, 0, 0)
	terrain._refresh_detail_chunks()
	assert(terrain.requested == [4096,4096,4096,2048], "slower low flight keeps a wider sharp patch")
	terrain.requested.clear()
	focus.position.y = 1310
	terrain._refresh_detail_chunks()
	assert(terrain.requested[0] == 4096, "hysteresis prevents refetching on small altitude oscillations")
	terrain.requested.clear()
	focus.position.y = 1350
	terrain._refresh_detail_chunks()
	assert(terrain.requested == [2048,2048,2048,2048], "above 300m AGL reduces detail, even over elevated terrain")
	terrain.free()
	focus.free()
	print("TERRAIN_DETAIL_POLICY_TEST_PASS")
	quit()
