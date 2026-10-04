extends SceneTree
## Guards the shipped building data, not the code that made it.
##
## Every theatre used to arrive with three quarters of its buildings at one
## identical height, because that is the fallback the OSM extract writes when a
## way carries no `height` or `building:levels` tag. From the air that is a
## carpet of boxes rather than a city, and nothing in the render path notices:
## a box extrudes just as happily as a tower. So the assertion is about the
## data itself -- one height must not own a theatre.

const THEATRES := ["au_gold_coast_tweed_corridor", "au_nsw_sydney_harbour"]
const CHUNKS_SAMPLED := 12
const MIN_DISTINCT_HEIGHTS := 12
const MAX_MODAL_SHARE := 0.4
const MIN_PLAUSIBLE_M := 2.5
const MAX_PLAUSIBLE_M := 220.0


func _init() -> void:
	for theatre in THEATRES:
		var samples := _sample_chunks("res://data/regions/%s/buildings" % theatre)
		assert(not samples.is_empty(), "%s must ship building chunks" % theatre)
		var heights := {}
		var tallest := 0.0
		var shortest := 1e9
		var buildings := 0
		for records: Array in samples:
			for record: Dictionary in records:
				var height := float(record.get("height", 0.0))
				assert(
					height >= MIN_PLAUSIBLE_M and height <= MAX_PLAUSIBLE_M,
					"%s: building %s has an implausible height %.2f m"
					% [theatre, record.get("osm_id", 0), height]
				)
				var key := "%.1f" % height
				heights[key] = int(heights.get(key, 0)) + 1
				tallest = maxf(tallest, height)
				shortest = minf(shortest, height)
				buildings += 1
		var modal := 0
		for count: int in heights.values():
			modal = maxi(modal, count)
		var share := float(modal) / float(maxi(buildings, 1))
		assert(
			heights.size() >= MIN_DISTINCT_HEIGHTS,
			"%s: only %d distinct heights across %d sampled buildings"
			% [theatre, heights.size(), buildings]
		)
		assert(
			share <= MAX_MODAL_SHARE,
			"%s: one height still owns %.0f%% of buildings, so the skyline is a carpet"
			% [theatre, share * 100.0]
		)
		assert(tallest > 60.0, "%s: no tower-scale building survived" % theatre)
		assert(shortest < 4.0, "%s: nothing reads as a garage or shed" % theatre)
		print("%s: %d sampled buildings, %d heights, modal %.0f%%" % [theatre, buildings, heights.size(), share * 100.0])
	print("BUILDING_HEIGHT_TEST_PASS")
	quit()


## Every chunk must carry the inference model's mark, or the extract was
## regenerated and never restated -- which is exactly how the flat carpet came
## back. Sampling every nth file keeps this under a second instead of parsing
## all 663 chunks.
func _sample_chunks(directory_path: String) -> Array:
	var directory := DirAccess.open(directory_path)
	assert(directory != null, "%s must exist" % directory_path)
	var names: Array = []
	for name in directory.get_files():
		if String(name).ends_with(".json"):
			names.append(name)
	names.sort()
	assert(not names.is_empty(), "%s must hold building files" % directory_path)
	var step := maxi(1, names.size() / CHUNKS_SAMPLED)
	var picked: Array = []
	for index in range(0, names.size(), step):
		var file := FileAccess.open(String(directory_path) + "/" + String(names[index]), FileAccess.READ)
		assert(file != null, "building chunk must be readable")
		var payload = JSON.parse_string(file.get_as_text())
		file.close()
		assert(payload is Dictionary, "%s must hold a chunk object" % names[index])
		assert(
			not String((payload as Dictionary).get("height_model", "")).is_empty(),
			"%s: chunk carries no height_model, so heights were never inferred" % names[index]
		)
		picked.append((payload as Dictionary).get("buildings", []))
	return picked
