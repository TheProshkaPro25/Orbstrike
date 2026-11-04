extends SceneTree
## Новый ANIME last-rush и исторический LEGACY; настоящие исходы трёх боёв.
var assertions := 0
var failures := 0
var observations: Array = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func deck(el: int) -> DeckDef:
	var ids: Array = []
	for sp in ["dragnar", "ratnik", "gorgul"]:
		ids.append(StringName("creature_%s_%s" % [sp, GameData.ATTR_KEYS[el]]))
	return CardDB.build_deck(ids, [&"arena_funnel", &"arena_altar", StringName("arena_field_" + GameData.ATTR_KEYS[el])], [])

func fixture(player: int, el: int, ruleset: int = MatchRules.Ruleset.ANIME_INSPIRED, species_index: int = 2) -> MatchController:
	var own := deck(el)
	var foe := deck(Attr.A.FIRE)
	var ctrl := MatchController.new(own if player == 0 else foe, foe if player == 0 else own, 88219, ruleset)
	ctrl.landing_window = true
	ctrl._draw_pools = [[[], []], [[], []]]
	ctrl.start(player)
	for ps in ctrl.state.players: ps.ability_hand.clear()
	for uid in ctrl.state.players[player].creature_uids:
		ctrl.state.creatures[uid].alive = uid == player * 3 + species_index
	return ctrl

func begin(ctrl: MatchController, player: int, foe_index: int, gate_id: StringName = &"arena_funnel", gate_owner: int = -1, revealed: bool = true, species_index: int = 2) -> void:
	for c in ctrl.state.creatures.values(): c.slot = -1
	for s in ctrl.state.slots:
		s.has_card = false
		s.occupant_uid = -1
	var own := player * 3 + species_index
	var foe := (1 - player) * 3 + foe_index
	var gate := ctrl.state.slots[0]
	gate.has_card = true
	gate.card_id = gate_id
	gate.card_owner = player if gate_owner < 0 else gate_owner
	gate.revealed = revealed
	gate.occupant_uid = own
	ctrl.state.creatures[own].slot = 0
	var spare := ctrl.state.slots[1]
	spare.has_card = true
	spare.card_id = &"arena_funnel"
	spare.card_owner = 1 - player
	ctrl._turn_player = 1 - player
	ctrl._start_battle(foe, own, 0)

func finish(ctrl: MatchController) -> void:
	for step in 8:
		if ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW: return
		check(ctrl.pass_ability(ctrl.get_active_player()) == OK, "пас существующего окна разрешён")
	check(false, "обмен завершён")

func check_rest(ctrl: MatchController, player: int, id: StringName, expected: int, message: String) -> void:
	var ps := ctrl.state.players[player]
	check(not ps.ability_hand.has(id) and ps.abilities_used.has(id) and ps.ability_cooldown.get(id, -1) == expected, message)

func rest_chain(player: int, el: int, id: StringName, ruleset: int, cancelled: bool = false, suppressed: bool = false) -> void:
	var ctrl := fixture(player, el, ruleset)
	var resolved: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: resolved.append(r))
	ctrl.state.players[player].ability_hand.assign([id])
	if cancelled: ctrl.state.players[1 - player].ability_hand.assign([&"ability_fire_counter"])
	begin(ctrl, player, 2, &"arena_mute" if suppressed else &"arena_funnel", 1 - player if suppressed else player, not suppressed)
	if ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and ctrl.get_active_player() == 1 - player:
		check(ctrl.pass_ability(1 - player) == OK, "противник сохраняет закрытые ворота до карты")
	check(ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and ctrl.get_active_player() == player, "последний боец получает настоящий ответ")
	check(ctrl.play_ability(player, id) == OK, "карта последнего разыграна")
	if cancelled:
		check(ctrl.play_ability(1 - player, &"ability_fire_counter") == OK, "реакция действительно отменяет Тишь")
	if suppressed:
		check(ctrl.reveal_gate(1 - player) == OK, "противник действительно открывает Глухие после Тиши")
	finish(ctrl)
	check(resolved.size() == 1 and not ctrl.state.creatures[(1 - player) * 3 + 2].alive, "первый исход действительно вывел соперника")
	if cancelled or suppressed: check(resolved[0].cancelled_plays.has([1, id]), "разыгранная карта реально отменена/подавлена")
	var immediate := MatchRules.last_rush_returns(CardDB.card(id), ruleset)
	if immediate:
		check(ctrl.state.players[player].ability_hand.has(id) and not ctrl.state.players[player].ability_cooldown.has(id), "разрешённый last-rush возвращает карту сразу")
	else:
		check_rest(ctrl, player, id, 2, "бой розыгрыша не сокращает два следующих боя отдыха")
		for index in 2:
			begin(ctrl, player, index)
			finish(ctrl)
			check(resolved.size() == index + 2 and not ctrl.state.creatures[(1 - player) * 3 + index].alive, "следующий реальный исход посчитан")
			if index == 0: check_rest(ctrl, player, id, 1, "после первого следующего боя карта ещё отдыхает")
			else: check(ctrl.state.players[player].ability_hand.has(id) and not ctrl.state.players[player].ability_cooldown.has(id), "карта вернулась ровно после второго следующего боя")
	observations.append({"case": "rest_chain", "player": player, "card": String(id), "ruleset": ruleset, "cancelled": cancelled, "suppressed": suppressed, "immediate": immediate, "resolved_battles": resolved.size()})

func ebb_rest(player: int) -> void:
	var ctrl := fixture(player, Attr.A.TIDE)
	ctrl.state.players[player].ability_hand.assign([&"ability_tide_ebb"])
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	begin(ctrl, player, 2)
	check(ctrl.play_ability(player, &"ability_tide_ebb") == OK, "Отлив реально разыгран")
	finish(ctrl)
	check(results.size() == 1 and results[0].interrupted and ctrl.state.alive_count(player) == 1, "Отлив сохранил последнего без выбытия")
	check_rest(ctrl, player, &"ability_tide_ebb", 2, "спасение отдыхает два следующих боя")
	for index in 2:
		begin(ctrl, player, index)
		finish(ctrl)
		if index == 0: check_rest(ctrl, player, &"ability_tide_ebb", 1, "Отлив ещё не вернулся после одного исхода")
		else: check(ctrl.state.players[player].ability_hand.has(&"ability_tide_ebb"), "Отлив вернулся после двух последующих исходов")
	check(results.size() == 3, "у спасения проверены три настоящих исхода")

func explicit_contracts(player: int) -> void:
	# Явный returns действует и когда осталось два бойца: last-rush тут неприменим.
	var ctrl := fixture(player, Attr.A.GALE)
	ctrl.state.creatures[player * 3].alive = true
	ctrl.state.players[player].ability_hand.assign([&"ability_gale_vengeance"])
	begin(ctrl, player, 2)
	check(ctrl.play_ability(player, &"ability_gale_vengeance") == OK, "явный returns разыгран при отставании2:3")
	finish(ctrl)
	check(ctrl.state.alive_count(player) == 2 and ctrl.state.players[player].ability_hand.has(&"ability_gale_vengeance"), "явный returns сохраняется независимо от last-rush")
	# Зеленый recall возвращает другую красную карту, но сам отдыхает по новой норме.
	ctrl = fixture(player, Attr.A.FIRE, MatchRules.Ruleset.ANIME_INSPIRED, 1)
	ctrl.state.players[player].ability_hand.assign([&"ability_fire_drain", &"ability_ratnik_rearm"])
	begin(ctrl, player, 2, &"arena_funnel", player, true, 1)
	check(ctrl.play_ability(player, &"ability_fire_drain") == OK, "красная основа recall разыграна")
	check(ctrl.play_ability(player, &"ability_ratnik_rearm") == OK, "зелёный recall разыгран")
	finish(ctrl)
	check(ctrl.state.players[player].ability_hand.has(&"ability_fire_drain") and not ctrl.state.players[player].ability_cooldown.has(&"ability_fire_drain"), "recall действительно вернул красную карту вне обычного отдыха")
	check_rest(ctrl, player, &"ability_ratnik_rearm", 2, "сам recall отдыхает полный срок")

func helper_contract() -> void:
	check(not MatchRules.last_rush_returns(null), "пустая карта не возвращается")
	for id in CardDB.ability_ids():
		var card := CardDB.card(id)
		var expected: bool = CardDB.card_class(card) == &"blue" and not bool(card.params.get("cooldown_always", false))
		check(MatchRules.last_rush_returns(card) == expected, "единая ANIME-классификация " + String(id))
		var legacy: bool = not MatchRules.LEGACY_RESCUE_EFFECTS.has(String(card.effect_id)) and not bool(card.params.get("cooldown_always", false))
		check(MatchRules.last_rush_returns(card, MatchRules.Ruleset.LEGACY) == legacy, "историческая LEGACY-классификация " + String(id))
	var forced := CardDef.make(&"rush_forced_blue", "forced", CardDef.Kind.ABILITY, &"boost", {"amount": 10, "cooldown_always": true}, "")
	check(not MatchRules.last_rush_returns(forced) and not MatchRules.last_rush_returns(forced, MatchRules.Ruleset.LEGACY), "cooldown_always сохраняет полный отдых даже синей карты")

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	helper_contract()
	for player in 2:
		for ruleset in [MatchRules.Ruleset.ANIME_INSPIRED, MatchRules.Ruleset.LEGACY]:
			rest_chain(player, Attr.A.TIDE, &"ability_tide_hush", ruleset)
			rest_chain(player, Attr.A.GALE, &"ability_gale_leap", ruleset)
			rest_chain(player, Attr.A.TIDE, &"ability_gorgul_night", ruleset)
		rest_chain(player, Attr.A.TIDE, &"ability_tide_surf", MatchRules.Ruleset.ANIME_INSPIRED)
		rest_chain(player, Attr.A.TIDE, &"ability_tide_hush", MatchRules.Ruleset.ANIME_INSPIRED, true)
		rest_chain(player, Attr.A.TIDE, &"ability_tide_hush", MatchRules.Ruleset.ANIME_INSPIRED, false, true)
		ebb_rest(player)
		explicit_contracts(player)
	var output := FileAccess.open("res://build/checks/element-balance-20261104/last-rush.json", FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "observations": observations}, "\t") + "\n")
	print("Last rush rules: %d assertions; %d failures" % [assertions, failures])
	quit(1 if failures else 0)
