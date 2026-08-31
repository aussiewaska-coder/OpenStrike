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
	terrain.free()
	print("TERRAIN_SAMPLING_TEST_PASS")
	quit()
