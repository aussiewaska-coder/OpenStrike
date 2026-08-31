extends SceneTree

const TERRAIN_SCRIPT := preload("res://scripts/terrain/procedural_terrain.gd")


func _init() -> void:
	var terrain := TERRAIN_SCRIPT.new()
	var height_image := Image.create(2, 2, false, Image.FORMAT_RF)
	height_image.set_pixel(0, 0, Color(0.0, 0.0, 0.0))
	height_image.set_pixel(1, 0, Color(1.0, 0.0, 0.0))
	height_image.set_pixel(0, 1, Color(1.0, 0.0, 0.0))
	height_image.set_pixel(1, 1, Color(0.0, 0.0, 0.0))
	terrain.set("_height_image", height_image)
	terrain.set("_metadata", {
		"world_size_m": 2.0,
		"elevation_min_m": 0.0,
		"elevation_max_m": 100.0,
		"vertical_exaggeration": 1.0,
	})
	assert(is_equal_approx(terrain.sample_height_world(0.0, 0.0), 50.0))
	assert(is_equal_approx(terrain.sample_height_world(-0.5, -0.5), 37.5))

	# The flyable box comes from the theatre, not a constant: a fixed limit
	# fenced the aircraft into 4 km no matter which region was loaded.
	if not is_equal_approx(terrain.world_half_extent(), 1.0):
		push_error("half extent must follow the region metadata, got %f" % terrain.world_half_extent())
		quit(1)
	terrain.set("_metadata", {"world_size_m": 36000.0})
	if not is_equal_approx(terrain.world_half_extent(), 18000.0):
		push_error("a 36 km corridor must allow 18000 m, got %f" % terrain.world_half_extent())
		quit(1)
	terrain.free()
	print("TERRAIN_SAMPLING_TEST_PASS")
	quit()
