extends "res://tests/elemental_cards_tests.gd"
## Локальные видовые карты, их выбор и победный переход через команды матча.

const FLORIS := &"creature_floris_gale"
const OCTO := &"creature_octo_tide"
const GARDEN := &"arena_den_floris"
const GROTTO := &"arena_den_octo"
const ROOT_GUARD := &"ability_floris_root_guard"
const GRAB := &"ability_octo_tentacle_grab"
const SWAP := &"ability_gale_swap"


func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	_add_test_creatures()
	call_deferred("_run_species_cards")


func _run_species_cards() -> void:
	_test_local_pools()
	_test_grab_replay()
	_test_symmetric_gates()
	_test_root_guard()
	_test_grab_choices()
	_test_grab_outcomes()
	_test_grab_sluice_and_copy()
	await _test_grab_ui_and_ai()
	print("Species cards: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_local_pools() -> void:
	for pair in [[GARDEN, ROOT_GUARD, &"floris"], [GROTTO, GRAB, &"octo"]]:
		for index in range(2):
			var card := CardDB.card(pair[index])
			var cls: StringName = &"silver" if index == 0 else &"green"
			_check(CardDB.card_class(card) == cls, "класс локальной карты " + String(card.id))
			_check(CardDB.cards_of(index, cls, Attr.A.FIRE, [pair[2]], CardDB.Pool.SPECIES).has(card.id), "локальный выбор по виду для любой стихии")
			_check(not CardDB.cards_of(index, cls, Attr.A.FIRE, [&"dragnar"], CardDB.Pool.SPECIES).has(card.id), "фильтр чужого вида")
			_check(not CardDB.cards_of(index, cls, Attr.A.FIRE, [pair[2]], CardDB.Pool.ELEMENTAL).has(card.id), "правила 2 сохраняют прежний пул")
			_check(not CardDB.cards_of(index, cls, Attr.A.FIRE, [pair[2]], CardDB.Pool.BASE).has(card.id), "базовый пул без новой карты")
	var deck := CardDB.build_deck([OCTO, &"creature_gorgul_tide", &"creature_ratnik_tide"],
		[&"arena_field_tide", GROTTO, &"arena_mirror"], [&"ability_tide_hush", &"ability_tide_surf", GRAB])
	var ids := Tournament.deck_ids(deck)
	_check(CardDB.deck_error(ids[0], ids[1], ids[2], CardDB.Pool.SPECIES).is_empty(), "колода Окто принимает оба слота")
	_check(not CardDB.deck_error(ids[0], ids[1], ids[2], CardDB.Pool.ELEMENTAL).is_empty(), "старый набор отвергает новую колоду")
	var cup := Tournament.create(deck, AIPlayer.Difficulty.NORMAL, 42, "Окто", "", CardDB.Pool.SPECIES)
	_check(cup != null and Tournament.from_dict(cup.state).get("error") == "", "сохранение нового турнира")
	var saved := Campaign.create(deck, AIPlayer.Difficulty.NORMAL, 42, "Окто", "", CardDB.Pool.SPECIES)
	_check(saved != null and saved.cup.card_pool() == CardDB.Pool.SPECIES, "новая кампания фиксирует пул")
	for pool in [CardDB.Pool.BASE, CardDB.Pool.ELEMENTAL, CardDB.Pool.SPECIES]:
		var ctrl := MatchController.new(CardDB.build_deck(ids[0], [&"arena_field_tide", &"arena_den_ratnik", &"arena_mirror"],
			[&"ability_tide_hush", &"ability_tide_surf", &"ability_ratnik_oath"]), CardDB.preset_deck(0),
			42, MatchRules.Ruleset.ANIME_INSPIRED, pool)
		_check(ctrl._draw_pools[0][0].has(GROTTO) == (pool == CardDB.Pool.SPECIES) and ctrl._draw_pools[0][1].has(GRAB) == (pool == CardDB.Pool.SPECIES), "пул добора " + str(pool))
		var restored := MatchReplay.restore(JSON.parse_string(JSON.stringify(ctrl.debug_snapshot())))
		_check(restored.error.is_empty() and restored.controller.state.card_pool == pool and restored.controller._draw_pools == ctrl._draw_pools, "совместимый повтор с исходным добором " + str(pool))
	var career := Career.create("tide", AIPlayer.Difficulty.NORMAL, 42, "Окто", "")
	_check(career.price(String(GROTTO)) == 200 and career.price(String(GRAB)) == 200, "обе карты Окто в магазине по обычной цене класса")
	_check(career.start_cup(career.starter_deck(), {}, CardDB.Pool.SPECIES) == OK and Career.from_dict(JSON.parse_string(JSON.stringify(career.state))).get("error") == "", "сохранение нового кубка карьеры")


func _test_grab_replay() -> void:
	var deck := CardDB.build_deck([OCTO, &"creature_gorgul_tide", &"creature_ratnik_tide"],
		[&"arena_field_tide", GROTTO, &"arena_mirror"], [&"ability_tide_hush", &"ability_tide_surf", GRAB])
	var ctrl := MatchController.new(deck, CardDB.preset_deck(0), 510, MatchRules.Ruleset.ANIME_INSPIRED, CardDB.Pool.SPECIES)
	ctrl.state.creatures[0].base_power_override = 420
	ctrl.start()
	_check(ctrl.place_arena_card(0, &"arena_field_tide", 1) == OK, "карта боя в повторе")
	_throw(ctrl, 0, 1, -1)
	_check(ctrl.place_arena_card(1, &"arena_field_fire", 4) == OK, "ход противника в повторе")
	_throw(ctrl, 1, 3, 1)
	_check(ctrl.throw_with_gate(0, GROTTO, 0, 0) == OK, "закрытая цель перехода в повторе")
	ctrl.report_landing(0, 1)
	_check(ctrl.play_ability(0, GRAB, {"target_slot": 0}) == OK, "захват с целью записан в повтор")
	_pass_windows(ctrl)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(ctrl.debug_snapshot()))
	var restored := MatchReplay.restore(snapshot)
	_check(restored.error.is_empty() and restored.controller.state.creatures[0].slot == 0
		and restored.controller.state.players[0].captured == [&"arena_field_tide"]
		and not restored.controller.state.slots[0].revealed, "JSON восстанавливает цель, трофей и закрытые ворота")
	snapshot.erase("card_pool")
	_check(not MatchReplay.restore(snapshot).error.is_empty(), "новый набор не читается как старая версия")


func _test_symmetric_gates() -> void:
	for pair in [[FLORIS, GARDEN], [OCTO, GROTTO]]:
		var s := _position(pair[0], pair[0], pair[1])
		s.creatures[0].base_power_override = 305
		s.creatures[1].base_power_override = 336
		for owner in [0, 1]:
			s.slots[0].card_owner = owner
			_powers(s, [], [610, 672], "серебро удваивает базы обеих сторон независимо от владельца")
		s.slots[0].revealed = false
		_powers(s, [], [305, 336], "закрытое серебро не действует")
		var other := _position(pair[0], MA, pair[1])
		_check(_seq(other, []).powers[1] == TEST_POWER[Attr.A.TIDE], "серебро не усиливает другой вид")


func _test_root_guard() -> void:
	var ctrl := _fixture(FLORIS, FLORIS, [ROOT_GUARD, SHIELD], [ROOT_GUARD, SWAP])
	_check(ctrl.select_creature(0, 0) == OK and not ctrl.legal_abilities(0).has(ROOT_GUARD), "заслон не прикрепляется перед броском")
	ctrl.report_landing(0, 1)
	_check(not ctrl.legal_abilities(0).has(ROOT_GUARD), "заслон недоступен атакующему Флорису")
	ctrl.pass_ability(0)
	var before := ctrl.get_battle_preview()
	_play(ctrl, 1, ROOT_GUARD)
	_check(ctrl.get_battle_preview().powers[1] == before.powers[1] + 90, "заслон даёт защитнику ровно +90 G")
	_play(ctrl, 0, SHIELD)
	var cancelled := ctrl.get_battle_preview()
	_check(cancelled.cancelled_plays.has([1, ROOT_GUARD]) and cancelled.powers[1] == before.powers[1], "отмена снимает +90 G")
	_pass_windows(ctrl)
	_check(ctrl.state.players[1].ability_cooldown.get(ROOT_GUARD) == 2, "отменённый заслон отдыхает два боя")
	var swapped := _fixture(FLORIS, FLORIS, [PLUS], [ROOT_GUARD, SWAP])
	_throw(swapped, 0, 0, 1)
	swapped.pass_ability(0)
	_play(swapped, 1, ROOT_GUARD)
	swapped.pass_ability(0)
	_play(swapped, 1, SWAP)
	var result := swapped.get_battle_preview()
	_check(result.defender_uid != 3 and result.ability_count(1) == 2, "подмена сохраняет расход заслона")
	for entry in result.breakdown:
		if entry.source == "ability:" + String(ROOT_GUARD):
			_check(entry.delta == 0, "новый защитник другого вида не получает +90 G")


func _grab_fixture(gate: StringName = NEUTRAL, owner: int = 0) -> MatchController:
	var ctrl := _fixture(OCTO, MA, [GRAB, PLUS], [SHIELD, PLUS], gate, owner)
	ctrl.state.card_pool = CardDB.Pool.SPECIES
	ctrl.state.creatures[0].base_power_override = 540
	_set_card(ctrl, 0, &"arena_fallen_call", 0)
	_set_card(ctrl, 2, GROTTO, 0)
	_set_card(ctrl, 3, NEUTRAL, 0)
	_set_card(ctrl, 4, NEUTRAL, 1)
	_set_card(ctrl, 5, NEUTRAL, 0)
	return ctrl


func _test_grab_choices() -> void:
	var ctrl := _grab_fixture()
	_check(ctrl.select_creature(0, 0) == OK and not ctrl.legal_abilities(0).has(GRAB), "захват недоступен перед броском")
	ctrl.report_landing(0, 1)
	_check(ctrl.legal_ability_targets(0, GRAB) == [{"target_slot": 0}, {"target_slot": 2}], "две соседние пустые свои цели")
	for invalid in [{}, {"target_slot": true}, {"target_slot": 0.2}, {"target_slot": 4}, {"target_slot": 3}, {"target_slot": 5}, {"target_slot": 0, "target_uid": 4}]:
		_check(ctrl.play_ability(0, GRAB, invalid) == ERR_INVALID_PARAMETER, "отклонение цели " + str(invalid))
	_check(ctrl.state.players[0].ability_hand.has(GRAB) and ctrl.get_battle_preview().ability_count(0) == 0, "отказ не тратит карту и действие")
	_stand(ctrl, 1, 2)
	ctrl.state.slots[0].has_card = false
	_check(ctrl.legal_ability_targets(0, GRAB).is_empty() and ctrl.ability_unavailable_reason(0, GRAB).contains("пустые"), "нет цели: занятые, чужие, отсутствующие и диагональные ворота исключены")
	_check(not PowerCalc.adjacent_free_gates(ctrl.state, 2, 0).has(3), "слоты 2 и 3 на разных краях ряда")


func _test_grab_outcomes() -> void:
	for mode in ["win", "cancel", "tie", "loss", "hold", "mute", "stale", "open"]:
		var gate: StringName = &"arena_hold" if mode == "hold" else (&"arena_mute" if mode == "mute" else NEUTRAL)
		var ctrl := _grab_fixture(gate, 1 if mode == "mute" else 0)
		if mode in ["tie", "loss"]:
			ctrl.state.creatures[0].base_power_override = TEST_POWER[Attr.A.TIDE] - int(mode == "loss")
		if mode == "open":
			ctrl.state.slots[0].revealed = true
		ctrl.state.creatures[5].alive = false
		_throw(ctrl, 0, 0, 1)
		if mode == "hold":
			_check(ctrl.reveal_gate(0) == OK, "открывается Удержание до розыгрыша")
		var before := ctrl.get_battle_preview()
		_check(ctrl.play_ability(0, GRAB, {"target_slot": 0}) == OK, "захват сыгран: " + mode)
		_check(ctrl.state.slots[0].occupant_uid < 0 and ctrl.get_battle_preview().powers == before.powers, "выбор не перемещает бойца и даёт +0 G")
		if mode == "cancel":
			_play(ctrl, 1, SHIELD)
		elif mode == "mute":
			_check(ctrl.reveal_gate(1) == OK, "Глухие врата подавляют Захват")
		elif mode == "stale":
			_stand(ctrl, 1, 0)
		var moves := []
		ctrl.creature_relocated.connect(func(uid: int, from: int, to: int) -> void: moves.append([uid, from, to]))
		var result := ctrl.get_battle_preview()
		_pass_windows(ctrl)
		var success: bool = mode in ["win", "open"]
		_check(result.tentacle_slot == (0 if success else -1), "предпросмотр победного перехода " + mode)
		_check(ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW, "переход не начинает обмен " + mode)
		_check(ctrl.state.players[0].ability_cooldown.get(GRAB) == 2, "два боя отдыха " + mode)
		if success:
			_check(moves == [[0, 1, 0]] and ctrl.state.slots[0].occupant_uid == 0 and ctrl.state.creatures[0].slot == 0 and not ctrl.state.creatures[0].used, "ровно одно перемещение на выбранные ворота")
			_check(ctrl.state.slots[0].revealed == (mode == "open") and not ctrl.state.creatures[5].alive, "переход сохраняет статус и не запускает Зов павших")
			_check(ctrl.state.players[0].captured == [gate] and not ctrl.state.slots[1].has_card and not ctrl.state.creatures[3].alive and ctrl.get_active_player() == 0, "сохраняются KO, трофей и ход победителя")
		else:
			_check(moves.is_empty() or mode == "hold", "несработавший захват не даёт переход " + mode)


func _test_grab_sluice_and_copy() -> void:
	var ctrl := _grab_fixture(SLUICE)
	_throw(ctrl, 0, 0, 1)
	_check(ctrl.reveal_gate(0) == OK, "Шлюз открыт")
	_check(ctrl.play_ability(0, GRAB, {"target_slot": 2}) == OK, "цель Захвата отличается от цели Шлюза")
	var preview := ctrl.get_battle_preview()
	_check(preview.sluice_slot == 0 and preview.tentacle_slot == -1 and preview.winner_destination() == 0, "Шлюз даёт один переход с приоритетом")
	_pass_windows(ctrl)
	_check(ctrl.state.creatures[0].slot == 0 and ctrl.state.slots[2].occupant_uid == -1, "цепочки переходов нет")
	var s := _position(OCTO, GR)
	s.creatures[0].base_power_override = 500
	s.slots[1].has_card = true
	s.slots[1].card_id = GROTTO
	s.slots[1].card_owner = 0
	var result := _seq(s, [[0, GRAB, {"target_slot": 1}], [1, COPY]])
	_check(result.copies.is_empty() and result.tentacle_slot == 1, "копия не повторяет Захват")
	for id in [&"ability_tide_ebb", &"ability_shadow_doom"]:
		var special := _seq(s, [[0, GRAB, {"target_slot": 1}], [1, id]])
		_check(not special.ordinary and special.tentacle_slot == -1, "особый исход исключает переход: " + String(id))


func _test_grab_ui_and_ai() -> void:
	var ctrl := _grab_fixture()
	ctrl.state.players[1].ability_hand.clear()
	_throw(ctrl, 0, 0, 1)
	var targets := ctrl.legal_ability_targets(0, GRAB)
	var view := ctrl.get_view(0)
	for difficulty in [AIPlayer.Difficulty.NORMAL, AIPlayer.Difficulty.HARD]:
		var ai := AIPlayer.new(0, 43, -1.0, difficulty)
		var preview := ctrl.get_battle_preview()
		_check(ai.choose_ability(view, preview, ctrl.legal_abilities(0)) == GRAB, "ИИ применяет переход при надёжной победе")
		_check(ai.choose_ability_target(view, preview, GRAB, targets).get("target_slot") == 2, "ИИ ставит Окто на его серебро")
	var picker := AbilityTargetPicker.new()
	root.add_child(picker)
	var sent := []
	picker.chosen.connect(func(value: Dictionary) -> void: sent.append(value))
	picker.show_targets(GRAB, targets, view)
	_check(picker._choices.get_child_count() == 2 and picker._title.text.contains("ворота"), "диалог показывает две цели-ворота")
	var first: VBoxContainer = picker._choices.get_child(0)
	var second: VBoxContainer = picker._choices.get_child(1)
	_check(first.get_child(0).text.contains("Ворота 1") and second.get_child(0).text.contains("Ворота 3"), "различимы номера ворот")
	var back := InputEventMouseButton.new()
	back.button_index = MOUSE_BUTTON_RIGHT
	back.pressed = true
	picker._input(back)
	_check(sent.is_empty() and ctrl.state.players[0].ability_hand.has(GRAB), "закрытие диалога обратимо")
	picker.show_targets(GRAB, targets, view)
	picker._choices.get_child(1).get_child(1).pressed.emit()
	_check(sent == [{"target_slot": 2}], "интерфейс передаёт номер выбранного слота")
	await process_frame
	picker.free()
