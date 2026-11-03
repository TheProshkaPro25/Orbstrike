class_name OnlineServer
extends Node
## Dedicated authoritative WebSocket service. A socket owns its seat; clients never own state.
const Protocol = preload("res://network/online_protocol.gd")
const Codec = preload("res://network/state_codec.gd")
const Physics = preload("res://network/online_physics.gd")
const MAX_PEERS := 64
const MAX_ROOMS := 32
const BURST := 24.0
const RATE := 12.0
const IDLE_MS := 600000
const HELLO_MS := 10000
const OUTBOUND_LIMIT := 524288
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
var _listener := TCPServer.new()
var _peers: Dictionary = {}
var _rooms: Dictionary = {}
var _next_peer := 1
var _crypto := Crypto.new()
var bound_port := 0

func listen(port: int = 8910, address: String = "127.0.0.1") -> Error:
	if port < 1 or port > 65535: return ERR_INVALID_PARAMETER
	var err := _listener.listen(port, address)
	if err == OK: bound_port = port
	return err

func stop() -> void:
	_listener.stop()
	for id in _peers.keys(): _drop(id, "server_stopped")

func _exit_tree() -> void:
	stop()

func _process(_delta: float) -> void:
	Engine.max_fps = 60
	var now := Time.get_ticks_msec()
	# Bound acceptance and packet work per frame as well as total live peers.
	for _i in range(8):
		if not _listener.is_connection_available(): break
		var tcp := _listener.take_connection()
		if _peers.size() >= MAX_PEERS:
			tcp.disconnect_from_host()
			continue
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = Protocol.MAX_PACKET * 2
		ws.outbound_buffer_size = OUTBOUND_LIMIT
		ws.max_queued_packets = 64
		ws.heartbeat_interval = 15.0
		if ws.accept_stream(tcp) != OK: continue
		_peers[_next_peer] = {"ws": ws, "hello": false, "room": "", "player": -1,
			"created": now, "last": now, "bucket": BURST, "bucket_at": now}
		_next_peer += 1
	for id in _peers.keys():
		if not _peers.has(id): continue
		var peer: Dictionary = _peers[id]
		var ws: WebSocketPeer = peer.ws
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_drop(id, "disconnected")
			continue
		if (not peer.hello and now - int(peer.created) > HELLO_MS) or now - int(peer.last) > IDLE_MS:
			_drop(id, "timeout")
			continue
		if ws.get_ready_state() != WebSocketPeer.STATE_OPEN: continue
		for _packet_index in range(8):
			if not _peers.has(id) or ws.get_available_packet_count() == 0: break
			var bytes := ws.get_packet()
			if not ws.was_string_packet() or bytes.size() > Protocol.MAX_PACKET:
				_drop(id, "invalid_packet")
				break
			peer.bucket = minf(BURST, float(peer.bucket) + (now - int(peer.bucket_at)) * RATE / 1000.0)
			peer.bucket_at = now
			if float(peer.bucket) < 1.0:
				_drop(id, "rate_limit")
				break
			peer.bucket -= 1.0
			var parser := JSON.new()
			if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
				_error(id, "invalid_json", "Ожидалось JSON-сообщение")
				continue
			var message: Dictionary = parser.data
			var validation := Protocol.validate(message)
			if not validation.is_empty():
				_error(id, "invalid_message", validation)
				continue
			peer.last = now
			_handle(id, message)

func _send(id: int, message: Dictionary) -> void:
	if not _peers.has(id): return
	var ws: WebSocketPeer = _peers[id].ws
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN: return
	var body := JSON.stringify(message)
	if body.to_utf8_buffer().size() + ws.get_current_outbound_buffered_amount() > OUTBOUND_LIMIT:
		_drop(id, "slow_client")
		return
	ws.send_text(body)

func _error(id: int, code: String, text: String) -> void:
	_send(id, {"t": "error", "code": code, "message": text})

func _handle(id: int, message: Dictionary) -> void:
	if not _peers.has(id): return
	var peer: Dictionary = _peers[id]
	if message.t == "hello":
		if peer.hello or int(message.version) != Protocol.VERSION or message.content != Protocol.content_tag():
			_error(id, "incompatible", "Версии игры или правил различаются")
			# A rejected peer stays unauthenticated and cannot join or act.
			return
		peer.hello = true
		_send(id, {"t": "hello", "version": Protocol.VERSION, "content": Protocol.content_tag()})
		return
	if not peer.hello:
		_error(id, "hello_required", "Сначала подтвердите версию игры")
		return
	if message.t == "ping":
		_send(id, {"t": "pong"})
		return
	if message.t == "leave":
		_leave(id, "left")
		_send(id, {"t": "ended", "reason": "left"})
		return
	if message.t == "create" or message.t == "join":
		if not String(peer.room).is_empty():
			_error(id, "already_in_room", "Вы уже в комнате")
			return
		if message.t == "create": _create(id, String(message.name).strip_edges())
		else: _join(id, String(message.code).to_upper(), String(message.name).strip_edges())
		return
	var code: String = peer.room
	if not _rooms.has(code):
		_error(id, "no_room", "Сначала войдите в комнату")
		return
	var room: Dictionary = _rooms[code]
	var player: int = peer.player
	if message.t == "rematch":
		if room.ctrl == null or room.ctrl.get_phase() != MatchController.Phase.GAME_OVER or room.busy:
			_error(id, "not_finished", "Реванш доступен после матча")
			return
		room.rematch[player] = true
		if room.rematch[0] and room.rematch[1]:
			_free_physics(room)
			room.ctrl = null
			room.ready = [false, false]
			room.rematch = [false, false]
			room.last_battle = {}
			room.battle_serial = 0
		_lobby(room)
		return
	if message.t == "deck":
		if room.ctrl != null:
			_error(id, "match_started", "Колоду можно менять до матча")
			return
		var reason := Protocol.deck_error(message)
		if not reason.is_empty():
			_error(id, "invalid_deck", reason)
			return
		room.decks[player] = {"creatures": message.creatures.duplicate(), "gates": message.gates.duplicate(), "abilities": message.abilities.duplicate()}
		room.ready[player] = false
		_lobby(room)
		return
	if message.t == "ready":
		if room.ctrl != null or room.decks[player].is_empty():
			_error(id, "not_ready", "Сначала выберите допустимую колоду")
			return
		room.ready[player] = message.ready
		_lobby(room)
		if room.ready[0] and room.ready[1] and int(room.peers[0]) >= 0 and int(room.peers[1]) >= 0: _start(room)
		return
	if message.t == "action":
		_action(id, room, player, message.command, message.args)

func _create(id: int, player_name: String) -> void:
	if _rooms.size() >= MAX_ROOMS:
		_error(id, "server_full", "Все комнаты заняты")
		return
	var code := ""
	while code.is_empty() or _rooms.has(code):
		code = ""
		for byte in _crypto.generate_random_bytes(8): code += CODE_ALPHABET[int(byte) % CODE_ALPHABET.length()]
	var room := {"code": code, "peers": [id, -1], "names": [player_name, ""], "decks": [{}, {}],
		"ready": [false, false], "rematch": [false, false], "ctrl": null, "physics": null,
		"busy": false, "closed": false, "last_battle": {}, "battle_serial": 0}
	_rooms[code] = room
	_peers[id].room = code
	_peers[id].player = 0
	_lobby(room)

func _join(id: int, code: String, player_name: String) -> void:
	if not _rooms.has(code) or _rooms[code].peers[1] != -1 or _rooms[code].ctrl != null:
		_error(id, "room_unavailable", "Комната не найдена или уже занята")
		return
	var room: Dictionary = _rooms[code]
	room.peers[1] = id
	room.names[1] = player_name
	_peers[id].room = code
	_peers[id].player = 1
	_lobby(room)

func _lobby(room: Dictionary) -> void:
	var players: Array = []
	for p in range(2):
		players.append({"name": room.names[p], "connected": int(room.peers[p]) >= 0, "ready": room.ready[p],
			"has_deck": not room.decks[p].is_empty(), "creatures": room.decks[p].get("creatures", []).duplicate()})
	for p in range(2):
		if room.closed: break
		_send(int(room.peers[p]), {"t": "lobby", "code": room.code, "player": p, "players": players,
			"rematch": room.rematch.duplicate(), "in_match": room.ctrl != null})

func _start(room: Dictionary) -> void:
	if room.closed: return
	var decks: Array[DeckDef] = []
	for deck in room.decks: decks.append(CardDB.build_deck(deck.creatures, deck.gates, deck.abilities))
	var seed_bytes := _crypto.generate_random_bytes(4)
	var secret_seed := int(seed_bytes.decode_u32(0))
	var ctrl := MatchController.new(decks[0], decks[1], secret_seed)
	ctrl.landing_window = true
	room.ctrl = ctrl
	room.physics = Physics.new()
	add_child(room.physics)
	ctrl.battle_resolved.connect(_capture_battle.bind(String(room.code)))
	ctrl.start(0)
	_states(room)

func _capture_battle(result: BattleResult, code: String) -> void:
	if not _rooms.has(code): return
	var room: Dictionary = _rooms[code]
	room.last_battle = Codec.preview(result)
	room.battle_serial = int(room.battle_serial) + 1

func _action(id: int, room: Dictionary, player: int, command: String, args: Dictionary) -> void:
	var ctrl: MatchController = room.ctrl
	if ctrl == null:
		_error(id, "not_started", "Матч ещё не начался")
		return
	if room.busy:
		_error(id, "flight_busy", "Дождитесь приземления сферы")
		return
	var err: Error = ERR_UNAUTHORIZED
	match command:
		"place_gate": err = ctrl.place_arena_card(player, StringName(args.card), int(args.slot))
		"throw_with_gate": err = ctrl.throw_with_gate(player, StringName(args.card), int(args.slot), int(args.uid))
		"skip_gate": err = ctrl.skip_gate(player)
		"select": err = ctrl.select_creature(player, int(args.uid))
		"ability": err = ctrl.play_ability(player, StringName(args.card))
		"pass": err = ctrl.pass_ability(player)
		"reveal_gate": err = ctrl.reveal_gate(player)
		"launch":
			var uid := ctrl.get_selected_uid()
			var view := ctrl.get_view(player)
			var target: int = args.slot
			if ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING and ctrl.get_active_player() == player and uid >= 0 and view.slots[target].has_card and (ctrl.get_throw_gate_slot() < 0 or ctrl.get_throw_gate_slot() == target):
				room.busy = true
				_states(room)
				_run_flight(room, player, uid, target)
				return
	# MatchController keeps replay diagnostics; online invalid requests must not grow them forever.
	if ctrl.action_trace.size() > 256: ctrl.action_trace = ctrl.action_trace.slice(-256)
	if ctrl.event_log.size() > 512: ctrl.event_log = ctrl.event_log.slice(-512)
	if err != OK:
		_error(id, "illegal_action", "Действие недоступно в текущем состоянии (%d)" % err)
		return
	_states(room)

func _run_flight(room: Dictionary, player: int, uid: int, target: int) -> void:
	if room.closed:
		_free_physics(room)
		return
	var gates: Array[int] = []
	var ctrl: MatchController = room.ctrl
	var view := ctrl.get_view(player)
	for i in range(6):
		if view.slots[i].has_card: gates.append(i)
	var result: Dictionary = await room.physics.throw_ball(player, uid, target, gates, int(_crypto.generate_random_bytes(4).decode_u32(0)))
	if room.closed:
		_free_physics(room)
		return
	if result.is_empty() or not result.has("slot") or not result.has("duration"):
		# Failure ends the room; never invent a landing or hand authority to a client.
		_leave(int(room.peers[player]), "physics_failed")
		_free_physics(room)
		return
	var flight := result.duplicate(true)
	flight.erase("seed")
	flight.t = "flight"
	flight.owner = player
	flight.target_slot = target
	for id in room.peers:
		if room.closed: break
		_send(int(id), flight)
	if room.closed:
		_free_physics(room)
		return
	# Captured physical motion is replayed by both clients before changing the rules state.
	await get_tree().create_timer(clampf(float(result.duration), 0.01, 12.0)).timeout
	if room.closed:
		_free_physics(room)
		return
	ctrl.report_landing(uid, int(result.slot))
	room.busy = false
	_states(room)

func _states(room: Dictionary) -> void:
	if room.closed: return
	var ctrl: MatchController = room.ctrl
	for player in range(2):
		if room.closed: break
		var view := ctrl.get_view(player)
		var reasons: Dictionary = {}
		for id in view.players[player].ability_hand: reasons[String(id)] = ctrl.ability_unavailable_reason(player, id)
		# Battle plays are public. Recompute separately using each recipient's masked state.
		var preview: BattleResult = ctrl.get_battle_preview()
		if preview != null:
			var passed := preview.passed.duplicate()
			preview = PowerCalc.compute_seq(view, preview.attacker_uid, preview.defender_uid, preview.slot, preview.battle_plays)
			preview.passed.assign(passed)
		_send(int(room.peers[player]), {"t": "state", "player": player, "view": Codec.encode_view(view),
			"legal": {"setup_slots": ctrl.legal_setup_slots() if ctrl.get_phase() == MatchController.Phase.SETUP and ctrl.get_active_player() == player else [],
				"creatures": ctrl.legal_creatures(player), "abilities": ctrl.legal_abilities(player),
				"can_skip_gate": ctrl.get_active_player() == player and ctrl.can_skip_gate(), "can_reveal_gate": ctrl.can_reveal_gate(player),
				"abilities_left": ctrl.abilities_left(player), "ability_reasons": reasons},
			"selected_uid": ctrl.get_selected_uid(), "landed_uid": ctrl.get_landed_uid(),
			"throw_gate_slot": ctrl.get_throw_gate_slot(), "ability_moment": String(ctrl.get_ability_moment()),
			"preview": Codec.preview(preview), "busy": room.busy, "winner": ctrl.winner, "reason": String(ctrl.game_over_reason),
			"last_battle": room.last_battle, "battle_serial": room.battle_serial})

func _free_physics(room: Dictionary) -> void:
	if is_instance_valid(room.physics): room.physics.queue_free()
	room.physics = null

func _leave(id: int, reason: String) -> void:
	if not _peers.has(id): return
	var code: String = _peers[id].room
	if code.is_empty() or not _rooms.has(code): return
	var room: Dictionary = _rooms[code]
	room.closed = true
	_rooms.erase(code)
	for member in room.peers:
		if not _peers.has(member): continue
		_peers[member].room = ""
		_peers[member].player = -1
		if int(member) != id: _send(int(member), {"t": "ended", "reason": reason})
	if not room.busy: _free_physics(room)

func _drop(id: int, reason: String) -> void:
	if not _peers.has(id): return
	_leave(id, reason)
	var ws: WebSocketPeer = _peers[id].ws
	ws.close(-1)
	_peers.erase(id)
