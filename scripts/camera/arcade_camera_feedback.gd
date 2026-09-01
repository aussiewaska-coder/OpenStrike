class_name ArcadeCameraFeedback
extends RefCounted

var trauma_decay_per_second := 1.7
var maximum_rotation_degrees := Vector3(0.72, 0.9, 0.4)

var trauma := 0.0
var _phase := 0.0


static func speed_fov_offset(speed: float, reference_speed: float, maximum_degrees: float) -> float:
	if reference_speed <= 0.0 or maximum_degrees <= 0.0:
		return 0.0
	var ratio := clampf(speed / reference_speed, 0.0, 1.0)
	return smoothstep(0.15, 1.0, ratio) * maximum_degrees


func add_recoil(amount: float = 0.08) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func add_impact(distance_m: float, destructive: bool) -> void:
	var reach := 650.0 if destructive else 180.0
	var strength := 0.82 if destructive else 0.1
	var ratio := maxf(distance_m, 0.0) / reach
	trauma = clampf(trauma + strength / (1.0 + ratio * ratio), 0.0, 1.0)


func update(delta: float) -> Vector3:
	_phase += maxf(delta, 0.0)
	trauma = move_toward(trauma, 0.0, trauma_decay_per_second * maxf(delta, 0.0))
	var amplitude := trauma * trauma
	return Vector3(
		sin(_phase * 43.1) * maximum_rotation_degrees.x,
		sin(_phase * 51.7 + 1.4) * maximum_rotation_degrees.y,
		sin(_phase * 37.9 + 2.6) * maximum_rotation_degrees.z
	) * amplitude
