class_name Career
extends RefCounted
## Изолированная клиентская экономика. Обычные режимы и CardDB не изменяются.
const Cup = preload("res://core/tournament.gd")
const Simulator = preload("res://core/tournament_npc_simulator.gd")
const VERSION := 1
const SAVE_PATH := "user://career/active.json"
const MAX_SAVE_BYTES := 4194304
const MAX_EVENTS := 8192
const MAX_CUPS := 256
const ELEMENTS := ["fire", "gale", "light", "stone", "shadow", "tide"]
const BASE_POWER := {"rogozhuk": 190, "gorgul": 200, "klykar": 230, "grifalon": 240, "levian": 260, "ratnik": 280, "dragnar": 300, "kolossar": 310}
const LEAGUES := [
	{"title": "Кубок Каньона", "max_level": 3, "max_power": 250, "max_total": 650},
	{"title": "Кубок Гавани", "max_level": 6, "max_power": 350, "max_total": 900},
	{"title": "Кубок Стихий", "max_level": 10, "max_power": 420, "max_total": 1100},
]
var state: Dictionary = {}
var cup: Tournament
var autosave_path := SAVE_PATH
var last_error := ""
var last_reward: Dictionary = {}
static var creation_error := ""

static func create(element: String, difficulty: int, rng_seed: int, player_name: String = "Игрок", path: String = SAVE_PATH) -> Career:
	creation_error = ""
	CardDB.load_all()
	if not ELEMENTS.has(element) or difficulty < 0 or difficulty > 2 or rng_seed < 0 or rng_seed > 2147483647 or player_name.strip_edges().is_empty() or player_name.length() > 80:
		creation_error = "Некорректные параметры карьеры"
		return null
	# Новое начало не подменяет имеющуюся карьеру, в том числе повреждённую.
	if not path.is_empty() and FileAccess.file_exists(path):
		creation_error = "Карьера уже существует: продолжите сохранение"
		return null
	var run := Career.new()
	run.autosave_path = path
	var deck := _default_deck(element, ["gorgul", "rogozhuk", "klykar"])
	var owned: Dictionary = {}
	for id in deck[0]:
		owned[id] = 0
	run.state = {"format": "orbstrike_career", "version": VERSION, "id": "career-%d-%d" % [rng_seed, Time.get_ticks_usec()], "element": element, "name": player_name.strip_edges(), "seed": rng_seed, "difficulty": difficulty, "credits": 100, "owned_creatures": owned, "owned_cards": deck[1] + deck[2], "league": 0, "active": {}, "cups": [], "ledger": []}
	if not path.is_empty() and run.save_file(path) != OK:
		creation_error = run.last_error
		return null
	return run

static func _default_deck(element: String, species: Array, preferred: Array = []) -> Array:
	var creatures: Array = []
	for sp in species:
		creatures.append("creature_%s_%s" % [sp, element])
	var cards: Array = [[], []]
	for category in range(2):
		var classes: Array = CardDB.GATE_CLASSES if category == 0 else CardDB.ABILITY_CLASSES
		for cls in classes:
			var options := CardDB.cards_of(CardDef.Kind.ARENA if category == 0 else CardDef.Kind.ABILITY, cls, ELEMENTS.find(element), species)
			var chosen := String(options[0])
			for id in preferred:
				if options.has(StringName(id)):
					chosen = String(id)
					break
			cards[category].append(chosen)
	return [creatures, cards[0], cards[1]]

func starter_deck() -> DeckDef:
	var ids := _default_deck(String(state.element), ["gorgul", "rogozhuk", "klykar"])
	return CardDB.build_deck(ids[0], ids[1], ids[2])

static func xp_for_level(value: int) -> int:
	var n := clampi(value, 1, 10) - 1
	return 100 * n + 20 * n * (n - 1)

static func level_from_xp(xp: int) -> int:
	var result := 1
	while result < 10 and xp >= xp_for_level(result + 1):
		result += 1
	return result

func level(id: String) -> int:
	return level_from_xp(int(state.owned_creatures.get(id, 0)))

func max_level() -> int:
	return 10

func power(id: String, requested_level: int = -1) -> int:
	var definition := CardDB.creature(StringName(id))
	if definition == null or not BASE_POWER.has(String(definition.species)):
		return 0
	return int(BASE_POWER[String(definition.species)]) + 10 * (clampi(level(id) if requested_level < 0 else requested_level, 1, 10) - 1)

func league_rules(index: int = -1) -> Dictionary:
	return LEAGUES[clampi(int(state.league) if index < 0 else index, 0, 2)].duplicate(true)

func available_species() -> Array:
	var result: Array = [&"rogozhuk", &"gorgul", &"klykar", &"grifalon"]
	var cleared := _cleared_leagues()
	if cleared.has(0):
		result.append_array([&"levian", &"ratnik"])
	if cleared.has(1):
		result.append_array([&"dragnar", &"kolossar"])
	return result

func _cleared_leagues() -> Array:
	var result: Array = []
	for entry in _all_cups():
		if bool(entry.tournament.completed) and not result.has(int(entry.league)):
			result.append(int(entry.league))
	return result

func price(id: String) -> int:
	var creature := CardDB.creature(StringName(id))
	if creature != null:
		if not BASE_POWER.has(String(creature.species)) or creature.attribute != ELEMENTS.find(state.element):
			return 0
		if [&"levian", &"ratnik"].has(creature.species):
			return 650
		if [&"dragnar", &"kolossar"].has(creature.species):
			return 900
		return 400
	var card := CardDB.card(StringName(id))
	if card == null or not CardDB.card_fits(card, ELEMENTS.find(state.element)):
		return 0
	return 100 if CardDB.card_class(card) in [&"gold", &"blue"] else (200 if CardDB.card_class(card) in [&"silver", &"green"] else 300)

func purchase(id: String) -> Error:
	last_error = ""
	if cup != null and not cup.completed():
		return _fail("Магазин доступен между кубками")
	var cost := price(id)
	if cost <= 0:
		return _fail("Предмет не подходит вашей стихии")
	if state.owned_creatures.has(id) or state.owned_cards.has(id):
		return _fail("Этот предмет уже есть в коллекции")
	var creature := CardDB.creature(StringName(id))
	if creature != null and not available_species().has(creature.species):
		return _fail("Сначала завершите предыдущий кубок")
	if int(state.credits) < cost:
		return _fail("Недостаточно кредитов")
	var previous := state.duplicate(true)
	state.credits -= cost
	if creature != null:
		state.owned_creatures[id] = 0
	else:
		state.owned_cards.append(id)
	state.ledger.append({"type": "purchase", "id": "purchase/" + id, "item": id, "credits": -cost})
	return _commit(previous)

func deck_error(creatures: Array, gates: Array, abilities: Array, effective_levels: Dictionary = {}) -> String:
	var problem := _cards_error([creatures, gates, abilities])
	if not problem.is_empty():
		return problem
	var total := 0
	var rules := league_rules()
	for id in creatures:
		if not state.owned_creatures.has(String(id)):
			return "В команде есть существо вне коллекции"
		var value: Variant = effective_levels.get(String(id), mini(level(String(id)), int(rules.max_level)))
		if not Cup._integer(value, 1, mini(level(String(id)), int(rules.max_level))):
			return "Недопустимый эффективный уровень"
		var g := power(String(id), int(value))
		if g > int(rules.max_power):
			return "Сила одного существа превышает лимит лиги"
		total += g
	for id in gates + abilities:
		if not state.owned_cards.has(String(id)):
			return "В колоде есть карта вне коллекции"
	for id in effective_levels:
		if not creatures.has(String(id)):
			return "Уровень указан для существа вне команды"
	return "Сумма силы команды превышает %d G" % rules.max_total if total > int(rules.max_total) else ""

static func _cards_error(ids: Variant) -> String:
	if not ids is Array or ids.size() != 3:
		return "Нужна команда и шесть карт"
	for list in ids:
		if not list is Array or list.size() != 3:
			return "Нужно по три существа, ворот и способности"
		var seen: Array = []
		for id in list:
			if not id is String and not id is StringName:
				return "Некорректный ID"
			if seen.has(String(id)):
				return "Предметы не должны повторяться"
			seen.append(String(id))
	var element := -1
	for id in ids[0]:
		var creature := CardDB.creature(StringName(id))
		if creature == null or not BASE_POWER.has(String(creature.species)):
			return "Неизвестное существо карьеры"
		if element >= 0 and element != creature.attribute:
			return "Все существа должны быть одной стихии"
		element = creature.attribute
	var species := CardDB.team_species(ids[0])
	for index in range(2):
		var classes: Array = []
		for id in ids[index + 1]:
			var card := CardDB.card(StringName(id))
			if card == null or card.kind != (CardDef.Kind.ARENA if index == 0 else CardDef.Kind.ABILITY) or not CardDB.card_fits(card, element, species):
				return "Карта не подходит команде"
			classes.append(CardDB.card_class(card))
		for cls in (CardDB.GATE_CLASSES if index == 0 else CardDB.ABILITY_CLASSES):
			if not classes.has(cls):
				return "Нужно по одной карте каждого класса"
	return ""

func start_cup(deck: DeckDef, effective_levels: Dictionary = {}) -> Error:
	if cup != null or not state.active.is_empty():
		return _fail("Команда уже зарегистрирована на кубок")
	if state.cups.size() >= MAX_CUPS:
		return _fail("Достигнут предел истории карьеры")
	var ids := Cup.deck_ids(deck) if deck != null else []
	if ids.size() != 3:
		return _fail("Команда не выбрана")
	var problem := deck_error(ids[0], ids[1], ids[2], effective_levels)
	if not problem.is_empty():
		return _fail(problem)
	var previous := state.duplicate(true)
	var levels: Dictionary = {}
	for id in ids[0]:
		levels[id] = int(effective_levels.get(id, mini(level(id), int(league_rules().max_level))))
	var serial: int = state.cups.size()
	var cup_id := "%s/cup-%d" % [state.id, serial]
	state.active = _new_entry(ids, levels, int(state.league), serial, cup_id)
	state.ledger.append({"type": "registration", "id": cup_id + "/registration", "cup": cup_id, "credits": 0})
	cup = _build_cup(state.active)
	state.active.tournament = cup.state
	return _commit(previous)

func _new_entry(ids: Array, levels: Dictionary, league_index: int, serial: int, cup_id: String) -> Dictionary:
	var snapshots: Array = [{}]
	var earned_xp: Dictionary = {}
	for id in ids[0]:
		snapshots[0][id] = power(id, int(levels[id]))
		earned_xp[id] = int(state.owned_creatures.get(id, 0))
	for npc in range(1, 8):
		var row: Array = Cup.NPCS[npc - 1]
		var species: Array = ["gorgul", "rogozhuk", "klykar"]
		if league_index == 1:
			species = ["levian", "ratnik", "gorgul"] if npc % 2 else ["grifalon", "rogozhuk", "ratnik"]
		elif league_index == 2:
			species = ["dragnar", "kolossar", "grifalon"] if npc % 2 else ["ratnik", "levian", "klykar"]
		var powers: Dictionary = {}
		for sp in species:
			powers["creature_%s_%s" % [sp, row[2]]] = int(BASE_POWER[sp]) + 10 * league_index
		snapshots.append(powers)
	return {"league": league_index, "serial": serial, "id": cup_id, "deck": ids.duplicate(true), "levels": levels.duplicate(true), "earned_xp": earned_xp, "snapshots": snapshots, "tournament": {}}

func _build_cup(entry: Dictionary) -> Tournament:
	var result := Tournament.new()
	result.autosave_path = ""
	result._build(entry.deck, int(state.difficulty), (int(state.seed) ^ (int(entry.serial) * 0x1f123bb5)) & 0x7fffffff, String(state.name), String(entry.id))
	for npc in range(1, 8):
		var row: Array = Cup.NPCS[npc - 1]
		var species: Array = []
		for id in entry.snapshots[npc]:
			species.append(String(CardDB.creature(StringName(id)).species))
		result.state.participants[npc].deck = _default_deck(String(row[2]), species, [row[4], row[5], row[6], row[7]])
	return result

func power_snapshot(participant: int) -> Dictionary:
	if cup == null or participant < 0 or participant > 7:
		return {}
	return state.active.snapshots[participant].duplicate(true)

func participant_deck(participant: int) -> DeckDef:
	return cup.participant_deck(participant) if cup != null else null

func begin_match(id: String) -> Error:
	if cup == null:
		return _fail("Сначала зарегистрируйте команду")
	var previous := state.duplicate(true)
	var code := cup.begin_match(id)
	if code != OK:
		last_error = cup.last_error
		return code
	state.active.tournament = cup.state
	return _commit(previous)

func record_result(id: String, winner: int, alive: Array, reason: String, observation: Dictionary = {}) -> Error:
	last_error = ""
	last_reward = {}
	if cup == null:
		return _fail("Кубок не начат")
	# Повтор доставки идентичного результата безопасен даже после перезапуска.
	var index := cup._match_index(id)
	if index >= 0 and cup.state.matches[index].has("result"):
		var recorded: Dictionary = cup.state.matches[index].result
		if int(recorded.winner) == winner and Cup._equivalent(recorded.alive, alive) and String(recorded.reason) == reason:
			return OK
		return _fail("У матча уже есть другой результат")
	if not _metrics_valid(observation):
		return _fail("Некорректные показатели участия")
	var duel := cup.next_match()
	if duel.is_empty() or String(duel.id) != id:
		return _fail("Матч сейчас недоступен")
	var previous := state.duplicate(true)
	var code := cup.record_result(id, winner, alive, reason)
	if code != OK:
		last_error = cup.last_error
		return code
	state.active.tournament = cup.state
	if int(duel.a) == 0 or int(duel.b) == 0:
		var npc := int(duel.b if int(duel.a) == 0 else duel.a)
		var key := "%d/%d" % [state.league, npc]
		var repeat := false
		for event in state.ledger:
			if event.type == "match" and event.encounter == key:
				repeat = true
				break
		var engaged := int(observation.get("throws", 0)) >= 2 or int(observation.get("battles", 0)) >= 1
		var credits := (15 if repeat else 60) if winner == 0 else (15 if not repeat and engaged else 0)
		var xp := (12 if repeat else 50) if winner == 0 else (20 if not repeat and engaged else 0)
		if winner == -1:
			credits = 0
			xp = (6 if repeat else 25) if engaged else 0
		var event := {"type": "match", "id": String(state.active.id) + "/" + id, "encounter": key, "winner": winner, "engaged": engaged, "repeat": repeat, "credits": credits, "xp": xp, "creatures": state.active.deck[0].duplicate()}
		state.ledger.append(event)
		state.credits += credits
		for creature_id in event.creatures:
			state.owned_creatures[creature_id] = mini(xp_for_level(10), int(state.owned_creatures[creature_id]) + xp)
		last_reward = {"credits": credits, "xp": xp, "repeat": repeat, "completion": 0}
	if cup.completed():
		var completion := _completion_reward()
		last_reward.completion = completion
		last_reward.credits = int(last_reward.get("credits", 0)) + completion
	return _commit(previous)

func _completion_reward() -> int:
	var key := "league/%d" % state.league
	var champion_key := key + "/champion"
	var ids: Array = []
	for event in state.ledger:
		ids.append(event.id)
	var reward := 0
	for pair in [[key, true], [champion_key, cup.champion() == 0]]:
		if pair[1] and not ids.has(pair[0]):
			state.ledger.append({"type": "completion", "id": pair[0], "cup": state.active.id, "credits": 150})
			reward += 150
	state.credits += reward
	return reward

static func _metrics_valid(observation: Dictionary) -> bool:
	for key in observation:
		if not ["throws", "battles", "abilities", "gate_opens"].has(key) or not Cup._integer(observation[key], 0, 4096):
			return false
	return true

func simulate_next_npc() -> Dictionary:
	if cup == null:
		return {"error": "Кубок не начат"}
	var duel := cup.next_match()
	if duel.is_empty() or int(duel.a) == 0 or int(duel.b) == 0:
		return {"error": "Этот матч должен сыграть человек"}
	var result: Dictionary = Simulator.simulate(cup.participant_deck(int(duel.a)), cup.participant_deck(int(duel.b)), int(duel.seed), int(duel.first_player), int(state.difficulty), Simulator.STEP_LIMIT, [Cup.personality(int(duel.a)), Cup.personality(int(duel.b))], [power_snapshot(int(duel.a)), power_snapshot(int(duel.b))])
	if not String(result.error).is_empty():
		return result
	var winner := -1 if int(result.winner) == -1 else int(duel.a if int(result.winner) == 0 else duel.b)
	if record_result(String(duel.id), winner, result.alive, String(result.reason)) != OK:
		return {"error": last_error}
	return {"error": "", "match": duel, "result": cup.state.matches[cup._match_index(String(duel.id))].result.duplicate(true)}

func can_advance() -> bool:
	return cup != null and cup.completed() and int(state.league) < 2

func completed() -> bool:
	return cup != null and cup.completed() and int(state.league) == 2

func advance_cup() -> Error:
	if not can_advance():
		return _fail("Следующая лига пока недоступна")
	return _leave_completed(true)

func replay_cup() -> Error:
	if cup == null or not cup.completed():
		return _fail("Сначала завершите текущий кубок")
	return _leave_completed(false)

func _leave_completed(advance: bool) -> Error:
	var previous := state.duplicate(true)
	var original_cup := cup
	state.cups.append(state.active.duplicate(true))
	state.active = {}
	if advance:
		state.league += 1
	cup = null
	return _commit(previous, original_cup)

func cup_index() -> int:
	return int(state.league)

func cup_title() -> String:
	return String(league_rules().title)

func progress_text() -> String:
	return "Карьера · %d/3 · %s" % [int(state.league) + 1, cup_title()]

func _all_cups() -> Array:
	var result: Array = state.cups.duplicate()
	if not state.active.is_empty():
		result.append(state.active)
	return result

func _fail(message: String) -> Error:
	last_error = message
	return ERR_INVALID_DATA

func _commit(previous: Dictionary, original_cup: Tournament = null) -> Error:
	last_error = ""
	if state.ledger.size() > MAX_EVENTS:
		last_error = "Достигнут предел истории операций"
		if original_cup != null:
			cup = original_cup
		_restore(previous)
		return ERR_OUT_OF_MEMORY
	if autosave_path.is_empty():
		return OK
	var code := save_file(autosave_path)
	if code != OK:
		if original_cup != null:
			cup = original_cup
		_restore(previous)
		last_reward = {}
	return code

func _restore(previous: Dictionary) -> void:
	state = previous
	if state.active.is_empty():
		cup = null
	else:
		if cup == null or String(cup.state.id) != String(state.active.id):
			cup = _build_cup(state.active)
		cup.state = state.active.tournament

static func load_file(path: String = SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "Сохранение карьеры отсутствует", "missing": true}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_SAVE_BYTES:
		return {"error": "Не удалось прочитать сохранение карьеры"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"error": "Повреждён JSON карьеры; исходный файл сохранён"}
	var restored := from_dict(parser.data)
	if String(restored.error).is_empty():
		restored.career.autosave_path = path
	return restored

static func from_dict(data: Dictionary) -> Dictionary:
	CardDB.load_all()
	var error := "Некорректное сохранение карьеры"
	if data.size() != 14 or data.get("format") != "orbstrike_career" or not Cup._integer(data.get("version"), VERSION, VERSION):
		return {"error": error}
	for key in ["id", "element", "name"]:
		if not data.get(key) is String or String(data[key]).is_empty() or String(data[key]).length() > 80:
			return {"error": error}
	if not ELEMENTS.has(data.element) or not Cup._integer(data.get("seed"), 0, 2147483647) or not Cup._integer(data.get("difficulty"), 0, 2) or not Cup._integer(data.get("league"), 0, 2) or not Cup._integer(data.get("credits"), 0, 10000000):
		return {"error": error}
	if not data.get("owned_creatures") is Dictionary or not data.get("owned_cards") is Array or not data.get("active") is Dictionary or not data.get("cups") is Array or data.cups.size() > MAX_CUPS or not data.get("ledger") is Array or data.ledger.size() > MAX_EVENTS:
		return {"error": error}
	if data.owned_creatures.size() > 8 or data.owned_cards.size() > 100:
		return {"error": error}
	for id in data.owned_creatures:
		if not id is String or not Cup._integer(data.owned_creatures[id], 0, xp_for_level(10)):
			return {"error": "Недопустимый опыт коллекции"}
		var definition := CardDB.creature(StringName(id))
		if definition == null or not BASE_POWER.has(String(definition.species)) or definition.attribute != ELEMENTS.find(data.element):
			return {"error": "Недопустимое существо коллекции"}
	var seen_cards: Array = []
	for id in data.owned_cards:
		if not id is String or seen_cards.has(id) or CardDB.card(StringName(id)) == null or not CardDB.card_fits(CardDB.card(StringName(id)), ELEMENTS.find(data.element)):
			return {"error": "Недопустимая карта коллекции"}
		seen_cards.append(id)
	var run := Career.new()
	run.autosave_path = ""
	run.state = data.duplicate(true)
	var cups := run._all_cups()
	var match_events: Dictionary = {}
	var completion_cups: Dictionary = {}
	var registrations: Dictionary = {}
	var cleared: Array = []
	var prior_league := 0
	for i in range(cups.size()):
		var entry: Variant = cups[i]
		if not entry is Dictionary or entry.size() != 8 or not Cup._integer(entry.get("league"), 0, 2) or not Cup._integer(entry.get("serial"), i, i) or entry.get("id") != "%s/cup-%d" % [data.id, i] or not entry.get("levels") is Dictionary or not entry.get("earned_xp") is Dictionary or not entry.get("snapshots") is Array or entry.snapshots.size() != 8 or not entry.get("tournament") is Dictionary or not _cards_error(entry.get("deck")).is_empty():
			return {"error": "Повреждены данные регистрации кубка"}
		if int(entry.league) < prior_league or int(entry.league) > prior_league + 1 or (i == 0 and int(entry.league) != 0) or (int(entry.league) > prior_league and not cleared.has(prior_league)):
			return {"error": "Нарушен порядок лиг"}
		prior_league = int(entry.league)
		if entry.levels.size() != 3 or entry.earned_xp.size() != 3:
			return {"error": "Повреждены уровни регистрации"}
		for id in entry.deck[0]:
			if not Cup._integer(entry.earned_xp.get(id), 0, xp_for_level(10)) or not Cup._integer(entry.levels.get(id), 1, int(LEAGUES[int(entry.league)].max_level)) or not data.owned_creatures.has(id) or int(entry.levels[id]) > level_from_xp(int(entry.earned_xp[id])):
				return {"error": "Недопустимый уровень регистрации"}
		for id in entry.deck[1] + entry.deck[2]:
			if not data.owned_cards.has(id):
				return {"error": "В регистрации отсутствующая карта"}
		var canonical := run._new_entry(entry.deck, entry.levels, int(entry.league), i, String(entry.id))
		registrations[String(entry.id)] = entry
		if not Cup._equivalent(canonical.snapshots, entry.snapshots):
			return {"error": "Снимок силы не соответствует регистрации"}
		for powers in entry.snapshots:
			var total := 0
			for id in powers:
				if not Cup._integer(powers[id], 190, int(LEAGUES[int(entry.league)].max_power)):
					return {"error": "Сила превышает лимит лиги"}
				total += int(powers[id])
			if total > int(LEAGUES[int(entry.league)].max_total):
				return {"error": "Команда превышает лимит лиги"}
		var restored := run._build_cup(canonical)
		if not entry.tournament.get("matches") is Array or entry.tournament.matches.size() < 12 or entry.tournament.matches.size() > 18:
			return {"error": "Повреждена сетка кубка"}
		for duel in entry.tournament.matches:
			if not duel is Dictionary:
				return {"error": error}
			if not duel.has("result"):
				continue
			var result: Variant = duel.result
			if not result is Dictionary or not Cup._integer(result.get("winner"), -1, 7) or not result.get("alive") is Array or not result.get("reason") is String or not duel.get("id") is String or restored.record_result(String(duel.id), int(result.winner), result.alive, String(result.reason)) != OK:
				return {"error": "Повреждён результат кубка"}
			if int(duel.get("a", -1)) == 0 or int(duel.get("b", -1)) == 0:
				match_events[String(entry.id) + "/" + String(duel.id)] = {"winner": int(result.winner), "encounter": "%d/%d" % [entry.league, int(duel.b if int(duel.a) == 0 else duel.a)], "creatures": entry.deck[0], "cup": String(entry.id)}
		if not entry.tournament.get("in_progress") is String or (not String(entry.tournament.in_progress).is_empty() and restored.begin_match(String(entry.tournament.in_progress)) != OK) or not Cup._equivalent(restored.state, entry.tournament):
			return {"error": "Сетка не соответствует каноническому расписанию"}
		if i < data.cups.size() and not restored.completed():
			return {"error": "В архиве незавершённый кубок"}
		if restored.completed():
			cleared.append(int(entry.league))
			completion_cups[String(entry.id)] = {"league": int(entry.league), "champion": restored.champion()}
		if i == cups.size() - 1 and not data.active.is_empty():
			run.cup = restored
	if (int(data.league) > 0 and not cleared.has(int(data.league) - 1)) or (not data.active.is_empty() and int(data.active.league) != int(data.league)) or int(data.league) < prior_league:
		return {"error": "Недопустимая текущая лига"}
	var starter := _default_deck(String(data.element), ["gorgul", "rogozhuk", "klykar"])
	var expected_owned: Dictionary = {}
	for id in starter[0]:
		expected_owned[id] = 0
	var expected_cards: Array = starter[1] + starter[2]
	var credits := 100
	var seen: Array = []
	var encounters: Array = []
	var consumed: Array = []
	var registered: Array = []
	var cleared_at_time: Array = []
	for event in data.ledger:
		if not event is Dictionary or not event.get("id") is String or String(event.id).length() > 160 or seen.has(event.id) or not Cup._integer(event.get("credits"), -900, 300):
			return {"error": "Повреждён журнал экономики"}
		seen.append(event.id)
		match String(event.get("type", "")):
			"registration":
				if event.size() != 4 or not event.get("cup") is String or not registrations.has(event.cup) or int(event.credits) != 0 or event.id != String(event.cup) + "/registration" or registered.has(event.cup):
					return {"error": "Повреждена запись регистрации"}
				var registration: Dictionary = registrations[event.cup]
				if int(registration.serial) != registered.size() or (int(registration.league) > 0 and not cleared_at_time.has(int(registration.league) - 1)):
					return {"error": "Лига не была открыта при регистрации"}
				for id in registration.deck[0]:
					if not expected_owned.has(id) or not Cup._equivalent(expected_owned[id], registration.earned_xp[id]):
						return {"error": "Снимок опыта не соответствует моменту регистрации"}
				for id in registration.deck[1] + registration.deck[2]:
					if not expected_cards.has(id):
						return {"error": "Карта не была куплена до регистрации"}
				registered.append(event.cup)
			"purchase":
				if event.size() != 4 or not event.get("item") is String or event.id != "purchase/" + String(event.item) or expected_owned.has(event.item) or expected_cards.has(event.item) or int(event.credits) != -run.price(String(event.item)) or int(event.credits) >= 0:
					return {"error": "Некорректная покупка"}
				var definition := CardDB.creature(StringName(event.item))
				if definition == null:
					expected_cards.append(event.item)
				else:
					if (([&"levian", &"ratnik"].has(definition.species) and not cleared_at_time.has(0)) or ([&"dragnar", &"kolossar"].has(definition.species) and not cleared_at_time.has(1))):
						return {"error": "Куплен закрытый вид"}
					expected_owned[event.item] = 0
			"match":
				if event.size() != 9 or not match_events.has(event.id) or not event.get("engaged") is bool or not event.get("repeat") is bool:
					return {"error": "Награда без результата матча"}
				var expected: Dictionary = match_events[event.id]
				if not registered.has(expected.cup):
					return {"error": "Награда раньше регистрации"}
				for key in ["winner", "encounter", "creatures"]:
					if not Cup._equivalent(expected[key], event.get(key)):
						return {"error": "Награда не соответствует матчу"}
				var repeat := encounters.has(event.encounter)
				if repeat != bool(event.repeat):
					return {"error": "Неверное повторное вознаграждение"}
				encounters.append(event.encounter)
				var expected_credits := (15 if repeat else 60) if int(event.winner) == 0 else (15 if not repeat and event.engaged else 0)
				var xp := (12 if repeat else 50) if int(event.winner) == 0 else (20 if not repeat and event.engaged else 0)
				if int(event.winner) == -1:
					expected_credits = 0
					xp = 6 if repeat else (25 if event.engaged else 0)
				if int(event.winner) == -1 and not event.engaged:
					xp = 0
				# Локальный формат v1 до 0.4.2 ошибочно выдавал 6 XP за повторную
				# ничью без участия. Только чтение сохраняет уже заработанный опыт;
				# record_result больше не может создать такую награду.
				var historical_draw: bool = int(event.winner) == -1 and repeat and not event.engaged and Cup._integer(event.get("xp"), 6, 6)
				if int(event.credits) != expected_credits or (not Cup._integer(event.get("xp"), xp, xp) and not historical_draw):
					return {"error": "Неверный размер награды"}
				for id in event.creatures:
					if not expected_owned.has(id):
						return {"error": "Опыт начислен отсутствующему существу"}
					expected_owned[id] = mini(xp_for_level(10), int(expected_owned[id]) + int(event.xp))
				consumed.append(event.id)
			"completion":
				if event.size() != 4 or not event.get("cup") is String or not completion_cups.has(event.cup) or int(event.credits) != 150:
					return {"error": "Награда без завершённого кубка"}
				var entry: Dictionary = completion_cups[event.cup]
				if event.id != "league/%d" % entry.league and (event.id != "league/%d/champion" % entry.league or int(entry.champion) != 0):
					return {"error": "Неверная награда кубка"}
				if not registered.has(event.cup):
					return {"error": "Завершение раньше регистрации"}
				for match_id in match_events:
					if match_events[match_id].cup == event.cup and not consumed.has(match_id):
						return {"error": "Завершение раньше результатов"}
				if event.id == "league/%d" % entry.league:
					cleared_at_time.append(int(entry.league))
			_:
				return {"error": "Неизвестная операция экономики"}
		credits += int(event.credits)
		if credits < 0 or credits > 10000000:
			return {"error": "Недопустимый баланс экономики"}
	if registered.size() != registrations.size() or consumed.size() != match_events.size() or not Cup._equivalent(expected_owned, data.owned_creatures) or not Cup._equivalent(expected_cards, data.owned_cards) or credits != int(data.credits):
		return {"error": "Коллекция, опыт или баланс не соответствуют журналу"}
	for entry in completion_cups.values():
		if not seen.has("league/%d" % entry.league) or (int(entry.champion) == 0 and not seen.has("league/%d/champion" % entry.league)):
			return {"error": "Не записана награда завершённого кубка"}
	return {"error": "", "career": run}

func save_file(path: String = SAVE_PATH) -> Error:
	last_error = ""
	if cup != null:
		state.active.tournament = cup.state
	var validated := from_dict(state)
	if not String(validated.error).is_empty():
		last_error = String(validated.error)
		return ERR_INVALID_DATA
	if FileAccess.file_exists(path):
		var old := load_file(path)
		if not String(old.error).is_empty():
			last_error = String(old.error)
			return ERR_FILE_CORRUPT
	var body := JSON.stringify(state, "  ")
	if body.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return _fail("Сохранение слишком велико")
	var absolute := ProjectSettings.globalize_path(path)
	var code := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if code != OK:
		return _fail("Не удалось создать папку карьеры")
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail("Не удалось записать временное сохранение")
	file.store_string(body)
	file.flush()
	code = file.get_error()
	file.close()
	if code == OK and FileAccess.file_exists(path):
		code = DirAccess.copy_absolute(absolute, absolute + ".bak")
	if code == OK:
		code = DirAccess.rename_absolute(temporary, absolute)
	if code != OK:
		DirAccess.remove_absolute(temporary)
		last_error = "Не удалось атомарно сохранить карьеру: %d" % code
	return code
