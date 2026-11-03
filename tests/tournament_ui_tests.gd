extends SceneTree
## Изолированные новые экраны: результаты задаются ядру, физических матчей здесь нет.
const OUT := "res://build/checks/tournament-ui"
var panel: TournamentPanel
var _checks := 0
var _failures := 0
var _advances := 0
var _plays := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(OUT)
	call_deferred("_run")


func _run() -> void:
	CardDB.load_all()
	var menu: MainMenu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	var appearance_deadline := Time.get_ticks_msec() + 5000
	while (menu._buttons[-1].modulate.a <= .99 or menu._fade.color.a >= .01) and Time.get_ticks_msec() < appearance_deadline:
		await process_frame
	var button_labels: Array = menu._buttons.map(func(button: Button) -> String: return button.text)
	_check(button_labels.has("Дуэль") and button_labels.has("Новый турнир") and button_labels.has("Продолжить турнир"), "меню содержит дуэль, новый и продолжаемый турнир")
	_check(menu._buttons[-1].modulate.a > .99 and menu._fade.color.a < .01, "снимок меню после завершённого появления")
	for button in menu._buttons:
		_check(root.get_visible_rect().encloses(button.get_global_rect()), "кнопка меню в пределах окна: " + button.text)
	await _shot("01-menu")
	menu.queue_free()
	await process_frame
	await process_frame
	panel = TournamentPanel.new()
	root.add_child(panel)
	panel.play_requested.connect(func() -> void: _plays += 1)
	panel.advance_requested.connect(func() -> void: _advances += 1)
	var eliminated := _group_stage(false)
	_check(eliminated.player_eliminated(), "подготовлено исключение из плей-офф после трёх поражений")
	panel.display(eliminated)
	_check(panel.primary_button.text == "Узнать чемпиона", "выбывшему игроку предложен досчёт турнира")
	panel.primary_button.pressed.emit()
	_check(_advances == 1 and _plays == 0, "выбывший игрок вызывает advance, а не физический матч")
	await _shot("02-eliminated")
	await _scroll_to("Плей-офф")
	await _shot("03-bracket-styles")
	await _scroll_to("Результаты встреч")
	await _shot("04-results")
	panel.show_notice("Тест ошибки сохранения: результат пока не записан.", true)
	_check(panel._notice.visible and panel._notice.text.contains("ошибки"), "ошибка сохранения видна в закреплённом статусе")
	panel.set_busy(true)
	_check(panel.primary_button.disabled and panel.exit_button.disabled, "во время досчёта кнопки отключены")
	panel.primary_button.pressed.emit()
	_check(_advances == 1, "повторное действие блокируется при досчёте")
	panel.set_busy(false)
	_complete(eliminated)
	panel.display(eliminated, [eliminated._history_entry()])
	panel.scroll.scroll_vertical = 0
	_check(eliminated.completed() and eliminated.champion() != 0, "подготовлен завершённый турнир после вылета")
	_check(not panel.primary_button.visible and not panel._warning.visible, "после финала остаётся выход, предупреждение повтора скрыто")
	await _shot("05-champion")
	await _scroll_to("История турниров")
	await _shot("06-history")
	var victory := _group_stage(true)
	_complete(victory)
	panel.display(victory, [eliminated._history_entry(), victory._history_entry()])
	panel.scroll.scroll_vertical = 0
	_check(victory.champion() == 0 and _has_text("ВЫ — ЧЕМПИОН!"), "собственная победа получает титул чемпиона")
	await _shot("07-player-champion")
	var actor_counts := [GameLoading.i().actor_build_count, GameLoading.i().arena_build_count, GameLoading.i().fighter_build_count]
	_check(actor_counts == [0, 0, 0], "изолированная UI проверка не строит существ, арены и бойцов")
	panel.queue_free()
	if is_instance_valid(GameLoading._inst):
		GameLoading._inst.queue_free()
	if is_instance_valid(SoundFx._inst):
		SoundFx._inst.queue_free()
	await process_frame
	await process_frame
	print("Tournament UI: %d checks, %d failures (scripted core results, no physical matches)" % [_checks, _failures])
	quit(1 if _failures else 0)


func _group_stage(human_wins: bool) -> Tournament:
	var cup := Tournament.create(CardDB.preset_deck(0), AIPlayer.Difficulty.NORMAL, 261103 if human_wins else 261104, "Участник проверки", "")
	while String(cup.next_match().get("stage", "")).begins_with("group_"):
		var match_record: Dictionary = cup.next_match()
		var human: bool = int(match_record.a) == 0 or int(match_record.b) == 0
		var winner: int = int(match_record.a)
		if human:
			winner = 0 if human_wins else (int(match_record.b) if int(match_record.a) == 0 else int(match_record.a))
		_check(cup.record_result(String(match_record.id), winner, [2, 0] if winner == int(match_record.a) else [0, 2], "ui_fixture") == OK, "подготовлен групповой результат " + String(match_record.id))
	return cup


func _complete(cup: Tournament) -> void:
	while not cup.completed():
		var match_record: Dictionary = cup.next_match()
		var winner: int = 0 if int(match_record.a) == 0 or int(match_record.b) == 0 else int(match_record.a)
		_check(cup.record_result(String(match_record.id), winner, [2, 0] if winner == int(match_record.a) else [0, 2], "ui_fixture") == OK, "подготовлен результат плей-офф " + String(match_record.id))


func _has_text(text: String) -> bool:
	for label in panel.find_children("*", "Label", true, false):
		if label.text == text:
			return true
	return false


func _scroll_to(text: String) -> void:
	await process_frame
	await process_frame
	for label in panel.content.find_children("*", "Label", true, false):
		if label.text == text:
			panel.scroll.scroll_vertical += int(label.global_position.y - panel.scroll.global_position.y)
			break
	await process_frame
	await process_frame


func _shot(filename: String) -> void:
	await process_frame
	await process_frame
	_check(root.get_texture().get_image().save_png(OUT.path_join(filename + ".png")) == OK, "сохранён кадр " + filename)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + description)
