extends "res://tests/run_tests.gd"
## Дополнение к регрессиям: реальные розыгрыши всех способностей, пустые запасы и точный повтор матча.

func _initialize() -> void:
	CardDB.load_all()
	_add_test_creatures()
	_test_manual_gates()
	_test_available_abilities()
	_test_empty_resources()
	_test_recall_scope()
	_test_card_contracts()
	_test_trace_replay()
	print("Крайние ситуации и карты: %d проверок, %d ошибок" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_empty_resources() -> void:
	var ctrl := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(1), 707)
	ctrl.landing_window = true
	for p in [0, 1]:
		ctrl.state.players[p].ability_hand.clear()
		ctrl._draw_pools[p] = [[], []]
	ctrl.start()
	var player := ctrl.get_active_player()
	var gate: StringName = ctrl.state.players[player].arena_hand[0]
	var slot := ctrl.legal_setup_slots()[0]
	_check(ctrl.place_arena_card(player, gate, slot) == OK, "ворота без способностей доступны")
	_check(ctrl.select_creature(player, ctrl.legal_creatures(player)[0]) == OK, "выбор при пустой руке способностей")
	ctrl.report_landing(ctrl.get_selected_uid(), slot)
	_check(ctrl.get_phase() != MatchController.Phase.AFTER_LANDING, "пустая рука не оставляет пустое окно прикрепления")
	for p in [0, 1]:
		var count: int = ctrl.state.players[p].arena_hand.size()
		for i in 150:
			ctrl._draw_turn_card(p)
		_check(ctrl.state.players[p].arena_hand.size() == count, "пустой запас не создаёт карты")
	# Нет ворот, рук, запаса и захватов: завершение вместо рекурсии ходов.
	var end := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(1), 708)
	for p in [0, 1]:
		end.state.players[p].arena_hand.clear()
		end._draw_pools[p] = [[], []]
	end.start()
	_check(end.get_phase() == MatchController.Phase.GAME_OVER and end.game_over_reason == &"no_gates", "полное исчерпание ворот завершает матч")
	_test_used_zone_refill()
	_test_no_recall_and_standoff()
	_test_fusion_and_locks()
	_test_silence_and_lockout()
	_test_swap_fighter()
	_test_turn_limit()


func _test_recall_scope() -> void:
	var ctrl := _battle_ctrl([PLUS, &"ability_ratnik_rearm"], [PLUS], NEUTRAL, 1, 1, 710)
	var ps: PlayerState = ctrl.state.players[0]
	ps.abilities_used.append(MINUS)  # карта из предыдущего боя, ещё не отдохнула
	ctrl.play_ability(0, PLUS)
	ctrl.pass_ability(1)
	ctrl.play_ability(0, &"ability_ratnik_rearm")
	_pass_windows(ctrl)
	_check(ps.ability_hand.has(PLUS), "Второе дыхание возвращает карту текущего боя")
	_check(not ps.ability_hand.has(MINUS) and ps.abilities_used.has(MINUS), "Второе дыхание не возвращает карты прежних боёв")


func _test_card_contracts() -> void:
	for id in CardDB.ability_ids():
		var card := CardDB.card(id)
		for side in [0, 1]:
			var ctrl := _battle_ctrl([PLUS, id], [PLUS, id], NEUTRAL, 0, 0, 711)
			# Главный участник подходит замкам проверяемой карты.
			var uid: int = ctrl._b_atk if side == 0 else ctrl._b_def
			for cid in CardDB.creature_ids():
				var def := CardDB.creature(cid)
				if (CardEffects.lock_attr(card) < 0 or def.attribute == CardEffects.lock_attr(card)) and (CardEffects.species_lock(card) == &"" or def.species == CardEffects.species_lock(card)):
					ctrl.state.creatures[uid].def_id = cid
					break
			if CardEffects.is_fusion(card):
				ctrl._b_plays.append([side, PLUS])
				ctrl._b_count[side] = 1
			# Свободные свои ворота нужны для «Сдвига плит».
			ctrl.state.slots[2].has_card = true
			ctrl.state.slots[2].card_id = &"arena_field_stone"
			ctrl.state.slots[2].card_owner = side
			ctrl._b_turn = side
			ctrl.state.active_player = side
			var legal := ctrl.legal_abilities(side).has(id)
			_check(ctrl.ability_unavailable_reason(side, id).is_empty() == legal, "объяснение совпадает с правилами: " + String(id))
			if not legal:
				continue
			var expected := PowerCalc.compute_with(ctrl.state, ctrl._b_atk, ctrl._b_def, ctrl._b_slot, ctrl._b_plays, side, id)
			_check(ctrl.play_ability(side, id) == OK, "карта принимается: " + String(id))
			var actual := ctrl.get_battle_preview()
			_check(actual != null and actual.powers == expected.powers and actual.both_lose == expected.both_lose and actual.interrupted == expected.interrupted, "предпросмотр совпадает с фактическим розыгрышем: " + String(id))
		_check(not card.text.is_empty() and not card.display_name.is_empty(), "описание карты существует")
	# Проверяем в том числе ворота и последствия всеми существующими целевыми сценариями.
	_test_gate_cards()
	_test_element_abilities()
	_test_ladder()
	_test_species_abilities()
	_test_traps_in_match()
	_test_gust()
	_test_shift_gate()
	_test_ebb()
	_test_both_lose()
	_test_hold()
	_test_revive()
	_test_marks()


func _test_trace_replay() -> void:
	var ctrl := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(1), 99117)
	ctrl.landing_window = true
	ctrl.start()
	var ais := [AIPlayer.new(0, 1), AIPlayer.new(1, 2)]
	var target := -1
	for step in 2000:
		var p := ctrl.get_active_player()
		match ctrl.get_phase():
			MatchController.Phase.SETUP:
				var choice: Dictionary = ais[p].choose_setup(ctrl.get_view(p), ctrl.legal_setup_slots(), ctrl.can_skip_gate())
				if choice.is_empty():
					ctrl.skip_gate(p)
				else:
					ctrl.place_arena_card(p, choice.card_id, choice.slot)
			MatchController.Phase.AWAIT_THROW:
				var choice: Dictionary = ais[p].choose_throw(ctrl.get_view(p))
				target = choice.target_slot
				ctrl.select_creature(p, choice.uid)
			MatchController.Phase.AWAIT_LANDING:
				ctrl.report_landing(ctrl.get_selected_uid(), target)
			MatchController.Phase.ABILITY_WINDOW:
				if ctrl.can_reveal_gate(p) and ais[p].should_open_gate(ctrl.get_view(p), ctrl.get_battle_preview()):
					ctrl.reveal_gate(p)
					continue
				var card: StringName = ais[p].choose_ability(ctrl.get_view(p), ctrl.get_battle_preview(), ctrl.legal_abilities(p))
				if card == &"":
					ctrl.pass_ability(p)
				else:
					ctrl.play_ability(p, card)
			MatchController.Phase.AFTER_LANDING:
				ctrl.pass_ability(p)
			MatchController.Phase.GAME_OVER:
				break
	_check(ctrl.get_phase() == MatchController.Phase.GAME_OVER, "точное размещение завершает матч без зависания")
	_check(ctrl.action_trace.any(func(row: Array) -> bool: return row[0] == "reveal_gate"), "запись содержит добровольное открытие ворот")
	var json := JSON.stringify(ctrl.debug_snapshot())
	var replay := MatchReplay.restore(JSON.parse_string(json))
	_check(replay.error.is_empty(), "JSON запись воспроизводится без ошибки")
	if replay.error.is_empty():
		var restored: MatchController = replay.controller
		_check(restored.winner == ctrl.winner and restored.get_turn() == ctrl.get_turn(), "повтор сохраняет победителя и ход")
		_check(restored.state.manual_gates, "повтор сохраняет режим открытия ворот")
		_check(restored.event_log == ctrl.event_log, "повтор сохраняет все события партии")


func _manual_battle(a: Array, b: Array, gate: StringName = NEUTRAL, owner: int = 1) -> MatchController:
	var ctrl := _ctrl([ZH, LU, GR], a, [VI, SU, MA], b, 720)
	ctrl.state.ruleset = MatchRules.Ruleset.ANIME_INSPIRED
	ctrl.state.manual_gates = true
	_set_card(ctrl, 1, gate, owner)
	_check(not ctrl.can_reveal_gate(owner), "вне боя ворота открыть нельзя")
	_check(ctrl.reveal_gate(owner) != OK, "команда открытия вне боя отклоняется")
	_stand(ctrl, 5, 1)
	_throw(ctrl, 0, 0, 1)
	return ctrl


func _test_manual_gates() -> void:
	var ctrl := _manual_battle([PLUS], [PLUS], &"arena_mute")
	_check(not ctrl.state.slots[1].revealed, "бой начинается с закрытыми воротами")
	_check(not _has_event(ctrl, "card_revealed"), "нет автоматического события открытия")
	var before := ctrl.get_battle_preview()
	_check(before.arena_card_id == &"" and not before.silenced[0], "закрытая ловушка не действует и не раскрывает id")
	_check(ctrl.reveal_gate(0) != OK, "чужие ворота открыть нельзя")
	ctrl.pass_ability(0)
	_check(ctrl.can_reveal_gate(1), "владелец может открыть в свой ответ")
	var left := ctrl.abilities_left(1)
	_check(ctrl.reveal_gate(1) == OK, "явная команда владельца открывает ворота")
	_check(ctrl.state.slots[1].revealed and _has_event(ctrl, "card_revealed"), "открытие создаёт событие")
	_check(ctrl.abilities_left(1) == left, "открытие не тратит способность")
	_check(ctrl.get_battle_preview().silenced[0], "ловушка действует после открытия")
	_check(ctrl.reveal_gate(1) != OK, "повторно открыть нельзя")
	var empty := _manual_battle([PLUS], [], NEUTRAL)
	empty.pass_ability(0)
	_check(empty.get_phase() == MatchController.Phase.ABILITY_WINDOW and empty.can_reveal_gate(1), "пустая рука не лишает выбора открытия")
	empty.pass_ability(1)
	_check(empty.get_phase() != MatchController.Phase.ABILITY_WINDOW, "можно завершить бой, оставив ворота закрытыми")
	var bonus := _manual_battle([PLUS], [PLUS], &"arena_field_tide")
	bonus.pass_ability(0)
	var closed_power: int = bonus.get_battle_preview().powers[1]
	bonus.reveal_gate(1)
	_check(bonus.get_battle_preview().powers[1] > closed_power, "бонус ворот появляется лишь после решения владельца")

	var shift := _manual_battle([PLUS, &"ability_stone_shift"], [PLUS])
	shift.state.creatures[0].def_id = GR
	_set_card(shift, 2, &"arena_field_stone", 0)
	var original := shift.state.slots[1].card_id
	_check(PowerCalc.best_gate_swap(shift.state, 0, 5, 1, [], 0) == 2, "Сдвиг плит выбирает выгоднейшие из закрытых ворот")
	_check(not shift.state.slots[1].revealed and shift.state.slots[1].card_id == original and not shift.state.slots[2].revealed, "оценка сдвига не меняет состояние закрытых ворот")
	var expected := PowerCalc.compute_with(shift.state, 0, 5, 1, [], 0, &"ability_stone_shift")
	_check(shift.play_ability(0, &"ability_stone_shift") == OK, "доступный Сдвиг плит сыгран")
	_check(shift.state.slots[1].revealed and shift.state.slots[1].card_id == &"arena_field_stone" and shift.get_battle_preview().powers == expected.powers, "результат Сдвига совпадает с предпросмотром при ручных воротах")


func _test_available_abilities() -> void:
	var coil := _battle_ctrl([PLUS, SHIELD, MINUS], [&"ability_levian_coil", PLUS, MINUS], NEUTRAL, 0, 2, 721)
	coil.play_ability(0, PLUS)
	coil.play_ability(1, &"ability_levian_coil")
	coil.play_ability(0, SHIELD)
	_check(coil.get_active_player() == 1 and coil.legal_abilities(1).has(PLUS), "отменённые Кольца глубин не запрещают доступную карту")
	_check(coil.ability_unavailable_reason(1, PLUS).is_empty() and coil.play_ability(1, PLUS) == OK, "доступная карта реально принимается после отмены блокировки")
	var fusion := _battle_ctrl([PLUS, &"ability_dragnar_heart", MINUS], [SHIELD, PLUS], NEUTRAL, 0, 0, 722)
	fusion.play_ability(0, PLUS)
	fusion.play_ability(1, SHIELD)
	_check(not fusion.legal_abilities(0).has(&"ability_dragnar_heart"), "слияние не подсвечивается поверх отменённой основы")
	_check(not fusion.ability_unavailable_reason(0, &"ability_dragnar_heart").is_empty(), "слияние объясняет отсутствие действующей основы")
	var cond := _battle_ctrl([PLUS, &"ability_fire_last"], [PLUS], NEUTRAL, 0, 0, 723)
	_check(not cond.legal_abilities(0).has(&"ability_fire_last"), "условное усиление не подсвечивается, когда дало бы ноль")
	_check(cond.ability_unavailable_reason(0, &"ability_fire_last").contains("последнего"), "показана конкретная причина")
	for uid in [1, 2]: cond.state.creatures[uid].alive = false
	_check(cond.legal_abilities(0).has(&"ability_fire_last"), "карта становится доступной при выполнении условия")
	var old: int = cond.get_battle_preview().powers[0]
	_check(cond.play_ability(0, &"ability_fire_last") == OK and cond.get_battle_preview().powers[0] == old + 200, "доступное условное усиление действительно даёт +200")
