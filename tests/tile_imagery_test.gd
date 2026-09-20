extends SceneTree


func _init(): call_deferred("_run")


func _run() -> void:
	var client = root.get_node_or_null("TileClient")
	assert(client != null, "TileClient autoload must exist")
	# A solid frame (what Queensland serves outside its coverage) is blank.
	var black := Image.create(64, 64, false, Image.FORMAT_RGB8)
	assert(client._is_blank_frame(black), "solid black decodes as blank")
	# Any real photo varies, sea included.
	var photo := Image.create(64, 64, false, Image.FORMAT_RGB8)
	photo.fill(Color(0.05, 0.12, 0.20))
	photo.set_pixel(10, 10, Color(0.06, 0.13, 0.21))
	photo.set_pixel(40, 30, Color(0.30, 0.32, 0.28))
	assert(not client._is_blank_frame(photo), "a varying frame is not blank")
	print("TILE_IMAGERY_TEST_PASS")
	quit()
