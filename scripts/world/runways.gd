class_name Runways
extends RefCounted

## Authored runway data for full landing-sim ops.
##
## Positions are game placements near the real thresholds (ARP-centred, real
## headings and lengths), not survey data. Each runway spawns at its threshold
## end and takes off along heading_deg. Lengths: YSSY 16R/34L 3962 m,
## 16L/34R 2438 m, 07/25 2530 m; OOL 14/32 2492 m.

const SYDNEY_ARP_LAT := -33.9399
const SYDNEY_ARP_LON := 151.1753
const COOLANGATTA_ARP_LAT := -28.164444
const COOLANGATTA_ARP_LON := 153.504722


## All runways for a theatre id. Empty for theatres with no authored airport.
static func for_region(region_id: String) -> Array:
	if region_id == "au_nsw_sydney_harbour":
		return [
			{"airport": "YSSY", "id": "16R", "center_lat": -33.9455, "center_lon": 151.1780,
				"heading_deg": 160.0, "length_m": 3962.0, "width_m": 45.0},
			{"airport": "YSSY", "id": "16L", "center_lat": -33.9410, "center_lon": 151.1650,
				"heading_deg": 160.0, "length_m": 2438.0, "width_m": 45.0},
			{"airport": "YSSY", "id": "07", "center_lat": -33.9350, "center_lon": 151.1780,
				"heading_deg": 70.0, "length_m": 2530.0, "width_m": 45.0},
		]
	if region_id == "au_gold_coast_tweed_corridor":
		return [
			{"airport": "OOL", "id": "14", "center_lat": -28.1644, "center_lon": 153.5047,
				"heading_deg": 140.0, "length_m": 2492.0, "width_m": 45.0},
		]
	return []


## Longest runway first: the default takeoff slot.
static func default_runway(region_id: String) -> Dictionary:
	var best := {}
	for runway in for_region(region_id):
		if best.is_empty() or float(runway.get("length_m", 0.0)) > float(best.get("length_m", 0.0)):
			best = runway
	return best


## Latitude/longitude of the threshold the aircraft lines up on: half the
## length behind the centre, along the reciprocal of the takeoff heading.
static func threshold_latlon(runway: Dictionary) -> Vector2:
	var heading := deg_to_rad(float(runway.get("heading_deg", 0.0)))
	var half_m := float(runway.get("length_m", 0.0)) * 0.5
	var back_lat := half_m / 111320.0
	var back_lon := half_m / (111320.0 * cos(deg_to_rad(float(runway.get("center_lat", 0.0)))))
	var dlat := -cos(heading) * back_lat
	var dlon := -sin(heading) * back_lon
	return Vector2(float(runway.get("center_lat", 0.0)) + dlat, float(runway.get("center_lon", 0.0)) + dlon)
