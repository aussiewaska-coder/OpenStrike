extends SceneTree
## HeightField is shared by the packaged and the streamed terrain, so both
## decode elevation identically.

func _init() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RF)
	image.set_pixel(0, 0, Color(0.0, 0.0, 0.0))
	image.set_pixel(1, 0, Color(1.0, 0.0, 0.0))
	image.set_pixel(0, 1, Color(1.0, 0.0, 0.0))
	image.set_pixel(1, 1, Color(0.0, 0.0, 0.0))
	var metadata := {
		"world_size_m": 2.0,
		"elevation_min_m": 0.0,
		"elevation_max_m": 100.0,
		"vertical_exaggeration": 1.0,
	}
	assert(is_equal_approx(HeightField.sample(image, metadata, 0.0, 0.0), 50.0))
	assert(is_equal_approx(HeightField.sample(image, metadata, -0.5, -0.5), 37.5))

	# Missing imagery must read as flat ground, never crash the flight model.
	assert(is_equal_approx(HeightField.sample(null, metadata, 0.0, 0.0), 0.0))

	# A flat field points straight up regardless of the sampling step.
	var flat := Image.create(4, 4, false, Image.FORMAT_RF)
	flat.fill(Color(0.5, 0.0, 0.0))
	var normal := HeightField.normal_at(flat, metadata, 0.0, 0.0, 0.25)
	assert(normal.is_equal_approx(Vector3.UP))

	print("HEIGHT_FIELD_TEST_PASS")
	quit()
