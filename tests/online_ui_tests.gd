extends SceneTree
## Actual Boot -> internet menu -> room -> resident team -> physical match -> result.
const Client = preload("res://network/online_client.gd")
const Server = preload("res://network/online_server.gd")
const Codec = preload("res://network/state_codec.gd")
var game: Node
var service: Node
var opponent: Client
var opponent_state: Dictionary = {}
var opponent_pending := false
var checks := 0
var failures := 0
var out := "res://build/checks/online-ui"
var _driving := false
var _captures: Dictionary = {}
var _started := 0
var _counts: Array = []
var _last_opponent_battle := 0
var _capture_pause := false
var _progress_at := 0
var opponent_lobby: Dictionary = {}
var _pause_peer1 := false

func _initialize() -> void:
	Engine.max_fps = 60
	if not OS.get_cmdline_user_args().is_empty(): out = OS.get_cmdline_user_args()[0]
	print("ONLINE UI RUN: ",out)
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	_started = Time.get_ticks_msec()
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ",label)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file("res://scenes/loading/boot.tscn")
	if not await until(func() -> bool: return current_scene != null and current_scene.scene_file_path == "res://scenes/menu/main_menu.tscn",180):
		_finish("Boot did not reach menu")
		return
	await create_timer(1.8).timeout
	var menu: MainMenu = current_scene
	check(menu._buttons.size() == 10,"menu has10actions including internet")
	for button in menu._buttons: check(button.get_global_rect().end.y <= 720,"1280 menu button visible: "+button.text)
	await shot("01-menu")
	root.size = Vector2i(960,540)
	root.content_scale_size = root.size
	await process_frame
	await process_frame
	for button in menu._buttons: check(button.get_global_rect().position.y >= 0 and button.get_global_rect().end.y <= 540,"960 menu button visible: "+button.text)
	await shot("02-menu-960")
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	_counts = preparation_counts()
	for button in menu._buttons:
		if button.text == "Игра через интернет": button.pressed.emit(); break
	await process_frame
	game = current_scene
	if not check_game(): return
	check(game._connection_panel.visible and not game.hud.visible,"internet connection screen opens")
	check(game._address.text.is_empty() or game._address.text.begins_with("ws"),"address is explicit configurable value")
	await shot("03-connect")
	root.size = Vector2i(960,540)
	root.content_scale_size = root.size
	await process_frame
	await shot("04-connect-960")
	check(game._connection_panel.get_global_rect().position.y >= 0 and game._connection_panel.get_global_rect().end.y <= 540,"connection panel fits960")
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	service = Server.new()
	root.add_child(service)
	var port := 20000 + OS.get_process_id()%20000
	check(service.listen(port,"127.0.0.1") == OK,"UI dedicated service listener")
	game._address.text = "ws://127.0.0.1:%d" % port
	game._connect_button.pressed.emit()
	if not await until(func() -> bool: return game.client.verified,5):
		_finish("UI handshake failed")
		return
	game._create_button.pressed.emit()
	if not await until(func() -> bool: return not game.lobby.is_empty(),5):
		_finish("UI room creation failed")
		return
	var code: String = game.lobby.code
	opponent = Client.new()
	root.add_child(opponent)
	opponent.message.connect(_opponent_message)
	opponent.connect_server(game._address.text)
	if not await until(func() -> bool: return opponent.verified,5):
		_finish("opponent handshake failed")
		return
	opponent.send({"t":"join","code":code,"name":"Online Rival"})
	if not await until(func() -> bool: return game.lobby.players[1].connected,5):
		_finish("opponent join failed")
		return
	await shot("05-room")
	check(game.local_side == 0 and game.lobby.players[1].name == "Online Rival","room code connects two identities")
	game._deck_button.pressed.emit()
	await process_frame
	check(game.team_menu.visible and not game.team_menu._arena_btn.visible,"current team constructor reused")
	game.team_menu.pick_random()
	await create_timer(.7).timeout
	await shot("06-team")
	game.team_menu.pick_random_and_start()
	if not await until(func() -> bool: return game.lobby.players[0].has_deck,5):
		_finish("UI deck acknowledgement failed")
		return
	var deck := CardDB.preset_deck(1)
	var packet := {"t":"deck","creatures":[],"gates":[],"abilities":[]}
	for c in deck.creatures: packet.creatures.append(String(c.id))
	for c in deck.arena: packet.gates.append(String(c.id))
	for c in deck.abilities: packet.abilities.append(String(c.id))
	opponent.send(packet)
	if not await until(func() -> bool: return game.lobby.players[1].has_deck,5):
		_finish("opponent deck acknowledgement failed")
		return
	opponent.send({"t":"ready","ready":true})
	game._ready_button.pressed.emit()
	if not await until(func() -> bool: return game._match_ready and not game.events.is_busy(),15):
		_finish("UI match start failed")
		return
	check(preparation_counts() == _counts,"Boot catalog allocation counts unchanged at online start")
	check(game.balls.size()==6 and game.fighters.size()==2,"six resident creatures and two fighters leased")
	check(game.snapshot.view.players[1].arena_hand == ["","",""],"UI only receives masked remote cards")
	await shot("07-hands")
	_driving = true
	process_frame.connect(_drive)
	if not await until(func() -> bool: return game._game_over and game.game_over_ui._panel.visible,420):
		_finish("UI physical match did not complete")
		return
	_driving = false
	await shot("11-result")
	check(game._flight_count > 0,"recorded server physical trajectories rendered")
	check(_last_opponent_battle > 0 and game._last_battle_serial > 0,"public battle results displayed")
	check(preparation_counts()==_counts,"online full match keeps resident preparation counts")
	check(Engine.max_fps==60,"test remains limited60FPS")
	game._on_restart()
	opponent.send({"t":"rematch"})
	if not await until(func() -> bool: return not game._match_ready and game._connection_panel.visible,10):
		_finish("UI rematch lobby failed")
		return
	check(not game.lobby.players[0].ready and not game.lobby.players[1].ready,"rematch requires readiness and allows deck changes")
	await shot("12-rematch")
	opponent.close()
	if not await until(func() -> bool: return game._closed,5): check(false,"disconnect notification arrives")
	check(game._connection_panel.visible,"disconnect returns to clear connection screen")
	# A fresh connection takes seat1 with a different deck, without another catalog build.
	opponent_state = {}
	opponent_lobby = {}
	opponent_pending = false
	opponent.connect_server(game._address.text)
	game._connect_button.pressed.emit()
	if not await until(func() -> bool: return opponent.verified and game.client.verified,5):
		_finish("reconnect handshake failed")
		return
	opponent.send({"t":"create","name":"Online Host"})
	if not await until(func() -> bool: return not opponent_lobby.is_empty(),5):
		_finish("reconnect hostroom failed")
		return
	game.client.send({"t":"join","name":"Peer One","code":opponent_lobby.code})
	if not await until(func() -> bool: return not game.lobby.is_empty() and game.local_side == 1,5):
		_finish("seat1 join failed")
		return
	for side in range(2):
		var next_deck := CardDB.preset_deck(side)
		var next_packet := {"t":"deck","creatures":[],"gates":[],"abilities":[]}
		for c in next_deck.creatures: next_packet.creatures.append(String(c.id))
		for c in next_deck.arena: next_packet.gates.append(String(c.id))
		for c in next_deck.abilities: next_packet.abilities.append(String(c.id))
		if side == 0: opponent.send(next_packet)
		else: game.client.send(next_packet)
	if not await until(func() -> bool: return game.lobby.players[0].has_deck and game.lobby.players[1].has_deck,5):
		_finish("seat1 deck confirmations failed")
		return
	opponent.send({"t":"ready","ready":true})
	game._ready_button.pressed.emit()
	_pause_peer1 = true
	_driving = true
	if not await until(func() -> bool: return game._match_ready and game.local_side == 1 and not _driving,90):
		_finish("seat1 prethrow did not arrive")
		return
	check(game.snapshot.view.players[0].arena_hand.all(func(id): return id == ""),"seat1 never gets host hand")
	check(game.snapshot.view.players[1].ability_hand.all(func(id): return not String(id).is_empty()),"seat1 own abilities remain visible")
	check(game._owner_of(int(game.snapshot.selected_uid)) == 1,"seat1 only selects its own creature")
	check(game.balls.size()==6 and preparation_counts()==_counts,"fresh reconnect leases correct actors without rebuilding")
	await shot("13-peer1-prethrow")
	var before: int = game._flight_count
	var target := int(decision(game.snapshot).args.slot)
	game._on_slot_picked(target)
	if not await until(func() -> bool: return game._flight_count>before and not game.events.is_busy(),25):
		_finish("seat1 physical replay did not complete")
		return
	check(int(game._last_flight.owner)==1,"seat1 flight originates on authoritative side1")
	await shot("14-peer1-landing")
	_finish()

func check_game() -> bool:
	if game == null or game.scene_file_path != "res://scenes/online/online_game.tscn":
		_finish("internet menu did not open online scene")
		return false
	return true

func preparation_counts() -> Array:
	var pool := GameLoading.i()
	return [pool.preparation_count,pool.actor_build_count,pool.arena_build_count,pool.fighter_build_count]

func _opponent_message(data: Dictionary) -> void:
	if data.t == "lobby": opponent_lobby = data
	elif data.t == "state":
		opponent_state = data
		opponent_pending = false
		_last_opponent_battle = maxi(_last_opponent_battle,int(data.battle_serial))
	elif data.t == "error":
		check(false,"opponent command: "+str(data))
		opponent_pending = false

func _drive() -> void:
	if not _driving or game == null or _capture_pause: return
	if Time.get_ticks_msec()-_progress_at > 2000:
		_progress_at = Time.get_ticks_msec()
		var file := FileAccess.open(out+"/progress.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"seconds":(Time.get_ticks_msec()-_started)/1000.0,"phase":game.snapshot.get("view",{}).get("phase",-1),"turn":game.snapshot.get("view",{}).get("turn",0),"events":game.events._queue.size(),"running":game.events._running,"flight":game._flight_count,"battle":game._last_battle_serial,"overlay":game.battle_overlay._open,"pending":game._input_pending,"stage":game.get_meta("online_presentation","other"),"actors":game.balls.values().map(func(ball): return {"uid":ball.uid,"visible":ball.is_visible_in_tree(),"figure":ball._figure.is_visible_in_tree(),"open":ball._open,"anim":ball._anim.is_visible_in_tree(),"action":String(ball._anim._action),"elapsed":ball._anim._elapsed})}))
	if game.battle_overlay._open: game.battle_overlay._close()
	if game.director.flying and not _captures.has("flight"):
		_captures.flight = true
		_capture_later("08-flight")
	if game.battle_hud.visible and game._battle_key != "" and not game.events.is_busy() and not _captures.has("battle"):
		_captures.battle = true
		_capture_ready("09-battle")
		return
	if not game._input_pending and not game.events.is_busy() and not game.snapshot.is_empty() and not game._game_over:
		if _pause_peer1 and int(game.snapshot.view.active_player) == 1 and int(game.snapshot.view.phase) == MatchController.Phase.AWAIT_LANDING:
			_driving = false
			return
		var command := decision(game.snapshot)
		if not command.is_empty(): game._command(command.command,command.args)
	if not opponent_pending and not opponent_state.is_empty():
		var command := decision(opponent_state)
		if not command.is_empty():
			opponent_pending = true
			opponent.action(command.command,command.args)

func decision(state: Dictionary) -> Dictionary:
	var side := int(state.player)
	var view := Codec.decode_view(state.view)
	if state.busy or int(state.winner) != -2 or view.active_player != side: return {}
	var legal: Dictionary = state.legal
	match view.phase:
		MatchController.Phase.SETUP:
			if legal.can_skip_gate: return {"command":"skip_gate","args":{}}
			return {"command":"place_gate","args":{"card":view.players[side].arena_hand[0],"slot":int(legal.setup_slots[0])}}
		MatchController.Phase.AWAIT_THROW:
			return {"command":"select","args":{"uid":int(legal.creatures[0])}}
		MatchController.Phase.AWAIT_LANDING:
			var target := -1
			for slot in range(6):
				if view.slots[slot].has_card:
					target = slot
					var occupant := view.creature(view.slots[slot].occupant_uid)
					if occupant != null and occupant.owner != side: break
			return {"command":"launch","args":{"slot":target}}
		MatchController.Phase.AFTER_LANDING: return {"command":"pass","args":{}}
		MatchController.Phase.ABILITY_WINDOW:
			if legal.can_reveal_gate: return {"command":"reveal_gate","args":{}}
			if not legal.abilities.is_empty(): return {"command":"ability","args":{"card":legal.abilities[0]}}
			return {"command":"pass","args":{}}
	return {}

func _capture_ready(name: String) -> void:
	_capture_pause = true
	await shot(name)
	_capture_pause = false

func _capture_later(name: String) -> void:
	await create_timer(.6).timeout
	await shot(name)

func until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call(): return true
		await process_frame
	return false

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(out+"/"+name+".png")==OK,"PNG "+name)

func _finish(error: String = "") -> void:
	if not error.is_empty(): check(false,error)
	_driving = false
	if is_instance_valid(opponent): opponent.close(); opponent.queue_free()
	if is_instance_valid(service): service.stop(); service.queue_free()
	if is_instance_valid(current_scene): current_scene.queue_free()
	for _frame in range(8): await process_frame
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	for _frame in range(8): await process_frame
	print("Online UI: %d checks, %d failures, %.2fs" % [checks,failures,(Time.get_ticks_msec()-_started)/1000.0])
	quit(1 if failures else 0)
