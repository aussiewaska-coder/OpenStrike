extends Node

const ENGINE := preload("res://assets/audio/jet_engine_loop.ogg")
const CONFIG_PATH := "user://audio.cfg"
const VOLUME_STEPS := [0.0, 0.4, 0.7, 1.0]
var level := 0.7
var player: AudioStreamPlayer
var _filter: AudioEffectLowPassFilter
var _bus_name: StringName
var _gain := 0.0
var _suspended := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		level = clampf(float(config.get_value("audio", "engine_volume", 0.7)), 0.0, 1.0)
	_bus_name = StringName("JetEngine_%d" % get_instance_id())
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, _bus_name)
	AudioServer.set_bus_send(index, &"Master")
	_filter = AudioEffectLowPassFilter.new()
	_filter.cutoff_hz = 16000.0
	AudioServer.add_bus_effect(index, _filter)
	player = AudioStreamPlayer.new()
	player.name = "EngineLoop"
	player.stream = ENGINE.duplicate()
	player.stream.loop = true
	player.bus = _bus_name
	player.volume_db = -80.0
	player.pitch_scale = 0.78
	add_child(player)

func update_state(delta: float, active: bool, core: float, burner: float, cockpit: bool, remote_view: bool) -> void:
	core = clampf(core, 0.0, 1.0)
	burner = clampf(burner, 0.0, 1.0)
	var audible := active and not remote_view and level > 0.0
	var wanted := db_to_linear(lerpf(-13.0, -1.0, core) + burner * 3.0 - (4.0 if cockpit else 0.0)) * level if audible else 0.0
	_gain = lerpf(_gain, wanted, 1.0 - exp(-6.0 * delta))
	player.volume_db = linear_to_db(maxf(_gain, 0.0001))
	player.pitch_scale = lerpf(player.pitch_scale, 0.78 + core * 0.34 + burner * 0.08, 1.0 - exp(-2.5 * delta))
	_filter.cutoff_hz = lerpf(_filter.cutoff_hz, 3800.0 if cockpit else 16000.0, 1.0 - exp(-5.0 * delta))
	if audible and not player.playing:
		player.play()
	elif not audible and _gain < 0.0002:
		player.stop()
	if _suspended:
		player.stream_paused = true

func cycle_volume() -> void:
	var next := 0.0
	for value in VOLUME_STEPS:
		if value > level + 0.001:
			next = value
			break
	set_volume(next)

func set_volume(value: float, persist := true) -> void:
	level = clampf(value, 0.0, 1.0)
	if level == 0.0:
		_gain = 0.0
		player.stop()
	if persist:
		var config := ConfigFile.new()
		config.load(CONFIG_PATH)
		config.set_value("audio", "engine_volume", level)
		config.save(CONFIG_PATH)

func volume_text() -> String:
	return "ENGINE SOUND: OFF" if level == 0.0 else "ENGINE SOUND: %d%%" % roundi(level * 100.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_suspended = true
		if is_instance_valid(player):
			player.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_suspended = false
		if is_instance_valid(player) and is_inside_tree():
			player.stream_paused = get_tree().paused

func _exit_tree() -> void:
	if is_instance_valid(player):
		# Move playback off the private bus before deleting it, so the mixer
		# can release its pending fade even when the aircraft was paused.
		player.bus = &"Master"
		player.stop()
		player.stream = null
	var index := AudioServer.get_bus_index(_bus_name)
	if index > 0:
		AudioServer.remove_bus(index)
