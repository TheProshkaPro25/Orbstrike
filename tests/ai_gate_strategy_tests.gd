extends SceneTree
## Узкие позиции ручных ворот: настоящий обмен контроллера, без физической сцены.
var failures := 0
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func deck(element: int) -> DeckDef:
	var creatures: Array = []
	for species in ["dragnar", "ratnik", "levian"]:
		creatures.append(StringName("creature_%s_%s" % [species, GameData.ATTR_KEYS[element]]))
	var red := [&"ability_fire_drain", &"ability_gale_swap", &"ability_light_crown", &"ability_stone_copy", &"ability_shadow_pact", &"ability_tide_hush"]
	var blue := [&"ability_fire_spark", &"ability_gale_gust", &"ability_light_glint", &"ability_stone_firm", &"ability_shadow_haze", &"ability_tide_spray"]
	return CardDB.build_deck(creatures, [&"arena_altar", &"arena_den_dragnar", &"arena_mute"], [red[element], blue[element], &"ability_ratnik_oath"])

func board(element: int, foe_element: int, gate: StringName, owner: int = 0) -> MatchController:
	var ctrl := MatchController.new(deck(element), deck(foe_element), 90311)
	ctrl._draw_pools = [[[], []], [[], []]]
	ctrl.start()
	for sl in ctrl.state.slots:
		sl.has_card = false
		sl.occupant_uid = -1
	var sl := ctrl.state.slots[0]
	sl.has_card = true
	sl.card_id = gate
	sl.card_owner = owner
	sl.revealed = false
	ctrl.state.players[0].ability_hand.clear()
	ctrl.state.players[1].ability_hand.clear()
	return ctrl

func begin(ctrl: MatchController, attacker: int = 0, defender: int = 3) -> void:
	ctrl.state.slots[0].occupant_uid = defender
	ctrl.state.creatures[defender].slot = 0
	ctrl._turn_player = ctrl.state.creatures[attacker].owner
	ctrl._start_battle(attacker, defender, 0)

func finish(ctrl: MatchController) -> void:
	for i in 8:
		if ctrl.get_phase() != MatchController.Phase.ABILITY_WINDOW:
			return
		check(ctrl.pass_ability(ctrl.get_active_player()) == OK, "разрешённый пас")
	check(false, "обмен завершился")

func mute_before_shift() -> void:
	# 390:330 в пользу владельца. Если он пасует, Сдвиг необратимо заменяет
	# Глухие врата Полем Камня: защитник получает +150 и +80, владелец теряет окно открытия.
	for early in [false, true]:
		var ctrl := board(Attr.A.FIRE, Attr.A.STONE, &"arena_mute")
		ctrl.state.players[1].ability_hand.assign([&"ability_stone_shift"])
		ctrl.state.players[0].ability_hand.assign([&"ability_fire_spark"])
		var spare := ctrl.state.slots[1]
		spare.has_card = true
		spare.card_id = &"arena_field_stone"
		spare.card_owner = 1
		spare.revealed = false
		begin(ctrl)
		var ai := AIPlayer.new(0, 1, -1.0, AIPlayer.Difficulty.HARD)
		var view := ctrl.get_view(0)
		check(view.players[1].ability_hand == [&""] and view.slots[1].card_id == &"", "чужие ID замаскированы")
		var preview := ctrl.get_battle_preview()
		check(preview.powers == [390, 330] and preview.winner_uid == 0, "исходная позиция 390:330")
		if early:
			check(ai.should_open_gate(view, preview), "ИИ открывает Глухие до публично возможного мгновенного ухода")
			check(ctrl.reveal_gate(0) == OK, "раннее открытие разрешено")
			check(ctrl.get_battle_preview().sealed and not ctrl.legal_abilities(1).has(&"ability_stone_shift"), "открытие запрещает Сдвиг")
		else:
			check(ctrl.pass_ability(0) == OK and ctrl.get_active_player() == 1, "позднее открытие оставляет ответ")
			check(ctrl.play_ability(1, &"ability_stone_shift") == OK, "Сдвиг проходит до открытия")
			# У владельца нет способностей: после потери своих ворот обмен может уже завершиться.
			check(ctrl.state.slots[0].card_id == &"arena_field_stone" or not ctrl.state.slots[0].has_card, "Сдвиг заменил карту боя")
			check(not ctrl.can_reveal_gate(0), "бывший владелец не может открыть ушедшие Глухие")
		finish(ctrl)
		check(ctrl.state.creatures[0].alive == early and ctrl.state.creatures[3].alive != early, "раннее открытие меняет фактическое выбывание")
		print("mute_shift early=", early, " own_alive=", ctrl.state.creatures[0].alive)

func mute_irreversible_risk_bounds() -> void:
	var ctrl := board(Attr.A.FIRE, Attr.A.STONE, &"arena_mute")
	ctrl.state.players[0].ability_hand.assign([&"ability_fire_spark"])
	ctrl.state.players[1].ability_hand.assign([&"ability_stone_shift"])
	begin(ctrl)
	var ai := AIPlayer.new(0, 5, -1.0, AIPlayer.Difficulty.HARD)
	check(not ai.should_open_gate(ctrl.get_view(0), ctrl.get_battle_preview()), "без свободных чужих ворот Сдвиг не требует раннего открытия")
	var spare := ctrl.state.slots[1]
	spare.has_card = true
	spare.card_owner = 1
	spare.card_id = &"arena_field_stone"
	check(ai.should_open_gate(ctrl.get_view(0), ctrl.get_battle_preview()), "закрытая потенциальная цель учитывается без её ID")
	spare.card_id = &"arena_mirror"
	ctrl.state.players[1].ability_hand.assign([&"ability_stone_firm"])
	check(ai.should_open_gate(ctrl.get_view(0), ctrl.get_battle_preview()), "подмена настоящих скрытых ID не меняет решение")
	spare.revealed = true
	check(not ai.should_open_gate(ctrl.get_view(0), ctrl.get_battle_preview()), "известная открытая ловушка не цель Сдвига")
	spare.card_id = &"arena_field_stone"
	ctrl.state.players[1].abilities_used.assign([&"ability_stone_shift"])
	check(not ai.should_open_gate(ctrl.get_view(0), ctrl.get_battle_preview()), "публично использованный Сдвиг не создаёт риск")
	ctrl.state.players[1].abilities_used.clear()
	ctrl.state.players[1].ability_hand.clear()
	check(not ai.should_open_gate(ctrl.get_view(0), ctrl.get_battle_preview()), "пустая чужая рука не требует раннего открытия")

func mute_before_swap() -> void:
	for early in [false, true]:
		var ctrl := board(Attr.A.FIRE, Attr.A.GALE, &"arena_mute")
		ctrl.state.creatures[5].def_id = &"creature_kolossar_gale" # резерв400 против владельца390
		ctrl.state.players[0].ability_hand.assign([&"ability_fire_spark"])
		ctrl.state.players[1].ability_hand.assign([&"ability_gale_swap"])
		begin(ctrl, 0, 4) # защитник Ратник340
		var ai := AIPlayer.new(0, 7, -1.0, AIPlayer.Difficulty.HARD)
		check(ai.should_open_gate(ctrl.get_view(0), ctrl.get_battle_preview()), "публичная допустимая Подмена требует раннего открытия")
		if early:
			check(ctrl.reveal_gate(0) == OK, "открытие до Подмены")
			check(not ctrl.legal_abilities(1).has(&"ability_gale_swap"), "открытые Глухие запрещают Подмену")
		else:
			check(ctrl.pass_ability(0) == OK and ctrl.play_ability(1, &"ability_gale_swap") == OK, "Подмена успевает до открытия")
			check(ctrl.reveal_gate(0) == OK, "после Подмены ловушку ещё можно открыть")
			var result := ctrl.get_battle_preview()
			check(result.defender_uid == 5 and result.powers == [390, 400], "подавление бонуса Подмены не возвращает старого бойца")
		finish(ctrl)
		check(ctrl.state.creatures[0].alive == early, "раннее открытие сохраняет бойца против Подмены")

func mute_preserves_safe_delay() -> void:
	var ctrl := board(Attr.A.FIRE, Attr.A.LIGHT, &"arena_mute")
	ctrl.state.players[1].ability_hand.assign([&"ability_light_glint"])
	ctrl.state.players[0].ability_hand.assign([&"ability_fire_spark"])
	begin(ctrl)
	var ai := AIPlayer.new(0, 2, -1.0, AIPlayer.Difficulty.HARD)
	check(not ai.should_open_gate(ctrl.get_view(0), ctrl.get_battle_preview()), "без мгновенного риска сохраняется позднее открытие")
	check(ctrl.pass_ability(0) == OK and ctrl.play_ability(1, &"ability_light_glint") == OK, "противник тратит обычное усиление")
	check(ai.should_open_gate(ctrl.get_view(0), ctrl.get_battle_preview()), "после обычного усиления ИИ открывает ловушку")
	check(ctrl.reveal_gate(0) == OK, "позднее открытие разрешено")
	check(ctrl.get_battle_preview().cancelled_plays.has([1, &"ability_light_glint"]), "потраченная карта подавлена")
	finish(ctrl)

func own_gate_planning() -> void:
	var ctrl := board(Attr.A.SHADOW, Attr.A.STONE, &"arena_altar")
	ctrl.state.creatures[0].def_id = &"creature_gorgul_shadow" # 280
	ctrl.state.creatures[3].def_id = &"creature_kolossar_stone" # 410
	for uid in [1, 2, 4, 5]:
		ctrl.state.creatures[uid].used = true
	var ai := AIPlayer.new(0, 3, -1.0, AIPlayer.Difficulty.HARD)
	var view := ctrl.get_view(0)
	var closed := PowerCalc.compute_seq(view, 3, 0, 0, [])
	check(closed.powers == [410, 280], "закрытый Алтарь действительно не даёт силу")
	check(ai._exposure(view, 0, 0) == 0.0, "план защиты учитывает будущее открытие своего Алтаря")
	check(not view.slots[0].revealed and not ctrl.state.slots[0].revealed, "прогноз не открывает настоящую карту")
	ctrl.state.slots[0].card_id = &"arena_field_shadow"
	check(ai._exposure(ctrl.get_view(0), 0, 0) > 0.0, "Поле Тени не спасает 280 против 410")
	ctrl.state.slots[0].has_card = false
	ctrl.state.players[0].arena_hand.assign([&"arena_field_shadow", &"arena_altar"])
	var setup := ai.choose_setup(ctrl.get_view(0), [0], false)
	check(setup.get("card_id", &"") == &"arena_altar", "при одинаковой доступности ИИ выбирает защищающий Алтарь")
	# Свои видовые ворота помогают атаке, если вид соперника иной; Алтарь в атаке — нет.
	ctrl.state.slots[0].has_card = true
	ctrl.state.slots[0].card_id = &"arena_den_gorgul"
	ctrl.state.slots[0].occupant_uid = 3
	ctrl.state.creatures[3].slot = 0
	var attack_view := ctrl.get_view(0)
	check(ai._attack_win_prob(attack_view, 0, 3, 0) == 1.0, "атака учитывает своё открываемое удвоение 560:410")
	var normal := AIPlayer.new(0, 3, -1.0, AIPlayer.Difficulty.NORMAL)
	check(normal._score(attack_view, 0, 0) >= 1000.0, "обычная сложность видит выигрышную атаку через свои видовые ворота")
	check(not attack_view.slots[0].revealed and not ctrl.state.slots[0].revealed, "атака не мутирует настоящие ворота")
	ctrl.state.slots[0].card_id = &"arena_altar"
	check(ai._attack_win_prob(ctrl.get_view(0), 0, 3, 0) == 0.0, "Алтарь не получает выдуманный бонус в атаке")
	# Когда удвоение помогает чужому виду, можно оставить свои ворота закрытыми.
	ctrl.state.slots[0].card_id = &"arena_den_kolossar"
	var harmful := PowerCalc.compute_seq(ctrl.get_view(0), 0, 3, 0, [])
	check(not ai.should_open_gate(ctrl.get_view(0), harmful), "ИИ не открывает выгодные сопернику видовые ворота")
	# Подтверждение прогноза защиты фактическим открытием/исходом того же контроллера.
	ctrl.state.slots[0].card_id = &"arena_altar"
	ctrl.state.slots[0].occupant_uid = -1
	ctrl.state.creatures[3].slot = -1
	var results: Array = []
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
	begin(ctrl, 3, 0)
	check(ctrl.can_reveal_gate(0) and ai.should_open_gate(ctrl.get_view(0), ctrl.get_battle_preview()), "защитник действительно получает окно открытия Алтаря")
	check(ctrl.reveal_gate(0) == OK, "прогнозируемое открытие Алтаря разрешено")
	finish(ctrl)
	check(results.size() == 1 and results[0].powers == [410, 580] and ctrl.state.creatures[0].alive and not ctrl.state.creatures[3].alive, "реальный Алтарь сохраняет Горгула280 против Колоссара410")

func exposure_first_irreversible() -> void:
	for owner in [0, 1]:
		var foe: int = 1 - owner
		var defender: int = owner * 3
		var attacker: int = foe * 3
		var ctrl := board(Attr.A.SHADOW if owner == 0 else Attr.A.STONE, Attr.A.STONE if owner == 0 else Attr.A.SHADOW, &"arena_altar", owner)
		ctrl.state.creatures[defender].def_id = &"creature_gorgul_shadow"
		ctrl.state.creatures[attacker].def_id = &"creature_kolossar_stone"
		for u in ctrl.state.creatures:
			ctrl.state.creatures[u].used = int(u) != defender and int(u) != attacker
		ctrl.state.players[owner].ability_hand.assign([&"ability_shadow_haze"])
		ctrl.state.players[foe].ability_hand.assign([&"ability_stone_shift"])
		var spare := ctrl.state.slots[1]
		spare.has_card = true
		spare.card_owner = foe
		spare.card_id = &"arena_field_stone"
		var ai := AIPlayer.new(owner, 90312, -1.0, AIPlayer.Difficulty.HARD)
		var view := ctrl.get_view(owner)
		check(view.players[foe].ability_hand == [&""] and view.slots[1].card_id == &"", "exposure получает замаскированные ID")
		var started := Time.get_ticks_usec()
		var risk := ai._exposure(view, defender, 0)
		print("exposure first_shift owner=", owner, " risk=", risk, " usec=", Time.get_ticks_usec() - started)
		check(not view.slots[0].revealed and view.slots[1].card_id == &"" and view.players[foe].ability_hand == [&""], "прогноз Сдвига не мутирует закрытые карты/руку")
		check(risk > 0.0, "закрытый Алтарь не гарантирует защиту до первого Сдвига")
		ctrl.state.players[foe].ability_hand.assign([&"ability_stone_firm"])
		spare.card_id = &"arena_mirror"
		check(ai._exposure(ctrl.get_view(owner), defender, 0) == risk, "настоящие скрытые ID не меняют публичный риск")
		spare.revealed = true
		check(ai._exposure(ctrl.get_view(owner), defender, 0) == 0.0, "открытая ловушка не цель Сдвига")
		spare.has_card = false
		check(ai._exposure(ctrl.get_view(owner), defender, 0) == 0.0, "без цели Сдвига базовая защита Алтаря сохранена")
		spare.has_card = true
		spare.card_id = &"arena_field_stone"
		spare.revealed = false
		ctrl.state.players[foe].abilities_used.assign([&"ability_stone_shift"])
		check(ai._exposure(ctrl.get_view(owner), defender, 0) == 0.0, "публично использованный Сдвиг исключён из риска")
		ctrl.state.players[foe].abilities_used.clear()
		ctrl.state.players[foe].ability_hand.clear()
		check(ai._exposure(ctrl.get_view(owner), defender, 0) == 0.0, "пустая чужая рука не отменяет будущую защиту")
		ctrl.state.players[foe].ability_hand.assign([&"ability_stone_shift"])
		ctrl.state.slots[0].revealed = true
		check(ai._exposure(ctrl.get_view(owner), defender, 0) > 0.0, "уже открытый Алтарь также уязвим к Сдвигу")
		ctrl.state.slots[0].revealed = false
		spare.revealed = true
		# Реальный порядок: атакующий первым меняет ворота, защитник лишается открытия Алтаря.
		begin(ctrl, attacker, defender)
		check(ctrl.get_active_player() == foe and not ctrl.can_reveal_gate(owner), "защитник не получает открытие раньше атакующего")
		check(ctrl.play_ability(foe, &"ability_stone_shift") == OK and not ctrl.can_reveal_gate(owner), "первый Сдвиг уносит закрытый Алтарь")
		finish(ctrl)
		check(not ctrl.state.creatures[defender].alive, "опасность первого Сдвига подтверждена настоящим исходом")
	for opened in [false, true]:
		var ctrl := board(Attr.A.FIRE, Attr.A.GALE, &"arena_mute")
		ctrl.state.slots[0].revealed = opened
		ctrl.state.creatures[5].def_id = &"creature_kolossar_gale"
		ctrl.state.creatures[3].used = true
		ctrl.state.creatures[5].used = true # Подмена может брать использованный резерв.
		ctrl.state.players[0].ability_hand.assign([&"ability_fire_spark"])
		ctrl.state.players[1].ability_hand.assign([&"ability_gale_swap"])
		var ai := AIPlayer.new(0, 90313, -1.0, AIPlayer.Difficulty.HARD)
		var risk := ai._exposure(ctrl.get_view(0), 0, 0)
		check((risk > 0.0) == (not opened), "только закрытые Глухие не успевают запретить первую Подмену")
		check(ctrl.state.slots[0].revealed == opened and ctrl.state.creatures[5].used, "прогноз Подмены не меняет состояние")
		begin(ctrl, 4, 0)
		if not opened:
			check(not ctrl.can_reveal_gate(0) and ctrl.play_ability(1, &"ability_gale_swap") == OK, "Подмена проходит до первого открытия защитником")
			check(ctrl.reveal_gate(0) == OK and ctrl.get_battle_preview().attacker_uid == 5, "открытие не возвращает прежнего атакующего")
		finish(ctrl)
		check(ctrl.state.creatures[0].alive == opened, "фактическая защита Глухих зависит от порядка открытия")

func exposure_swap_bounds() -> void:
	var ctrl := board(Attr.A.FIRE, Attr.A.GALE, &"arena_mute")
	ctrl.state.creatures[5].def_id = &"creature_kolossar_gale"
	ctrl.state.creatures[3].used = true
	ctrl.state.creatures[5].used = true
	ctrl.state.players[0].ability_hand.assign([&"ability_fire_spark"])
	ctrl.state.players[1].ability_hand.assign([&"ability_gale_swap"])
	var ai := AIPlayer.new(0, 90314, -1.0, AIPlayer.Difficulty.HARD)
	ctrl.state.players[1].abilities_used.assign([&"ability_gale_swap"])
	check(ai._exposure(ctrl.get_view(0), 0, 0) == 0.0, "публично использованная Подмена не угрожает")
	ctrl.state.players[1].abilities_used.clear()
	ctrl.state.players[1].ability_hand.clear()
	check(ai._exposure(ctrl.get_view(0), 0, 0) == 0.0, "Подмена не прогнозируется при пустой руке")
	ctrl.state.players[1].ability_hand.assign([&"ability_gale_swap"])
	for uid in [3, 5]:
		ctrl.state.creatures[uid].alive = false
	check(ai._exposure(ctrl.get_view(0), 0, 0) == 0.0, "без живой замены нет риска Подмены")
	ctrl.state.creatures[5].alive = true
	ctrl.state.creatures[4].attached.assign([[1, &"ability_gale_gust"], [2, &"ability_gale_counter"], [3, &"ability_gale_vengeance"]])
	var view := ctrl.get_view(0)
	var before := PowerCalc.compute_seq(view, 4, 0, 0, [])
	check(ai._first_irreversible_exposure(view, before, 0.0) == 0.0, "три прежних прикрепления запрещают первую Подмену")
	begin(ctrl, 4, 0)
	check(not ctrl.legal_abilities(1).has(&"ability_gale_swap"), "лимит первой Подмены подтверждён контроллером")

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	mute_before_shift()
	mute_preserves_safe_delay()
	mute_irreversible_risk_bounds()
	mute_before_swap()
	own_gate_planning()
	exposure_first_irreversible()
	exposure_swap_bounds()
	print("AI gates: ", assertions, " assertions, ", failures, " failures")
	quit(1 if failures else 0)
