class_name LauncherLayout
extends RefCounted

const TARGETS_PER_CLUSTER := 1

## Fictional game sites around the built-up coast and inland hills.
static func clusters_for(region_id: String, half_extent: float, world_of := Callable()) -> Array:
	if region_id == "au_gold_coast_tweed_corridor" and world_of.is_valid():
		var sites := [
			["CITY NORTH", -27.978, 153.412],
			["CITY CENTRAL", -28.015, 153.416],
			["CITY SOUTH", -28.092, 153.435],
			["HINTERLAND NORTH", -27.985, 153.285],
			["HINTERLAND CENTRAL", -28.064, 153.302],
			["HINTERLAND SOUTH", -28.165, 153.348],
		]
		var out := []
		for site in sites:
			out.append({"name": site[0], "centre": world_of.call(site[1], site[2])})
		return out
	if region_id == "au_nsw_sydney_harbour" and world_of.is_valid():
		var sydney := [
			["CITY NORTH", -33.815, 151.20],
			["CITY CENTRAL", -33.8688, 151.2093],
			["CITY SOUTH", -33.92, 151.20],
			["HINTERLAND NORTH", -33.80, 151.05],
			["HINTERLAND CENTRAL", -33.87, 151.05],
			["HINTERLAND SOUTH", -33.95, 151.10],
		]
		var syd_out := []
		for site in sydney:
			syd_out.append({"name": site[0], "centre": world_of.call(site[1], site[2])})
		return syd_out
	var scale := minf(half_extent, 6000.0)
	return [
		{"name": "CITY NORTH", "centre": Vector2(-0.12, -0.25) * scale},
		{"name": "CITY CENTRAL", "centre": Vector2(-0.16, 0.0) * scale},
		{"name": "CITY SOUTH", "centre": Vector2(-0.12, 0.25) * scale},
		{"name": "HINTERLAND NORTH", "centre": Vector2(-0.65, -0.4) * scale},
		{"name": "HINTERLAND CENTRAL", "centre": Vector2(-0.55, 0.0) * scale},
		{"name": "HINTERLAND SOUTH", "centre": Vector2(-0.65, 0.4) * scale},
	]
