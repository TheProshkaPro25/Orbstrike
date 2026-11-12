extends Node
## Offline mode/domain/UI owner. It never receives Main or scene-private callbacks.
const MatchSpec := preload("res://scenes/modes/match_spec.gd")
const ModeResult := preload("res://scenes/modes/mode_result.gd")

signal match_requested(spec: MatchSpec)
signal restart_requested(entry_mode: String)
signal restart_rejected(message: String)
signal exit_requested
signal arena_selection_requested(index: int, save_choice: bool)
signal duel_menu_requested
signal modal_opening
signal focus_restore_requested

var campaign: Campaign
var career: Career
var tournament: Tournament
var fixture: Dictionary = {}
var registration := false
var campaign_registration := false
var player_deck: Array = []
var tournament_panel: TournamentPanel
var career_panel: CareerPanel
var exit_button: Button
var current_spec: MatchSpec
var leaving := false
var exit_confirm: ConfirmationDialog
var duel_button: Button

var _team: TeamMenu
var _hud: HudUI
var _interface: CanvasLayer
var _rng: RandomNumberGenerator
var _request_pending := false
var _match_in_progress := false
var _registration_back: Button
var _configured := false
var _dialogs: Array[Window] = []

func configure(team: TeamMenu, hud: HudUI, interface: CanvasLayer, random: RandomNumberGenerator, ordinary_exit: Button = null) -> void:
	assert(not _configured,"GameModes is configured once per scene")
	_configured = true
	_team = team
	_hud = hud
	_interface = interface
	_rng = random
	duel_button = ordinary_exit
	if is_instance_valid(duel_button): duel_button.pressed.connect(duel_menu_requested.emit)
	_team.deck_chosen.connect(submit_deck)
	_team.location_previewed.connect(func(index: int) -> void: arena_selection_requested.emit(index,true))
	_hud.battle_mode_changed.connect(place_exit)
	DeviceSettings.events().changed.connect(func(_style: int) -> void: place_exit(_hud._battle))

func mode_name() -> String:
	if career != null: return "career"
	if campaign != null or campaign_registration: return "campaign"
	if tournament != null or registration: return "tournament"
	return "duel"

func enter_requested_mode() -> void:
	var entry := TournamentSession.entry_mode
	TournamentSession.entry_mode = ""
	enter(entry)

func enter(entry: String) -> void:
	if entry == "career":
		enter_career()
		return
	campaign_registration = entry == "campaign_new"
	if entry in ["new","campaign_new"]:
		registration = true
		_configure_registration()
		return
	if entry not in ["continue","campaign_continue"]: return
	var loaded: Dictionary = Campaign.load_file() if entry == "campaign_continue" else Tournament.load_file()
	if not String(loaded.error).is_empty():
		_team.hide()
		show_error(String(loaded.error))
		return
	if entry == "campaign_continue":
		campaign = loaded.campaign
		tournament = campaign.cup
	else:
		tournament = loaded.tournament
	show_tournament()

func _configure_registration() -> void:
	_team._go_btn.text = "Зарегистрироваться"
	_team._go_btn.tooltip_text = "Команда, колода и сложность закрепятся на всю кампанию" if campaign_registration else "Команда, колода и сложность закрепятся на весь турнир"
	_team._arena_btn.disabled = true
	_team._arena_btn.text = "Арены по этапам"
	_team._arena_btn.tooltip_text = "Группы — Каньон; полуфиналы — Гавань; финал — Святилище"
	for label in _team.find_children("*","Label",true,false):
		if label.text == "Соперник": label.text = "Сложность кампании" if campaign_registration else "Сложность турнира"
		elif label.text.contains("Enter — в бой"): label.text = "1–3 шаги · ←/→ · Enter — регистрация · R — случайная"
	var titles := _team.find_children("*","Label",true,false)
	if not titles.is_empty(): titles[0].text = "Кампания · регистрация" if campaign_registration else "Турнир · регистрация"
	if not is_instance_valid(_registration_back):
		_registration_back = Button.new()
		_registration_back.text = "В меню"
		_registration_back.pressed.connect(request_exit)
		_team._graphics_button.get_parent().add_child(_registration_back)

func submit_deck(creatures: Array[StringName], gates: Array[StringName], abilities: Array[StringName]) -> void:
	if registration:
		register_tournament(creatures,gates,abilities)
		return
	if _request_pending or _match_in_progress: return
	player_deck = [creatures.duplicate(),gates.duplicate(),abilities.duplicate()]
	_request(prepare_match_spec())

func choose_decks() -> Array[DeckDef]:
	if career != null and not fixture.is_empty():
		return [career.participant_deck(0),career.participant_deck(opponent())]
	if tournament != null and not fixture.is_empty():
		return [tournament.participant_deck(0),tournament.participant_deck(opponent())]
	var mine: DeckDef
	if player_deck.size() == 3 and CardDB.deck_error(player_deck[0],player_deck[1],player_deck[2]).is_empty():
		mine = CardDB.build_deck(player_deck[0],player_deck[1],player_deck[2])
	if mine == null:
		push_warning("Недопустимая команда, берётся пресет")
		mine = CardDB.preset_deck(0)
	return [mine,CardDB.opponent_deck(_rng)]

func prepare_match_spec() -> MatchSpec:
	var spec := MatchSpec.new()
	spec.mode = mode_name()
	spec.decks = choose_decks()
	spec.fixture = fixture.duplicate(true)
	spec.seed = int(fixture.seed) if not fixture.is_empty() else int(_rng.randi())
	if not fixture.is_empty(): _rng.seed = spec.seed
	spec.first_side = first_side() if tournament != null else 0
	spec.difficulty = int(tournament.state.difficulty) if tournament != null else TeamMenu.difficulty
	if tournament != null:
		spec.ai_preferences = campaign.ai_preferences(opponent()) if campaign != null else Tournament.personality(opponent())
	var profile := PlayerProfile.new()
	profile.load_from()
	var rival := PlayerProfile.npc_profile(opponent() if tournament != null else 2)
	if tournament != null: rival.name = tournament.participant_name(opponent())
	spec.profiles = [profile.value.duplicate(true),rival]
	spec.names = [tournament.participant_name(0) if tournament != null else String(profile.value.name),tournament.participant_name(opponent()) if tournament != null else "Соперник · %s" % AIPlayer.difficulty_name(TeamMenu.difficulty)]
	spec.arena_id = arena_for_match()
	if career != null:
		spec.power_snapshots = [career.power_snapshot(0),career.power_snapshot(opponent())]
	return spec

func arena_for_match() -> int:
	if career != null: return [1,2,0][int(career.state.league)]
	if campaign != null: return [1,2,0][campaign.cup_index()]
	if tournament != null and not fixture.is_empty():
		return 1 if String(fixture.stage).begins_with("group") else (2 if fixture.stage == "semifinal" else 0)
	return ArenaLocations.current()

func opponent() -> int:
	if fixture.is_empty(): return 2
	return int(fixture.b) if int(fixture.a) == 0 else int(fixture.a)

func first_side() -> int:
	if fixture.is_empty(): return 0
	var participant: int = int(fixture.a) if int(fixture.first_player) == 0 else int(fixture.b)
	return 0 if participant == 0 else 1

func _request(spec: MatchSpec) -> void:
	_request_pending = true
	current_spec = spec
	match_requested.emit(spec)

## Main accepts only after atomic arena selection and lifecycle request_start succeed.
func match_accepted(spec: MatchSpec) -> void:
	if spec != current_spec or not _request_pending: return
	_request_pending = false
	_match_in_progress = true
	_team.hide()
	if is_instance_valid(tournament_panel): tournament_panel.hide()
	if is_instance_valid(career_panel): career_panel.hide()
	_hud.show()
	if tournament != null:
		_clear_exit()
		exit_button = make_exit_button()
		_interface.add_child(exit_button)
		place_exit(_hud._battle)

func match_rejected(message: String) -> void:
	_request_pending = false
	_match_in_progress = false
	_clear_exit()
	if tournament != null:
		show_tournament()
		tournament_panel.show_notice(message)
	else:
		_team.show()
		_team._preview.show_hint("Не удалось начать матч.\n" + message)

func start_failed(message: String) -> void:
	match_rejected(message)

func arena_selection_completed(index: int, accepted: bool, message: String = "") -> void:
	if not accepted:
		_team._arena_btn.text = "Арена: " + str(ArenaLocations.definition(index).name)
		_team._preview.show_hint(message)

func register_tournament(creatures: Array[StringName], gates: Array[StringName], abilities: Array[StringName]) -> void:
	_team.show()
	var error := CardDB.deck_error(creatures,gates,abilities)
	if not error.is_empty():
		_team._error.text = error
		return
	var save_path := Campaign.SAVE_PATH if campaign_registration else Tournament.SAVE_PATH
	var invalid_save := FileAccess.file_exists(save_path) and not String((Campaign.load_file() if campaign_registration else Tournament.load_file()).error).is_empty()
	var confirm := ConfirmationDialog.new()
	confirm.theme = UiTheme.get_theme()
	confirm.title = "Кампания · три кубка" if campaign_registration else "Регистрация на турнир"
	confirm.dialog_text = "8 участников · 2 группы · полуфиналы и финал.\nКоманда, 3 карты ворот, 3 способности и сложность «%s»\nзакрепятся до конца турнира. Арены выбираются этапом.\nНезавершённый матч повторяется с начала с тем же начальным раскладом." % AIPlayer.difficulty_name(TeamMenu.difficulty)
	if campaign_registration:
		confirm.dialog_text = "Три последовательных кубка: Каньон → Гавань → Стихии.\nТе же семь соперников; каждый кубок — группы и плей-офф.\nСледующий кубок открывается после завершения текущего, независимо от места.\nКоманда и сложность закрепятся на кампанию; соперники помнят только завершённые встречи с вами.\nСкрытого усиления характеристик и карт нет. Старый отдельный турнир сохранится."
	if invalid_save: confirm.dialog_text += "\nПрежнее сохранение не читается: оно останется отдельной резервной копией."
	elif FileAccess.file_exists(save_path): confirm.dialog_text += "\nПредыдущее активное сохранение будет заменено. История останется."
	confirm.ok_button_text = "Начать кампанию" if campaign_registration else "Начать турнир"
	confirm.cancel_button_text = "Назад"
	_interface.add_child(confirm)
	_dialogs.append(confirm)
	confirm.confirmed.connect(func() -> void:
		if invalid_save and (Campaign.archive_invalid() if campaign_registration else Tournament.archive_invalid()) != OK:
			_team._error.text = "Не удалось сохранить резервную копию прежнего турнира"
			confirm.queue_free()
			return
		var profile := PlayerProfile.new()
		profile.load_from()
		var seed_value := int(_rng.randi()) & 0x7fffffff
		if campaign_registration:
			campaign = Campaign.create(CardDB.build_deck(creatures,gates,abilities),TeamMenu.difficulty,seed_value,profile.value.name)
			tournament = campaign.cup if campaign != null else null
		else:
			tournament = Tournament.create(CardDB.build_deck(creatures,gates,abilities),TeamMenu.difficulty,seed_value,profile.value.name)
		if tournament == null: _team._error.text = "Не удалось сохранить: " + creation_error()
		else:
			registration = false
			show_tournament()
		confirm.queue_free())
	confirm.canceled.connect(confirm.queue_free)
	confirm.popup_centered()

func creation_error() -> String:
	return Campaign.creation_error if campaign_registration else Tournament.creation_error

func last_error() -> String:
	return career.last_error if career != null else (campaign.last_error if campaign != null else (tournament.last_error if tournament != null else ""))

func show_error(message: String) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_interface.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var label := VisualUtil.label(message,20)
	label.custom_minimum_size.x = 580
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var back := Button.new()
	back.text = "В главное меню"
	back.pressed.connect(request_exit)
	box.add_child(back)
	panel.reset_size()
	panel.position = (_interface.get_viewport().get_visible_rect().size-panel.size)*.5

func show_tournament() -> void:
	_team.hide()
	_hud.hide()
	if is_instance_valid(career_panel): career_panel.hide()
	if not is_instance_valid(tournament_panel):
		tournament_panel = TournamentPanel.new()
		_interface.add_child(tournament_panel)
		tournament_panel.play_requested.connect(play_tournament_match)
		tournament_panel.advance_requested.connect(advance_tournament)
		tournament_panel.exit_requested.connect(func() -> void:
			if career != null: show_career()
			else: request_exit())
	var history: Dictionary = {"entries":[]} if career != null else (Campaign.history() if campaign != null else Tournament.history())
	tournament_panel.display(tournament,history.get("entries",[]),campaign)
	if career != null:
		career_tournament_heading()
		UiTheme.apply_device_frame(tournament_panel,"ТУРНИР / КАРЬЕРА")
	if tournament != null and not String(tournament.state.get("in_progress","")).is_empty():
		tournament_panel.show_notice("Матч был прерван. Он начнётся заново с теми же участниками, первым ходом и начальным раскладом.")

func advance_tournament() -> void:
	if _request_pending or _match_in_progress or tournament == null: return
	if career != null and tournament.completed():
		show_career()
		return
	if campaign != null and campaign.can_advance():
		if campaign.advance_cup() != OK:
			tournament_panel.show_notice(campaign.last_error,true)
			return
		tournament = campaign.cup
		show_tournament()
		return
	tournament_panel.set_busy(true)
	while not tournament.completed():
		var next := tournament.next_match()
		if next.is_empty() or int(next.a) == 0 or int(next.b) == 0: break
		var simulated: Dictionary = career.simulate_next_npc() if career != null else (campaign.simulate_next_npc() if campaign != null else tournament.simulate_next_npc())
		if not String(simulated.error).is_empty():
			tournament_panel.display(tournament,[],campaign)
			career_tournament_heading()
			tournament_panel.show_notice(String(simulated.error),true)
			return
		await get_tree().process_frame
		if not is_inside_tree(): return
	var history: Dictionary = {"entries":[]} if career != null else (Campaign.history() if campaign != null else Tournament.history())
	tournament_panel.display(tournament,history.get("entries",[]),campaign)
	career_tournament_heading()

func career_tournament_heading() -> void:
	if career != null and is_instance_valid(tournament_panel):
		tournament_panel._title.text = "Карьера · " + career.cup_title()
		tournament_panel.exit_button.text = "К карьере"

func play_tournament_match() -> void:
	if _request_pending or _match_in_progress or tournament == null: return
	fixture = tournament.next_match()
	if fixture.is_empty() or (int(fixture.a) != 0 and int(fixture.b) != 0): return
	var code: Error = career.begin_match(String(fixture.id)) if career != null else (campaign.begin_match(String(fixture.id)) if campaign != null else tournament.begin_match(String(fixture.id)))
	if code != OK:
		tournament_panel.show_notice("Не удалось сохранить начало матча. " + last_error())
		return
	_request(prepare_match_spec())

func make_exit_button() -> Button:
	var button := Button.new()
	button.theme = UiTheme.get_theme()
	button.custom_minimum_size = Vector2(0,36)
	button.text = "Выйти из турнира"
	button.tooltip_text = "Этот незавершённый матч при продолжении начнётся заново"
	button.pressed.connect(func() -> void:
		var confirm := ConfirmationDialog.new()
		confirm.theme = UiTheme.get_theme()
		confirm.title = "Выход из турнира"
		confirm.cancel_button_text = "Назад"
		confirm.dialog_text = "Выйти в меню? Незавершённый матч начнётся заново\nс теми же участниками, первым ходом и начальным раскладом."
		confirm.ok_button_text = "Выйти"
		_interface.add_child(confirm)
		_dialogs.append(confirm)
		confirm.confirmed.connect(request_exit)
		confirm.canceled.connect(confirm.queue_free)
		confirm.popup_centered())
	place_exit(_hud._battle,button)
	return button

func place_exit(battle: bool, target: Button = null) -> void:
	var buttons: Array = [target] if target != null else [duel_button,exit_button]
	for button: Button in buttons:
		if not is_instance_valid(button): continue
		if DeviceSettings.is_device():
			VisualUtil.place(button, 0.0, 0.0, 14.0, 97.0)
		elif battle:
			# Accepted shared HUD toolbar slot, clear of the battle phase and panels.
			VisualUtil.place(button,0.5,0.0,0.0,4.0)
		else:
			VisualUtil.place(button,1.0,0.0,-16.0,164.0)

func _clear_exit() -> void:
	if is_instance_valid(exit_button): exit_button.queue_free()
	exit_button = null

func accept_result(controller: MatchController, stats: Dictionary) -> ModeResult:
	if tournament == null or fixture.is_empty() or controller == null or controller.get_phase() != MatchController.Phase.GAME_OVER:
		return ModeResult.new(ERR_UNAVAILABLE,"Завершённый результат матча недоступен.")
	if String(tournament.next_match().get("id","")) != String(fixture.id): return ModeResult.new()
	var winner := -1 if controller.winner < 0 else (0 if controller.winner == 0 else opponent())
	var alive := [controller.state.alive_count(0),controller.state.alive_count(1)]
	if int(fixture.a) != 0: alive.reverse()
	var code: Error
	if career != null:
		var human_throws := 0
		for action in controller.action_trace:
			if action[0] in ["select_creature","throw_with_gate"] and not action[1].is_empty() and int(action[1][0]) == 0: human_throws += 1
		code = career.record_result(String(fixture.id),winner,alive,String(controller.game_over_reason),{"throws":human_throws,"battles":stats.get("battles",[]).size()})
	elif campaign != null:
		code = campaign.record_result(String(fixture.id),winner,alive,String(controller.game_over_reason),Campaign.observations_from_actions(controller.action_trace,0))
	else:
		code = tournament.record_result(String(fixture.id),winner,alive,String(controller.game_over_reason))
	return ModeResult.new(code,last_error() if code != OK else "")

func request_restart(controller: MatchController, stats: Dictionary, failed: bool = false) -> ModeResult:
	if tournament != null and not failed:
		var accepted := accept_result(controller,stats)
		if not accepted.is_ok():
			restart_rejected.emit("Не удалось сохранить результат. Повторите «К турниру». " + accepted.message)
			return accepted
	var entry := "career" if career != null else ("campaign_continue" if campaign != null else ("continue" if tournament != null else ""))
	TournamentSession.entry_mode = entry
	restart_requested.emit(entry)
	return ModeResult.new()

func result_suffix(controller: MatchController, stats: Dictionary) -> String:
	if tournament == null: return ""
	if not accept_result(controller,stats).is_ok(): return "\nНе удалось сохранить результат. «К турниру» повторит сохранение."
	return "\nРезультат турнира сохранён." + reward_text()

func restart_label() -> String:
	return "К карьере" if career != null else ("К турниру" if tournament != null else "Ещё раз")

func reward_text() -> String:
	if career == null or career.last_reward.is_empty(): return ""
	var reward: Dictionary = career.last_reward
	return "\nКарьера: +%d кредитов, +%d XP существам команды. Новые уровни — со следующего кубка." % [int(reward.get("credits",0)),int(reward.get("xp",0))]

func request_exit() -> void:
	if leaving: return
	leaving = true
	if is_instance_valid(duel_button): duel_button.disabled = true
	exit_requested.emit()

func request_duel_menu(controller: MatchController, finished: bool) -> void:
	if leaving or tournament != null or controller == null: return
	modal_opening.emit()
	if finished:
		leave_duel()
		return
	if is_instance_valid(exit_confirm):
		exit_confirm.popup_centered()
		return
	exit_confirm = ConfirmationDialog.new()
	exit_confirm.theme = UiTheme.get_theme()
	exit_confirm.title = "Вернуться в главное меню?"
	exit_confirm.dialog_text = "Текущая дуэль завершится. Можно будет начать новую."
	exit_confirm.ok_button_text = "В меню"
	exit_confirm.cancel_button_text = "Продолжить дуэль"
	exit_confirm.confirmed.connect(leave_duel)
	exit_confirm.canceled.connect(focus_restore_requested.emit)
	_interface.add_child(exit_confirm)
	exit_confirm.popup_centered()

func leave_duel() -> void:
	if tournament != null: return
	request_exit()

func modal_open() -> bool:
	if is_instance_valid(exit_confirm) and exit_confirm.visible: return true
	for dialog in _dialogs:
		if is_instance_valid(dialog) and dialog.visible: return true
	return false

func focus_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for button in [duel_button,exit_button]:
		if is_instance_valid(button): controls.append(button)
	return controls

func enter_career() -> void:
	_team.hide()
	_hud.hide()
	var loaded := Career.load_file()
	if not String(loaded.get("error","")).is_empty() and not bool(loaded.get("missing",false)):
		show_error("Карьера: " + String(loaded.error) + "\nИсходное сохранение оставлено без изменений.")
		return
	career = loaded.get("career")
	tournament = career.cup if career != null else null
	show_career()

func show_career(notice: String = "") -> void:
	_team.hide()
	_hud.hide()
	if is_instance_valid(tournament_panel): tournament_panel.hide()
	if not is_instance_valid(career_panel):
		career_panel = CareerPanel.new()
		_interface.add_child(career_panel)
		career_panel.create_requested.connect(create_career)
		career_panel.registration_requested.connect(register_career)
		career_panel.continue_requested.connect(func() -> void:
			if career == null or career.cup == null: return
			tournament = career.cup
			career_panel.hide()
			show_tournament())
		career_panel.advance_requested.connect(func() -> void:
			if career.advance_cup() != OK:
				career_panel.show_error(career.last_error)
				return
			tournament = career.cup
			show_career("Новый кубок открыт. Можно изменить команду и колоду."))
		career_panel.replay_requested.connect(func() -> void:
			if career.replay_cup() != OK:
				career_panel.show_error(career.last_error)
				return
			tournament = career.cup
			show_career("Повторный кубок. Награды за знакомых соперников уменьшены."))
		career_panel.exit_requested.connect(request_exit)
	career_panel.display(career,notice)

func create_career(element: int, difficulty: int) -> void:
	var profile := PlayerProfile.new()
	profile.load_from()
	career = Career.create(GameData.ATTR_KEYS[clampi(element,0,5)],difficulty,int(_rng.randi()) & 0x7fffffff,String(profile.value.name))
	if career == null:
		career_panel.show_error(Career.creation_error)
		return
	tournament = null
	show_career("Стартовая команда и шесть карт получены. Выберите «Начать кубок». ")

func register_career(creatures: Array[StringName], gates: Array[StringName], abilities: Array[StringName], levels: Dictionary) -> void:
	if career == null: return
	if career.start_cup(CardDB.build_deck(creatures,gates,abilities),levels) != OK:
		career_panel.show_error(career.last_error)
		return
	tournament = career.cup
	career_panel.hide()
	show_tournament()
