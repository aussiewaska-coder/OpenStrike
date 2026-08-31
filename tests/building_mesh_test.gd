extends SceneTree

## BuildingMesh is shared by the packaged theatres and the streamed corridor, so
## a change that suits one must not silently break the other.


func _init() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0

	# Nothing to draw must be null, not an empty mesh: the caller skips creating
	# a MeshInstance3D on null, and an empty mesh would leave one per chunk.
	if BuildingMesh.build([], flat) != null:
		push_error("no records must produce no mesh")
		quit(1)
	var degenerate := [{"x": 0.0, "z": 0.0, "height": 8.0, "footprint": [[0.0, 0.0], [1.0, 0.0]]}]
	if BuildingMesh.build(degenerate, flat) != null:
		push_error("a footprint with fewer than three points must produce no mesh")
		quit(1)

	# A 10 m square extruded 20 m: the mesh must span the footprint exactly and
	# rise from the ground to the building height.
	var square := [{
		"x": 5.0,
		"z": 5.0,
		"height": 20.0,
		"osm_id": 1,
		"footprint": [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]],
	}]
	var mesh: ArrayMesh = BuildingMesh.build(square, flat)
	if mesh == null:
		push_error("a valid footprint must produce a mesh")
		quit(1)
	var box := mesh.get_aabb()
	_assert_vector(box.position, Vector3(0.0, 0.0, 0.0), "mesh starts at the footprint and the ground")
	_assert_vector(box.size, Vector3(10.0, 20.0, 10.0), "mesh spans the footprint and the height")

	# A square is two roof triangles and four walls of two triangles each.
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if vertices.size() != 30:
		push_error("expected 30 vertices for a square building, got %d" % vertices.size())
		quit(1)

	# Ground height comes from the callable, so buildings seat on the terrain
	# rather than at sea level. This is what keeps the streamed corridor's
	# 1096 m of relief from burying or floating them.
	var hill := func(_x: float, _z: float) -> float: return 150.0
	var seated: ArrayMesh = BuildingMesh.build(square, hill)
	var seated_box := seated.get_aabb()
	if not is_equal_approx(seated_box.position.y, 150.0):
		push_error("building must seat on the sampled ground, got y = %f" % seated_box.position.y)
		quit(1)
	if not is_equal_approx(seated_box.size.y, 20.0):
		push_error("seating must not change the building height, got %f" % seated_box.size.y)
		quit(1)

	# Buildings with no height fall back to a sensible storey count rather than
	# collapsing flat.
	var unmeasured := [{"x": 0.0, "z": 0.0, "footprint": [[0.0, 0.0], [8.0, 0.0], [8.0, 8.0]]}]
	var fallback: ArrayMesh = BuildingMesh.build(unmeasured, flat)
	if fallback == null or fallback.get_aabb().size.y <= 0.0:
		push_error("a building without a height must still be extruded")
		quit(1)

	# Several buildings accumulate into one mesh; that is the whole point of
	# batching a chunk.
	var pair := square.duplicate(true)
	pair.append({
		"x": 25.0,
		"z": 5.0,
		"height": 12.0,
		"osm_id": 2,
		"footprint": [[20.0, 0.0], [30.0, 0.0], [30.0, 10.0], [20.0, 10.0]],
	})
	var batched: ArrayMesh = BuildingMesh.build(pair, flat)
	if not is_equal_approx(batched.get_aabb().size.x, 30.0):
		push_error("batched buildings must share one mesh, got width %f" % batched.get_aabb().size.x)
		quit(1)
	print("BUILDING_MESH_TEST_PASS")
	quit()


func _assert_vector(actual: Vector3, expected: Vector3, label: String) -> void:
	if not actual.is_equal_approx(expected):
		push_error("%s: expected %s, got %s" % [label, expected, actual])
		quit(1)
