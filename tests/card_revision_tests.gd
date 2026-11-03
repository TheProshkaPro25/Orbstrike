extends "res://tests/rules_edge_tests.gd"
## CARD-01–CARD-10: узкие регрессии без массовой серии матчей.
const STRIP := &"ability_levian_abyss"
const SHELL := &"ability_rogozhuk_shell"
const RESET := &"ability_kolossar_reset"
const COIL := &"ability_levian_coil"
const COPY := &"ability_stone_copy"
const SHIFT := &"ability_stone_shift"

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	_add_test_creatures()
	_test_ordered_cuts()
	_test_shift_outcomes()
	_test_shift_revival()
	_test_swap_budget()
	_test_cancel_dependencies()
	_test_reactive_counters()
	_test_copied_price_and_revive_cycle()
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
	print("CARD contracts: %d проверок, %d ошибок" % [_checks, _failures])
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

func _test_shift_revival() -> void:
	for already_open in [false, true]:
		var ctrl := _manual_battle([SHIFT, PLUS], [PLUS])
		ctrl.state.creatures[0].def_id = GR
		# Двое живых против трёх: прикреплённый «Гнев гор» даёт +180 до воскрешения.
		ctrl.state.creatures[0].attached = [[0, &"ability_stone_wrath"]]
		ctrl.state.creatures[2].alive = false
		for slot in [0, 4]:
			_set_card(ctrl, slot, NEUTRAL, 1) # единственная своя свободная цель — Зов
		_set_card(ctrl, 2, &"arena_fallen_call", 0)
		ctrl.state.slots[2].revealed = already_open
		var before := ctrl.state.duplicate_full()
		var predicted := PowerCalc.compute_with(ctrl.state, 0, 5, 1, [], 0, SHIFT)
		_check(not ctrl.state.creatures[2].alive and ctrl.state.slots[2].revealed == already_open, "оценка Сдвига не воскрешает в исходном состоянии")
		_check(ctrl.play_ability(0, SHIFT) == OK, "Сдвиг на Зов павших принят")
		var actual := ctrl.get_battle_preview()
		_check(ctrl.state.slots[1].card_id == &"arena_fallen_call" and ctrl.state.slots[1].revealed, "Зов павших оказался открытым под боем")
		_check(ctrl.state.creatures[2].alive != already_open, "только первое открытие Зова воскрешает")
		_check(actual.powers == predicted.powers and actual.winner_uid == predicted.winner_uid, "воскрешение и условное усиление: предпросмотр совпал с контроллером")
		_check(actual.powers[0] == 450 + (180 if already_open else 0), "после воскрешения Гнев гор больше не действует")
		if not already_open:
			_check(ctrl.state.creatures[2].used and ctrl.state.creatures[2].slot == -1, "воскрешённый возвращён в использованные")
		_check(before.slots[1].occupant_uid == ctrl.state.slots[1].occupant_uid, "воскрешение не перемещает бойцов")

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

func _test_swap_budget() -> void:
	for incoming in [1, 2, 3]:
		var ctrl := _manual_battle([&"ability_gale_swap", PLUS], [PLUS])
		ctrl.state.creatures[0].def_id = VI
		# Сильнейший резерв — Камень; Свет занят на других воротах и не может заменить.
		_stand(ctrl, 1, 3)
		ctrl.state.creatures[0].attached = [[0, PLUS]]
		ctrl._b_count[0] = 1
		for stamp in incoming:
			ctrl.state.creatures[2].attached.append([stamp + 1, PLUS])
		var before := ctrl.state.duplicate_full()
		var allowed: bool = incoming == 1
		_check(ctrl.legal_abilities(0).has(&"ability_gale_swap") == allowed, "подмена учитывает старые карты + себя + резерв")
		if not allowed:
			_check(ctrl.ability_unavailable_reason(0, &"ability_gale_swap").contains("лимит"), "причина запрета подмены объясняет лимит")
			_check(ctrl.play_ability(0, &"ability_gale_swap") != OK and ctrl.state.players[0].ability_hand.has(&"ability_gale_swap"), "запрещённая подмена не расходует карту")
		else:
			var predicted := PowerCalc.compute_with(ctrl.state, 0, 5, 1, [], 0, &"ability_gale_swap")
			_check(ctrl.play_ability(0, &"ability_gale_swap") == OK, "подмена ровно на три карты разрешена")
			var actual := ctrl.get_battle_preview()
			_check(actual.ability_counts == predicted.ability_counts and actual.ability_counts[0] == 3, "счётчик расхода един для предпросмотра и контроллера")
			var ai := AIPlayer.new(0, 1, -1.0, AIPlayer.Difficulty.HARD)
			_check(ai._my_plays_left(ctrl.get_view(0), actual, 0) == 0, "ИИ не прогнозирует четвёртую карту после подмены")
			_check(ctrl._b_count[0] == 3 and actual.attacker_uid == 2, "старое прикрепление не освобождает место в лимите")
			_check(actual.powers == predicted.powers and actual.attacker_uid == predicted.attacker_uid, "подмена: контроллер и прогноз используют одинаковую допустимую замену")
			_check(ctrl.state.creatures[0].attached == before.creatures[0].attached, "прикрепление ушедшего бойца сохранено")
	# Сильнейший резерв не подходит по лимиту — берём следующего допустимого, не четвёртую карту.
	var fallback := _manual_battle([&"ability_gale_swap", PLUS], [PLUS])
	fallback.state.creatures[0].def_id = VI
	fallback.state.creatures[2].attached = [[0, PLUS], [1, PLUS], [2, PLUS]]
	var preview := PowerCalc.compute_with(fallback.state, 0, 5, 1, [], 0, &"ability_gale_swap")
	_check(fallback.play_ability(0, &"ability_gale_swap") == OK and fallback.get_battle_preview().attacker_uid == 1, "подмена выбирает сильнейшего из допустимых резервов")
	_check(fallback.get_battle_preview().attacker_uid == preview.attacker_uid, "прогноз тоже исключил переполненный резерв")

# CARD-15: обе стороны зависимости отмены/Тиши и полноценная контригра.
func _test_cancel_dependencies() -> void:
	var s := _anime(&"creature_klykar_tide", &"creature_klykar_tide", NEUTRAL)
	var hush := &"ability_tide_hush"
	var spray := &"ability_tide_spray"
	var bite := &"ability_klykar_bite"
	var r := _powers(s, [[0, hush], [0, spray], [1, bite]], [460, 360], "подавленная Хватка не оставляет отмену Брызг")
	_check(r.cancelled_plays == [[1, bite]], "отменена только подавленная Хватка")
	r = _powers(s, [[0, hush], [1, bite]], [310, 360], "Хватка может отменить саму Тишь")
	_check(not r.silenced[1] and r.cancelled_plays == [[0, hush]], "отмена Тиши снимает запрет")
	r = _seq(s, [[0, hush], [0, spray], [1, bite], [0, bite]])
	_check(not r.cancelled_plays.has([0, spray]), "отмена подавленной отмены не гасит исходную карту")
	# Законная цепь с временно снятой Тишью: отмена реакции восстанавливает Тишь,
	# мгновенный перенос уже выполнен, но его поздняя сила подавляется.
	var ctrl := _manual_battle([&"ability_stone_counter", SHIFT, PLUS], [&"ability_tide_spray", &"ability_tide_counter"])
	ctrl.state.creatures[0].def_id = GR
	_set_card(ctrl, 2, &"arena_field_stone", 0)
	ctrl._b_plays = [[1, hush]]
	ctrl._b_count[1] = 1
	_check(ctrl.play_ability(0, &"ability_stone_counter") == OK, "реакция временно снимает Тишь перед Сдвигом")
	_check(ctrl.play_ability(1, spray) == OK, "соперник усиливается между реакциями")
	_check(ctrl.play_ability(0, SHIFT) == OK, "Сдвиг законно выполнен при снятой Тиши")
	var after_shift := ctrl.state.slots[2].card_id
	var results: Array = []
	ctrl.battle_resolved.connect(func(result: BattleResult) -> void: results.append(result))
	_check(ctrl.play_ability(1, &"ability_tide_counter") == OK, "контрреакция восстанавливает прежнюю Тишь")
	_check(not results.is_empty() and results[0].cancelled_plays.has([0, SHIFT]), "восстановленная Тишь гасит силу Сдвига")
	_check(ctrl.state.slots[2].card_id == after_shift, "восстановленная Тишь не откатывает выполненное перемещение")
	# Подавленное позднее прикрепление не отвлекает ответ от настоящей активной цели.
	var with_hidden_target := _anime(&"creature_klykar_tide", &"creature_klykar_fire", NEUTRAL)
	var ordered := [[1, &"ability_fire_drain"], [0, hush], [1, &"ability_fire_ash"]]
	var pre := _seq(with_hidden_target, ordered)
	_check(PowerCalc.reactive_target(pre, 0).id == &"ability_fire_drain", "подсказка цели пропускает подавленный Пепел")
	ordered.append([0, &"ability_tide_counter"])
	var reacted := _seq(with_hidden_target, ordered)
	_check(reacted.cancelled_plays.has([1, &"ability_fire_drain"]) and reacted.cancelled_plays.has([1, &"ability_fire_ash"]), "реальная реакция также пропускает подавленную цель")
	_check(reacted.powers == [410, 320], "реакция отменяет действующий Жар, Тишь сохраняет свои +50")
	# Больше одной Тиши с разных сторон и отмены: детерминизм, исходное состояние сохранено.
	var plays := [[0, hush], [1, hush], [0, bite], [1, bite]]
	var first := _seq(s, plays)
	_check(first.to_log_string() == _seq(s, plays).to_log_string(), "зависимости отмен детерминированы")


func _test_reactive_counters() -> void:
	var ids := [&"ability_fire_counter", &"ability_gale_rebuttal", &"ability_light_counter", &"ability_stone_counter", &"ability_shadow_counter", &"ability_tide_counter"]
	var names: Dictionary = {}
	for id in CardDB.arena_ids() + CardDB.ability_ids():
		_check(not names.has(id), "ID каталога уникален: " + String(id))
		names[id] = true
	for attr in range(6):
		var counter: StringName = ids[attr]
		var c := CardDB.card(counter)
		_check(c != null and CardDB.card_class(c) == &"red" and CardEffects.lock_attr(c) == attr, "отмена доступна каждой стихии в том же слоте")
		var s := _anime(&"creature_klykar_tide", &"creature_klykar_tide", NEUTRAL)
		var base := _seq(s, [])
		var no_target := _seq(s, [[0, counter], [1, &"ability_tide_spray"]])
		_check(no_target.powers == [360, 410], "реакция не ловит будущую карту и не добавляет силу")
		var r := _seq(s, [[1, &"ability_tide_spray"], [0, counter]])
		_check(r.powers == base.powers and r.cancelled_plays == [[1, &"ability_tide_spray"]], "реакция отменяет уже сыгранное усиление")
		r = _seq(s, [[1, &"ability_tide_hush"], [0, counter]])
		_check(r.powers == base.powers and not r.silenced[0] and not r.cancelled_plays.has([0, counter]), "ответная отмена снимает Тишь")
		r = _seq(s, [[1, &"ability_tide_spray"], [0, counter], [1, &"ability_tide_counter"]])
		_check(r.powers == [360, 410] and r.cancelled_plays == [[0, counter]], "контротмена восстанавливает исходную карту")
		r = _seq(s, [[1, &"ability_tide_spray"], [1, &"ability_dragnar_heart"], [0, counter]])
		_check(r.powers == base.powers and r.cancelled_plays.has([1, &"ability_dragnar_heart"]), "реакция на основу гасит слияние, не выбирая его целью")
		r = _seq(s, [[1, &"ability_fire_spark"], [0, counter]])
		_check(not r.cancelled_plays.has([1, &"ability_fire_spark"]), "неотменяемая карта защищена")
		var ctrl := _manual_battle([PLUS, counter], [PLUS])
		ctrl.state.creatures[0].def_id = StringName("creature_dragnar_" + GameData.ATTR_KEYS[attr])
		_check(not ctrl.legal_abilities(0).has(counter), "без цели реакция недоступна")
		_check(ctrl.ability_unavailable_reason(0, counter).contains("действующая"), "отсутствие цели объяснено")
		ctrl._b_plays = [[1, &"ability_tide_hush"]]
		ctrl._b_count[1] = 1
		_check(ctrl.legal_abilities(0).has(counter) and ctrl.ability_unavailable_reason(0, counter).is_empty(), "контроллер разрешает контрответ Тиши")
		var before := ctrl.get_battle_preview()
		var predicted := PowerCalc.compute_with(ctrl.state, 0, 5, 1, ctrl._b_plays, 0, counter)
		_check(ctrl.play_ability(0, counter) == OK, "легальная реакция действительно сыграна")
		_check(not predicted.silenced[0] and predicted.cancelled_plays.has([1, &"ability_tide_hush"]), "PowerCalc предсказывает тот же ответ")
		_check(ctrl._b_count[0] == 1 and not ctrl.state.players[0].ability_hand.has(counter), "отмена расходует карту и место лимита")
		var encoded := OnlineStateCodec.preview(predicted)
		var decoded := OnlineStateCodec.decode_battle(encoded)
		_check(decoded != null and decoded.cancelled_plays == predicted.cancelled_plays and decoded.powers == predicted.powers, "сетевой предпросмотр сохраняет отмену")
		_check(before.silenced[0], "до реакции Тишь действовала")
	# Глухие врата и собственная цена не обходятся реакцией.
	var muted := _manual_battle([PLUS, ids[0]], [PLUS], &"arena_mute", 1)
	muted.state.slots[1].revealed = true
	muted._b_plays = [[1, PLUS]]
	_check(not muted.legal_abilities(0).has(ids[0]), "реакция не обходит Глухие врата")
	var locked := _manual_battle([PLUS, ids[0]], [PLUS])
	locked._b_plays = [[0, COIL], [1, PLUS]]
	_check(not locked.legal_abilities(0).has(ids[0]), "реакция не обходит собственный lockout")
	# Контрпозиция: против неотменяемого усиления красный Жар полезнее реакции;
	# против мощной действующей карты реакция полезнее +100. Нет безусловного превосходства.
	var context := _anime(&"creature_dragnar_fire", &"creature_dragnar_fire", NEUTRAL)
	var response := _seq(context, [[1, &"ability_fire_spark"], [0, ids[0]]])
	var drain := _seq(context, [[1, &"ability_fire_spark"], [0, &"ability_fire_drain"]])
	_check(response.powers[0] - response.powers[1] < drain.powers[0] - drain.powers[1], "цена красного слота: реакция слабее Жара против sure")
	response = _seq(context, [[1, &"ability_dragnar_heart"], [0, ids[0]]])
	# Слияние без основы уже не действует: отмена не извлекает силу из несуществующей цели.
	_check(response.powers[0] == response.powers[1], "нет выгоды от отмены недействующего слияния")


func _test_copied_price_and_revive_cycle() -> void:
	for target in [COIL, RESET]:
		var ctrl := _manual_battle([COPY, &"ability_stone_firm"], [PLUS])
		ctrl.state.creatures[0].def_id = GR
		ctrl.state.active_player = 0
		ctrl._b_turn = 0
		ctrl._b_passed[0] = false
		ctrl._b_plays = [[1, target]]
		ctrl._b_count[1] = 1
		_check(ctrl.play_ability(0, COPY) == OK, "Копия чужого среза разрешена")
		var r := PowerCalc.compute_seq(ctrl.state, ctrl._b_atk, ctrl._b_def, ctrl._b_slot, ctrl._b_plays)
		_check(PowerCalc.side_locked(r, 0), "Копия наследует цену скопированного эффекта")
		ctrl.state.active_player = 0
		ctrl._b_turn = 0
		ctrl._b_passed[0] = false
		_check(ctrl.legal_abilities(0).is_empty(), "после копии среза нельзя играть дальше")
		_check(ctrl.ability_unavailable_reason(0, &"ability_stone_firm").contains("скопированный"), "запрет Копии объяснён")
		ctrl._b_plays.append([1, &"ability_klykar_bite"])
		r = PowerCalc.compute_seq(ctrl.state, ctrl._b_atk, ctrl._b_def, ctrl._b_slot, ctrl._b_plays)
		_check(not PowerCalc.side_locked(r, 0), "отмена Копии снимает унаследованную цену, даже при копировании sure")
	# Две последовательные смерти последнего существа: обычный отдых не даёт повторить спасение.
	var revive := &"ability_light_revive"
	var battle := _manual_battle([revive, PLUS], [PLUS])
	battle.state.creatures[0].def_id = LU
	battle.state.creatures[1].alive = false
	battle.state.creatures[2].alive = false
	battle.state.creatures[5].marks = [{"delta": 1000}]
	_check(battle.play_ability(0, revive) == OK, "последнее существо использует Возрождение")
	_pass_windows(battle)
	_check(battle.state.creatures[0].alive and battle.state.alive_count(0) == 1, "первая смерть спасена")
	_check(not battle.state.players[0].ability_hand.has(revive) and battle.state.players[0].ability_cooldown.get(revive) == 2, "Возрождение не возвращается сразу последнему")
	_set_card(battle, 1, NEUTRAL, 1)
	battle._b_atk = 0
	battle._b_def = 5
	battle._b_slot = 1
	battle._b_plays = []
	battle._b_count = [0, 0]
	battle.state.creatures[5].marks = [{"delta": 1000}]
	battle._resolve()
	_check(battle.state.alive_count(0) == 0 and battle.state.phase == MatchController.Phase.GAME_OVER, "вторая смерть не запускает бесконечное Возрождение")
	for id in [revive, COPY]:
		var ctrl := _manual_battle([PLUS], [PLUS])
		ctrl.state.creatures[1].alive = false
		ctrl.state.creatures[2].alive = false
		ctrl.state.players[0].abilities_used = [id]
		ctrl.state.players[0].ability_cooldown[id] = 3
		for left in [2, 1]:
			ctrl._recharge_abilities()
			_check(not ctrl.state.players[0].ability_hand.has(id) and ctrl.state.players[0].ability_cooldown[id] == left, "спасение/Копия отдыхает положенные бои")
		ctrl._recharge_abilities()
		_check(ctrl.state.players[0].ability_hand.has(id), "спасение/Копия возвращается после обычного отдыха")
