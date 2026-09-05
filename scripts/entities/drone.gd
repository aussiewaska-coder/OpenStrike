extends RefCounted

## One drone: where it is, what it is doing, and how it gets away from you.
##
## Kinematic, not aerodynamic. Attitude is derived from the path so it banks
## into turns and looks like an aircraft, but there is no lift and no drag;
## nobody can tell a drone is obeying a drag polar, and ten flight models on a
## phone would be paid for in framerate.
##
## The behaviour that matters is evasion. A threatened drone breaks AWAY from
## the player's nose -- never toward it, that is a head-on and the drone loses
## it -- dashes, jinks on a timer so it cannot be led with a steady deflection,
## and drops below the player where a gun fighter least wants to follow. And it
## ABORTS its attack run: a pilot on a drone's tail saves the building without
## firing; shooting it down is what stops it coming back.

enum State {INBOUND, ATTACK_RUN, EVADING, EGRESS, DESTROYED}

const DRONE_CRUISE_MPS := 95.0
## Briefly above the F-22's cruise, so a chase is a chase.
const DRONE_DASH_MPS := 150.0
## rad/s. Tighter than the F-22 at speed, looser than it at corner.
const DRONE_TURN_RATE := 0.9
const ATTACK_ENTRY_RANGE := 2500.0
const BOMB_RELEASE_RANGE := 350.0
## Roughly gun-plus-rocket reach.
const THREAT_RANGE := 1400.0
## Pointing at it, not merely near it.
const THREAT_CONE_DEGREES := 25.0
const DASH_SECONDS := 4.0
## Shorter than the time it takes to settle a lead.
const JINK_INTERVAL := 1.6
const EVADE_SECONDS := 5.0
const EGRESS_SECONDS := 12.0

const INBOUND_ALTITUDE := 700.0
const MIN_ALTITUDE := 120.0
## How far under the player an evading drone tries to get.
const DROP_BELOW_PLAYER := 150.0
## Vertical rate cap, so altitude changes read as flight rather than as lifts.
const CLIMB_RATE := 25.0

var id := 0
var position := Vector3.ZERO
var velocity := Vector3.ZERO
## Radians, same convention as jet_controller.heading_of: atan2(nose.x, -nose.z).
var heading := 0.0
var speed := DRONE_CRUISE_MPS
var state: int = State.INBOUND
var target_handle := -1
var target_position := Vector3.ZERO
## +1 or -1: which way the current break goes. Public so the jink test can see
## it reverse.
var break_sign := 1.0

var _target_altitude := INBOUND_ALTITUDE
var _evade_remaining := 0.0
var _dash_remaining := 0.0
var _jink_remaining := 0.0
var _egress_remaining := 0.0
var _last_range := INF
var _near_city := false
var _desired_heading := 0.0


func nose() -> Vector3:
	return Vector3(sin(heading), 0.0, -cos(heading))


## Bank for the visual: proportional to how hard the heading is changing.
func bank() -> float:
	var error := wrapf(_desired_heading - heading, -PI, PI)
	return clampf(error * 1.4, -1.1, 1.1)


func wants_target() -> bool:
	return state == State.INBOUND and target_handle < 0 and _near_city


func assign_target(handle: int, at: Vector3) -> void:
	target_handle = handle
	target_position = at
	state = State.ATTACK_RUN


func destroy() -> void:
	state = State.DESTROYED
	target_handle = -1


## Range, cone and closure together. Any one alone is not a threat: a player
## flying past at 500 m is not attacking, and neither is one pointing at the
## drone from four kilometres.
func is_threatened(player_position: Vector3, player_nose: Vector3) -> bool:
	var to_drone := position - player_position
	var range_m := to_drone.length()
	if range_m > THREAT_RANGE or range_m < 0.001:
		return false
	var cone := cos(deg_to_rad(THREAT_CONE_DEGREES))
	if player_nose.normalized().dot(to_drone / range_m) < cone:
		return false
	return range_m < _last_range


## One step. Returns true if a bomb should be released this frame.
func update(
	delta: float,
	player_position: Vector3,
	player_nose: Vector3,
	city_centre: Vector3,
	rng: RandomNumberGenerator
) -> bool:
	if state == State.DESTROYED:
		# Dead weight: falls, keeps its heading, nothing else.
		velocity.y -= 9.80665 * delta
		position += velocity * delta
		return false

	var release := false
	var threatened := is_threatened(player_position, player_nose)
	_last_range = position.distance_to(player_position)
	_near_city = Vector2(position.x, position.z).distance_to(Vector2(city_centre.x, city_centre.z)) <= ATTACK_ENTRY_RANGE

	if threatened and state != State.EVADING:
		_begin_evasion(player_position, player_nose)
	if state == State.EVADING and threatened:
		# Every frame under threat resets the clock, so the drone keeps
		# evading for EVADE_SECONDS after the LAST moment it was threatened.
		_evade_remaining = EVADE_SECONDS

	match state:
		State.INBOUND:
			_desired_heading = _heading_to(city_centre)
			_target_altitude = INBOUND_ALTITUDE
		State.ATTACK_RUN:
			_desired_heading = _heading_to(target_position)
			# Descend onto the target so the run reads as a dive, but never
			# under the minimum: a drone that flies into the sea is a bug.
			_target_altitude = maxf(target_position.y + 120.0, MIN_ALTITUDE)
			if Vector2(position.x, position.z).distance_to(Vector2(target_position.x, target_position.z)) <= BOMB_RELEASE_RANGE:
				release = true
				_begin_egress(city_centre)
		State.EVADING:
			_update_evasion(delta, player_position, rng)
		State.EGRESS:
			_target_altitude = INBOUND_ALTITUDE
			_egress_remaining -= delta
			if _egress_remaining <= 0.0:
				state = State.INBOUND

	_steer(delta)
	return release


func _heading_to(point: Vector3) -> float:
	var to_point := point - position
	return atan2(to_point.x, -to_point.z)


func _begin_evasion(player_position: Vector3, player_nose: Vector3) -> void:
	state = State.EVADING
	target_handle = -1
	_evade_remaining = EVADE_SECONDS
	_dash_remaining = DASH_SECONDS
	_jink_remaining = JINK_INTERVAL
	speed = DRONE_DASH_MPS
	# Break to the side that increases the angle off the player's nose. The
	# sign of the cross product of nose and approach says which side of the
	# nose the drone is already on; going further that way is "away".
	var approach := position - player_position
	var cross_y := player_nose.z * approach.x - player_nose.x * approach.z
	break_sign = 1.0 if cross_y >= 0.0 else -1.0


func _update_evasion(delta: float, player_position: Vector3, rng: RandomNumberGenerator) -> void:
	_evade_remaining -= delta
	_dash_remaining -= delta
	_jink_remaining -= delta
	if _jink_remaining <= 0.0:
		_jink_remaining = JINK_INTERVAL * rng.randf_range(0.7, 1.3)
		break_sign = -break_sign
	if _dash_remaining <= 0.0:
		speed = DRONE_CRUISE_MPS
	# Perpendicular to the line from the player, on the chosen side.
	var from_player := position - player_position
	from_player.y = 0.0
	if from_player.is_zero_approx():
		from_player = nose()
	var away_heading := atan2(from_player.x, -from_player.z)
	_desired_heading = away_heading + break_sign * PI * 0.5
	# Drop under the player if there is room. A gun fighter hates looking down.
	_target_altitude = maxf(player_position.y - DROP_BELOW_PLAYER, MIN_ALTITUDE)
	if _evade_remaining <= 0.0:
		state = State.INBOUND
		speed = DRONE_CRUISE_MPS


func _begin_egress(city_centre: Vector3) -> void:
	state = State.EGRESS
	target_handle = -1
	_egress_remaining = EGRESS_SECONDS
	# Turn back the way it came: away from the city.
	var away := position - city_centre
	_desired_heading = atan2(away.x, -away.z)


## Turn toward the desired heading at the rate cap, hold speed, and ease toward
## the target altitude. Position integrates from the resulting velocity.
func _steer(delta: float) -> void:
	var error := wrapf(_desired_heading - heading, -PI, PI)
	var turn := clampf(error, -DRONE_TURN_RATE * delta, DRONE_TURN_RATE * delta)
	heading = wrapf(heading + turn, -PI, PI)
	var vertical := clampf(_target_altitude - position.y, -CLIMB_RATE, CLIMB_RATE)
	velocity = nose() * speed + Vector3(0.0, vertical, 0.0)
	position += velocity * delta
