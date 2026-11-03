extends "res://tests/rules_edge_tests.gd"
## CARD-01–CARD-10: узкие регрессии без массовой серии матчей.
const STRIP := &"ability_levian_abyss"
const SHELL := &"ability_rogozhuk_shell"
const RESET := &"ability_kolossar_reset"
const COIL := &"ability_levian_coil"
const COPY := &"ability_stone_copy"
const SHIFT := &"ability_stone_shift"

func _initialize() -> void:
	CardDB.load_all()
	_add_test_creatures()
	_test_ordered_cuts()
	_test_shift_outcomes()
	_test_gate_timing()
	_test_suppression_boundaries()
	_test_fixed_risk()
	_test_recall_scope()
	_test_text_contract()
	# Существующие связанные проверки, без симуляции 200 партий.
	_test_gate_cards()
	_test_species_abilities()
	_test_negate_chain()
	_test_fusion_and_locks()
	_test_silence_and_lockout()
	_test_manual_gates()
	print("CARD-01–CARD-10: %d проверок, %d ошибок" % [_checks, _failures])
	quit(1 if _failures else 0)

func _anime(a: StringName = ZH, b: StringName = VI, gate: StringName = &"arena_field_fire") -> MatchState:
	var s := _mk_state(a, b, gate)
	s.ruleset = MatchRules.Ruleset.ANIME_INSPIRED
	return s

func _powers(s: MatchState, plays: Array, expected: Array, label: String) -> BattleResult:
	var r := _seq(s, plays)
	_check(r.powers == expected, label + ": " + str(r.powers))
	# Каждая строка объяснения складывается в тот же фактический результат.
	var totals := [0, 0]
	for line in r.breakdown:
		totals[int(line.side)] += int(line.delta)
	_check(totals == expected, "разбивка: " + label)
	return r

func _test_ordered_cuts() -> void:
	var s := _anime()
	_powers(s, [[1, STRIP], [0, PLUS], [1, SHELL]], [300, 300], "Пучина → +80 → Панцирь")
	_powers(s, [[1, SHELL], [0, PLUS], [1, STRIP]], [340, 300], "Панцирь → +80 → Пучина")
	_powers(s, [[1, RESET], [0, PLUS], [1, STRIP]], [340, 300], "Сброс → +80 → Пучина")
	_powers(s, [[1, STRIP], [0, PLUS], [1, RESET]], [340, 300], "Пучина → +80 → Сброс")
	_powers(s, [[1, COIL], [0, PLUS], [1, STRIP]], [340, 330], "Кольца → +80 → Пучина")
	_powers(s, [[1, STRIP], [0, PLUS], [1, COIL]], [340, 320], "Пучина → +80 → Кольца")
	_powers(_anime(ZH, VI, &"arena_field_gale"), [[0, COIL], [1, PLUS], [0, STRIP]], [377, 300], "срезы атакующего")
	var copied := _powers(s, [[1, COIL], [0, PLUS], [0, COPY]], [477, 300], "копия Колец в момент копии")
	_check(copied.copies == [[0, COPY, COIL]], "источник копии сохраняется")
	_powers(s, [[1, COIL], [0, PLUS], [0, COPY], [1, SHIELD]], [420, 330], "отмена копии убирает и скопированный срез")
	var copied_attachment := _anime()
	copied_attachment.creatures[1].attached = [[10, COIL]]
	copied_attachment.creatures[0].attached = [[20, PLUS], [30, COPY]]
	_powers(copied_attachment, [], [477, 300], "прикреплённая копия разрешается по своему штампу")
	_powers(s, [[1, STRIP], [0, PLUS], [1, STRIP], [0, SHIELD]], [420, 300], "отмена второго среза")
	_powers(s, [[1, STRIP], [0, PLUS], [1, SHELL], [0, SHIELD]], [300, 300], "неотменяемый второй срез")
	_powers(s, [[0, PLUS], [1, STRIP], [0, &"ability_dragnar_heart"], [1, COIL]], [340, 350], "слияние между срезами")
	var attached := _anime()
	attached.creatures[0].attached = [[20, PLUS]]
	attached.creatures[1].attached = [[10, STRIP], [30, SHELL]]
	var result := _powers(attached, [], [300, 300], "штампы прикреплений обеих сторон")
	_check(result.plays == [[1, STRIP], [0, PLUS], [1, SHELL]], "прикрепления упорядочены по времени")
	_powers(attached, [[0, PLUS], [1, RESET]], [340, 300], "обмен следует после прикреплений")
	# Подавление второго среза должно убрать и его эффект.
	_powers(s, [[1, STRIP], [0, &"ability_tide_hush"], [0, PLUS], [1, STRIP]], [470, 300], "Тишь гасит последующий срез")

func _test_shift_outcomes() -> void:
	# Каменный боец может иметь любую видовую принадлежность; здесь важна стихия соперника Тень.
	var ctrl := _manual_battle([SHIFT, PLUS], [PLUS])
	ctrl.state.creatures[0].def_id = GR
	ctrl.state.creatures[5].def_id = SU
	_set_card(ctrl, 2, &"arena_field_stone", 0) # 600 против 350, но Трон гарантирует поражение
	_set_card(ctrl, 4, &"arena_dusk_throne", 0)
	var before := ctrl.state.duplicate_full()
	_check(PowerCalc.best_gate_swap(ctrl.state, 0, 5, 1, [], 0) == 2, "Сдвиг избегает Трона в пользу числовой победы")
	# Теперь никакие числа не спасают: Трон даёт нашу победу при худшем перевесе.
	ctrl.state.creatures[0].def_id = SU
	ctrl.state.creatures[5].def_id = GR
	_set_card(ctrl, 2, &"arena_altar", 0)
	_set_card(ctrl, 4, &"arena_dusk_throne", 0)
	# Противник усилен так, что ни +80, ни обычные ворота не дают победу.
	var plays: Array = [[1, PLUS], [1, PLUS], [1, PLUS]]
	ctrl._b_plays = plays.duplicate(true)
	_check(PowerCalc.best_gate_swap(ctrl.state, 0, 5, 1, plays, 0) == 4, "Сдвиг предпочитает особую победу числовому перевесу")
	_check(ctrl.state.slots[1].card_id == before.slots[1].card_id and not ctrl.state.slots[4].revealed, "оценка не меняет карты и открытость")
	# Реальная карта Камня: Трон даёт больший числовой перевес, но гарантирует победу чужой Тени.
	ctrl.state.creatures[0].def_id = GR
	ctrl.state.creatures[5].def_id = SU
	ctrl._b_plays.clear()
	_set_card(ctrl, 0, NEUTRAL, 1) # третья свободная карта не принадлежит игроку
	_set_card(ctrl, 2, &"arena_dusk_throne", 0)
	_set_card(ctrl, 4, &"arena_field_shadow", 0)
	var preview := PowerCalc.compute_with(ctrl.state, 0, 5, 1, [], 0, SHIFT)
	_check(ctrl.play_ability(0, SHIFT) == OK, "реальный Сдвиг принимается контроллером")
	var actual := ctrl.get_battle_preview()
	_check(actual != null and actual.powers == preview.powers and actual.winner_uid == preview.winner_uid and actual.auto_win == preview.auto_win, "Сдвиг: предпросмотр и применение совпадают")
	_check(actual != null and actual.winner_uid == 0 and ctrl.state.slots[1].card_id == &"arena_field_shadow" and ctrl.state.slots[1].revealed, "Сдвиг предпочёл обычную победу большему перевесу на проигрышном Троне")
	_check(ctrl.state.creatures[5].slot == 1 and ctrl.state.slots[1].occupant_uid == 5, "Сдвиг не перемещает защитника")
	# +80 Сдвига может превратить поражение в победу: выбор должен учитывать его.
	var s := _anime(GR, SU, NEUTRAL)
	s.creatures[1].marks = [{"delta": 80}]
	for j in [2, 3]:
		s.slots[j].has_card = true
		s.slots[j].card_owner = 0
	s.slots[2].card_id = NEUTRAL
	s.slots[3].card_id = &"arena_dusk_throne"
	_check(PowerCalc.best_gate_swap(s, 0, 1, 0, [], 0) == 2, "+80 учтены в выборе исхода Сдвига")
	s.slots[2].card_id = &"arena_limit"
	_check(PowerCalc.best_gate_swap(s, 0, 1, 0, [], 0) == 3, "ловушка исключена из целей Сдвига")

func _test_gate_timing() -> void:
	for gate in [&"arena_limit", &"arena_clash"]:
		var ctrl := _manual_battle([PLUS], [PLUS], gate)
		ctrl.pass_ability(0)
		_check(ctrl.reveal_gate(1) == OK and ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW, "открытие не завершает бой: " + String(gate))
		_check(ctrl.play_ability(1, PLUS) == OK, "после открытия можно ответить: " + String(gate))
		_pass_windows(ctrl)
		_check(ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW, "итог после пасов: " + String(gate))
	var s := _anime(ZH, VI, &"arena_weight")
	_powers(s, [[0, &"ability_fire_assault"], [0, PLUS]], [420, 300], "Гнёт проверяет порог один раз")
	s = _anime(ZH, VI, &"arena_web")
	s.manual_gates = true
	s.slots[0].revealed = true
	s.slots[2].has_card = true
	s.slots[2].card_id = NEUTRAL
	_powers(s, [], [340, 400], "Сеть считает текущие и закрытые ворота")
	var interrupted := _seq(s, [[0, &"ability_tide_ebb"]])
	_check(interrupted.interrupted and interrupted.relocate_to == 2, "Отлив выбирает первую свободную карту")
	s.slots[0].card_id = &"arena_clash"
	_check(_seq(s, [[0, &"ability_tide_ebb"]]).interrupted, "Отлив прерывает особое обоюдное поражение")
	_check(not _seq(s, [[0, &"ability_tide_ebb"], [1, SHIELD]]).interrupted, "Отлив отменяется до итога")
	s.slots[2].has_card = false
	_check(not _seq(s, [[0, &"ability_tide_ebb"]]).interrupted, "без свободной цели Отлив не действует")
	s.slots[0].card_id = &"arena_hold"
	s.slots[2].has_card = true
	_check(not _seq(s, [[0, &"ability_tide_ebb"]]).winner_stays, "Удержание не отменяет прерывание")
	_check(not _seq(s, [[1, &"ability_shadow_doom"]]).winner_stays, "Удержание не отменяет общую гибель")

func _test_suppression_boundaries() -> void:
	var ctrl := _manual_battle([&"ability_fire_spark", &"ability_light_purge"], [PLUS], &"arena_mute")
	ctrl.state.creatures[0].attached = [[0, PLUS]]
	_check(ctrl.play_ability(0, &"ability_fire_spark") == OK, "неотменяемая карта до открытия")
	_check(ctrl.reveal_gate(1) == OK, "открытие Глухих врат")
	var r := ctrl.get_battle_preview()
	_check(r != null and r.powers[0] == 340 and r.cancelled_plays.has([0, PLUS]) and r.cancelled_plays.has([0, &"ability_fire_spark"]), "Глухие врата гасят прикрепление и прежнюю неотменяемую карту")
	_check(ctrl.legal_abilities(0).is_empty(), "Глухие врата запрещают новые карты")
	# Выполненное мгновенное перемещение остаётся, даже когда бонус карты подавлен.
	var shift := _manual_battle([SHIFT, PLUS], [PLUS], NEUTRAL)
	shift.state.creatures[0].def_id = GR
	_set_card(shift, 2, &"arena_field_stone", 0)
	_check(shift.play_ability(0, SHIFT) == OK, "Сдвиг до подавления")
	# Вражеский владелец моделирует последующее попадание на ловушку; состояние перемещения не откатывается расчётом.
	shift.state.slots[1].card_id = &"arena_mute"
	shift.state.slots[1].card_owner = 1
	var muted := shift.get_battle_preview()
	_check(muted.cancelled_plays.has([0, SHIFT]) and shift.state.slots[2].card_id == NEUTRAL and shift.state.slots[1].occupant_uid == 5, "подавление не откатывает выполненный обмен")
	var fallen := _manual_battle([&"ability_gorgul_gaze", PLUS], [PLUS], &"arena_fallen_call")
	fallen.state.creatures[2].alive = false
	fallen.pass_ability(0)
	fallen.reveal_gate(1)
	_check(fallen.state.creatures[2].alive, "Зов павших воскрешает при открытии")
	fallen.pass_ability(1)
	fallen.state.creatures[0].def_id = SU
	_check(fallen.play_ability(0, &"ability_gorgul_gaze") == OK, "подавление после воскрешения")
	_check(fallen.get_battle_preview().arena_cancelled and fallen.state.creatures[2].alive, "подавление ворот не откатывает воскрешение")
	var hush := _anime(ZH, VI, NEUTRAL)
	hush.creatures[1].attached = [[0, PLUS]]
	_powers(hush, [[0, &"ability_tide_hush"]], [390, 380], "Тишь сохраняет прежние прикрепления")

func _test_fixed_risk() -> void:
	var s := _anime(ZH, VI, &"arena_field_fire")
	s.creatures[0].marks = [{"fix": 440}, {"delta": -50}]
	_powers(s, [[0, PLUS], [1, STRIP]], [440, 300], "ровно 440 после штрафов и среза")
	_powers(s, [[0, PLUS]], [440, 300], "фиксация теряет усиление выше 440")
	s.slots[0].card_id = &"arena_weight"
	_powers(s, [[0, PLUS], [0, &"ability_fire_assault"]], [440, 300], "фиксация после Гнёта")

func _test_text_contract() -> void:
	for id in CardDB.arena_ids() + CardDB.ability_ids():
		var c := CardDB.card(id)
		_check(not c.text.is_empty() and c.text.length() <= 120, "краткий текст до 120: " + String(id))
		_check(UiTheme.card_help(c)[4] == c.full_text(), "подсказка использует полный текст: " + String(id))
	_check(CardDB.card(&"ability_dragnar_rush").details.contains("ровно на 440"), "риск Напора явно описан")
