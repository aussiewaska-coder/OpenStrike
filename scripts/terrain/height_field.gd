class_name HeightField
extends RefCounted
## Bilinear sampling of a normalised heightmap image.
##
## Shared by the packaged terrain (procedural_terrain.gd) and the streamed
## terrain so both decode elevation identically. The image holds 0..1 and the
## metadata carries the real metre range it was normalised against.

static func decode(metadata: Dictionary, encoded: float) -> float:
	var min_m := float(metadata.get("elevation_min_m", 0.0))
	var max_m := float(metadata.get("elevation_max_m", 1.0))
	var exaggeration := float(metadata.get("vertical_exaggeration", 1.5))
	return lerp(min_m, max_m, encoded) * exaggeration


## Bilinear rather than nearest: a one-pixel elevation step makes a
## terrain-following aircraft jump at every heightmap cell boundary.
static func sample(image: Image, metadata: Dictionary, world_x: float, world_z: float) -> float:
	if image == null or image.is_empty():
		return 0.0
	var world_size := float(metadata.get("world_size_m", 4000.0))
	var u: float = clampf(world_x / world_size + 0.5, 0.0, 1.0)
	var v: float = clampf(world_z / world_size + 0.5, 0.0, 1.0)
	var pixel_x := u * float(image.get_width() - 1)
	var pixel_y := v * float(image.get_height() - 1)
	var x0 := int(floor(pixel_x))
	var y0 := int(floor(pixel_y))
	var x1 := mini(x0 + 1, image.get_width() - 1)
	var y1 := mini(y0 + 1, image.get_height() - 1)
	var blend_x := pixel_x - float(x0)
	var blend_y := pixel_y - float(y0)
	var top := lerpf(
		decode(metadata, image.get_pixel(x0, y0).r),
		decode(metadata, image.get_pixel(x1, y0).r),
		blend_x
	)
	var bottom := lerpf(
		decode(metadata, image.get_pixel(x0, y1).r),
		decode(metadata, image.get_pixel(x1, y1).r),
		blend_x
	)
	return lerpf(top, bottom, blend_y)


## Central-difference surface normal, sampled in world metres. Cheaper and
## smoother than deriving normals from the built triangles.
static func normal_at(image: Image, metadata: Dictionary, world_x: float, world_z: float, step_m: float) -> Vector3:
	var west := sample(image, metadata, world_x - step_m, world_z)
	var east := sample(image, metadata, world_x + step_m, world_z)
	var north := sample(image, metadata, world_x, world_z - step_m)
	var south := sample(image, metadata, world_x, world_z + step_m)
	return Vector3(west - east, 2.0 * step_m, north - south).normalized()
