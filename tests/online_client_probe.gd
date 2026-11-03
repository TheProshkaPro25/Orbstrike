extends SceneTree
## Real TCP/WebSocket loopback probe. Includes two captured RigidBody3D throws; no visible window.
const Protocol = preload("res://network/online_protocol.gd")
const Codec = preload("res://network/state_codec.gd")
const Server = preload("res://network/online_server.gd")
var service: Node
var sockets: Array[WebSocketPeer] = []
var inbox: Array = [[], []]
var latest: Array = [{}, {}]
var checks := 0
var failures := 0
var throws := 0
var code := ""
var started_at := 0
var external_url := ""

func _initialize() -> void:
	Engine.max_fps = 60
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	preload("res://tools/test_window.gd").background(self)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--url="): external_url = arg.substr(6)
	_run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
	return value

func _run() -> void:
	started_at = Time.get_ticks_msec()
	var port := 21000 + OS.get_process_id() % 20000
	if external_url.is_empty():
		service = Server.new()
		root.add_child(service)
		if not check(service.listen(port, "127.0.0.1") == OK, "loopback listening"):
			_finish()
			return
	var address := external_url if not external_url.is_empty() else "ws://127.0.0.1:%d" % port
	for p in range(2):
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = Protocol.MAX_SERVER_PACKET
		ws.outbound_buffer_size = 32768
		sockets.append(ws)
		check(ws.connect_to_url(address) == OK, "websocket connect " + str(p))
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and (sockets[0].get_ready_state() != WebSocketPeer.STATE_OPEN or sockets[1].get_ready_state() != WebSocketPeer.STATE_OPEN):
		_poll()
		await process_frame
	if not check(sockets[0].get_ready_state() == WebSocketPeer.STATE_OPEN and sockets[1].get_ready_state() == WebSocketPeer.STATE_OPEN, "both real WebSockets open"):
		_finish()
		return
	for p in range(2):
		_send(p, {"t": "hello", "version": Protocol.VERSION, "content": Protocol.content_tag()})
		check(not (await _message(p, "hello")).is_empty(), "compatible handshake " + str(p))
	_send(0, {"t": "create", "name": "Loopback A"})
	var lobby := await _message(0, "lobby")
	if not check(not lobby.is_empty(), "create response"):
		_finish()
		return
	code = lobby.code
	_send(1, {"t": "join", "code": code, "name": "Loopback B"})
	lobby = await _message(1, "lobby")
	check(not lobby.is_empty() and lobby.player == 1 and lobby.players[0].connected, "join assigns second socket")
	_send(1, {"t": "action", "command": "report_landing", "args": {"uid": 0, "slot": 1}})
	check((await _message(1, "error")).get("code") == "invalid_message", "remote landing rejected by wire")
	_send(1, {"t": "action", "command": "select", "args": {"uid": 0, "player": 0}})
	check((await _message(1, "error")).get("code") == "invalid_message", "remote player spoof rejected by wire")
	for p in range(2):
		_send(p, _deck(CardDB.preset_deck(p)))
		# There may be an earlier join lobby; wait for this seat's confirmed deck.
		var until := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < until:
			lobby = await _message(p, "lobby")
			if not lobby.is_empty() and lobby.players[p].has_deck: break
		check(not lobby.is_empty() and lobby.players[p].has_deck, "deck acknowledged " + str(p))
	for p in range(2): _send(p, {"t": "ready", "ready": true})
	if not check(await _state(0, func(s: Dictionary) -> bool: return s.view.phase == MatchController.Phase.SETUP), "both ready starts state"):
		_finish()
		return
	check(await _state(1, func(s: Dictionary) -> bool: return s.view.phase == MatchController.Phase.SETUP), "second receives own view")
	check(latest[0].view.players[1].arena_hand == ["", "", ""], "own snapshot masks enemy hand")
	check(latest[1].legal.setup_slots.is_empty(), "other peer cannot setup")
	_send(1, {"t": "action", "command": "skip_gate", "args": {}})
	check((await _message(1, "error")).get("code") == "illegal_action", "wrong side action denied by controller")
	var slot := int(latest[0].legal.setup_slots[0])
	_send(0, {"t": "action", "command": "place_gate", "args": {"card": latest[0].view.players[0].arena_hand[0], "slot": slot}})
	check(await _state(0, func(s: Dictionary) -> bool: return s.view.phase == MatchController.Phase.AWAIT_THROW), "gate accepted")
	check(await _state(1, func(s: Dictionary) -> bool: return s.view.phase == MatchController.Phase.AWAIT_THROW), "other gate snapshot")
	check(latest[1].view.slots[slot].has_card and latest[1].view.slots[slot].card_id == "", "wire placed gate is masked")
	_send(0, {"t": "action", "command": "select", "args": {"uid": 0}})
	check(await _state(0, func(s: Dictionary) -> bool: return s.selected_uid == 0), "select enters prethrow")
	check(latest[0].ability_moment == "pre_throw", "prethrow moment sent")
	if not latest[0].legal.abilities.is_empty():
		var hand_size: int = latest[0].view.players[0].ability_hand.size()
		_send(0, {"t": "action", "command": "ability", "args": {"card": latest[0].legal.abilities[0]}})
		check(await _state(0, func(s: Dictionary) -> bool: return s.view.players[0].ability_hand.size() < hand_size), "prethrow ability authoritative")
	await _throw(0, slot)
	var s: Dictionary = latest[0]
	if s.view.phase == MatchController.Phase.AFTER_LANDING:
		check(s.ability_moment == "after_landing", "afterlanding moment sent")
		_send(0, {"t": "action", "command": "pass", "args": {}})
		check(await _state(0, func(row: Dictionary) -> bool: return row.view.phase == MatchController.Phase.SETUP and row.view.active_player == 1), "afterlanding pass changes turn")
	check(await _state(1, func(row: Dictionary) -> bool: return row.view.phase == MatchController.Phase.SETUP and row.view.active_player == 1), "second turn synchronized")
	if latest[1].legal.can_skip_gate:
		_send(1, {"t": "action", "command": "skip_gate", "args": {}})
	else:
		_send(1, {"t": "action", "command": "place_gate", "args": {"card": latest[1].view.players[1].arena_hand[0], "slot": int(latest[1].legal.setup_slots[0])}})
	check(await _state(1, func(row: Dictionary) -> bool: return row.view.phase == MatchController.Phase.AWAIT_THROW), "second chooses gate phase")
	_send(1, {"t": "action", "command": "select", "args": {"uid": 3}})
	check(await _state(1, func(row: Dictionary) -> bool: return row.selected_uid == 3), "second selects own creature")
	await _throw(1, slot)
	var reveal_count := 0
	for _step in range(16):
		_poll()
		var state: Dictionary = latest[1]
		if state.view.phase != MatchController.Phase.ABILITY_WINDOW: break
		var player := int(state.view.active_player)
		check(await _state(player, func(row: Dictionary) -> bool: return row.view.phase == MatchController.Phase.ABILITY_WINDOW and int(row.view.active_player) == player), "combat response belongs to seat")
		if latest[player].legal.can_reveal_gate:
			_send(player, {"t": "action", "command": "reveal_gate", "args": {}})
			reveal_count += 1
		else:
			_send(player, {"t": "action", "command": "pass", "args": {}})
		# Require a fresh state (revealing can retain same response player).
		latest[0] = {}
		latest[1] = {}
		check(await _state(0, func(_row: Dictionary) -> bool: return true), "combat state0 updates")
		check(await _state(1, func(_row: Dictionary) -> bool: return true), "combat state1 updates")
	check(int(latest[0].battle_serial) >= 1, "actual physical landing resolves battle")
	check(reveal_count >= 1, "gate owner manually opens during combat")
	if not latest[0].last_battle.is_empty():
		var battle := Codec.decode_battle(latest[0].last_battle, Codec.decode_view(latest[0].view))
		check(battle.attacker_uid == 3 and battle.defender_uid == 0 and battle.powers.size() == 2, "public battle result survives wire")
	# Room disconnect is a real socket close, not a direct service call.
	sockets[1].close(1000, "probe complete")
	var ended := await _message(0, "ended")
	check(not ended.is_empty() and ended.reason == "disconnected", "socket disconnect ends peer room")
	if service != null: check(service._rooms.is_empty(), "disconnected room released")
	_finish()

func _throw(player: int, target: int) -> void:
	_send(player, {"t": "action", "command": "launch", "args": {"slot": target}})
	check(await _state(player, func(row: Dictionary) -> bool: return row.busy), "server flight lock")
	var flight := await _message(player, "flight", 16000)
	if not check(not flight.is_empty(), "server captured actual flight"):
		return
	throws += 1
	check(flight.samples.size() > 30 and flight.samples.size() <= 600 and flight.samples[0].size() == 7, "bounded physical position/quaternion samples")
	check(flight.duration > 0.5 and flight.duration <= 10.0 and not flight.has("seed"), "flight public duration excludes seed")
	latest[player] = {}
	check(await _state(player, func(row: Dictionary) -> bool: return not row.busy and int(row.selected_uid) == -1, 16000), "server applies landing after shared flight replay")
	check(await _state(1 - player, func(row: Dictionary) -> bool: return not row.busy and int(row.selected_uid) == -1 and row.view.turn == latest[player].view.turn, 5000), "other recipient landing synchronized")
	check(int(flight.slot) == target, "actual physics landed selected test gate")
	check(Engine.max_fps == 60 and Engine.physics_ticks_per_second == 60, "server/test stays sixty FPS")

func _send(player: int, packet: Dictionary) -> void:
	sockets[player].send_text(JSON.stringify(packet))

func _poll() -> void:
	for p in range(sockets.size()):
		var ws := sockets[p]
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var packet: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if not packet is Dictionary:
				check(false, "server sent JSON dictionary")
				continue
			check(Protocol.validate_server(packet), "real server packet validated " + String(packet.get("t", "")))
			inbox[p].append(packet)
			if packet.t == "state": latest[p] = packet

func _message(player: int, type: String, timeout: int = 5000) -> Dictionary:
	var until := Time.get_ticks_msec() + timeout
	while Time.get_ticks_msec() < until:
		_poll()
		for i in range(inbox[player].size()):
			if inbox[player][i].t == type:
				var packet: Dictionary = inbox[player][i]
				inbox[player].remove_at(i)
				return packet
		await process_frame
	return {}

func _state(player: int, predicate: Callable, timeout: int = 5000) -> bool:
	var until := Time.get_ticks_msec() + timeout
	while Time.get_ticks_msec() < until:
		_poll()
		if not latest[player].is_empty() and predicate.call(latest[player]): return true
		await process_frame
	return false

func _deck(deck: DeckDef) -> Dictionary:
	var packet := {"t": "deck", "creatures": [], "gates": [], "abilities": []}
	for pair in [[deck.creatures, "creatures"], [deck.arena, "gates"], [deck.abilities, "abilities"]]:
		for definition in pair[0]: packet[pair[1]].append(String(definition.id))
	return packet

func _finish() -> void:
	if service != null:
		service.stop()
		service.queue_free()
	for ws in sockets: ws.close(-1)
	print("ONLINE LOOPBACK: %d checks, %d failures, %d physical throws" % [checks, failures, throws])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/checks/online-loopback"))
	var file := FileAccess.open("res://build/checks/online-loopback/summary.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "physical_throws": throws, "seconds": (Time.get_ticks_msec() - started_at) / 1000.0, "kind": "real_loopback_websocket_two_physical_throws"}, "  "))
	await process_frame
	quit(1 if failures else 0)
