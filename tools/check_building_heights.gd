extends SceneTree
## Renders a real theatre's buildings from a low external camera and measures
## the skyline they make, so a height change can be seen instead of trusted.
##
## The number that matters is not the mean height, it is the *profile*: a
## district where every box is the same height draws a flat-topped wall. Each
## column of the frame is scanned from the sky down to the first non-background
## pixel, and the spread of those silhouette heights is the report.
##
##   xvfb-run -a ~/tools/godot/Godot_v4.7.2-stable_linux.arm64 --path . \
##     --script tools/check_building_heights.gd -- --dir=/tmp/skyline --prefix=before
##
## `--dir` holds `<prefix>_<chunk>.json` building chunks as the game reads them,
## so a before/after pair is two directories of the same chunks.

const SKY := Color(0.22, 0.32, 0.45)
const RESOLUTION := Vector2i(960, 540)

var _directory := "/tmp/skyline"
var _prefix := "after"
## Camera distance as a fraction of the patch width. Drop it to see facades and
## roof lines instead of the whole district.
var _range := 0.52


func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dir="):
			_directory = argument.trim_prefix("--dir=")
		elif argument.begins_with("--prefix="):
			_prefix = argument.trim_prefix("--prefix=")
		elif argument.begins_with("--range="):
			_range = float(argument.trim_prefix("--range="))
	call_deferred("_run")


func _run() -> void:
	root.size = RESOLUTION
	var records := _records()
	if records.is_empty():
		push_error("no building records found under %s/%s_*.json" % [_directory, _prefix])
		quit(1)
		return
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.42
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -24.0, 0.0)
	sun.light_energy = 0.95
	stage.add_child(sun)
	var building_mesh: ArrayMesh = load("res://scripts/terrain/building_mesh.gd").build(
		records, func(_world_x: float, _world_z: float) -> float: return 0.0
	)
	if building_mesh == null:
		push_error("the chunk set produced no mesh")
		quit(1)
		return
	var mesh_instance := _mesh_instance(building_mesh)
	stage.add_child(mesh_instance)
	# Chunk records are region-local, so a CBD block can sit 15 km from the
	# origin. Frame the cluster where it actually is.
	var lowest := Vector2(1e9, 1e9)
	var highest := Vector2(-1e9, -1e9)
	for record: Dictionary in records:
		for point: Array in record.get("footprint", []):
			var corner := Vector2(float(point[0]), float(point[1]))
			lowest = lowest.min(corner)
			highest = highest.max(corner)
	var centre := (lowest + highest) * 0.5
	var span := maxf(highest.x - lowest.x, highest.y - lowest.y)
	mesh_instance.position = Vector3(-centre.x, 0.0, -centre.y)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0.0, maxf(45.0, span * 0.055), span * _range)
	camera.look_at(Vector3(0.0, span * 0.018, 0.0))
	camera.far = span * 4.0
	camera.fov = 52.0
	print("  patch %.0f m across, centred at %.0f, %.0f" % [span, centre.x, centre.y])
	var rooftops := {}
	var tallest := 0.0
	for record: Dictionary in records:
		var height := float(record.get("height", 0.0))
		rooftops["%.1f" % height] = true
		tallest = maxf(tallest, height)
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	var path := "/tmp/skyline-%s.png" % _prefix
	shot.save_png(path)
	var profile := _silhouette_profile(shot)
	print("%s: %d buildings, %d rooftop heights, tallest %.0f m" % [_prefix, records.size(), rooftops.size(), tallest])
	print("  skyline -> %s, silhouette spread %.1f px over %d roof levels" % [
		path, float(profile[0]), int(profile[1])
	])
	print("SKYLINE_RENDER_PASS")
	quit(0)


func _records() -> Array:
	var directory := DirAccess.open(_directory)
	if directory == null:
		return []
	var records := []
	directory.list_dir_begin()
	var name := directory.get_next()
	while name != "":
		if name.begins_with(_prefix + "_") and name.ends_with(".json"):
			var file := FileAccess.open(_directory + "/" + name, FileAccess.READ)
			var payload = JSON.parse_string(file.get_as_text())
			records.append_array((payload as Dictionary).get("buildings", []))
		name = directory.get_next()
	directory.list_dir_end()
	return records


func _mesh_instance(mesh: Mesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	return instance


## Standard deviation of the skyline height across the frame, plus how many
## different silhouette levels occur. A uniform box town scores near zero on
## both no matter how tall its boxes are.
func _silhouette_profile(image: Image) -> Array:
	var heights := []
	for x in range(0, image.get_width(), 3):
		var top := -1
		for y in range(0, image.get_height()):
			var pixel := image.get_pixel(x, y)
			var dr := pixel.r - SKY.r
			var dg := pixel.g - SKY.g
			var db := pixel.b - SKY.b
			if dr * dr + dg * dg + db * db > 0.012:
				top = image.get_height() - y
				break
		if top >= 0:
			heights.append(float(top))
	if heights.size() < 8:
		return [0.0, 0]
	var mean := 0.0
	for value: float in heights:
		mean += value
	mean /= float(heights.size())
	var variance := 0.0
	var levels := {}
	for value: float in heights:
		variance += (value - mean) * (value - mean)
		levels[int(round(value / 4.0))] = true
	return [sqrt(variance / float(heights.size())), levels.size()]
