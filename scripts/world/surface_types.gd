extends RefCounted

# Authoritative physical-surface vocabulary shared by projectiles, impact FX,
# rotor wash and every future system that asks "what is at this coordinate?".

enum Surface {
	UNKNOWN,
	DIRT,
	GRASS,
	SAND,
	ROCK,
	ASPHALT,
	CONCRETE,
	GLASS,
	METAL,
	ROOF_TILE,
	WATER,
}

const NAMES := {
	Surface.UNKNOWN: "UNKNOWN",
	Surface.DIRT: "DIRT",
	Surface.GRASS: "GRASS",
	Surface.SAND: "SAND",
	Surface.ROCK: "ROCK",
	Surface.ASPHALT: "ASPHALT",
	Surface.CONCRETE: "CONCRETE",
	Surface.GLASS: "GLASS",
	Surface.METAL: "METAL",
	Surface.ROOF_TILE: "ROOF_TILE",
	Surface.WATER: "WATER",
}

# Splat channel name -> surface. The world compiler owns the channel names; this
# table is the only place that has to learn a new one.
const SPLAT_CHANNELS := {
	"grass": Surface.GRASS,
	"sand": Surface.SAND,
	"soil": Surface.DIRT,
	"dirt": Surface.DIRT,
	"rock": Surface.ROCK,
	"urban": Surface.ASPHALT,
	"asphalt": Surface.ASPHALT,
	"concrete": Surface.CONCRETE,
	"water": Surface.WATER,
}


static func name_of(surface: int) -> String:
	return String(NAMES.get(surface, "UNKNOWN"))


static func dominant_channel(weights: Dictionary) -> int:
	# Highest-weight valid channel wins. Unrecognised channels are ignored
	# rather than defaulting, so a new splat layer cannot silently become dirt.
	var best := Surface.UNKNOWN
	var best_weight := 0.0
	for channel: String in weights.keys():
		if not SPLAT_CHANNELS.has(channel):
			continue
		var weight := float(weights[channel])
		if weight > best_weight:
			best_weight = weight
			best = int(SPLAT_CHANNELS[channel])
	return best


static func is_hard(surface: int) -> bool:
	return surface in [
		Surface.ASPHALT,
		Surface.CONCRETE,
		Surface.METAL,
		Surface.ROCK,
		Surface.GLASS,
		Surface.ROOF_TILE,
	]
