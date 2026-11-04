extends SceneTree
var assertions := 0
var failures := 0
var observations: Array = []
var baseline := false
var timings: Array = []

class BeforeComboAI extends AIPlayer:
	func _swap_combo_plan(_view: MatchState, _initial: BattleResult, _swapped: BattleResult, _swap_id: StringName, _side: int) -> Dictionary:
		return {}

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func deck(el: String) -> DeckDef:
	var species: Array = ["ratnik", "kolossar", "gorgul"] if el == "gale" else ["dragnar", "ratnik", "gorgul"]
	var ids: Array = []
	for sp in species: ids.append(StringName("creature_%s_%s" % [sp, el]))
	var abilities: Array = [&"ability_gale_swap", &"ability_gale_gust", &"ability_kolossar_wall"] if el == "gale" else [&"ability_fire_toll", &"ability_fire_spark", &"ability_dragnar_rush"]
	return CardDB.build_deck(ids, [&"arena_altar", StringName("arena_den_" + String(species[0])), &"arena_funnel"], abilities)

func fixture(player: int) -> MatchController:
	var ctrl := MatchController.new(deck("gale") if player == 0 else deck("fire"), deck("fire") if player == 0 else deck("gale"), 80213)
	ctrl.landing_window = true
	ctrl._draw_pools = [[[], []], [[], []]]
	ctrl.start(player)
	ctrl.state.players[player].ability_hand.assign([&"ability_gale_swap", &"ability_gale_gust"])
	ctrl.state.players[1 - player].ability_hand.assign([&"ability_fire_toll"])
	var foe := (1 - player) * 3
	ctrl.state.slots[0].has_card = true
	ctrl.state.slots[0].card_id = &"arena_altar"
	ctrl.state.slots[0].card_owner = 1 - player
	ctrl.state.slots[0].revealed = true
	ctrl.state.slots[0].occupant_uid = foe
	ctrl.state.creatures[foe].slot = 0
	ctrl.state.slots[1].has_card = true
	ctrl.state.slots[1].card_id = &"arena_funnel"
	ctrl.state.slots[1].card_owner = player
	ctrl.state.slots[1].occupant_uid = player * 3 + 2
	ctrl.state.creatures[player * 3 + 2].slot = 1
	ctrl.state.phase = MatchController.Phase.AWAIT_THROW
	ctrl.state.active_player = player
	return ctrl

func counterposition(player: int) -> void:
	var ctrl := fixture(player)
	var uid := player * 3
	var foe := (1 - player) * 3
	var ai := AIPlayer.new(player, 80219, -1.0, AIPlayer.Difficulty.HARD)
	var view := ctrl.get_view(player)
	var encoded := JSON.stringify(OnlineStateCodec.encode_view(view))
	var pre := PowerCalc.compute_seq(view, uid, foe, 0, [])
	var swap := ai._with_card(view, pre, &"ability_gale_swap", 0)
	var boost := ai._with_card(view, pre, &"ability_gale_gust", 0)
	var pair := ai._with_card(view, swap, &"ability_gale_gust", 0)
	check(pre.powers == [340, 690] and swap.powers == [660, 690] and boost.powers == [480, 690], "обе одиночные карты проигрывают Алтарю")
	check(pair.powers == [800, 690] and pair.winner_uid == player * 3 + 1 and pair.ability_count(0) == 2, "PowerCalc уже умеет законную победную пару с заменённым бойцом")
	var forecast := ai._attack_win_prob(view, uid, foe, 0)
	check(JSON.stringify(OnlineStateCodec.encode_view(view)) == encoded, "прогноз пары не изменяет исходный вид")
	check(is_zero_approx(forecast) if baseline else forecast > 0.0, "прогноз видит именно выигрыш двух доступных карт")
	check(ctrl.select_creature(player, uid) == OK, "готовый атакующий выбран")
	ctrl.report_landing(uid, 0)
	var choice := ai.choose_ability(ctrl.get_view(player), ctrl.get_battle_preview(), ctrl.legal_abilities(player))
	check(choice == (&"" if baseline else &"ability_gale_swap"), "живой HARD начинает ту же пару, которую видит прогноз")
	observations.append({"case": "counterposition", "player": player, "single_swap": swap.powers, "single_boost": boost.powers, "pair": pair.powers, "forecast": forecast, "chosen": String(choice)})
	if baseline: return
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	check(ctrl.play_ability(player, choice) == OK, "HARD реально начал Подмену")
	for step in 10:
		if ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW: break
		var p := ctrl.get_active_player()
		var responder := AIPlayer.new(p, 80223, -1.0, AIPlayer.Difficulty.HARD)
		var id := responder.choose_ability(ctrl.get_view(p), ctrl.get_battle_preview(), ctrl.legal_abilities(p))
		check((ctrl.pass_ability(p) if id == &"" else ctrl.play_ability(p, id)) == OK, "живой ответ HARD разрешён")
	check(results.size() == 1, "настоящий бой разрешён")
	if not results.is_empty():
		var r: BattleResult = results[0]
		check(r.powers == [740, 690] and r.winner_uid == player * 3 + 1 and not ctrl.state.creatures[foe].alive, "Swap+Gust реально победили740:690 после настоящей Пошлины соперника")
		check(r.plays == [[0, &"ability_gale_swap"], [1, &"ability_fire_toll"], [0, &"ability_gale_gust"]], "между двумя своими картами состоялся настоящий ответ противника")
		observations.append({"case": "actual_hard_combo", "player": player, "plays": r.plays, "powers": r.powers, "winner": r.winner_uid, "loser": r.loser_uid})

func negative_guards(player: int) -> void:
	var uid := player * 3
	var foe := (1 - player) * 3
	for mode in ["no_reserve", "no_boost", "no_strength", "wrong_species", "old_slots", "new_slots"]:
		var ctrl := fixture(player)
		match mode:
			"no_reserve": ctrl.state.creatures[uid + 1].slot = 2
			"no_boost": ctrl.state.players[player].ability_hand.assign([&"ability_gale_swap"])
			"no_strength": ctrl.state.creatures[foe].marks.append({"delta": 200, "src": &"fixture"})
			"wrong_species": ctrl.state.players[player].ability_hand.assign([&"ability_gale_swap", &"ability_ratnik_oath"])
			"old_slots": ctrl.state.creatures[uid].attached.assign([[0, &"ability_ratnik_oath"], [1, &"ability_gale_counter"]])
			"new_slots": ctrl.state.creatures[uid + 1].attached.assign([[0, &"ability_kolossar_wall"], [1, &"ability_gale_counter"]])
		var ai := AIPlayer.new(player, 80227, -1.0, AIPlayer.Difficulty.HARD)
		var view := ctrl.get_view(player)
		var pre := PowerCalc.compute_seq(view, uid, foe, 0, [])
		var first := ai._with_card(view, pre, &"ability_gale_swap", 0)
		check(ai._swap_combo_plan(view, pre, first, &"ability_gale_swap", 0).is_empty(), "нет незаконного/бесполезного продолжения: " + mode)
		check(ctrl.select_creature(player, uid) == OK, "контрольный атакующий выбран")
		ctrl.report_landing(uid, 0)
		var pick := ai.choose_ability(ctrl.get_view(player), ctrl.get_battle_preview(), ctrl.legal_abilities(player))
		if mode not in ["old_slots", "new_slots"]: check(pick == &"", "комбо не форсируется: " + mode)
		elif mode == "old_slots": check(pick != &"ability_gale_swap", "два старых прикрепления не оставляют двух действий")
		else: check(first.ability_count(0) == 3, "два новых прикрепления учтены вместе с Подменой")
	# Между картами противник действительно может изменить исход; второй ход не предписан.
	var ctrl := fixture(player)
	ctrl.state.players[1 - player].ability_hand.assign([&"ability_fire_drain"])
	check(ctrl.select_creature(player, uid) == OK, "атакующий контрответа выбран")
	ctrl.report_landing(uid, 0)
	check(ctrl.play_ability(player, &"ability_gale_swap") == OK, "первая Подмена законна до ответа")
	var rival := AIPlayer.new(1 - player, 80229, -1.0, AIPlayer.Difficulty.HARD)
	var response := rival.choose_ability(ctrl.get_view(1 - player), ctrl.get_battle_preview(), ctrl.legal_abilities(1 - player))
	check(response == &"ability_fire_drain" and ctrl.play_ability(1 - player, response) == OK, "HARD противник реально выбрал изменяющий бой ответ")
	var ai := AIPlayer.new(player, 80231, -1.0, AIPlayer.Difficulty.HARD)
	check(ai.choose_ability(ctrl.get_view(player), ctrl.get_battle_preview(), ctrl.legal_abilities(player)) == &"", "после контрответа второй boost не форсируется")
	check(ctrl.pass_ability(player) == OK, "пас после опровержения плана разрешён")
	check(ctrl.state.players[player].ability_hand.has(&"ability_gale_gust"), "бесполезный boost действительно сохранён")

func timing() -> void:
	for mode in ["combo", "no_reserve"]:
		var ctrl := fixture(0)
		if mode == "no_reserve": ctrl.state.creatures[1].slot = 2
		ctrl.select_creature(0, 0)
		ctrl.report_landing(0, 0)
		var view := ctrl.get_view(0)
		var preview := ctrl.get_battle_preview()
		var legal := ctrl.legal_abilities(0)
		var entry := {"position": mode}
		for method in ["planning", "live"]:
			for before in [true, false]:
				var samples: Array = []
				for run in 3:
					var ai: AIPlayer = BeforeComboAI.new(0, 80237, -1.0, AIPlayer.Difficulty.HARD) if before else AIPlayer.new(0, 80237, -1.0, AIPlayer.Difficulty.HARD)
					var start := Time.get_ticks_usec()
					if method == "planning": ai._attack_win_prob(view, 0, 3, 0)
					else: ai.choose_ability(view, preview, legal)
					samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
				samples.sort()
				entry[method + ("_before" if before else "_after")] = {"median_ms": samples[1], "max_ms": samples[-1], "samples_ms": samples}
		timings.append(entry)

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	baseline = OS.get_cmdline_user_args().has("baseline")
	for player in 2: counterposition(player)
	if not baseline:
		for player in 2: negative_guards(player)
		timing()
	var file := FileAccess.open("res://build/checks/element-balance-20261104/swap-combo-baseline.json" if baseline else "res://build/checks/element-balance-20261104/swap-combo.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "baseline": baseline, "observations": observations, "timings": timings}, "\t") + "\n")
	print("AI swap combo: %d assertions; %d failures; baseline=%s" % [assertions, failures, baseline])
	quit(1 if failures else 0)
