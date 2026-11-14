extends "res://tests/run_tests.gd"
## Проверки новых стихийных карт через расчёт и команды локального матча.

const AFTERBURN := &"ability_fire_afterburn"
const BREAKAWAY := &"ability_gale_breakaway"
const REFRACTION := &"ability_light_refraction"
const BASTION := &"ability_stone_bastion"
const TRIBUTE := &"ability_shadow_tribute"
const STORED_WAVE := &"ability_tide_stored_wave"
const FORGE := &"arena_fire_forge"
const PASS := &"arena_gale_pass"
const DOME := &"arena_light_dome"
const PLATE := &"arena_stone_plate"
const VEIL := &"arena_shadow_veil"
const SLUICE := &"arena_tide_sluice"
const REDS := [AFTERBURN, BREAKAWAY, REFRACTION, BASTION, TRIBUTE, STORED_WAVE]
const GOLDS := [FORGE, PASS, DOME, PLATE, VEIL, SLUICE]
const FIGHTERS := [ZH, VI, LU, GR, SU, MA]
const COPY := &"ability_stone_copy"
const ECLIPSE := &"ability_shadow_eclipse"
const PACT := &"ability_shadow_pact"
const RESET := &"ability_kolossar_reset"
const LARGE_BOOST := &"ability_test_elemental_plus160"
const LARGE_PENALTY := &"ability_test_elemental_minus120"
const RETURNING_BLUE := &"ability_test_elemental_returning_blue"


func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	_add_test_creatures()
	CardDB._cards[String(LARGE_BOOST)] = CardDef.make(LARGE_BOOST, "+160", CardDef.Kind.ABILITY, &"boost", {"amount": 160}, "")
	CardDB._cards[String(LARGE_PENALTY)] = CardDef.make(LARGE_PENALTY, "−120", CardDef.Kind.ABILITY, &"weaken", {"amount": 120}, "")
	CardDB._cards[String(RETURNING_BLUE)] = CardDef.make(RETURNING_BLUE, "+40", CardDef.Kind.ABILITY, &"boost", {"amount": 40, "returns": true}, "")
	if _test_catalog():
		_test_red_restrictions()
		_test_afterburn()
		_test_refraction()
		_test_bastion()
		_test_gold_powers()
		_test_plate()
		_test_breakaway()
		_test_tribute()
		_test_stored_wave()
		_test_sluice()
		_test_draw_and_replay()
		_test_mode_saves()
	print("Elemental cards: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_catalog() -> bool:
	var present := true
	for element in Attr.COUNT:
		for spec in [[REDS[element], CardDef.Kind.ABILITY, &"red"], [GOLDS[element], CardDef.Kind.ARENA, &"gold"]]:
			var id: StringName = spec[0]
			var card := CardDB.card(id)
			_check(card != null, "карта зарегистрирована: " + String(id))
			if card == null:
				present = false
				continue
			var kind: int = spec[1]
			var cls: StringName = spec[2]
			_check(card.kind == kind and CardDB.card_class(card) == cls, "класс карты: " + String(id))
			_check(not card.text.is_empty() and card.text.length() <= 120 and not card.full_text().is_empty(), "текст карты: " + String(id))
			for candidate in Attr.COUNT:
				_check(CardDB.cards_of(kind, cls, candidate, [], true).has(id) == (candidate == element),
					"фильтр стихии %d: %s" % [candidate, id])
			_check(not CardDB.cards_of(kind, cls, element).has(id), "прежний пул: " + String(id))
	return present


func _position(a: StringName, d: StringName, gate: StringName = NEUTRAL, owner: int = 1) -> MatchState:
	var s := _mk_state(a, d, gate)
	s.ruleset = MatchRules.Ruleset.ANIME_INSPIRED
	s.manual_gates = true
	s.elemental_cards = true
	s.slots[0].card_owner = owner
	s.slots[0].revealed = true
	return s


func _powers(s: MatchState, plays: Array, expected: Array, label: String) -> BattleResult:
	var r := _seq(s, plays)
	_check(r.powers == expected, "%s: ожидалось %s, получено %s" % [label, expected, r.powers])
	var totals := [0, 0]
	for row in r.breakdown:
		totals[row.side] += row.delta
	_check(totals == expected, "разбивка: " + label)
	return r


func _test_red_restrictions() -> void:
	for element in Attr.COUNT:
		var id: StringName = REDS[element]
		var card := CardDB.card(id)
		_check(CardEffects.moment(card) == &"battle" and CardEffects.lock_attr(card) == element, "момент и стихия: " + String(id))
		_check(not CardEffects.copyable(card), "копия не повторяет " + String(id))
		var s := _position(FIGHTERS[element], GR)
		_check(_seq(s, [[0, id], [1, COPY]]).copies.is_empty(), "копия в расчёте пропускает " + String(id))
		_check(_seq(s, [[0, id], [1, SHIELD]]).cancelled_plays.has([0, id]), "отменяемость " + String(id))
		var ctrl := _fixture(FIGHTERS[element], FIGHTERS[element], [id, PLUS], [SHIELD, PLUS])
		_check(ctrl.select_creature(0, 0) == OK, "подготовка броска для " + String(id))
		_check(ctrl.get_ability_moment() == &"pre_throw" and not ctrl.legal_abilities(0).has(id), "до броска недоступна " + String(id))
		_check(ctrl.play_ability(0, id) != OK and ctrl.state.players[0].ability_hand.has(id), "вне боя не расходуется " + String(id))
		ctrl.report_landing(0, 1)
		_play(ctrl, 0, id)
		_play(ctrl, 1, SHIELD)
		_pass_windows(ctrl)
		_check(ctrl.state.players[0].ability_cooldown.get(id, 0) == 2, "полный отдых после отмены " + String(id))


func _test_afterburn() -> void:
	var s := _position(ZH, ZH)
	_powers(s, [[0, AFTERBURN]], [370, 340], "Дожиг без основы")
	_powers(s, [[0, AFTERBURN], [0, PLUS], [1, PLUS]], [450, 420], "поздние карты не усиливают Дожиг")
	_powers(s, [[0, PLUS], [1, PLUS], [0, AFTERBURN]], [510, 420], "Дожиг считает только свои карты")
	_powers(s, [[0, PLUS], [1, SHIELD], [0, AFTERBURN]], [370, 340], "отменённая основа не усиливает Дожиг")
	s.creatures[1].attached = [[0, PLUS]]
	_powers(s, [[1, MINUS], [1, AFTERBURN]], [260, 570], "Дожиг защитника считает прикрепление")
	_powers(s, [[1, MINUS], [1, PLUS], [1, AFTERBURN]], [260, 650], "Дожиг ограничен +150")


func _test_refraction() -> void:
	var s := _position(LU, SU)
	_powers(s, [[0, REFRACTION]], [410, 350], "Преломление даёт +80")
	_powers(s, [[1, MINUS], [0, REFRACTION]], [330, 350], "щит не гасит ранний штраф")
	_powers(s, [[0, REFRACTION], [1, LARGE_PENALTY], [1, MINUS]], [290, 350], "щит гасит до 80 первого позднего штрафа")
	_powers(s, [[0, REFRACTION], [1, PACT], [1, MINUS]], [330, 390], "первый штраф тратит щит полностью")
	_powers(s, [[0, REFRACTION], [1, LARGE_PENALTY], [0, SHIELD], [1, MINUS]], [410, 350],
		"отменённый штраф не тратит щит")
	_powers(s, [[0, REFRACTION], [1, RESET], [1, MINUS]], [330, 350], "сброс силы обходит щит и не тратит его")
	_powers(s, [[0, REFRACTION], [1, &"ability_fire_toll"], [0, PLUS], [1, MINUS]], [430, 350], "пошлина действует отдельно от щита")
	_powers(s, [[0, REFRACTION], [1, SHIELD], [1, MINUS]], [250, 350], "отмена убирает прибавку и щит")
	_powers(_position(SU, LU), [[1, REFRACTION], [0, LARGE_PENALTY]], [350, 370], "щит защитника")


func _test_bastion() -> void:
	var s := _position(GR, GR)
	_powers(s, [[0, BASTION]], [415, 370], "Застава без союзника")
	_add_creature(s, 2, GR, 0, 4)
	_add_creature(s, 3, GR, 1, 1)
	_powers(s, [[0, BASTION]], [415, 370], "диагональный союзник и соседний соперник")
	_add_creature(s, 4, GR, 0, 3)
	_powers(s, [[0, BASTION], [1, BASTION]], [495, 495], "вертикальный и горизонтальный союзники")
	s.creatures[4].slot = -1
	_powers(s, [[0, BASTION]], [415, 370], "устаревший occupant_uid не считается")
	s.creatures[4].slot = 3
	s.creatures[4].alive = false
	_powers(s, [[0, BASTION]], [415, 370], "выбывший союзник не считается")
	s.slots[2].card_id = NEUTRAL
	s.slots[2].has_card = true
	s.slots[2].revealed = true
	s.slots[2].occupant_uid = 1
	s.creatures[1].slot = 2
	s.slots[0].occupant_uid = -1
	s.creatures[4].alive = true
	_check(PowerCalc.compute_seq(s, 0, 1, 2, [[0, BASTION]]).powers[0] == 415,
		"слоты 2 и 3 разделены краем ряда")


func _test_gold_powers() -> void:
	for element in Attr.COUNT:
		var id: StringName = GOLDS[element]
		var fighter: StringName = FIGHTERS[element]
		var base: int = TEST_POWER[element]
		var ordinary_bonus: int = [40, 60, 110, 40, 30, 110][element]
		for owner in [0, 1]:
			var s := _position(fighter, fighter, id, owner)
			var bonus := 120 if id == PASS and owner == 0 else ordinary_bonus
			var expected := [base, base]
			expected[owner] += bonus
			_powers(s, [], expected, "%s: бонус только хозяину %d" % [id, owner])
			s.slots[0].revealed = false
			_powers(s, [], [base, base], "%s: закрытые ворота" % id)
		var wrong := _position(fighter, FIGHTERS[(element + 1) % Attr.COUNT], id, 1)
		_powers(wrong, [], [base, TEST_POWER[(element + 1) % Attr.COUNT]], "%s: чужая стихия хозяина" % id)

	var fire := _position(ZH, ZH, FORGE, 0)
	fire.creatures[0].attached = [[0, PLUS]]
	_powers(fire, [], [460, 340], "одна карта Горнила")
	_powers(fire, [[0, MINUS]], [520, 260], "Горнило считает прикреплённую и сыгранную карты")
	_powers(fire, [[0, MINUS], [1, SHIELD]], [460, 340], "отменённая карта Горнила не считается")
	_powers(fire, [[1, PLUS]], [460, 420], "чужая карта Горнила не считается")
	var light := _position(LU, LU, DOME, 1)
	_powers(light, [[1, PLUS]], [330, 460], "Купол с действующей картой")
	_powers(light, [[1, PLUS], [0, SHIELD]], [330, 440], "Купол с отменённой картой")
	_powers(light, [[0, PLUS]], [410, 440], "чужая карта не меняет Купол")
	var shadow := _position(SU, SU, VEIL, 0)
	shadow.creatures[1].base_power_override = 351
	shadow.creatures[0].marks = [{"delta": 100}]
	_powers(shadow, [], [570, 351], "Завеса сравнивает базу и учитывает снимок")
	shadow.creatures[1].base_power_override = 349
	shadow.creatures[0].marks = [{"delta": -100}]
	_powers(shadow, [], [280, 349], "Завеса не сравнивает силу после метки")


func _test_plate() -> void:
	var s := _position(SU, GR, PLATE, 1)
	_powers(s, [[0, LARGE_BOOST], [0, PLUS]], [505, 410], "Плита ограничивает только первую способность соперника")
	_powers(s, [[0, LARGE_BOOST], [1, SHIELD], [0, PLUS]], [425, 410], "отменённая первая карта не занимает ограничение")
	_powers(s, [[0, MINUS], [0, LARGE_BOOST]], [510, 330], "чистый штраф занимает место первой способности")
	_powers(s, [[0, LARGE_BOOST], [1, LARGE_BOOST]], [425, 570], "Плита не ограничивает владельца")
	s.creatures[0].attached = [[0, LARGE_BOOST]]
	_powers(s, [[0, PLUS]], [505, 410], "первой может быть прикреплённая способность")
	_powers(s, [[0, ECLIPSE]], [510, 320], "подавление Плиты снимает ограничение и бонус")
	s = _position(GR, GR, PLATE, 1)
	_powers(s, [[1, LARGE_BOOST], [0, COPY]], [445, 570], "у первой Копии один общий предел +75")


func _fixture(a: StringName, d: StringName, hand_a: Array, hand_d: Array, gate: StringName = NEUTRAL, owner: int = 1) -> MatchController:
	var gates := [NEUTRAL, NEUTRAL, NEUTRAL]
	var ctrl := MatchController.new(_mk_deck([a, LU, GR], gates, hand_a), _mk_deck([d, SU, MA], gates, hand_d),
		6113, MatchRules.Ruleset.ANIME_INSPIRED, true)
	ctrl._draw_pools = [[[], []], [[], []]]
	_setup_controller(ctrl)
	_set_card(ctrl, 1, gate, owner)
	_stand(ctrl, 3, 1)
	return ctrl


func _play(ctrl: MatchController, player: int, id: StringName) -> void:
	_check(ctrl.legal_abilities(player).has(id), "доступна %s игроку %d" % [id, player])
	_check(ctrl.play_ability(player, id) == OK, "сыграна %s игроком %d" % [id, player])


func _test_breakaway() -> void:
	for mode in [&"ordinary", &"tie", &"cancelled", &"loss", &"hold"]:
		var ctrl := _fixture(VI, VI, [PLUS], [BREAKAWAY, PLUS], &"arena_hold" if mode == &"hold" else NEUTRAL)
		var atk: CreatureState = ctrl.state.creatures[0]
		atk.base_power_override = 365 if mode == &"tie" else (400 if mode == &"loss" else 250)
		_throw(ctrl, 0, 0, 1)
		ctrl.pass_ability(0)
		if mode == &"hold":
			_check(ctrl.reveal_gate(1) == OK, "защитник открывает Удержание")
		_play(ctrl, 1, BREAKAWAY)
		if mode == &"cancelled":
			# Ответ после Отрыва снова доступен атакующему.
			ctrl.state.players[0].ability_hand.append(SHIELD)
			_play(ctrl, 0, SHIELD)
		var before := ctrl.get_battle_preview()
		_check(before.powers[1] == (300 if mode == &"cancelled" else 365), "Отрыв даёт +65 до исхода: " + String(mode))
		_pass_windows(ctrl)
		var defender: CreatureState = ctrl.state.creatures[3]
		var note := String(mode)
		if mode == &"hold":
			_check(defender.slot == 1 and not defender.used and ctrl.state.players[1].captured.is_empty(), "Удержание важнее Отрыва")
		elif mode == &"loss":
			_check(not defender.alive, "Отрыв не спасает проигравшего")
		else:
			_check(defender.alive and defender.slot < 0 and defender.used == (mode != &"ordinary"), "зона победителя после Отрыва: " + note)
			_check(ctrl.state.players[1].captured == [NEUTRAL], "Отрыв сохраняет захват: " + note)
		_check(ctrl.state.players[1].ability_cooldown.get(BREAKAWAY, 0) == 2, "Отрыв отдыхает: " + note)


func _test_tribute() -> void:
	for mode in [&"ordinary", &"cancelled_blue", &"cancelled_tribute", &"returned", &"last"]:
		var first_blue := RETURNING_BLUE if mode == &"returned" else PLUS
		var ctrl := _fixture(SU, MA, [TRIBUTE, SHIELD], [first_blue, &"ability_tide_surf", SHIELD])
		ctrl.state.creatures[0].base_power_override = 700
		if mode == &"last":
			ctrl.state.creatures[5].alive = false
		_throw(ctrl, 0, 0, 1)
		_play(ctrl, 0, TRIBUTE)
		if mode == &"cancelled_tribute":
			_play(ctrl, 1, SHIELD)
			ctrl.pass_ability(0)
		_play(ctrl, 1, first_blue)
		if mode == &"cancelled_blue":
			_play(ctrl, 0, SHIELD)
		else:
			ctrl.pass_ability(0)
		_play(ctrl, 1, &"ability_tide_surf")
		var preview := ctrl.get_battle_preview()
		_check(preview.powers[0] == (700 if mode == &"cancelled_tribute" else 820), "сила Дани: " + String(mode))
		_pass_windows(ctrl)
		var foe: PlayerState = ctrl.state.players[1]
		var first_rest: int = 3 if mode in [&"ordinary", &"cancelled_blue"] else (0 if mode in [&"returned", &"last"] else 2)
		var second_rest := 0 if mode == &"last" else 2
		_check(foe.ability_cooldown.get(first_blue, 0) == first_rest, "отдых первой чужой синей: " + String(mode))
		_check(foe.ability_cooldown.get(&"ability_tide_surf", 0) == second_rest, "отдых второй чужой синей: " + String(mode))


func _test_stored_wave() -> void:
	for margin in [79, 80, 81]:
		var ctrl := _fixture(MA, MA, [STORED_WAVE, PLUS], [PLUS])
		ctrl.state.creatures[0].base_power_override = 230 + margin
		_throw(ctrl, 0, 0, 1)
		_play(ctrl, 0, STORED_WAVE)
		var first := ctrl.get_battle_preview()
		_check(first.powers == [320 + margin, 320], "Волна даёт +90 в первом бою")
		_pass_windows(ctrl)
		var winner: CreatureState = ctrl.state.creatures[0]
		_check(winner.marks.size() == (1 if margin >= 80 else 0), "порог Волны " + str(margin))
		if margin == 80:
			_stand(ctrl, 4, 3)
			ctrl.state.creatures[4].base_power_override = 300
			# Возвращаем использованного бойца в руку как после исчерпания резерва.
			winner.used = false
			_throw(ctrl, 0, 0, 3)
			_check(ctrl.get_battle_preview().powers == [370, 300], "Волна добавляет +60 в следующем бою победителя")
			_pass_windows(ctrl)
			_check(winner.marks.is_empty(), "метка Волны расходуется ровно за один бой")
	var held := _fixture(MA, MA, [STORED_WAVE, PLUS], [PLUS], &"arena_hold", 0)
	held.state.creatures[0].base_power_override = 450
	_throw(held, 0, 0, 1)
	_check(held.reveal_gate(0) == OK, "атакующий открывает Удержание")
	_play(held, 0, STORED_WAVE)
	_pass_windows(held)
	_check(held.state.creatures[0].marks.is_empty(), "особый исход не ставит метку Волны")


func _test_sluice() -> void:
	for mode in [&"ordinary", &"closed", &"suppressed", &"no_target", &"enemy_wins", &"tie"]:
		var ctrl := _fixture(SU, MA, [PLUS, ECLIPSE], [PLUS], SLUICE)
		ctrl.state.creatures[0].base_power_override = 430 if mode == &"tie" else (450 if mode == &"enemy_wins" else 300)
		if mode == &"no_target":
			for slot in [3, 5]:
				ctrl.state.slots[slot].card_owner = 0
		else:
			_stand(ctrl, 4, 3)
			ctrl.state.slots[4].card_owner = 1
		_throw(ctrl, 0, 0, 1)
		if mode == &"suppressed":
			_play(ctrl, 0, ECLIPSE)
		else:
			ctrl.pass_ability(0)
		if mode != &"closed":
			_check(ctrl.reveal_gate(1) == OK, "Шлюз открывается хозяином: " + String(mode))
		var preview := ctrl.get_battle_preview()
		_check(preview.powers[1] == (270 if mode == &"suppressed" else (320 if mode == &"closed" else 430)),
			"бонус Шлюза: " + String(mode))
		_pass_windows(ctrl)
		var winner_uid := 0 if mode in [&"enemy_wins", &"suppressed"] else 3
		var winner: CreatureState = ctrl.state.creatures[winner_uid]
		_check(ctrl.state.players[winner.owner].captured == [SLUICE] and not ctrl.state.slots[1].has_card,
			"захват закрывает старый слот Шлюза: " + String(mode))
		if mode == &"ordinary":
			_check(winner.slot == 4 and not winner.used and ctrl.state.slots[4].occupant_uid == 3,
				"Шлюз переносит победителя на первые свободные свои ворота")
			_check(ctrl.state.slots[3].occupant_uid == 4 and ctrl.state.slots[5].occupant_uid == -1,
				"Шлюз сохраняет занятые и следующие свободные ворота")
		else:
			_check(winner.slot == -1 and winner.used, "Шлюз оставляет победителя в использованных: " + String(mode))


func _test_draw_and_replay() -> void:
	var fire := CardDB.preset_deck(0)
	var tide := CardDB.preset_deck(1)
	var older := MatchController.new(fire, tide, 6113)
	var local := MatchController.new(fire, tide, 6113, MatchRules.Ruleset.ANIME_INSPIRED, true)
	for mode in [older, local]:
		var enabled: bool = mode == local
		_check(mode.state.elemental_cards == enabled and mode.state.duplicate_full().elemental_cards == enabled
			and mode.get_view(0).elemental_cards == enabled, "флаг матча и снимков: " + str(enabled))
		mode.start()
		_check(mode.throw_with_gate(0, fire.arena[0].id, 0, 0) == OK, "первый бросок записи")
		mode.report_landing(0, 0)
		_check(mode.throw_with_gate(1, tide.arena[0].id, 3, 3) == OK, "второй бросок записи")
		mode.report_landing(3, 3)
		_check(_has_event(mode, "card_drawn"), "запись содержит добор: " + str(enabled))
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(mode.debug_snapshot()))
		if not enabled:
			snapshot.erase("elemental_cards")
		var replay := MatchReplay.restore(snapshot)
		_check(replay.error.is_empty(), "повтор записи: " + str(replay.error))
		if replay.error.is_empty():
			var restored: MatchController = replay.controller
			_check(restored.state.elemental_cards == enabled, "повтор восстанавливает режим добора")
			_check(mode.event_log == restored.event_log, "повтор восстанавливает события и порядок добора")

		for p in [0, 1]:
			var new_gate := FORGE if p == 0 else SLUICE
			var new_ability := AFTERBURN if p == 0 else STORED_WAVE
			for turn in 32:
				mode._draw_turn_card(p)
			var ps: PlayerState = mode.state.players[p]
			_check(ps.arena_hand.count(new_gate) == int(enabled) and ps.ability_hand.count(new_ability) == int(enabled),
				"добор содержит свою новую пару ровно один раз только при opt-in")
			_check(ps.arena_hand.count(SLUICE if p == 0 else FORGE) == 0 and ps.ability_hand.count(STORED_WAVE if p == 0 else AFTERBURN) == 0,
				"чужие новые карты не добираются")


func _test_mode_saves() -> void:
	var preset := CardDB.preset_deck(0)
	var elemental := Tournament.deck_ids(preset)
	elemental[1][0] = String(FORGE)
	elemental[2][0] = String(AFTERBURN)
	var new_deck := CardDB.build_deck(elemental[0], elemental[1], elemental[2])
	_check(Tournament.create(new_deck, 1, 8127, "Проверка", "") == null, "старый турнир отклоняет карты нового набора")
	for enabled in [false, true]:
		var deck := new_deck if enabled else preset
		var cup := Tournament.create(deck, 1, 8127, "Проверка", "", enabled)
		_check(cup != null, "регистрация турнира: " + Tournament.creation_error)
		if cup == null:
			continue
		_check(cup.begin_match(cup.next_match().id) == OK, "незавершённая встреча турнира")
		var saved_cup := Tournament.from_dict(JSON.parse_string(JSON.stringify(cup.state)))
		_check(saved_cup.error.is_empty(), "турнир читается: " + saved_cup.error)
		if saved_cup.error.is_empty():
			_check_saved_cup(cup, saved_cup.tournament, enabled, "Турнир")
		if enabled:
			var invalid := cup.state.duplicate(true)
			invalid.rules_version = Tournament.RULES_VERSION
			_check(not Tournament.from_dict(invalid).error.is_empty(), "старое сохранение отклоняет карты нового набора")

		var campaign := Campaign.create(deck, 1, 8127, "Проверка", "", enabled)
		_check(campaign != null, "регистрация кампании: " + Campaign.creation_error)
		if campaign == null:
			continue
		var next := campaign.cup.next_match()
		_check(campaign.begin_match(next.id) == OK, "незавершённая встреча кампании")
		var saved_campaign := Campaign.from_dict(JSON.parse_string(JSON.stringify(campaign.state)))
		_check(saved_campaign.error.is_empty(), "кампания читается: " + saved_campaign.error)
		if saved_campaign.error.is_empty():
			_check_saved_cup(campaign.cup, saved_campaign.campaign.cup, enabled, "Кампания")
			_check(Tournament._equivalent(campaign.state, saved_campaign.campaign.state), "кампания сохраняет полное состояние")
			_check_campaign_advance(saved_campaign.campaign, enabled)
	_test_career_save()


func _check_saved_cup(before: Tournament, after: Tournament, enabled: bool, label: String) -> void:
	var rules_version := 2 if enabled else 1
	_check(after.state.rules_version == rules_version and after.uses_elemental_cards() == enabled, "%s: сохранена версия правил %d" % [label, rules_version])
	_check(Tournament._equivalent(before.state, after.state) and not String(after.state.in_progress).is_empty(),
		"%s: сетка, колоды и незавершённый матч сохранены" % label)
	var ids := Tournament.deck_ids(after.participant_deck(0))
	_check(ids[1].has(String(FORGE)) == enabled, "%s: Горнило в сохранённой колоде" % label)


func _check_campaign_advance(campaign: Campaign, enabled: bool) -> void:
	for step in 18:
		if campaign.cup.completed():
			break
		var duel := campaign.cup.next_match()
		if campaign.record_result(duel.id, duel.a, [3, 0], "fixture") != OK:
			break
	var advanced := campaign.advance_cup()
	_check(advanced == OK, "загруженная кампания продвигается в следующий кубок")
	if advanced == OK:
		_check(campaign.cup.uses_elemental_cards() == enabled and campaign.state.cups[0].rules_version == campaign.state.cups[1].rules_version,
			"новый кубок наследует версию правил кампании")
		_check(Tournament.deck_ids(campaign.cup.participant_deck(0))[1].has(String(FORGE)) == enabled, "колода переходит в следующий кубок")


func _test_career_save() -> void:
	var career := Career.create("fire", 1, 8127, "Проверка", "")
	_check(career != null, "создание карьеры: " + Career.creation_error)
	if career == null:
		return
	var registration := career.start_cup(career.starter_deck())
	_check(registration == OK, "регистрация в карьерный кубок с правилами 1: " + career.last_error)
	if registration != OK:
		return
	_check(career.begin_match(career.cup.next_match().id) == OK, "незавершённая встреча карьеры с правилами 1")
	var legacy_save := Career.from_dict(JSON.parse_string(JSON.stringify(career.state)))
	_check(legacy_save.error.is_empty(), "карьера с правилами 1 читается: " + legacy_save.error)
	if not legacy_save.error.is_empty():
		return
	_check_saved_cup(career.cup, legacy_save.career.cup, false, "Карьера")
	career = legacy_save.career
	for step in 18:
		if career.cup.completed():
			break
		var duel := career.cup.next_match()
		if career.record_result(duel.id, duel.a, [3, 0], "fixture") != OK:
			break
	var archived := career.replay_cup()
	_check(archived == OK and career.state.cups[0].tournament.rules_version == 1, "прошлый карьерный кубок хранит правила 1")
	if archived != OK:
		return

	_check(career.purchase(String(FORGE)) == OK, "новые ворота приобретаются за кредиты")
	var ids := Tournament.deck_ids(career.starter_deck())
	ids[1][0] = String(FORGE)
	var deck := CardDB.build_deck(ids[0], ids[1], ids[2])
	var levels := {}
	for id in ids[0]:
		levels[id] = 1
	registration = career.start_cup(deck, levels, true)
	_check(registration == OK, "регистрация в карьерный кубок с правилами 2: " + career.last_error)
	if registration != OK:
		return
	_check(career.begin_match(career.cup.next_match().id) == OK, "незавершённая встреча карьеры с правилами 2")
	var saved := Career.from_dict(JSON.parse_string(JSON.stringify(career.state)))
	_check(saved.error.is_empty(), "карьера с правилами 1 и 2 читается: " + saved.error)
	if saved.error.is_empty():
		_check_saved_cup(career.cup, saved.career.cup, true, "Карьера")
		_check(Tournament._equivalent(career.state, saved.career.state), "карьера сохраняет старый архив, покупку и активный кубок")
