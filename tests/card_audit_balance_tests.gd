extends "res://tests/card_balance_scenarios.gd"
## Actual controller outcomes complement the preregistered full-match grid.


func actual_gold_role_outcomes() -> void:
	for el in 6:
		var own_id := StringName("creature_gorgul_" + GameData.ATTR_KEYS[el])
		var base: int = CardDB.creature(own_id).base_power
		var field := StringName("arena_field_" + GameData.ATTR_KEYS[el])
		var amount: int = CardDB.card(field).params.amount
		for attack in [false, true]:
			var foe_el := 4 if el == 0 else 0
			if attack:
				for candidate in 6:
					var foe_id := StringName("creature_ratnik_" + GameData.ATTR_KEYS[candidate])
					var foe_base: int = CardDB.creature(foe_id).base_power
					if candidate != el and foe_base >= base and foe_base < base + amount:
						foe_el = candidate
						break
			for gate in [field, &"arena_altar"]:
				var subject := deck(el, gate)
				subject.creatures[2] = CardDB.creature(own_id)
				var ctrl := board(subject, deck(foe_el), gate, 2 if attack else 4, 4 if attack else 2, 0)
				var observed := {"powers": []}
				ctrl.battle_resolved.connect(func(result: BattleResult) -> void: observed.powers = result.powers.duplicate())
				ctrl.state.players[0].ability_hand.clear()
				ctrl.state.players[1].ability_hand.assign([] if attack else [&"ability_ratnik_oath"])
				if not attack: play(ctrl, 1, &"ability_ratnik_oath")
				check(ctrl.reveal_gate(0) == OK, "actualgoldowneropen")
				finish(ctrl)
				var powers: Array = observed.powers
				var won: bool = (gate == field) == attack
				check(ctrl.state.creatures[2].alive == won and ctrl.state.creatures[4].alive != won, "actualgoldrolecounterexample")
				observations.append({"case": "actual_gold_role_outcome", "element": GameData.ATTR_KEYS[el], "attack": attack, "gate": String(gate), "powers": powers, "subject_survived": won})

func all_species_symmetry() -> void:
	for el in 6:
		for definition in GameData.SPECIES:
			var own := StringName("creature_%s_%s" % [definition.id, GameData.ATTR_KEYS[el]])
			var gate := StringName("arena_den_" + definition.id)
			var same := gate_position(own, own, gate, 1)
			var mirrored := PowerCalc.compute_seq(same, 0, 1, 0, [])
			var base: int = CardDB.creature(own).base_power
			check(mirrored.powers == [base * 2, base * 2] and mirrored.winner_uid == 1, "видовые ворота одинаково усиливают оба совпадающих вида")
			var other := &"creature_klykar_light" if definition.id != "klykar" else &"creature_gorgul_light"
			for attack in [false, true]:
				var side := 0 if attack else 1
				var state := gate_position(own, other, gate, side, attack)
				var actual := PowerCalc.compute_seq(state, 0, 1, 0, [])
				state.slots[0].revealed = false
				var closed := PowerCalc.compute_seq(state, 0, 1, 0, [])
				check(actual.powers[side] - closed.powers[side] == base, "видовой бонус равен базовой силе в атаке и защите")
				check(actual.powers[1 - side] == closed.powers[1 - side], "несовпадающий вид не усиливается")
	observations.append({"case": "species_all48", "same_species": "both base x2; tie defender", "mismatched_species": "no bonus", "roles": "attack and defense"})

func actual_conditional_returns() -> void:
	for el in 6:
		var target := StringName("ability_" + RETURNING[el])
		var ctrl := board(deck(el, &"arena_altar", &"arena_funnel", target), deck((el + 2) % 6), &"arena_funnel", 1, 4, 1)
		var last: bool = CardDB.card(target).params.cond == "last"
		ctrl.state.creatures[0].alive = false
		if last: ctrl.state.creatures[2].alive = false
		var recalls: Array = []
		ctrl.abilities_recalled.connect(func(player: int, cards: Array) -> void:
			if player == 0: recalls.append_array(cards))
		play(ctrl, 0, target)
		finish(ctrl)
		check(recalls.count(target) == 1, "реальный сигнал условного возврата один раз")
		check(ctrl.state.creatures[1].alive and not ctrl.state.creatures[4].alive, "условная карта реально выиграла первый бой")
		check(ctrl.state.players[0].ability_hand.has(target) and not ctrl.state.players[0].ability_cooldown.has(target), "реальный возврат без отдыха")
		begin(ctrl, &"arena_funnel", 1, 3, 1)
		check(ctrl.legal_abilities(0).has(target) == last, "после выравнивания числа живых behind закрывается; last остаётся")
		if last: play(ctrl, 0, target)
		finish(ctrl)
		observations.append({"case": "conditional_actual_return", "card": String(target), "first_recall": true, "second_legal": last, "alive": ctrl.state.alive_count(0)})
		for connection in ctrl.get_signal_connection_list(&"abilities_recalled"):
			ctrl.disconnect(&"abilities_recalled", connection.callable)

func actual_recall_two_battles() -> void:
	for enabled in [false, true]:
		var green := &"ability_ratnik_rearm" if enabled else &"ability_ratnik_oath"
		var ctrl := board(deck(0, &"arena_altar", &"arena_funnel", &"", green), deck(2, &"arena_altar", &"arena_funnel", &"ability_light_guard"), &"arena_field_light", 1, 4, 1)
		ctrl.state.slots[1].revealed = true
		var recalled: Array = []
		ctrl.abilities_recalled.connect(func(p: int, cards: Array) -> void:
			if p == 0: recalled.append_array(cards))
		play(ctrl, 0, &"ability_fire_drain")
		play(ctrl, 1, &"ability_light_guard")
		play(ctrl, 0, green)
		finish(ctrl)
		check(recalled.has(&"ability_fire_drain") == enabled, "Второе дыхание имеет фактический recall сигнал")
		check(ctrl.state.alive_count(0) == 3, "recall получен до последнего существа")
		begin(ctrl, &"arena_field_light", 1, 3, 1)
		ctrl.state.slots[1].revealed = true
		play(ctrl, 0, &"ability_fire_drain" if enabled else &"ability_fire_spark")
		finish(ctrl)
		check(ctrl.state.creatures[1].alive == enabled and ctrl.state.creatures[3].alive != enabled, "возврат меняет настоящий исход второго боя")
		observations.append({"case": "recall_actual_two_battles", "enabled": enabled, "recalled": recalled.duplicate(), "second_subject_alive": ctrl.state.creatures[1].alive})
		for connection in ctrl.get_signal_connection_list(&"abilities_recalled"):
			ctrl.disconnect(&"abilities_recalled", connection.callable)

func actual_revive_cooldown() -> void:
	for copy in [false, true]:
		var target := &"ability_stone_copy" if copy else &"ability_light_revive"
		var own_el := 3 if copy else 2
		var foe_el := 2 if copy else 0
		var subject := deck(own_el)
		subject.abilities[0] = CardDB.card(target)
		var foe := deck(foe_el)
		if copy: foe.abilities[0] = CardDB.card(&"ability_light_revive")
		var ctrl := board(subject, foe, StringName("arena_field_" + GameData.ATTR_KEYS[foe_el]), 1, 3, 1)
		ctrl.state.slots[1].revealed = true
		ctrl.state.creatures[0].alive = false
		ctrl.state.creatures[2].alive = false
		ctrl.state.players[0].ability_hand.assign([target])
		ctrl.state.players[1].ability_hand.assign([&"ability_light_revive"] if copy else [])
		var revived: Array = []
		ctrl.creature_revived.connect(func(uid: int) -> void:
			if ctrl.state.creatures[uid].owner == 0: revived.append(uid))
		if copy:
			check(ctrl.pass_ability(0) == OK, "Копия ждёт действующего Возрождения соперника")
			play(ctrl, 1, &"ability_light_revive")
		play(ctrl, 0, target)
		finish(ctrl)
		check(revived == [0] and ctrl.state.alive_count(0) == 1 and not ctrl.state.creatures[1].alive, "реальное спасение проигранного боя через первое погибшее существо")
		check(not ctrl.state.players[0].ability_hand.has(target) and ctrl.state.players[0].ability_cooldown[target] == 2, "бой применения не погасил двухбоевой отдых")
		ctrl.state.players[0].ability_hand.clear()
		ctrl.state.players[1].ability_hand.clear()
		for index in 2:
			begin(ctrl, StringName("arena_field_" + GameData.ATTR_KEYS[own_el]), 0, 3 + index, 0)
			ctrl.state.slots[1].revealed = true
			finish(ctrl)
			check(ctrl.state.players[0].ability_hand.has(target) == (index == 1), "спасение возвращается ровно после двух следующих реальных боёв")
		observations.append({"case": "copy_actual_cooldown" if copy else "revive_actual_cooldown", "revived_uids": revived, "subsequent_battles": 2, "alive": ctrl.state.alive_count(0)})
		for connection in ctrl.get_signal_connection_list(&"creature_revived"):
			ctrl.disconnect(&"creature_revived", connection.callable)

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	gate_tradeoffs()
	actual_gold_role_outcomes()
	all_species_symmetry()
	mute_timing()
	actual_conditional_returns()
	actual_recall_two_battles()
	actual_revive_cooldown()
	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else "user://card-audit-balance-tests.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "отчёт записывается")
	if file != null:
		file.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "observations": observations, "scope": "6 gold role pairs +24actual gold battles,48species x attack/defense/mirror,6 actual conditional returns,2 actual recall sequences,actual revival/copy and cooldown,early/late mute"}, "\t") + "\n")
		file.close()
	print("CARD AUDIT BALANCE TESTS: ", assertions, "/", failures)
	quit(1 if failures else 0)
