extends RefCounted
const TILES := preload("res://scripts/terrain/map_tiles.gd")
# Existing theatre anchors for Surfers, Burleigh and Tweed. Nerang (POPL 24047)
# and Helensvale (SUB 46051): Queensland Place Names gazetteer.
# Airport ARP: Airservices YBCG aerodrome chart, 28 09 52S / 153 30 17E.
const PLACES := [
	{"name": "COOLANGATTA AIRPORT", "subtitle": "OOL / GOLD COAST", "lat": -28.164444, "lon": 153.504722, "airport": true},
	{"name": "SURFERS PARADISE", "lat": -28.0023, "lon": 153.431},
	{"name": "HELENSVALE", "lat": -27.90083, "lon": 153.33778},
	{"name": "NERANG", "lat": -27.99028, "lon": 153.33583},
	{"name": "BURLEIGH HEADS", "lat": -28.0894, "lon": 153.4506},
	{"name": "TWEED HEADS", "lat": -28.1739, "lon": 153.545},
]

static func for_bounds(bounds: Dictionary, world_size: float) -> Array:
	var result := []
	if bounds.is_empty():
		return result
	var region := Rect2(Vector2.ONE * -world_size * 0.5, Vector2.ONE * world_size)
	for place in PLACES:
		var position := TILES.world_of(bounds, place.lat, place.lon, world_size)
		if region.has_point(position):
			var marker: Dictionary = place.duplicate()
			marker["position"] = position
			result.append(marker)
	return result
