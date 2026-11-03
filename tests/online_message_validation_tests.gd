extends SceneTree
const Protocol = preload("res://network/online_protocol.gd")
const Codec = preload("res://network/state_codec.gd")
const Server = preload("res://network/online_server.gd")
var checks := 0
var failures := 0
class CaptureServer extends Server:
	var messages: Array = []
	func _send(id: int, message: Dictionary) -> void:
		if id >= 0: messages.append(message.duplicate(true))
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
func wire(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))
func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	call_deferred("run")
func run() -> void:
	var server := CaptureServer.new()
	for id in [1,2]:
		server._peers[id] = {"hello":false,"room":"","player":-1,"ws":WebSocketPeer.new()}
		server._handle(id,{"t":"hello","version":1,"content":Protocol.content_tag()})
	server._handle(1,{"t":"create","name":"A"})
	server._handle(2,{"t":"join","name":"B","code":server._peers[1].room})
	for id in [1,2]:
		var deck := CardDB.preset_deck(id-1)
		var packet := {"t":"deck","creatures":[],"gates":[],"abilities":[]}
		for pair in [[deck.creatures,"creatures"],[deck.arena,"gates"],[deck.abilities,"abilities"]]:
			for definition in pair[0]: packet[pair[1]].append(String(definition.id))
		server._handle(id,packet)
		server._handle(id,{"t":"ready","ready":true})
	var room: Dictionary = server._rooms[server._peers[1].room]
	var ctrl: MatchController = room.ctrl
	var slot: int = ctrl.legal_setup_slots()[0]
	var card: StringName = ctrl.get_view(0).players[0].arena_hand[0]
	server._handle(1,{"t":"action","command":"place_gate","args":{"card":String(card),"slot":slot}})
	var state: Dictionary = {}
	for packet in server.messages:
		check(Protocol.validate_server(wire(packet)),"real server "+packet.t)
		if packet.t == "state": state = wire(packet)
	check(not state.is_empty(),"state fixture exists")
	var broken := state.duplicate(true)
	broken.view.players = []
	check(not Protocol.validate_server(broken),"short players rejected before decode")
	broken = state.duplicate(true)
	broken.view.creatures[0].def_id = "missing_model"
	check(not Protocol.validate_server(broken),"unknown creature rejected before rendering")
	broken = state.duplicate(true)
	broken.view.creatures[0].uid = 5
	check(not Protocol.validate_server(broken),"duplicate creature rejected")
	broken = state.duplicate(true)
	broken.view.slots[0].revealed = true
	broken.view.slots[0].has_card = true
	broken.view.slots[0].card_owner = 0
	broken.view.slots[0].card_id = ""
	check(not Protocol.validate_server(broken),"revealed blank gate rejected")
	broken = state.duplicate(true)
	broken.legal.abilities = [{"injected":"object"}]
	check(not Protocol.validate_server(broken),"malformed legal cards rejected")
	broken = state.duplicate(true)
	broken.legal.abilities_left = 9
	check(not Protocol.validate_server(broken),"ability budget bounded")
	for bad in [{"t":"state"},{"t":"flight"},{"t":"lobby"},{"t":"unexpected"},{"t":"error","code":{},"message":"x"}]:
		check(not Protocol.validate_server(bad),"incomplete or unknown remote message rejected")
	var view := ctrl.get_view(0)
	view.battle_context = BattleContext.duel(view,0,3,slot)
	check(Codec.valid_view(wire(Codec.encode_view(view))),"duel context without teams supported")
	for id in CardDB.arena_ids():
		view.slots[slot].card_id = id
		view.slots[slot].revealed = true
		var battle := PowerCalc.compute_seq(view,0,3,slot,[])
		check(Codec.valid_battle(wire(Codec.preview(battle))),"real gate battle "+String(id))
	var battle := PowerCalc.compute_seq(view,0,3,slot,[])
	broken = wire(Codec.preview(battle))
	broken.powers = ["bad",0]
	check(not Codec.valid_battle(broken),"typed power array rejected")
	broken = wire(Codec.preview(battle))
	broken.attacker_uid = 6
	check(not Codec.valid_battle(broken),"battle uid outside roster rejected")
	var flight := {"t":"flight","uid":0,"slot":slot,"samples":[[0,0,0,0,0,0,1],[1,.4,1,0,0,0,1]],"duration":1.0/60.0,"position":[1,.4,1],"quaternion":[0,0,0,1],"bounces":2,"timed_out":false,"owner":0,"target_slot":slot}
	check(Protocol.validate_server(wire(flight)),"valid sampled flight")
	for key in ["samples","position","quaternion"]:
		broken = wire(flight)
		broken[key] = []
		check(not Protocol.validate_server(broken),"short trajectory component "+key)
	broken = wire(flight)
	broken.samples[0][6] = 0
	check(not Protocol.validate_server(broken),"nonunit quaternion rejected")
	broken = wire(flight)
	broken.samples[0][0] = 10000
	check(not Protocol.validate_server(broken),"physical coordinate bounded")
	broken = wire(flight)
	broken.duration = .5
	check(not Protocol.validate_server(broken),"unrelated replay duration rejected")
	server._leave(1,"fixture")
	server._peers.clear()
	server.free()
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/checks/online-messages"))
	var report := FileAccess.open("res://build/checks/online-messages/summary.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("ONLINE MESSAGE VALIDATION: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
