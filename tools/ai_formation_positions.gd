extends SceneTree
## Narrow production formation regression; no match series.
var assertions := 0
var failures := 0
var observations: Array = []

class BeforeFormationAI extends AIPlayer:
	func _reserve_attack_better_than_stand(_view: MatchState, _ready: Array[int], _gate_id: StringName, _gate_slot: int, _stand_uid: int) -> bool:
		return false

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func deck(el: String) -> DeckDef:
	var ids: Array = []
	for sp in ["dragnar", "ratnik", "levian"]: ids.append(StringName("creature_%s_%s" % [sp, el]))
	var abilities: Array = [&"ability_gale_swap", &"ability_gale_gust", &"ability_ratnik_oath"] if el == "gale" else [&"ability_fire_counter", &"ability_fire_spark", &"ability_ratnik_rearm"]
	return CardDB.build_deck(ids, [StringName("arena_field_" + el), &"arena_den_dragnar", &"arena_funnel"], abilities)

func fixture(player: int) -> MatchController:
	var ctrl := MatchController.new(deck("gale") if player == 0 else deck("fire"), deck("fire") if player == 0 else deck("gale"), 66103)
	ctrl.landing_window = true
	ctrl._draw_pools = [[[], []], [[], []]]
	ctrl.start(player)
	var own_base := player * 3
	var foe_base := (1 - player) * 3
	ctrl.state.players[player].ability_hand.assign([&"ability_gale_swap"])
	ctrl.state.players[player].arena_hand.assign([&"arena_field_gale"])
	ctrl.state.players[1 - player].ability_hand.assign([&"ability_fire_counter", &"ability_fire_spark", &"ability_ratnik_rearm"])
	ctrl.state.players[1 - player].abilities_used.assign([&"ability_ratnik_oath"])
	ctrl.state.creatures[own_base].slot = own_base
	ctrl.state.slots[own_base].has_card = true
	ctrl.state.slots[own_base].card_id = &"arena_funnel"
	ctrl.state.slots[own_base].card_owner = player
	ctrl.state.slots[own_base].occupant_uid = own_base
	var enemy: CreatureState = ctrl.state.creatures[foe_base + 1]
	enemy.slot = own_base + 1
	enemy.attached.append([0, &"ability_ratnik_oath"])
	ctrl.state.slots[own_base + 1].has_card = true
	ctrl.state.slots[own_base + 1].card_id = &"arena_den_dragnar"
	ctrl.state.slots[own_base + 1].card_owner = player
	ctrl.state.slots[own_base + 1].revealed = true
	ctrl.state.slots[own_base + 1].occupant_uid = enemy.uid
	return ctrl

func resolve_attack(player: int) -> void:
	var ctrl := fixture(player)
	var ai := AIPlayer.new(player, 66107, -1.0, AIPlayer.Difficulty.HARD)
	var view := ctrl.get_view(player)
	var saved := JSON.stringify(OnlineStateCodec.encode_view(view))
	var setup := ai.choose_setup(view, ctrl.legal_setup_slots(), false)
	check(saved == JSON.stringify(OnlineStateCodec.encode_view(view)), "production choose_setup не изменяет полученный вид")
	check(not setup.has("throw_uid"), "card-aware production отдаёт выбор обычной атакующей политике")
	check(ctrl.place_arena_card(player, setup.card_id, setup.slot) == OK, "выбранные ворота реально размещены")
	var shot := ai.choose_throw(ctrl.get_view(player))
	check(shot.target_slot == player * 3 + 1, "обычная политика реально выбрала вражескую цель")
	check(shot.uid != player * 3 and ctrl.state.creatures[shot.uid].slot < 0, "стоящее существо не отзывается для атаки")
	check(ctrl.select_creature(player, shot.uid) == OK, "атакующий выбран")
	ctrl.report_landing(shot.uid, shot.target_slot)
	var pre := ctrl.get_battle_preview()
	var pick := ai.choose_ability(ctrl.get_view(player), pre, ctrl.legal_abilities(player))
	check(pick == &"ability_gale_swap", "ранее сохранённая Подмена действительно нужна и выбрана")
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	check(ctrl.play_ability(player, pick) == OK, "Подмена реально сыграна")
	for step in 8:
		if ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW: break
		var p := ctrl.get_active_player()
		var rival := AIPlayer.new(p, 66111, -1.0, AIPlayer.Difficulty.HARD)
		var id := rival.choose_ability(ctrl.get_view(p), ctrl.get_battle_preview(), ctrl.legal_abilities(p))
		check((ctrl.pass_ability(p) if id == &"" else ctrl.play_ability(p, id)) == OK, "настоящий ответ разрешён")
	check(results.size() == 1, "боевой исход получен")
	if not results.is_empty():
		var r: BattleResult = results[0]
		check(ctrl.state.creatures[r.winner_uid].owner == player and not ctrl.state.creatures[(1 - player) * 3 + 1].alive, "атака с Подменой фактически выбила защитника")
		check(ctrl.state.creatures[player * 3].slot == player * 3, "ранее стоящий союзник сохранён на своём месте")
		observations.append({"case": "resolved_swap_attack", "player": player, "setup": setup, "shot": shot, "plays": r.plays, "powers": r.powers, "winner_uid": r.winner_uid, "loser_uid": r.loser_uid})
	var control := fixture(player)
	control.state.players[player].ability_hand.clear()
	var cautious := AIPlayer.new(player, 66107, -1.0, AIPlayer.Difficulty.HARD)
	check(cautious.choose_setup(control.get_view(player), control.legal_setup_slots(), false).has("throw_uid"), "без полезной резервной способности прежняя постановка сохраняется")

func guards(player: int) -> void:
	var ctrl := fixture(player)
	var ai := AIPlayer.new(player, 66107, -1.0, AIPlayer.Difficulty.HARD)
	var view := ctrl.get_view(player)
	check(CardDB.deck_error(ctrl._debug_decks[0][0], ctrl._debug_decks[0][1], ctrl._debug_decks[0][2]).is_empty() and CardDB.deck_error(ctrl._debug_decks[1][0], ctrl._debug_decks[1][1], ctrl._debug_decks[1][2]).is_empty(), "обе исходные колоды полностью законны")
	for uid in [player * 3 + 1, player * 3 + 2]:
		view.creatures[uid].attached.assign([[0, &"ability_gale_gust"], [1, &"ability_gale_counter"], [2, &"ability_ratnik_oath" if uid % 3 == 1 else &"ability_levian_coil"]])
	check(not ai._reserve_attack_better_than_stand(view, ai._ready(view), &"arena_field_gale", player * 3 + 2, player * 3 + 2), "заполненный лимит прикреплений не создаёт фиктивную Подмену")
	view = ctrl.get_view(player)
	view.creatures[player * 3 + 2].slot = (1 - player) * 3
	view.slots[(1 - player) * 3].has_card = true
	view.slots[(1 - player) * 3].card_id = &"arena_funnel"
	view.slots[(1 - player) * 3].card_owner = player
	view.slots[(1 - player) * 3].occupant_uid = player * 3 + 2
	var picked := ai.choose_setup(view, [player * 3 + 2], false)
	check(picked.has("throw_uid"), "нелегальная замена стоящим резервом сохраняет прежнюю посадку")
	view = ctrl.get_view(player)
	view.players[1 - player].ability_hand.clear()
	view.creatures[(1 - player) * 3 + 1].marks.append({"delta": -300, "src": &"fixture"})
	check(not ai._reserve_attack_better_than_stand(view, ai._ready(view), &"arena_field_gale", player * 3 + 2, player * 3 + 2), "Подмена без улучшения лучшей атаки не включает новую ветку")
	view = ctrl.get_view(player)
	view.creatures[(1 - player) * 3 + 1].marks.append({"delta": 400, "src": &"fixture"})
	check(not ai._reserve_attack_better_than_stand(view, ai._ready(view), &"arena_field_gale", player * 3 + 2, player * 3 + 2), "невыгодная атака не форсируется ради резерва")

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	for player in 2:
		var ctrl := fixture(player)
		var ai := BeforeFormationAI.new(player, 66107, -1.0, AIPlayer.Difficulty.HARD)
		var view := ctrl.get_view(player)
		var setup := ai.choose_setup(view, [player * 3 + 2], false)
		var trial := view.duplicate_full()
		trial.slots[int(setup.slot)].has_card = true
		trial.slots[int(setup.slot)].card_id = setup.card_id
		trial.slots[int(setup.slot)].card_owner = player
		var attack := ai._score(trial, player * 3 + 1, player * 3 + 1)
		var stand := ai._score(trial, int(setup.throw_uid), int(setup.slot))
		var throw_choice := ai.choose_throw(trial)
		print("FORMATION player=", player, " setup=", setup, " attack=", attack, " stand=", stand, " throw=", throw_choice, " legal=", ctrl.legal_setup_slots())
		check(setup.has("throw_uid") and attack > stand and attack < 900.0 and throw_choice.target_slot == player * 3 + 1, "разрыв setup900 против обычного выбора throw воспроизведён")
		check(ctrl.throw_with_gate(player, setup.card_id, setup.slot, setup.throw_uid) == OK, "старый автоматический ход действительно размещён")
		ctrl.report_landing(setup.throw_uid, setup.slot)
		var camper := ctrl.get_view(player)
		check(PowerCalc.swap_candidate(camper, player, [player * 3 + 1, (1 - player) * 3 + 1]) < 0, "вторая посадка действительно оставила готового бойца без резерва Подмены")
		observations.append({"case": "old_setup_vs_throw", "player": player, "setup": setup, "attack_score": attack, "stand_score": stand, "ordinary_throw": throw_choice})
		resolve_attack(player)
		guards(player)
	var output := FileAccess.open("res://build/checks/element-balance-20261104/formation-positions.json", FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "production_changed": true, "observations": observations}, "\t") + "\n")
	print("AI formation positions: %d assertions; %d failures" % [assertions, failures])
	quit(1 if failures else 0)
