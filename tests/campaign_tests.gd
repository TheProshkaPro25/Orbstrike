extends SceneTree
const Run = preload("res://core/campaign.gd")
const Cup = preload("res://core/tournament.gd")
const Simulator = preload("res://core/tournament_npc_simulator.gd")
const TEST_PATH := "res://build/checks/campaign-unit/active.json"
var assertions := 0
var failures := 0
class QuietPanel extends AbilityPanel:
	func set_dock_visible(_value: bool) -> void:
		pass
class QuietSetup extends SetupPanel:
	func set_dock_visible(_value: bool) -> void:
		pass
func check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func make_run():
	return Run.create(CardDB.preset_deck(0), 1, 8127, "Haru Akiyama", "")
func _initialize() -> void:
	CardDB.load_all()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_PATH.get_base_dir()))
	_test_progress()
	_test_persistence()
	_test_personality()
	_test_style_decisions()
	_test_observations()
	_test_result_boundary()
	print("CAMPAIGN: %d checks, %d failures" % [assertions, failures])
	var file := FileAccess.open(TEST_PATH.get_base_dir() + "/summary.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "kind": "headless_campaign_core", "scenarios": ["three_cups", "fixed_roster_decks", "resume", "strict_validation", "atomic_rollback", "bounded_personalities", "public_observations", "same_opponent_memory", "deterministic_legal_npc"]}, "  "))
	quit(1 if failures else 0)
func finish(run, player_wins: bool) -> void:
	while not run.cup.completed():
		var duel: Dictionary = run.cup.next_match()
		var winner := int(duel.a)
		if int(duel.a) == 0 or int(duel.b) == 0:
			winner = 0 if player_wins else int(duel.b if int(duel.a) == 0 else duel.a)
		check(run.record_result(duel.id, winner, [3, 0] if winner == int(duel.a) else [0, 3], "fixture", {"throws": 4, "abilities": 3, "gate_opens": 2}) == OK, "accepted fixture result")
func _test_progress() -> void:
	var run = make_run()
	check(run != null and run.cup_index() == 0 and not run.completed(), "campaign starts first cup")
	check(run.advance_cup() != OK, "cannot skip unfinished cup")
	var deck: Array = Cup.deck_ids(run.cup.participant_deck(0))
	for index in range(3):
		check(run.cup_index() == index and run.cup_title() == Run.CUP_TITLES[index], "visible cup progression")
		for npc in range(1, 8):
			check(run.cup.participant_name(npc) == Cup.NPCS[npc - 1][0], "permanent named NPC")
			check(Cup.deck_ids(run.cup.participant_deck(npc)) == Cup.deck_ids(Cup.create(CardDB.preset_deck(0), 1, 2, "Test", "").participant_deck(npc)), "no deck strengthening")
		check(Cup.deck_ids(run.cup.participant_deck(0)) == deck, "player registration unchanged")
		finish(run, index != 1)
		check(Run.from_dict(run.state).error == "", "completed cup state validates")
		if index < 2:
			check(run.can_advance() and run.advance_cup() == OK, "completion unlocks next including elimination")
	check(run.completed() and not run.can_advance() and run.advance_cup() != OK, "three cups bounded end")
	check(run.state.cups.size() == 3 and run.state.cups[1].champion != 0, "elimination preserved without grind")
func _test_persistence() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var run = make_run()
	var duel: Dictionary = run.cup.next_match()
	check(run.begin_match(duel.id) == OK and run.save_file(TEST_PATH) == OK, "save in progress")
	var loaded: Dictionary = Run.load_file(TEST_PATH)
	check(loaded.error == "" and Cup._equivalent(run.state, loaded.campaign.state), "JSON resume exact schedule and marker")
	check(loaded.campaign.cup.next_match().seed == duel.seed, "unfinished meeting restarts same seed")
	var bad: Dictionary = run.state.duplicate(true)
	bad.version = 99
	check(Run.from_dict(bad).error != "", "unsupported format rejected")
	bad = run.state.duplicate(true)
	bad.cups.append(run.state.cups[0].duplicate(true))
	check(Run.from_dict(bad).error != "", "unfinished advance rejected")
	bad = run.state.duplicate(true)
	bad.cups[0].participants[1].deck[0][0] = "creature_ratnik_light"
	check(Run.from_dict(bad).error != "", "changed NPC deck rejected")
	bad = run.state.duplicate(true)
	bad.meetings.append({"cup": 0, "match": duel.id, "npc": 1, "winner": 0, "observation": {"throws": 1, "abilities": 2, "gate_opens": 1}})
	check(Run.from_dict(bad).error != "", "invented meeting rejected")
	var before: Dictionary = run.state.duplicate(true)
	var cup_reference: Tournament = run.cup
	var blocked := FileAccess.open(TEST_PATH + ".blocked", FileAccess.WRITE)
	blocked.store_string("{broken")
	blocked.close()
	run.autosave_path = TEST_PATH + ".blocked"
	check(run.record_result(duel.id, int(duel.a), [3, 0], "fixture") != OK and Cup._equivalent(run.state, before), "write refusal rolls back result and observations")
	check(run.cup == cup_reference, "rollback preserves Main cup object reference")
	check(run.cup.state.in_progress == duel.id and not run.cup.next_match().has("result"), "rollback resets active cup reference")
	run.autosave_path = ""
	finish(run, true)
	check(run.save_file(TEST_PATH) == OK and Run.history(TEST_PATH).entries.size() == 1, "completed cup history persisted")
	var completed_state: Dictionary = run.state.duplicate(true)
	cup_reference = run.cup
	run.autosave_path = TEST_PATH + ".blocked"
	check(run.advance_cup() != OK and run.cup == cup_reference and Cup._equivalent(run.state, completed_state), "advance refusal restores cup object and unlocked progress")
	run.autosave_path = ""
	check(run.advance_cup() == OK and run.save_file(TEST_PATH) == OK, "save next cup")
	loaded = Run.load_file(TEST_PATH)
	check(loaded.error == "" and loaded.campaign.cup_index() == 1 and loaded.campaign.state.meetings.size() == run.state.meetings.size(), "advance and opponent memory resume")
	var replacement = Run.create(CardDB.preset_deck(0), 1, 19, "Replacement", TEST_PATH)
	check(replacement != null and Run.history(TEST_PATH).entries.size() == 1, "new campaign preserves earlier completed cup history")
	var existing_history: Dictionary = Run.load_file(TEST_PATH)
	check(existing_history.error == "" and existing_history.campaign.state.history.size() == 1, "legacy campaign history persists separately")
	var legacy = Cup.create(CardDB.preset_deck(0), 1, 8, "Custom кириллица", "")
	check(Cup.from_dict(legacy.state).error == "" and legacy.participant_name(0) == "Custom кириллица", "standalone tournament remains v1 and preserves player names")
func _test_personality() -> void:
	var run = make_run()
	var distinct: Array = []
	for npc in range(1, 8):
		distinct.append(JSON.stringify(Cup.personality(npc)))
		check(run.ai_preferences(npc) == Cup.personality(npc), "unmet opponent has fixed base style")
	var unique := {}
	for entry in distinct:
		unique[entry] = true
	check(unique.size() == 7, "seven distinct AI personalities")
	var bot := AIPlayer.new(1, 1, -1.0, 1)
	bot.configure_personality({"attack_bias": 99999, "trap_bias": -99999, "safe_margin": INF, "card_cost_bias": 99})
	check(bot.personality.attack_bias == 60 and bot.personality.trap_bias == -60 and bot.personality.safe_margin == 0 and bot.personality.card_cost_bias == 0.04, "personality input bounded")
	check(bot.get_aim_error() == AIPlayer.AIM_ERROR[1] and bot.difficulty == 1, "personality does not alter accuracy or difficulty")
	finish(run, true)
	var memories: Array = run.state.meetings.duplicate(true)
	check(run.advance_cup() == OK, "second cup for rematch memory")
	var met: int = memories[0].npc
	check(run.ai_preferences(met) != Cup.personality(met) and "Память" in run.opponent_brief(met), "same opponent remembers public completed meeting")
	for npc in range(1, 8):
		if not memories.any(func(m): return int(m.npc) == npc):
			check(run.ai_preferences(npc) == Cup.personality(npc), "other opponents do not borrow memory")
	var prefs: Dictionary = run.ai_preferences(met)
	var restored: Dictionary = Run.from_dict(run.state)
	check(restored.error == "" and Cup._equivalent(restored.campaign.ai_preferences(met), prefs), "saved rematch preference deterministic")
	var a: DeckDef = run.cup.participant_deck(1)
	var b: DeckDef = run.cup.participant_deck(5)
	var first := Simulator.simulate(a, b, 923, 0, 1, 4096, [Cup.personality(1), Cup.personality(5)])
	var second := Simulator.simulate(a, b, 923, 0, 1, 4096, [Cup.personality(1), Cup.personality(5)])
	check(first.error == "" and second.error == "" and first.trace.actions == second.trace.actions and first.alive == second.alive, "styled NPC legal and deterministic")
func _test_observations() -> void:
	var actions := [["start", [0]], ["select_creature", [0, 2]], ["throw_with_gate", [0, "hidden", 0, 2]], ["play_ability", [0, "public"]], ["play_ability", [1, "opponent"]], ["reveal_gate", [0]], ["report_landing", [0, 3]]]
	check(Run.observations_from_actions(actions, 0) == {"throws": 2, "abilities": 1, "gate_opens": 1}, "only public accepted player action types counted")
	check(Run.observations_from_actions(actions, 1) == {"throws": 0, "abilities": 1, "gate_opens": 0}, "side mapping respected")
	var run = make_run()
	var duel: Dictionary = run.cup.next_match()
	check(run.record_result(duel.id, int(duel.a), [3, 0], "fixture", {"abilities": -1}) != OK, "malformed observation rejected")

func _test_result_boundary() -> void:
	var run = make_run()
	var duel: Dictionary = run.cup.next_match()
	while int(duel.a) != 0 and int(duel.b) != 0:
		run.record_result(duel.id, int(duel.a), [3, 0], "fixture")
		duel = run.cup.next_match()
	var path := TEST_PATH + ".boundary"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	run.autosave_path = path
	check(run.begin_match(duel.id) == OK, "campaign boundary persists marker")
	var main = load("res://scenes/main.gd").new()
	var panel := QuietPanel.new()
	var setup := QuietSetup.new()
	var events := EventPlayer.new()
	events._running = true
	main.campaign = run
	main.tournament = run.cup
	main._tournament_match = duel
	main.ability_panel = panel
	main.setup_panel = setup
	main.events = events
	var opponent: int = int(duel.b) if int(duel.a) == 0 else int(duel.a)
	main.ctrl = MatchController.new(run.cup.participant_deck(0), run.cup.participant_deck(opponent), int(duel.seed))
	main.ctrl.state.phase = MatchController.Phase.GAME_OVER
	main.ctrl.winner = 0
	main.ctrl.game_over_reason = &"knockout"
	main.ctrl.action_trace = [["play_ability", [0, "public-a"]], ["play_ability", [0, "public-b"]], ["reveal_gate", [0]]]
	for uid in main.ctrl.state.players[1].creature_uids:
		main.ctrl.state.creatures[uid].alive = false
	main._on_game_over(0, &"knockout")
	check(events.is_busy() and events._queue.size() == 1, "campaign animation still queued")
	check(run.cup.next_match().id != duel.id and run.cup.state.in_progress == "", "campaign result accepted before animation")
	var restored := Run.load_file(path)
	check(restored.error == "" and Cup._equivalent(run.state, restored.campaign.state), "campaign result and observation durable before animations")
	check(run.state.meetings.size() == 1 and run.state.meetings[0].npc == opponent and run.state.meetings[0].observation.abilities == 2, "Main forwards actual public player observations")
	check(run.cup.state.matches[run.cup._match_index(duel.id)].result.alive == ([3, 0] if int(duel.a) == 0 else [0, 3]), "Main result side remap preserved")
	var snapshot: Dictionary = run.state.duplicate(true)
	main._on_game_over(0, &"knockout")
	check(Cup._equivalent(snapshot, run.state), "campaign repeated result no duplicate memory")
	events._queue.clear()
	main.free()
	panel.free()
	setup.free()
	events.free()

func _test_style_decisions() -> void:
	var attacker := CreatureDef.make(&"campaign_test_attacker", "attacker", Attr.A.FIRE, 375, Color.WHITE)
	var defender := CreatureDef.make(&"campaign_test_defender", "defender", Attr.A.FIRE, 300, Color.WHITE)
	attacker.species = &"dragnar"
	defender.species = &"dragnar"
	CardDB._creatures[String(attacker.id)] = attacker
	CardDB._creatures[String(defender.id)] = defender
	var boost := CardDef.make(&"campaign_test_boost", "boost", 1, &"boost", {"amount": 80}, "")
	CardDB._cards[String(boost.id)] = boost
	var view := MatchState.new()
	view.creatures[0] = CreatureState.new(0, attacker.id, 0)
	view.creatures[1] = CreatureState.new(1, defender.id, 1)
	view.players[0].creature_uids.assign([0])
	view.players[1].creature_uids.assign([1])
	view.players[0].ability_hand.assign([boost.id])
	view.players[1].ability_hand.assign([&""])
	var preview := PowerCalc.compute_seq(view, 0, 1, 0, [])
	var akari := AIPlayer.new(0, 9, -1.0, 1)
	akari.configure_personality(Cup.personality(1))
	var daichi := AIPlayer.new(0, 9, -1.0, 1)
	daichi.configure_personality(Cup.personality(4))
	check(akari.choose_ability(view, preview, [boost.id]) == &"" and daichi.choose_ability(view, preview, [boost.id]) == boost.id, "same public state produces distinct actual personality decision")
	check(preview.powers == [375, 300] and view.players[0].ability_hand == [boost.id], "personality decision leaves battle power and hand unchanged")
	check(akari.choose_ability(view, preview, []) == &"" and daichi.choose_ability(view, preview, []) == &"", "styles respect controller legal ability filter")
