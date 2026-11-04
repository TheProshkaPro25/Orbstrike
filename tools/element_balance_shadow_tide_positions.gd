extends "res://tests/ai_interruption_strategy_tests.gd"
## Достижимая контригра Прилива против Бездны, без новой матчевой серии.

func doom_reply(player: int, escape: bool) -> void:
	var ctrl := board(player, Attr.A.TIDE, Attr.A.SHADOW, false)
	var own := player * 3
	var foe := (1 - player) * 3
	ctrl.state.slots[0].card_id = &"arena_funnel"
	ctrl.state.slots[0].card_owner = player
	ctrl.state.players[player].ability_hand.assign([&"ability_tide_ebb" if escape else &"ability_tide_counter"])
	ctrl.state.players[1 - player].ability_hand.assign([&"ability_shadow_doom"])
	if escape:
		for uid in ctrl.state.players[player].creature_uids: ctrl.state.creatures[uid].alive = uid == own
	ctrl._start_battle(foe, own, 0)
	check(ctrl.play_ability(1 - player, &"ability_shadow_doom") == OK, "Бездна действительно сыграна проигрывающей Тенью")
	var pre := ctrl.get_battle_preview()
	check(pre != null and pre.both_lose and ctrl.get_active_player() == player, "Прилив получил настоящий ответ на угрозу размена")
	var ai := AIPlayer.new(player, 88901, -1.0, AIPlayer.Difficulty.HARD)
	var chosen := ai.choose_ability(ctrl.get_view(player), pre, ctrl.legal_abilities(player))
	check(chosen == (&"ability_tide_ebb" if escape else &"ability_tide_counter"), "HARD использует доступную контригру")
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	check(ctrl.play_ability(player, chosen) == OK, "выбранный ответ принят контроллером")
	finish(ctrl)
	check(results.size() == 1, "получен настоящий итог боя")
	if not results.is_empty():
		var r: BattleResult = results[0]
		if escape:
			check(r.interrupted and not r.both_lose and ctrl.state.creatures[own].alive and ctrl.state.creatures[foe].alive, "Отлив реально спасает последнего без гибели обоих")
		else:
			check(not r.both_lose and r.winner_uid == own and not ctrl.state.creatures[foe].alive, "ответная отмена действительно убирает Бездну и выводит Тень")
		observations.append({"case": "ebb" if escape else "counter", "player": player, "chosen": String(chosen), "powers": r.powers, "interrupted": r.interrupted, "both_lose": r.both_lose, "winner": r.winner_uid})

func preemptive_hush(player: int) -> void:
	var ctrl := board(player, Attr.A.TIDE, Attr.A.SHADOW, true)
	var own := player * 3
	var foe := (1 - player) * 3
	ctrl.state.creatures[own].marks.append({"delta": 300, "src": &"fixture"})
	ctrl.state.slots[0].card_id = &"arena_funnel"
	ctrl.state.slots[0].card_owner = 1 - player
	ctrl.state.slots[0].revealed = false
	ctrl.state.players[player].ability_hand.assign([&"ability_tide_hush"])
	ctrl.state.players[1 - player].ability_hand.assign([&"ability_shadow_doom"])
	ctrl._start_battle(own, foe, 0)
	check(ctrl.play_ability(player, &"ability_tide_hush") == OK, "упреждающая Тишь сыграна до Бездны")
	check(ctrl.get_active_player() == 1 - player and not ctrl.legal_abilities(1 - player).has(&"ability_shadow_doom"), "Тишь действительно запрещает новую Бездну")
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	check(ctrl.reveal_gate(1 - player) == OK, "противник использовал своё настоящее окно открытия ворот")
	finish(ctrl)
	check(results.size() == 1 and results[0].winner_uid == own and not results[0].both_lose and not ctrl.state.creatures[foe].alive, "запрет Бездны сохраняется после открытия и Прилив реально побеждает")
	observations.append({"case": "preemptive_hush", "player": player, "winner": results[0].winner_uid if not results.is_empty() else -1})

func _initialize() -> void:
	Engine.max_fps = 60
	AudioServer.set_bus_mute(0, true)
	CardDB.load_all()
	for player in 2:
		doom_reply(player, false)
		doom_reply(player, true)
		preemptive_hush(player)
	var f := FileAccess.open("res://build/checks/element-balance-20261104/shadow-tide-counterpositions.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "observations": observations, "scope": "Три доступных вида контригры, обе playerID, реальные одиночные исходы; не новая серия и не доказательство равенства пары."}, "\t"))
	print("SHADOW TIDE COUNTERPOSITIONS: %d checks, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
