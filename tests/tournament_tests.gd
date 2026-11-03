extends SceneTree
const Cup = preload("res://core/tournament.gd")
const Simulator = preload("res://core/tournament_npc_simulator.gd")
var failures := 0
var assertions := 0
const TEST_PATH := "res://build/checks/tournament-unit/active.json"

class QuietPanel extends AbilityPanel:
	func set_dock_visible(_value: bool) -> void:
		pass

func check(value: bool, text: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", text)

func make_cup(seed_value: int = 8127):
	return Cup.create(CardDB.preset_deck(0), AIPlayer.Difficulty.NORMAL, seed_value, "Проверка", "")

func _initialize() -> void:
	CardDB.load_all()
	_test_schedule()
	_test_standings()
	_test_knockout()
	_test_persistence()
	_test_npc_names()
	_test_npc()
	_test_campaign_paths()
	_test_first_player_replay()
	_test_result_boundary()
	print("TOURNAMENT: %d checks, %d failures" % [assertions, failures])
	var summary := FileAccess.open("res://build/checks/tournament-unit/summary.json", FileAccess.WRITE)
	summary.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "kind": "headless_core_and_result_boundary", "scenarios": ["schedule", "recursive_standings", "knockout_replay", "atomic_save_validation", "npc_name_compatibility", "npc_determinism", "human_champion", "human_eliminated_npc_completion", "first_player_replay", "save_before_animation_drains"]}, "  "))
	summary.close()
	quit(1 if failures else 0)

func _test_schedule() -> void:
	var cup = make_cup()
	check(cup != null, "legal player + all seven fixed NPC decks")
	if cup == null:
		printerr(Cup.creation_error)
		return
	check(cup.state.matches.size() == 12, "twelve group duels")
	var seen: Array = []
	var per_round: Dictionary = {}
	var per_player: Dictionary = {}
	var opening_counts: Dictionary = {}
	for duel in cup.state.matches:
		var pair := "%d-%d" % [mini(duel.a, duel.b), maxi(duel.a, duel.b)]
		check(not seen.has(pair), "each group pair once")
		seen.append(pair)
		var opener: int = int(duel.a if duel.first_player == 0 else duel.b)
		opening_counts[opener] = int(opening_counts.get(opener, 0)) + 1
		for id in [duel.a, duel.b]:
			var key := "%d-%d" % [id, duel.round]
			check(not per_round.has(key), "each entrant once per round")
			per_round[key] = true
			per_player[id] = int(per_player.get(id, 0)) + 1
	for count in per_player.values():
		check(count == 3, "three matches per entrant")
	for id in range(8):
		check(int(opening_counts.get(id, 0)) >= 1 and int(opening_counts.get(id, 0)) <= 2, "balanced one or two starts per entrant")
	var other = make_cup()
	check(cup.state.groups == other.state.groups and cup.state.lot == other.state.lot and cup.state.matches == other.state.matches, "seed fixes draw, lot, schedule, first players")
	var first: Dictionary = cup.next_match()
	check(cup.record_result(first.id, 99, [3, 0], "knockout") != OK, "reject foreign winner")
	check(cup.record_result(first.id, first.a, [4, 0], "knockout") != OK, "reject invalid alive counts")
	check(cup.record_result(first.id, first.a, [0, 3], "knockout") != OK, "reject winner with no alive creatures")
	check(cup.record_result(first.id, -1, [2, 3], "turn_limit") != OK, "reject draw with unequal alive counts")
	check(cup.record_result(first.id, first.a, [3, 0], "knockout") == OK, "accept next result")
	var snapshot: Dictionary = cup.state.duplicate(true)
	check(cup.record_result(first.id, first.a, [3, 0], "knockout") != OK and cup.state == snapshot, "results exactly once")
	var illegal := CardDB.build_deck(["creature_dragnar_fire", "creature_dragnar_fire", "creature_grifalon_fire"], ["arena_field_fire", "arena_den_dragnar", "arena_mirror"], ["ability_fire_drain", "ability_fire_assault", "ability_dragnar_rush"])
	check(Cup.create(illegal, 1, 5, "Игрок", "") == null, "illegal registration rejected")

func _test_standings() -> void:
	var cup = make_cup()
	var a: Array = cup.state.groups.A
	# X/Y/Z по 6 очков: mini diff X=1,Y=1,Z=-2. Их общая diff Y=4>X=2,
	# но повторная мини-таблица X/Y ставит X выше за личную победу.
	var outcomes := {}
	_fixture(outcomes, a[0], a[1], a[0], [2, 0])
	_fixture(outcomes, a[1], a[2], a[1], [3, 0])
	_fixture(outcomes, a[2], a[0], a[2], [1, 0])
	_fixture(outcomes, a[0], a[3], a[0], [1, 0])
	_fixture(outcomes, a[1], a[3], a[1], [3, 0])
	_fixture(outcomes, a[2], a[3], a[2], [3, 0])
	while cup.state.matches.size() == 12:
		var duel: Dictionary = cup.next_match()
		if duel.stage == "group_A":
			var result: Dictionary = outcomes["%d-%d" % [duel.a, duel.b]]
			check(cup.record_result(duel.id, result.winner, result.alive, "fixture") == OK, "record mini-table fixture")
		else:
			cup.record_result(duel.id, -1, [1, 1], "fixture")
	var table: Array = cup.standings("A")
	check(table[0].id == a[0] and table[1].id == a[1] and table[2].id == a[2], "recursive mini-table precedes overall difference")
	check(table[0].points == 6 and table[3].points == 0 and table[0].played == 3, "3/1/0 scoring and played totals")
	var b := cup.standings("B")
	var lot: Array = []
	for id in cup.state.lot:
		if cup.state.groups.B.has(id):
			lot.append(id)
	check(b.map(func(row): return row.id) == lot, "fully equal group uses saved lot")
	var semis: Array = cup.state.matches.slice(12)
	check(semis[0].a == table[0].id and semis[0].b == b[1].id and semis[1].a == b[0].id and semis[1].b == table[1].id, "crossed semifinal A1-B2 and B1-A2")
	var empty = make_cup()
	var rows := {0: {"diff": 1, "wins": 0}, 1: {"diff": 0, "wins": 2}}
	check(empty._resolve_tie([0, 1], rows) == [0, 1], "overall difference before wins")
	rows[1].diff = 1
	check(empty._resolve_tie([0, 1], rows) == [1, 0], "wins before lot when overall difference equal")

func _fixture(outcomes: Dictionary, a: int, b: int, winner: int, alive: Array) -> void:
	outcomes["%d-%d" % [a, b]] = {"winner": winner, "alive": alive}
	outcomes["%d-%d" % [b, a]] = {"winner": winner, "alive": [alive[1], alive[0]]}

func _groups_draw(cup) -> void:
	for index in range(12):
		var duel: Dictionary = cup.next_match()
		check(cup.record_result(duel.id, -1, [1, 1], "turn_limit") == OK, "group draw")

func _test_knockout() -> void:
	var cup = make_cup()
	_groups_draw(cup)
	for stage_index in range(3):
		var duel: Dictionary = cup.next_match()
		check(duel.attempt == 0, "first knockout attempt")
		cup.record_result(duel.id, -1, [0, 0], "knockout")
		var replay: Dictionary = cup.next_match()
		check(replay.a == duel.a and replay.b == duel.b and replay.attempt == 1 and replay.first_player == 1 - duel.first_player, "exactly one replay swaps first player")
		var expected: int = cup._ko_advancer(duel.a, duel.b)
		cup.record_result(replay.id, -1, [0, 0], "knockout")
		var stored: Dictionary = cup.state.matches[cup._match_index(replay.id)].result
		check(stored.winner == -1 and stored.advancing == expected, "second duel stays draw; tiebreak advancement separate")
		if stage_index < 2:
			check(expected == duel.a, "group first beats group second on second draw")
	check(cup.completed() and cup.champion() >= 0 and cup.state.matches.size() == 18 and cup.next_match().is_empty(), "completed bracket bounded to eighteen duels")
	check(cup.player_eliminated() == (cup.champion() != 0), "terminal player elimination")

func _test_persistence() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_PATH.get_base_dir()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var cup = make_cup()
	cup.autosave_path = TEST_PATH
	var duel: Dictionary = cup.next_match()
	check(cup.begin_match(duel.id) == OK and cup.state.in_progress == duel.id, "begin match persists unfinished marker")
	check(cup.begin_match(duel.id) == OK, "begin match idempotent")
	var loaded := Cup.load_file(TEST_PATH)
	check(loaded.error == "" and loaded.tournament.state == cup.state, "strict JSON roundtrip")
	if loaded.error != "":
		printerr(loaded.error)
		return
	check(loaded.tournament.next_match() == duel, "restart same duel from beginning")
	var snapshot: Dictionary = cup.state.duplicate(true)
	var blocked := FileAccess.open(TEST_PATH + ".blocked", FileAccess.WRITE)
	blocked.store_string("{broken")
	blocked.close()
	cup.autosave_path = TEST_PATH + ".blocked"
	check(cup.record_result(duel.id, duel.a, [3, 0], "knockout") != OK and cup.state == snapshot, "save failure rolls back result and marker")
	cup.autosave_path = TEST_PATH
	check(cup.record_result(duel.id, duel.a, [3, 0], "knockout") == OK and cup.state.in_progress == "", "result autosaves and clears marker")
	var bad: Dictionary = cup.state.duplicate(true)
	bad.matches[0].seed += 1
	check(Cup.from_dict(bad).error != "", "reject tampered seed")
	bad = cup.state.duplicate(true)
	bad.lot.reverse()
	check(Cup.from_dict(bad).error != "", "reject changed saved lot")
	bad = cup.state.duplicate(true)
	bad.version = 99
	check(Cup.from_dict(bad).error != "", "unsupported version rejected")
	check(Cup.from_dict({"version": 1, "seed": [], "difficulty": 1}).error != "", "malformed nested data rejected without crash")
	while not cup.completed():
		duel = cup.next_match()
		cup.record_result(duel.id, duel.a, [3, 0], "knockout")
	check(cup.save_file(TEST_PATH) == OK and cup.save_file(TEST_PATH) == OK, "completed save repeatable")
	var history := Cup.history(TEST_PATH)
	check(history.error == "" and history.entries.size() == 1 and history.entries[0].id == cup.state.id, "history exactly once")
	var second = make_cup(8)
	check(second.save_file(TEST_PATH) == OK and Cup.history(TEST_PATH).entries.size() == 1, "new active preserves history")
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(Cup.load_file(TEST_PATH).error != "" and second.save_file(TEST_PATH) != OK and FileAccess.get_file_as_string(TEST_PATH) == "{broken", "corrupt save rejected and preserved")
	check(Cup.archive_invalid(TEST_PATH) == OK and not FileAccess.file_exists(TEST_PATH), "explicit archive frees path and preserves corrupt file")

func _test_npc_names() -> void:
	var expected := ["Akari Hoshino", "Ren Kazehara", "Hikari Aizawa", "Daichi Iwata", "Yui Kurose", "Kaito Minase", "Takumi Hayashi"]
	var cup = Cup.create(CardDB.preset_deck(0), 1, 8127, Cup.LEGACY_NPC_NAMES[0], "")
	for id in range(1, 8):
		check(cup.participant_name(id) == expected[id - 1], "Japanese display name for NPC %d" % id)
	var duel: Dictionary = cup.next_match()
	cup.record_result(duel.id, duel.a, [3, 0], "fixture")
	cup.begin_match(cup.next_match().id)
	var legacy: Dictionary = cup.state.duplicate(true)
	for id in range(1, 8):
		legacy.participants[id].name = Cup.LEGACY_NPC_NAMES[id - 1]
	var original: Dictionary = legacy.duplicate(true)
	var restored := Cup.from_dict(legacy)
	check(restored.error == "" and restored.tournament.state == cup.state, "legacy active names preserve results, seed, decks and unfinished match")
	check(legacy == original, "name compatibility does not mutate caller data")
	check(restored.tournament.participant_name(0) == Cup.LEGACY_NPC_NAMES[0], "player-chosen name is never renamed")
	legacy.participants[1].name = Cup.LEGACY_NPC_NAMES[1]
	check(Cup.from_dict(legacy).error != "", "legacy name for a different ID remains invalid")
	legacy = original.duplicate(true)
	legacy.participants[1].deck[0][0] = "creature_levian_tide"
	check(Cup.from_dict(legacy).error != "", "legacy labels do not bypass strict NPC deck validation")
	# Завершённый турнир с чемпионом-NPC и предыдущие итоги всех семи NPC.
	while not cup.completed():
		duel = cup.next_match()
		var winner: int = int(duel.b) if int(duel.a) == 0 else int(duel.a)
		cup.record_result(duel.id, winner, [0, 3] if winner == int(duel.b) else [3, 0], "fixture")
	check(cup.champion() > 0, "legacy history fixture has NPC champion")
	legacy = cup.state.duplicate(true)
	for id in range(1, 8):
		legacy.participants[id].name = Cup.LEGACY_NPC_NAMES[id - 1]
	var entries: Array = []
	for id in range(1, 8):
		entries.append({"id": "previous-%d" % id, "name": "Игрок", "champion": id, "champion_name": Cup.LEGACY_NPC_NAMES[id - 1], "player_rank": 5, "seed": id, "difficulty": 1})
	var completed_entry: Dictionary = cup._history_entry()
	completed_entry.champion_name = Cup.LEGACY_NPC_NAMES[cup.champion() - 1]
	entries.append(completed_entry)
	var path := TEST_PATH + ".names"
	var file := FileAccess.open(path, FileAccess.WRITE)
	var body := JSON.stringify({"format": "sfery_tournament", "version": 1, "active": legacy, "history": entries})
	file.store_string(body)
	file.close()
	restored = Cup.load_file(path)
	check(restored.error == "" and restored.tournament.state == cup.state, "completed legacy active and matching history load together")
	var history := Cup.history(path)
	check(history.error == "" and history.entries.size() == 8, "all previous tournament results retained")
	for id in range(1, 8):
		check(history.entries[id - 1].champion_name == expected[id - 1], "legacy history shows Japanese champion name %d" % id)
	check(FileAccess.get_file_as_string(path) == body, "reading old save leaves its bytes intact")
	check(restored.tournament.save_file(path) == OK, "next save writes current names without duplicate history")
	check(Cup.load_file(path).error == "" and Cup.history(path).entries.size() == 8, "renamed save roundtrips with unchanged history count")
	var written: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(Cup._equivalent(cup.state, written.active) and Cup._equivalent(history.entries, written.history), "only display names change on disk")

func _test_npc() -> void:
	var cup = make_cup(613)
	while not cup.next_match().is_empty() and (cup.next_match().a == 0 or cup.next_match().b == 0):
		var human: Dictionary = cup.next_match()
		check(cup.simulate_next_npc().error != "", "NPC simulator refuses human duel")
		cup.record_result(human.id, human.a, [3, 0], "fixture")
	var duel: Dictionary = cup.next_match()
	var a: DeckDef = cup.participant_deck(duel.a)
	var b: DeckDef = cup.participant_deck(duel.b)
	var first := Simulator.simulate(a, b, duel.seed, duel.first_player, 1)
	var second := Simulator.simulate(a, b, duel.seed, duel.first_player, 1)
	check(first.error == "" and first == second, "seeded NPC duel deterministic including command trace")
	if first.error == "":
		var replay := MatchReplay.restore(first.trace)
		check(replay.error == "" and replay.controller.winner == first.winner, "NPC duel command trace replays through MatchController")
	check(Simulator.simulate(a, b, duel.seed, duel.first_player, 1, 0).error != "", "bounded simulator explicit failure, no fabricated winner")
	check(Simulator.simulate(null, b, duel.seed, duel.first_player, 1).error != "", "invalid simulator arguments return explicit error")
	var result := cup.simulate_next_npc()
	check(result.error == "" and cup.next_match().id != duel.id, "NPC result recorded once and advances schedule")

func _test_campaign_paths() -> void:
	var champion_cup = make_cup(313)
	while not champion_cup.completed():
		var duel: Dictionary = champion_cup.next_match()
		var winner: int = 0 if duel.a == 0 or duel.b == 0 else int(duel.a)
		var alive := [3, 0] if winner == int(duel.a) else [0, 3]
		check(champion_cup.record_result(duel.id, winner, alive, "knockout") == OK, "human champion path result")
	check(champion_cup.champion() == 0 and not champion_cup.player_eliminated(), "three group wins plus semifinal/final crown player")
	var path := TEST_PATH + ".eliminated"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var eliminated = make_cup(613)
	eliminated.autosave_path = path
	var losses := 0
	for index in range(12):
		var duel: Dictionary = eliminated.next_match()
		var human: bool = duel.a == 0 or duel.b == 0
		var winner: int = int(duel.b) if duel.a == 0 else int(duel.a)
		check(eliminated.record_result(duel.id, winner, [3, 0] if winner == int(duel.a) else [0, 3], "knockout") == OK, "elimination group path result")
		if human:
			losses += 1
		if losses == 2:
			var loaded := Cup.load_file(path)
			check(loaded.error == "" and loaded.tournament.state == eliminated.state, "resume before third group loss")
			eliminated = loaded.tournament
	check(losses == 3 and eliminated.player_eliminated(), "three losses eliminate player before semifinals")
	var npc_count := 0
	while not eliminated.completed() and npc_count < 6:
		var result: Dictionary = eliminated.simulate_next_npc()
		check(result.error == "", "eliminated player watches remaining NPC bracket complete")
		if result.error != "":
			printerr(result.error)
			break
		npc_count += 1
	var restored := Cup.load_file(path)
	check(eliminated.completed() and eliminated.champion() > 0 and restored.error == "" and restored.tournament.completed(), "NPC champion autosaved and resumes as completed")
	check(Cup.history(path).entries.size() == 1, "elimination path writes one history result")

func _test_first_player_replay() -> void:
	for first in [0, 1]:
		var ctrl := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(1), 72)
		ctrl.start(first)
		var restored := MatchReplay.restore(ctrl.debug_snapshot())
		check(restored.error == "" and restored.controller.get_active_player() == first, "explicit first player command replay %d" % first)
	var old_ctrl := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(1), 72)
	var old_trace := old_ctrl.debug_snapshot()
	old_trace.actions = [["start", []]]
	var legacy := MatchReplay.restore(old_trace)
	check(legacy.error == "" and legacy.controller.get_active_player() == 0, "old start[] trace remains compatible")

func _test_result_boundary() -> void:
	var cup = make_cup(613)
	var duel: Dictionary = cup.next_match()
	while duel.a != 0 and duel.b != 0:
		cup.record_result(duel.id, duel.a, [3, 0], "knockout")
		duel = cup.next_match()
	var path := TEST_PATH + ".boundary"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	cup.autosave_path = path
	check(cup.begin_match(duel.id) == OK, "boundary fixture has persisted in-progress marker")
	# Main is deliberately outside the tree: no scene, renderer, Boot or animation.
	var main = load("res://scenes/main.gd").new()
	var panel := QuietPanel.new()
	var events := EventPlayer.new()
	events._running = true
	main.tournament = cup
	main._tournament_match = duel
	main.ability_panel = panel
	main.events = events
	main.ctrl = MatchController.new(cup.participant_deck(0), cup.participant_deck(int(duel.b) if duel.a == 0 else int(duel.a)), int(duel.seed))
	main.ctrl.state.phase = MatchController.Phase.GAME_OVER
	main.ctrl.winner = 0
	main.ctrl.game_over_reason = &"knockout"
	for uid in main.ctrl.state.players[1].creature_uids:
		main.ctrl.state.creatures[uid].alive = false
	main._on_game_over(0, &"knockout")
	check(events.is_busy() and events._queue.size() == 1, "result animation still queued and unplayed")
	check(cup.next_match().id != duel.id and cup.state.in_progress == "", "logical game-over advances before animation queue drains")
	var restored := Cup.load_file(path)
	check(restored.error == "" and restored.tournament.state == cup.state, "logical result already durable while presentation busy")
	var snapshot: Dictionary = cup.state.duplicate(true)
	main._on_game_over(0, &"knockout")
	check(cup.state == snapshot, "repeated result notification records no duplicate")
	events._queue.clear()
	main.free()
	panel.free()
	events.free()
