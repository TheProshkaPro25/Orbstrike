extends "res://tools/autoplay.gd"
## Узкий настоящий путь турнира: Boot, регистрация, физический матч и продолжение.
## Игроком управляет прежний AI-driver, все броски проходят физику Main.

var OUT := "res://build/checks/tournament-flow"
var campaign_flow := false
var _checks := 0
var _failures := 0
var _drive := false
var _target_actions := 0
var _fixture: Dictionary
var _initial_snapshot: Dictionary
var _landed := 0
var _started_at := 0


func _initialize() -> void:
	_lock_fps()
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	_loading = true
	_started_at = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(OUT)
	call_deferred("_run_flow")


func _run_flow() -> void:
	change_scene_to_file("res://scenes/loading/boot.tscn")
	if not await _wait_for_scene("res://scenes/menu/main_menu.tscn", 180.0):
		_abort("Boot → главное меню")
		return
	_check(GameLoading.i().ready_to_play, "Boot завершил подготовку до меню")
	startup_counts = _preparation_counts()
	await _shot("01-menu")
	_menu_button("Новая кампания" if campaign_flow else "Новый турнир").pressed.emit()
	if not await _wait_for_scene("res://scenes/main.tscn", 15.0):
		_abort("меню → регистрация")
		return
	main = current_scene
	await process_frame
	_check(main._tournament_registration and main.team_menu.visible, "отдельная регистрация турнира")
	_check(main.team_menu._go_btn.text == "Зарегистрироваться", "турнирная кнопка регистрации")
	await _shot("02-registration")
	# Сначала проверяем отмену: TeamMenu прячет себя ещё до deck_chosen.
	main.team_menu.pick_random_and_start()
	await process_frame
	var confirm := _dialog()
	if confirm == null:
		_abort("подтверждение закрепления колоды не открылось")
		return
	_check(main.tournament == null, "до подтверждения турнир не создаётся")
	_check(confirm.dialog_text.contains("закрепятся"), "подтверждение предупреждает о закреплении колоды")
	confirm.canceled.emit()
	await process_frame
	_check(main.team_menu.visible and main._tournament_registration, "отмена возвращает в регистрацию")
	main.rng.seed = 20261103
	main.team_menu._go_btn.pressed.emit()
	await process_frame
	confirm = _dialog()
	if confirm == null:
		_abort("повторное подтверждение не открылось")
		return
	confirm.confirmed.emit()
	await process_frame
	await process_frame
	if main.tournament == null or not is_instance_valid(main.tournament_panel):
		_abort("подтверждение → турнирное табло")
		return
	_check(main.tournament_panel.visible and not main.team_menu.visible, "табло заменило регистрацию")
	_check(not String((Campaign.load_file() if campaign_flow else Tournament.load_file()).get("error", "")).length(), "регистрация сохранена и читается")
	await _shot("03-hub")
	root.size = Vector2i(960, 640)
	root.content_scale_size = root.size
	await process_frame
	await process_frame
	_check(main.tournament_panel._groups.columns == 1, "узкое табло перестраивает группы в одну колонку")
	_check(main.tournament_panel.primary_button.get_global_rect().end.y <= root.get_visible_rect().size.y + 1, "основная кнопка остаётся в узком окне")
	_check(main.tournament_panel.content.size.x <= main.tournament_panel.scroll.size.x + 1, "узкая панель не требует горизонтальной прокрутки")
	await _shot("04-hub-narrow")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	await process_frame
	if not await _reach_human():
		return
	_fixture = main.tournament.next_match().duplicate(true)
	main.tournament_panel.primary_button.pressed.emit()
	if not await _wait_match_started("первый матч после интро "): return
	if main.ctrl == null:
		_abort("табло → первый матч")
		return
	_initial_snapshot = main.ctrl.debug_snapshot()
	_check(main.ctrl.match_seed == int(_fixture.seed), "физический матч использует seed встречи")
	_check(main.ctrl.action_trace[0] == ["start", [main._tournament_first_side()]], "первый ход учитывает перестановку человека в сторону 0")
	_check(_preparation_counts() == startup_counts, "первый матч использует подготовленный каталог")
	_check(_actors_valid(), "шесть арендованных существ имеют правильные uid, коллайдеры и отключённый резерв")
	main.ctrl.creature_stood.connect(func(_uid, _slot): _landed += 1)
	main.ctrl.battle_started.connect(func(_slot, _attacker, _defender): _landed += 1)
	bot = AIPlayer.new(0, 1271, -1.0, int(main.tournament.state.difficulty))
	_drive = true
	if not await _until(func() -> bool: return _landed > 0, 90.0):
		_abort("перед прерыванием не было настоящего физического приземления")
		return
	_drive = false
	_check(main.ctrl.action_trace.size() > _initial_snapshot.actions.size(), "прерванный матч действительно был начат")
	main._tournament_exit.pressed.emit()
	await process_frame
	confirm = _dialog()
	if confirm == null:
		_abort("предупреждение выхода из начатой встречи")
		return
	confirm.confirmed.emit()
	main = null
	if not await _wait_for_scene("res://scenes/menu/main_menu.tscn", 15.0):
		_abort("выход из встречи → меню")
		return
	await process_frame
	_check(GameLoading.i()._leased.is_empty(), "выход вернул все сферы в каталог")
	_menu_button("Продолжить кампанию" if campaign_flow else "Продолжить турнир").pressed.emit()
	if not await _wait_for_scene("res://scenes/main.tscn", 15.0):
		_abort("продолжить турнир → табло")
		return
	main = current_scene
	await process_frame
	_check(main.tournament.next_match() == _fixture, "продолжение сохраняет участников, seed и первый ход той же встречи")
	_check(main.tournament.state.in_progress == _fixture.id, "незавершённая встреча помечена в сохранении")
	_check(main.tournament_panel._notice.visible, "табло объясняет повтор незавершённой встречи")
	main.tournament_panel.primary_button.pressed.emit()
	if not await _wait_match_started("повтор встречи после интро "): return
	_check(main.ctrl.match_seed == int(_initial_snapshot.seed), "повтор начинает тот же seed")
	_check(main.ctrl.debug_snapshot().decks == _initial_snapshot.decks, "повтор начинает те же колоды")
	_check(main.ctrl.action_trace[0] == _initial_snapshot.actions[0], "повтор сохраняет первый ход")
	_check(main.ctrl.state.alive_count(0) == 3 and main.ctrl.state.alive_count(1) == 3, "повтор создаёт свежий матч с шестью живыми существами")
	_check(main.ctrl.get_turn() == 1, "повтор идёт с начала, а не с места прерывания")
	_check(_preparation_counts() == startup_counts and _actors_valid(), "повтор арендует каталог без подготовки")
	bot = AIPlayer.new(0, 1271, -1.0, int(main.tournament.state.difficulty))
	match_frames = 0
	_drive = true
	if not await _until(func() -> bool: return main._game_over, 180.0):
		_abort("физический матч не завершился")
		return
	_drive = false
	await process_frame
	await process_frame
	_check(main.game_over_ui._restart_button.text == "К турниру", "результат предлагает вернуться к турниру")
	var played_before := _result_count(main.tournament.state)
	var accepted := _find_match(main.tournament.state, String(_fixture.id))
	_check(accepted.has("result"), "результат физического матча записан в турнир")
	var expected_winner: int = -1 if main.ctrl.winner < 0 else (0 if main.ctrl.winner == 0 else main._tournament_opponent())
	_check(int(accepted.result.winner) == expected_winner, "победитель преобразован из стороны матча в участника турнира")
	var expected_alive := [main.ctrl.state.alive_count(0), main.ctrl.state.alive_count(1)]
	if int(_fixture.a) != 0:
		expected_alive.reverse()
	_check(accepted.result.alive == expected_alive, "счёт живых преобразован в порядок a/b сетки")
	await _shot("05-result")
	var old_main := main
	main.game_over_ui._restart_button.pressed.emit()
	main = null
	if not await _wait_for_scene("res://scenes/main.tscn", 15.0, old_main):
		_abort("К турниру → новое табло")
		return
	main = current_scene
	await process_frame
	_check(main.tournament_panel.visible and _result_count(main.tournament.state) == played_before, "возврат не записывает результат второй раз")
	_check(GameLoading.i()._leased.is_empty(), "табло не удерживает аренду шести сфер")
	_check(_preparation_counts() == startup_counts, "возврат к табло не готовит модели/арены/звук")
	await _shot("06-hub-after-result")
	if not await _reach_human():
		return
	var second: Dictionary = main.tournament.next_match()
	_check(second.id != _fixture.id, "следующий матч отличается от завершённого")
	main.tournament_panel.primary_button.pressed.emit()
	if not await _wait_match_started("следующая встреча после интро "): return
	_check(main.ctrl != null and not main._game_over and main.ctrl.get_turn() == 1, "следующая встреча начинается свежим физическим матчем")
	_check(_preparation_counts() == startup_counts and _actors_valid(), "следующая встреча повторно использует каталог и правильные uid")
	print("Tournament flow: %d checks, %d failures; %.2fs; fixture %s human_side=%s" % [_checks, _failures, (Time.get_ticks_msec() - _started_at) / 1000.0, _fixture.id, "a" if int(_fixture.a) == 0 else "b"])
	_write_report()
	_finish(1 if _failures else 0)


## Production intentionally runs the7.2s intro before controller.start.
func _wait_match_started(label: String) -> bool:
	pending_launches.clear()
	main.ctrl.creature_selected.connect(func(player: int, uid: int, _recall: bool) -> void:
		throws[player] += 1
		pending_launches[uid] = true)
	main.ctrl.creature_returned.connect(func(uid, reason): _ret(uid,reason))
	main.ctrl.creature_stood.connect(func(uid, _slot): _land(uid,true))
	main.ctrl.battle_started.connect(func(_slot, attacker, _defender): battles += 1; _land(attacker,true))
	if not await _until(func() -> bool: return is_instance_valid(main) and main.ctrl != null and main.ctrl._started and not main._preparing,15.0):
		_abort(label)
		return false
	_check(main._lifecycle.input_allowed(),"coordinator permits play only after intro")
	return true


func _reach_human() -> bool:
	var fixture: Dictionary = main.tournament.next_match()
	if not fixture.is_empty() and int(fixture.a) != 0 and int(fixture.b) != 0:
		var before := _result_count(main.tournament.state)
		main.tournament_panel.primary_button.pressed.emit()
		if not await _until(func() -> bool: return not main.tournament_panel._busy, 45.0):
			_abort("расчёт встреч NPC не завершился")
			return false
		_check(_result_count(main.tournament.state) > before, "кнопка табло рассчитывает встречи NPC")
	fixture = main.tournament.next_match()
	if fixture.is_empty() or (int(fixture.a) != 0 and int(fixture.b) != 0):
		_abort("после расчёта NPC не дошли до следующего матча человека")
		return false
	_check(main.tournament_panel.primary_button.text == "Играть встречу", "табло предлагает сыграть встречу человека")
	return true


func _actors_valid() -> bool:
	var actors: Dictionary = main.balls.duplicate()
	actors.merge(main._prepared_balls)
	if actors.size() != 6:
		return false
	var instances: Array = []
	for uid in actors:
		var ball: CreatureBall = actors[uid]
		if instances.has(ball.get_instance_id()) or ball.uid != uid or ball._shape.disabled:
			return false
		instances.append(ball.get_instance_id())
		if main._prepared_balls.has(uid) and (ball.visible or ball.process_mode != Node.PROCESS_MODE_DISABLED):
			return false
	return true


func _dialog() -> ConfirmationDialog:
	for child in main.ui_layer.get_children():
		if child is ConfirmationDialog and not child.is_queued_for_deletion():
			return child
	return null


func _until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return false


func _result_count(state: Dictionary) -> int:
	var count := 0
	for match_record in state.matches:
		if match_record.has("result"):
			count += 1
	return count


func _find_match(state: Dictionary, id: String) -> Dictionary:
	for match_record in state.matches:
		if match_record.id == id:
			return match_record
	return {}


func _shot(filename: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	_check(image.save_png(OUT.path_join(filename + ".png")) == OK, "сохранён кадр " + filename)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + description)


func _abort(description: String) -> void:
	_check(false, description)
	_drive = false
	if is_instance_valid(main) and main.ctrl != null: main.ctrl.save_debug_trace(OUT.path_join("aborted-match.json"))
	_write_report()
	_finish(1)


func _write_report() -> void:
	var runtime: Dictionary = {}
	if is_instance_valid(main) and main.ctrl != null:
		runtime = {"phase":main.ctrl.get_phase(),"turn":main.ctrl.get_turn(),"ability_moment":String(main.ctrl.get_ability_moment()),"target_picker":main.ability_target_picker.visible,"pending":main._pending,"event_busy":main.events.is_busy(),"lifecycle":main._lifecycle.stage if is_instance_valid(main._lifecycle) else -1}
	var file := FileAccess.open(OUT.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks":_checks,"failures":_failures,"fixture":_fixture,"preparation_counts":startup_counts,"elapsed_seconds":(Time.get_ticks_msec()-_started_at)/1000.0,"target_actions":_target_actions,"throws":throws,"hits":hits,"misses":misses,"runtime":runtime},"  "))


func _process(_delta: float) -> bool:
	if not _drive or not is_instance_valid(main) or main.ctrl == null or main._game_over:
		return false
	match_frames += 1
	if main.hud._reading > 0:
		main.hud._skip_flag = true
	if main.battle_overlay._open:
		main.battle_overlay._close()
	var view: MatchState = main.ctrl.get_view(0)
	if choose_pending_target(main,bot):
		_target_actions += 1
		return false
	if main.setup_panel._panel.visible:
		var choice: Dictionary = bot.choose_setup(view, main.ctrl.legal_setup_slots(), main.ctrl.can_skip_gate())
		main.setup_panel.hide_panel()
		if choice.is_empty():
			main._on_setup_skipped()
		else:
			main._on_setup_placed(choice.card_id, int(choice.slot))
	elif main.hud._creature_panel.visible:
		var choice: Dictionary = bot.choose_throw(view)
		target = int(choice.target_slot)
		main._on_creature_chosen(int(choice.uid))
	elif main._active_ball != null and not main.director.flying and main.ctrl.get_active_player() == 0 and not main.events.is_busy():
		var slots: Array = main._gate_slots()
		if not slots.is_empty():
			main._on_slot_picked(target if slots.has(target) else int(slots[0]))
	elif main.ability_panel._panel.visible:
		var card: StringName = &""
		if main.ctrl.get_ability_moment() == &"battle":
			if main.ctrl.can_reveal_gate(0) and bot.should_open_gate(view, main.ctrl.get_battle_preview()):
				main._on_gate_open_requested()
				return false
			card = bot.choose_ability(view, main.ctrl.get_battle_preview(), main.ctrl.legal_abilities(0))
		elif main.ctrl.get_ability_moment() == &"after_landing":
			card = bot.choose_attach(view, main.ctrl.get_landed_uid(), main.ctrl.legal_abilities(0))
		else:
			return false
		if card == &"":
			main._on_ability_passed()
		else:
			main._on_ability_chosen(card)
	return false


func _menu_button(text: String) -> Button:
	for button in current_scene._buttons:
		if button.text == text: return button
	return null
