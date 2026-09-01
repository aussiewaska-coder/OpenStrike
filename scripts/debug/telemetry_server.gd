extends Node

## A loopback telemetry socket, so the game can be profiled from a shell on the
## same device.
##
## logcat is not reachable from inside the proot userland this project is built
## in, and adb needs a network the phone does not always have. A TCP listener on
## 127.0.0.1 needs neither: the app already holds the INTERNET permission for map
## tiles, loopback needs no other permission, and anything on the device can
## connect and read.
##
## Line-delimited JSON, one sample per interval, to every connected client.

const PORT := 8787
const SAMPLE_INTERVAL_S := 0.5

var _server := TCPServer.new()
var _peers: Array[StreamPeerTCP] = []
var _accumulator := 0.0
var _sources: Array[Callable] = []


func _ready() -> void:
	var error := _server.listen(PORT, "127.0.0.1")
	if error != OK:
		push_warning("Telemetry socket could not listen on %d: %d" % [PORT, error])
		set_process(false)
		return
	print("Telemetry listening on 127.0.0.1:%d" % PORT)


## Anything that wants to report registers a Callable returning a Dictionary.
func add_source(source: Callable) -> void:
	_sources.append(source)


func _process(delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer != null:
			_peers.append(peer)
	_accumulator += delta
	if _accumulator < SAMPLE_INTERVAL_S:
		return
	_accumulator = 0.0
	if _peers.is_empty():
		return
	var line := JSON.stringify(_sample()) + "\n"
	var bytes := line.to_utf8_buffer()
	var live: Array[StreamPeerTCP] = []
	for peer in _peers:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		if peer.put_data(bytes) == OK:
			live.append(peer)
	_peers = live


func _sample() -> Dictionary:
	var sample := {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"texture_mem_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}
	for source in _sources:
		if source.is_valid():
			sample.merge(source.call(), true)
	return sample
