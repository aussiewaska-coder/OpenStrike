extends SceneTree
const PLACES := preload("res://scripts/ui/map_places.gd")
const TILES := preload("res://scripts/terrain/map_tiles.gd")
func _init(): call_deferred("_run")
func _run():
	var bounds := TILES.region_bounds(-28.08, 153.365, 50000.0)
	var terrain = load("res://scripts/terrain/streamed_terrain.gd").new()
	terrain._bounds = bounds
	terrain._metadata = {"world_size_m": 50000.0}
	var layers: Dictionary = terrain.tactical_map_layers()
	assert(layers.places.size() == 6, "corridor contains five town labels and airport")
	var names := []
	for place in layers.places: names.append(place.name)
	for expected in ["SURFERS PARADISE", "HELENSVALE", "NERANG", "BURLEIGH HEADS", "TWEED HEADS", "COOLANGATTA AIRPORT"]:
		assert(expected in names)
	assert(layers.places[0].airport and layers.places[0].subtitle == "OOL / GOLD COAST")
	assert(PLACES.for_bounds({}, 50000).is_empty())
	assert(PLACES.for_bounds(TILES.region_bounds(0,0,8000),8000).is_empty(), "unrelated maps must not inherit Gold Coast labels")
	var map := preload("res://scripts/ui/tactical_map_canvas.gd").new()
	root.add_child(map)
	map.size = Vector2(900,600)
	map.set_layers(layers)
	map.set_range(25000)
	for style in range(3):
		map.map_style = style
		var labels := map.place_labels()
		assert(labels.size() == 6, "every layer must show all in-view geographic labels")
		for i in range(labels.size()):
			for j in range(i):
				assert(not labels[i].rect.intersects(labels[j].rect), "town labels must not overlap")
	var airport: Vector2 = layers.places[0].position
	map.centre = airport
	map.set_range(500)
	assert(map.place_labels().size() == 1 and map.place_labels()[0].airport, "zooming to airport keeps its marker anchored")
	assert(map.contact_at(map.world_to_screen(airport)) == -1, "geographic markers must not become weapon targets")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--visual-out=") and DisplayServer.get_name() != "headless":
			var mfd := preload("res://scripts/ui/tactical_mfd.gd").new()
			root.add_child(mfd)
			mfd.map.set_layers(layers)
			mfd.open_panel()
			mfd.map.set_range(25000)
			for viewport_size in [Vector2i(1280,720), Vector2i(640,360), Vector2i(360,640)]:
				root.content_scale_size = viewport_size
				root.size = viewport_size
				await process_frame
				await process_frame
				assert(mfd.map.place_labels().size() == 6, "small-screen map must retain every in-view town and airport label")
				await RenderingServer.frame_post_draw
				assert(root.get_texture().get_image().save_png("%s-%d.png" % [arg.trim_prefix("--visual-out="), viewport_size.x]) == OK)
			mfd.free()
	map.free()
	terrain.free()
	print("TACTICAL_PLACES_TEST_PASS")
	quit()
