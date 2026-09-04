extends RefCounted

## One enemy Raptor: where it is, what it is doing, and how it gets away from
## you.
##
## Kinematic, not aerodynamic, for the same reason `drone.gd` is: nobody can
## tell a jet is obeying a drag polar, and a second full flight model on a phone
## would be paid for in framerate. Attitude is derived from the path so it banks
## into its turns and looks like an aircraft.
##
## In this phase it carries no weapons, so POSITION is the whole threat. It
## closes, and inside the merge it works for your six rather than for a shot --
## a Raptor sliding onto your tail is legible without a round being fired. And
## like a drone it breaks AWAY when you point at it, never toward you.

enum State {INGRESS, PURSUIT, MERGE, EVADE, EGRESS, DESTROYED}

## Above the player's 134 m/s corner speed, so it cannot simply be out-turned.
const ENEMY_CRUISE_MPS := 200.0
const ENEMY_DASH_MPS := 380.0
## rad/s, near the player's, so the merge is a contest rather than a formality.
const ENEMY_TURN_RATE := 0.32
## Where inbound becomes a committed chase.
const PURSUIT_RANGE_M := 12000.0
## Where the chase becomes a knife fight.
const MERGE_RANGE_M := 2500.0
## Roughly gun-plus-rocket reach.
const THREAT_RANGE_M := 1600.0
## Pointing at it, not merely near it.
const THREAT_CONE_DEGREES := 25.0
const EVADE_SECONDS := 5.0
## Shorter than the time it takes to settle a lead.
const JINK_INTERVAL := 1.6
## A fight that goes nowhere ends, rather than accumulating jets forever.
const EGRESS_AFTER_SECONDS := 45.0
const EGRESS_SECONDS := 20.0
const MIN_ALTITUDE_M := 400.0
const CLIMB_RATE_MPS := 60.0
## How far above the player a merging jet tries to sit before it comes down.
const MERGE_ALTITUDE_ADVANTAGE_M := 250.0

var id := 0
var position := Vector3.ZERO
var velocity := Vector3.ZERO
## Radians, same convention as jet_controller.heading_of: atan2(nose.x, -nose.z).
var heading := 0.0
var speed := ENEMY_CRUISE_MPS
var state: int = State.INGRESS
## +1 or -1: which way the current break goes. Public so the jink test can see
## it reverse.
var break_sign := 1.0
## Offset from the squadron lead, so a formation reads as a formation.
var formation_offset := Vector3.ZERO

var _evade_remaining := 0.0
var _jink_remaining := JINK_INTERVAL
var _egress_remaining := 0.0
var _fight_elapsed := 0.0
var _target_altitude := 0.0
var _desired_heading := 0.0


func nose() -> Vector3:
	return Vector3(sin(heading), 0.0, -cos(heading))


## Proportional to how hard the heading is changing, so it banks into turns.
func bank() -> float:
	return clampf(wrapf(_desired_heading - heading, -PI, PI) * 1.6, -1.2, 1.2)


func update(delta: float, player_position: Vector3, player_nose: Vector3) -> void:
	if state == State.DESTROYED:
		return
	var offset := player_position - position
	var range_m := offset.length()
	_fight_elapsed += delta
	_advance_state(delta, offset, range_m, player_nose)
	_steer(delta, player_position, offset, range_m)
	_move(delta)


func _advance_state(delta: float, offset: Vector3, range_m: float, player_nose: Vector3) -> void:
	if state == State.EGRESS:
		_egress_remaining -= delta
		return
	if state == State.EVADE:
		_evade_remaining -= delta
		_jink_remaining -= delta
		if _jink_remaining <= 0.0:
			break_sign = -break_sign
			_jink_remaining = JINK_INTERVAL
		if _evade_remaining <= 0.0:
			state = State.PURSUIT
		return
	if _threatened(offset, range_m, player_nose):
		state = State.EVADE
		_evade_remaining = EVADE_SECONDS
		_jink_remaining = JINK_INTERVAL
		# Break away from wherever the player's nose is, not toward it.
		break_sign = 1.0 if offset.cross(Vector3.UP).dot(player_nose) > 0.0 else -1.0
		return
	if _fight_elapsed > EGRESS_AFTER_SECONDS:
		state = State.EGRESS
		_egress_remaining = EGRESS_SECONDS
		return
	if range_m <= MERGE_RANGE_M:
		state = State.MERGE
	elif range_m <= PURSUIT_RANGE_M:
		state = State.PURSUIT
	else:
		state = State.INGRESS


## Pointed at, and close enough for it to matter. Both, not either.
func _threatened(offset: Vector3, range_m: float, player_nose: Vector3) -> bool:
	if range_m > THREAT_RANGE_M:
		return false
	var to_jet := -offset
	if to_jet.length_squared() < 1e-6:
		return false
	return rad_to_deg(player_nose.normalized().angle_to(to_jet.normalized())) <= THREAT_CONE_DEGREES


func _steer(delta: float, player_position: Vector3, offset: Vector3, range_m: float) -> void:
	match state:
		State.EVADE:
			# Away from the player, turned hard to one side, and descending is
			# where a gun fighter least wants to follow.
			var away := -offset
			var side := away.cross(Vector3.UP).normalized() * break_sign
			_desired_heading = _heading_of(away.normalized() + side * 0.9)
			speed = ENEMY_DASH_MPS
			_target_altitude = maxf(player_position.y - 200.0, MIN_ALTITUDE_M)
		State.EGRESS:
			_desired_heading = _heading_of(-offset)
			speed = ENEMY_DASH_MPS
			_target_altitude = maxf(position.y, MIN_ALTITUDE_M)
		State.MERGE:
			# For the six, not for a shot: aim behind the player rather than at
			# it, and hold a little height in hand.
			var behind := player_position - _player_forward_guess(offset) * 600.0
			_desired_heading = _heading_of(behind - position)
			speed = ENEMY_DASH_MPS
			_target_altitude = maxf(player_position.y + MERGE_ALTITUDE_ADVANTAGE_M, MIN_ALTITUDE_M)
		_:
			_desired_heading = _heading_of(offset + formation_offset)
			speed = ENEMY_CRUISE_MPS if range_m > PURSUIT_RANGE_M else ENEMY_DASH_MPS
			_target_altitude = maxf(player_position.y, MIN_ALTITUDE_M)
	heading = _turn_toward(heading, _desired_heading, ENEMY_TURN_RATE * delta)


## With no player velocity to read, the direction it is being chased from is a
## good enough guess at where the player is pointing.
func _player_forward_guess(offset: Vector3) -> Vector3:
	var flat := Vector3(offset.x, 0.0, offset.z)
	return flat.normalized() if flat.length_squared() > 1e-6 else Vector3.FORWARD


func _move(delta: float) -> void:
	var climb := clampf(_target_altitude - position.y, -CLIMB_RATE_MPS, CLIMB_RATE_MPS)
	velocity = nose() * speed + Vector3(0.0, climb, 0.0)
	position += velocity * delta
	position.y = maxf(position.y, MIN_ALTITUDE_M)


static func _heading_of(direction: Vector3) -> float:
	if direction.length_squared() < 1e-6:
		return 0.0
	return atan2(direction.x, -direction.z)


static func _turn_toward(from: float, to: float, max_step: float) -> float:
	var difference := wrapf(to - from, -PI, PI)
	return from + clampf(difference, -max_step, max_step)
