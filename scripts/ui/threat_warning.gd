extends Control

## Always visible in aircraft and weapon views; visual and audio share a clock.
var state := {}
var _phase := 0.0
var _pulse := 0.0
var _hit_time := 0.0
var _camera: Camera3D
var _audio: AudioStreamPlayer
var hull := 100
var watching_sequence := -1
var _hit_flash := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_audio = AudioStreamPlayer.new()
	_audio.stream = _warning_tone()
	_audio.volume_db = -7.0
	add_child(_audio)

static func pulse_period(distance: float, incoming: bool) -> float:
	return lerpf(0.16, 0.95, clampf(distance / 6000.0, 0.0, 1.0)) if incoming else 1.35

func update_warning(delta: float, next_state: Dictionary, camera: Camera3D, health: int) -> void:
	var was_active := int(state.get("locks", 0)) > 0 or int(state.get("incoming", 0)) > 0
	state = next_state
	_camera = camera
	hull = health
	_hit_flash = maxf(0, _hit_flash - delta * 2.5)
	_hit_time = maxf(0.0, _hit_time - delta)
	var incoming := int(state.get("incoming", 0)) > 0
	var active := incoming or int(state.get("locks", 0)) > 0
	if active:
		_phase += delta / pulse_period(float(state.get("distance", INF)), incoming)
		if not was_active or _phase >= 1.0:
			_phase = fmod(_phase, 1.0) if was_active else 0.0
			_audio.pitch_scale = 1.2 if incoming else 0.8
			_audio.play()
		_pulse = pow(1.0 - _phase, 2.0)
	else:
		_phase = 0.0
		_pulse = 0.0
		_audio.stop()
	queue_redraw()

func show_hit() -> void:
	_hit_time = 2.0
	_hit_flash = 1.0

func warning_rect() -> Rect2:
	var width := minf(520, size.x - 40)
	return Rect2(Vector2((size.x - width) * 0.5, size.y - 86), Vector2(width, 48))

func missile_marker(point: Vector3) -> Dictionary:
	if not is_instance_valid(_camera): return {}
	var local := _camera.global_transform.affine_inverse() * point
	var behind := local.z >= -0.01
	var screen := _camera.unproject_position(point) if not behind else size * 0.5
	var bounds := Rect2(30, 200, maxf(size.x - 60, 1), maxf(size.y - 310, 1))
	if not behind and bounds.has_point(screen):
		return {"point": screen, "edge": false, "behind": false, "distance": local.length()}
	var direction := Vector2(local.x, -local.y) if behind else screen - size * 0.5
	if direction.length_squared() < 0.001: direction = Vector2.DOWN
	direction = direction.normalized()
	var centre := bounds.get_center()
	var half := bounds.size * 0.5
	var reach := minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
	return {"point": centre + direction * reach, "direction": direction, "edge": true, "behind": behind, "distance": local.length()}

func _draw() -> void:
	var incoming := int(state.get("incoming", 0)) > 0
	var active := incoming or int(state.get("locks", 0)) > 0
	var red := Color(1.0, 0.08, 0.05, 0.4 + _pulse * 0.6)
	if active or _hit_time > 0.0:
		draw_rect(Rect2(Vector2(7, 7), size - Vector2(14, 14)), Color(red, 0.15 + _pulse * 0.35), false, 2.0 + _pulse * 3.0)
		var text := "MISSILE INBOUND" if incoming else "ENEMY LOCK"
		if _hit_time > 0.0:
			text = "MISSILE HIT  •  HULL %d%%" % hull if hull > 0 else "AIRCRAFT LOST"
		elif incoming:
			text += "  •  %d M" % roundi(float(state.distance))
		var panel := warning_rect()
		draw_rect(panel, Color(0.12, 0.01, 0.01, 0.84))
		draw_circle(panel.position + Vector2(19, 22), 5 + _pulse * 4, red)
		draw_string(ThemeDB.fallback_font, panel.position + Vector2(40, 29), text, HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 45, 20, red)
	if _hit_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.3, 0.04, _hit_flash * 0.42))
	if incoming and is_instance_valid(_camera):
		var marker := missile_marker(state.position)
		var point: Vector2 = marker.point
		var range_text := "%d M" % roundi(float(state.get("distance", marker.distance)))
		if marker.edge:
			var direction: Vector2 = marker.direction
			var side := Vector2(-direction.y, direction.x)
			# Shaded arrow faces give depth, while the true camera projection
			# keeps the direction attached to the missile as the aircraft rolls.
			var tip := point + direction * 10
			var back := point - direction * 16
			draw_colored_polygon(PackedVector2Array([tip, back + side * 13, point - direction * 6]), red)
			draw_colored_polygon(PackedVector2Array([tip, point - direction * 6, back - side * 13]), red.darkened(0.4))
			var label := ("BEHIND • " if marker.behind else "MISSILE • ") + range_text
			var label_point := Vector2(clampf(point.x - 65, 12, size.x - 170), clampf(point.y + 28, 112, size.y - 100))
			draw_string(ThemeDB.fallback_font, label_point, label, HORIZONTAL_ALIGNMENT_LEFT, 170, 15, red)
		else:
			var radius := lerpf(24, 10, clampf(float(marker.distance) / 4000, 0, 1))
			for sign in [-1, 1]:
				var x: float = point.x + sign * radius
				draw_line(Vector2(x, point.y - radius), Vector2(x, point.y + radius), red, 2)
				draw_line(Vector2(x, point.y - radius), Vector2(x - sign * 7, point.y - radius), red, 2)
				draw_line(Vector2(x, point.y + radius), Vector2(x - sign * 7, point.y + radius), red, 2)
			draw_string(ThemeDB.fallback_font, point + Vector2(radius + 7, 5), range_text, HORIZONTAL_ALIGNMENT_LEFT, 120, 16, red)
	if watching_sequence >= 0:
		draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.5 - 130, size.y - 105), "INCOMING VIEW • R3 NEXT / RETURN", HORIZONTAL_ALIGNMENT_CENTER, 260, 15, Color(1, 0.7, 0.4))

static func _warning_tone() -> AudioStreamWAV:
	# Original synthesized alternating tone, short attack/release avoids clicks.
	var rate := 22050
	var samples := int(rate * 0.12)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / rate
		var envelope := minf(t / 0.006, 1.0) * minf((0.12 - t) / 0.018, 1.0)
		var value := (sin(TAU * 880.0 * t) * 0.65 + sin(TAU * 1320.0 * t) * 0.25) * envelope
		data.encode_s16(i * 2, int(value * 24000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream

func _exit_tree() -> void:
	if is_instance_valid(_audio):
		_audio.stop()
