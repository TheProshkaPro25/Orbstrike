extends "res://tests/rules_edge_tests.gd"
## 0.3.3: изолированные позиции новых карт, без массовой симуляции/графики.
const TOLL := &"ability_fire_toll"
const CALL := &"ability_gale_call"
const RESERVE := &"ability_light_reserve"
const CEILING := &"ability_stone_ceiling"
const TRIUMPH := &"ability_shadow_triumph"
const WASH := &"ability_tide_wash"
const VALOR := &"arena_valor"
const COPY033 := &"ability_stone_copy"
const BIG := &"ability_test_033_big"
const FUSION033 := &"ability_test_033_fusion"
const TEST_IDS := [ZH, VI, LU, GR, SU, MA]
var observations033: Array = []

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	_add_test_creatures()
	CardDB._cards[String(BIG)] = CardDef.make(BIG, "+180", 1, &"boost", {"amount": 180}, "")
	CardDB._cards[String(FUSION033)] = CardDef.make(FUSION033, "+160", 1, &"fusion_boost", {"amount": 160, "fusion": true}, "")
	_test_toll033()
	_test_ceiling033()
	_test_wash033()
	_test_wash_special033()
	_test_suppression_and_rest033()
	_test_call033()
	_test_reserve033()
	_test_triumph033()
	_test_valor033()
	_test_ai033()
	_test_codec033()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var f := FileAccess.open(args[0], FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"assertions": _checks, "failures": _failures, "observations": observations033, "scope": "Узкие позиции 7 карт: обе стороны, отмены, цели, исходы, ИИ, codec. Без winrate/физики/визуальной оценки."}, "\t") + "\n")
	print("Cards 0.3.3: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)

func _s033(element: int = 0, gate: StringName = NEUTRAL) -> MatchState:
	var s := _mk_state(TEST_IDS[element], TEST_IDS[element], gate)
	s.ruleset = MatchRules.Ruleset.ANIME_INSPIRED
	s.manual_gates = true
	s.slots[0].revealed = true
	return s

func _r033(s: MatchState, plays: Array, expected: Array, label: String) -> BattleResult:
	var r := _seq(s, plays)
	_check(r.powers == expected, label + ": " + str(r.powers))
	var totals := [0, 0]
	for line in r.breakdown: totals[int(line.side)] += int(line.delta)
	_check(totals == r.powers, label + ": breakdown")
	return r

func _test_toll033() -> void:
	for side in [0, 1]:
		var foe: int = 1 - side
		var s := _s033()
		var base := [340, 340]
		_r033(s, [[side, TOLL]], base, "Пошлина без стартовой силы")
		var expected := base.duplicate()
		expected[foe] += 60 # 3 × 60 усиление, но не больше двух штрафов
		var blue := CardDB.card(PLUS)
		var old: int = int(blue.params.amount)
		blue.params.amount = 60
		_r033(s, [[side, TOLL], [foe, PLUS], [foe, PLUS], [foe, PLUS]], expected, "Пошлина максимум120")
		blue.params.amount = old
		expected = base.duplicate(); expected[foe] += 80
		_r033(s, [[foe, PLUS], [side, TOLL]], expected, "ранняя карта не облагается")
		_r033(s, [[side, TOLL], [foe, PLUS], [side, SHIELD]], [340, 280] if foe == 1 else [280, 340], "отменённая поздняя карта потрачена")
		expected = base.duplicate(); expected[foe] += 80
		_r033(s, [[side, TOLL], [foe, PLUS], [foe, SHIELD]], expected, "отмена Пошлины снимает штраф")
		s.slots[0].card_id = &"arena_mute"; s.slots[0].card_owner = foe
		_r033(s, [[side, TOLL], [foe, PLUS]], expected, "Глухие гасят Пошлину")

func _test_ceiling033() -> void:
	for side in [0, 1]:
		var foe: int = 1 - side
		var s := _s033(3)
		var expected := [370, 370]; expected[foe] += 280
		_r033(s, [[foe, BIG], [side, CEILING], [foe, BIG]], expected, "Свод не режет прежние прибавки")
		expected = [570, 570]
		_r033(s, [[side, CEILING], [foe, BIG], [foe, FUSION033], [side, BIG], [side, FUSION033]], expected, "каждая карта и слияние cap100 обеим сторонам")
		expected = [370, 370]; expected[foe] += 180
		_r033(s, [[side, CEILING], [foe, SHIELD], [foe, BIG]], expected, "отмена Свода возвращает прибавку")
		expected = [370, 370]; expected[side] -= 80; expected[foe] += 100
		_r033(s, [[side, CEILING], [foe, MINUS], [foe, BIG]], expected, "штраф не ограничен Сводом")
		var copied := _seq(s, [[side, CEILING], [foe, COPY033], [side, BIG]])
		_check(copied.powers[side] == 470 and copied.copies.has([foe, COPY033, CEILING]), "Копия включает cap для следующих карт")

func _test_wash033() -> void:
	for side in [0, 1]:
		var foe: int = 1 - side
		var s := _s033(5)
		s.creatures[side].marks = [{"delta": -150}]
		_r033(s, [[side, WASH]], [320, 320], "Волна ровно до базы")
		var expected := [320, 320]; expected[side] -= 80
		_r033(s, [[side, WASH], [foe, MINUS]], expected, "поздний штраф после Волны")
		expected = [320, 320]; expected[side] -= 150
		_r033(s, [[side, WASH], [foe, SHIELD]], expected, "отмена Волны убирает восстановление")
		_r033(s, [[foe, CEILING], [side, WASH]], [320, 320], "Свод не ломает точное восстановление")

## player может быть атакующим и защитником. Все шесть uid настоящие объекты контроллера.
func _c033(player: int, element: int, hand: Array, winning: bool = true, gate: StringName = NEUTRAL) -> MatchController:
	var ctrl := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(1), 33303)
	ctrl._draw_pools = [[[], []], [[], []]]
	ctrl.start()
	for i in 6:
		_set_card(ctrl, i, NEUTRAL, i % 2)
	for p in [0, 1]:
		ctrl.state.players[p].ability_hand.assign(hand if p == player else [PLUS, SHIELD])
		ctrl.state.creatures[p * 3].def_id = TEST_IDS[element]
	var own := player * 3
	ctrl.state.creatures[own].marks = [{"delta": 150 if winning else -150}]
	_stand(ctrl, 3, 1)
	_set_card(ctrl, 1, gate, player)
	ctrl._turn_player = 0
	ctrl._start_battle(0, 3, 1)
	if player == 1:
		_check(ctrl.pass_ability(0) == OK, "передача ответа защитнику")
	return ctrl

func _p033(ctrl: MatchController, player: int, id: StringName, target: Dictionary = {}) -> void:
	_check(ctrl.legal_abilities(player).has(id), "разрешена " + String(id))
	_check(ctrl.play_ability(player, id, target) == OK, "разыграна " + String(id))

func _test_call033() -> void:
	for player in [0, 1]:
		for cancelled in [false, true]:
			var ctrl := _c033(player, 1, [CALL, PLUS])
			var ally: int = player * 3 + 1
			_stand(ctrl, ally, 4)
			_check(ctrl.legal_ability_targets(player, CALL).any(func(t: Dictionary) -> bool: return t.get("target_uid", -1) == ally), "Зов видит союзника")
			_check(ctrl.play_ability(player, CALL, {"target_uid": (1 - player) * 3}) != OK and ctrl.state.players[player].ability_hand.has(CALL), "чужая цель не тратит карту")
			_p033(ctrl, player, CALL, {"target_uid": ally})
			if cancelled: _p033(ctrl, 1 - player, SHIELD)
			_pass_windows(ctrl)
			_check(ctrl.state.creatures[ally].slot == (4 if cancelled else -1), "Зов: цель перемещена только без отмены")
			_check(ctrl.state.creatures[ally].alive, "Зов не убивает союзника")
		var lost := _c033(player, 1, [CALL, PLUS], false)
		_stand(lost, player * 3 + 1, 4)
		_p033(lost, player, CALL, {"target_uid": player * 3 + 1})
		_pass_windows(lost)
		_check(lost.state.creatures[player * 3 + 1].slot == 4, "при поражении цель остаётся")
		var gone := _c033(player, 1, [CALL, PLUS])
		_stand(gone, player * 3 + 1, 4)
		_p033(gone, player, CALL, {"target_uid": player * 3 + 1})
		gone.state.creatures[player * 3 + 1].slot = -1
		gone.state.slots[4].occupant_uid = -1
		_check(gone.get_battle_preview().called_uids[player] == -1, "ушедшая цель не заменяется другой")
	_check(not CardEffects.copyable(CardDB.card(CALL)), "Зов не копируется без своей цели")

func _test_reserve033() -> void:
	var blue := &"ability_light_guard"
	for player in [0, 1]:
		for cancelled in [false, true]:
			var ctrl := _c033(player, 2, [RESERVE, PLUS])
			var ps: PlayerState = ctrl.state.players[player]
			ps.abilities_used.append(blue); ps.ability_cooldown[blue] = 2
			_check(ctrl.legal_ability_targets(player, RESERVE).any(func(t: Dictionary) -> bool: return StringName(t.get("target_card", "")) == blue), "резерв предлагает синюю прошлого боя")
			_check(ctrl.play_ability(player, RESERVE, {"target_card": PLUS}) != OK and ps.ability_hand.has(RESERVE), "нельзя вернуть карту текущей руки")
			_p033(ctrl, player, RESERVE, {"target_card": blue})
			_check(not ps.ability_hand.has(blue), "резерв не возвращает до исхода")
			if cancelled: _p033(ctrl, 1 - player, SHIELD)
			_pass_windows(ctrl)
			_check(ps.ability_hand.has(blue) == not cancelled, "возврат запаса зависит от отмены")
			_check(ps.ability_hand.count(blue) <= 1, "резерв без дубликата")
		var current := _c033(player, 2, [RESERVE, PLUS])
		current.state.players[player].abilities_used.append(blue)
		current.state.players[player].ability_cooldown[blue] = 2
		current._b_plays.append([player, blue])
		_check(current.legal_ability_targets(player, RESERVE).is_empty(), "карта текущего боя не цель запаса")
	_check(not CardEffects.copyable(CardDB.card(RESERVE)), "запас не копируется без своей цели")

func _test_triumph033() -> void:
	for player in [0, 1]:
		for cancelled in [false, true]:
			var ctrl := _c033(player, 4, [TRIUMPH, PLUS], false)
			_p033(ctrl, player, TRIUMPH)
			if cancelled: _p033(ctrl, 1 - player, SHIELD)
			_pass_windows(ctrl)
			_check(not ctrl.state.creatures[player * 3].alive, "Триумф не спасает проигравшего")
			_check(ctrl.get_active_player() == (1 - player if cancelled else player), "Триумф меняет только следующий ход")
			_check(ctrl.state.players[1 - player].captured.has(NEUTRAL), "трофей остаётся победителю")
		var last := _c033(player, 4, [TRIUMPH, PLUS], false)
		for uid in last.state.players[player].creature_uids:
			if uid != player * 3: last.state.creatures[uid].alive = false
		_p033(last, player, TRIUMPH); _pass_windows(last)
		_check(last.get_phase() == MatchController.Phase.GAME_OVER and last.winner == 1 - player, "Триумф не отменяет конец матча")

func _test_valor033() -> void:
	for player in [0, 1]:
		for margin in [0, 1, 50, 51]:
			var ctrl := _c033(player, 0, [PLUS], false, VALOR)
			ctrl.state.creatures[player * 3].marks = [{"delta": -margin}]
			ctrl.state.slots[1].revealed = true
			var r := ctrl.get_battle_preview()
			var saved: bool = margin > 0 and margin <= 50
			_check((r.valor_saved_uid == player * 3) == saved, "Доблесть граница " + str(margin))
			_pass_windows(ctrl)
			if margin > 0:
				_check(ctrl.state.creatures[player * 3].alive == saved, "Доблесть фактическое спасение " + str(margin))
		var closed := _c033(player, 0, [PLUS], false, VALOR)
		closed.state.creatures[player * 3].marks = [{"delta": -30}]
		_check(closed.get_battle_preview().valor_saved_uid < 0, "закрытая Доблесть не спасает")
		for gate in [&"arena_hold", &"arena_limit", &"arena_clash"]:
			var s := _s033(0, gate)
			_check(not _seq(s, []).ordinary, "особые ворота не обычный исход " + String(gate))

func _test_ai033() -> void:
	for player in [0, 1]:
		for difficulty in [AIPlayer.Difficulty.NORMAL, AIPlayer.Difficulty.HARD]:
			var ai := AIPlayer.new(player, 333, -1.0, difficulty)
			var ctrl := _c033(player, 1, [CALL], true)
			_stand(ctrl, player * 3 + 1, 4)
			ctrl.state.players[1 - player].ability_hand.clear()
			var preview := ctrl.get_battle_preview()
			var view := ctrl.get_view(player)
			var before := JSON.stringify(OnlineStateCodec.encode_view(view))
			_check(ai.choose_ability(view, preview, [CALL]) == CALL, "ИИ применяет послебоевое извлечение союзника")
			var target := ai.choose_ability_target(view, preview, CALL, ctrl.legal_ability_targets(player, CALL))
			_check(target.get("target_uid", -1) == player * 3 + 1, "ИИ передаёт явную цель Зова")
			_check(before == JSON.stringify(OnlineStateCodec.encode_view(view)), "ИИ не меняет вид")
			ctrl = _c033(player, 2, [RESERVE], true)
			ctrl.state.players[player].abilities_used.append(&"ability_light_guard")
			ctrl.state.players[player].ability_cooldown[&"ability_light_guard"] = 2
			ctrl.state.players[1 - player].ability_hand.clear()
			_check(ai.choose_ability(ctrl.get_view(player), ctrl.get_battle_preview(), [RESERVE]) == RESERVE, "ИИ возвращает синюю прошлого боя")
			ctrl = _c033(player, 4, [TRIUMPH], false)
			ctrl.state.players[1 - player].ability_hand.clear()
			_check(ai.choose_ability(ctrl.get_view(player), ctrl.get_battle_preview(), [TRIUMPH]) == TRIUMPH, "ИИ перехватывает следующий ход при поражении")
			ctrl = _c033(player, 0, [PLUS], false, VALOR)
			ctrl.state.creatures[player * 3].marks = [{"delta": -30}]
			_check(ai.should_open_gate(ctrl.get_view(player), ctrl.get_battle_preview()), "ИИ открывает спасение без числовой прибавки")

func _test_codec033() -> void:
	var ctrl := _c033(0, 1, [CALL], true)
	_stand(ctrl, 1, 4)
	_p033(ctrl, 0, CALL, {"target_uid": 1})
	var before := ctrl.get_battle_preview()
	var payload: Dictionary = JSON.parse_string(JSON.stringify(OnlineStateCodec.preview(before)))
	var after := OnlineStateCodec.decode_battle(payload, ctrl.get_view(0))
	_check(after.called_uids == before.called_uids and after.battle_plays == payload.battle_plays, "codec сохраняет явную цель Зова")
	_check(after.ordinary == before.ordinary and after.valor_saved_uid == before.valor_saved_uid, "codec сохраняет новые признаки исхода")
	var s := _s033(2)
	s.players[0].abilities_used.append(&"ability_light_guard")
	s.players[0].ability_cooldown[&"ability_light_guard"] = 2
	var reserve := _seq(s, [[0, RESERVE, {"target_card": &"ability_light_guard"}]])
	var copy := OnlineStateCodec.decode_battle(JSON.parse_string(JSON.stringify(OnlineStateCodec.preview(reserve))))
	_check(copy.reserve_cards == reserve.reserve_cards, "codec сохраняет цель запаса")


func _test_wash_special033() -> void:
	for side in [0, 1]:
		var foe: int = 1 - side
		var s := _s033(5, &"arena_weight")
		# Тестовый боец с базой450 попадает под Гнёт; определение лишь в локальном словаре.
		var id := StringName("test_033_tide450")
		var d := CreatureDef.make(id, "Прилив450", 5, 450, Color.WHITE)
		d.species = &"levian"
		CardDB._creatures[String(id)] = d
		s.creatures[side].def_id = id
		var before := _seq(s, [])
		_check(before.powers[side] == 350, "Гнёт уменьшил базу450 до350")
		var washed := _seq(s, [[side, WASH]])
		_check(washed.powers[side] == 450, "Волна восстанавливает видимую силу после Гнёта")
		var late := _seq(s, [[side, WASH], [foe, MINUS]])
		_check(late.powers[side] == 370, "поздний штраф после восстановления Гнёта")
		var cancelled := _seq(s, [[side, WASH], [foe, SHIELD]])
		_check(cancelled.powers[side] == 350, "отмена Волны возвращает Гнёт")
		s.slots[0].card_id = NEUTRAL
		s.creatures[side].marks = [{"fix": 200}]
		_check(_seq(s, [[side, WASH]]).powers[side] == 450, "Волна после фиксированной метки")
		_check(_seq(s, [[side, WASH], [foe, MINUS]]).powers[side] == 370, "поздний штраф после фиксированной метки")
		_check(_seq(s, [[side, WASH], [foe, &"ability_kolossar_reset"]]).powers[side] == 450, "поздний сброс после Волны задаёт базу")
		_check(_seq(s, [[side, WASH], [foe, SHIELD]]).powers[side] == 200, "отмена Волны возвращает фиксацию")
		s = _s033(5, &"arena_mirror")
		s.creatures[foe].marks = [{"delta": -100}]
		_check(_seq(s, []).powers[side] == 220, "Зеркало показывает220")
		_check(_seq(s, [[side, WASH]]).powers[side] == 320, "Волна под Зеркалом ровно до собственной базы")

func _test_suppression_and_rest033() -> void:
	var cards := [TOLL, CALL, RESERVE, CEILING, TRIUMPH, WASH]
	for element in 6:
		var id: StringName = cards[element]
		for side in [0, 1]:
			var foe: int = 1 - side
			var s := _s033(element, &"arena_mute")
			s.slots[0].card_owner = foe
			var result := _seq(s, [[side, id]])
			_check(result.cancelled_plays.has([side, id]), "Глухие подавляют " + String(id))
			_check(result.called_uids[side] < 0 and result.reserve_cards[side] == &"" and not result.triumph[side], "нет подавленных последствий " + String(id))
			var silenced := _s033(element)
			result = _seq(silenced, [[foe, &"ability_tide_hush"], [side, id]])
			_check(result.cancelled_plays.has([side, id]), "Тишь подавляет следующую " + String(id))
			var ctrl := _c033(side, element, [id, PLUS], true)
			var target: Dictionary = {}
			if id == CALL:
				_stand(ctrl, side * 3 + 1, 4); target = {"target_uid": side * 3 + 1}
			elif id == RESERVE:
				ctrl.state.players[side].abilities_used.append(&"ability_light_guard")
				ctrl.state.players[side].ability_cooldown[&"ability_light_guard"] = 2
				target = {"target_card": &"ability_light_guard"}
			elif id == WASH:
				ctrl.state.creatures[side * 3].marks = [{"delta": -50}]
				ctrl.state.creatures[foe * 3].def_id = VI
			_p033(ctrl, side, id, target)
			_pass_windows(ctrl)
			_check(ctrl.state.players[side].ability_cooldown.get(id, 0) == 2, "новая карта отдыхает два следующих боя " + String(id))
	# Тот же ID, сыгранный соперником, не мешает вернуть свой экземпляр прошлого боя.
	for side in [0, 1]:
		var s := _s033(2)
		s.players[side].abilities_used.append(&"ability_light_guard")
		s.players[side].ability_cooldown[&"ability_light_guard"] = 2
		var plays: Array = [[1 - side, &"ability_light_guard"], [side, RESERVE, {"target_card": &"ability_light_guard"}]]
		_check(_seq(s, plays).reserve_cards[side] == &"ability_light_guard", "чужой одноимённый текущий ID не блокирует резерв")
		# Отмена единственного источника не должна оставлять скопированный эффект Пошлины.
		s = _s033(0)
		var r := _seq(s, [[side, TOLL], [1 - side, COPY033], [1 - side, SHIELD]])
		_check(not r.copies.has([1 - side, COPY033, TOLL]), "отмена источника Пошлины убирает его из Копии")
