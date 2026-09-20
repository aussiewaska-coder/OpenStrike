extends SceneTree


func _make_chunk(index: int) -> Dictionary:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain_imagery.gdshader")
	return {
		"index": index, "cx": index, "cz": 0,
		"instance": MeshInstance3D.new(), "material": material,
		"texture": null, "center": Vector2.ZERO, "detailed": false,
	}


func _init(): call_deferred("_run")


func _run() -> void:
	var terrain = load("res://scripts/terrain/streamed_terrain.gd").new()
	root.add_child(terrain)
	var first := _make_chunk(0)
	var second := _make_chunk(1)
	root.add_child(first["instance"])
	root.add_child(second["instance"])
	terrain._chunks.append(first)
	terrain._chunks.append(second)
	terrain._pending_detail[0] = true
	terrain._pending_detail[1] = true
	var photo := Image.create(32, 32, false, Image.FORMAT_RGB8)
	photo.fill(Color(0.4, 0.35, 0.3))
	terrain._upload_queue.append({"chunk": first, "image": photo, "tier_px": 1024})
	terrain._upload_queue.append({"chunk": second, "image": photo, "tier_px": 1024})
	terrain._drain_uploads(1)
	assert(terrain._upload_queue.size() == 1, "one upload per frame, the rest wait")
	assert(bool(first["detailed"]) and not terrain._pending_detail.has(0), "uploaded chunk resolves")
	assert(not bool(second["detailed"]) and terrain._pending_detail.has(1), "queued chunk stays pending")
	terrain._drain_uploads(1)
	assert(terrain._upload_queue.is_empty() and bool(second["detailed"]), "next frame uploads the rest")
	terrain.free()
	print("UPLOAD_PACING_TEST_PASS")
	quit()
