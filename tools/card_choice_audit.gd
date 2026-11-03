extends SceneTree
## Анализ сохранённых решений CARD-10. Повторяет команды, не запускает новую серию ИИ.
var failures := 0
var cards := {}
var joint := {}
const PAIRS := [[&"ability_fire_spark", &"ability_fire_drain"], [&"ability_fire_assault", &"ability_fire_drain"], [&"ability_light_glint", &"ability_light_crown"], [&"ability_stone_firm", &"ability_stone_copy"]]

func _initialize() -> void:
	CardDB.load_all()
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("FAIL: нужны путь матчей и путь отчёта")
		quit(1)
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var decisions := 0
	for index in data.matches.size():
		var row: Dictionary = data.matches[index]
		var side := int(row.side)
		var d: Array = row.decks
		var subject := CardDB.build_deck(d[0][0], d[0][1], d[0][2])
		var foe := CardDB.build_deck(d[1][0], d[1][1], d[1][2])
		var ctrl := MatchController.new(subject if side == 0 else foe, foe if side == 0 else subject, int(row.seed))
		ctrl.landing_window = true
		var first: int = index - index % 2
		for pool in ctrl._draw_pools[side]:
			for id in [data.matches[first].target, data.matches[first + 1].target]: pool.erase(StringName(id))
		for action in row.actions:
			var name := String(action[0])
			if not MatchReplay.ALLOWED.has(name):
				failures += 1
				continue
			var values: Array = action[1].duplicate()
			for i in values.size():
				if typeof(values[i]) == TYPE_STRING: values[i] = StringName(values[i])
				elif typeof(values[i]) == TYPE_FLOAT: values[i] = int(values[i])
			if name in ["play_ability", "pass_ability"] and ctrl.get_phase() == MatchController.Phase.ABILITY_WINDOW and ctrl.get_active_player() == side:
				decisions += 1
				audit(ctrl, side, StringName(values[1]) if name == "play_ability" else &"")
			var result: Variant = ctrl.callv(name, values)
			if result != null and int(result) != OK: failures += 1
		if ctrl.get_phase() != MatchController.Phase.GAME_OVER or hash(ctrl.action_trace) != int(row.trace_hash): failures += 1
	var out := {"replayed_matches": data.matches.size(), "battle_decisions": decisions, "failures": failures, "cards": cards, "joint": joint,
		"limits": "Повтор тех же 104 записей, не новые матчи. Счётчики окон решений коррелированы; локальная победа без будущего ответа не является вероятностью выигрыша боя или матча."}
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	if f == null: failures += 1
	else:
		f.store_string(JSON.stringify(out, "\t") + "\n")
		f.close()
	if failures: printerr("FAIL: ошибок аудита ", failures)
	print("CARD-10 аудит: ", data.matches.size(), " повторов, ", decisions, " решений, ", failures, " ошибок")
	quit(1 if failures else 0)

func audit(ctrl: MatchController, player: int, chosen: StringName) -> void:
	var legal := ctrl.legal_abilities(player)
	var r := ctrl.get_battle_preview()
	var side := 0 if ctrl.state.creatures[r.attacker_uid].owner == player else 1
	var uid := r.attacker_uid if side == 0 else r.defender_uid
	var winning := []
	for id in ctrl.state.players[player].ability_hand:
		var key := String(id)
		if not cards.has(key): cards[key] = {"hand_windows": 0, "legal_windows": 0, "chosen": 0, "immediate_win_windows": 0, "legal_while_losing": 0}
		cards[key].hand_windows += 1
		if not legal.has(id): continue
		cards[key].legal_windows += 1
		var after := PowerCalc.compute_with(ctrl.state, r.attacker_uid, r.defender_uid, r.slot, r.battle_plays, side, id)
		if after.winner_uid == uid:
			cards[key].immediate_win_windows += 1
			winning.append(id)
		if r.winner_uid != uid: cards[key].legal_while_losing += 1
		if chosen == id: cards[key].chosen += 1
	for pair in PAIRS:
		if not legal.has(pair[0]) or not legal.has(pair[1]): continue
		var key := String(pair[0]) + "/" + String(pair[1])
		if not joint.has(key): joint[key] = {"both_legal": 0, "chosen_a": 0, "chosen_b": 0, "pass_or_other": 0, "a_immediate_win": 0, "b_immediate_win": 0}
		joint[key].both_legal += 1
		if chosen == pair[0]: joint[key].chosen_a += 1
		elif chosen == pair[1]: joint[key].chosen_b += 1
		else: joint[key].pass_or_other += 1
		if winning.has(pair[0]): joint[key].a_immediate_win += 1
		if winning.has(pair[1]): joint[key].b_immediate_win += 1
