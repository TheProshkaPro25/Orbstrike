extends SceneTree
## Предложение цены «против ветра»: только локальная память стенда, не GameData.
const IDS := [&"ability_gale_gust", &"ability_gale_leap", &"ability_gale_swap"]
var checks := 0
var failures := 0
var observations: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func board(gale_side: int, foe_attr: int = Attr.A.FIRE) -> MatchState:
	var state := MatchState.new()
	state.ruleset = MatchRules.Ruleset.ANIME_INSPIRED
	state.manual_gates = true
	for p in [0, 1]:
		for i in 3:
			var uid: int = p * 3 + i
			state.creatures[uid] = CreatureState.new(uid, &"gale_price_330" if p == gale_side else StringName("gale_price_330_" + str(foe_attr)), p)
			state.players[p].creature_uids.append(uid)
	state.slots[0].has_card = true
	state.slots[0].card_owner = 1 - gale_side
	state.slots[0].occupant_uid = 3
	state.creatures[3].slot = 0
	return state

func result(state: MatchState, plays: Array) -> BattleResult:
	return PowerCalc.compute_seq(state, 0, 3, 0, plays)

func _initialize() -> void:
	Engine.max_fps = 60
	AudioServer.set_bus_mute(0, true)
	CardDB.load_all()
	for attr in 6:
		var id := StringName("gale_price_330_" + str(attr))
		var definition := CreatureDef.make(id, String(id), attr, 330, Color.WHITE)
		definition.species = &"ratnik"
		CardDB._creatures[String(id)] = definition
	var gale := CreatureDef.make(&"gale_price_330", "Gale330", Attr.A.GALE, 330, Color.WHITE)
	gale.species = &"ratnik"
	CardDB._creatures[String(gale.id)] = gale
	var old: Array = []
	for id in IDS: old.append(int(CardDB.card(id).params.vs_adv))
	for stage in ["historical170150150", "proposal60"]:
		for i in IDS.size(): CardDB.card(IDS[i]).params.vs_adv = 60 if stage == "proposal60" else [170, 150, 150][i]
		for side in [0, 1]:
			var own: int = side * 3
			var fire_side: int = 1 - side
			var fire: int = fire_side * 3
			var state := board(side)
			var base := result(state, [])
			check(base.powers == [330, 330], "ANIME не даёт автоматические60G Пламени")
			for id in IDS:
				var plays := [[fire_side, &"ability_fire_drain"], [fire_side, &"ability_fire_spark"], [side, id]]
				var r := result(state, plays)
				var extra: int = 60 if stage == "proposal60" else int(CardDB.card(id).params.vs_adv)
				var amount: int = int(CardDB.card(id).params.amount) + extra
				check(r.powers[fire_side] == 460 and r.powers[side] == 230 + amount, "точная цена двух карт Пламени против " + String(id))
				if id != &"ability_gale_swap":
					check(r.winner_uid == (fire if stage == "proposal60" else own), "одиночный усилитель меняет исход только ценой vs_adv")
				else:
					check(r.winner_uid / 3 == side and r.powers[side] == (490 if stage == "proposal60" else 580), "Подмена сохраняет резерв и достаточно сильные260G")
				observations.append({"stage": stage, "gale_side": side, "card": String(id), "powers": r.powers, "winner": r.winner_uid})
				for foe_attr in range(1, 6):
					var non_fire := result(board(side, foe_attr), [[side, id]])
					check(non_fire.powers[side] == 330 + int(CardDB.card(id).params.amount), "базовая прибавка без огненного условия сохранена")
			var two := result(state, [[fire_side, &"ability_fire_drain"], [fire_side, &"ability_fire_spark"], [side, &"ability_gale_gust"], [side, &"ability_gale_leap"]])
			check(two.winner_uid == own, "две способности Бури сохраняют контригру")
			if stage == "proposal60":
				var nominal: int = 230 + int(CardDB.card(&"ability_gale_gust").params.amount) + int(CardDB.card(&"ability_gale_leap").params.amount) + 120
				check(two.powers[side] == nominal, "сумма текущих базовых цен двух карт и двух условных доплат60")
	for i in IDS.size(): CardDB.card(IDS[i]).params.vs_adv = old[i]
	for i in IDS.size(): check(CardDB.card(IDS[i]).params.vs_adv == old[i], "runtime-каталог восстановлен")
	var output := FileAccess.open("res://build/checks/element-balance-20261104/gale-price-proposal.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "observations": observations, "scope": "Синтетические равные330G, ANIME, нейтральные ворота. vs_adv60 только в памяти процесса. Не серия и не общая оценка баланса."}, "\t"))
	print("GALE PRICE PROPOSAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
