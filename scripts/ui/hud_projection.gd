extends RefCounted

## Where the visor's conformal symbols live, expressed as world directions.
##
## The helmet's trick is that the horizon, the ladder and the flight path marker
## are stuck to the WORLD, not to the screen: swing the view and they stay put.
## The cheapest way to get that is to compute a world point for each symbol and
## let `Camera3D.unproject_position` do the rest. Keeping the world half here,
## pure and static, is what makes a head-up display testable without a viewport.

## Far enough to read as infinity. Only ever unprojected, never rendered, so it
## is free to sit outside the 30 km far plane.
const CONFORMAL_DISTANCE_M := 50000.0
const PITCH_LADDER_STEP_DEGREES := 5.0
## Below this the velocity vector is noise, and the marker parks on the nose.
const FPM_MIN_SPEED_MPS := 20.0


## The camera's forward flattened onto the horizontal plane: the direction the
## horizon runs across, and the axis the ladder climbs from.
static func level_forward(basis: Basis) -> Vector3:
	var forward := -basis.z
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 1e-6:
		# Straight up or straight down: the forward vector has no horizontal
		# part left, so borrow the camera's own up, which does.
		var up := basis.y
		flat = Vector3(up.x, 0.0, up.z)
	if flat.length_squared() < 1e-6:
		return Vector3.FORWARD
	return flat.normalized()


static func level_right(basis: Basis) -> Vector3:
	return level_forward(basis).cross(Vector3.UP).normalized()


static func far_point(origin: Vector3, direction: Vector3) -> Vector3:
	return origin + direction.normalized() * CONFORMAL_DISTANCE_M


## Two points at the camera's own altitude, left and right. Because they are
## level and far away, the line between them projects onto the true horizon --
## it cants under roll and slides under pitch without being told to.
static func horizon_points(basis: Basis, origin: Vector3) -> Array:
	var right := level_right(basis)
	var ahead := origin + level_forward(basis) * CONFORMAL_DISTANCE_M
	return [
		ahead - right * CONFORMAL_DISTANCE_M,
		ahead + right * CONFORMAL_DISTANCE_M,
	]


## Constant-elevation arcs on the sphere around the pilot. Their projection
## curves naturally away from the centre and rolls with the real horizon.
static func pitch_arc(basis: Basis, pitch_degrees: float, start_azimuth: float, end_azimuth: float, segments := 8) -> PackedVector3Array:
	var points := PackedVector3Array()
	var pitch := deg_to_rad(pitch_degrees)
	var forward := level_forward(basis)
	var right := level_right(basis)
	for index in range(segments + 1):
		var azimuth := deg_to_rad(lerpf(start_azimuth, end_azimuth, float(index) / float(segments)))
		points.append((forward * cos(azimuth) + right * sin(azimuth)) * cos(pitch) + Vector3.UP * sin(pitch))
	return points


## Keep attitude symbols inside the useful central area of the visor, fading
## before the edge instead of drawing over every peripheral instrument.
static func visor_alpha(point: Vector2, viewport_size: Vector2) -> float:
	var radius := viewport_size * Vector2(0.37, 0.39)
	if radius.x <= 0.0 or radius.y <= 0.0:
		return 0.0
	var distance := ((point - viewport_size * 0.5) / radius).length()
	return 1.0 - smoothstep(0.65, 1.0, distance)


static func ladder_direction(basis: Basis, degrees: float) -> Vector3:
	return level_forward(basis).rotated(level_right(basis), deg_to_rad(degrees)).normalized()


static func ladder_degrees() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var degrees := -90.0
	while degrees <= 90.0 + 0.001:
		out.append(degrees)
		degrees += PITCH_LADDER_STEP_DEGREES
	return out


static func flight_path_direction(velocity: Vector3, basis: Basis) -> Vector3:
	if velocity.length() < FPM_MIN_SPEED_MPS:
		return (-basis.z).normalized()
	return velocity.normalized()
