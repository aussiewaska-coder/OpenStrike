extends RefCounted

# Standardised impact record (spec section 24). Every producer - terrain,
# batched OSM buildings, water, future landmark meshes - returns this shape so
# the cannon never learns which system answered.

enum ObjectKind { NONE, TERRAIN, BUILDING, WATER, ENTITY }

var hit := false
var position := Vector3.ZERO
var normal := Vector3.UP
var distance := 0.0
# Segment parameter in 0..1, used to pick the nearest of several candidates.
var t := 1.0
var surface_type := 0
var object_type := ObjectKind.NONE
var object_id := 0
var building_id := 0
var hit_zone := ""
# Damage-cell coordinates resolved at impact time so projectile code never has
# to be revisited when procedural destruction lands (spec section 51).
var relative_height := 0.0
var wall_index := -1
var penetration_depth := 0.0
var incident_velocity := Vector3.ZERO


static func miss() -> RefCounted:
	return new()


func incident_direction() -> Vector3:
	return incident_velocity.normalized() if not incident_velocity.is_zero_approx() else Vector3.DOWN


func impact_energy() -> float:
	return incident_velocity.length_squared()
