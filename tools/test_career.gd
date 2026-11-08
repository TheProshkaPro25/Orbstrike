extends SceneTree
const Run = preload("res://core/career.gd")
const Cup = preload("res://core/tournament.gd")
const PATH := "res://build/checks/career-unit/active.json"
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	preload("res://tools/test_window.gd").background(self)
	CardDB.load_all()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATH.get_base_dir()))
	_test_starters()
	_test_rewards_progression()
	_test_loss_and_integrity()
	_test_draw_participation()
	_test_economy_paths()
	_test_persistence()
	print("CAREER: %d checks, %d failures" % [checks, failures])
	var file := FileAccess.open(PATH.get_base_dir() + "/summary.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "scenarios": ["six_starters", "xp_thresholds", "league_caps", "registration_lock", "transaction_rewards", "repeat_dampening", "purchase_ownership", "strict_corrupt_refusal", "atomic_rollback", "independent_legacy", "draw_participation", "legacy_draw_compatibility", "economy_loss_champion_paths"]}, "  "))
	quit(1 if failures else 0)

func make_run(element: String = "fire") -> Career:
	return Run.create(element, 1, 8127, "Career Fixture", "")

func play_next(run: Career, human_wins: bool = true, engaged: bool = true) -> void:
	var duel := run.cup.next_match()
	var winner := int(duel.a)
	if int(duel.a) == 0 or int(duel.b) == 0:
		winner = 0 if human_wins else int(duel.b if int(duel.a) == 0 else duel.a)
	check(run.record_result(String(duel.id), winner, [3, 0] if winner == int(duel.a) else [0, 3], "fixture", {"throws": 3 if engaged else 0, "battles": 1 if engaged else 0}) == OK, "canonical fixture result accepted")

func finish(run: Career, human_wins: bool = true) -> void:
	var budget := 20
	while not run.cup.completed() and budget > 0:
		play_next(run, human_wins)
		budget -= 1
	check(run.cup.completed(), "cup completes within schedule budget")

func _test_starters() -> void:
	check(Run.xp_for_level(1) == 0 and Run.xp_for_level(2) == 100 and Run.xp_for_level(3) == 240 and Run.xp_for_level(10) == 2340, "total XP progression")
	check(Run.level_from_xp(99) == 1 and Run.level_from_xp(100) == 2 and Run.level_from_xp(239) == 2 and Run.level_from_xp(240) == 3, "level boundaries")
	var old_power := CardDB.creature(&"creature_gorgul_fire").base_power
	for element in Run.ELEMENTS:
		var run := make_run(element)
		check(run != null and run.cup == null and run.state.credits == 100, "pending starter and 100 credits " + element)
		var ids := Cup.deck_ids(run.starter_deck())
		check(run.deck_error(ids[0], ids[1], ids[2]).is_empty(), "starter deck classes and ownership " + element)
		var total := 0
		for id in ids[0]:
			total += run.power(id)
		check(total == 620, "starter total620 " + element)
		check(run.start_cup(run.starter_deck()) == OK, "register starter " + element)
		check(Run.from_dict(run.state).error == "", "fresh registration roundtrip " + element)
		for npc in range(1, 8):
			var powers := run.power_snapshot(npc)
			var npc_total := 0
			for id in powers:
				npc_total += int(powers[id])
			check(npc_total <= 650 and run.cup.participant_name(npc) == Cup.NPCS[npc - 1][0], "league0 legal fixed NPC")
		check(run.start_cup(run.starter_deck()) != OK and run.advance_cup() != OK, "registration cannot change or skip")
		check(run.purchase("creature_grifalon_" + element) != OK, "shop locked during cup")
		check(run.deck_error(ids[0], [ids[1][0], ids[1][0], ids[1][2]], ids[2]) != "", "duplicate gate rejected")
		check(run.deck_error(ids[0], ids[1], ids[2], {ids[0][0]: 2}) != "", "unearned level rejected")
		check(run.deck_error(ids[0], ids[1], ids[2], {"not_in_roster": 1}) != "", "foreign level override rejected")
	check(CardDB.creature(&"creature_gorgul_fire").base_power == old_power, "legacy G unchanged")
	check(Cup.from_dict(Cup.create(CardDB.preset_deck(0), 1, 9, "Legacy", "").state).error == "", "legacy tournament unchanged")

func _test_rewards_progression() -> void:
	var run := make_run()
	check(run.start_cup(run.starter_deck()) == OK, "register progression")
	var snapshots: Array = run.state.active.snapshots.duplicate(true)
	while int(run.cup.next_match().a) != 0 and int(run.cup.next_match().b) != 0:
		play_next(run)
	var duel := run.cup.next_match()
	check(run.begin_match(String(duel.id)) == OK, "begin persists marker")
	play_next(run)
	var before := run.state.duplicate(true)
	check(run.last_reward.credits == 60 and run.last_reward.xp == 50, "firstwin reward")
	check(run.record_result(String(duel.id), 0, [3, 0] if int(duel.a) == 0 else [0, 3], "fixture") == OK and Cup._equivalent(before, run.state), "duplicate result idempotent")
	check(run.record_result(String(duel.id), 0, [2, 0] if int(duel.a) == 0 else [0, 2], "different") != OK, "conflicting duplicate rejected")
	finish(run)
	check(Cup._equivalent(snapshots, run.state.active.snapshots), "XP never changes registered snapshots")
	check(run.available_species().has(&"levian") and not run.available_species().has(&"dragnar"), "firstcup unlocks intermediate species")
	check(Run.from_dict(run.state).error == "", "rewardledger canonical aftercup")
	var credits := int(run.state.credits)
	check(run.replay_cup() == OK and run.cup == null, "replay returns to registration")
	check(run.start_cup(run.starter_deck()) != OK, "earned levels exceeding team650 require reduction")
	var levels: Dictionary = {}
	for id in run.state.owned_creatures:
		levels[id] = 1
	check(run.start_cup(run.starter_deck(), levels) == OK, "lower effective level accepted")
	finish(run)
	check(int(run.state.credits) - credits < 300, "repeatcup completion and champion reward not farmed")
	check(Run.from_dict(run.state).error == "", "repeat ledger validates")
	check(run.advance_cup() == OK and int(run.state.league) == 1, "nextleague aftercompletion")
	check(run.purchase("creature_grifalon_fire") == OK, "regular creature400 purchase")
	check(run.purchase("creature_grifalon_fire") != OK, "no duplicatecreature purchase")
	check(run.purchase("creature_dragnar_fire") != OK, "late species locked beforesecondcup")
	check(run.start_cup(run.starter_deck()) == OK, "newroster secondleague")
	finish(run)
	check(run.available_species().has(&"dragnar"), "secondcup unlocks finalspecies")
	check(run.advance_cup() == OK and run.start_cup(run.starter_deck()) == OK, "thirdleague registration")
	finish(run)
	check(run.completed() and not run.can_advance() and run.advance_cup() != OK, "bounded threeleague career")
	check(Run.from_dict(run.state).error == "", "completecareer validator")

func _test_loss_and_integrity() -> void:
	var run := make_run()
	check(run.price("ability_gale_rebuttal") == 0 and run.purchase("ability_gale_rebuttal") != OK and run.state.credits == 100 and not run.state.owned_cards.has("ability_gale_rebuttal"), "foreign zero-price purchase rejected independently of UI")
	run.start_cup(run.starter_deck())
	while int(run.cup.next_match().a) != 0 and int(run.cup.next_match().b) != 0:
		play_next(run)
	play_next(run, false, false)
	check(run.last_reward.credits == 0 and run.last_reward.xp == 0, "nonparticipatingloss not rewarded")
	while int(run.cup.next_match().a) != 0 and int(run.cup.next_match().b) != 0:
		play_next(run)
	play_next(run, false, true)
	check(run.last_reward.credits == 15 and run.last_reward.xp == 20, "participatingfirstloss rewarded")
	check(Run.from_dict(run.state).error == "", "lossmetrics roundtrip")
	for field in ["credits", "version", "owned_creatures", "ledger", "active"]:
		var bad := run.state.duplicate(true)
		match field:
			"credits": bad.credits += 1
			"version": bad.version = 99
			"owned_creatures": bad.owned_creatures["creature_gorgul_fire"] = 999999
			"ledger": bad.ledger.append(bad.ledger[-1].duplicate(true))
			"active": bad.active.snapshots[0]["creature_gorgul_fire"] += 10
		check(Run.from_dict(bad).error != "", "tampering rejected " + field)
	var bad := run.state.duplicate(true)
	bad.owned_creatures["creature_gorgul_fire"] = {}
	check(Run.from_dict(bad).error != "", "wrong XP type rejected")
	bad = run.state.duplicate(true)
	bad.active.earned_xp["creature_gorgul_fire"] = 100
	check(Run.from_dict(bad).error != "", "registration XP must match chronological ledger")
	bad = run.state.duplicate(true)
	var registration: Dictionary = bad.ledger.pop_front()
	bad.ledger.append(registration)
	check(Run.from_dict(bad).error != "", "reward cannot precede registration")

func _test_draw_participation() -> void:
	var run := make_run()
	run.start_cup(run.starter_deck())
	while int(run.cup.next_match().a) != 0 and int(run.cup.next_match().b) != 0:
		play_next(run)
	var duel := run.cup.next_match()
	check(run.record_result(String(duel.id), -1, [1, 1], "fixture-draw", {}) == OK, "first unengaged draw accepted")
	check(run.last_reward.xp == 0 and run.last_reward.credits == 0, "first unengaged draw gives no XP or credits")
	finish(run, false)
	var found := false
	for attempt in range(4):
		check(run.replay_cup() == OK and run.start_cup(run.starter_deck()) == OK, "draw regression replay registration")
		while not run.cup.completed():
			duel = run.cup.next_match()
			var human := int(duel.a) == 0 or int(duel.b) == 0
			var key := "%d/%d" % [run.state.league, int(duel.b if int(duel.a) == 0 else duel.a)]
			var repeated := false
			for event in run.state.ledger:
				if event.type == "match" and event.encounter == key:
					repeated = true
			if human and repeated:
				var xp_before: Dictionary = run.state.owned_creatures.duplicate(true)
				check(run.record_result(String(duel.id), -1, [1, 1], "fixture-draw", {}) == OK, "repeat unengaged draw accepted")
				check(run.last_reward.xp == 0 and run.last_reward.credits == 0 and Cup._equivalent(xp_before, run.state.owned_creatures), "repeat unengaged draw cannot farm XP")
				var saved := run.state.duplicate(true)
				check(Run.from_dict(saved).error == "", "corrected draw reward roundtrip")
				check(run.record_result(String(duel.id), -1, [1, 1], "fixture-draw", {}) == OK and Cup._equivalent(saved, run.state), "repeat draw delivery never doubles XP")
				# Older local v1 saves retain their already granted six XP.
				var legacy := saved.duplicate(true)
				legacy.ledger[-1].xp = 6
				for id in legacy.ledger[-1].creatures:
					legacy.owned_creatures[id] += 6
				var restored := Run.from_dict(legacy)
				check(restored.error == "" and Cup._equivalent(restored.career.state, legacy), "historical v1 unengaged draw XP remains readable without duplication")
				var legacy_path := PATH + ".draw-legacy"
				DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
				check(restored.career.save_file(legacy_path) == OK, "historical draw save remains writable")
				var reloaded := Run.load_file(legacy_path)
				check(reloaded.error == "" and Cup._equivalent(legacy, reloaded.career.state), "historical draw disk roundtrip neither removes nor duplicates XP: " + String(reloaded.error))
				legacy.ledger[-1].xp = 12
				for id in legacy.ledger[-1].creatures:
					legacy.owned_creatures[id] += 6
				check(Run.from_dict(legacy).error != "", "legacy draw compatibility cannot grant arbitrary XP")
				found = true
				break
			play_next(run, false)
		if found:
			break
	check(found, "repeat encounter reached in bounded fixture cups")

func _test_economy_paths() -> void:
	var losing := make_run()
	losing.start_cup(losing.starter_deck())
	finish(losing, false)
	check(losing.state.credits == 295 and losing.can_advance(), "all-loss first cup: 100 start +45 participation +150 completion, next league unlocked")
	check(losing.advance_cup() == OK, "all-loss career can advance without buying a creature")
	var ids := Cup.deck_ids(losing.starter_deck())
	check(losing.deck_error(ids[0], ids[1], ids[2]).is_empty(), "free roster remains legal in second league after losses")
	var affordable_card := ""
	for id in CardDB.arena_ids() + CardDB.ability_ids():
		if not losing.state.owned_cards.has(String(id)) and losing.price(id) > 0 and losing.price(id) <= 295:
			affordable_card = String(id)
			break
	check(not affordable_card.is_empty() and losing.purchase(affordable_card) == OK, "all-loss path affords a permanent card upgrade before second league")
	var winning := make_run()
	winning.start_cup(winning.starter_deck())
	finish(winning)
	check(int(winning.state.credits) >= 655 and int(winning.state.credits) <= 700, "champion first cup funds one 650-credit intermediate creature even with repeat final opponent")
	check(winning.purchase("creature_ratnik_fire") == OK and winning.level("creature_ratnik_fire") == 1, "first championship permits exact intermediate purchase, new creature starts at level one")
	var mixed := make_run()
	mixed.start_cup(mixed.starter_deck())
	var human_match := 0
	while not mixed.cup.completed():
		var duel := mixed.cup.next_match()
		var human := int(duel.a) == 0 or int(duel.b) == 0
		play_next(mixed, human_match % 2 == 0)
		if human:
			human_match += 1
	check(mixed.state.credits >= 340 and mixed.can_advance(), "mixed win-loss cup funds upgrades and unlocks progression without a championship")
	check(Run.from_dict(winning.state).error == "" and Run.from_dict(losing.state).error == "" and Run.from_dict(mixed.state).error == "", "loss, mixed and champion economy ledgers remain canonical")

func _test_persistence() -> void:
	for suffix in ["", ".bak", ".tmp", ".blocked"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))
	var run := make_run()
	check(run.save_file(PATH) == OK, "initialsave")
	run.autosave_path = PATH
	check(run.start_cup(run.starter_deck()) == OK and FileAccess.file_exists(PATH + ".bak"), "transactional backup")
	var duel := run.cup.next_match()
	check(run.begin_match(String(duel.id)) == OK, "save beganmatch")
	var loaded := Run.load_file(PATH)
	check(loaded.error == "" and Cup._equivalent(run.state, loaded.career.state), "JSON roundtrip includingmarker")
	check(loaded.career.cup.next_match().seed == duel.seed, "resume same seed")
	var blocked := FileAccess.open(PATH + ".blocked", FileAccess.WRITE)
	blocked.store_string("{broken")
	blocked.close()
	var before := run.state.duplicate(true)
	var reference := run.cup
	run.autosave_path = PATH + ".blocked"
	check(run.record_result(String(duel.id), int(duel.a), [3, 0], "fixture", {"throws": 3}) != OK, "corrupt destination refuses transaction")
	check(Cup._equivalent(run.state, before) and run.cup == reference, "writefailure rollsbackandpreservescupreference")
	check(FileAccess.get_file_as_string(PATH + ".blocked") == "{broken", "corruptfile neveroverwritten")
	check(Run.create("fire", 1, 1, "Replacement", PATH) == null, "existingcareer neverreplaced")
