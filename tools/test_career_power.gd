extends SceneTree
## Изолированный контракт матчевой БС, без моделей, физики и массовых матчей.

var checks := 0
var failures := 0

func _initialize() -> void:
	preload("res://tools/test_window.gd").background(self)
	CardDB.load_all()
	var catalogue: Dictionary = {}
	for id in CardDB.creature_ids():
		catalogue[String(id)] = CardDB.creature(id).base_power
	_test_snapshots_and_replay()
	_test_power_effects()
	_test_controller_and_ai()
	_test_simulator_validation()
	for id in catalogue:
		_check(CardDB.creature(StringName(id)).base_power == catalogue[id], "каталог неизменен: " + id)
	print("CAREER POWER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)

func _controller() -> MatchController:
	return MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(0), 6159)

func _test_snapshots_and_replay() -> void:
	var ctrl := _controller()
	var id: StringName = ctrl.state.creatures[0].def_id
	var original: int = CardDB.creature(id).base_power
	_check(PowerCalc.base_power(ctrl.state, 0) == original and PowerCalc.base_power(ctrl.state, 3) == original, "обычная дуэль использует каталог")
	_check(not ctrl.debug_snapshot().has("power_snapshots"), "старый формат реплея без лишнего поля")
	var old_replay := MatchReplay.restore(ctrl.debug_snapshot())
	_check(old_replay.error == "" and PowerCalc.base_power(old_replay.controller.state, 0) == original, "прежний реплей совместим")
	var frozen := {String(id): 200}
	PowerCalc.apply_power_snapshot(ctrl.state, 0, frozen)
	PowerCalc.apply_power_snapshot(ctrl.state, 1, {String(id): 390})
	frozen[String(id)] = 420
	_check(PowerCalc.base_power(ctrl.state, 0) == 200 and PowerCalc.base_power(ctrl.state, 3) == 390, "одинаковый вид: независимая зафиксированная БС сторон")
	_check(CardDB.creature(id).base_power == original, "снимок не мутирует CardDB")
	for copy in [ctrl.state.duplicate_full(), ctrl.get_view(0), ctrl.get_view(1), ctrl.state.duplicate_view(-1)]:
		_check(PowerCalc.base_power(copy, 0) == 200 and PowerCalc.base_power(copy, 3) == 390, "клоны и скрытые виды сохраняют обе БС")
	ctrl.start(0)
	var data: Dictionary = JSON.parse_string(JSON.stringify(ctrl.debug_snapshot()))
	var replay := MatchReplay.restore(data)
	_check(replay.error == "", "JSON-реплей с карьерной БС восстановлен")
	_check(replay.controller.event_log == ctrl.event_log and PowerCalc.base_power(replay.controller.state, 3) == 390, "реплей воспроизводит события и БС")
	for value in [-9, 189, 421, 210.5, 1e100, INF, NAN, "210"]:
		_check(PowerCalc.apply_power_snapshot(ctrl.state, 0, {String(id): value}) == ERR_INVALID_PARAMETER and PowerCalc.base_power(ctrl.state, 0) == 200, "некорректная БС отклонена атомарно: " + str(value))
	_check(PowerCalc.apply_power_snapshot(ctrl.state, 0, {"unknown": 200}) == ERR_INVALID_PARAMETER, "неизвестный id снимка отклонён")
	for bad in [{String(id): 200}, {String(id): 1e100}, {"unknown": 200}]:
		var invalid_data := data.duplicate(true)
		invalid_data.power_snapshots[0] = bad
		_check(not MatchReplay.restore(invalid_data).error.is_empty(), "реплей отклоняет неполный или неверный снимок")
	for value in [210.5, 1e100, 189, 421]:
		var invalid_data := data.duplicate(true)
		invalid_data.power_snapshots[0][String(id)] = value
		_check(not MatchReplay.restore(invalid_data).error.is_empty(), "полный снимок реплея отклоняет неверную БС: " + str(value))
	_check(PowerCalc.apply_power_snapshot(ctrl.state, 0, {}) == OK and PowerCalc.base_power(ctrl.state, 0) == original and PowerCalc.base_power(ctrl.state, 3) == 390, "пустой снимок возвращает fallback только своей стороны")

func _position(species: String = "kolossar", attr: String = "tide", gate: StringName = &"arena_hold") -> MatchState:
	var state := _controller().state
	for uid in [0, 3]:
		state.creatures[uid].def_id = StringName("creature_%s_%s" % [species, attr])
		state.creatures[uid].base_power_override = 200 if uid == 0 else 410
	state.slots[0].has_card = true
	state.slots[0].card_id = gate
	state.slots[0].card_owner = 1
	state.slots[0].revealed = true
	state.creatures[3].slot = 0
	state.slots[0].occupant_uid = 3
	return state

func _test_power_effects() -> void:
	var state := _position()
	_check(PowerCalc.compute_seq(state, 0, 3, 0, []).powers == [200, 410], "расчёт начинает с БС экземпляров")
	state.creatures[0].marks = [{"delta": 150}]
	state.creatures[3].marks = [{"delta": -100}]
	_check(PowerCalc.compute_seq(state, 0, 3, 0, [[0, &"ability_kolossar_reset"]]).powers == [200, 410], "Сброс восстанавливает обе карьерные базы")
	state = _position("dragnar", "tide", &"arena_den_dragnar")
	_check(PowerCalc.compute_seq(state, 0, 3, 0, []).powers == [400, 820], "ворота вида удваивают разные базы")
	_check(PowerCalc.gate_bonus_for(state, 0, 0) == 200 and PowerCalc.gate_bonus_for(state, 3, 0) == 410, "подсказка ворот использует ту же БС")
	state = _position("levian", "tide", &"arena_weight")
	_check(PowerCalc.compute_seq(state, 0, 3, 0, []).powers == [200, 310], "Гнёт проверяет порог силы из снимка")
	state.slots[0].card_id = &"arena_limit"
	var limit := PowerCalc.compute_seq(state, 0, 3, 0, [])
	_check(limit.winner_uid == 0 and not limit.both_lose, "Предел применяет карьерную БС")
	state.slots[0].card_id = &"arena_hold"
	state.creatures[0].marks = [{"delta": -50}]
	_check(PowerCalc.compute_seq(state, 0, 3, 0, [[0, &"ability_tide_wash"]]).powers == [200, 410], "Волна восстанавливает карьерную базу")
	state = _position("klykar", "gale")
	_check(PowerCalc.compute_seq(state, 0, 3, 0, [[0, &"ability_klykar_hunt"]]).powers == [400, 410], "условие слабейшего сравнивает снимки")

func _test_controller_and_ai() -> void:
	var ctrl := _controller()
	ctrl.state = _position("klykar", "gale")
	ctrl.state.players[0].ability_hand = [&"ability_klykar_hunt"]
	ctrl._start_battle(0, 3, 0)
	_check(ctrl.legal_abilities(0).has(&"ability_klykar_hunt"), "контроллер разрешает карту слабейшему по снимку")
	ctrl.state.creatures[0].base_power_override = 420
	_check(not ctrl.legal_abilities(0).has(&"ability_klykar_hunt"), "контроллер запрещает карту сильнейшему по снимку")
	ctrl.state = _position("levian", "tide")
	ctrl.state.players[0].ability_hand = [&"ability_tide_wash", &"ability_tide_spray"]
	ctrl._start_battle(0, 3, 0)
	var bot := AIPlayer.new(0, 17, 0.0, AIPlayer.Difficulty.HARD)
	var pre := ctrl.get_battle_preview()
	_check(not ctrl.legal_abilities(0).has(&"ability_tide_wash") and not bot._forecast_legal(ctrl.get_view(0), pre, &"ability_tide_wash", 0), "UI/ИИ запрещают Волну ровно на новой базе")
	ctrl.state.creatures[0].marks = [{"delta": -30}]
	pre = ctrl.get_battle_preview()
	_check(ctrl.legal_abilities(0).has(&"ability_tide_wash") and bot._forecast_legal(ctrl.get_view(0), pre, &"ability_tide_wash", 0), "UI/ИИ разрешают Волну ниже новой базы")
	ctrl.state.creatures[1].base_power_override = 210
	ctrl.state.creatures[2].base_power_override = 400
	var target := bot._best_ability_target(ctrl.get_view(0), &"ability_gale_call", 0, [{"target_uid": 2}, {"target_uid": 1}])
	_check(target.target_uid == 1, "ИИ выбирает слабого союзника по БС снимка")
	_check(PowerCalc.swap_candidate(ctrl.state, 0, [0]) == 2, "Подмена выбирает сильнейшего из снимка")
	ctrl.state.creatures[1].slot = 1
	ctrl.state.creatures[2].slot = 2
	_check(ctrl._strongest_standing(0) == 2, "тупик выбирает сильнейшего из снимка")
	_check(PowerCalc.gust_target(ctrl.state, 1) == 1, "Шквал выбирает слабейшего из снимка")
	_check(ctrl._alive_power(0) == 810, "лимит матча суммирует БС снимка")

func _test_simulator_validation() -> void:
	var deck := CardDB.preset_deck(0)
	var ids: Array = [[], [], []]
	var snapshot: Dictionary = {}
	for pair in [[deck.creatures, 0], [deck.arena, 1], [deck.abilities, 2]]:
		for definition in pair[0]:
			ids[pair[1]].append(String(definition.id))
	for id in ids[0]:
		snapshot[id] = 200
	_check(TournamentNpcSimulator._snapshot_deck_valid(ids, snapshot), "NPC принимает полную легальную карьерную колоду")
	var high_ids: Array = [["creature_dragnar_fire", "creature_kolossar_fire", "creature_ratnik_fire"], ids[1], ids[2]]
	var low_snapshot: Dictionary = {}
	for id in high_ids[0]:
		low_snapshot[id] = 200
	_check(not CardDB.deck_error(high_ids[0], high_ids[1], high_ids[2]).is_empty() and TournamentNpcSimulator._snapshot_deck_valid(high_ids, low_snapshot), "NPC проверяет лимит по карьерной БС вместо исходной1120G")
	var invalid := snapshot.duplicate()
	invalid[ids[0][0]] = 421
	_check(not TournamentNpcSimulator._snapshot_deck_valid(ids, invalid), "NPC ограничивает отдельную БС")
	invalid = snapshot.duplicate()
	for id in invalid:
		invalid[id] = 400
	_check(not TournamentNpcSimulator._snapshot_deck_valid(ids, invalid), "NPC ограничивает общую БС1100")
	invalid = snapshot.duplicate()
	invalid.erase(ids[0][0])
	_check(not TournamentNpcSimulator._snapshot_deck_valid(ids, invalid), "NPC не принимает неполный снимок")
	_check(not TournamentNpcSimulator.simulate(deck, deck, 17, 0, 1, 1, [], [snapshot]).error.is_empty(), "NPC отклоняет снимок одной стороны")
