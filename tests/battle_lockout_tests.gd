extends "res://tests/card_revision_tests.gd"
## Reported 370:510 position and early own lockout; no balance series.
const BITE := &"ability_klykar_bite"
const HUNT := &"ability_klykar_hunt"
const BOOST := &"ability_shadow_strike"

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	_add_test_creatures()
	_lockout_positions()
	print("BATTLE LOCKOUT: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)

func reported_position(two_cards: bool = true) -> MatchController:
	var c := _ctrl([&"creature_kolossar_shadow", LU, GR], [BOOST, RESET, &"ability_shadow_haze"], [&"creature_klykar_shadow", SU, MA], [BITE, HUNT, &"ability_shadow_haze"], 430)
	c.state.ruleset = MatchRules.Ruleset.ANIME_INSPIRED
	_set_card(c, 1, &"arena_den_klykar", 1)
	_stand(c, 3, 1)
	_throw(c, 0, 0, 1)
	_check(c.get_battle_preview().powers == [370,620], "reported creature and gate bases")
	_check(c.play_ability(0, BOOST) == OK if two_cards else c.pass_ability(0) == OK, "initial response")
	_check(c.play_ability(1, BITE) == OK, "bite before reset")
	return c

func _lockout_positions() -> void:
	for two_cards in [false, true]:
		var c := reported_position(two_cards)
		var results: Array = []
		c.battle_resolved.connect(func(r: BattleResult) -> void: results.append(r))
		_check(c.play_ability(0, RESET) == OK, "reset accepted")
		var r := c.get_battle_preview()
		_check(r.powers == [370,310], "reset removes bite and den bonus")
		_check(r.ability_count(0) == (2 if two_cards else 1), "lockout occurs below cap")
		_check(MatchController.battle_ability_block_reason(r,0).contains("Великий сброс"), "named reset reason")
		_check(c.legal_abilities(0).is_empty() and c.get_active_player() == 1, "opponent still gets response")
		_check(c.play_ability(1,HUNT) == OK, "hunt after reset accepted")
		r = c.get_battle_preview()
		_check(r.powers == [370,510] and r.passed[0], "370:510 and own automatic pass")
		_check(c.abilities_left(0) == (1 if two_cards else 2), "unused capacity is not legal action")
		_check(c.pass_ability(1) == OK and results.size() == 1, "opponent pass resolves")
		_check(results[0].powers == [370,510] and results[0].winner_uid == 3, "actual controller result")
		_check(MatchController.battle_ability_block_reason(results[0],0).contains("Великий сброс"), "past result keeps reason")
	for side in [0,1]:
		var s := _anime()
		for id in [RESET,COIL]:
			var r := _seq(s, [[side,id]])
			_check(not MatchController.battle_ability_block_reason(r,side).is_empty(), "own lockout both sides")
			_check(MatchController.battle_ability_block_reason(r,1-side).is_empty(), "other side not locked")
		var cancelled := _seq(s, [[side,COIL],[1-side,BITE]])
		_check(not PowerCalc.side_locked(cancelled,side) and MatchController.battle_ability_block_reason(cancelled,side).is_empty(), "cancelled coil unlocks")
		var copied := _seq(s, [[1-side,RESET],[side,COPY]])
		_check(MatchController.battle_ability_block_reason(copied,side).contains("скопированный"), "copied price named")
		var cancelled_copy := _seq(s, [[1-side,RESET],[side,COPY],[1-side,BITE]])
		_check(MatchController.battle_ability_block_reason(cancelled_copy,side).is_empty(), "cancelled copy unlocks")
		var limit := _seq(s, [])
		limit.ability_counts[side] = 3
		_check(MatchController.battle_ability_block_reason(limit,side).contains("Лимит"), "spent cap survives fighter replacement")
		var sealed := _anime(ZH,VI,&"arena_mute")
		sealed.slots[0].card_owner = 1-side
		var muted := _seq(sealed, [[side,RESET]])
		_check(not PowerCalc.side_locked(muted,side) and MatchController.battle_ability_block_reason(muted,side).is_empty(), "suppressed reset has no own lockout")
	# Existing narrow regressions prove legal third card, reversible lockout and gate access.
	_test_exchange()
	_test_silence_and_lockout()
	_check(MatchController.ability_play_warning(RESET).contains("меньше трёх"), "preplay warning explains cap")
	_check(MatchController.ability_play_warning(COPY).begins_with("Если"), "copy warning conditional")
	_check(MatchController.ability_play_warning(BOOST).is_empty(), "ordinary boost has no false warning")
