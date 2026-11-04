extends SceneTree
## Перенос номинального бюджета из узкого anti-Fire в базу Шквала; только память стенда.
const LEAP := &"ability_gale_leap"
var checks := 0
var failures := 0
var observations: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func board(side: int, foe_attr: int, gate: StringName) -> MatchState:
	var s := MatchState.new()
	s.ruleset = MatchRules.Ruleset.ANIME_INSPIRED
	s.manual_gates = true
	for p in [0,1]:
		var uid: int = p * 3
		s.creatures[uid] = CreatureState.new(uid, &"leap_price_gale330" if p == side else StringName("leap_price_foe440_" + str(foe_attr)), p)
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
	var own := CreatureDef.make(&"leap_price_gale330", "Gale330", 1, 330, Color.WHITE)
	own.species = &"grifalon"
	CardDB._creatures[String(own.id)] = own
	for attr in [0,2,3,4,5]:
		var id := StringName("leap_price_foe440_" + str(attr))
		var d := CreatureDef.make(id, String(id), attr, 440, Color.WHITE)
		d.species = &"ratnik"
		CardDB._creatures[String(id)] = d
	CardDB._cards["leap_price_cancel"] = CardDef.make(&"leap_price_cancel", "cancel", 1, &"negate", {}, "")
	var card := CardDB.card(LEAP)
	var original := card.params.duplicate(true)
	for stage in [["historical",100,150,130.0], ["current",100,60,112.0], ["proposal",120,60,132.0]]:
		card.params.amount = stage[1]
		card.params.vs_adv = stage[2]
		var nominal := 0.0
		for foe_attr in [0,2,3,4,5]:
			var gain: int = CardEffects.ability_delta(card,{"foe_beats": foe_attr == 0}).x
			nominal += gain
			for side in [0,1]:
				for gate in [&"", &"arena_field_gale", StringName("arena_field_" + GameData.ATTR_KEYS[foe_attr]), &"arena_altar"]:
					var state := board(side, foe_attr, gate)
					var before := PowerCalc.compute_seq(state,0,3,0,[])
					var after := PowerCalc.compute_seq(state,0,3,0,[[side,LEAP]])
					check(after.powers[side] == before.powers[side] + gain and after.powers[1-side] == before.powers[1-side], "изменяется только точная собственная цена Шквала")
					if gate == &"" and foe_attr != 0:
						check(after.winner_uid == (side*3 if stage[0] == "proposal" else (1-side)*3), "120 вместо100 преодолевает обычный дефицит10G без anti-Fire")
					var totals := [0,0]
					for line in after.breakdown: totals[int(line.side)] += int(line.delta)
					check(totals == after.powers, "breakdown содержит всю цену")
					observations.append({"stage":stage[0],"side":side,"foe":foe_attr,"gate":String(gate),"powers":after.powers,"winner":after.winner_uid})
		check(is_equal_approx(nominal/5.0,stage[3]), "средний номинальный бюджет130→112→132 по пяти равновесным соперникам")
		for side in [0,1]:
			var state := board(side,5,&"")
			var result := PowerCalc.compute_seq(state,0,3,0,[[side,LEAP],[1-side,&"leap_price_cancel"]])
			check(result.cancelled_plays.has([side,LEAP]) and result.powers[side] == 330, "контркарта по-прежнему полностью снимает прибавку")
		check(card.effect_id == &"gust" and not CardEffects.is_sure(card) and not CardEffects.is_instant(card) and CardDB.card_class(card) == &"red", "перемещение/отменяемость/класс не изменились")
	card.params = original
	check(card.params == original, "runtime-каталог восстановлен")
	var output := FileAccess.open("res://build/checks/element-balance-20261104/leap-price-proposal.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"scope":"Три номинальных бюджета, пять соперников, две стороны, нейтральные/Field/Altar/отмена. Только память процесса; не матчевые серии и не обещание общего баланса."}, "\t"))
	print("LEAP PRICE PROPOSAL: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
