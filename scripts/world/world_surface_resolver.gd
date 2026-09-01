extends RefCounted

# One authoritative answer to "what physical surface is at world X/Z?".
# Compiled theatres answer from the same splat masks the terrain shader
# samples, so anything that looks like sand behaves like sand. Rotor wash,
# landing dust, rocket and missile impacts are all expected to share this.

const SURFACES := preload("res://scripts/world/surface_types.gd")

var sea_level := 0.0

var _splat_provider := Callable()
var _height_sampler := Callable()


func configure(height_sampler: Callable, sea_level_m: float) -> void:
	_height_sampler = height_sampler
	sea_level = sea_level_m


func set_splat_provider(provider: Callable) -> void:
	# The world-compiler session owns this Callable: (x, z) -> {channel: weight}.
	# Until it is supplied the elevation fallback below stands in.
	_splat_provider = provider


func has_splat_data() -> bool:
	return _splat_provider.is_valid()


func sample_weights(world_x: float, world_z: float) -> Dictionary:
	if _splat_provider.is_valid():
		var weights: Variant = _splat_provider.call(world_x, world_z)
		if typeof(weights) == TYPE_DICTIONARY:
			return weights
	return {}


func resolve(world_x: float, world_z: float) -> int:
	var weights := sample_weights(world_x, world_z)
	if not weights.is_empty():
		var dominant := SURFACES.dominant_channel(weights)
		if dominant != SURFACES.Surface.UNKNOWN:
			return dominant
	return _fallback_surface(world_x, world_z)


func resolve_blend(world_x: float, world_z: float) -> Dictionary:
	# Kept for the blended-impact case the spec flags as post-MVP: a beach edge
	# reading 65% sand / 35% grass should eventually tint its debris.
	var weights := sample_weights(world_x, world_z)
	if weights.is_empty():
		return {resolve(world_x, world_z): 1.0}
	var blended := {}
	for channel: String in weights.keys():
		if not SURFACES.SPLAT_CHANNELS.has(channel):
			continue
		var surface: int = SURFACES.SPLAT_CHANNELS[channel]
		blended[surface] = float(blended.get(surface, 0.0)) + float(weights[channel])
	return blended if not blended.is_empty() else {resolve(world_x, world_z): 1.0}


func _fallback_surface(world_x: float, world_z: float) -> int:
	# Provisional elevation banding for theatres compiled before the splat
	# pipeline existed. Deliberately crude: it is meant to be replaced, not tuned.
	if not _height_sampler.is_valid():
		return SURFACES.Surface.DIRT
	var height := float(_height_sampler.call(world_x, world_z))
	var above_sea := height - sea_level
	if above_sea <= 0.4:
		return SURFACES.Surface.WATER
	if above_sea <= 3.0:
		return SURFACES.Surface.SAND
	if above_sea <= 26.0:
		return SURFACES.Surface.GRASS
	return SURFACES.Surface.ROCK
