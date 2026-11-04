extends SceneTree
## Actual opening commands, replay and isolated scheduler/RNG invariants.
var checks := 0
var failures: Array = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func opening(seed_value: int, first: int) -> MatchController:
	var ctrl := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(0), seed_value)
	ctrl.start(first)
	for step in 6:
		var p := ctrl.get_active_player()
		check(ctrl.get_phase() == MatchController.Phase.SETUP, "actual opening setup")
		var slot: int = ctrl.legal_setup_slots()[0]
		var uid: int = -1
		for candidate in ctrl.state.players[p].creature_uids:
			if ctrl.state.creatures[candidate].slot < 0:
				uid = candidate
				break
		check(ctrl.throw_with_gate(p, ctrl.state.players[p].arena_hand[0], slot, uid) == OK, "legal opening throw")
		ctrl.report_landing(uid, slot)
	return ctrl

func synthetic(seed_value: int, rules: int = MatchRules.Ruleset.ANIME_INSPIRED) -> MatchController:
	var ctrl := MatchController.new(CardDB.preset_deck(0), CardDB.preset_deck(0), seed_value, rules)
	ctrl.state.turn = 8
	ctrl._turn_player = 0
	for uid in 6:
		var c: CreatureState = ctrl.state.creatures[uid]
		c.slot = uid
		var s := ctrl.state.slots[uid]
		s.has_card = true
		s.card_owner = c.owner
		s.card_id = &"arena_field_fire"
		s.occupant_uid = uid
	return ctrl

func _initialize() -> void:
	Engine.max_fps = 60
	AudioServer.set_bus_mute(0, true)
	CardDB.load_all()
	var attackers: Array[int] = [0, 0]
	for seed_value in range(410, 426):
		var a := opening(seed_value, 0)
		var b := opening(seed_value, 1)
		var owner: int = a.state.creatures[a._b_atk].owner
		attackers[owner] += 1
		check(b.state.creatures[b._b_atk].owner == owner, "first mover does not select the lottery side")
		check(a.get_active_player() == owner, "actual attacker gets the first answer")
		check(a.can_reveal_gate(1 - owner) == false, "defender waits for own answer")
		check(a.get_battle_preview().arena_card_id == &"", "closed enemy gate remains hidden")
		var restored := MatchReplay.restore(a.debug_snapshot())
		check(restored.error.is_empty(), "opening replay accepted")
		if restored.error.is_empty():
			var replay: MatchController = restored.controller
			check(replay.event_log == a.event_log and replay._b_atk == a._b_atk, "saved commands replay identical lottery/events")
		var isolated := synthetic(seed_value)
		var rng_before: int = isolated._rng.state
		var turn_before := isolated.get_turn()
		isolated._standoff(0)
		check(isolated._rng.state == rng_before, "lottery never consumes draw RNG")
		check(isolated.get_turn() == turn_before and isolated._turn_player == 0, "forced battle preserves skipped-turn scheduler")
		var atk_owner: int = isolated.state.creatures[isolated._b_atk].owner
		check(isolated.get_active_player() == atk_owner, "synthetic attacker answers first")
		check(not isolated.can_reveal_gate(1-atk_owner), "gate owner cannot reveal in the other answer")
		check(isolated.pass_ability(atk_owner) == OK, "attacker can pass")
		check(isolated.can_reveal_gate(1-atk_owner), "gate owner can reveal in own answer")
		check(isolated.reveal_gate(1-atk_owner) == OK, "gate opens legally")
	check(attackers[0] > 0 and attackers[1] > 0, "both lottery outcomes occur across fixed seeds")
	var legacy := synthetic(410, MatchRules.Ruleset.LEGACY)
	legacy._standoff(1)
	check(legacy.state.creatures[legacy._b_atk].owner == 1, "legacy scheduled attacker unchanged")
	var path := "build/checks/element-balance-20261104/standoff-invariants.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failures": failures, "fixed_seed_attackers": attackers}, "\t"))
	print("STANDOFF LOTTERY: ", checks, " checks, ", failures.size(), " failures; attackers ", attackers)
	quit(1 if not failures.is_empty() else 0)
