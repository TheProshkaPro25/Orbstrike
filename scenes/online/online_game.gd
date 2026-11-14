extends "res://scenes/main.gd"
## Reuses the current arena, resident actors, hands and sequential presentation.
## Match decisions are exclusively commands to the dedicated server.
const HelpPolicy := preload("res://scenes/presentation/online_help_policy.gd")
var _help_policy: HelpPolicy
const Client = preload("res://network/online_client.gd")
const Codec = preload("res://network/state_codec.gd")
const ViewAdapter = preload("res://network/online_view.gd")
var client: Client
var local_side := -1
var lobby: Dictionary = {}
var snapshot: Dictionary = {}
var _connection_panel: PanelContainer
var _connection_box: VBoxContainer
var _address: LineEdit
var _room_code: LineEdit
var _connection_status: Label
var _room_label: Label
var _members: Label
var _connect_button: Button
var _create_button: Button
var _join_button: Button
var _deck_button: Button
var _ready_button: Button
var _leave_button: Button
var _room_buttons: HBoxContainer
var _initial_buttons: HBoxContainer
var _rendered_slots: Dictionary = {}
var _battle_key := ""
var _last_battle_serial := 0
var _last_standoff_serial := 0
var _input_pending := false
var _match_ready := false
var _names: Array = ["", ""]
var _flight_count := 0
var _last_flight: Dictionary = {}
var _connection_epoch := 0
var _closed := false
var _cleaning_match := false

func _ready() -> void:
	_previous_time_scale = Engine.time_scale
	Engine.time_scale = 1.0
	rng.randomize()
	CardDB.load_all()
	ctrl = ViewAdapter.new()
	_build_world()
	_build_ui(false, true)
	_help_policy = HelpPolicy.new(presentation)
	presentation.slot_help = _help_policy.slot_tip
	presentation.creature_help = _help_policy.creature_tip
	client = Client.new()
	add_child(client)
	client.message.connect(_message)
	client.status.connect(_status)
	client.disconnected.connect(_disconnected)
	events.drained.connect(_show_input)
	team_menu.hide()
	team_menu.deck_chosen.connect(_on_deck_chosen)
	# The server uses the same geometry for all locations; this first version uses the Sanctuary.
	team_menu._arena_btn.hide()
	hud.visible = false
	hud._tempo.hide()
	hud.creature_chosen.connect(_on_creature_chosen)
	hud.creature_cancelled.connect(_on_gate_throw_cancelled)
	setup_panel.placed.connect(_on_setup_placed)
	setup_panel.placed_throw.connect(_on_setup_placed_throw)
	setup_panel.skipped.connect(_on_setup_skipped)
	ability_panel.ability_chosen.connect(_on_ability_chosen)
	ability_panel.gate_open_requested.connect(_on_gate_open_requested)
	ability_panel.passed.connect(_on_ability_passed)
	ability_panel.unavailable.connect(func(reason: String) -> void: hud.reject_action(reason))
	ability_panel.reason_for_card = func(id: StringName) -> String:
		return str(snapshot.get("legal", {}).get("ability_reasons", {}).get(String(id), "Ожидается ответ сервера"))
	ability_panel.warning_for_card = MatchController.ability_play_warning
	arena.slot_clicked.connect(_on_slot_picked)
	game_over_ui.restart_requested.connect(_on_restart)
	game_over_ui.set_restart_text("Реванш")
	setup_panel.set_dock_visible(false)
	ability_panel.set_dock_visible(false)
	_build_connection_ui()
	SoundFx.i().play_music(SoundFx.MUSIC_TEAM)

func _build_connection_ui() -> void:
	_connection_panel = PanelContainer.new()
	_connection_panel.name = "InternetLobby"
	_connection_panel.theme = UiTheme.get_theme()
	_connection_panel.add_theme_stylebox_override("panel", UiTheme.box(Color(.025,.035,.065,.97), UiTheme.GOLD_DIM, 2, 14, 24))
	_connection_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_connection_panel.offset_left = -330
	_connection_panel.offset_right = 330
	_connection_panel.offset_top = -242
	_connection_panel.offset_bottom = 242
	ui_layer.add_child(_connection_panel)
	_connection_box = VBoxContainer.new()
	_connection_box.add_theme_constant_override("separation", 12)
	_connection_panel.add_child(_connection_box)
	var title := VisualUtil.label("ИГРА ЧЕРЕЗ ИНТЕРНЕТ", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	_connection_box.add_child(title)
	var note := VisualUtil.label("Приватная дуэль 1 на 1 · пригласите друга по коду комнаты", 17)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_connection_box.add_child(note)
	_connection_box.add_child(VisualUtil.label("Адрес сервера", 16))
	_address = LineEdit.new()
	_address.placeholder_text = "wss://ваш-сервер.example"
	_address.text = Client.saved_address()
	_address.custom_minimum_size.y = 42
	_connection_box.add_child(_address)
	_connect_button = _button(_connection_box, "Подключиться", _connect)
	_initial_buttons = HBoxContainer.new()
	_connection_box.add_child(_initial_buttons)
	_create_button = _button(_initial_buttons, "Создать комнату", func() -> void: client.send({"t":"create", "name": _profile_name()}))
	_room_code = LineEdit.new()
	_room_code.placeholder_text = "Код комнаты"
	_room_code.max_length = 8
	_room_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_initial_buttons.add_child(_room_code)
	_join_button = _button(_initial_buttons, "Войти", func() -> void:
		client.send({"t":"join", "code": _room_code.text.strip_edges().to_upper(), "name": _profile_name()}))
	_room_label = VisualUtil.label("", 27)
	_room_label.add_theme_color_override("font_color", UiTheme.GOLD)
	_connection_box.add_child(_room_label)
	_members = VisualUtil.label("", 19)
	_members.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_connection_box.add_child(_members)
	_room_buttons = HBoxContainer.new()
	_connection_box.add_child(_room_buttons)
	_deck_button = _button(_room_buttons, "Выбрать команду и карты", _choose_deck)
	_ready_button = _button(_room_buttons, "Готов", func() -> void:
		if not lobby.is_empty(): client.send({"t":"ready", "ready": not bool(lobby.players[local_side].ready)}))
	_connection_status = VisualUtil.label("Укажите адрес размещённого сервера. Общедоступный сервер ещё не назначен.", 17)
	_connection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_connection_status.custom_minimum_size = Vector2(580, 52)
	_connection_box.add_child(_connection_status)
	_button(_connection_box, "В главное меню", _leave)
	_leave_button = Button.new()
	_leave_button.text = "Покинуть комнату"
	_leave_button.custom_minimum_size = Vector2(160, 38)
	_leave_button.pressed.connect(_leave)
	ui_layer.add_child(_leave_button)
	_place_leave_button(false)
	_leave_button.hide()
	_refresh_lobby()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _profile_name() -> String:
	var profile := PlayerProfile.new()
	profile.load_from()
	return String(profile.value.name).strip_edges().left(32)

func _connect() -> void:
	if _cleaning_match: return
	_closed = false
	_connection_epoch += 1
	client.connect_server(_address.text)

func _status(text: String) -> void:
	if is_instance_valid(_connection_status): _connection_status.text = text
	if is_instance_valid(hud) and hud.visible: hud.set_hint(text)
	_refresh_lobby()

func _refresh_lobby() -> void:
	if not is_instance_valid(_connection_panel): return
	var in_room := not lobby.is_empty()
	_connect_button.disabled = _cleaning_match
	_create_button.disabled = not client.verified or in_room
	_join_button.disabled = not client.verified or in_room
	_initial_buttons.visible = not in_room
	_connect_button.visible = not in_room
	_address.editable = not in_room
	_room_buttons.visible = in_room
	_room_label.visible = in_room
	_members.visible = in_room
	if in_room:
		_room_label.text = "Код комнаты: " + String(lobby.code)
		var lines: Array[String] = []
		for i in range(2):
			var member: Dictionary = lobby.players[i]
			var present := bool(member.get("connected", false))
			lines.append("%s%s — %s" % [str(member.get("name", "Ожидание друга")) if present else "Ожидание друга", " (вы)" if i == local_side else "", "готов" if member.get("ready", false) else ("команда выбрана" if member.get("has_deck", false) else "выбор команды")])
		_members.text = "\n".join(lines)
		_ready_button.disabled = not bool(lobby.players[local_side].get("has_deck", false))
		_ready_button.text = "Не готов" if lobby.players[local_side].ready else "Готов"
		_deck_button.disabled = bool(lobby.players[local_side].ready)

func _choose_deck() -> void:
	_connection_panel.hide()
	team_menu.show()
	team_menu.refresh_settings_labels()
	_place_leave_button(false)
	_leave_button.show()

func _on_deck_chosen(creatures: Array[StringName], gates: Array[StringName], abilities: Array[StringName]) -> void:
	if not creatures.all(CardDB.online_creature_available):
		_status("В интернет-дуэли доступны только существа сетевого каталога.")
		return
	client.send({"t":"deck", "creatures":creatures, "gates":gates, "abilities":abilities})
	team_menu.hide()
	team_menu._preview.release()
	_connection_panel.show()
	_status("Команда отправлена серверу. Когда оба готовы, матч начнётся.")

func _message(data: Dictionary) -> void:
	match str(data.t):
		"hello": _refresh_lobby()
		"error":
			_input_pending = false
			_status(str(data.get("message", data.get("text", "Сервер отклонил действие"))))
			if _match_ready: _show_input()
		"lobby":
			lobby = data
			local_side = int(data.player)
			for i in range(2): _names[i] = str(data.players[i].get("name", "Ожидание друга"))
			_refresh_lobby()
			if _match_ready and data.get("in_match", false) == false and int(snapshot.get("winner", -2)) != -2:
				_return_to_lobby()
		"state":
			_input_pending = false
			events.push(_apply_snapshot.bind(data))
		"flight": events.push(_play_flight.bind(data))
		"ended": _disconnected("Соперник покинул комнату. Матч завершён.")

func _apply_snapshot(data: Dictionary) -> void:
	if not is_inside_tree() or _closed: return
	var epoch := _connection_epoch
	local_side = int(data.player)
	snapshot = data
	_help_policy.set_view(data,local_side)
	ctrl.state = Codec.decode_view(data.view)
	if not _match_ready: _prepare_online_match()
	_connection_panel.hide()
	team_menu.hide()
	hud.show()
	_place_leave_button(true)
	_leave_button.show()
	_hide_input()
	var view := ctrl.state
	var removed_slots: Array[int] = []
	for slot in range(6):
		var state := view.slots[slot]
		if state.has_card and not card_nodes.has(slot):
			await director.card_placed(state.card_owner, slot)
			if _closed or epoch != _connection_epoch: return
		elif not state.has_card and card_nodes.has(slot):
			removed_slots.append(slot)
		if state.has_card and card_nodes.has(slot):
			var node: ArenaCardNode = card_nodes[slot]
			if state.revealed: node.reveal(CardDB.card(state.card_id))
			else: node.show_facedown(state.card_owner, CardDB.card(state.card_id))
	var serial := int(data.get("battle_serial", 0))
	var standoff_serial := int(data.get("standoff_serial", 0))
	if standoff_serial > _last_standoff_serial:
		_last_standoff_serial = standoff_serial
		var pair: Array = data.last_standoff
		var attacker := CardDB.creature(view.creatures[int(pair[0])].def_id).display_name
		var defender := CardDB.creature(view.creatures[int(pair[1])].def_id).display_name
		var notice := "Тупик: жребий выбрал атакующего — %s идёт на %s!" % [attacker, defender]
		hud.flash(notice)
		await hud.wait_read(HudUI.read_time(1.4, notice))
		if _closed or epoch != _connection_epoch: return
		hud.clear_flash()
	if serial > _last_battle_serial:
		_last_battle_serial = serial
		var result := Codec.decode_battle(data.last_battle, view)
		if result != null:
			# The rules may resolve immediately when neither side has a response.
			# In that case no ability-window snapshot introduced these fighters.
			# Show the actual pair before awaiting their contact animation.
			for uid in [result.attacker_uid,result.defender_uid]:
				var fighter_ball: CreatureBall = balls[uid]
				fighter_ball.show()
				fighter_ball.set_process(true)
				if not fighter_ball._open: fighter_ball.open_animated(false)
			if _battle_key == "":
				set_meta("online_presentation","battle-intro-auto")
				await director.battle_started(result.slot,result.attacker_uid,result.defender_uid,result.powers,result.momentum)
				if _closed or epoch != _connection_epoch: return
			set_meta("online_presentation","battle-result")
			await director.battle_resolved(result)
			if _closed or epoch != _connection_epoch: return
		_battle_key = ""
	# The server's final snapshot already captures/discards the gate. Keep its
	# visible surface through the strike and result confirmation, then remove it.
	for slot in removed_slots:
		var node: ArenaCardNode = card_nodes[slot]
		card_nodes.erase(slot)
		node.set_field_surface(false)
		node.queue_free()
	var selected := int(data.get("selected_uid", -1))
	for uid in balls:
		var cs: CreatureState = view.creature(uid)
		var ball: CreatureBall = balls[uid]
		var old_slot := int(_rendered_slots.get(uid, -1))
		# An attacking creature intentionally has no occupied slot during combat.
		# Its presence comes from the authoritative battle participants.
		var combat: Dictionary = data.get("preview", {})
		var in_battle: bool = uid == int(combat.get("attacker_uid", -1)) or uid == int(combat.get("defender_uid", -1))
		ball.visible = cs.alive and (cs.slot >= 0 or uid == selected or in_battle)
		ball.set_process(ball.visible)
		if not ball.visible:
			ball.freeze_at(_start_pos(cs.owner))
		elif cs.slot >= 0 and cs.slot != old_slot:
			if uid != int(_last_flight.get("uid", -1)):
				ball.freeze_at(arena.slot_position(cs.slot) + Vector3(0,BALL_Y,0))
			ball.hold_landing_pose()
			ball.open_animated()
			ball.slot = cs.slot
		elif uid == selected and cs.slot < 0 and old_slot != -2:
			ball.freeze_at(_start_pos(cs.owner))
		_rendered_slots[uid] = cs.slot if cs.slot >= 0 else (-2 if uid == selected else -1)
		var idx := view.players[cs.owner].creature_uids.find(uid)
		if cs.alive: hud.revive_creature(0 if cs.owner == local_side else 1, idx)
		else: hud.kill_creature(0 if cs.owner == local_side else 1, idx)
	hud.set_names(_names[local_side] + " (вы)", _names[1-local_side])
	hud.set_status(view.turn, 0 if view.active_player == local_side else 1, view.alive_count(local_side), view.alive_count(1-local_side))
	hud.set_phase(view.phase)
	hud.set_captures(view.players[local_side].captured.size(), view.players[1-local_side].captured.size())
	setup_panel.set_hand(view.players[local_side].arena_hand)
	ability_panel.set_hand(view.players[local_side].ability_hand)
	var preview := Codec.decode_battle(data.get("preview", {}), view)
	if preview != null:
		var key := "%d:%d:%d" % [view.turn,preview.attacker_uid,preview.defender_uid]
		if _battle_key != key:
			_battle_key = key
			await director.battle_started(preview.slot,preview.attacker_uid,preview.defender_uid,preview.powers,preview.momentum)
			if _closed or epoch != _connection_epoch: return
		battle_hud.set_powers(preview.powers)
		battle_hud.set_chain(preview.plays, preview.passed, 0 if _owner_of(preview.attacker_uid) == view.active_player else 1, preview.cancelled_plays, preview.ability_counts, [MatchController.battle_ability_block_reason(preview, 0), MatchController.battle_ability_block_reason(preview, 1)])
	else:
		battle_hud.close()
		hud.set_battle_mode(false)
		if not bool(data.busy): cam.overview()
	if int(data.get("winner", -2)) != -2:
		_hide_input()
		_game_over = true
		var winner := int(data.winner)
		game_over_ui.show_result(-1 if winner < 0 else (0 if winner == local_side else 1), _reason_text(StringName(data.reason)), {"summary_only":true,"turns":view.turn,"alive":[view.alive_count(local_side),view.alive_count(1-local_side)],"captures":[view.players[local_side].captured.size(),view.players[1-local_side].captured.size()]})
	set_meta("online_presentation","ready")

func _prepare_online_match() -> void:
	team_menu._preview.release()
	if arena.location_id == ArenaLocations.CANYON:
		director.play_match_music()
	game_over_ui.set_restart_text("Реванш")
	_match_ready = true
	_game_over = false
	_index_creatures()
	var pool := GameLoading.i()
	for uid in _defs:
		var ball: CreatureBall
		if pool.ready_to_play:
			ball = pool.take_ball(_defs[uid].id, uid, _start_pos(_owners[uid]))
			assert(ball != null, "Resident catalog has no online actor")
			ball.reparent(world, false)
		else:
			# Only isolated graphical checks bypass Boot.
			ball = BALL_SCENE.instantiate()
			world.add_child(ball)
			ball.setup(_defs[uid], uid)
			ball.freeze_at(_start_pos(_owners[uid]))
		ball.freeze = true
		ball.collision_layer = 0
		ball.collision_mask = 0
		ball.hide()
		balls[uid] = ball
	var colors: Array = [[], []]
	var elements: Array = [[], []]
	for side in range(2):
		for uid in ctrl.state.players[side].creature_uids:
			var local_index := 0 if side == local_side else 1
			colors[local_index].append(VisualUtil.attr_color(_creature_def(uid).attribute))
			elements[local_index].append(_creature_def(uid).attribute)
	hud.setup_plates(colors[0], colors[1], elements)
	setup_panel.set_dock_visible(true)
	ability_panel.set_dock_visible(true)
	# Fighters use resident models; the remote player's default look is public presentation only.
	var saved := PlayerProfile.new()
	saved.load_from()
	for side in range(2):
		var profile: Dictionary = saved.value if side == local_side else PlayerProfile.npc_profile(2)
		var fighter := pool.take_fighter(profile) if pool.ready_to_play else null
		if fighter == null:
			fighter = VrmFighter.new()
			world.add_child(fighter)
			fighter.apply_profile(profile)
		else: fighter.reparent(world,false)
		fighter.position = Vector3(-2.3 if side == 0 else 2.3,0,(THROW_Z+1.4)*(1 if side == 0 else -1))
		fighter.rotation.y = PI if side == 0 else 0.0
		fighters.append(fighter)

func _play_flight(data: Dictionary) -> void:
	if _closed: return
	var epoch := _connection_epoch
	_hide_input()
	var uid := int(data.uid)
	var ball: CreatureBall = balls.get(uid)
	if ball == null: return
	director.flying = true
	_last_flight = data
	_flight_count += 1
	ball.close_up()
	ball.freeze_at(_start_pos(int(data.owner)))
	ball.show()
	ball._figure.hide()
	ball._show_closed()
	ball.set_process(false)
	hud.set_hint("Бросок: сервер рассчитал физику, воспроизводится общая траектория")
	SoundFx.i().play("ball_throw", -3.0)
	var samples: Array = data.samples
	var first_pose: Array = samples.front()
	var last_pose: Array = samples.back()
	# Replayed frozen bodies have no physical velocity on the client. Use the
	# transmitted motion direction so CameraRig follows the actual pose changes.
	cam.follow(ball,Vector3(float(last_pose[0])-float(first_pose[0]),0,float(last_pose[2])-float(first_pose[2])))
	var duration := float(data.duration)
	var elapsed := 0.0
	while elapsed < duration and is_inside_tree() and not _closed and epoch == _connection_epoch:
		var cursor := minf(elapsed / duration * (samples.size()-1), samples.size()-1)
		var a: Array = samples[int(cursor)]
		var b: Array = samples[mini(int(cursor)+1,samples.size()-1)]
		var blend := cursor - floorf(cursor)
		var pos := Vector3(float(a[0]),float(a[1]),float(a[2])).lerp(Vector3(float(b[0]),float(b[1]),float(b[2])),blend)
		var qa := Quaternion(float(a[3]),float(a[4]),float(a[5]),float(a[6]))
		var qb := Quaternion(float(b[3]),float(b[4]),float(b[5]),float(b[6]))
		ball.global_transform = Transform3D(Basis(qa.slerp(qb,blend)),pos)
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if _closed or epoch != _connection_epoch: return
	var final: Array = samples.back()
	ball.global_transform = Transform3D(Basis(Quaternion(float(final[3]),float(final[4]),float(final[5]),float(final[6]))),Vector3(float(final[0]),float(final[1]),float(final[2])))
	ball.hold_landing_pose()
	ball.set_process(true)
	director.flying = false
	if int(data.slot) >= 0:
		cam.reveal_orbit(ball.global_position - Vector3(0,BALL_Y,0),ball.figure_height(),Vector3.FORWARD,ball.figure_size())
		ball.open_animated()
		await _wait(1.9)
	else:
		hud.flash("Промах")
		await _wait(.3)

func _hide_input() -> void:
	setup_panel.hide_panel()
	ability_panel.hide_panel()
	ability_target_picker.hide()
	_ability_target_card = &""
	hud.hide_creatures()
	arena.set_highlight([])

func _show_input() -> void:
	if snapshot.is_empty() or _game_over or _input_pending or events.is_busy() or not client.verified: return
	_hide_input()
	if bool(snapshot.get("busy", false)):
		hud.set_hint("Сервер рассчитывает физический бросок…")
		return
	var view := ctrl.state
	if view.active_player != local_side:
		hud.set_hint("Ход соперника · " + _names[1-local_side])
		return
	var legal: Dictionary = snapshot.legal
	match view.phase:
		MatchController.Phase.SETUP:
			var cards: Array = []
			for cid in view.players[local_side].arena_hand: cards.append({"id":cid})
			arena.set_highlight(legal.setup_slots,true)
			setup_panel.begin(cards,legal.setup_slots,bool(legal.can_skip_gate),true)
			hud.set_hint("Выберите ворота слева → место на арене")
		MatchController.Phase.AWAIT_THROW:
			var entries: Array = []
			for uid in legal.creatures: entries.append({"uid":int(uid),"def":_creature_def(int(uid)),"note":""})
			hud.show_creatures(entries)
			hud.set_hint("Ваш бросок: выберите существо")
		MatchController.Phase.AWAIT_LANDING:
			var slots: Array = []
			for slot in range(6):
				if view.slots[slot].has_card: slots.append(slot)
			arena.set_highlight(slots,true)
			hud.set_hint("Выберите целевые ворота. Перед броском можно прикрепить способность справа.")
			_show_online_abilities("До броска", "pre_throw")
		MatchController.Phase.ABILITY_WINDOW: _show_online_abilities("Ваш ответ: способность или пас", "battle")
		MatchController.Phase.AFTER_LANDING: _show_online_abilities("После приземления: прикрепить карту?", "after_landing")

func _show_online_abilities(title: String, moment: String) -> void:
	var entries: Array = []
	for cid in snapshot.legal.abilities: entries.append({"id":StringName(cid)})
	ability_panel.show_options(entries,title,{"moment":StringName(moment),"can_open_gate":bool(snapshot.legal.can_reveal_gate),"used":3-int(snapshot.legal.get("abilities_left",3)),"pass_text":"Завершить ход" if moment == "after_landing" else "Пас"})

func _command(command: String, args: Dictionary = {}) -> void:
	if _input_pending or events.is_busy() or snapshot.is_empty() or _game_over: return
	_input_pending = true
	_hide_input()
	client.action(command,args)

func _on_slot_picked(slot: int) -> void:
	if snapshot.is_empty() or events.is_busy() or _input_pending: return
	if ctrl.state.phase == MatchController.Phase.SETUP: setup_panel.pick_slot(slot)
	elif ctrl.state.phase == MatchController.Phase.AWAIT_LANDING: _command("launch",{"slot":slot})

func _on_setup_placed(card_id: StringName, slot: int) -> void:
	_command("place_gate",{"card":card_id,"slot":slot})

func _on_setup_skipped() -> void: _command("skip_gate")
func _on_creature_chosen(uid: int) -> void:
	if not _gate_pick.is_empty():
		var pick := _gate_pick.duplicate()
		interaction.gate_pick.clear()
		_command("throw_with_gate",{"card":pick.card,"slot":pick.slot,"uid":uid})
	else: _command("select",{"uid":uid})
func _on_ability_chosen(card_id: StringName) -> void:
	var targets: Array = snapshot.get("legal", {}).get("ability_targets", {}).get(String(card_id), [])
	if not targets.is_empty():
		_ability_target_card = card_id
		ability_panel.hide_panel()
		ability_target_picker.show_targets(card_id, targets, ctrl.state)
		return
	_command("ability", {"card":card_id})

func _on_ability_target_chosen(target: Dictionary) -> void:
	var card_id := _ability_target_card
	_ability_target_card = &""
	_command("ability", {"card":card_id, "target":target})

func _on_ability_target_cancelled() -> void:
	_ability_target_card = &""
	_show_input()
func _on_gate_open_requested() -> void: _command("reveal_gate")
func _on_ability_passed() -> void: _command("pass")
func _on_setup_placed_throw(card_id: StringName, slot: int) -> void:
	_gate_pick = {"card":card_id,"slot":slot}
	setup_panel.hide_panel()
	var entries: Array = []
	for uid in ctrl.state.players[local_side].creature_uids:
		var cs := ctrl.state.creature(uid)
		if cs.alive and cs.slot < 0 and not cs.used: entries.append({"uid":uid,"def":_creature_def(uid),"note":""})
	hud.show_creatures(entries,"Кого бросить на новые ворота?",true)
func _on_gate_throw_cancelled() -> void:
	interaction.gate_pick.clear()
	_show_input()

func _on_restart() -> void:
	game_over_ui.set_restart_text("Ждём согласия соперника…")
	client.send({"t":"rematch"})

func _return_to_lobby() -> void:
	# Keep the arena resident, return only match actors before the next readiness cycle.
	if is_instance_valid(director.effects): director.effects.clear()
	SoundFx.i().cancel_match_sfx()
	if is_instance_valid(arena) and arena.location_id == ArenaLocations.CANYON:
		SoundFx.i().play_music(SoundFx.MUSIC_TEAM)
	team_menu._preview.release()
	interaction.gate_pick.clear()
	interaction.clear_request()
	_battle_uids.clear()
	_active_ball = null
	_input_pending = false
	director.flying = false
	game_over_ui.set_restart_text("Реванш")
	battle_hud.close()
	hud.set_battle_mode(false)
	game_over_ui._panel.hide()
	game_over_ui._dim.hide()
	_hide_input()
	for ball in balls.values():
		if GameLoading.i().ready_to_play: GameLoading.i().return_ball(ball)
		else: ball.queue_free()
	balls.clear()
	for fighter in fighters:
		if GameLoading.i().ready_to_play: GameLoading.i().return_fighter(fighter)
		else: fighter.queue_free()
	fighters.clear()
	for node in card_nodes.values(): node.queue_free()
	card_nodes.clear()
	_rendered_slots.clear()
	_last_battle_serial = 0
	_last_standoff_serial = 0
	_last_flight = {}
	_battle_key = ""
	_match_ready = false
	_game_over = false
	snapshot = {}
	hud.hide()
	_place_leave_button(false)
	setup_panel.set_dock_visible(false)
	ability_panel.set_dock_visible(false)
	_connection_panel.show()
	_status("Реванш принят. Можно изменить команду; затем оба нажмите «Готов».")

func _disconnected(reason: String) -> void:
	if _cleaning_match: return
	_cleaning_match = true
	client.close()
	_closed = true
	_connection_epoch += 1
	events._queue.clear()
	if battle_overlay._open: battle_overlay._close()
	_input_pending = false
	_game_over = true
	_hide_input()
	game_over_ui._panel.hide()
	game_over_ui._dim.hide()
	team_menu.hide()
	lobby = {}
	_connection_panel.show()
	_status(reason)
	# A running director action can still hold references to its actors. Close
	# its result overlay and drain that action before returning leases to storage.
	while events.is_busy():
		if battle_overlay._open: battle_overlay._close()
		await get_tree().process_frame
		if not is_inside_tree(): return
	_return_to_lobby()
	_game_over = true
	_cleaning_match = false
	_status(reason)

func _leave() -> void:
	client.send({"t":"leave"})
	client.close()
	SoundFx.i().cancel_match_sfx()
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _slot_tip(index: int, slot: SlotState, view: MatchState) -> Array:
	return _help_policy.slot_tip(index,slot,view)

func _creature_tip(uid: int, view: MatchState) -> Array:
	return _help_policy.creature_tip(uid,view)


func _place_leave_button(in_match: bool) -> void:
	if in_match:
		VisualUtil.place(_leave_button, 0.0, 0.0, 14.0, 97.0)
	else:
		VisualUtil.place(_leave_button, 1.0, 0.0, -16.0, 88.0)
