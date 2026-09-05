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
## Commands arrive as one JSON object per line from any peer; each handler
## gets the object and returns a reply dictionary, sent back on that peer.
var _command_handlers: Array[Callable] = []
var _inbound: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var error := _server.listen(PORT, "127.0.0.1")
	if error != OK:
		push_warning("Telemetry socket could not listen on %d: %d" % [PORT, error])
		set_process(false)
		return
	print("Telemetry listening on 127.0.0.1:%d" % PORT)


## Anything that wants to report registers a Callable returning a Dictionary.
func add_source(source: Callable) -> void:
	_sources.append(source)


func add_command_handler(handler: Callable) -> void:
	_command_handlers.append(handler)


func _process(delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer != null:
			_peers.append(peer)
	_read_commands()
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


func _read_commands() -> void:
	for peer in _peers:
		peer.poll()
		var available := peer.get_available_bytes()
		if available <= 0:
			continue
		var chunk: Array = peer.get_data(available)
		if chunk[0] != OK:
			continue
		var text: String = _inbound.get(peer, "") + (chunk[1] as PackedByteArray).get_string_from_utf8()
		while text.contains("\n"):
			var line := text.substr(0, text.find("\n")).strip_edges()
			text = text.substr(text.find("\n") + 1)
			if not line.is_empty():
				_dispatch(peer, line)
		_inbound[peer] = text


func _dispatch(peer: StreamPeerTCP, line: String) -> void:
	var command = JSON.parse_string(line)
	if not (command is Dictionary):
		peer.put_data((JSON.stringify({"reply": "error", "detail": "not a JSON object"}) + "\n").to_utf8_buffer())
		return
	var reply := {"reply": "ok"}
	for handler in _command_handlers:
		if handler.is_valid():
			var result = await handler.call(command)
			if result is Dictionary:
				reply.merge(result, true)
	peer.put_data((JSON.stringify(reply) + "\n").to_utf8_buffer())


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
