extends SceneTree

var failures: int = 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	var ids: Array = CardDB.creature_ids()
	var state := MatchState.new()
	state.creatures[0] = CreatureState.new(0, ids[0], 0)
	state.creatures[1] = CreatureState.new(1, ids[1], 1)
	state.players[0].creature_uids.assign([0])
	state.players[1].creature_uids.assign([1])
	state.players[0].ability_hand.assign([&"ability_fire_boost"])
	state.players[1].ability_hand.assign([&"", &"", &""])
	var ai := AIPlayer.new(0, 7, -1.0, AIPlayer.Difficulty.HARD)
	var r := BattleResult.new()
	r.attacker_uid = 0
	r.defender_uid = 1
	r.slot = 0
	r.powers.assign([100, 300])
	check(ai.choose_ability(state, r, []) == &"", "явно пустой список способностей означает пас")
	state.players[0].arena_hand.assign([&"arena_field_fire"])
	check(ai.choose_setup(state, [], false).is_empty(), "явно пустой список мест не допускает выкладку")
	check(ai._foe_plays_left(state, r, 0) == MatchController.MAX_BATTLE_ABILITIES, "соперник может отвечать")
	r.plays = [[1, &"ability_fire_boost"]]
	check(ai._foe_plays_left(state, r, 0) == MatchController.MAX_BATTLE_ABILITIES - 1, "прикреплённая карта расходует лимит обмена")
	r.battle_plays = [[1, &"ability_fire_boost"]]
	r.plays = r.battle_plays.duplicate(true)
	check(ai._foe_plays_left(state, r, 0) == MatchController.MAX_BATTLE_ABILITIES - 1, "карта обмена расходует лимит")
	r.passed[1] = true
	check(ai._foe_plays_left(state, r, 0) == 0 and ai._foe_plays_left(state, r, 0, true) > 0, "после собственной карты соперник может ответить снова")
	var dragon := CreatureDef.make(&"ai_test_dragon", "dragon", Attr.A.FIRE, 300, Color.WHITE)
	dragon.species = &"dragnar"
	CardDB._creatures[String(dragon.id)] = dragon
	state.creatures[0].def_id = dragon.id
	r.plays = []
	check(not ai._forecast_legal(state, r, &"ability_dragnar_heart", 0), "слияние нельзя разыграть первым")
	check(ai._forecast_legal(state, r, &"ability_dragnar_heart", 0, &"ability_gale_gust"), "слияние допустимо вторым поверх основной карты")
	check(not ai._forecast_legal(state, r, &"ability_ratnik_oath", 0, &"ability_gale_gust"), "прогноз не использует способность чужого вида")
	# Два усиления вместе спасают проигрывающего бойца; после ответа игрока план пересчитывается.
	var strong := CreatureDef.make(&"ai_test_strong", "strong", Attr.A.FIRE, 450, Color.WHITE)
	strong.species = &"dragnar"
	CardDB._creatures[String(strong.id)] = strong
	for id in [&"ai_test_boost_a", &"ai_test_boost_b", &"ai_test_enemy_boost"]:
		CardDB._cards[String(id)] = CardDef.make(id, "boost", 1, &"boost", {"amount": 80}, "")
	var gate := CardDef.make(&"ai_test_gate", "gate", 0, &"none", {}, "")
	gate.params["g"] = [0, 0, 0, 0, 0, 0]
	CardDB._cards[String(gate.id)] = gate
	state.creatures[1].def_id = strong.id
	state.creatures[1].slot = 0
	state.slots[0].has_card = true
	state.slots[0].card_id = gate.id
	state.slots[0].card_owner = 0
	state.slots[0].occupant_uid = 1
	state.players[0].ability_hand.assign([&"ai_test_boost_a", &"ai_test_boost_b"])
	var normal := AIPlayer.new(0, 9, -1.0, AIPlayer.Difficulty.NORMAL)
	var before: BattleResult = PowerCalc.compute_seq(state, 0, 1, 0, [])
	var first: StringName = normal.choose_ability(state, before, state.players[0].ability_hand)
	check(first != &"", "Боец начинает выигрышную комбинацию из двух карт")
	var after: BattleResult = PowerCalc.compute_seq(state, 0, 1, 0, [[0, first], [1, &"ai_test_enemy_boost"]])
	state.players[0].ability_hand.erase(first)
	check(normal.choose_ability(state, after, state.players[0].ability_hand) == &"", "Боец пересчитывает план после усиления противника")
	# При выборе ворот оценивается реальная защита существа от готового соперника.
	state.creatures[1].slot = -1
	state.slots[0].has_card = false
	state.slots[0].occupant_uid = -1
	state.players[0].arena_hand.assign([gate.id, &"arena_field_fire"])
	var setup: Dictionary = normal.choose_setup(state, [0], false)
	check(setup.get("card_id") == &"arena_field_fire" and setup.get("throw_uid") == 0, "Боец выбирает подходящие ворота и существо")
	state.slots[0].has_card = true
	state.slots[0].card_id = gate.id
	state.slots[0].card_owner = 0
	state.creatures[1].slot = 1
	check(normal._exposure(state, 0, 0) > 0.0, "Угроза учитывает переброс с поля, когда резерв пуст")
	state.creatures[0].def_id = CardDB.RARE_SHADOW_ID
	state.slots[0].card_id = &"arena_dusk_throne"
	check(is_zero_approx(normal._exposure(state, 0, 0)), "Трон сумрака оценивается по исходу, а не только числам силы")
	_test_hidden_field_forecast()
	_test_public_draw_forecast()
	_test_reactive_counters()
	print("AI tactics: %d failures" % failures)
	quit(1 if failures else 0)


func _test_hidden_field_forecast() -> void:
	# Мастер взвешивает нейтральный бой и вероятное открытое Поле защитника.
	# Чужая настоящая карта скрыта; предположение не должно менять переданный вид.
	var state := MatchState.new()
	state.manual_gates = true
	var attacker := CreatureDef.make(&"ai_field_attacker", "attacker", Attr.A.FIRE, 300, Color.WHITE)
	var defender := CreatureDef.make(&"ai_field_defender", "defender", Attr.A.TIDE, 280, Color.WHITE)
	CardDB._creatures[String(attacker.id)] = attacker
	CardDB._creatures[String(defender.id)] = defender
	state.creatures[0] = CreatureState.new(0, attacker.id, 0)
	state.creatures[1] = CreatureState.new(1, defender.id, 1)
	state.players[0].creature_uids.assign([0])
	state.players[1].creature_uids.assign([1])
	state.creatures[1].slot = 0
	state.slots[0].has_card = true
	state.slots[0].card_owner = 1
	state.slots[0].occupant_uid = 1
	var ai := AIPlayer.new(0, 17, -1.0, AIPlayer.Difficulty.HARD)
	check(is_equal_approx(ai._attack_win_prob(state, 0, 1, 0), 1.0), "без известных ворот 300 побеждает 280")
	check(is_zero_approx(ai._attack_win_prob(state, 0, 1, 0, &"arena_field_tide")), "прогноз Поля Прилива учитывает открытие: 300 проигрывает 410")
	check(state.slots[0].card_id == &"" and not state.slots[0].revealed, "прогноз не раскрывает и не меняет неизвестные ворота")


func _forecast_state(attr: int = Attr.A.FIRE) -> MatchState:
	var state := MatchState.new()
	for side in [0, 1]:
		var creature := CreatureDef.make(StringName("ai_counter_%d_%d" % [attr, side]), "counter", attr, 400 if side == 0 else 350, Color.WHITE)
		creature.species = &"dragnar"
		CardDB._creatures[String(creature.id)] = creature
		state.creatures[side] = CreatureState.new(side, creature.id, side)
		state.players[side].creature_uids.assign([side])
	state.creatures[1].slot = 0
	state.slots[0].has_card = true
	state.slots[0].card_id = &"ai_test_gate"
	state.slots[0].card_owner = 0
	state.slots[0].occupant_uid = 1
	state.slots[0].revealed = true
	return state


func _test_public_draw_forecast() -> void:
	var ai := AIPlayer.new(0, 41, -1.0, AIPlayer.Difficulty.HARD)
	# Полностью перечислимый пример: два ID в каждом классе, красный a уже сыгран.
	# До добора остаются только синий/зелёный; после одного добора 8 из 16
	# одинаково вероятных старт+добор историй содержат в руке вторую красную.
	var groups: Array = [[&"red_b"], [&"blue_a", &"blue_b"], [&"green_a", &"green_b"]]
	var known: Array[int] = [1, 0, 0]
	var before: Dictionary = ai._hidden_card_odds(groups, known, {&"red_b": true}, 2)
	var drawn: Dictionary = ai._hidden_card_odds(groups, known, {&"red_b": true}, 3)
	check(is_zero_approx(before.any), "до добора сыгранная стартовая красная исчерпывает красный слот")
	check(is_equal_approx(drawn.any, 0.5) and is_equal_approx(drawn.share, 1.0 / 6.0), "после добора вторая красная возможна: точный пример 8/16")
	check(is_equal_approx(ai._hidden_card_odds(groups, known, {&"red_b": true}, 5).any, 1.0), "исчерпанный запас делает оставшийся ответ достоверным")
	check(is_zero_approx(ai._hidden_card_odds(groups, known, {&"red_b": true}, 0).any), "пустая скрытая рука не отвечает")
	var state := _forecast_state()
	state.players[1].abilities_used.assign([&"ability_fire_drain"])
	state.players[1].ability_hand.assign([&"", &"", &""])
	var pool: Array = ai._foe_pool(state, 1)
	check(not pool[0].has(&"ability_fire_drain") and pool[0].has(&"ability_fire_counter"), "использованный ID исключается, другой красный после добора остаётся в пуле")
	var preview := PowerCalc.compute_seq(state, 0, 1, 0, [])
	var probability: float = ai._flip_prob(state, preview, 0)
	check(probability > 0.0 and probability < 1.0, "после добора скрытая рука имеет ненулевой ограниченный риск ответа")
	state.players[1].ability_hand.assign([&"ability_fire_spark", &"ability_fire_assault", &"ability_fire_ash"])
	check(is_equal_approx(ai._flip_prob(state, preview, 0), probability), "прогноз не читает настоящие ID чужой руки")
	var masked := state.duplicate_view(0)
	check(masked.players[1].ability_hand == [&"", &"", &""] and is_equal_approx(ai._flip_prob(masked, preview, 0), probability), "маскированный вид даёт тот же прогноз")
	state.players[1].ability_hand.clear()
	check(is_zero_approx(ai._flip_prob(state, preview, 0)), "размер пустой руки обнуляет прогноз ответа")
	# После одной захваченной бронзы и одного добора у врага могут быть другие бронзовые.
	state.players[0].captured.assign([&"arena_mirror"])
	state.players[1].arena_hand.assign([&"", &""])
	state.slots[0].card_owner = 1
	state.slots[0].revealed = false
	state.slots[0].card_id = &"arena_clash"
	var trap: float = ai._foe_trap_prob(state)
	check(trap > 0.0 and trap < 1.0, "захват бронзы не обнуляет риск другой ловушки после добора")
	state.slots[0].card_id = &"arena_field_fire"
	check(is_equal_approx(ai._foe_trap_prob(state), trap), "оценка ловушки не читает ID закрытых ворот даже из полного состояния")
	check(is_equal_approx(ai._foe_trap_prob(state.duplicate_view(0)), trap), "публичный вид сохраняет оценку ловушки")
	state.players[1].arena_hand.resize(1)
	check(is_zero_approx(ai._foe_trap_prob(state)), "без добора известная стартовая бронза исчерпана")
	state.players[0].arena_hand.assign([&"arena_limit"])
	ai._remember_gates(state)
	check(ai._my_gates.has("arena_limit"), "свои ворота из позднего добора тоже запоминаются")


func _test_reactive_counters() -> void:
	var counters: Array[StringName] = [&"ability_fire_counter", &"ability_gale_rebuttal", &"ability_light_counter", &"ability_stone_counter", &"ability_shadow_counter", &"ability_tide_counter"]
	for attr in range(counters.size()):
		var state := _forecast_state(attr)
		state.players[0].ability_hand.assign([counters[attr]])
		var ai := AIPlayer.new(0, 47, -1.0, AIPlayer.Difficulty.HARD)
		var empty := PowerCalc.compute_seq(state, 0, 1, 0, [])
		check(not ai._forecast_legal(state, empty, counters[attr], 0), "реакция не прогнозируется без существующей цели %d" % attr)
		var boosted := PowerCalc.compute_seq(state, 0, 1, 0, [[1, &"ai_test_enemy_boost"]])
		check(ai._forecast_legal(state, boosted, counters[attr], 0), "реакция допустима против действующего усиления %d" % attr)
		check(boosted.winner_uid == 1 and ai._with_card(state, boosted, counters[attr], 0).winner_uid == 0, "общий PowerCalc учитывает выигрыш отменой без бонуса %d" % attr)
		check(ai.choose_ability(state, boosted, [counters[attr]]) == counters[attr], "Мастер использует доступную выигрышную реакцию %d" % attr)
		var sure := PowerCalc.compute_seq(state, 0, 1, 0, [[1, &"ability_fire_spark"]])
		check(not ai._forecast_legal(state, sure, counters[attr], 0), "неотменяемая карта не даёт ложную цель реакции %d" % attr)
	var state := _forecast_state(Attr.A.TIDE)
	var ai := AIPlayer.new(0, 53, -1.0, AIPlayer.Difficulty.HARD)
	state.players[0].ability_hand.assign([&"ability_tide_counter"])
	var hush := PowerCalc.compute_seq(state, 0, 1, 0, [[1, &"ability_tide_hush"]])
	check(hush.silenced[0] and ai._forecast_legal(state, hush, &"ability_tide_counter", 0), "общий контракт разрешает прогноз реакции именно на активную Тишь")
	check(ai.choose_ability(state, hush, [&"ability_tide_counter"]) == &"ability_tide_counter", "Мастер отвечает на Тишь выигрышной реакцией")
	check(ai._foe_plays_left(state, hush, 1) > 0 and ai._flip_prob(state, hush, 1) > 0.0, "прогноз защитника учитывает скрытый контрответ на свою Тишь")
	state.slots[0].card_id = &"arena_mute"
	state.slots[0].card_owner = 1
	var sealed := PowerCalc.compute_seq(state, 0, 1, 0, [[1, &"ability_tide_hush"]])
	check(not ai._forecast_legal(state, sealed, &"ability_tide_counter", 0) and ai._foe_plays_left(state, sealed, 1) == 0, "реакция не обходит Глухие врата в прогнозе ИИ")
	state.slots[0].card_id = &"ai_test_gate"
	var locked := PowerCalc.compute_seq(state, 0, 1, 0, [[1, &"ai_test_enemy_boost"], [0, &"ability_levian_coil"]])
	check(not ai._forecast_legal(state, locked, &"ability_tide_counter", 0), "свой lockout запрещает реакцию")
	var unlocked := PowerCalc.compute_seq(state, 0, 1, 0, [[1, &"ai_test_enemy_boost"], [0, &"ability_levian_coil"], [1, &"ability_tide_counter"]])
	check(ai._forecast_legal(state, unlocked, &"ability_tide_counter", 0), "отмена lockout вновь разрешает прогноз реакции")
	state = _forecast_state(Attr.A.STONE)
	var copied := PowerCalc.compute_seq(state, 0, 1, 0, [[1, &"ability_levian_coil"], [0, &"ability_stone_copy"]])
	check(not ai._forecast_legal(state, copied, &"ability_stone_counter", 0), "прогноз соблюдает унаследованный Копией lockout")
