extends "res://tools/card_balance_matches.gd"
## 16 матчей: две команды × два seed × обе стороны × до/после только rescue-fallback.
## Числа карт, остальные решения ИИ, команды и добор пары одинаковы.
class RescueAI extends AIPlayer:
	var enabled := true
	var rescue_decisions := 0
	var losing_rescue_decisions := 0
	func _choose_revival(view: MatchState, preview: BattleResult, cards: Array[StringName], side: int) -> StringName:
		if not enabled: return &""
		return super._choose_revival(view, preview, cards, side)
	func choose_ability(view: MatchState, preview: BattleResult, legal = null) -> StringName:
		var chosen := super.choose_ability(view, preview, legal)
		if chosen != &"":
			var side: int = 0 if view.creatures[preview.attacker_uid].owner == player else 1
			var after := _with_card(view, preview, chosen, side)
			if after.revive[side] and _alive_after(view, after, side) > _alive_after(view, preview, side):
				rescue_decisions += 1
				if _margin(after, side) <= 0.0: losing_rescue_decisions += 1
		return chosen

var enabled := true
var subject_side := 0
var actors: Array[RescueAI] = []

func make_ai(player: int, rng_seed: int) -> AIPlayer:
	var ai := RescueAI.new(player, rng_seed, -1.0, AIPlayer.Difficulty.HARD)
	ai.enabled = enabled if player == subject_side else true
	actors.append(ai)
	return ai

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	var summary := []
	for copy in [false, true]:
		var subject := deck(3 if copy else 2)
		var foe := deck(2 if copy else 0)
		var target: StringName = &"ability_stone_copy" if copy else &"ability_light_revive"
		subject.abilities[0] = CardDB.card(target)
		if copy: foe.abilities[0] = CardDB.card(&"ability_light_revive")
		var row := {"case": "copy" if copy else "revive", "before": {"wins": 0, "draws": 0, "rescue_decisions": 0, "losing_rescue_decisions": 0}, "after": {"wins": 0, "draws": 0, "rescue_decisions": 0, "losing_rescue_decisions": 0}}
		for seed_value in [11603, 11617]:
			for side in [0, 1]:
				var pool_hash := 0
				for variant in [false, true]:
					enabled = variant
					subject_side = side
					actors.clear()
					var match_row := run_match(subject, foe, seed_value, side, target, [])
					if not variant: pool_hash = int(match_row.pool_hash)
					else: verify(int(match_row.pool_hash) == pool_hash, "добор пары одинаков")
					var actor := actors[side]
					match_row["rescue_policy"] = variant
					match_row["case"] = row.case
					match_row["rescue_decisions"] = actor.rescue_decisions
					match_row["losing_rescue_decisions"] = actor.losing_rescue_decisions
					verify(int(match_row.turns) < MatchController.MAX_TURNS, "матч не упёрся в лимит ходов")
					var stats: Dictionary = row.after if variant else row.before
					stats.wins += int(int(match_row.win) == 1)
					stats.draws += int(int(match_row.win) < 0)
					stats.rescue_decisions += actor.rescue_decisions
					stats.losing_rescue_decisions += actor.losing_rescue_decisions
					matches.append(match_row)
		summary.append(row)
	var report := {"method": "16 HARD/HARD матчей: 2 состава (Свет с Возрождением, Камень с Копией против Света с Возрождением), seed11603/11617, обе стороны и до/после только _choose_revival исследуемой стороны. Команды, руки/запас и seed совпадают; get_view, точные приземления.", "failures": failures, "summary": summary, "matches": matches, "limits": "Два seed/состав, не общий winrate. Проверяет достижимость спасения и завершение при полной политике. Улучшения ворот действуют в обеих версиях. Счётчики rescue_decisions — выбор карты с ожидаемым приростом живых до чужого ответа, не число фактических воскрешений. Локальное число живых не предсказывает скрытый ответ или качество следующего боя; физики/графики нет."}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		verify(file != null, "отчёт записывается")
		if file != null:
			file.store_string(JSON.stringify(report, "\t") + "\n")
			file.close()
	print("AI rescue pairs: ", matches.size(), " matches, ", failures, " failures; ", JSON.stringify(summary))
	quit(1 if failures else 0)
