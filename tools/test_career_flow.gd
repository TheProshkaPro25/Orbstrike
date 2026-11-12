extends "res://tests/tournament_flow_tests.gd"
## Настоящий путь карьеры через Boot и один полный физический матч.
## Остальные встречи завершаются отдельно явно заданными результатами для проверки перехода кубка.

func _initialize() -> void:
	OUT = "res://build/checks/career-flow"
	if not OS.get_cmdline_user_args().is_empty(): OUT = OS.get_cmdline_user_args()[0]
	super._initialize()


func _run_flow() -> void:
	# check.py supplies an isolated user directory. Never delete a player's career.
	if not OS.get_environment("XDG_DATA_HOME").begins_with(ProjectSettings.globalize_path("res://build/checks/")):
		_abort("стенд требует изолированный XDG_DATA_HOME через tools/check.py")
		return
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.SAVE_PATH + suffix))
	change_scene_to_file("res://scenes/loading/boot.tscn")
	if not await _wait_for_scene("res://scenes/menu/main_menu.tscn",180.0):
		_abort("Boot → меню карьеры")
		return
	startup_counts = _preparation_counts()
	_menu_button("Карьера").pressed.emit()
	if not await _wait_for_scene("res://scenes/main.tscn",15.0):
		_abort("кнопка карьеры → Main")
		return
	main = current_scene
	await process_frame
	_check(main.career_panel.visible and not main.team_menu.visible,"карьера открывается отдельно от свободной команды")
	main.career_panel.create_requested.emit(0,1)
	await process_frame
	if main.career == null:
		_abort("создана и сохранена карьера")
		return
	_check(main.career.state.credits == 100,"начальные100кредитов")
	await _shot("01-career")
	var deck: DeckDef = main.career.starter_deck()
	var ids := Tournament.deck_ids(deck)
	main.career_panel.registration_requested.emit(_names(ids[0]),_names(ids[1]),_names(ids[2]),{})
	await process_frame
	if main.tournament == null:
		_abort("законная стартовая тройка → кубок")
		return
	_check(main.career.deck_error(ids[0],ids[1],ids[2]).is_empty(),"стартовые620G разрешены")
	if not await _reach_human(): return
	_fixture = main.tournament.next_match().duplicate(true)
	main.tournament_panel.primary_button.pressed.emit()
	if not await _wait_match_started("матч карьеры после интро"): return
	_check(main.ctrl != null,"стартовал матч карьеры")
	if main.ctrl == null:
		_abort("нет контроллера карьеры")
		return
	for uid in main.ctrl.state.players[0].creature_uids:
		var id: StringName = main.ctrl.state.creatures[uid].def_id
		_check(PowerCalc.base_power(main.ctrl.state,uid) == int(main.career.power_snapshot(0)[String(id)]),"физический матч получает снимокG")
		_check(main._creature_def(uid).base_power == PowerCalc.base_power(main.ctrl.state,uid),"UI показываетGснимка")
	for uid in main._prepared_balls:
		var actor: CreatureBall = main._prepared_balls[uid]
		var actor_id := actor.get_instance_id()
		var animator_id := actor._anim.get_instance_id()
		var basis_before := actor._visual.global_basis
		var cloth_before: Variant = actor._anim._cloth
		actor.set_presentation_definition(actor.def)
		_check(actor.get_instance_id() == actor_id and actor._anim.get_instance_id() == animator_id and actor._visual.global_basis.is_equal_approx(basis_before) and actor._anim._cloth == cloth_before,"сменаподписи сохраняетактор/аниматор/Basis/cloth")
		_check(actor.def.base_power == PowerCalc.base_power(main.ctrl.state,uid) and actor._label.text.contains(str(actor.def.base_power)),"подписьарендованноймодели используетGснимка")
	_check(_preparation_counts() == startup_counts and _actors_valid(),"карьера арендует теже6акторов безподготовки")
	bot = AIPlayer.new(0,1271,-1.0,1)
	_drive = true
	if not await _until(func() -> bool: return main._game_over,200.0):
		_abort("полный физический матч карьеры")
		return
	_drive = false
	await process_frame
	await process_frame
	_check(main.game_over_ui._restart_button.text == "К карьере","результат возвращает к карьере")
	var credits_before: int = main.career.state.credits
	var ledger_size: int = main.career.state.ledger.size()
	main._accept_tournament_result()
	_check(main.career.state.credits == credits_before and main.career.state.ledger.size() == ledger_size,"повторное принятие результата невыдаёт награду")
	var loaded := Career.load_file()
	_check(String(loaded.error).is_empty() and loaded.career.state.credits == credits_before,"результат и награда сохранены вместе")
	await _shot("02-career-result")
	var old_main: Node = main
	main.game_over_ui._restart_button.pressed.emit()
	main = null
	if not await _wait_for_scene("res://scenes/main.tscn",15.0,old_main):
		_abort("кнопка результата → карьера")
		return
	main = current_scene
	await process_frame
	_check(main.career_panel.visible and main.career.state.credits == credits_before,"возврат загружает карьеру безповторной награды")
	_check(GameLoading.i()._leased.is_empty(),"экранкарьеры вернул6сфер")
	var leased := GameLoading.i().take_ball(StringName(ids[0][0]),991,Vector3.ZERO)
	_check(leased != null and leased.def == CardDB.creature(StringName(ids[0][0])) and leased._label.text.contains(str(leased.def.base_power)),"послеrelease новаяобычнаяаренда восстанавливаеткаталожныйG")
	if leased != null: GameLoading.i().return_ball(leased)

	# Дальше узко проверяем интеграцию завершения кубка, не выдавая фикстуры за физические матчи.
	var guard := 0
	while not main.career.cup.completed() and guard < 20:
		var duel: Dictionary = main.career.cup.next_match()
		var code: Error = main.career.record_result(String(duel.id),int(duel.a),[3,0],"fixture",{"throws":3,"battles":1})
		_check(code == OK,"фикстура завершает оставшуюся встречу")
		if code != OK:
			_abort(main.career.last_error)
			return
		guard += 1
	_check(main.career.cup.completed(),"кубок завершён")
	main._show_career()
	await process_frame
	await _shot("03-career-shop")
	var purchasable := ""
	for id in CardDB.ability_ids() + CardDB.arena_ids():
		if not main.career.state.owned_cards.has(String(id)) and main.career.price(id) > 0 and main.career.price(id) <= int(main.career.state.credits):
			purchasable = String(id)
			break
	_check(not purchasable.is_empty(),"послекубка хватаетна новуюкарту")
	if not purchasable.is_empty():
		var before: int = main.career.state.credits
		var price: int = main.career.price(purchasable)
		_check(main.career.purchase(purchasable) == OK,"покупка карты межкубками")
		_check(main.career.state.credits == before-price and main.career.state.owned_cards.has(purchasable),"покупка списала ровно цену и дала владение")
	main.career_panel.advance_requested.emit()
	await process_frame
	_check(main.career.state.league == 1 and main.career.cup == null,"второйкубок открыт с новойрегистрацией")
	_check(_preparation_counts() == startup_counts,"весьпуть неготовил модели/арены/звук повторно")
	print("Career flow: %d checks, %d failures; one real physical match; remaining cup fixtures explicit" % [_checks,_failures])
	_write_report()
	_finish(1 if _failures else 0)


func _names(ids: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in ids: result.append(StringName(id))
	return result


func _shot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("Headless career flow: no rendered PNG " + filename)
		await process_frame
		return
	await super._shot(filename)
