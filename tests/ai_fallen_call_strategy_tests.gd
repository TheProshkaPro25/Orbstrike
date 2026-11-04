extends "res://tests/ai_interruption_strategy_tests.gd"
## Глобальное воскрешение ворот сравнивается с реальным закрытым исходом.

func fallen_position(player: int, attacks: bool, own_alive: int, foe_alive: int) -> MatchController:
	var ctrl := board(player, Attr.A.FIRE, Attr.A.TIDE, attacks)
	for p in 2:
		var count: int = own_alive if p == player else foe_alive
		for i in 3: ctrl.state.creatures[p * 3 + i].alive = i < count
	ctrl.state.slots[0].card_id = &"arena_fallen_call"
	ctrl.state.slots[0].card_owner = player
	ctrl.state.slots[0].revealed = false
	return ctrl

func preserve_terminal_win() -> void:
	for player in 2:
		for attacks in [false, true]:
			var ctrl := fallen_position(player, attacks, 2, 1)
			var own := player * 3
			var foe := (1 - player) * 3
			ctrl._start_battle(own if attacks else foe, foe if attacks else own, 0)
			var pre := ctrl.get_battle_preview()
			var ai := AIPlayer.new(player, 71119, -1.0, AIPlayer.Difficulty.HARD)
			check(pre.winner_uid == own and ctrl.can_reveal_gate(player), "закрытый бой уже выбивает последнего соперника")
			var view := ctrl.get_view(player)
			var saved := JSON.stringify(OnlineStateCodec.encode_view(view))
			var opened := ai.should_open_gate(view, pre)
			check(opened == baseline, "HARD не меняет готовую победу в матче на глобальный reset")
			check(saved == JSON.stringify(OnlineStateCodec.encode_view(view)) and not ctrl.state.slots[0].revealed, "прогноз не меняет вид/настоящие ворота")
			if baseline: check(ctrl.reveal_gate(player) == OK, "старое ошибочное решение действительно открыло ворота")
			finish(ctrl)
			if baseline:
				check(ctrl.state.alive_count(player) == 3 and ctrl.state.alive_count(1 - player) == 2 and ctrl.get_phase() != MatchController.Phase.GAME_OVER, "ошибочное открытие действительно отменило матчевую победу")
			else:
				check(ctrl.get_phase() == MatchController.Phase.GAME_OVER and ctrl.winner == player and ctrl.state.alive_count(1 - player) == 0, "закрытый исход действительно завершил матч победой")
			observations.append({"case": "terminal_win", "player": player, "attacks": attacks, "opened": opened, "alive_after": [ctrl.state.alive_count(player), ctrl.state.alive_count(1 - player)], "game_over": ctrl.get_phase() == MatchController.Phase.GAME_OVER})

func useful_recovery() -> void:
	for player in 2:
		var ctrl := fallen_position(player, false, 1, 3)
		var own := player * 3
		var foe := (1 - player) * 3
		ctrl._start_battle(foe, own, 0)
		var ai := AIPlayer.new(player, 71123, -1.0, AIPlayer.Difficulty.HARD)
		check(ai.should_open_gate(ctrl.get_view(player), ctrl.get_battle_preview()), "когда возвращаются только свои союзники, полезное открытие сохранено")
		check(ctrl.reveal_gate(player) == OK, "полезное открытие реально выполнено")
		finish(ctrl)
		check(ctrl.state.alive_count(player) == 3 and ctrl.state.alive_count(1 - player) == 2, "реальная выгодная прибавка своих живых посчитана")

func raw_ninth_interaction() -> void:
	for player in 2:
		var ctrl := fallen_position(player, false, 2, 1)
		var own := player * 3
		var foe := (1 - player) * 3
		ctrl.state.creatures[own].def_id = &"creature_grifalon_light" # 340
		ctrl.state.creatures[foe].def_id = &"creature_rogozhuk_tide" # 310
		ctrl.state.players[1 - player].ability_hand.assign([&"ability_tide_ninth"])
		ctrl._start_battle(foe, own, 0)
		check(ctrl.play_ability(1 - player, &"ability_tide_ninth") == OK, "последний соперник действительно сыграл Девятый вал")
		var pre := ctrl.get_battle_preview()
		check(pre.powers == [490, 340] and pre.loser_uid == own, "как в V5 b11 закрытые ворота оставляют поражение владельца")
		var ai := AIPlayer.new(player, 71129, -1.0, AIPlayer.Difficulty.HARD)
		check(ai.should_open_gate(ctrl.get_view(player), pre), "открытие полезно, если глобальное оживление выключит last-условие врага")
		var results: Array = []
		ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
		check(ctrl.reveal_gate(player) == OK, "материально полезный global reset разрешён")
		finish(ctrl)
		check(results.size() == 1 and results[0].powers == [310, 340] and results[0].winner_uid == own, "last-усиление реально выключилось, силовая победа перешла владельцу")
		check(ctrl.state.alive_count(player) == 3 and ctrl.state.alive_count(1 - player) == 2, "после открытия учтены все оживлённые обеих сторон")

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	baseline = OS.get_cmdline_user_args().has("baseline")
	preserve_terminal_win()
	if not baseline:
		useful_recovery()
		raw_ninth_interaction()
	var file := FileAccess.open("res://build/checks/element-balance-20261104/fallen-call-baseline.json" if baseline else "res://build/checks/element-balance-20261104/fallen-call.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "baseline": baseline, "observations": observations}, "\t") + "\n")
	print("AI fallen-call positions: %d assertions; %d failures; baseline=%s" % [assertions, failures, baseline])
	quit(1 if failures else 0)
