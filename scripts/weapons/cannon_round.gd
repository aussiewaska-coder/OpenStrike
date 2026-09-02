extends RefCounted

# Lightweight per-round state (spec section 13). Deliberately not a RigidBody3D
# and deliberately not a Node - at 625 RPM there are only ~20 of these alive.

var sequence := 0
var spawn_time := 0.0
var origin := Vector3.ZERO
var position := Vector3.ZERO
var previous_position := Vector3.ZERO
var direction := Vector3.FORWARD
var velocity := Vector3.ZERO
var age := 0.0
var distance := 0.0
var is_tracer := false
var damage_profile: Resource = null
var weapon_source := ""
## The flight model this round advances through. Null means the manager's
## shared ballistics, which is what every 30 mm shell wants.
var flight: RefCounted = null


func initialise(
	round_sequence: int,
	muzzle_origin: Vector3,
	launch_direction: Vector3,
	launch_velocity: Vector3,
	tracer: bool,
	profile: Resource,
	source: String
) -> void:
	sequence = round_sequence
	origin = muzzle_origin
	position = muzzle_origin
	previous_position = muzzle_origin
	direction = launch_direction
	velocity = launch_velocity
	age = 0.0
	distance = 0.0
	is_tracer = tracer
	damage_profile = profile
	weapon_source = source
	# Cleared explicitly: rounds are pooled, and a recycled shell that kept the
	# previous occupant's rocket motor would fly like one.
	flight = null
