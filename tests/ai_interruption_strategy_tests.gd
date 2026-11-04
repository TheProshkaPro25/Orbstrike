extends SceneTree
## Реальные ответы на Отлив: отмена должна предпочитаться прерыванию, если даёт победу.
var failures := 0
var assertions := 0
var observations: Array = []
var baseline := false

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func deck(el: int) -> DeckDef:
	var creatures: Array = []
	for sp in ["dragnar", "ratnik", "levian"]:
		creatures.append(StringName("creature_%s_%s" % [sp, GameData.ATTR_KEYS[el]]))
	return CardDB.build_deck(creatures, [&"arena_funnel", &"arena_altar", StringName("arena_field_" + GameData.ATTR_KEYS[el])], [])

func board(player: int, own_element: int, foe_element: int, own_attacks: bool) -> MatchController:
	var own := deck(own_element)
	var foe := deck(foe_element)
	var ctrl := MatchController.new(own if player == 0 else foe, foe if player == 0 else own, 77309)
	ctrl.landing_window = true
	ctrl._draw_pools = [[[], []], [[], []]]
	ctrl.start(player)
	for ps in ctrl.state.players: ps.ability_hand.clear()
	var uid := player * 3
	var other := (1 - player) * 3
	var gate := ctrl.state.slots[0]
	gate.has_card = true
	gate.card_id = &"arena_hold" # neutral power; preserve a real gate and opening window
	gate.card_owner = 1 - player
	gate.revealed = true
	var defender := other if own_attacks else uid
	gate.occupant_uid = defender
	ctrl.state.creatures[defender].slot = 0
	var spare := ctrl.state.slots[1]
	spare.has_card = true
	spare.card_id = &"arena_funnel"
	spare.card_owner = 1 - player
	ctrl._turn_player = player if own_attacks else 1 - player
	return ctrl

func finish(ctrl: MatchController) -> void:
	for i in 8:
		if ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW: return
		check(ctrl.pass_ability(ctrl.get_active_player()) == OK, "пас разрешён")
	check(false, "бой завершился")

func counter_ebb() -> void:
	for player in 2:
		for attacks in [false, true]:
			var ctrl := board(player, Attr.A.FIRE, Attr.A.TIDE, attacks)
			var uid := player * 3
			var foe := (1 - player) * 3
			ctrl.state.players[player].ability_hand.assign([&"ability_fire_counter"])
			ctrl.state.players[1 - player].ability_hand.assign([&"ability_tide_ebb"])
			ctrl._start_battle(uid if attacks else foe, foe if attacks else uid, 0)
			if attacks and ctrl.get_active_player() == player: check(ctrl.pass_ability(player) == OK, "сначала ответ противника")
			check(ctrl.play_ability(1 - player, &"ability_tide_ebb") == OK, "настоящий Отлив сыгран")
			var before := ctrl.get_battle_preview()
			check(before.interrupted and ctrl.get_active_player() == player, "Отлив прерывает, окно отмены ещё открыто")
			check(ctrl.legal_abilities(player).has(&"ability_fire_counter"), "реальная ответная отмена законна")
			var ai := AIPlayer.new(player, 77311, -1.0, AIPlayer.Difficulty.HARD)
			var chosen := ai.choose_ability(ctrl.get_view(player), before, ctrl.legal_abilities(player))
			check(chosen == (&"" if baseline else &"ability_fire_counter"), "HARD предпочитает настоящее выбытие прерыванию")
			observations.append({"case": "counter_ebb", "player": player, "attacks": attacks, "powers": before.powers, "chosen": String(chosen)})
			if not baseline:
				var resolved: Array = []
				ctrl.battle_resolved.connect(func(r: BattleResult) -> void: resolved.append(r))
				check(ctrl.play_ability(player, chosen) == OK, "ИИ действительно играет отмену")
				var after := ctrl.get_battle_preview()
				if after == null and not resolved.is_empty(): after = resolved[-1]
				check(not after.interrupted and after.winner_uid == uid and after.cancelled_plays.has([1 if attacks else 0, &"ability_tide_ebb"]), "отмена убирает Отлив и возвращает победу")
				finish(ctrl)
				check(not ctrl.state.creatures[foe].alive and ctrl.state.creatures[uid].alive, "фактическое выбытие соперника вместо прерывания")

func own_escape_and_win() -> void:
	for player in 2:
		var ctrl := board(player, Attr.A.TIDE, Attr.A.FIRE, false)
		var uid := player * 3
		var foe := (1 - player) * 3
		ctrl.state.players[player].ability_hand.assign([&"ability_tide_ebb"])
		ctrl._start_battle(foe, uid, 0)
		if ctrl.get_active_player() == 1 - player: check(ctrl.pass_ability(1 - player) == OK, "владелец Отлива получает ответ")
		var ai := AIPlayer.new(player, 77312, -1.0, AIPlayer.Difficulty.HARD)
		var pre := ctrl.get_battle_preview()
		check(pre.loser_uid == uid, "до спасения проигрыш")
		check(is_zero_approx(ai._outcome_utility(ctrl.get_view(player), pre, 1)), "поражение имеет нулевую ценность")
		var escape := ai._with_card(ctrl.get_view(player), pre, &"ability_tide_ebb", 1)
		check(escape.interrupted and is_equal_approx(ai._outcome_utility(ctrl.get_view(player), escape, 1), 0.5), "прерывание имеет половинную ценность, а не победу")
		check(is_equal_approx(ai._attack_win_prob(ctrl.get_view(player), uid, foe, 0), 0.5 - AIPlayer.CARD_COST), "план атаки с одним Отливом не обещает почти гарантированную победу")
		check(ai.choose_ability(ctrl.get_view(player), pre, ctrl.legal_abilities(player)) == &"ability_tide_ebb", "Отлив по-прежнему выбирается для спасения")
		ctrl.state.players[player].ability_hand.append(&"ability_tide_surf")
		check(ai.choose_ability(ctrl.get_view(player), pre, ctrl.legal_abilities(player)) == &"ability_tide_surf", "доступная настоящая победа лучше своего прерывания")
		var won := ai._with_card(ctrl.get_view(player), pre, &"ability_tide_surf", 1)
		check(is_equal_approx(ai._outcome_utility(ctrl.get_view(player), won, 1), 1.0), "настоящая победа имеет полную ценность")
		check(ctrl.play_ability(player, &"ability_tide_surf") == OK, "победное усиление законно")
		finish(ctrl)
		check(ctrl.state.creatures[uid].alive and not ctrl.state.creatures[foe].alive, "свой Отлив не отнимает достигнутую победу")

func preserve_useful_interruption() -> void:
	for player in 2:
		var ctrl := board(player, Attr.A.FIRE, Attr.A.TIDE, false)
		var uid := player * 3
		var foe := (1 - player) * 3
		ctrl.state.creatures[uid].def_id = &"creature_gorgul_fire"
		ctrl.state.creatures[foe].def_id = &"creature_levian_tide"
		ctrl.state.slots[0].card_id = &"arena_field_tide"
		ctrl.state.players[player].ability_hand.assign([&"ability_fire_counter"])
		ctrl.state.players[1 - player].ability_hand.assign([&"ability_tide_ebb"])
		ctrl._start_battle(foe, uid, 0)
		check(ctrl.play_ability(1 - player, &"ability_tide_ebb") == OK, "Отлив спасает обе стороны от исхода")
		var ai := AIPlayer.new(player, 77313, -1.0, AIPlayer.Difficulty.HARD)
		var pre := ctrl.get_battle_preview()
		check(ctrl.legal_abilities(player).has(&"ability_fire_counter"), "бесполезная отмена всё же законна")
		check(ai._with_card(ctrl.get_view(player), pre, &"ability_fire_counter", 1).loser_uid == uid, "после отмены всё ещё проигрыш")
		check(ai.choose_ability(ctrl.get_view(player), pre, ctrl.legal_abilities(player)) == &"", "ИИ не тратит отмену ради собственного поражения")
		finish(ctrl)
		check(ctrl.state.creatures[uid].alive and ctrl.state.creatures[foe].alive, "фактическое прерывание сохраняет бойцов")

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	var args := OS.get_cmdline_user_args()
	baseline = args.has("baseline")
	counter_ebb()
	if not baseline:
		own_escape_and_win()
		preserve_useful_interruption()
	var output := "res://build/checks/element-balance-20261104/interruption-baseline.json" if baseline else "res://build/checks/element-balance-20261104/interruption.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "baseline": baseline, "observations": observations}, "\t") + "\n")
	print("AI interruption positions: %d assertions; %d failures; baseline=%s" % [assertions, failures, baseline])
	quit(1 if failures else 0)
