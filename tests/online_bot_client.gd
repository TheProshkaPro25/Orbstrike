extends SceneTree
## Separate-process test bot: only observes its wire snapshot, never imports OnlineServer.
const Protocol = preload("res://network/online_protocol.gd")
var socket := WebSocketPeer.new()
var side := 0
var url := ""
var shared := ""
var sent_hello := false
var joined := false
var deck_sent := false
var ready_sent := false
var rematch_sent := false
var rematch_confirmed := false
var matches := 0
var finished_matches := 0
var throws := 0
var actions := 0
var failures := 0
var last_state: Dictionary = {}
var last_packet_at := 0
var last_ping_at := 0
var last_action_at := 0
var wants_action := false
var stopping := false
var results: Array = []
var started_at := 0

func _initialize() -> void:
	Engine.max_fps = 60
	preload("res://tools/test_window.gd").background(self)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--side="): side = int(arg.substr(7))
		elif arg.begins_with("--url="): url = arg.substr(6)
		elif arg.begins_with("--shared="): shared = arg.substr(9)
	if url.is_empty() or shared.is_empty() or side < 0 or side > 1:
		printerr("Usage --side=0|1 --url=ws://... --shared=/tmp/...")
		quit(2)
		return
	started_at = Time.get_ticks_msec()
	last_packet_at = started_at
	socket.inbound_buffer_size = Protocol.MAX_SERVER_PACKET
	socket.outbound_buffer_size = 32768
	if socket.connect_to_url(url) != OK:
		_fail("connect failed")
		return
	process_frame.connect(_tick)

func _tick() -> void:
	if stopping: return
	socket.poll()
	var now := Time.get_ticks_msec()
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_fail("unexpected closed socket")
		return
	if now - last_packet_at > 60000 or now - started_at > 240000:
		_fail("bot timed out")
		return
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return
	if not sent_hello:
		sent_hello = true
		_send({"t": "hello", "version": Protocol.VERSION, "content": Protocol.content_tag()})
	if now - last_ping_at > 20000:
		last_ping_at = now
		_send({"t": "ping"})
	while socket.get_available_packet_count() > 0:
		var message: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if not message is Dictionary:
			_fail("non-dictionary server packet")
			return
		if not Protocol.validate_server(message):
			_fail("server packet failed strict validation " + String(message.get("t", "")))
			return
		last_packet_at = now
		_message(message)
		if stopping: return
	if side == 1 and sent_hello and not joined and FileAccess.file_exists(shared + "/room.txt"):
		joined = true
		_send({"t": "join", "code": FileAccess.get_file_as_string(shared + "/room.txt"), "name": "Bot B"})
	if wants_action and now - last_action_at > 100:
		wants_action = false
		last_action_at = now
		_act(last_state)

func _message(message: Dictionary) -> void:
	match message.t:
		"hello":
			if side == 0:
				joined = true
				_send({"t": "create", "name": "Bot A"})
		"error": _fail("server error %s %s" % [message.code, message.message])
		"lobby":
			if int(message.player) != side:
				_fail("wrong seat")
				return
			if side == 0 and not FileAccess.file_exists(shared + "/room.txt"):
				var file := FileAccess.open(shared + "/room.txt", FileAccess.WRITE)
				file.store_string(message.code)
				file.close()
			if not deck_sent:
				deck_sent = true
				_send(_deck())
			if finished_matches > 0 and not message.in_match and not rematch_confirmed:
				rematch_confirmed = true
				ready_sent = false
			if not message.in_match and message.players[side].has_deck and not message.players[side].ready and not ready_sent:
				ready_sent = true
				_send({"t": "ready", "ready": true})
		"state":
			if last_state.is_empty() or (rematch_confirmed and matches == 1):
				matches += 1
				print("BOT%d match%d started" % [side, matches])
			last_state = message
			if int(message.view.phase) == MatchController.Phase.GAME_OVER:
				if not rematch_sent:
					finished_matches += 1
					results.append({"winner": int(message.winner), "reason": message.reason, "turn": int(message.view.turn), "battle_serial": int(message.battle_serial)})
					print("BOT%d gameover %s" % [side, JSON.stringify(results.back())])
					rematch_sent = true
					ready_sent = false
					_send({"t": "rematch"})
				return
			if not message.busy and int(message.view.active_player) == side: wants_action = true
		"flight":
			throws += 1
			if message.samples.size() < 30 or message.has("seed"):
				_fail("invalid/private flight")
				return
			print("BOT%d physicalflight%d owner%d samples%d" % [side, throws, int(message.owner), message.samples.size()])
			if matches >= 2 and side == 1:
				# Close a real socket during captured replay in the rematch.
				_finish("intentional_disconnect")
		"ended":
			if matches >= 2 and rematch_confirmed and finished_matches == 1:
				_finish(String(message.reason))
			else: _fail("early room ended " + String(message.reason))

func _act(state: Dictionary) -> void:
	if state.is_empty() or state.busy or int(state.view.active_player) != side: return
	var view: Dictionary = state.view
	var legal: Dictionary = state.legal
	match int(view.phase):
		MatchController.Phase.SETUP:
			if legal.can_skip_gate: _action("skip_gate")
			elif not legal.setup_slots.is_empty() and not view.players[side].arena_hand.is_empty():
				_action("place_gate", {"card": view.players[side].arena_hand[0], "slot": int(legal.setup_slots[0])})
			else: _fail("no setup action")
		MatchController.Phase.AWAIT_THROW:
			if legal.creatures.is_empty():
				_fail("no legal creature")
				return
			_action("select", {"uid": int(legal.creatures[0])})
		MatchController.Phase.AWAIT_LANDING:
			# Use one or more legal attachments, then launch toward an enemy to finish promptly.
			if not legal.abilities.is_empty():
				_action("ability", {"card": legal.abilities[0]})
				return
			var target := -1
			for i in range(6):
				var slot: Dictionary = view.slots[i]
				if not slot.has_card: continue
				if target < 0: target = i
				if int(slot.occupant_uid) >= 0:
					for creature in view.creatures:
						if int(creature.uid) == int(slot.occupant_uid) and int(creature.owner) != side:
							target = i
							break
			if int(state.throw_gate_slot) >= 0: target = int(state.throw_gate_slot)
			if target < 0: _fail("no gate target")
			else: _action("launch", {"slot": target})
		MatchController.Phase.AFTER_LANDING: _action("pass")
		MatchController.Phase.ABILITY_WINDOW:
			if legal.can_reveal_gate: _action("reveal_gate")
			elif not legal.abilities.is_empty(): _action("ability", {"card": legal.abilities[0]})
			else: _action("pass")

func _action(command: String, args: Dictionary = {}) -> void:
	actions += 1
	_send({"t": "action", "command": command, "args": args})

func _send(packet: Dictionary) -> void:
	socket.send_text(JSON.stringify(packet))

func _deck() -> Dictionary:
	var deck := CardDB.preset_deck(side)
	var packet := {"t": "deck", "creatures": [], "gates": [], "abilities": []}
	for pair in [[deck.creatures, "creatures"], [deck.arena, "gates"], [deck.abilities, "abilities"]]:
		for definition in pair[0]: packet[pair[1]].append(String(definition.id))
	return packet

func _fail(message: String) -> void:
	failures += 1
	printerr("BOT%d FAIL: %s" % [side, message])
	_finish("failure")

func _finish(reason: String) -> void:
	if stopping: return
	stopping = true
	# Immediate transport disconnect is observed by the dedicated process.
	socket.close(-1)
	var file := FileAccess.open(shared + "/bot%d.json" % side, FileAccess.WRITE)
	file.store_string(JSON.stringify({"side": side, "failures": failures, "matches": matches, "finished_matches": finished_matches,
		"rematch_confirmed": rematch_confirmed, "physical_flights": throws, "actions": actions, "results": results,
		"seconds": (Time.get_ticks_msec() - started_at) / 1000.0, "ended_reason": reason}, "  "))
	file.close()
	quit(1 if failures else 0)
