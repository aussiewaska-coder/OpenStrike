class_name BuildingMesh
extends RefCounted
## Builds an extruded-footprint building mesh from OSM records.
##
## Shared by the packaged theatres, which hand it every building in the region
## at once, and the streamed corridor, which hands it one terrain chunk's worth
## at a time. Ground height comes in as a Callable so neither caller has to know
## how the other samples terrain.

const DEFAULT_HEIGHT_M := 7.5


## `ground_height` must be a Callable taking (world_x, world_z) and returning
## the terrain height in metres. Returns null when there is nothing to draw.
static func build(building_records: Array, ground_height: Callable) -> ArrayMesh:
	if building_records.is_empty():
		return null
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drawn := 0
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
		var building_height := float(building.get("height", DEFAULT_HEIGHT_M))
		var base_height: float = ground_height.call(world_x, world_z)
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
				surface.add_vertex(Vector3(roof_point.x, base_height + building_height, roof_point.y))
		for edge_index in range(footprint.size()):
			var a := footprint[edge_index]
			var b := footprint[(edge_index + 1) % footprint.size()]
			var edge := b - a
			var side_normal := Vector3(edge.y, 0.0, -edge.x).normalized()
			var bottom_a := Vector3(a.x, base_height, a.y)
			var bottom_b := Vector3(b.x, base_height, b.y)
			var top_a := Vector3(a.x, base_height + building_height, a.y)
			var top_b := Vector3(b.x, base_height + building_height, b.y)
			for vertex in [bottom_a, bottom_b, top_b, bottom_a, top_b, top_a]:
				surface.set_color(building_colour)
				surface.set_normal(side_normal)
				surface.add_vertex(vertex)
		drawn += 1
	if drawn == 0:
		return null
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/building_facade.gdshader") as Shader
	surface.set_material(material)
	return surface.commit()
