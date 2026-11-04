extends SceneTree
## Узкие контрпозиции скрытых ворот и двух ответов; без матчевой серии/сцены.
var failures := 0
var assertions := 0

class PairAI extends AIPlayer:
	var reply_pool: Array = [[&"ability_light_crown"], [&"ability_light_glint"]]
	func _public_card_pool(_view: MatchState, _foe: int, kind: int) -> Array:
		if kind == CardDef.Kind.ABILITY:
			return reply_pool.duplicate(true)
		return []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func board(player: int) -> MatchState:
	var state := MatchState.new()
	state.manual_gates = true
	for p in 2:
		var el: String = "gale" if p == player else "light"
		for i in 3:
			var uid: int = p * 3 + i
			var sp: String = ["levian", "ratnik", "dragnar"][i] if p == player else ["dragnar", "ratnik", "levian"][i]
			state.creatures[uid] = CreatureState.new(uid, StringName("creature_%s_%s" % [sp, el]), p)
			state.players[p].creature_uids.append(uid)
	var gate := state.slots[0]
	gate.has_card = true
	gate.card_owner = 1 - player
	gate.card_id = &"arena_den_dragnar"
	gate.occupant_uid = (1 - player) * 3
	state.creatures[gate.occupant_uid].slot = 0
	return state

func hidden_gate_positions() -> void:
	var reference := -1.0
	for player in 2:
		var full := board(player)
		var uid := player * 3
		var occ := (1 - player) * 3
		var ai := AIPlayer.new(player, 701, -1.0, AIPlayer.Difficulty.HARD)
		var view := full.duplicate_view(player)
		check(view.slots[0].card_id == &"", "настоящие скрытые ворота не переданы ИИ")
		check(ai._hidden_guard_gate(view, uid, occ, 0) == &"arena_den_dragnar", "публичное Логово опаснее одного Поля")
		var field_chance := ai._attack_win_prob(view, uid, occ, 0, &"arena_field_light")
		var den_chance := ai._attack_win_prob(view, uid, occ, 0, &"arena_den_dragnar")
		check(den_chance <= field_chance, "Логово не оценено безопаснее Поля")
		# Буря из baseline: Подмена выглядит достаточной на нейтральных воротах/Поле,
		# но не должна обещать безопасный заход в возможное Логово защитника.
		view.players[player].ability_hand.assign([&"ability_gale_swap", &"ability_gale_gust", &"ability_ratnik_oath"])
		view.players[1 - player].ability_hand.assign([&"", &"", &""])
		var speculative := ai._attack_win_prob(view, player * 3 + 1, occ, 0)
		var guarded := ai._attack_win_prob(view, player * 3 + 1, occ, 0, ai._hidden_guard_gate(view, player * 3 + 1, occ, 0))
		check(speculative > guarded, "Подмена не маскирует риск возможного Логова")
		check(ai._score(view, player * 3 + 1, 0) < 900.0, "ложная атака Подменой не проходит порог принудительного боя")
		view.players[player].ability_hand.clear()
		view.players[1 - player].ability_hand.clear()
		var score := ai._score(view, uid, 0)
		full.slots[0].card_id = &"arena_funnel"
		full.players[1 - player].ability_hand.assign([&"ability_light_glint"])
		var masked := full.duplicate_view(player)
		var old := ai._score(masked, uid, 0)
		full.slots[0].card_id = &"arena_den_ratnik"
		full.players[1 - player].ability_hand.assign([&"ability_light_crown"])
		check(is_equal_approx(old, ai._score(full.duplicate_view(player), uid, 0)), "скрытые ID одинакового размера не меняют прогноз")
		check(not view.slots[0].revealed and view.slots[0].card_id == &"" and not full.slots[0].revealed, "прогноз не открывает/меняет настоящий матч и вид")
		if reference >= 0.0:
			check(is_equal_approx(reference, score), "перестановка playerID не меняет оценку")
		reference = score
		# Уже раскрытый экземпляр не может одновременно быть другой скрытой картой.
		view.slots[1].has_card = true
		view.slots[1].card_owner = 1 - player
		view.slots[1].revealed = true
		view.slots[1].card_id = &"arena_den_dragnar"
		check(ai._hidden_guard_gate(view, uid, occ, 0) != &"arena_den_dragnar", "публично выложенный экземпляр исключён из гипотез")

func paired_replies() -> void:
	for player in 2:
		var state := board(player)
		var uid := player * 3
		var occ := (1 - player) * 3
		var a := CreatureDef.make(&"forecast_attacker", "attacker", Attr.A.GALE, 580, Color.WHITE)
		a.species = &"levian"
		var d := CreatureDef.make(&"forecast_defender", "defender", Attr.A.LIGHT, 460, Color.WHITE)
		d.species = &"dragnar"
		CardDB._creatures[String(a.id)] = a
		CardDB._creatures[String(d.id)] = d
		state.creatures[uid].def_id = a.id
		state.creatures[occ].def_id = d.id
		state.slots[0].card_id = &""
		state.players[1 - player].ability_hand.assign([&"", &""])
		var ai := PairAI.new(player, 702, -1.0, AIPlayer.Difficulty.HARD)
		var r := PowerCalc.compute_seq(state, uid, occ, 0, [])
		check(r.powers == [580, 460], "контрпозиция: перевес120 G")
		for id in [&"ability_light_crown", &"ability_light_glint"]:
			check(ai._margin(ai._with_card(state, r, id, 1), 0) > 0.0, "один малый ответ не переворачивает бой")
		var first := ai._with_card(state, r, &"ability_light_crown", 1)
		var both := ai._with_card(state, first, &"ability_light_glint", 1)
		check(both.winner_uid == occ, "две настоящие карты вместе переворачивают бой")
		check(is_equal_approx(ai._flip_prob(state, r, 0), 1.0), "две карты в публичном изолированном пуле дают реальный риск пары")
		ai.reply_pool = [[&"ability_light_crown", &"ability_light_glint", &"ability_light_reserve"]]
		check(is_equal_approx(ai._flip_prob(state, r, 0), 1.0 / 3.0), "пара среди трёх ID имеет совместную вероятность1/3, а не сумму одиночных")
		ai.reply_pool = [[&"ability_light_crown"], [&"ability_light_glint"]]
		r.ability_counts[1] = 2
		check(is_zero_approx(ai._flip_prob(state, r, 0)), "один оставшийся ответ не позволяет пару")
		r.ability_counts[1] = 0
		state.players[1 - player].ability_hand.resize(1)
		check(is_zero_approx(ai._flip_prob(state, r, 0)), "одна скрытая карта исключает пару")
		state.players[1 - player].ability_hand.resize(2)
		r.passed[1] = true
		check(is_zero_approx(ai._flip_prob(state, r, 0)), "два паса завершают бой без воображаемой пары")
		r.passed[1] = false
		state.players[1 - player].abilities_used.assign([&"ability_light_crown"])
		check(is_zero_approx(ai._flip_prob(state, r, 0)), "публично отдыхающая карта не входит в пару")

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	hidden_gate_positions()
	paired_replies()
	print("AI forecast positions: %d assertions; %d failures" % [assertions, failures])
	quit(1 if failures else 0)
