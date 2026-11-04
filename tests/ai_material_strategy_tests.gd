extends "res://tests/ai_interruption_strategy_tests.gd"
## Послебоевое число живых важнее одного флага победы.

func counter_revive(mode: String, control: bool = false) -> void:
	for player in 2:
		for attacks in [false, true]:
			var ctrl := board(player, Attr.A.FIRE, Attr.A.LIGHT, attacks)
			var uid := player * 3
			var foe := (1 - player) * 3 + (1 if mode == "ally" else 0)
			if mode == "ally": ctrl.state.creatures[(1 - player) * 3].alive = false
			elif mode == "last":
				for other in ctrl.state.players[1 - player].creature_uids:
					ctrl.state.creatures[other].alive = other == foe
			var before_alive := ctrl.state.alive_count(1 - player)
			ctrl.state.slots[0].card_id = &"arena_funnel"
			ctrl.state.slots[0].card_owner = player
			ctrl.state.slots[0].occupant_uid = foe if attacks else uid
			ctrl.state.creatures[(1 - player) * 3].slot = -1
			ctrl.state.creatures[foe if attacks else uid].slot = 0
			ctrl.state.players[player].ability_hand.assign([&"ability_fire_counter"])
			ctrl.state.players[1 - player].ability_hand.assign([&"ability_light_revive"])
			ctrl._start_battle(uid if attacks else foe, foe if attacks else uid, 0)
			if ctrl.get_active_player() == player: check(ctrl.pass_ability(player) == OK, "ответ Возрождения достигнут")
			check(ctrl.play_ability(1 - player, &"ability_light_revive") == OK, "противник реально сыграл Возрождение")
			var pre := ctrl.get_battle_preview()
			var side := 0 if attacks else 1
			check(pre.winner_uid == uid and pre.revive[1 - side], "силовая победа оставляет противнику воскрешение")
			check(ctrl.legal_abilities(player).has(&"ability_fire_counter"), "отмена Возрождения законна")
			var ai := AIPlayer.new(player, 99107, -1.0, AIPlayer.Difficulty.HARD)
			var view := ctrl.get_view(player)
			check(ai._alive_after(view, pre, 1 - side) == before_alive, "без отмены число живых соперника не уменьшится")
			var choice := ai.choose_ability(view, pre, ctrl.legal_abilities(player))
			check(choice == (&"" if baseline else &"ability_fire_counter"), "HARD отменяет воскрешение ради реального выбытия")
			observations.append({"case": mode, "player": player, "attacks": attacks, "choice": String(choice), "before_alive": before_alive, "powers": pre.powers})
			if baseline: continue
			check(is_equal_approx(ai._outcome_utility(view, pre, side), 0.5), "победа с воскрешением противника не уменьшает его материал")
			check(is_equal_approx(ai._outcome_utility(view, ai._with_card(view, pre, choice, side), side), 1.0), "отмена действительно улучшает материальный исход")
			if control:
				check(ctrl.pass_ability(player) == OK, "контроль: вручную сохранено чужое Возрождение")
				finish(ctrl)
				var revived_uid: int = (1 - player) * 3
				check(ctrl.state.alive_count(1 - player) == before_alive and ctrl.state.creatures[revived_uid].alive, "без отмены реально вернулся текущий проигравший либо прежний союзник")
				check(ctrl.get_phase() != MatchController.Phase.GAME_OVER, "сохранённое спасение последнего действительно продолжает матч")
				continue
			var results: Array = []
			ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
			check(ctrl.play_ability(player, choice) == OK, "отмена фактически сыграна")
			finish(ctrl)
			check(results.size() == 1 and not results[0].revive[1 - side], "реальный итог не содержит воскрешения")
			check(not ctrl.state.creatures[foe].alive and ctrl.state.alive_count(1 - player) == before_alive - 1, "соперник действительно потерял бойца")
			if mode == "last": check(ctrl.get_phase() == MatchController.Phase.GAME_OVER and ctrl.winner == player, "отмена спасения последнего завершила матч победой")

func no_waste_and_own_rescue() -> void:
	for player in 2:
		var ctrl := board(player, Attr.A.FIRE, Attr.A.LIGHT, false)
		var uid := player * 3
		var foe := (1 - player) * 3
		ctrl.state.creatures[uid].def_id = &"creature_gorgul_fire"
		ctrl.state.slots[0].card_id = &"arena_field_light"
		ctrl.state.slots[0].card_owner = 1 - player
		ctrl.state.players[player].ability_hand.assign([&"ability_fire_counter"])
		ctrl.state.players[1 - player].ability_hand.assign([&"ability_light_revive"])
		ctrl._start_battle(foe, uid, 0)
		check(ctrl.play_ability(1 - player, &"ability_light_revive") == OK, "Возрождение противника сыграно в контрольном проигрыше")
		var ai := AIPlayer.new(player, 99109, -1.0, AIPlayer.Difficulty.HARD)
		var pre := ctrl.get_battle_preview()
		check(ctrl.legal_abilities(player).has(&"ability_fire_counter"), "отмена доступна и в проигрышной позиции")
		check(ai._with_card(ctrl.get_view(player), pre, &"ability_fire_counter", 1).loser_uid == uid, "отмена всё ещё оставляет собственное поражение")
		check(ai.choose_ability(ctrl.get_view(player), pre, ctrl.legal_abilities(player)) == &"", "ИИ не тратит отмену без материального улучшения")
		finish(ctrl)
		check(not ctrl.state.creatures[uid].alive, "контрольный проигрыш фактически разрешён")
		# Собственное Возрождение продолжает спасать только что проигравшего последнего.
		ctrl = board(player, Attr.A.LIGHT, Attr.A.FIRE, false)
		ctrl.state.creatures[uid].def_id = &"creature_gorgul_light"
		for other in ctrl.state.players[player].creature_uids: ctrl.state.creatures[other].alive = other == uid
		ctrl.state.players[player].ability_hand.assign([&"ability_light_revive"])
		ctrl._start_battle(foe, uid, 0)
		pre = ctrl.get_battle_preview()
		check(pre.loser_uid == uid, "последний Свет проигрывает до собственного спасения")
		var choice := ai.choose_ability(ctrl.get_view(player), pre, ctrl.legal_abilities(player))
		check(choice == &"ability_light_revive", "собственное спасение выбирается при улучшении числа живых")
		check(ctrl.play_ability(player, choice) == OK, "собственное Возрождение разыграно")
		finish(ctrl)
		check(ctrl.state.creatures[uid].alive and ctrl.state.alive_count(player) == 1 and ctrl.get_phase() != MatchController.Phase.GAME_OVER, "только что проигравший последний действительно вернулся")

func terminal_trade() -> void:
	for player in 2:
		var ctrl := board(player, Attr.A.LIGHT, Attr.A.SHADOW, false)
		var uid := player * 3
		var foe := (1 - player) * 3
		ctrl.state.creatures[foe].def_id = &"creature_gorgul_shadow"
		# Keep the same terminal-trade contract after the accepted −100 G price:
		# 370+50−100 still beats280, so the losing Shadow fighter's Doom applies.
		ctrl.state.creatures[uid].marks.append({"delta": 50, "src": &"fixture_margin"})
		for p in 2:
			for other in ctrl.state.players[p].creature_uids: ctrl.state.creatures[other].alive = other == uid or other == foe
		ctrl.state.players[player].ability_hand.assign([&"ability_light_revive"])
		ctrl.state.players[1 - player].ability_hand.assign([&"ability_shadow_doom"])
		ctrl._start_battle(foe, uid, 0)
		check(ctrl.play_ability(1 - player, &"ability_shadow_doom") == OK, "настоящая Бездна готовит обоюдную гибель последних")
		var ai := AIPlayer.new(player, 99111, -1.0, AIPlayer.Difficulty.HARD)
		var pre := ctrl.get_battle_preview()
		check(pre.both_lose and is_equal_approx(ai._outcome_utility(ctrl.get_view(player), pre, 1), 0.5), "обоюдная гибель последних — ничейная ценность")
		var after := ai._with_card(ctrl.get_view(player), pre, &"ability_light_revive", 1)
		check(is_equal_approx(ai._outcome_utility(ctrl.get_view(player), after, 1), 1.0), "собственное спасение после обоюдной гибели выигрывает матч")
		check(ai.choose_ability(ctrl.get_view(player), pre, ctrl.legal_abilities(player)) == &"ability_light_revive", "HARD выбирает действительную победу вместо терминальной ничьей")
		check(ctrl.play_ability(player, &"ability_light_revive") == OK, "спасение терминального размена сыграно")
		finish(ctrl)
		check(ctrl.get_phase() == MatchController.Phase.GAME_OVER and ctrl.winner == player and ctrl.state.creatures[uid].alive and not ctrl.state.creatures[foe].alive, "реальная победа после обоюдной гибели и Возрождения")

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	baseline = OS.get_cmdline_user_args().has("baseline")
	for mode in ["current", "ally", "last"]: counter_revive(mode)
	if not baseline:
		for mode in ["current", "ally", "last"]: counter_revive(mode, true)
		no_waste_and_own_rescue()
		terminal_trade()
	var output := FileAccess.open("res://build/checks/element-balance-20261104/material-baseline.json" if baseline else "res://build/checks/element-balance-20261104/material.json", FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "baseline": baseline, "observations": observations}, "\t") + "\n")
	print("AI material positions: %d assertions; %d failures; baseline=%s" % [assertions, failures, baseline])
	quit(1 if failures else 0)
