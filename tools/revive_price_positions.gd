extends "res://tests/ai_interruption_strategy_tests.gd"
## Isolated card-price candidates; production GameData/CardDB files are untouched.
const PRICES := [30, 0, -80, -100]

func priced_board(player: int, shape: String, last: bool = false, attacks: bool = false) -> MatchController:
	var ctrl := board(player, Attr.A.LIGHT, Attr.A.SHADOW if shape == "middle" else Attr.A.FIRE, attacks)
	var uid := player * 3
	var foe := (1 - player) * 3
	ctrl.state.creatures[foe].def_id = &"creature_gorgul_shadow" if shape == "middle" else &"creature_levian_fire"
	ctrl.state.creatures[player * 3 + 1].alive = false
	if last: ctrl.state.creatures[player * 3 + 2].alive = false
	ctrl.state.slots[0].card_id = &"arena_funnel" if shape == "large" else &"arena_den_ratnik"
	ctrl.state.slots[0].card_owner = player
	return ctrl

func price_case(player: int, shape: String, amount: int) -> void:
	var ctrl := priced_board(player, shape)
	var uid := player * 3
	var foe := (1 - player) * 3
	ctrl.state.players[player].ability_hand.assign([&"ability_light_revive"])
	ctrl._start_battle(foe, uid, 0)
	var ai := AIPlayer.new(player, 55301, -1.0, AIPlayer.Difficulty.HARD)
	var pre := ctrl.get_battle_preview()
	var before := [ctrl.state.alive_count(player), ctrl.state.alive_count(1 - player)]
	check(pre.winner_uid == uid and before == [2, 3], "до карты побеждающий боец и один свой выбывший союзник")
	var decision := ai.choose_ability(ctrl.get_view(player), pre, ctrl.legal_abilities(player))
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	check(ctrl.play_ability(player, &"ability_light_revive") == OK, "цена разыграна настоящим контроллером")
	finish(ctrl)
	check(results.size() == 1, "фактический исход получен")
	var r: BattleResult = results[0]
	var won := r.winner_uid == uid
	var expected_win: bool = shape == "large" or (shape == "middle" and amount >= -80) or (shape == "near" and amount >= 0)
	check(won == expected_win, "цена меняет силовой исход в заявленном диапазоне")
	var after := [ctrl.state.alive_count(player), ctrl.state.alive_count(1 - player)]
	check(after == ([3, 2] if won else [2, 3]), "реально получены выигрыш+новая жизнь либо отказ от выбытия противника")
	check(decision == (&"ability_light_revive" if won else &""), "HARD не тратит побеждающий бой ради худшего исхода")
	check(ctrl.state.creatures[uid].alive, "даже при проигрыше механизм возврата текущего проигравшего сохранён")
	observations.append({"case": shape, "player": player, "amount": amount, "before_powers": pre.powers, "after_powers": r.powers, "chosen": String(decision), "winner_owner": ctrl.state.creatures[r.winner_uid].owner, "alive_before": before, "alive_after": after, "breakdown": r.breakdown})

func last_rescue(player: int, attacks: bool) -> void:
	var ctrl := priced_board(player, "near", true, attacks)
	var uid := player * 3
	var foe := (1 - player) * 3
	ctrl.state.creatures[uid].def_id = &"creature_gorgul_light"
	ctrl.state.creatures[foe].def_id = &"creature_dragnar_fire"
	ctrl.state.players[player].ability_hand.assign([&"ability_light_revive"])
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	ctrl._start_battle(uid if attacks else foe, foe if attacks else uid, 0)
	var pre := ctrl.get_battle_preview()
	var ai := AIPlayer.new(player, 55303, -1.0, AIPlayer.Difficulty.HARD)
	check(pre.loser_uid == uid, "последний уже проигрывает")
	check(ai.choose_ability(ctrl.get_view(player), pre, ctrl.legal_abilities(player)) == &"ability_light_revive", "HARD по-прежнему спасает последнего ценой силы")
	check(ctrl.play_ability(player, &"ability_light_revive") == OK, "спасение последнего сыграно")
	finish(ctrl)
	var cost_rows: Array = []
	for row in results[0].breakdown:
		if row.source == "ability:ability_light_revive": cost_rows.append([row.side, row.delta])
	check(cost_rows == [[0 if attacks else 1, -100]], "журнал и предпросмотр относят−100 самому бойцу владельца карты")
	check(ctrl.state.alive_count(player) == 1 and ctrl.state.creatures[uid].alive and ctrl.get_phase() != MatchController.Phase.GAME_OVER, "только что проигравший последний фактически возродился")
	check(ctrl.state.players[player].ability_cooldown.get(&"ability_light_revive", -1) == 2, "цена не меняет двухбоевой отдых")

func cancelled_price(player: int) -> void:
	var ctrl := priced_board(player, "near", true)
	var uid := player * 3
	var foe := (1 - player) * 3
	ctrl.state.players[player].ability_hand.assign([&"ability_light_revive"])
	ctrl.state.players[1 - player].ability_hand.assign([&"ability_fire_counter"])
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	ctrl._start_battle(foe, uid, 0)
	check(ctrl.play_ability(player, &"ability_light_revive") == OK, "ценовое Возрождение сыграно до отмены")
	var ai := AIPlayer.new(1 - player, 55307, -1.0, AIPlayer.Difficulty.HARD)
	check(ai.choose_ability(ctrl.get_view(1 - player), ctrl.get_battle_preview(), ctrl.legal_abilities(1 - player)) == &"", "HARD не отменяет штраф противника ценой собственного проигрыша")
	check(ctrl.play_ability(1 - player, &"ability_fire_counter") == OK, "цена и спасение отменены вместе")
	finish(ctrl)
	check(results.size() == 1 and not results[0].revive[1] and results[0].cancelled_plays.has([1, &"ability_light_revive"]), "отмена действительно сняла весь эффект Возрождения")
	var priced := false
	for row in results[0].breakdown:
		if row.source == "ability:ability_light_revive": priced = true
	check(not priced, "отменённая карта не оставляет штраф силы")
	check(results[0].powers == [330, 370] and ctrl.state.creatures[uid].alive, "снятие цены реально вернуло100G и изменило победителя")
	observations.append({"case": "cancelled_price", "player": player, "powers": results[0].powers, "own_alive": ctrl.state.alive_count(player)})

func copied_price(player: int, attacks: bool) -> void:
	var ctrl := board(player, Attr.A.STONE, Attr.A.LIGHT, attacks)
	var uid := player * 3
	var foe := (1 - player) * 3
	ctrl.state.creatures[player * 3 + 1].alive = false
	ctrl.state.slots[0].card_id = &"arena_den_ratnik"
	ctrl.state.players[player].ability_hand.assign([&"ability_stone_copy"])
	ctrl.state.players[1 - player].ability_hand.assign([&"ability_light_revive"])
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	ctrl._start_battle(uid if attacks else foe, foe if attacks else uid, 0)
	if ctrl.get_active_player() == player: check(ctrl.pass_ability(player) == OK, "Копия ждёт контракт соперника")
	check(ctrl.play_ability(1 - player, &"ability_light_revive") == OK, "оригинал с ценой сыгран")
	check(ctrl.play_ability(player, &"ability_stone_copy") == OK, "Копия повторяет контракт Возрождения")
	finish(ctrl)
	var deltas: Array = []
	var side: int = 0 if attacks else 1
	var attributed := true
	for row in results[0].breakdown:
		if row.source == "ability:ability_stone_copy":
			deltas.append(row.delta)
			attributed = attributed and int(row.side) == side
	check(deltas == [50, -100] and results[0].revive[side], "Копия даёт собственные+50 и наследует цену−100 вместе со спасением")
	check(attributed, "обе строки Копии относятся стороне скопировавшего бойца")
	check(ctrl.state.alive_count(player) == 3, "скопированное спасение действительно вернуло союзника")

func late_penalty(player: int) -> void:
	var ctrl := priced_board(player, "near", true)
	var uid := player * 3
	var foe := (1 - player) * 3
	ctrl.state.players[player].ability_hand.assign([&"ability_light_revive", &"ability_light_glint"])
	ctrl.state.players[1 - player].ability_hand.assign([&"ability_fire_drain"])
	ctrl._start_battle(foe, uid, 0)
	check(ctrl.pass_ability(1 - player) == OK, "противник ждёт начала последовательности")
	check(ctrl.play_ability(player, &"ability_light_revive") == OK, "Возрождение с ценой первым")
	check(ctrl.play_ability(1 - player, &"ability_fire_drain") == OK, "поздний штраф после цены")
	var pre := ctrl.get_battle_preview()
	check(pre.powers[1] == 170 and pre.powers[0] == 430, "−100 цены и поздние−100 складываются по порядку")
	finish(ctrl)
	check(ctrl.state.creatures[uid].alive and ctrl.state.alive_count(player) == 1, "поздний штраф не отменяет сам контракт спасения")

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	var original := CardDB.card(&"ability_light_revive")
	for amount in PRICES:
		var candidate: CardDef = original.duplicate(true)
		candidate.params["amount"] = amount
		CardDB._cards[String(candidate.id)] = candidate
		check(CardDB.card_class(candidate) == &"red" and not MatchRules.last_rush_returns(candidate), "цена не меняет красный класс и отдых")
		for player in 2:
			for shape in ["near", "middle", "large"]: price_case(player, shape, amount)
		if amount == -100:
			for player in 2:
				for attacks in [false, true]: last_rescue(player, attacks)
				cancelled_price(player)
				for attacks in [false, true]: copied_price(player, attacks)
				late_penalty(player)
	CardDB._cards[String(original.id)] = original
	var file := FileAccess.open("res://build/checks/element-balance-20261104/revive-price-positions.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "production_unchanged": true, "prices": PRICES, "observations": observations}, "\t") + "\n")
	print("Revive price candidates: %d assertions; %d failures" % [assertions, failures])
	quit(1 if failures else 0)
