extends SceneTree
## CARD-10: ограниченное сравнение каталога при одинаковом контексте, без серии матчей и изменения чисел.
func state_for(a: StringName, b: StringName, gate: StringName, owner: int) -> MatchState:
	var s := MatchState.new()
	s.ruleset = MatchRules.Ruleset.ANIME_INSPIRED
	s.creatures[0] = CreatureState.new(0, a, 0)
	s.creatures[1] = CreatureState.new(1, b, 1)
	s.players[0].creature_uids.assign([0])
	s.players[1].creature_uids.assign([1])
	s.creatures[1].slot = 0
	s.slots[0].occupant_uid = 1
	s.slots[0].has_card = gate != &""
	s.slots[0].card_id = gate
	s.slots[0].card_owner = owner
	s.slots[0].revealed = true
	return s

func _initialize() -> void:
	CardDB.load_all()
	var rows: Array = []
	for id in CardDB.creature_ids():
		var d := CardDB.creature(id)
		var next_species: String = "klykar" if d.species != &"klykar" else "dragnar"
		var foe := StringName("creature_%s_%s" % [next_species, GameData.ATTR_KEYS[(d.attribute + 3) % 6]])
		var field := StringName("arena_field_" + GameData.ATTR_KEYS[d.attribute])
		var den := StringName("arena_den_" + String(d.species))
		var row := {"creature": String(id), "base": d.base_power, "own_defense": {}, "own_attack": {}, "same_creature_foe": {}}
		for gate in [field, &"arena_altar", den]:
			var defense := PowerCalc.compute_seq(state_for(foe, id, gate, 1), 0, 1, 0, [])
			var attack := PowerCalc.compute_seq(state_for(id, foe, gate, 0), 0, 1, 0, [])
			var symmetric := PowerCalc.compute_seq(state_for(id, id, gate, 1), 0, 1, 0, [])
			row.own_defense[String(gate)] = defense.powers[1] - defense.powers[0] - d.base_power + CardDB.creature(foe).base_power
			row.own_attack[String(gate)] = attack.powers[0] - attack.powers[1] - d.base_power + CardDB.creature(foe).base_power
			row.same_creature_foe[String(gate)] = symmetric.powers[1] - symmetric.powers[0]
		rows.append(row)
	var ability_rows: Array = []
	for ids in [[&"ability_fire_spark", &"ability_fire_assault", &"ability_fire_drain"], [&"ability_light_glint", &"ability_light_guard", &"ability_light_crown"], [&"ability_stone_firm", &"ability_stone_footing", &"ability_stone_copy"]]:
		for id in ids:
			var c := CardDB.card(id)
			var ctx := {"attack": true, "own_gate": true, "my_base": 350, "foe_base": 350, "foe_beats": false, "alive_own": 3, "alive_foe": 3}
			var delta := CardEffects.ability_delta(c, ctx)
			ability_rows.append({"id": String(id), "class": String(CardDB.card_class(c)), "attack_swing": delta.x - delta.y,
				"sure": CardEffects.is_sure(c), "effect": String(c.effect_id), "note": "только прямой эффект; копия и будущие метки здесь не оценены"})
	var report := {"scope": "48 существ, 3 вида ворот, защита/атака владельца/симметричный соперник; 9 прямых эффектов способностей. Без матчей и оценки частоты условий.",
		"ruleset": "ANIME_INSPIRED", "gates": rows, "abilities": ability_rows,
		"limits": "Не доказывает статистический баланс, оптимальность ИИ, вероятность контркарты или ценность возврата. Числа не изменены."}
	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else "user://card-balance.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("FAIL: не записан отчёт CARD-10: ", path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("CARD-10: 48 существ × 9 контекстов ворот, 9 прямых эффектов; отчёт ", path)
	quit(0)
