extends RefCounted

## Arcade signature tuning, not real aircraft/RCS measurements.
var radar_signature := 1.0
var heat_signature := 1.0
var afterburner := 0.0
var nose := Vector3.FORWARD
var velocity := Vector3.ZERO
var position := Vector3.ZERO

func radar_range() -> float:
	return 8500.0 * sqrt(radar_signature)

func heat_range() -> float:
	return 3200.0 * heat_signature + 3000.0 * afterburner

func heat_strength(observer: Vector3) -> float:
	var to_observer := (observer - position).normalized()
	var exhaust_aspect := lerpf(0.55, 1.0, clampf(-nose.dot(to_observer), 0, 1))
	return heat_signature * (1.0 + 5.0 * afterburner) * exhaust_aspect

func beaming(observer: Vector3) -> bool:
	return velocity.length() > 160.0 and absf(velocity.normalized().dot((observer - position).normalized())) < 0.23

func radar_trackable(observer: Vector3) -> bool:
	# Flying across the radar line can drop a weak return. Turning alone is
	# not immunity: it takes sustained beaming and the missile has loss memory.
	return not (radar_signature < 0.7 and beaming(observer) and position.distance_to(observer) > 700.0)
