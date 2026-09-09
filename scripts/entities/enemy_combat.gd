extends Node3D

## Hostile weapons have their own pool and world-only collision query: they
## cannot hit their launcher, count as player kills, or enter the weapon camera.
const MANAGER := preload("res://scripts/weapons/projectile_manager.gd")
const FLIGHT := preload("res://scripts/weapons/hostile_missile_flight.gd")
const FX := preload("res://scripts/effects/missile_fx.gd")
const TRACKER := preload("res://scripts/targeting/target_tracker.gd")
const HIT := preload("res://scripts/world/world_hit_result.gd")
const ENEMY := preload("res://scripts/entities/enemy_jet.gd")
const PLAYER_ID := -2
const SAM_MIN_AGL_M := 152.4 # Strictly ABOVE 500 feet above local terrain.
const MAX_MISSILES := 1
const START_GRACE_SECONDS := 30.0
const BREATHER_SECONDS := 20.0
const DEFENCE := preload("res://scripts/weapons/aircraft_defence.gd")
signal player_hit(point: Vector3)
var defence := DEFENCE.new()
var countermeasures: Node3D
var grace_remaining := START_GRACE_SECONDS
var breather_remaining := 0.0
var projectiles: Node3D
var world_query: RefCounted
var trails: MeshInstance3D
var strike_fire: Node3D
var impact_fx: Node3D
var _sources := {}
var _player := {}
var _agl := 0.0
var _sequence := 3000000
var _launch_gap := 0.0
var _scan_in := 0.0
var _locks := 0

func _ready() -> void:
	projectiles = MANAGER.new()
	add_child(projectiles)
	projectiles.set_physics_process(false)
	projectiles.projectile_impacted.connect(_impact)
	projectiles.projectile_expired.connect(_expired)
	var visuals := FX.new()
	visuals.projectile_manager = projectiles
	add_child(visuals)

func clear() -> void:
	for round_data in projectiles.active_rounds:
		_expired(round_data)
	projectiles.clear()
	_sources.clear()
	_player.clear()
	_locks = 0
	_launch_gap = 0.0
	grace_remaining = START_GRACE_SECONDS
	breather_remaining = 0.0
	_scan_in = 0.0

func update(delta: float, point: Vector3, velocity: Vector3, agl: float, jets: Array, sites: Array, active := true) -> void:
	if not active:
		if not _player.is_empty() or not projectiles.active_rounds.is_empty():
			clear()
		return
	_player = TRACKER.contact(PLAYER_ID, TRACKER.Kind.AIR_JET, point, velocity, "PLAYER")
	_agl = agl
	defence.position = point
	defence.velocity = velocity
	grace_remaining = maxf(0, grace_remaining - delta)
	breather_remaining = maxf(0, breather_remaining - delta)
	# Retirement and defensive breaks are immediate even between sight scans.
	var live_ids := {}
	for jet in jets:
		if jet.state not in [ENEMY.State.DESTROYED, ENEMY.State.EGRESS]:
			live_ids[jet.id] = true
			if jet.state == ENEMY.State.EVADE and _sources.has(jet.id):
				_sources[jet.id].visible = false
	for site in sites:
		live_ids[site.id] = true
	for id in _sources.keys():
		if not live_ids.has(id):
			_sources.erase(id)
	_launch_gap = maxf(0.0, _launch_gap - delta)
	_scan_in -= delta
	# Long sight lines are sampled at 5 Hz, not for every projectile substep.
	if _scan_in <= 0.0:
		_scan_in = 0.2
		_scan_sources(jets, sites)
	_locks = 0
	for source: Dictionary in _sources.values():
		source.cooldown = maxf(0.0, source.cooldown - delta)
		if source.sam and not sam_altitude_allows_lock(_agl):
			source.visible = false
		var acquiring: bool = source.visible and source.cooldown <= 0 and _locks == 0 and grace_remaining <= 0 and breather_remaining <= 0 and projectiles.active_rounds.is_empty()
		source.lock_time = source.lock_time + delta if acquiring else 0.0
		if acquiring:
			_locks += 1
		var acquire := 4.0 / sqrt(defence.radar_signature) if source.sam else lerpf(4.0, 2.5, defence.afterburner)
		if grace_remaining <= 0 and breather_remaining <= 0 and source.lock_time >= acquire and source.cooldown <= 0.0 and _launch_gap <= 0.0 and projectiles.active_rounds.size() < MAX_MISSILES:
			_launch(source)
	projectiles.hit_query = world_query
	projectiles.step(delta)
	if trails != null:
		for round_data in projectiles.active_rounds:
			if round_data.flight.is_boosting(round_data.age):
				trails.push_point(round_data.sequence, round_data.position)
			elif round_data.age > 0.5:
				trails.end_trail(round_data.sequence)

static func sam_altitude_allows_lock(agl: float) -> bool:
	return agl > SAM_MIN_AGL_M

func _scan_sources(jets: Array, sites: Array) -> void:
	var alive := {}
	for jet in jets:
		if jet.state in [ENEMY.State.DESTROYED, ENEMY.State.EGRESS]:
			continue
		alive[jet.id] = true
		var source := _source(jet.id, false)
		source.position = jet.position
		source.velocity = jet.velocity
		source.nose = jet.velocity.normalized() if jet.velocity.length() > 1 else jet.nose()
		var offset: Vector3 = _player.position - jet.position
		source.visible = jet.state != ENEMY.State.EVADE and offset.length() > 900.0 and offset.length() < defence.heat_range() and source.nose.angle_to(offset) < deg_to_rad(35.0) and _line_clear(jet.position, _player.position)
	for site in sites:
		alive[site.id] = true
		var source := _source(site.id, true)
		source.position = site.position + Vector3.UP * 8.0
		var distance: float = source.position.distance_to(_player.position)
		source.visible = sam_altitude_allows_lock(_agl) and distance > 700.0 and distance < defence.radar_range() and defence.radar_trackable(source.position) and _line_clear(source.position, _player.position)
	for id in _sources.keys():
		if not alive.has(id):
			_sources.erase(id)

func _source(id: int, sam: bool) -> Dictionary:
	if not _sources.has(id):
		_sources[id] = {"id": id, "sam": sam, "position": Vector3.ZERO, "velocity": Vector3.ZERO, "nose": Vector3.UP, "visible": false, "lock_time": 0.0, "cooldown": 0.0}
	return _sources[id]

func _line_clear(from: Vector3, to: Vector3) -> bool:
	if world_query == null:
		return true
	var obstruction = world_query.query_segment(from, to)
	if obstruction != null and obstruction.hit:
		return false
	# Sample ridges separately, without repeating the building query per sample.
	var count := maxi(1, ceili(from.distance_to(to) / 200.0))
	for i in range(count):
		var point := from.lerp(to, float(i) / count)
		if point.y <= world_query.ground_height(point.x, point.z):
			return false
	return true

func _launch(source: Dictionary) -> void:
	var flight := FLIGHT.new()
	flight.defence = defence
	flight.decoy_provider = Callable(countermeasures, "contacts") if countermeasures != null else Callable()
	flight.target_handle = PLAYER_ID
	flight.target_provider = func(_id: int) -> Dictionary: return _player
	flight.seeker = FLIGHT.Seeker.RADAR if source.sam else FLIGHT.Seeker.HEAT
	var source_id: int = source.id
	flight.radar_lock_provider = func() -> int:
		var live: Dictionary = _sources.get(source_id, {})
		return PLAYER_ID if not live.is_empty() and live.visible and sam_altitude_allows_lock(_agl) else -1
	var direction: Vector3 = (_player.position - source.position).normalized() if source.sam else source.nose
	var origin: Vector3 = source.position + direction * 16.0
	var round_data: RefCounted = projectiles.acquire_round()
	_sequence += 1
	round_data.initialise(_sequence, origin, direction, direction * 180.0 if source.sam else flight.launch_velocity(direction, source.velocity), false, null, "missile")
	round_data.flight = flight
	projectiles.spawn(round_data)
	if trails != null:
		trails.begin_trail(round_data.sequence)
	source.cooldown = 18.0 if source.sam else 15.0
	source.lock_time = 0.0
	_launch_gap = 2.2

func warning_state() -> Dictionary:
	var nearest := INF
	var point := Vector3.ZERO
	var incoming := 0
	if not _player.is_empty():
		for round_data in projectiles.active_rounds:
			var offset: Vector3 = _player.position - round_data.position
			# A missile that has passed and is receding no longer drives the alarm.
			if (round_data.velocity - _player.velocity).dot(offset) <= 0.0:
				continue
			incoming += 1
			if offset.length() < nearest:
				nearest = offset.length()
				point = round_data.position
	return {"locks": _locks, "incoming": incoming, "distance": nearest, "position": point, "grace": grace_remaining, "breather": breather_remaining}

func _expired(round_data: RefCounted) -> void:
	breather_remaining = BREATHER_SECONDS
	if trails != null:
		trails.end_trail(round_data.sequence)

func _impact(hit: RefCounted, round_data: RefCounted) -> void:
	_expired(round_data)
	if impact_fx != null:
		impact_fx.spawn_explosion(hit.position)
	if strike_fire != null and hit.object_type in [HIT.ObjectKind.TERRAIN, HIT.ObjectKind.BUILDING]:
		strike_fire.ignite(hit.position, hit.object_type == HIT.ObjectKind.BUILDING)
	if hit.object_type == HIT.ObjectKind.ENTITY and hit.object_id == PLAYER_ID:
		player_hit.emit(hit.position)
