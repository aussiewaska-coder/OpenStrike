extends Node

const RAIN := preload("res://assets/audio/rain_loop.ogg")
const THUNDER := preload("res://assets/audio/thunder.ogg")
const CONFIG_PATH := "user://audio.cfg"
const VOLUME_STEPS := [0.0, 0.4, 0.7, 1.0]

var level := 0.7
var rain_player: AudioStreamPlayer
var thunder_player: AudioStreamPlayer
var _rain_gain := 0.0
var _suspended := false


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		level = clampf(float(config.get_value("audio", "weather_volume", 0.7)), 0.0, 1.0)
	rain_player = AudioStreamPlayer.new()
	rain_player.name = "RainLoop"
	rain_player.stream = RAIN.duplicate()
	rain_player.stream.loop = true
	rain_player.volume_db = -80.0
	add_child(rain_player)
	thunder_player = AudioStreamPlayer.new()
	thunder_player.name = "Thunder"
	thunder_player.stream = THUNDER
	thunder_player.max_polyphony = 3
	add_child(thunder_player)


func update_rain(delta: float, intensity: float) -> void:
	var wanted := clampf(intensity, 0.0, 1.0) * level * 0.22
	_rain_gain = lerpf(_rain_gain, wanted, 1.0 - exp(-5.0 * maxf(delta, 0.0)))
	rain_player.volume_db = linear_to_db(maxf(_rain_gain, 0.0001))
	if wanted > 0.0002 and not rain_player.playing:
		rain_player.play()
	elif wanted <= 0.0002 and _rain_gain < 0.0002:
		rain_player.stop()
	if _suspended:
		rain_player.stream_paused = true


func play_thunder(distance_m: float, pitch: float) -> void:
	if level <= 0.0 or _suspended:
		return
	thunder_player.volume_db = linear_to_db(level) + lerpf(-5.0, -17.0, clampf(distance_m / 4000.0, 0.0, 1.0))
	thunder_player.pitch_scale = pitch
	thunder_player.play()


func set_volume(value: float, persist := true) -> void:
	level = clampf(value, 0.0, 1.0)
	if level == 0.0:
		_rain_gain = 0.0
		rain_player.stop()
		thunder_player.stop()
	if persist:
		var config := ConfigFile.new()
		config.load(CONFIG_PATH)
		config.set_value("audio", "weather_volume", level)
		config.save(CONFIG_PATH)


func cycle_volume() -> void:
	for value in VOLUME_STEPS:
		if value > level + 0.001:
			set_volume(value)
			return
	set_volume(0.0)


func volume_text() -> String:
	return "WEATHER SOUND: OFF" if level == 0.0 else "WEATHER SOUND: %d%%" % roundi(level * 100.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_RESUMED:
		_suspended = what == NOTIFICATION_APPLICATION_PAUSED
		for player in [rain_player, thunder_player]:
			if is_instance_valid(player):
				player.stream_paused = _suspended or (is_inside_tree() and get_tree().paused)
