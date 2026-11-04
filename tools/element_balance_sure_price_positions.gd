extends SceneTree
## Сопоставление трёх низких sure-blue: только локальная память процесса.
const LOW := [&"ability_fire_spark", &"ability_shadow_haze", &"ability_light_glint"]
var checks := 0
var failures := 0
var observations: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func board(light_side: int, foe: int, gate: StringName) -> MatchState:
	var s := MatchState.new()
	s.ruleset = MatchRules.Ruleset.ANIME_INSPIRED
	s.manual_gates = true
	for p in [0, 1]:
		var uid: int = p * 3
		s.creatures[uid] = CreatureState.new(uid, StringName("sure_price_330_" + str(2 if p == light_side else foe)), p)
		s.players[p].creature_uids.append(uid)
	s.slots[0].has_card = true
	s.slots[0].card_id = gate
	s.slots[0].card_owner = 1
	s.slots[0].occupant_uid = 3
	s.slots[0].revealed = true
	s.creatures[3].slot = 0
	return s

func _initialize() -> void:
	Engine.max_fps = 60
	AudioServer.set_bus_mute(0, true)
	CardDB.load_all()
	for attr in [0, 2, 4]:
		var id := StringName("sure_price_330_" + str(attr))
		var d := CreatureDef.make(id, String(id), attr, 330, Color.WHITE)
		d.species = &"ratnik"
		CardDB._creatures[String(id)] = d
	var normalized: Dictionary = {}
	for id in LOW:
		var card := CardDB.card(id)
		check(card.effect_id == &"boost" and CardDB.card_class(card) == &"blue", "одинаковая базовая механика и класс")
		var params := card.params.duplicate(true)
		params.erase("amount")
		params.erase("lock")
		if normalized.is_empty(): normalized = params
		check(params == normalized and params == {"sure": true}, "кроме цены/стихии нет разных условий и преимуществ")
		check(not CardEffects.returns_to_hand(card) and MatchRules.last_rush_returns(card), "одинаковый обычный отдых и последний рывок")
	var glint := CardDB.card(&"ability_light_glint")
	var original: int = int(glint.params.amount)
	for stage in ["historical50", "proposal30"]:
		glint.params.amount = 50 if stage == "historical50" else 30
		for side in [0, 1]:
			for foe in [0, 4]:
				var rival: StringName = &"ability_fire_spark" if foe == 0 else &"ability_shadow_haze"
				for gate in [&"", &"arena_field_light", StringName("arena_field_" + GameData.ATTR_KEYS[foe]), &"arena_altar"]:
					var state := board(side, foe, gate)
					var raw := PowerCalc.compute_seq(state, 0, 3, 0, [])
					var r := PowerCalc.compute_seq(state, 0, 3, 0, [[side, &"ability_light_glint"], [1-side, rival]])
					check(r.powers[side] == raw.powers[side] + (50 if stage == "historical50" else 30) and r.powers[1-side] == raw.powers[1-side] + 30, "реальные прибавки на нейтральных/стихийных/общих воротах")
					var totals := [0,0]
					for line in r.breakdown: totals[int(line.side)] += int(line.delta)
					check(totals == r.powers, "breakdown объясняет полный итог")
					if gate == &"":
						check(r.winner_uid == (side * 3 if stage == "historical50" else 3), "нейтральная разница20G исчезла; при равенстве выигрывает защитник")
					observations.append({"stage":stage,"light_side":side,"foe":foe,"gate":String(gate),"powers":r.powers,"winner":r.winner_uid})
				var state := board(side, foe, &"")
				var counter := PowerCalc.compute_seq(state, 0, 3, 0, [[side, &"ability_light_glint"], [1-side, &"ability_fire_counter"]])
				check(not counter.cancelled_plays.has([side, &"ability_light_glint"]) and counter.powers[side] == 330 + int(glint.params.amount), "sure сохраняет защиту от реальной отмены")
	glint.params.amount = original
	check(int(glint.params.amount) == original, "текущий runtime-каталог восстановлен")
	var output := FileAccess.open("res://build/checks/element-balance-20261104/sure-price-proposal.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"scope":"Гарантированные низкие blue, равные330G, ANIME, обе стороны, Fire/Shadow, нейтральные/Field/Altar/отмена. Цена Glint50→30 только в памяти процесса. Не серия и не обещание общего winrate."}, "\t"))
	print("SURE PRICE PROPOSAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
