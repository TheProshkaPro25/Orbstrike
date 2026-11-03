extends "res://tools/card_balance_matches.gd"
## CARD-10: контрольные боевые позиции с настоящими колодами и командами контроллера.
## Расстановка задана явно, это не полные матчи; решения сценарные, не политика ИИ.
var observations: Array = []
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	verify(value, message)

func board(subject: DeckDef, foe: DeckDef, gate: StringName, attacker: int, defender: int, gate_owner: int = 0) -> MatchController:
	var ctrl := MatchController.new(subject, foe, 91031)
	ctrl.landing_window = true
	# Контроль одной позиции: обычные правила обмена, без случайного добора между боями.
	ctrl._draw_pools = [[[], []], [[], []]]
	ctrl.start()
	begin(ctrl, gate, attacker, defender, gate_owner)
	return ctrl

func begin(ctrl: MatchController, gate: StringName, attacker: int, defender: int, gate_owner: int = 1) -> void:
	var slot := ctrl.state.slots[1]
	slot.card_id = gate
	slot.card_owner = gate_owner
	slot.has_card = true
	slot.revealed = false
	slot.occupant_uid = defender
	ctrl.state.creatures[defender].slot = 1
	ctrl.state.creatures[attacker].slot = -1
	ctrl._turn_player = ctrl.state.creatures[attacker].owner
	ctrl._start_battle(attacker, defender, 1)

func play(ctrl: MatchController, player: int, id: StringName) -> void:
	check(ctrl.legal_abilities(player).has(id), "карта разрешена: " + String(id))
	check(ctrl.play_ability(player, id) == OK, "розыгрыш: " + String(id))

func finish(ctrl: MatchController) -> void:
	for step in 8:
		if ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW: break
		check(ctrl.pass_ability(ctrl.get_active_player()) == OK, "пас разрешён")
	check(ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW, "бой завершён")

func recall_pair() -> void:
	for green in [&"ability_ratnik_oath", &"ability_ratnik_rearm"]:
		var ctrl := board(deck(0, &"arena_altar", &"arena_funnel", &"", green), deck(2, &"arena_altar", &"arena_funnel", &"ability_light_guard"), &"arena_field_light", 1, 4, 1)
		ctrl.state.slots[1].revealed = true
		# Ратник Пламени атакует Ратника Света на открытом Поле Света.
		play(ctrl, 0, &"ability_fire_drain")
		play(ctrl, 1, &"ability_light_guard")
		var without_drain := PowerCalc.compute_seq(ctrl.state, 1, 4, 1, [[1, &"ability_light_guard"], [0, green]])
		check(without_drain.winner_uid == 4, "без Пожирающего жара первую защиту не пробить даже с зелёной картой")
		play(ctrl, 0, green)
		finish(ctrl)
		check(ctrl.state.creatures[1].alive and not ctrl.state.creatures[4].alive, "одинаковая победа в первом бою")
		check(ctrl.state.alive_count(0) == 3, "возврат не вызван последним существом")
		var returned := ctrl.state.players[0].ability_hand.has(&"ability_fire_drain")
		check(returned == (green == &"ability_ratnik_rearm"), "Возврат текущего боя отличается от обычной Клятвы")
		# Сразу второй бой: Ратник против свежего Драгнара Света на открытом Поле Света.
		begin(ctrl, &"arena_field_light", 1, 3, 1)
		ctrl.state.slots[1].revealed = true
		var initial := ctrl.get_battle_preview()
		check(initial.winner_uid == 3, "без новой карты второй бой проигрывается")
		if returned: play(ctrl, 0, &"ability_fire_drain")
		else: play(ctrl, 0, &"ability_fire_spark")
		var result := ctrl.get_battle_preview()
		check((result.winner_uid == 1) == returned, "ранний возврат меняет доступный ответ и исход второго боя")
		observations.append({"case": "recall_two_battles", "green": String(green), "returned_before_last_creature": returned, "second_powers": result.powers, "second_winner": result.winner_uid})
		finish(ctrl)

func mute_timing() -> void:
	for late in [false, true]:
		# Противник начинает атаку и может сохранить карту или потратить её до открытия.
		var ctrl := board(deck(0, &"arena_altar", &"arena_mute"), deck(2), &"arena_mute", 3, 1)
		if late: play(ctrl, 1, &"ability_light_glint")
		else: check(ctrl.pass_ability(1) == OK, "ранний пас атакующего")
		var before := ctrl.get_battle_preview()
		check(ctrl.reveal_gate(0) == OK, "владелец открыл Глухие врата")
		var after := ctrl.get_battle_preview()
		check(after != null and after.silenced[0] and after.winner_uid == 1, "ловушка гарантирует этот контрольный исход")
		check(after.cancelled_plays.has([0, &"ability_light_glint"]) == late, "позднее открытие гасит уже потраченную неотменяемую карту")
		observations.append({"case": "mute_timing", "late": late, "before_powers": before.powers, "after_powers": after.powers,
			"opponent_kept_glint": ctrl.state.players[1].ability_hand.has(&"ability_light_glint"), "cancelled": after.cancelled_plays})
		finish(ctrl)

func throne_counters() -> void:
	for counter in [false, true]:
		var foe := deck(2)
		foe.abilities[0] = CardDB.card(&"ability_light_purge")
		var ctrl := board(deck(4, &"arena_altar", &"arena_dusk_throne"), foe, &"arena_dusk_throne", 3, 2)
		check(ctrl.pass_ability(1) == OK, "первый ответ атакующего")
		var before := ctrl.get_battle_preview()
		check(before.winner_uid == 3, "слабый защитник Тени проигрывает без Трона")
		check(ctrl.reveal_gate(0) == OK, "открытие Трона")
		check(ctrl.get_battle_preview().auto_win and ctrl.get_battle_preview().winner_uid == 2, "Трон даёт особую победу")
		if counter:
			play(ctrl, 0, &"ability_shadow_haze") # передаём ответ атакующему, который имеет контркарту
			play(ctrl, 1, &"ability_light_purge")
			check(ctrl.get_battle_preview().arena_cancelled and ctrl.get_battle_preview().winner_uid == 3, "подавление ворот побеждает Трон")
		var result := ctrl.get_battle_preview()
		observations.append({"case": "throne_counter", "counter": counter, "powers": result.powers, "winner": result.winner_uid, "gate_cancelled": result.arena_cancelled})
		finish(ctrl)

func early_return() -> void:
	var blue := &"ability_stone_wrath"
	var ctrl := board(deck(3, &"arena_altar", &"arena_funnel", blue), deck(1), &"arena_funnel", 1, 4, 1)
	ctrl.state.creatures[0].alive = false # два против трёх — условие усиления выполнено
	play(ctrl, 0, blue)
	finish(ctrl)
	check(ctrl.state.alive_count(0) == 2, "ранний возврат при двух существах")
	check(ctrl.state.players[0].ability_hand.has(blue) and not ctrl.state.players[0].ability_cooldown.has(blue), "условная карта возвращена до автоматического возврата последнего существа")
	observations.append({"case": "early_conditional_return", "card": String(blue), "own_alive": ctrl.state.alive_count(0), "foe_alive": ctrl.state.alive_count(1),
		"returned": ctrl.state.players[0].ability_hand.has(blue), "condition_still_met": ctrl.state.alive_count(0) < ctrl.state.alive_count(1)})

func _initialize() -> void:
	CardDB.load_all()
	recall_pair()
	mute_timing()
	throne_counters()
	early_return()
	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else "user://card-balance-scenarios.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	check(f != null, "отчёт записывается")
	if f != null:
		f.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "observations": observations, "scope": "7 контрольных позиций, 9 боёв. Расстановка сценарная; правила, отмены, исходы и возврат через MatchController."}, "\t") + "\n")
		f.close()
	print("CARD-10 контрольные бои: ", assertions, " проверок, ", failures, " ошибок")
	quit(1 if failures else 0)
