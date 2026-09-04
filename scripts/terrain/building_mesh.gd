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
## `suppress` lists world XZ points whose nearby OSM boxes are NOT drawn --
## the hero towers stand there as real models. Visual only: the hit index
## keeps those footprints, so a round still strikes Q1 where Q1 is.
static func build(
	building_records: Array,
	ground_height: Callable,
	suppress := PackedVector2Array(),
	suppress_radius := 40.0
) -> ArrayMesh:
	if building_records.is_empty():
		return null
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# CUSTOM0 carries the wall run, roof layer and roof UV the facade shader
	# reads; without a float format the channel is silently dropped.
	surface.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var drawn := 0
	for index in range(building_records.size()):
		var building: Dictionary = building_records[index]
		var footprint_data: Array = building.get("footprint", [])
		if footprint_data.size() < 3:
			continue
		var footprint := PackedVector2Array()
		for point: Array in footprint_data:
			footprint.append(Vector2(float(point[0]), float(point[1])))
		if Geometry2D.triangulate_polygon(footprint).is_empty():
			continue
		var world_x := float(building.get("x", 0.0))
		var world_z := float(building.get("z", 0.0))
		if _under_hero(Vector2(world_x, world_z), suppress, suppress_radius):
			continue
		# Raw height, deliberately not snapped to floors: BuildingHitIndex reads
		# the same record, and the facade must sit exactly where the round
		# strikes. The only cost is a cut top floor at the parapet.
		var building_height := float(building.get("height", DEFAULT_HEIGHT_M))
		var base_height: float = ground_height.call(world_x, world_z)
		BuildingFacades.emit_building(
			surface, footprint, base_height, base_height + building_height, building.get("tags", {})
		)
		drawn += 1
	if drawn == 0:
		return null
	surface.set_material(BuildingFacades.make_material())
	return surface.commit()


static func _under_hero(point: Vector2, suppress: PackedVector2Array, radius: float) -> bool:
	var radius_squared := radius * radius
	for hero in suppress:
		if point.distance_squared_to(hero) <= radius_squared:
			return true
	return false
