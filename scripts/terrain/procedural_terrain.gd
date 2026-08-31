extends Node3D

var _height_image: Image
var _metadata: Dictionary = {}
var _mesh_instance: MeshInstance3D
var _detail_root: Node3D


func load_region(metadata_path: String) -> bool:
	_clear_terrain()
	if metadata_path.is_empty() or not FileAccess.file_exists(metadata_path):
		push_error("Terrain metadata is missing: %s" % metadata_path)
		return false
	var metadata_file := FileAccess.open(metadata_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(metadata_file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Terrain metadata is invalid: %s" % metadata_path)
		return false
	_metadata = parsed
	var heightmap_path: String = _metadata.get("heightmap", "")
	var height_texture := load(heightmap_path) as Texture2D
	_height_image = height_texture.get_image() if height_texture != null else null
	if _height_image == null or _height_image.is_empty():
		push_error("Terrain heightmap is missing: %s" % heightmap_path)
		return false
	_build_mesh()
	_build_environment_details()
	return true


func sample_height_world(world_x: float, world_z: float) -> float:
	if _height_image == null or _height_image.is_empty():
		return 0.0
	var world_size := float(_metadata.get("world_size_m", 4000.0))
	var u: float = clampf(world_x / world_size + 0.5, 0.0, 1.0)
	var v: float = clampf(world_z / world_size + 0.5, 0.0, 1.0)
	var pixel_x := u * float(_height_image.get_width() - 1)
	var pixel_y := v * float(_height_image.get_height() - 1)
	var x0 := int(floor(pixel_x))
	var y0 := int(floor(pixel_y))
	var x1 := mini(x0 + 1, _height_image.get_width() - 1)
	var y1 := mini(y0 + 1, _height_image.get_height() - 1)
	var blend_x := pixel_x - float(x0)
	var blend_y := pixel_y - float(y0)
	var top := lerpf(
		_decoded_height(_height_image.get_pixel(x0, y0).r),
		_decoded_height(_height_image.get_pixel(x1, y0).r),
		blend_x
	)
	var bottom := lerpf(
		_decoded_height(_height_image.get_pixel(x0, y1).r),
		_decoded_height(_height_image.get_pixel(x1, y1).r),
		blend_x
	)
	# Bilinear sampling removes the one-pixel elevation steps that otherwise
	# make terrain-following aircraft jump at every heightmap cell boundary.
	return lerpf(top, bottom, blend_y)


func get_spawn_position(clearance_m: float = 90.0) -> Vector3:
	var world_x := float(_metadata.get("spawn_world_x", 0.0))
	var world_z := float(_metadata.get("spawn_world_z", 0.0))
	return Vector3(world_x, sample_height_world(world_x, world_z) + clearance_m, world_z)


func get_spawn_yaw_degrees(default_yaw: float = -35.0) -> float:
	return float(_metadata.get("spawn_yaw_degrees", default_yaw))


func _build_mesh() -> void:
	var width := _height_image.get_width()
	var height := _height_image.get_height()
	var world_size := float(_metadata.get("world_size_m", 4000.0))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(height):
		var v := float(z) / float(height - 1)
		for x in range(width):
			var u := float(x) / float(width - 1)
			var elevation := _decoded_height(_height_image.get_pixel(x, z).r)
			surface.set_uv(Vector2(u, v))
			surface.set_color(_terrain_colour(elevation))
			surface.add_vertex(Vector3((u - 0.5) * world_size, elevation, (v - 0.5) * world_size))
	for z in range(height - 1):
		for x in range(width - 1):
			var top_left := z * width + x
			var top_right := top_left + 1
			var bottom_left := (z + 1) * width + x
			var bottom_right := bottom_left + 1
			surface.add_index(top_left)
			surface.add_index(bottom_left)
			surface.add_index(top_right)
			surface.add_index(top_right)
			surface.add_index(bottom_left)
			surface.add_index(bottom_right)
	surface.generate_normals()
	var material := StandardMaterial3D.new()
	var albedo_path: String = _metadata.get("albedo", "")
	var normal_path: String = _metadata.get("normalmap", "")
	var albedo_texture := load(albedo_path) as Texture2D if not albedo_path.is_empty() else null
	var normal_texture := load(normal_path) as Texture2D if not normal_path.is_empty() else null
	material.vertex_color_use_as_albedo = albedo_texture == null
	material.albedo_texture = albedo_texture
	material.albedo_color = Color.WHITE
	var aerial_imagery := bool(_metadata.get("imagery_is_aerial", false))
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if aerial_imagery else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.normal_enabled = normal_texture != null and not aerial_imagery
	material.normal_texture = normal_texture
	material.normal_scale = 0.14
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.92
	surface.set_material(material)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "OfflineTerrain"
	_mesh_instance.mesh = surface.commit()
	add_child(_mesh_instance)


func _decoded_height(encoded: float) -> float:
	var min_m := float(_metadata.get("elevation_min_m", 0.0))
	var max_m := float(_metadata.get("elevation_max_m", 1.0))
	var exaggeration := float(_metadata.get("vertical_exaggeration", 1.5))
	return lerp(min_m, max_m, encoded) * exaggeration


func _terrain_colour(elevation: float) -> Color:
	var min_m := float(_metadata.get("elevation_min_m", 0.0)) * float(_metadata.get("vertical_exaggeration", 1.5))
	var max_m := float(_metadata.get("elevation_max_m", 1.0)) * float(_metadata.get("vertical_exaggeration", 1.5))
	var t := inverse_lerp(min_m, max_m, elevation)
	if t < 0.28:
		return Color("8b7437").lerp(Color("a28b4c"), t / 0.28)
	if t < 0.68:
		return Color("6e7b3e").lerp(Color("4e6538"), (t - 0.28) / 0.4)
	return Color("685f4f").lerp(Color("a49a83"), (t - 0.68) / 0.32)


func _build_environment_details() -> void:
	var environment_type := String(_metadata.get("environment_type", ""))
	if environment_type not in ["city", "coastal_city"]:
		return
	_detail_root = Node3D.new()
	_detail_root.name = "MapDetails"
	add_child(_detail_root)
	if environment_type == "coastal_city":
		_build_positioned_buildings()
		if not bool(_metadata.get("imagery_is_aerial", false)):
			_build_ocean()
	else:
		_build_city_blocks()
		_build_city_helipad()


func _load_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("Offline map feature is missing: %s" % path)
		return {}
	var source := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(source.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Offline map feature is invalid: %s" % path)
		return {}
	return parsed


func _build_positioned_buildings() -> void:
	var feature_data := _load_json_dictionary(String(_metadata.get("buildings", "")))
	var building_records: Array = feature_data.get("buildings", [])
	if building_records.is_empty():
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(building_records.size()):
		var building: Dictionary = building_records[index]
		var footprint_data: Array = building.get("footprint", [])
		if footprint_data.size() < 3:
			continue
		var footprint := PackedVector2Array()
		for point: Array in footprint_data:
			footprint.append(Vector2(float(point[0]), float(point[1])))
		var triangles := Geometry2D.triangulate_polygon(footprint)
		if triangles.is_empty():
			continue
		var world_x := float(building.get("x", 0.0))
		var world_z := float(building.get("z", 0.0))
		var building_height := float(building.get("height", 7.5))
		var ground_height := sample_height_world(world_x, world_z)
		var tower_weight := clampf((building_height - 18.0) / 145.0, 0.0, 1.0)
		var variation := float(int(building.get("osm_id", index)) % 17) / 16.0
		var low_colour := Color("767d78").lerp(Color("aaa695"), variation * 0.42)
		var tower_colour := Color("8d9fa8").lerp(Color("bdc3c0"), variation * 0.3)
		var building_colour := low_colour.lerp(tower_colour, tower_weight)
		for triangle_index in range(0, triangles.size(), 3):
			for corner in range(3):
				var roof_point := footprint[triangles[triangle_index + corner]]
				surface.set_color(building_colour)
				surface.set_normal(Vector3.UP)
				surface.add_vertex(Vector3(roof_point.x, ground_height + building_height, roof_point.y))
		for edge_index in range(footprint.size()):
			var a := footprint[edge_index]
			var b := footprint[(edge_index + 1) % footprint.size()]
			var edge := b - a
			var side_normal := Vector3(edge.y, 0.0, -edge.x).normalized()
			var bottom_a := Vector3(a.x, ground_height, a.y)
			var bottom_b := Vector3(b.x, ground_height, b.y)
			var top_a := Vector3(a.x, ground_height + building_height, a.y)
			var top_b := Vector3(b.x, ground_height + building_height, b.y)
			for vertex in [bottom_a, bottom_b, top_b, bottom_a, top_b, top_a]:
				surface.set_color(building_colour)
				surface.set_normal(side_normal)
				surface.add_vertex(vertex)
	var building_material := ShaderMaterial.new()
	building_material.shader = load("res://shaders/building_facade.gdshader") as Shader
	surface.set_material(building_material)
	var building_mesh_instance := MeshInstance3D.new()
	building_mesh_instance.name = "SurfersParadiseBuildings"
	building_mesh_instance.mesh = surface.commit()
	_detail_root.add_child(building_mesh_instance)


func _build_ocean() -> void:
	var feature_data := _load_json_dictionary(String(_metadata.get("coastline", "")))
	var coastline_points: Array = feature_data.get("points", [])
	if coastline_points.size() < 2:
		return
	var world_east_x := float(feature_data.get("world_east_x", 2000.0)) + 25.0
	var sea_y := float(_metadata.get("sea_level_m", 0.0)) + 0.7
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(coastline_points.size() - 1):
		var a: Array = coastline_points[index]
		var b: Array = coastline_points[index + 1]
		var coast_a := Vector3(float(a[0]), sea_y, float(a[1]))
		var coast_b := Vector3(float(b[0]), sea_y, float(b[1]))
		var ocean_a := Vector3(world_east_x, sea_y, float(a[1]))
		var ocean_b := Vector3(world_east_x, sea_y, float(b[1]))
		surface.set_uv(Vector2(0.0, float(index)))
		surface.add_vertex(coast_a)
		surface.set_uv(Vector2(1.0, float(index)))
		surface.add_vertex(ocean_a)
		surface.set_uv(Vector2(0.0, float(index + 1)))
		surface.add_vertex(coast_b)
		surface.set_uv(Vector2(0.0, float(index + 1)))
		surface.add_vertex(coast_b)
		surface.set_uv(Vector2(1.0, float(index)))
		surface.add_vertex(ocean_a)
		surface.set_uv(Vector2(1.0, float(index + 1)))
		surface.add_vertex(ocean_b)
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.035, 0.30, 0.42, 1.0)
	water_material.metallic = 0.28
	water_material.roughness = 0.22
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.set_material(water_material)
	var ocean := MeshInstance3D.new()
	ocean.name = "PacificOcean"
	ocean.mesh = surface.commit()
	_detail_root.add_child(ocean)


func _build_city_blocks() -> void:
	var spacing := float(_metadata.get("city_block_spacing_m", 105.0))
	var radius := float(_metadata.get("city_radius_m", 1350.0))
	var half_count := int(floor(radius / spacing))
	var transforms: Array[Transform3D] = []
	var colours: Array[Color] = []
	for grid_z in range(-half_count, half_count + 1):
		for grid_x in range(-half_count, half_count + 1):
			var world_x := float(grid_x) * spacing
			var world_z := float(grid_z) * spacing
			var distance := Vector2(world_x, world_z).length()
			# Leave an open launch plaza around the player and soften the city edge.
			if distance < 220.0 or distance > radius:
				continue
			var seed: int = abs((grid_x * 73856093) ^ (grid_z * 19349663))
			var variation := float(seed % 1000) / 999.0
			var centre_weight := 1.0 - clampf(distance / radius, 0.0, 1.0)
			var width := lerpf(38.0, 60.0, float((seed >> 3) % 100) / 99.0)
			var depth := lerpf(38.0, 60.0, float((seed >> 9) % 100) / 99.0)
			var building_height := 18.0 + variation * 30.0 + centre_weight * centre_weight * 46.0
			var ground_height := sample_height_world(world_x, world_z)
			var building_basis := Basis.IDENTITY.scaled(Vector3(width, building_height, depth))
			transforms.append(Transform3D(
				building_basis,
				Vector3(world_x, ground_height + building_height * 0.5, world_z)
			))
			var shade := 0.32 + variation * 0.22
			colours.append(Color(shade * 0.82, shade * 0.9, shade, 1.0))
	var building_mesh := BoxMesh.new()
	building_mesh.size = Vector3.ONE
	var building_material := StandardMaterial3D.new()
	building_material.vertex_color_use_as_albedo = true
	building_material.roughness = 0.68
	building_material.metallic = 0.08
	building_mesh.material = building_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = building_mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_color(index, colours[index])
	var buildings := MultiMeshInstance3D.new()
	buildings.name = "CBD_Buildings"
	buildings.multimesh = multimesh
	_detail_root.add_child(buildings)


func _build_city_helipad() -> void:
	var pad := MeshInstance3D.new()
	pad.name = "CityStartHelipad"
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 24.0
	pad_mesh.bottom_radius = 24.0
	pad_mesh.height = 1.4
	pad_mesh.radial_segments = 48
	var pad_material := StandardMaterial3D.new()
	pad_material.albedo_color = Color("39444b")
	pad_material.roughness = 0.86
	pad_mesh.material = pad_material
	pad.mesh = pad_mesh
	pad.position = Vector3(0.0, sample_height_world(0.0, 0.0) + 0.7, 0.0)
	_detail_root.add_child(pad)


func _clear_terrain() -> void:
	if is_instance_valid(_mesh_instance):
		_mesh_instance.queue_free()
	if is_instance_valid(_detail_root):
		_detail_root.queue_free()
	_mesh_instance = null
	_detail_root = null
	_height_image = null
	_metadata = {}
