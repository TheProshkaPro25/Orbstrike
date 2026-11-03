extends Node
## Только транспорт. Правила и секреты соперника находятся на выделенном сервере.
const Protocol = preload("res://network/online_protocol.gd")
const SETTINGS := "user://online.cfg"
signal message(data: Dictionary)
signal status(text: String)
signal disconnected(reason: String)
var socket: WebSocketPeer
var connected := false
var verified := false
var _started := 0
var _last_ping := 0

static func saved_address() -> String:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	return str(cfg.get_value("online", "server", ""))

func connect_server(address: String) -> Error:
	close()
	address = address.strip_edges()
	# Plaintext is deliberately limited to local development. Public play uses TLS.
	if not address.begins_with("wss://") and not address.begins_with("ws://127.0.0.1:") and not address.begins_with("ws://localhost:"):
		status.emit("Укажите wss://адрес сервера. Для локальной проверки: ws://127.0.0.1:8910")
		return ERR_INVALID_PARAMETER
	if address.length() > 256 or "@" in address or "?" in address or "#" in address:
		status.emit("Некорректный адрес сервера")
		return ERR_INVALID_PARAMETER
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 524288
	socket.outbound_buffer_size = 32768
	socket.max_queued_packets = 32
	socket.heartbeat_interval = 15.0
	var err := socket.connect_to_url(address)
	if err != OK:
		socket = null
		status.emit("Не удалось начать подключение")
		return err
	var cfg := ConfigFile.new()
	cfg.set_value("online", "server", address)
	cfg.save(SETTINGS)
	_started = Time.get_ticks_msec()
	status.emit("Подключение…")
	return OK

func send(data: Dictionary) -> void:
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(data))

func action(command: String, args: Dictionary = {}) -> void:
	send({"t": "action", "command": command, "args": args})

func close() -> void:
	if socket != null:
		socket.close(1000, "leave")
	socket = null
	connected = false
	verified = false

func _process(_delta: float) -> void:
	if socket == null: return
	socket.poll()
	var state := socket.get_ready_state()
	if not verified and Time.get_ticks_msec() - _started > 15000:
		_fail("Сервер не ответил. Проверьте адрес и подключение.")
		return
	if state == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			send({"t": "hello", "version": Protocol.VERSION, "content": Protocol.content_tag()})
			_last_ping = Time.get_ticks_msec()
		if Time.get_ticks_msec() - _last_ping > 20000:
			send({"t": "ping"})
			_last_ping = Time.get_ticks_msec()
		var count := 0
		while socket != null and socket.get_available_packet_count() > 0 and count < 16:
			count += 1
			var packet := socket.get_packet()
			if not socket.was_string_packet() or packet.size() > Protocol.MAX_SERVER_PACKET:
				_fail("Ответ сервера слишком велик")
				return
			var data: Variant = JSON.parse_string(packet.get_string_from_utf8())
			if not data is Dictionary or not Protocol.validate_server(data):
				_fail("Некорректный ответ сервера")
				return
			if data.t == "hello":
				if int(data.get("version", -1)) != Protocol.VERSION or str(data.get("content", "")) != Protocol.content_tag():
					_fail("Версия игры не совпадает с сервером")
					return
				verified = true
				status.emit("Подключено. Создайте комнату или введите код.")
			if verified or data.t == "error": message.emit(data)
	elif state == WebSocketPeer.STATE_CLOSED:
		_fail("Соединение с сервером прервано. Матч завершён.")

func _fail(reason: String) -> void:
	close()
	status.emit(reason)
	disconnected.emit(reason)

func _exit_tree() -> void:
	close()
