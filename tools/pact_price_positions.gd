extends SceneTree
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
	for species in ["ratnik", "gorgul", "levian"]: ids.append(StringName("creature_%s_%s" % [species, GameData.ATTR_KEYS[el]]))
	var red: StringName = &"ability_shadow_pact" if el == 4 else (&"ability_stone_copy" if el == 3 else &"ability_light_crown")
	var blue: StringName = &"ability_shadow_haze" if el == 4 else (&"ability_stone_firm" if el == 3 else &"ability_light_glint")
	return CardDB.build_deck(ids, [StringName("arena_field_" + GameData.ATTR_KEYS[el]), &"arena_den_ratnik", &"arena_funnel"], [red, blue, &"ability_ratnik_oath"])

func fixture(player: int, foe_el: int = 2) -> MatchController:
	var own := deck(4)
	var foe := deck(foe_el)
	var ctrl := MatchController.new(own if player == 0 else foe, foe if player == 0 else own, 93103)
	ctrl._draw_pools = [[[], []], [[], []]]
	ctrl.start(player)
	for ps in ctrl.state.players: ps.ability_hand.clear()
	for slot in ctrl.state.slots:
		slot.has_card = true
		slot.card_id = &"arena_fallen_call" # already revealed, no opening event/revival
		slot.card_owner = player
		slot.revealed = true
		slot.occupant_uid = -1
	for i in [1, 2]:
		ctrl.state.creatures[player * 3 + i].slot = i
		ctrl.state.slots[i].occupant_uid = player * 3 + i
	return ctrl

func begin(ctrl: MatchController, attacker: int, defender: int, slot: int) -> void:
	if not ctrl.state.slots[slot].has_card:
		ctrl.state.slots[slot].has_card = true
		ctrl.state.slots[slot].card_id = &"arena_fallen_call"
		ctrl.state.slots[slot].revealed = true
	ctrl.state.creatures[defender].slot = slot
	ctrl.state.slots[slot].occupant_uid = defender
	ctrl._turn_player = ctrl.state.creatures[attacker].owner
	ctrl._start_battle(attacker, defender, slot)

func finish(ctrl: MatchController) -> void:
	for i in 10:
		if ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW: return
		check(ctrl.pass_ability(ctrl.get_active_player()) == OK, "пас только настоящего окна")
	check(false, "обмен завершился")

func effects_and_marks(player: int, attacks: bool, amount: int) -> void:
	var ctrl := fixture(player)
	var uid := player * 3
	var foe := (1 - player) * 3
	var side := 0 if attacks else 1
	ctrl.state.players[player].ability_hand.assign([&"ability_shadow_pact"])
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	begin(ctrl, uid if attacks else foe, foe if attacks else uid, 0)
	check(ctrl.play_ability(player, &"ability_shadow_pact") == OK, "Пакт законно сыгран")
	finish(ctrl)
	var first: BattleResult = results[0]
	var deltas: Array = []
	for row in first.breakdown:
		if row.source == "ability:ability_shadow_pact": deltas.append([row.side, row.delta])
	check(deltas == [[side, amount], [1 - side, -amount]], "источник Пакта даёт силу своему и снимает силу чужому бойцу")
	check(first.ability_count(side) == 1 and first.marks.size() == 2, "одна карта создаёт ровно две метки другим стоящим союзникам")
	for index in [1, 2]:
		var marks: Array = ctrl.state.creatures[uid + index].marks
		check(marks.size() == 1 and marks[0].src == &"ability_shadow_pact" and marks[0].delta == amount, "реальная отложенная метка записана своему союзнику")
	check(ctrl.state.players[player].ability_cooldown.get(&"ability_shadow_pact", -1) == 2, "обычный двухбоевой отдых сохранён")
	begin(ctrl, foe + 1, uid + 1, 1)
	finish(ctrl)
	var consumed: Array = []
	for row in results[1].breakdown:
		if row.source == "mark:ability_shadow_pact": consumed.append([row.side, row.delta])
	check(consumed == [[1, amount]] and ctrl.state.creatures[uid + 1].marks.is_empty(), "следующий настоящий бой потребил метку ровно один раз")
	check(ctrl.state.players[player].ability_cooldown.get(&"ability_shadow_pact", -1) == 1, "один следующий исход ещё не завершает отдых")
	begin(ctrl, foe + 2, uid + 1, 1)
	finish(ctrl)
	check(results[2].powers == [340, 280] and not ctrl.state.creatures[uid + 1].alive, "в повторном бою метка не возникает заново")
	check(ctrl.state.players[player].ability_hand.has(&"ability_shadow_pact"), "Пакт вернулся ровно после двух последующих исходов")
	begin(ctrl, foe + 2, uid + 2, 2)
	finish(ctrl)
	consumed.clear()
	for row in results[3].breakdown:
		if row.source == "mark:ability_shadow_pact": consumed.append([row.side, row.delta])
	check(consumed == [[1, amount]] and ctrl.state.creatures[uid + 2].marks.is_empty(), "второй союзник действительно отдельно потребил свою метку")
	observations.append({"case": "effects_marks", "player": player, "attacks": attacks, "amount": amount, "first_powers": first.powers, "first_deltas": deltas, "consumed_mark": amount, "actual_battles": results.size()})

func cancellation(player: int) -> void:
	var ctrl := fixture(player)
	var uid := player * 3
	var foe := (1 - player) * 3
	ctrl.state.players[player].ability_hand.assign([&"ability_shadow_pact"])
	ctrl.state.players[1 - player].ability_hand.assign([&"ability_light_counter"])
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	begin(ctrl, foe, uid, 0)
	check(ctrl.play_ability(player, &"ability_shadow_pact") == OK, "Пакт до ответа разыгран")
	check(ctrl.play_ability(1 - player, &"ability_light_counter") == OK, "Пакт реально отменён")
	finish(ctrl)
	check(results[0].cancelled_plays.has([1, &"ability_shadow_pact"]) and results[0].marks.is_empty(), "отмена снимает прямую силу и обе будущие метки")
	check(ctrl.state.creatures[uid + 1].marks.is_empty() and ctrl.state.creatures[uid + 2].marks.is_empty(), "отменённая карта не оставила меток в состоянии")
	check(ctrl.state.players[player].ability_cooldown.get(&"ability_shadow_pact", -1) == 2, "отмена не освобождает от обычного отдыха")

func copied_marks(player: int, attacks: bool) -> void:
	var ctrl := fixture(player, 3)
	var uid := player * 3
	var foe := (1 - player) * 3
	for index in [1, 2]:
		ctrl.state.creatures[foe + index].slot = index + 2
		ctrl.state.slots[index + 2].occupant_uid = foe + index
	ctrl.state.players[player].ability_hand.assign([&"ability_shadow_pact"])
	ctrl.state.players[1 - player].ability_hand.assign([&"ability_stone_copy"])
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	begin(ctrl, uid if attacks else foe, foe if attacks else uid, 0)
	if ctrl.get_active_player() != player: check(ctrl.pass_ability(1 - player) == OK, "Копия ждёт основную карту противника")
	check(ctrl.play_ability(player, &"ability_shadow_pact") == OK, "основной Пакт разыгран")
	check(ctrl.play_ability(1 - player, &"ability_stone_copy") == OK, "Копия действительно повторила Пакт")
	finish(ctrl)
	var side := 1 if attacks else 0
	var copied: Array = []
	for row in results[0].breakdown:
		if row.source == "ability:ability_stone_copy": copied.append([row.side, row.delta])
	check(copied == [[side, 50], [side, 40], [1 - side, -40]], "Копия сохраняет свои50 и наследует новые±40 по правильным сторонам")
	var marks: Array = []
	for index in [1, 2]:
		marks.append(ctrl.state.creatures[foe + index].marks)
		check(marks[-1].size() == 1 and marks[-1][0].src == &"ability_stone_copy" and marks[-1][0].delta == 40, "скопированные реальные метки40 принадлежат стороне Копии")
	check(results[0].ability_count(side) == 1, "Копия с повторённым эффектом остаётся одной картой")

func close_v8(player: int, amount: int) -> void:
	# V8 row42/b2: последний Свет340+Рассвет150 против Левиана Тени320+Поля80.
	var ctrl := fixture(player)
	var own := player * 3 + 2
	var foe := (1 - player) * 3 + 2
	for index in [0, 1]: ctrl.state.creatures[(1 - player) * 3 + index].alive = false
	ctrl.state.creatures[own].slot = 0
	ctrl.state.slots[0].card_id = &"arena_field_shadow"
	ctrl.state.slots[0].card_owner = player
	ctrl.state.players[player].ability_hand.assign([&"ability_shadow_pact"])
	ctrl.state.players[1 - player].ability_hand.assign([&"ability_light_dawn"])
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	begin(ctrl, foe, own, 0)
	check(ctrl.play_ability(1 - player, &"ability_light_dawn") == OK, "реальный Рассвет последнего Света")
	check(ctrl.play_ability(player, &"ability_shadow_pact") == OK, "Пакт в точной узкой позиции V8")
	finish(ctrl)
	check(results[0].powers == ([440, 450] if amount == 50 else [450, 440]), "50→40 меняет реальный исход440:450 на450:440")
	check(ctrl.state.creatures[foe].alive == (amount == 40) and ctrl.state.creatures[own].alive == (amount == 50), "цена меняет фактическое выбытие бойца")
	check((ctrl.get_phase() == MatchController.Phase.GAME_OVER) == (amount == 50), "снижение не скрывает прежний терминальныйKO, а меняет его конкретную причину")
	observations.append({"case": "v8_row42", "player": player, "amount": amount, "powers": results[0].powers, "own_alive": ctrl.state.alive_count(player), "foe_alive": ctrl.state.alive_count(1 - player)})

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	var original := CardDB.card(&"ability_shadow_pact")
	for amount in [50, 40]:
		var candidate: CardDef = original.duplicate(true)
		candidate.params["amount"] = amount
		CardDB._cards[String(candidate.id)] = candidate
		check(CardDB.card_class(candidate) == &"red" and CardEffects.moment(candidate) == CardEffects.moment(original) and not CardEffects.returns_to_hand(candidate) and not MatchRules.last_rush_returns(candidate), "класс/момент/возврат/last-rush не изменились")
		for player in 2:
			for attacks in [false, true]: effects_and_marks(player, attacks, amount)
			close_v8(player, amount)
			if amount == 40:
				cancellation(player)
				for attacks in [false, true]: copied_marks(player, attacks)
	CardDB._cards[String(original.id)] = original
	var output := FileAccess.open("res://build/checks/element-balance-20261104/pact-price-positions.json", FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "production_unchanged": true, "observations": observations}, "\t") + "\n")
	print("Pact price positions: %d assertions; %d failures" % [assertions, failures])
	quit(1 if failures else 0)
