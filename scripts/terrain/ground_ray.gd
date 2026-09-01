extends RefCounted

## Where a ray meets the terrain.
##
## Used to turn a screen tap into a point on the ground. The height field is a
## function rather than a collision body -- there are no physics shapes under
## the streamed terrain -- so this marches the ray and refines the crossing.


## `ground_height` takes (world_x, world_z) and returns terrain height. Returns
## an empty dictionary when the ray never goes below the ground inside range.
static func intersect(
	origin: Vector3,
	direction: Vector3,
	ground_height: Callable,
	maximum_distance := 20000.0,
	step := 25.0
) -> Dictionary:
	if direction.is_zero_approx() or step <= 0.0:
		return {}
	var ray := direction.normalized()
	var travelled := 0.0
	var point := origin
	var previous_gap: float = point.y - float(ground_height.call(point.x, point.z))
	if previous_gap <= 0.0:
		return {"point": origin, "distance": 0.0}
	while travelled < maximum_distance:
		var next_point := point + ray * step
		var gap: float = next_point.y - float(ground_height.call(next_point.x, next_point.z))
		travelled += step
		if gap <= 0.0:
			# Bisect the crossing: a 25 m step is far too coarse to aim with.
			var near := point
			var far := next_point
			for _refinement in range(12):
				var middle := (near + far) * 0.5
				var middle_gap: float = middle.y - float(ground_height.call(middle.x, middle.z))
				if middle_gap <= 0.0:
					far = middle
				else:
					near = middle
			var hit := (near + far) * 0.5
			return {"point": hit, "distance": origin.distance_to(hit)}
		point = next_point
		previous_gap = gap
	return {}
