extends "res://tools/card_balance_matches.gd"
## Узкая CARD-16/новые реакции серия: одна красная замена, шесть стихий, обе стороны.
## Runner использует настоящий MatchController и только get_view для решений ИИ.

const COUNTERS: Array[StringName] = [&"ability_fire_counter", &"ability_gale_rebuttal", &"ability_light_counter", &"ability_stone_counter", &"ability_shadow_counter", &"ability_tide_counter"]

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	for el in range(6):
		var baseline := deck(el)
		var candidate := deck(el)
		candidate.abilities[0] = CardDB.card(COUNTERS[el])
		var creature_ids: Array = ids(candidate)[0]
		var arena_ids: Array = ids(candidate)[1]
		var ability_ids: Array = ids(candidate)[2]
		verify(CardDB.deck_error(creature_ids, arena_ids, ability_ids).is_empty(), "реакция занимает законный красный слот %d" % el)
		compare("reactive_counter", GameData.ATTR_KEYS[el], baseline, candidate, deck((el + 3) % 6), baseline.abilities[0].id, COUNTERS[el], [7301 + el])
	for i in range(0, matches.size(), 2):
		verify(matches[i].pool_hash == matches[i + 1].pool_hash, "одинаковый публично неизвестный запас пары")
		verify(matches[i].decks[0][0] == matches[i + 1].decks[0][0] and matches[i].decks[1] == matches[i + 1].decks[1], "команды и соперник пары неизменны")
	var summary: Array = []
	for el in range(6):
		var row := {"element": String(GameData.ATTR_KEYS[el]), "baseline_wins": 0, "counter_wins": 0, "baseline_draws": 0, "counter_draws": 0, "counter_plays": 0, "counter_legal_windows": 0, "counter_local_outcome_changes": 0, "turn_limit_matches": 0}
		for i in range(el * 4, el * 4 + 4):
			var m: Dictionary = matches[i]
			var variant: String = "baseline" if int(m.variant) == 0 else "counter"
			if int(m.win) == 1:
				row[variant + "_wins"] += 1
			elif int(m.win) < 0:
				row[variant + "_draws"] += 1
			if int(m.turns) >= MatchController.MAX_TURNS:
				row.turn_limit_matches += 1
			if int(m.variant) == 1:
				row.counter_plays += int(m.plays)
				row.counter_legal_windows += int(m.legal_windows)
				row.counter_local_outcome_changes += int(m.local_outcome_changes)
		summary.append(row)
	var report := {"method": "24 детерминированных матча HARD/HARD: 6 стихий, одна красная замена, обе стороны, seed7301..7306. Те же команды и соперник; обе альтернативы исключены из добора только исследуемой стороны. Решения ИИ используют get_view, точные приземления без графики.",
		"failures": failures, "summary": summary, "matches": matches,
		"limits": "Один seed на стихию и три пары стихий: это проверка достижимости/регрессий, не оценка общего winrate или полного баланса. Победа не доказывает причинную силу карты; локальный пересчёт не моделирует иной ответ. Физика, внешний интерфейс и слабые сложности не оцениваются."}
	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else "user://card-counters.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	verify(file != null, "отчёт записывается")
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("CARD counters: ", matches.size(), " matches, ", failures, " failures; ", JSON.stringify(summary))
	quit(1 if failures else 0)
