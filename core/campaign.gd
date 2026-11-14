class_name Campaign
extends RefCounted
## Три самостоятельных кубка с постоянными соперниками, без усилений и экономики.
## Турнир v1 и его история хранятся отдельно и не переписываются кампанией.
const Cup = preload("res://core/tournament.gd")
const Simulator = preload("res://core/tournament_npc_simulator.gd")
const VERSION := 1
const SAVE_PATH := "user://campaign/active.json"
const CUP_TITLES := ["Кубок Каньона", "Кубок Гавани", "Кубок Стихий"]
const MAX_SAVE_BYTES := 786432
var state: Dictionary = {}
var cup: Tournament
var autosave_path: String = SAVE_PATH
var last_error: String = ""
static var creation_error: String = ""

static func create(deck: DeckDef, difficulty: int, rng_seed: int, player_name: String = "Игрок", path: String = SAVE_PATH, card_pool: int = CardDB.Pool.BASE) -> Campaign:
	creation_error = ""
	var previous_history: Array = []
	if not path.is_empty() and FileAccess.file_exists(path):
		var previous := history(path)
		if not String(previous.error).is_empty():
			creation_error = String(previous.error)
			return null
		previous_history = previous.entries
	var first := Cup.create(deck, difficulty, rng_seed, player_name, "", card_pool)
	if first == null:
		creation_error = Cup.creation_error
		return null
	var run := Campaign.new()
	run.cup = first
	run.autosave_path = path
	run.state = {"version": VERSION, "id": "campaign-%d-%d" % [rng_seed, Time.get_ticks_usec()], "seed": rng_seed, "difficulty": difficulty, "cups": [first.state], "meetings": [], "history": previous_history}
	if not path.is_empty() and run.save_file(path) != OK:
		creation_error = run.last_error
		return null
	return run

func cup_index() -> int:
	return state.cups.size() - 1

func cup_title() -> String:
	return CUP_TITLES[cup_index()]

func progress_text() -> String:
	return "Кампания · %d/3 · %s" % [cup_index() + 1, cup_title()]

func completed() -> bool:
	return cup_index() == 2 and cup.completed()

func can_advance() -> bool:
	return cup.completed() and cup_index() < 2

func begin_match(id: String) -> Error:
	var previous := state.duplicate(true)
	var code := cup.begin_match(id)
	if code != OK:
		last_error = cup.last_error
		return code
	return _persist_or_restore(previous)

func record_result(id: String, winner: int, alive: Array, reason: String, observation: Dictionary = {}) -> Error:
	if not _observation_valid(observation, true):
		last_error = "Некорректное наблюдение встречи"
		return ERR_INVALID_DATA
	var duel := cup.next_match()
	var previous := state.duplicate(true)
	var code := cup.record_result(id, winner, alive, reason)
	if code != OK:
		last_error = cup.last_error
		return code
	if int(duel.a) == 0 or int(duel.b) == 0:
		var npc := int(duel.b if int(duel.a) == 0 else duel.a)
		state.meetings.append({"cup": cup_index(), "match": id, "npc": npc, "winner": winner, "observation": _normalized_observation(observation)})
	return _persist_or_restore(previous)

func simulate_next_npc() -> Dictionary:
	var duel := cup.next_match()
	if duel.is_empty() or int(duel.a) == 0 or int(duel.b) == 0:
		return {"error": "Этот матч должен сыграть человек"}
	var result: Dictionary = Simulator.simulate(cup.participant_deck(int(duel.a)), cup.participant_deck(int(duel.b)), int(duel.seed), int(duel.first_player), int(state.difficulty), Simulator.STEP_LIMIT, [Cup.personality(int(duel.a)), Cup.personality(int(duel.b))], [], cup.card_pool())
	if not String(result.error).is_empty():
		return result
	var winner := -1 if int(result.winner) == -1 else int(duel.a if int(result.winner) == 0 else duel.b)
	if record_result(String(duel.id), winner, result.alive, String(result.reason)) != OK:
		return {"error": last_error}
	return {"error": "", "match": duel, "result": cup.state.matches[cup._match_index(String(duel.id))].result.duplicate(true)}

func advance_cup() -> Error:
	if not can_advance():
		last_error = "Следующий кубок пока недоступен"
		return ERR_UNAVAILABLE
	var previous := state.duplicate(true)
	var original_cup := cup
	var next := Cup.create(cup.participant_deck(0), int(state.difficulty), _cup_seed(int(state.seed), cup_index() + 1), cup.participant_name(0), "", cup.card_pool())
	if next == null:
		last_error = Cup.creation_error
		return ERR_INVALID_DATA
	cup = next
	state.cups.append(cup.state)
	return _persist_or_restore(previous, original_cup)

static func _cup_seed(seed_value: int, index: int) -> int:
	return (seed_value ^ (index * 0x1f123bb5)) & 0x7fffffff

func _persist_or_restore(previous: Dictionary, original_cup: Tournament = null) -> Error:
	state.cups[cup_index()] = cup.state
	last_error = ""
	if autosave_path.is_empty():
		return OK
	var code := save_file(autosave_path)
	if code != OK:
		var restored := from_dict(previous)
		if original_cup != null:
			cup = original_cup
		cup.state = restored.campaign.cup.state
		state = restored.campaign.state
		state.cups[cup_index()] = cup.state
	return code

## Только принятые публичные действия человека. Колоды/закрытые карты не читаются.
static func observations_from_actions(actions: Array, human_side: int = 0) -> Dictionary:
	var result := _normalized_observation({})
	for action in actions:
		if not action is Array or action.size() != 2 or not action[1] is Array or action[1].is_empty() or action[1][0] != human_side:
			continue
		match String(action[0]):
			"select_creature", "throw_with_gate": result.throws = mini(int(result.throws) + 1, 4096)
			"play_ability": result.abilities = mini(int(result.abilities) + 1, 4096)
			"reveal_gate": result.gate_opens = mini(int(result.gate_opens) + 1, 4096)
	return result

static func _normalized_observation(observation: Dictionary) -> Dictionary:
	return {"throws": int(observation.get("throws", 0)), "abilities": int(observation.get("abilities", 0)), "gate_opens": int(observation.get("gate_opens", 0))}

static func _observation_valid(value: Variant, allow_empty: bool = false) -> bool:
	if not value is Dictionary:
		return false
	if allow_empty and value.is_empty():
		return true
	if value.size() != 3:
		return false
	for key in ["throws", "abilities", "gate_opens"]:
		if not Cup._integer(value.get(key), 0, 4096):
			return false
	return true

func _past_meetings(npc: int) -> Array:
	var found: Array = []
	var pending := cup.next_match()
	for meeting in state.meetings:
		# Сохранённый итог уже завершённого матча не входит в повтор этой встречи.
		if int(meeting.npc) == npc and (int(meeting.cup) < cup_index() or String(meeting.match) != String(pending.get("id", ""))):
			found.append(meeting)
	return found.slice(maxi(0, found.size() - 3))

func ai_preferences(npc: int) -> Dictionary:
	var base := Cup.personality(npc)
	if base.is_empty():
		return base
	var meetings := _past_meetings(npc)
	if meetings.is_empty():
		return base
	var attack := 0.0
	var safe := 0.0
	var traps := 0.0
	for meeting in meetings:
		if int(meeting.winner) == 0:
			attack -= 12.0
			safe += 10.0
		elif int(meeting.winner) == npc:
			attack += 8.0
		if int(meeting.observation.abilities) >= 2:
			safe += 10.0
		if int(meeting.observation.gate_opens) >= 2:
			traps += 8.0
	base.attack_bias = clampf(float(base.attack_bias) + attack / meetings.size(), -60.0, 60.0)
	base.safe_margin = clampf(float(base.safe_margin) + safe / meetings.size(), -25.0, 25.0)
	base.trap_bias = clampf(float(base.trap_bias) + traps / meetings.size(), -60.0, 60.0)
	return base

func opponent_brief(npc: int) -> String:
	if npc < 1 or npc > 7:
		return ""
	var descriptions := ["Чаще выбирает атаку и охотнее тратит карты.", "Предпочитает манёвр и быстрый ответ.", "Бережёт карты и запас перевеса.", "Избегает риска, готовит надёжную защиту.", "Охотнее готовит ловушки.", "Предпочитает контроль и осторожный обмен.", "Готовит ловушку и бережёт ответную карту."]
	var brief: String = descriptions[npc - 1]
	var meetings := _past_meetings(npc)
	if meetings.is_empty():
		return brief + " Личных встреч ещё не было."
	var wins := 0
	var losses := 0
	var abilities := 0
	var opens := 0
	for meeting in meetings:
		wins += 1 if int(meeting.winner) == npc else 0
		losses += 1 if int(meeting.winner) == 0 else 0
		abilities += int(meeting.observation.abilities)
		opens += int(meeting.observation.gate_opens)
	var before := Cup.personality(npc)
	var after := ai_preferences(npc)
	return brief + " Память последних %d встреч: победы %d, поражения %d, ничьи %d; ваши способности %d, открытия ворот %d. Поправки к выбору: атака %+.0f, запас перевеса %+.0f, ловушки %+.0f. Сила, колода, точность и сложность прежние." % [meetings.size(), wins, losses, meetings.size() - wins - losses, abilities, opens, after.attack_bias - before.attack_bias, after.safe_margin - before.safe_margin, after.trap_bias - before.trap_bias]

static func from_dict(data: Dictionary) -> Dictionary:
	if data.size() != 7 or not Cup._integer(data.get("version"), VERSION, VERSION) or not data.get("id") is String or String(data.id).is_empty() or String(data.id).length() > 80 or not Cup._integer(data.get("seed"), 0, 2147483647) or not Cup._integer(data.get("difficulty"), 0, 2):
		return {"error": "Неподдерживаемые параметры кампании"}
	if not data.get("cups") is Array or data.cups.size() < 1 or data.cups.size() > 3 or not data.get("meetings") is Array or not data.get("history") is Array:
		return {"error": "Некорректный прогресс кампании"}
	var seen_history: Array = []
	for entry in data.history:
		if not Cup._history_entry_valid(entry) or seen_history.has(entry.id):
			return {"error": "Некорректная история кампаний"}
		seen_history.append(entry.id)
	var run := Campaign.new()
	run.autosave_path = ""
	run.state = data.duplicate(true)
	var expected_meetings: Array = []
	var player: Dictionary = {}
	for index in range(data.cups.size()):
		if not data.cups[index] is Dictionary:
			return {"error": "Некорректный кубок кампании"}
		var restored := Cup.from_dict(data.cups[index])
		if not String(restored.error).is_empty():
			return restored
		var item: Tournament = restored.tournament
		if seen_history.has(item.state.id):
			return {"error": "Кубок кампании уже записан в прежней истории"}
		if index == 0:
			player = item.state.participants[0]
		if int(item.state.seed) != _cup_seed(int(data.seed), index) or int(item.state.difficulty) != int(data.difficulty) or not Cup._equivalent(player, item.state.participants[0]) or (index < data.cups.size() - 1 and not item.completed()):
			return {"error": "Нарушен порядок или состав кубков кампании"}
		run.state.cups[index] = item.state
		for duel in item.state.matches:
			if duel.has("result") and (int(duel.a) == 0 or int(duel.b) == 0):
				expected_meetings.append({"cup": index, "match": duel.id, "npc": int(duel.b if int(duel.a) == 0 else duel.a), "winner": int(duel.result.winner)})
		run.cup = item
	if expected_meetings.size() != data.meetings.size():
		return {"error": "История личных встреч неполна"}
	for index in range(expected_meetings.size()):
		var saved: Variant = data.meetings[index]
		if not saved is Dictionary or saved.size() != 5 or not _observation_valid(saved.get("observation")):
			return {"error": "Некорректное наблюдение личной встречи"}
		for key in expected_meetings[index]:
			if not Cup._equivalent(expected_meetings[index][key], saved.get(key)):
				return {"error": "Личная встреча не соответствует результату кубка"}
	return {"error": "", "campaign": run}

static func load_file(path: String = SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "Сохранение кампании отсутствует", "missing": true}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_SAVE_BYTES:
		return {"error": "Не удалось прочитать сохранение кампании"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"error": "Повреждён JSON кампании"}
	var restored := from_dict(parser.data)
	if String(restored.error).is_empty():
		restored.campaign.autosave_path = path
	return restored

static func archive_invalid(path: String = SAVE_PATH) -> Error:
	return Cup.archive_invalid(path)

static func history(path: String = SAVE_PATH) -> Dictionary:
	var loaded := load_file(path)
	if not String(loaded.error).is_empty():
		return {"error": "" if loaded.get("missing", false) else loaded.error, "entries": []}
	var entries: Array = loaded.campaign.state.history.duplicate(true)
	for saved in loaded.campaign.state.cups:
		var restored := Cup.from_dict(saved)
		if restored.tournament.completed():
			entries.append(restored.tournament._history_entry())
	return {"error": "", "entries": entries}

func save_file(path: String = SAVE_PATH) -> Error:
	state.cups[cup_index()] = cup.state
	var validated := from_dict(state)
	if not String(validated.error).is_empty():
		last_error = String(validated.error)
		return ERR_INVALID_DATA
	if FileAccess.file_exists(path):
		var previous := load_file(path)
		if not String(previous.error).is_empty():
			last_error = String(previous.error)
			return ERR_FILE_CORRUPT
	var body := JSON.stringify(state, "  ")
	if body.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		last_error = "Сохранение кампании слишком велико"
		return ERR_OUT_OF_MEMORY
	var absolute := ProjectSettings.globalize_path(path)
	var code := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if code != OK:
		last_error = "Не удалось создать папку кампании"
		return code
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Не удалось записать кампанию"
		return FileAccess.get_open_error()
	file.store_string(body)
	file.flush()
	code = file.get_error()
	file.close()
	if code == OK:
		code = DirAccess.rename_absolute(temporary, absolute)
	if code != OK:
		DirAccess.remove_absolute(temporary)
		last_error = "Не удалось атомарно сохранить кампанию"
	return code
