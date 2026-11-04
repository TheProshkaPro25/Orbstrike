extends "res://tests/card_balance_scenarios.gd"
## Послебоевое спасение: решения ИИ проверяются на настоящем контроллере,
## включая проигранный бой, копирование, отмену и обе роли/стороны.

func rescue_board(player: int, defender: bool, copy: bool = false) -> MatchController:
	var own := deck(3 if copy else 2)
	own.abilities[0] = CardDB.card(&"ability_stone_copy" if copy else &"ability_light_revive")
	var foe := deck(2 if copy else 0)
	var ctrl := MatchController.new(own if player == 0 else foe, foe if player == 0 else own, 11203)
	ctrl.landing_window = true
	ctrl._draw_pools = [[[], []], [[], []]]
	ctrl.start()
	var own_uid: int = player * 3 + 1
	var foe_uid: int = (1 - player) * 3
	ctrl.state.players[player].ability_hand.assign([own.abilities[0].id])
	ctrl.state.players[1 - player].ability_hand.clear()
	if copy: ctrl.state.players[1 - player].ability_hand.assign([&"ability_light_revive"])
	# Открытое Поле соперника делает +30/+50 недостаточным для победы.
	begin(ctrl, &"arena_field_light" if copy else &"arena_field_fire", foe_uid if defender else own_uid, own_uid if defender else foe_uid, 1 - player)
	ctrl.state.slots[1].revealed = true
	if copy:
		if not defender: check(ctrl.pass_ability(player) == OK, "Копия ждёт действующую карту соперника")
		play(ctrl, 1 - player, &"ability_light_revive")
	elif defender:
		check(ctrl.pass_ability(1 - player) == OK, "первый ответ атакующего пропущен")
	return ctrl

func last_rescue() -> void:
	for player in [0, 1]:
		for defender in [false, true]:
			for difficulty in [AIPlayer.Difficulty.NORMAL, AIPlayer.Difficulty.HARD]:
				var ctrl := rescue_board(player, defender)
				for uid in ctrl.state.players[player].creature_uids:
					if uid != player * 3 + 1: ctrl.state.creatures[uid].alive = false
				var ai := AIPlayer.new(player, 111, -1.0, difficulty)
				var before := ctrl.get_battle_preview()
				check(before.loser_uid == player * 3 + 1, "последний проигрывает до спасения")
				var after := ai._with_card(ctrl.get_view(player), before, &"ability_light_revive", 1 if defender else 0)
				check(after.loser_uid == before.loser_uid and after.revive[1 if defender else 0], "Возрождение не выигрывает бой, но спасает после него")
				var chosen := ai.choose_ability(ctrl.get_view(player), before, ctrl.legal_abilities(player))
				check(chosen == &"ability_light_revive", "ИИ спасает последнего, даже если +30 не меняет проигрыш")
				if chosen != &"": play(ctrl, player, chosen)
				finish(ctrl)
				check(ctrl.state.alive_count(player) == 1 and ctrl.get_phase() != MatchController.Phase.GAME_OVER, "после поражения остаётся одно живое существо")
				check(ctrl.state.players[player].ability_cooldown.get(&"ability_light_revive", 0) == 2, "спасение по-прежнему оплачено двумя боями отдыха")
				observations.append({"case": "last_rescue", "player": player, "defender": defender, "difficulty": difficulty, "before": before.powers, "with_revive": after.powers, "chosen": String(chosen), "alive_after": ctrl.state.alive_count(player)})

func copied_rescue() -> void:
	for player in [0, 1]:
		for defender in [false, true]:
			var ctrl := rescue_board(player, defender, true)
			for uid in ctrl.state.players[player].creature_uids:
				if uid != player * 3 + 1: ctrl.state.creatures[uid].alive = false
			var ai := AIPlayer.new(player, 112, -1.0, AIPlayer.Difficulty.HARD)
			var before := ctrl.get_battle_preview()
			var after := ai._with_card(ctrl.get_view(player), before, &"ability_stone_copy", 1 if defender else 0)
			check(after.revive[1 if defender else 0] and after.loser_uid == player * 3 + 1, "Копия повторяет спасение без победы по силе")
			check(ai.choose_ability(ctrl.get_view(player), before, ctrl.legal_abilities(player)) == &"ability_stone_copy", "Мастер замечает спасение Копией")
			play(ctrl, player, &"ability_stone_copy")
			finish(ctrl)
			check(ctrl.state.alive_count(player) == 1, "Копия спасла последнюю команду")
			check(ctrl.state.players[player].ability_cooldown.get(&"ability_stone_copy", 0) == 2, "Копия сохраняет полную цену отдыха")

func revival_limits() -> void:
	for difficulty in [AIPlayer.Difficulty.NORMAL, AIPlayer.Difficulty.HARD]:
		var ctrl := rescue_board(0, false)
		var ai := AIPlayer.new(0, 113, -1.0, difficulty)
		# Открытое Поле Света обеспечивает победу уже без карты, противник не ответит.
		ctrl.state.slots[1].card_id = &"arena_field_light"
		# Synthetic headroom keeps this a safe-win revival case with the accepted −100 G price.
		ctrl.state.creatures[1].marks.append({"delta": 100, "src": &"fixture_margin"})
		var pre := ctrl.get_battle_preview()
		check(pre.winner_uid == 1, "контрольная победа без спасения")
		check(ai._with_card(ctrl.get_view(0), pre, &"ability_light_revive", 0).winner_uid == 1, "Возрождение с ценой не уступает контрольную победу")
		check(ai.choose_ability(ctrl.get_view(0), pre, ctrl.legal_abilities(0)) == &"", "Возрождение не тратится без выбывших при победе")
		ctrl.state.creatures[0].alive = false
		pre = ctrl.get_battle_preview()
		check(ai.choose_ability(ctrl.get_view(0), pre, ctrl.legal_abilities(0)) == &"ability_light_revive", "при надёжной победе ИИ возвращает выбывшего союзника")
		for uid in ctrl.state.players[1].creature_uids:
			if uid != 3: ctrl.state.creatures[uid].alive = false
		check(ai.choose_ability(ctrl.get_view(0), ctrl.get_battle_preview(), ctrl.legal_abilities(0)) == &"", "при уже выигранном матче Возрождение сохраняется")
		# Mute подавляет спасение, даже если карта была прикреплена/сыграна раньше.
		ctrl = rescue_board(0, false)
		ctrl.state.slots[1].card_id = &"arena_mute"
		pre = ctrl.get_battle_preview()
		check(pre.silenced[0], "Глухие врата запрещают спасение")
		check(ai.choose_ability(ctrl.get_view(0), pre, ctrl.legal_abilities(0)) == &"", "ИИ не пытается спасаться подавленной картой")
		# Уже сыгранное спасение не дублируется ради ещё одного +30.
		ctrl = rescue_board(0, false)
		play(ctrl, 0, &"ability_light_revive")
		var view := ctrl.get_view(0)
		view.players[0].ability_hand.assign([&"ability_light_revive"])
		check(ai.choose_ability(view, ctrl.get_battle_preview(), [&"ability_light_revive"]) == &"", "один действующий revive не считается двумя воскрешениями")

func hidden_information() -> void:
	var ctrl := rescue_board(0, false)
	for uid in [0, 2]: ctrl.state.creatures[uid].alive = false
	var ai := AIPlayer.new(0, 114, -1.0, AIPlayer.Difficulty.HARD)
	ctrl.state.players[1].ability_hand.assign([&"ability_fire_drain"])
	var pre := ctrl.get_battle_preview()
	var first := ai.choose_ability(ctrl.get_view(0), pre, ctrl.legal_abilities(0))
	ctrl.state.players[1].ability_hand.assign([&"ability_fire_counter"])
	var view := ctrl.get_view(0)
	var before := JSON.stringify(OnlineStateCodec.encode_view(ctrl.state))
	var view_before := JSON.stringify(OnlineStateCodec.encode_view(view))
	check(first == &"ability_light_revive" and ai.choose_ability(view, pre, ctrl.legal_abilities(0)) == first, "смена скрытого ID при том же размере руки не меняет спасение")
	check(ctrl.get_view(0).players[1].ability_hand == [&""], "прогноз получает только закрытый размер руки")
	check(before == JSON.stringify(OnlineStateCodec.encode_view(ctrl.state)) and view_before == JSON.stringify(OnlineStateCodec.encode_view(view)), "прогноз не меняет настоящий матч и полученный вид")

func final_resolution_edges() -> void:
	for difficulty in [AIPlayer.Difficulty.NORMAL, AIPlayer.Difficulty.HARD]:
		var ai := AIPlayer.new(0, 115, -1.0, difficulty)
		var ctrl := rescue_board(0, false)
		for uid in [0, 2, 4, 5]: ctrl.state.creatures[uid].alive = false
		ctrl.state.slots[1].card_id = &"arena_clash"
		check(ctrl.get_battle_preview().both_lose, "Обоюдный удар выводит обоих последних")
		check(ai.choose_ability(ctrl.get_view(0), ctrl.get_battle_preview(), ctrl.legal_abilities(0)) == &"ability_light_revive", "ИИ спасается от обоюдного поражения последних")
		play(ctrl, 0, &"ability_light_revive")
		finish(ctrl)
		check(ctrl.winner == 0 and ctrl.state.alive_count(0) == 1 and ctrl.state.alive_count(1) == 0, "послебоевое спасение превращает обоюдную гибель в победу матча")
		ctrl = rescue_board(0, false)
		for uid in [0, 2]: ctrl.state.creatures[uid].alive = false
		ctrl.state.players[1].ability_hand.assign([&"ability_fire_counter"])
		ctrl.state.players[0].ability_hand.append(&"ability_light_glint")
		play(ctrl, 0, &"ability_light_revive")
		play(ctrl, 1, &"ability_fire_counter")
		var pre := ctrl.get_battle_preview()
		check(not pre.revive[0] and ai._alive_after(ctrl.get_view(0), pre, 0) == 0, "настоящая ответная отмена убирает прогноз спасения")
		finish(ctrl)
		check(ctrl.state.alive_count(0) == 0 and ctrl.winner == 1, "подавленное спасение не предотвращает проигрыш матча")

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	last_rescue()
	copied_rescue()
	revival_limits()
	hidden_information()
	final_resolution_edges()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		check(file != null, "отчёт доступен для записи")
		if file != null:
			file.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "observations": observations, "limits": "Сценарные позиции с MatchController, не winrate/физические матчи. NORMAL/HARD, две стороны и две роли; без чтения скрытых ID."}, "\t") + "\n")
			file.close()
	print("AI outcomes: ", assertions, " assertions, ", failures, " failures")
	quit(1 if failures else 0)
