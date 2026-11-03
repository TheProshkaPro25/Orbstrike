class_name Tournament
extends RefCounted
## Турнир не зависит от сцен. Полная проверка сохранения воспроизводит журнал
## результатов и сравнивает всю производную сетку с каноническим состоянием.
const NpcSimulator = preload("res://core/tournament_npc_simulator.gd")
const VERSION := 1
const RULES_VERSION := 1
const SAVE_PATH := "user://tournament/active.json"
const HISTORY_PATH := SAVE_PATH
const MAX_SAVE_BYTES := 262144
const NPCS := [
	["Akari Hoshino", "Напор Пламени", "fire", ["dragnar", "klykar", "grifalon"], "arena_mirror", "ability_fire_drain", "ability_fire_assault", "ability_dragnar_rush"],
	["Ren Kazehara", "Манёвры Бури", "gale", ["grifalon", "rogozhuk", "gorgul"], "arena_hold", "ability_gale_leap", "ability_gale_gust", "ability_grifalon_sky"],
	["Hikari Aizawa", "Страж Света", "light", ["ratnik", "levian", "gorgul"], "arena_fallen_call", "ability_light_revive", "ability_light_guard", "ability_ratnik_oath"],
	["Daichi Iwata", "Защита Камня", "stone", ["kolossar", "rogozhuk", "gorgul"], "arena_limit", "ability_stone_copy", "ability_stone_firm", "ability_kolossar_wall"],
	["Yui Kurose", "Ловушки Тени", "shadow", ["klykar", "ratnik", "gorgul"], "arena_dusk_throne", "ability_shadow_doom", "ability_shadow_strike", "ability_klykar_bite"],
	["Kaito Minase", "Контроль Прилива", "tide", ["levian", "rogozhuk", "grifalon"], "arena_mute", "ability_tide_hush", "ability_tide_surf", "ability_levian_abyss"],
	["Takumi Hayashi", "Ответный удар", "fire", ["rogozhuk", "ratnik", "gorgul"], "arena_clash", "ability_fire_ash", "ability_fire_spark", "ability_rogozhuk_ram"],
]
# Только точные прежние подписи по тому же ID: версия и игровые данные не меняются.
const LEGACY_NPC_NAMES := ["Алина «Искра»", "Марк «Вихрь»", "София «Заря»", "Борис «Утёс»", "Ника «Сумрак»", "Лев «Прибой»", "Роман «Кузнец»"]

var state: Dictionary = {}
var autosave_path: String = SAVE_PATH
var last_error: String = ""
static var creation_error: String = ""

static func create(deck0: DeckDef, difficulty: int, rng_seed: int, player_name: String = "Игрок", path: String = SAVE_PATH) -> Tournament:
	creation_error = ""
	if deck0 == null or difficulty < 0 or difficulty > 2 or rng_seed < 0 or rng_seed > 2147483647 or player_name.strip_edges().is_empty() or player_name.length() > 80:
		creation_error = "Некорректные параметры нового турнира"
		return null
	var ids := deck_ids(deck0)
	if not _deck_valid(ids):
		creation_error = "Команда не соответствует правилам турнира"
		return null
	var cup := Tournament.new()
	cup.autosave_path = path
	cup._build(ids, difficulty, rng_seed, player_name.strip_edges(), "cup-%d-%d" % [rng_seed, Time.get_ticks_usec()])
	for participant in cup.state.participants:
		if not _deck_valid(participant.deck):
			creation_error = "Недопустимая колода NPC: " + String(participant.name)
			return null
	if not path.is_empty() and cup.save_file(path) != OK:
		creation_error = cup.last_error
		return null
	return cup

## Только после явного выбора «Новый турнир»: старый файл сохраняется для разбора.
static func archive_invalid(path: String = SAVE_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	var absolute := ProjectSettings.globalize_path(path)
	return DirAccess.rename_absolute(absolute, absolute + ".corrupt-%d" % Time.get_ticks_usec())

static func deck_ids(deck: DeckDef) -> Array:
	var out: Array = [[], [], []]
	for pair in [[deck.creatures, 0], [deck.arena, 1], [deck.abilities, 2]]:
		for definition in pair[0]:
			if definition == null:
				return []
			out[pair[1]].append(String(definition.id))
	return out

static func _deck_valid(ids: Variant) -> bool:
	if not ids is Array or ids.size() != 3:
		return false
	for list in ids:
		if not list is Array or list.size() != 3:
			return false
		for id in list:
			if not id is String:
				return false
	return CardDB.deck_error(ids[0], ids[1], ids[2]).is_empty()

func _build(ids: Array, difficulty: int, rng_seed: int, player_name: String, cup_id: String) -> void:
	state = {"version": VERSION, "rules_version": RULES_VERSION, "ruleset": MatchRules.Ruleset.ANIME_INSPIRED, "id": cup_id, "seed": rng_seed, "difficulty": difficulty, "participants": [{"id": 0, "name": player_name, "style": "Моя команда", "deck": ids.duplicate(true)}], "groups": {}, "lot": [], "matches": [], "in_progress": "", "completed": false, "champion": -1}
	for i in range(NPCS.size()):
		var row: Array = NPCS[i]
		var creatures: Array = []
		for species in row[3]:
			creatures.append("creature_%s_%s" % [species, row[2]])
		state.participants.append({"id": i + 1, "name": row[0], "style": row[1], "deck": [creatures, ["arena_field_" + row[2], "arena_den_" + row[3][0], row[4]], [row[5], row[6], row[7]]]})
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var entrants: Array = range(8)
	_shuffle(entrants, rng)
	state.groups = {"A": entrants.slice(0, 4), "B": entrants.slice(4, 8)}
	var lot: Array = range(8)
	_shuffle(lot, rng)
	state.lot = lot
	var pairings := [[[0, 3], [1, 2]], [[0, 2], [3, 1]], [[0, 1], [2, 3]]]
	# Каждый начинает один или два матча; seed меняет стороны всей группы.
	var starts := [[0, 0], [1, 0], [0, 0]]
	for round_index in range(3):
		for group in ["A", "B"]:
			for index in range(2):
				var pair: Array = pairings[round_index][index]
				var flip: int = (rng_seed >> (0 if group == "A" else 1)) & 1
				state.matches.append(_new_match("%s-R%d-M%d" % [group, round_index + 1, index + 1], int(state.groups[group][pair[0]]), int(state.groups[group][pair[1]]), "group_" + group, round_index + 1, 0, int(starts[round_index][index]) ^ flip))

static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var item: Variant = values[i]
		values[i] = values[j]
		values[j] = item

func _new_match(id: String, a: int, b: int, stage: String, round_number: int, attempt: int = 0, first: int = -1) -> Dictionary:
	var match_seed: int = (int(id.hash()) ^ int(state.seed)) & 0x7fffffff
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed
	return {"id": id, "a": a, "b": b, "seed": match_seed, "first_player": rng.randi_range(0, 1) if first < 0 else first, "stage": stage, "round": round_number, "attempt": attempt}

func participant_name(id: int) -> String:
	return String(state.participants[id].name) if id >= 0 and id < 8 else "—"

## Постоянный характер соперника. Все значения ограничены в AIPlayer.
static func personality(id: int) -> Dictionary:
	var rows := [[50.0, -10.0, -15.0, -0.025], [25.0, 10.0, -5.0, -0.01], [-25.0, 5.0, 20.0, 0.015], [-45.0, 15.0, 25.0, 0.025], [-15.0, 55.0, 5.0, 0.0], [-20.0, 25.0, 15.0, 0.01], [15.0, 35.0, 10.0, 0.02]]
	if id < 1 or id > rows.size():
		return {}
	var row: Array = rows[id - 1]
	return {"attack_bias": row[0], "trap_bias": row[1], "safe_margin": row[2], "card_cost_bias": row[3]}

func participant_style(id: int) -> String:
	return String(state.participants[id].style) if id >= 0 and id < 8 else ""

func participant_deck(id: int) -> DeckDef:
	if id < 0 or id >= 8:
		return null
	var ids: Array = state.participants[id].deck
	return CardDB.build_deck(ids[0], ids[1], ids[2])

func next_match() -> Dictionary:
	for duel in state.matches:
		if not duel.has("result"):
			return duel.duplicate(true)
	return {}

func completed() -> bool:
	return bool(state.completed)

func champion() -> int:
	return int(state.champion)

func player_eliminated() -> bool:
	if state.matches.size() <= 12:
		return false
	for duel in state.matches:
		if duel.stage == "semifinal" and (duel.a == 0 or duel.b == 0):
			if not duel.has("result") or int(duel.result.advancing) == 0:
				return false if not completed() else champion() != 0
			if int(duel.result.advancing) < 0:
				continue
			return true
	return true

func standings(group: String) -> Array:
	if not state.groups.has(group):
		return []
	var rows := _table(state.groups[group], false)
	var ids: Array = state.groups[group].duplicate()
	ids.sort_custom(func(a, b): return int(rows[a].points) > int(rows[b].points))
	var ranked: Array = []
	var tied: Array = []
	for id in ids:
		if not tied.is_empty() and rows[id].points != rows[tied[0]].points:
			ranked.append_array(_resolve_tie(tied, rows))
			tied = []
		tied.append(id)
	ranked.append_array(_resolve_tie(tied, rows))
	var output: Array = []
	for id in ranked:
		var row: Dictionary = rows[id]
		row.rank = output.size() + 1
		output.append(row)
	return output

func _table(ids: Array, mini: bool) -> Dictionary:
	var rows: Dictionary = {}
	for id in ids:
		rows[id] = {"id": id, "name": participant_name(int(id)), "played": 0, "points": 0, "wins": 0, "draws": 0, "losses": 0, "alive_for": 0, "alive_against": 0, "diff": 0}
	for duel in state.matches:
		if not String(duel.stage).begins_with("group_") or not duel.has("result"):
			continue
		if mini and (not ids.has(duel.a) or not ids.has(duel.b)):
			continue
		for side in range(2):
			var id: int = int(duel.a if side == 0 else duel.b)
			if not rows.has(id):
				continue
			var row: Dictionary = rows[id]
			row.played += 1
			row.alive_for += int(duel.result.alive[side])
			row.alive_against += int(duel.result.alive[1 - side])
			row.diff = row.alive_for - row.alive_against
			if int(duel.result.winner) == -1:
				row.points += 1
				row.draws += 1
			elif int(duel.result.winner) == id:
				row.points += 3
				row.wins += 1
			else:
				row.losses += 1
	return rows

func _resolve_tie(ids: Array, overall: Dictionary) -> Array:
	if ids.size() <= 1:
		return ids.duplicate()
	var mini := _table(ids, true)
	var sorted := ids.duplicate()
	sorted.sort_custom(func(a, b): return int(mini[a].points) > int(mini[b].points) if mini[a].points != mini[b].points else int(mini[a].diff) > int(mini[b].diff))
	var buckets: Array = []
	for id in sorted:
		if buckets.is_empty() or mini[id].points != mini[buckets[-1][0]].points or mini[id].diff != mini[buckets[-1][0]].diff:
			buckets.append([])
		buckets[-1].append(id)
	if buckets.size() > 1:
		var result: Array = []
		for bucket in buckets:
			result.append_array(_resolve_tie(bucket, overall))
		return result
	sorted.sort_custom(func(a, b):
		if overall[a].diff != overall[b].diff:
			return int(overall[a].diff) > int(overall[b].diff)
		if overall[a].wins != overall[b].wins:
			return int(overall[a].wins) > int(overall[b].wins)
		return state.lot.find(a) < state.lot.find(b))
	return sorted

func begin_match(id: String) -> Error:
	var duel := next_match()
	if duel.is_empty() or duel.id != id:
		last_error = "Матч сейчас недоступен"
		return ERR_INVALID_PARAMETER
	if state.in_progress == id:
		return OK
	var previous := state.duplicate(true)
	state.in_progress = id
	return _persist_or_restore(previous)

func record_result(id: String, winner: int, alive: Array, reason: String) -> Error:
	last_error = ""
	var duel := next_match()
	if duel.is_empty() or duel.id != id:
		last_error = "Результат уже записан или матч сейчас недоступен"
		return ERR_INVALID_PARAMETER
	if (winner != -1 and winner != int(duel.a) and winner != int(duel.b)) or not _alive_valid(alive) or reason.is_empty() or reason.length() > 120:
		last_error = "Некорректный результат матча"
		return ERR_INVALID_DATA
	var winning_side := 0 if winner == int(duel.a) else 1
	if (winner == -1 and int(alive[0]) != int(alive[1])) or (winner >= 0 and (int(alive[winning_side]) == 0 or int(alive[winning_side]) < int(alive[1 - winning_side]))):
		last_error = "Победитель не соответствует числу оставшихся существ"
		return ERR_INVALID_DATA
	var previous := state.duplicate(true)
	var advancing := winner
	if not String(duel.stage).begins_with("group_") and winner == -1 and int(duel.attempt) == 1:
		advancing = _ko_advancer(int(duel.a), int(duel.b))
	var index := _match_index(id)
	state.matches[index]["result"] = {"winner": winner, "alive": [int(alive[0]), int(alive[1])], "reason": reason, "advancing": advancing}
	state.in_progress = ""
	if not String(duel.stage).begins_with("group_") and winner == -1 and int(duel.attempt) == 0:
		state.matches.insert(index + 1, _new_match(id + "-replay", int(duel.a), int(duel.b), String(duel.stage), int(duel.round), 1, 1 - int(duel.first_player)))
	_advance()
	return _persist_or_restore(previous)

func _persist_or_restore(previous: Dictionary) -> Error:
	if autosave_path.is_empty():
		return OK
	var code := save_file(autosave_path)
	if code != OK:
		state = previous
	return code

func _match_index(id: String) -> int:
	for index in range(state.matches.size()):
		if state.matches[index].id == id:
			return index
	return -1

func _group_row(id: int) -> Dictionary:
	for group in ["A", "B"]:
		for row in standings(group):
			if int(row.id) == id:
				return row
	return {}

func _ko_advancer(a: int, b: int) -> int:
	var left := _group_row(a)
	var right := _group_row(b)
	for key in ["rank", "points", "diff", "wins"]:
		if left[key] != right[key]:
			if key == "rank":
				return a if int(left[key]) < int(right[key]) else b
			return a if int(left[key]) > int(right[key]) else b
	return a if state.lot.find(a) < state.lot.find(b) else b

func _stage_advancers(stage: String) -> Array:
	var output: Array = []
	for duel in state.matches:
		if duel.stage == stage and duel.has("result") and int(duel.result.advancing) >= 0:
			output.append(int(duel.result.advancing))
	return output

func _advance() -> void:
	if not next_match().is_empty():
		return
	var semis: Array = _stage_advancers("semifinal")
	var finals: Array = _stage_advancers("final")
	if not finals.is_empty():
		state.completed = true
		state.champion = int(finals[0])
	elif semis.size() == 2:
		state.matches.append(_new_match("FINAL", int(semis[0]), int(semis[1]), "final", 5))
	elif state.matches.size() == 12:
		var a := standings("A")
		var b := standings("B")
		state.matches.append(_new_match("SF1", int(a[0].id), int(b[1].id), "semifinal", 4))
		state.matches.append(_new_match("SF2", int(b[0].id), int(a[1].id), "semifinal", 4))

func simulate_next_npc() -> Dictionary:
	var duel := next_match()
	if duel.is_empty() or duel.a == 0 or duel.b == 0:
		return {"error": "Этот матч должен сыграть человек"}
	var result: Dictionary = NpcSimulator.simulate(participant_deck(int(duel.a)), participant_deck(int(duel.b)), int(duel.seed), int(duel.first_player), int(state.difficulty), NpcSimulator.STEP_LIMIT, [personality(int(duel.a)), personality(int(duel.b))])
	if not String(result.error).is_empty():
		return result
	var global_winner: int = -1 if int(result.winner) == -1 else int(duel.a if int(result.winner) == 0 else duel.b)
	var code := record_result(String(duel.id), global_winner, result.alive, String(result.reason))
	if code != OK:
		return {"error": last_error}
	return {"error": "", "match": duel, "result": state.matches[_match_index(String(duel.id))].result.duplicate(true)}

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _alive_valid(alive: Variant) -> bool:
	return alive is Array and alive.size() == 2 and _integer(alive[0], 0, 3) and _integer(alive[1], 0, 3)

## JSON возвращает целые числа как float; типы всех остальных значений строги.
static func _equivalent(expected: Variant, actual: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary or expected.size() != actual.size():
			return false
		for key in expected:
			if not actual.has(key) or not _equivalent(expected[key], actual[key]):
				return false
		return true
	if expected is Array:
		if not actual is Array or expected.size() != actual.size():
			return false
		for index in range(expected.size()):
			if not _equivalent(expected[index], actual[index]):
				return false
		return true
	if typeof(expected) == TYPE_INT:
		return _integer(actual, int(expected), int(expected))
	return typeof(expected) == typeof(actual) and expected == actual

static func from_dict(data: Dictionary) -> Dictionary:
	if not _integer(data.get("version"), VERSION, VERSION):
		return {"error": "Неподдерживаемая версия турнира"}
	if not _integer(data.get("seed"), 0, 2147483647) or not _integer(data.get("difficulty"), 0, 2) or not data.get("id") is String or String(data.id).is_empty() or String(data.id).length() > 80:
		return {"error": "Некорректные параметры турнира"}
	if not data.get("participants") is Array or data.participants.size() != 8 or not data.participants[0] is Dictionary:
		return {"error": "Некорректные участники турнира"}
	var human: Dictionary = data.participants[0]
	if not human.get("name") is String or String(human.name).strip_edges().is_empty() or String(human.name).length() > 80 or not _deck_valid(human.get("deck")):
		return {"error": "Некорректная команда игрока"}
	if not data.get("matches") is Array or data.matches.size() < 12 or data.matches.size() > 18 or not data.get("in_progress") is String:
		return {"error": "Некорректная сетка турнира"}
	# Совместимость декоративных имён не ослабляет сравнение колод/сетки/результатов.
	data = data.duplicate(true)
	for id in range(1, 8):
		if data.participants[id] is Dictionary and data.participants[id].get("name") is String:
			data.participants[id].name = _current_npc_name(id, data.participants[id].name)
	var cup := Tournament.new()
	cup.autosave_path = ""
	cup._build(human.deck, int(data.difficulty), int(data.seed), String(human.name), String(data.id))
	for duel in data.matches:
		if not duel is Dictionary:
			return {"error": "Некорректная запись матча"}
		if not duel.has("result"):
			continue
		var result: Variant = duel.result
		if not result is Dictionary or not _integer(result.get("winner"), -1, 7) or not _alive_valid(result.get("alive")) or not result.get("reason") is String or not duel.get("id") is String:
			return {"error": "Некорректный результат матча"}
		if cup.record_result(String(duel.id), int(result.winner), result.alive, String(result.reason)) != OK:
			return {"error": "Нарушен порядок результатов турнира"}
	if not String(data.in_progress).is_empty() and cup.begin_match(String(data.in_progress)) != OK:
		return {"error": "Некорректный незавершённый матч"}
	if not _equivalent(cup.state, data):
		return {"error": "Сохранение турнира не соответствует расписанию и результатам"}
	return {"error": "", "tournament": cup}

static func _current_npc_name(id: int, saved_name: String) -> String:
	if id > 0 and id <= NPCS.size() and saved_name == LEGACY_NPC_NAMES[id - 1]:
		return NPCS[id - 1][0]
	return saved_name

static func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "Сохранение турнира отсутствует", "missing": true}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Не удалось прочитать сохранение турнира"}
	if file.get_length() > MAX_SAVE_BYTES:
		return {"error": "Сохранение турнира слишком велико"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"error": "Повреждён JSON турнира"}
	var data: Dictionary = parser.data
	if data.size() != 4 or data.get("format") != "sfery_tournament" or not _integer(data.get("version"), VERSION, VERSION) or not data.get("active") is Dictionary or not data.get("history") is Array:
		return {"error": "Неподдерживаемый формат сохранения турнира"}
	var restored := from_dict(data.active)
	if not String(restored.error).is_empty():
		return restored
	var ids: Array = []
	var active_history_found := false
	for entry in data.history:
		if not _history_entry_valid(entry) or ids.has(entry.id):
			return {"error": "Повреждена история турниров"}
		entry.champion_name = _current_npc_name(int(entry.champion), entry.champion_name)
		ids.append(entry.id)
		if entry.id == restored.tournament.state.id:
			if not restored.tournament.completed() or not _equivalent(restored.tournament._history_entry(), entry):
				return {"error": "История не соответствует активному турниру"}
			active_history_found = true
	if restored.tournament.completed() and not active_history_found:
		return {"error": "В истории отсутствует итог завершённого турнира"}
	return {"error": "", "envelope": data, "tournament": restored.tournament}

static func load_file(path: String = SAVE_PATH) -> Dictionary:
	var data := _read_envelope(path)
	if not String(data.error).is_empty():
		return data
	var cup: Tournament = data.tournament
	cup.autosave_path = path
	return {"error": "", "tournament": cup}

static func history(path: String = HISTORY_PATH) -> Dictionary:
	var data := _read_envelope(path)
	if not String(data.error).is_empty():
		return {"error": "" if data.get("missing", false) else data.error, "entries": []}
	return {"error": "", "entries": data.envelope.history.duplicate(true)}

func _history_entry() -> Dictionary:
	var rank := 5
	for duel in state.matches:
		if duel.a != 0 and duel.b != 0:
			continue
		if duel.stage == "semifinal":
			rank = 3
		elif duel.stage == "final":
			rank = 1 if champion() == 0 else 2
	return {"id": state.id, "name": participant_name(0), "champion": champion(), "champion_name": participant_name(champion()), "player_rank": rank, "seed": state.seed, "difficulty": state.difficulty}

static func _history_entry_valid(entry: Variant) -> bool:
	if not entry is Dictionary or entry.size() != 7:
		return false
	for key in ["id", "name", "champion_name"]:
		if not entry.get(key) is String or String(entry[key]).is_empty() or String(entry[key]).length() > 80:
			return false
	return _integer(entry.get("champion"), 0, 7) and _integer(entry.get("player_rank"), 1, 5) and [1, 2, 3, 5].has(int(entry.player_rank)) and _integer(entry.get("seed"), 0, 2147483647) and _integer(entry.get("difficulty"), 0, 2)

func save_file(path: String = SAVE_PATH) -> Error:
	last_error = ""
	var validated := from_dict(state)
	if not String(validated.error).is_empty():
		last_error = String(validated.error)
		return ERR_INVALID_DATA
	var entries: Array = []
	if FileAccess.file_exists(path):
		var previous := _read_envelope(path)
		if not String(previous.error).is_empty():
			last_error = String(previous.error)
			return ERR_FILE_CORRUPT
		entries = previous.envelope.history.duplicate(true)
	if completed():
		var entry := _history_entry()
		var found := false
		for existing in entries:
			if existing.id == entry.id:
				if not _equivalent(entry, existing):
					last_error = "История уже содержит другой итог этого турнира"
					return ERR_INVALID_DATA
				found = true
		if not found:
			entries.append(entry)
	var envelope := {"format": "sfery_tournament", "version": VERSION, "active": state, "history": entries}
	var body := JSON.stringify(envelope, "  ")
	if body.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		last_error = "История турниров превысила допустимый размер"
		return ERR_OUT_OF_MEMORY
	var absolute := ProjectSettings.globalize_path(path)
	var code := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if code != OK:
		last_error = "Не удалось создать папку турнира: %d" % code
		return code
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Не удалось открыть временное сохранение турнира"
		return FileAccess.get_open_error()
	file.store_string(body)
	file.flush()
	code = file.get_error()
	file.close()
	if code == OK:
		code = DirAccess.rename_absolute(temporary, absolute)
	if code != OK:
		last_error = "Не удалось атомарно сохранить турнир: %d" % code
		DirAccess.remove_absolute(temporary)
	return code
