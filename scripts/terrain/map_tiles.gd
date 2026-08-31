class_name MapTiles
extends RefCounted
## Web Mercator and terrarium-encoding helpers.
##
## Deliberately free of engine state and networking so the whole coordinate
## chain can be exercised head-less by tests/map_tiles_test.gd. Everything the
## streamed terrain needs to turn a latitude/longitude into a tile pixel — and
## back — lives here.

const TILE_PX := 256
const EARTH_CIRCUMFERENCE_M := 40075016.686
const METRES_PER_DEGREE_LAT := 111320.0


## Godot has sinh() but no asinh(), and the Mercator forward projection needs it.
static func asinh_of(value: float) -> float:
	return log(value + sqrt(value * value + 1.0))


## Fractional tile column. The integer part is the tile index, the fraction is
## how far across that tile the longitude falls.
static func tile_x(longitude: float, zoom: int) -> float:
	return (longitude + 180.0) / 360.0 * float(1 << zoom)


static func tile_y(latitude: float, zoom: int) -> float:
	var clamped := clampf(latitude, -85.05112878, 85.05112878)
	return (1.0 - asinh_of(tan(deg_to_rad(clamped))) / PI) / 2.0 * float(1 << zoom)


static func longitude_of_tile_x(x: float, zoom: int) -> float:
	return x / float(1 << zoom) * 360.0 - 180.0


static func latitude_of_tile_y(y: float, zoom: int) -> float:
	return rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * y / float(1 << zoom)))))


## Ground resolution of a single tile pixel, which is what decides the zoom
## worth fetching: SRTM is ~30 m native, so anything finer only interpolates.
static func metres_per_pixel(latitude: float, zoom: int) -> float:
	return EARTH_CIRCUMFERENCE_M * cos(deg_to_rad(latitude)) / float((1 << zoom) * TILE_PX)


## Mapzen/Terrarium packs signed metres into RGB: h = R*256 + G + B/256 - 32768.
static func decode_terrarium(colour: Color) -> float:
	return (float(colour.r8) * 256.0 + float(colour.g8) + float(colour.b8) / 256.0) - 32768.0


## Pixel size to ask an ArcGIS export for, given a latitude/longitude box.
##
## The aspect must match the box *in degrees*. A region box is square in metres,
## which away from the equator is wider than tall in degrees; asking for a square
## image makes the service widen the extent to suit and report the adjustment in
## a field easily missed, which silently displaces the imagery against the mesh.
## Mapping the result across the mesh's 0..1 UVs undoes the pixel-aspect
## difference.
static func request_pixels(bounds: Dictionary, maximum_px: int) -> Vector2i:
	var lon_span: float = float(bounds["east"]) - float(bounds["west"])
	var lat_span: float = float(bounds["north"]) - float(bounds["south"])
	if lon_span <= 0.0 or lat_span <= 0.0:
		return Vector2i(maximum_px, maximum_px)
	if lon_span >= lat_span:
		return Vector2i(maximum_px, maxi(int(round(float(maximum_px) * lat_span / lon_span)), 1))
	return Vector2i(maxi(int(round(float(maximum_px) * lon_span / lat_span)), 1), maximum_px)


## A square-in-metres region expressed as a latitude/longitude box. The
## longitude half-width is widened by 1/cos(lat) so the box stays square on the
## ground rather than in degrees.
static func region_bounds(center_latitude: float, center_longitude: float, size_m: float) -> Dictionary:
	var half_lat := (size_m * 0.5) / METRES_PER_DEGREE_LAT
	var half_lon := half_lat / cos(deg_to_rad(center_latitude))
	return {
		"north": center_latitude + half_lat,
		"south": center_latitude - half_lat,
		"west": center_longitude - half_lon,
		"east": center_longitude + half_lon,
	}


## u runs west->east and v runs north->south, matching both the heightmap image
## and the aerial image, so one UV pair addresses either.
static func latitude_at(bounds: Dictionary, v: float) -> float:
	return lerpf(float(bounds["north"]), float(bounds["south"]), v)


static func longitude_at(bounds: Dictionary, u: float) -> float:
	return lerpf(float(bounds["west"]), float(bounds["east"]), u)


## Inverse of the two above: where a real coordinate sits inside the region,
## as (u, v) in 0..1. Used to place the spawn point from a lat/lon.
static func uv_of(bounds: Dictionary, latitude: float, longitude: float) -> Vector2:
	var north := float(bounds["north"])
	var south := float(bounds["south"])
	var west := float(bounds["west"])
	var east := float(bounds["east"])
	return Vector2(
		(longitude - west) / maxf(east - west, 1e-9),
		(north - latitude) / maxf(north - south, 1e-9)
	)


## Inclusive tile index range covering the region at a zoom level.
static func tile_range(bounds: Dictionary, zoom: int) -> Dictionary:
	var x0 := int(floor(tile_x(float(bounds["west"]), zoom)))
	var x1 := int(floor(tile_x(float(bounds["east"]), zoom)))
	var y0 := int(floor(tile_y(float(bounds["north"]), zoom)))
	var y1 := int(floor(tile_y(float(bounds["south"]), zoom)))
	return {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "columns": x1 - x0 + 1, "rows": y1 - y0 + 1}
