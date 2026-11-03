extends SceneTree
const Protocol = preload("res://network/online_protocol.gd")
const Codec = preload("res://network/state_codec.gd")
const Server = preload("res://network/online_server.gd")
var checks := 0
var failures := 0

class CaptureServer extends Server:
	var messages: Dictionary = {}
	func _send(id: int, message: Dictionary) -> void:
		if id < 0: return
		if not messages.has(id): messages[id] = []
		messages[id].append(message.duplicate(true))
	func last(id: int, type: String) -> Dictionary:
		var rows: Array = messages.get(id, [])
		for i in range(rows.size() - 1, -1, -1):
			if rows[i].t == type: return rows[i]
		return {}

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	_test_protocol()
	_test_codec()
	_test_server()
	print("ONLINE CORE: %d checks, %d failures" % [checks, failures])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/checks/online-core"))
	var file := FileAccess.open("res://build/checks/online-core/summary.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "kind": "headless_online_authority_privacy_lifecycle"}, "  "))
	quit(1 if failures else 0)

func _packet(deck: DeckDef) -> Dictionary:
	var out := {"t": "deck", "creatures": [], "gates": [], "abilities": []}
	for pair in [[deck.creatures, "creatures"], [deck.arena, "gates"], [deck.abilities, "abilities"]]:
		for definition in pair[0]: out[pair[1]].append(String(definition.id))
	return out

func _test_protocol() -> void:
	check(Protocol.content_tag().length() == 64, "stable content digest")
	for packet in [{"t": "hello", "version": 1, "content": Protocol.content_tag()}, {"t": "create", "name": "Тест"}, {"t": "join", "name": "Other", "code": "ABCDEFGH"}, {"t": "ready", "ready": true}, {"t": "leave"}, {"t": "rematch"}, {"t": "ping"}, _packet(CardDB.preset_deck(0))]:
		check(Protocol.validate(packet).is_empty(), "known message accepted " + packet.t)
	var valid: Array = [{"command": "place_gate", "args": {"card": "gate_x", "slot": 2}}, {"command": "throw_with_gate", "args": {"card": "gate_x", "slot": 2, "uid": 0}}, {"command": "select", "args": {"uid": 0}}, {"command": "launch", "args": {"slot": 0}}, {"command": "ability", "args": {"card": "ability_x"}}, {"command": "skip_gate", "args": {}}, {"command": "pass", "args": {}}, {"command": "reveal_gate", "args": {}}]
	for packet in valid:
		packet.t = "action"
		check(Protocol.validate(packet).is_empty(), "known command accepted " + packet.command)
	for packet in [{}, {"t": 1}, {"t": "report_landing", "uid": 0, "slot": 0}, {"t": "action", "command": "report_landing", "args": {}}, {"t": "action", "command": "select", "args": {"uid": 0, "player": 1}}, {"t": "action", "command": "select", "args": {"uid": true}}, {"t": "action", "command": "select", "args": {"uid": 1.5}}, {"t": "action", "command": "select", "args": {"uid": -1}}, {"t": "action", "command": "launch", "args": {"slot": 6}}, {"t": "ready", "ready": 1}, {"t": "create", "name": "x\ny"}, {"t": "ping", "state": {}}, {"t": "join", "name": "x", "code": 1}, {"t": "deck", "creatures": [0, 1, 2], "gates": [], "abilities": []}]:
		check(not Protocol.validate(packet).is_empty(), "malformed/spoofed message rejected")
	var deck := _packet(CardDB.preset_deck(0))
	check(Protocol.deck_error(deck).is_empty(), "existing CardDB deck rules accepted")
	var wrong := deck.duplicate(true)
	wrong.creatures[1] = wrong.creatures[0]
	check(not Protocol.deck_error(wrong).is_empty(), "duplicate creature rejected")
	wrong = deck.duplicate(true)
	wrong.gates[0] = wrong.abilities[0]
	check(not Protocol.deck_error(wrong).is_empty(), "wrong kind rejected before build")
	wrong = deck.duplicate(true)
	wrong.creatures[0] = String(CardDB.RARE_SHADOW_ID)
	check(not Protocol.deck_error(wrong).is_empty(), "NPC rare creature rejected")
	wrong = deck.duplicate(true)
	wrong.creatures[0] = "not_in_catalog"
	check(not Protocol.deck_error(wrong).is_empty(), "unknown creature rejected")

func _test_codec() -> void:
	var ctrl := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(1), 123)
	ctrl.start(0)
	var card: StringName = ctrl.get_view(0).players[0].arena_hand[0]
	var slot: int = ctrl.legal_setup_slots()[0]
	check(ctrl.place_arena_card(0, card, slot) == OK, "privacy setup")
	for p in range(2):
		var wire := Codec.encode_view(ctrl.get_view(p))
		var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(wire))
		var view := Codec.decode_view(roundtrip)
		check(view.slots[slot].card_id == (card if p == 0 else &""), "closed gate masked per recipient")
		check(view.slots[slot].has_card, "hidden gate presence public")
		for id in view.players[1 - p].arena_hand: check(id == &"", "opponent gate hand masked")
		for id in view.players[1 - p].ability_hand: check(id == &"", "opponent ability hand masked")
		check(view.players[p].ability_hand == ctrl.get_view(p).players[p].ability_hand, "own hand roundtrip")
		check(view.creatures.size() == 6 and view.players[0].creature_uids == [0, 1, 2], "public roster stable")
		for secret in ["seed", "actions", "action_trace", "decks", "draw_pools"]: check(not wire.has(secret), "no private diagnostics " + secret)
	var battle := BattleResult.new()
	battle.powers = [410, 390]
	battle.attacker_uid = 0
	battle.defender_uid = 3
	battle.atk_ability = &"ability_test"
	battle.plays = [[0, &"ability_test"]]
	battle.breakdown = [{"side": 0, "source": "base", "delta": 410}]
	var restored := Codec.decode_battle(JSON.parse_string(JSON.stringify(Codec.preview(battle))), ctrl.get_view(0))
	check(restored.powers == battle.powers and restored.atk_ability == battle.atk_ability, "battle typed fields roundtrip")
	check(restored.context != null and restored.context.participants.size() == 2, "battle public context reconstructed")

func _test_server() -> void:
	var server := CaptureServer.new()
	for id in range(1, 5): server._peers[id] = {"hello": false, "room": "", "player": -1, "ws": WebSocketPeer.new()}
	server._handle(1, {"t": "create", "name": "A"})
	check(server._rooms.is_empty(), "handshake required")
	server._handle(1, {"t": "hello", "version": 999, "content": Protocol.content_tag()})
	check(not server._peers[1].hello, "incompatible version rejected")
	for id in range(1, 5): server._handle(id, {"t": "hello", "version": 1, "content": Protocol.content_tag()})
	server._handle(1, {"t": "create", "name": "A"})
	var code: String = server._peers[1].room
	check(code.length() == 8 and server._rooms.size() == 1, "opaque room code")
	server._handle(2, {"t": "join", "code": code, "name": "B"})
	server._handle(3, {"t": "join", "code": code, "name": "C"})
	check(server._peers[2].player == 1 and server._peers[3].room == "", "two socket owned seats only")
	server._handle(1, {"t": "ready", "ready": true})
	var room: Dictionary = server._rooms[code]
	check(not room.ready[0] and room.ctrl == null, "deck required before ready")
	server._handle(1, _packet(CardDB.preset_deck(0)))
	server._handle(2, _packet(CardDB.preset_deck(1)))
	check(server.last(1, "lobby").players[0].has_deck, "deck acknowledgement")
	var lobby: Dictionary = server.last(2, "lobby")
	check(not lobby.players[0].has("gates") and not lobby.players[0].has("abilities"), "lobby publishes creatures only")
	server._handle(1, {"t": "ready", "ready": true})
	check(room.ctrl == null, "one ready does not start")
	server._handle(2, {"t": "ready", "ready": true})
	var ctrl: MatchController = room.ctrl
	check(ctrl != null and ctrl.landing_window, "two confirmations start authoritative match with afterlanding")
	var own: Dictionary = server.last(1, "state")
	var other: Dictionary = server.last(2, "state")
	check(own.player == 0 and other.player == 1, "recipient seat snapshots")
	check(own.legal.setup_slots.size() > 0 and other.legal.setup_slots.is_empty(), "legal actions belong to seat")
	var card: StringName = ctrl.get_view(0).players[0].arena_hand[0]
	var slot: int = ctrl.legal_setup_slots()[0]
	server._handle(2, {"t": "action", "command": "place_gate", "args": {"card": String(card), "slot": slot}})
	check(ctrl.get_phase() == MatchController.Phase.SETUP, "wrong socket cannot act on other turn")
	server._handle(1, {"t": "action", "command": "place_gate", "args": {"card": String(card), "slot": slot}})
	check(ctrl.get_phase() == MatchController.Phase.AWAIT_THROW, "legal gate action")
	check(server.last(2, "state").view.slots[slot].card_id == "", "wire closed gate never leaks")
	server._handle(1, {"t": "action", "command": "select", "args": {"uid": 3}})
	check(ctrl.get_selected_uid() == -1, "cannot select enemy UID")
	server._handle(1, {"t": "action", "command": "select", "args": {"uid": 0}})
	check(ctrl.get_selected_uid() == 0, "legal select opens prethrow attach")
	room.busy = true
	server._handle(1, {"t": "action", "command": "ability", "args": {"card": String(ctrl.get_view(0).players[0].ability_hand[0])}})
	check(server.last(1, "error").code == "flight_busy", "flight lock blocks rule changes")
	room.busy = false
	# Explicit core fixture endpoint is internal only; network schema rejects it above.
	ctrl.report_landing(0, slot)
	check(ctrl.get_selected_uid() == -1, "internal authoritative landing advances rules")
	ctrl._end_game(0, &"fixture")
	var old_physics: Node = room.physics
	server._handle(1, {"t": "rematch"})
	check(room.ctrl != null and room.rematch[0], "one rematch vote waits")
	server._handle(2, {"t": "rematch"})
	check(room.ctrl == null and room.physics == null and old_physics.is_queued_for_deletion(), "both votes release physical world")
	check(room.ready == [false, false] and not room.decks[0].is_empty(), "rematch preserves decks and resets readiness")
	server._handle(1, {"t": "leave"})
	check(server._rooms.is_empty() and server._peers[2].room == "", "leave closes room and releases both seats")
	check(server.last(2, "ended").reason == "left", "remaining peer receives end reason")
	server._peers.clear()
	server.free()
