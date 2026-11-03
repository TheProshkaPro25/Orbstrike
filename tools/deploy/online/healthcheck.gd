extends SceneTree
## End-to-end protocol health probe, not an HTTP 200 check.
const Protocol = preload("res://network/online_protocol.gd")
var socket := WebSocketPeer.new()
var address := "ws://127.0.0.1:8910"
var started := 0
var greeted := false

func _initialize() -> void:
	Engine.max_fps = 60
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--url="): address = arg.substr(6)
		else:
			printerr("Usage: --url=ws://127.0.0.1:8910 or --url=wss://your-domain")
			quit(2)
			return
	started = Time.get_ticks_msec()
	if socket.connect_to_url(address) != OK:
		printerr("HEALTH FAILED: cannot connect")
		quit(1)
		return
	process_frame.connect(_tick)

func _tick() -> void:
	socket.poll()
	if Time.get_ticks_msec() - started > 10000 or socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		printerr("HEALTH FAILED: handshake timeout or closed socket")
		quit(1)
		return
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return
	if not greeted:
		greeted = true
		socket.send_text(JSON.stringify({"t": "hello", "version": Protocol.VERSION, "content": Protocol.content_tag()}))
	while socket.get_available_packet_count() > 0:
		var message: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if message is Dictionary and Protocol.validate_server(message) and message.t == "hello" and int(message.version) == Protocol.VERSION and message.content == Protocol.content_tag():
			print("HEALTH OK: WebSocket and matching game protocol")
			socket.close(-1)
			quit(0)
			return
		printerr("HEALTH FAILED: incompatible or invalid reply")
		quit(1)
		return
