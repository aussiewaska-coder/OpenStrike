extends RefCounted

## Authored fixed-wing views. External cameras follow a bounded 3D flight path
## and use separate body/aim springs; cockpit inherits the airframe directly.

enum Mode {COCKPIT, PURSUIT, TRACK, ISOMETRIC}


## The camera falls back as the aircraft accelerates, which reads as the
## aircraft pulling away from the viewer.
static func trailing_distance(
	speed_mps: float,
	minimum_speed: float,
	maximum_speed: float,
	base_distance: float,
	distance_gain: float
) -> float:
	var span := maxf(maximum_speed - minimum_speed, 1.0)
	var fraction := clampf((speed_mps - minimum_speed) / span, 0.0, 1.0)
	return base_distance + fraction * distance_gain


## Fixed-wing triggers are rudder pedals. They must never also enter the
## helicopter's camera sweep, and a helicopter orbit command likewise owns
## them before the camera does.
static func routed_orbit_input(
	raw_input: float,
	fixed_wing_active: bool,
	aircraft_is_orbiting: bool
) -> float:
	return 0.0 if fixed_wing_active or aircraft_is_orbiting else raw_input


## Right-stick look is always available in the jet, and the cockpit view STAYS
## where the pilot left it. A head does not spring back to the instrument panel
## when you stop turning it, and a view that does makes checking six impossible:
## the moment you release the stick to do anything else, you lose the picture.
##
## Recentring is therefore a deliberate command rather than a consequence of
## letting go -- see main.gd's R3 handling.
static func updated_look(
	current: Vector2,
	input: Vector2,
	speed: float,
	_return_response: float,
	delta: float
) -> Vector2:
	if input.is_zero_approx():
		return current
	return Vector2(
		clampf(current.x - input.x * speed * delta, -1.0, 1.0),
		clampf(current.y - input.y * speed * delta, -1.0, 1.0)
	)


## Snapping the head forward. Returns true while there is anything to recentre,
## so the caller can spend the button on something else when the view is
## already straight ahead.
static func is_look_displaced(look: Vector2, threshold := 0.02) -> bool:
	return look.length() > threshold


## External orbit can pass either side of the tail indefinitely. Normalized
## yaw wraps at +/-1 (the same 180-degree position) while pitch stays bounded.
static func updated_external_look(
	current: Vector2,
	input: Vector2,
	speed: float,
	_return_response: float,
	delta: float
) -> Vector2:
	if not input.is_zero_approx():
		return Vector2(
			wrapf(current.x - input.x * speed * delta, -1.0, 1.0),
			clampf(current.y - input.y * speed * delta, -1.0, 1.0)
		)
	return current


static func orbited_position(focus: Vector3, camera_position: Vector3, look_basis: Basis) -> Vector3:
	return focus + look_basis * (camera_position - focus)


## A sphere, and nothing else: the camera orbits the aircraft at whatever radius
## the view and the zoom have already set, and the radius does not change
## because the player looked somewhere.
##
## It used to. Pursuit stretched its boom to 1.65 times the radius as the look
## grew, and the aim point slid from the velocity lead onto the aircraft at the
## same time, so orbiting the aircraft also dollied and re-framed it. Two
## smoothstepped blends running against each other is what made the 360 read as
## warped rather than as a camera moving round a fixed object.
static func external_orbit_position(
	_mode: int,
	focus: Vector3,
	camera_position: Vector3,
	look_basis: Basis,
	_look: Vector2
) -> Vector3:
	return focus + look_basis * (camera_position - focus)


## Smooth around the sphere, carrying its centre with the displayed aircraft.
## Interpolating world positions cuts chords and adds aircraft travel to zoom.
static func smooth_orbit_offset(current: Vector3, wanted: Vector3, weight: float) -> Vector3:
	if current.length_squared() < 0.0001 or wanted.length_squared() < 0.0001:
		return current.lerp(wanted, weight)
	var radius := lerpf(current.length(), wanted.length(), weight)
	return current.normalized().slerp(wanted.normalized(), weight).normalized() * radius


## Keep a usable horizon and lift the orbit over terrain without stretching
## its radius, except when the entire sphere is below the clearance height.
static func clear_orbit_position(focus: Vector3, position: Vector3, floor_y: float) -> Vector3:
	var offset := position - focus
	var radius := offset.length()
	if radius < 0.001:
		return Vector3(position.x, maxf(position.y, floor_y), position.z)
	var limit := radius * sin(deg_to_rad(85.0))
	var height := maxf(clampf(offset.y, -limit, limit), floor_y - focus.y)
	var horizontal := Vector3(offset.x, 0.0, offset.z)
	if horizontal.length_squared() < 0.000001:
		horizontal = Vector3.BACK
	return focus + horizontal.normalized() * sqrt(maxf(radius * radius - height * height, 0.0)) + Vector3.UP * height


## A small neck roll follows a sideways glance, with no tilt looking forward.
static func head_tilt(yaw: float) -> float:
	return -sin(yaw) * deg_to_rad(6.0)


static func cockpit_look_basis(yaw: float, pitch: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) \
		* Basis(Vector3.BACK, head_tilt(yaw))


static func tracking_basis(direction: Vector3, reference: Basis, previous: Basis, cockpit: bool) -> Basis:
	var forward := direction.normalized()
	var up := reference.y
	if absf(forward.dot(up)) > 0.98:
		# Remove the previous neck roll before reusing its up vector, so a
		# stationary target overhead cannot accumulate tilt every frame.
		var neutral_previous := previous
		if cockpit:
			var previous_local := reference.inverse() * -previous.z
			neutral_previous *= Basis(Vector3.BACK, -head_tilt(atan2(-previous_local.x, -previous_local.z)))
		up = neutral_previous.y
		if absf(forward.dot(up)) > 0.98:
			up = neutral_previous.x
	var result := Basis.looking_at(forward, up)
	if cockpit:
		var local := reference.inverse() * forward
		var yaw := atan2(-local.x, -local.z)
		result *= Basis(Vector3.BACK, head_tilt(yaw))
	return result


static func flight_direction(
	velocity: Vector3,
	nose: Vector3,
	maximum_pitch_degrees := 35.0
) -> Vector3:
	var direction := velocity if velocity.length_squared() >= 1.0 else nose
	if direction.is_zero_approx():
		return Vector3.FORWARD
	direction = direction.normalized()
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.is_zero_approx():
		horizontal = Vector3(nose.x, 0.0, nose.z)
	if horizontal.is_zero_approx():
		horizontal = Vector3.FORWARD
	horizontal = horizontal.normalized()
	var pitch := clampf(
		asin(clampf(direction.y, -1.0, 1.0)),
		-deg_to_rad(maximum_pitch_degrees),
		deg_to_rad(maximum_pitch_degrees)
	)
	return horizontal * cos(pitch) + Vector3.UP * sin(pitch)


static func desired_position(
	mode: int,
	focus: Vector3,
	direction: Vector3,
	base_distance: float,
	base_height: float
) -> Vector3:
	match mode:
		Mode.PURSUIT:
			var close_distance := maxf(base_distance * 0.45, 15.0)
			var close_height := maxf(base_height * 0.35, 3.0)
			return focus - direction * close_distance + Vector3.UP * close_height
		Mode.TRACK:
			return focus - direction * base_distance * 1.65 + Vector3.UP * base_height * 2.0
		Mode.ISOMETRIC:
			var diagonal := Vector3(1.0, 0.0, 1.0).normalized()
			return focus + diagonal * base_distance * 2.0 \
				+ Vector3.UP * maxf(base_height * 5.5, base_distance * 1.2)
		_:
			return focus - direction * base_distance + Vector3.UP * base_height


## Framing leads the velocity instead of pinning the aircraft to dead centre.
## The lead is bounded so a speed spike cannot throw the target across screen.
static func look_target(
	mode: int,
	focus: Vector3,
	velocity: Vector3,
	direction: Vector3,
	base_distance: float
) -> Vector3:
	if mode == Mode.ISOMETRIC:
		var ground_direction := Vector3(direction.x, 0.0, direction.z).normalized()
		return focus + ground_direction * maxf(18.0, base_distance * 0.3)
	if mode == Mode.COCKPIT:
		return focus + direction * 100.0
	var lead_seconds := 0.24 if mode == Mode.TRACK else 0.14
	var maximum_lead := 45.0 if mode == Mode.TRACK else 24.0
	var lead := velocity * lead_seconds
	if lead.length() > maximum_lead:
		lead = lead.normalized() * maximum_lead
	if lead.length_squared() < 1.0:
		lead = direction * minf(maximum_lead, base_distance * 0.3)
	return focus + lead


## Each view has its own lens. Pursuit is wide for speed and peripheral
## awareness; tracking and tactical progressively compress the scene.
## The cockpit's default lens is also its tightest. Widening past it is the
## pilot leaning back off the panel to take in more of the canopy; there is
## nothing useful to gain by narrowing, because the seat cannot move forward.
const COCKPIT_FOV := 70.0
const COCKPIT_FOV_WIDE := 100.0
## Zoom values at or below the default are the same picture -- the cockpit only
## opens up, and only as the player zooms out past neutral.
const COCKPIT_ZOOM_DEFAULT := 1.0


static func cockpit_field_of_view(zoom: float, speed_fraction: float, zoom_max: float) -> float:
	var span := maxf(zoom_max - COCKPIT_ZOOM_DEFAULT, 0.001)
	var widen := clampf((zoom - COCKPIT_ZOOM_DEFAULT) / span, 0.0, 1.0)
	return lerpf(COCKPIT_FOV, COCKPIT_FOV_WIDE, widen) \
		+ clampf(speed_fraction, 0.0, 1.0) * 1.5


static func field_of_view(
	mode: int,
	zoom: float,
	speed_fraction: float,
	zoom_max := COCKPIT_ZOOM_DEFAULT
) -> float:
	if mode == Mode.COCKPIT:
		return cockpit_field_of_view(zoom, speed_fraction, zoom_max)
	var base := 68.0
	var speed_gain := 8.0
	match mode:
		Mode.TRACK:
			base = 60.0
			speed_gain = 5.0
		Mode.ISOMETRIC:
			base = 52.0
			speed_gain = 0.0
	var zoom_bias := clampf((1.0 - zoom) * 10.0, -5.0, 8.0)
	return clampf(base + zoom_bias + clampf(speed_fraction, 0.0, 1.0) * speed_gain, 45.0, 92.0)


## External views receive only a hint of airframe roll. Full roll is reserved
## for cockpit, while tactical remains locked to the world horizon.
static func camera_up(mode: int, airframe_up: Vector3) -> Vector3:
	var aircraft_up := airframe_up.normalized() if not airframe_up.is_zero_approx() else Vector3.UP
	if mode == Mode.COCKPIT:
		return aircraft_up
	var roll_weight := 0.22 if mode == Mode.PURSUIT else 0.1
	if mode == Mode.ISOMETRIC:
		roll_weight = 0.0
	var blended := Vector3.UP.lerp(aircraft_up, roll_weight)
	return blended.normalized() if not blended.is_zero_approx() else Vector3.UP


static func position_response(mode: int) -> float:
	match mode:
		Mode.TRACK:
			return 4.5
		Mode.ISOMETRIC:
			return 5.5
		_:
			return 7.0


static func aim_response(mode: int) -> float:
	match mode:
		Mode.TRACK:
			return 7.5
		Mode.ISOMETRIC:
			return 8.0
		_:
			return 12.0


static func allows_free_look(mode: int) -> bool:
	return mode != Mode.ISOMETRIC


## Head bob, in degrees of camera rotation. Cockpit only.
##
## This is the second attempt. The first was high-frequency synthetic buffet
## applied to the airframe, and it made both the external model and the cockpit
## camera jitter -- the note on jet_controller._update_visual records it being
## torn out. So: low frequency, sub-degree, applied to the CAMERA and never to
## the airframe, and driven by what the aircraft is actually doing rather than
## by noise. The two axes run at different rates so the motion is a slow figure
## rather than a single rocking axis; they realign every ten seconds, which is
## also the period the caller's clock wraps on.
##
## Amplitude follows load factor rather than speed, because what a pilot's head
## does under G is the part worth feeling: heavy under the pull, still when
## unloaded.
const BOB_PITCH_HZ := 1.4
const BOB_ROLL_HZ := 0.9
const BOB_PITCH_DEGREES := 0.28
const BOB_ROLL_DEGREES := 0.18
## Below one G there is nothing pressing on the pilot and the bob dies away.
const BOB_LOAD_REFERENCE := 4.0


static func head_bob(time_seconds: float, load_factor: float, speed_fraction: float) -> Vector2:
	var loaded := clampf((absf(load_factor) - 1.0) / BOB_LOAD_REFERENCE, 0.0, 1.0)
	# A little always present at speed, so straight and level is not dead still.
	var weight := clampf(0.25 * clampf(speed_fraction, 0.0, 1.0) + loaded, 0.0, 1.0)
	if weight <= 0.001:
		return Vector2.ZERO
	return Vector2(
		sin(time_seconds * TAU * BOB_PITCH_HZ) * BOB_PITCH_DEGREES * weight,
		sin(time_seconds * TAU * BOB_ROLL_HZ) * BOB_ROLL_DEGREES * weight
	)
