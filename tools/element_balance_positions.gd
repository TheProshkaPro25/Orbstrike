extends "res://tests/cards033_tests.gd"
## Only the two cards not exercised by the matched series. No new match grid.

func _initialize() -> void:
	Engine.max_fps = 60
	AudioServer.set_bus_mute(0, true)
	CardDB.load_all()
	_add_test_creatures()
	_test_wash033()
	_test_wash_special033()
	_test_valor033()
	for player in 2:
		for margin in [30, 50, 51]:
			var ctrl := _c033(player, 0, [PLUS], false, VALOR)
			var uid := player * 3
			for other in ctrl.state.players[player].creature_uids:
				if other != uid: ctrl.state.creatures[other].alive = false
			ctrl.state.creatures[uid].marks = [{"delta": -margin}]
			var ai := AIPlayer.new(player, 18401, -1.0, AIPlayer.Difficulty.HARD)
			var preview := ctrl.get_battle_preview()
			var view := ctrl.get_view(player)
			var opened := PowerCalc.preview_open_gate(view, preview.slot)
			var after := PowerCalc.compute_seq(opened, preview.attacker_uid, preview.defender_uid, preview.slot, preview.battle_plays)
			var should := ai.should_open_gate(view, preview)
			_check(should == (margin <= 50), "HARD last-creature Valor decision margin=%d player=%d" % [margin, player])
			_check(ai._alive_after(view, after, player) == (1 if margin <= 50 else 0), "last-creature survival forecast")
			var returned: Array = []
			ctrl.creature_returned.connect(func(u: int, reason: StringName) -> void: returned.append([u, String(reason)]))
			if should: _check(ctrl.reveal_gate(player) == OK, "HARD opens Valor")
			for ps in ctrl.state.players: ps.ability_hand.clear()
			_pass_windows(ctrl)
			_check(ctrl.state.creatures[uid].alive == (margin <= 50), "actual last-creature survival")
			_check((ctrl.get_phase() == MatchController.Phase.GAME_OVER) == (margin > 50), "Valor retains match for last creature")
			_check(returned.has([uid, "valor"]) == (margin <= 50), "actual Valor return signal")
			observations033.append({"case": "last_valor", "player": player, "margin": margin, "should_open": should, "saved_uid": after.valor_saved_uid, "actual_alive": ctrl.state.creatures[uid].alive, "actual_returned": returned, "phase": ctrl.get_phase(), "winner": ctrl.winner})
		var wash := _c033(player, 5, [WASH], false)
		# Restore 170->320 against 300; both attacker/defender now win, with no hidden reply.
		wash.state.creatures[(1 - player) * 3].marks = [{"delta": -20}]
		wash.state.players[1 - player].ability_hand.clear()
		var bot := AIPlayer.new(player, 18457, -1.0, AIPlayer.Difficulty.HARD)
		var before := wash.get_battle_preview()
		var pick := bot.choose_ability(wash.get_view(player), before, wash.legal_abilities(player))
		_check(pick == WASH, "HARD uses Wash for actual winning restoration")
		_p033(wash, player, pick)
		var restored := wash.get_battle_preview()
		_check(restored.powers[player] == 320 and restored.winner_uid == player * 3, "Wash restores base and changes winner")
		_pass_windows(wash)
		_check(wash.state.creatures[player * 3].alive and not wash.state.creatures[(1 - player) * 3].alive, "Wash actual resolution")
		observations033.append({"case": "wash_ai", "player": player, "before": before.powers, "after": restored.powers, "pick": String(pick), "winner_uid": restored.winner_uid, "actual_foe_alive": wash.state.creatures[(1 - player) * 3].alive})
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var f := FileAccess.open(args[0], FileAccess.WRITE)
		if f != null: f.store_string(JSON.stringify({"assertions": _checks, "failures": _failures, "observations": observations033, "scope": "Narrow fresh Wash/Valor positions, boundary/cancellation/late penalties/mirror and last-creature HARD decisions; production controller outcomes. Synthetic battle fixtures, no match-rate claim."}, "\t") + "\n")
	print("ELEMENT positions: %d assertions, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)
