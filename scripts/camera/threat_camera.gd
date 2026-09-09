extends Node3D

## An aircraft-relative glance at incoming weapons. Never changes flight inputs
## or the player's weapon lock. Sequence IDs survive projectile pool reuse.
var aircraft_camera: Camera3D
var ground_height := Callable()
var camera: Camera3D
var sequence := -1
var watching := false
var wreck_view := false
var _cycle: Array[int] = []
var _wreck_offset := Vector3(45, 22, 55)

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera = Camera3D.new()
	camera.name = "ThreatCamera"
	camera.fov = 58.0
	camera.far = 50000.0
	add_child(camera)
	camera.current = false

static func nearest_first(rounds: Array, point: Vector3) -> Array:
	var sorted := rounds.duplicate()
	sorted.sort_custom(func(a, b): return a.position.distance_squared_to(point) < b.position.distance_squared_to(point))
	return sorted

func cycle(rounds: Array, point: Vector3) -> void:
	if wreck_view:
		return
	if not watching:
		_cycle.clear()
		for round_data in nearest_first(rounds, point):
			_cycle.append(round_data.sequence)
		sequence = -1
	var index := _cycle.find(sequence) + 1 if watching else 0
	while index < _cycle.size():
		var next := _cycle[index]
		if rounds.any(func(r): return r.sequence == next):
			sequence = next
			watching = true
			camera.make_current()
			return
		index += 1
	stop()

func show_wreck(player: Node3D) -> void:
	watching = true
	wreck_view = true
	sequence = -1
	_wreck_offset = -player.global_basis.x.normalized() * 48.0 + player.global_basis.z.normalized() * 28.0 + Vector3.UP * 18.0
	camera.make_current()
	update(0, [], player)

func update(_delta: float, rounds: Array, player: Node3D) -> void:
	if not watching:
		return
	var aim := player.global_position
	if wreck_view:
		camera.global_position = aim + _wreck_offset
	else:
		var found := false
		for round_data in rounds:
			if round_data.sequence == sequence:
				aim = round_data.position
				found = true
				break
		if not found:
			stop()
			return
		var toward := (aim - player.global_position).normalized()
		camera.global_position = player.global_position - toward * 28.0 + Vector3.UP * 10.0
	if ground_height.is_valid():
		camera.global_position.y = maxf(camera.global_position.y, ground_height.call(camera.global_position) + 4.0)
	var direction := aim - camera.global_position
	if not direction.is_zero_approx():
		camera.look_at(aim, Vector3.RIGHT if absf(direction.normalized().y) > 0.98 else Vector3.UP)

func stop() -> void:
	watching = false
	wreck_view = false
	sequence = -1
	_cycle.clear()
	if is_instance_valid(aircraft_camera):
		aircraft_camera.make_current()
