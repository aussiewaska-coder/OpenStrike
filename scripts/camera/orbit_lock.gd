extends RefCounted

## A ground pivot the travel camera sweeps around.
##
## Tactical orbit turns the camera about the aircraft, so the aircraft can never
## leave the middle of the frame. This locks a point on the ground instead: the
## camera circles that spot and keeps looking at it, and the helicopter is free
## to fly out of shot mid-sweep.

var active := false
var pivot := Vector3.ZERO
var radius := 0.0
var height := 0.0
var angle := 0.0

var _velocity := 0.0

const MINIMUM_RADIUS := 0.001


## Captures the pivot from wherever the camera already is. Radius, height and
## angle are all read back off the current position, so engaging a sweep never
## jumps the view.
func engage(camera_position: Vector3, ground_pivot: Vector3) -> void:
	pivot = ground_pivot
	var offset := camera_position - ground_pivot
	height = offset.y
	offset.y = 0.0
	radius = offset.length()
	if radius < MINIMUM_RADIUS:
		radius = MINIMUM_RADIUS
		offset = Vector3(0.0, 0.0, radius)
	# Matches the trailing-heading convention in main.gd: a heading of zero puts
	# the camera on the pivot's +Z side.
	angle = atan2(offset.x, offset.z)
	_velocity = 0.0
	active = true


func release() -> void:
	active = false
	_velocity = 0.0


## Integrates the sweep with the same eased velocity the tactical orbit uses, so
## both orbits share one feel.
func advance(delta: float, input: float, speed_radians: float, response: float) -> void:
	var target_velocity := input * speed_radians
	var weight := 1.0 - exp(-response * delta)
	_velocity = lerpf(_velocity, target_velocity, weight)
	angle = wrapf(angle + _velocity * delta, -PI, PI)


func camera_position() -> Vector3:
	var direction := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, angle)
	return pivot - direction * radius + Vector3.UP * height
