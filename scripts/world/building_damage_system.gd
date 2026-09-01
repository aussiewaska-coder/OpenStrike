extends RefCounted

# Records what the cannon did to each building. Deliberately thin: the
# projectile side must not learn about destruction, and this interface has to
# survive the arrival of wall breaches and damage cells (spec sections 50, 51).

signal building_damaged(building_id: int, accumulated: float, relative_height: float)
signal building_smoking(building_id: int)

const SMOKE_THRESHOLD := 420.0

var building_index: RefCounted = null

var _accumulated: Dictionary = {}
var _smoking: Dictionary = {}


func apply_hit(hit_result: RefCounted, round_data: RefCounted) -> void:
	var building_id := int(hit_result.building_id)
	if building_id == 0:
		return
	var profile: Resource = round_data.damage_profile
	var structural := float(profile.structural_damage) if profile != null else 10.0
	# Roof strikes on an extrusion carry more structural weight than a facade
	# graze; refined once damage cells exist.
	if hit_result.hit_zone == "roof":
		structural *= 1.35
	var total := float(_accumulated.get(building_id, 0.0)) + structural
	_accumulated[building_id] = total
	building_damaged.emit(building_id, total, hit_result.relative_height)
	if total >= SMOKE_THRESHOLD and not _smoking.has(building_id):
		_smoking[building_id] = true
		building_smoking.emit(building_id)


func damage_for(building_id: int) -> float:
	return float(_accumulated.get(building_id, 0.0))


func reset() -> void:
	_accumulated.clear()
	_smoking.clear()
