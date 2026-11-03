class_name TournamentNpcSimulator
extends RefCounted
## Ограниченная детерминированная симуляция теми же правилами и ИИ. Бросок попадает
## точно в выбранные ворота: это явное приближение без физики, не случайный исход.
const STEP_LIMIT := 4096

static func simulate(deck_a: DeckDef, deck_b: DeckDef, match_seed: int, first_player: int, difficulty: int, step_limit: int = STEP_LIMIT, personalities: Array = []) -> Dictionary:
	if deck_a == null or deck_b == null or not [0, 1].has(first_player) or difficulty < 0 or difficulty > 2:
		return {"error": "Некорректные параметры симуляции NPC"}
	for deck in [deck_a, deck_b]:
		var ids: Array = [[], [], []]
		for pair in [[deck.creatures, 0], [deck.arena, 1], [deck.abilities, 2]]:
			for definition in pair[0]:
				if definition == null:
					return {"error": "Некорректная колода NPC"}
				ids[pair[1]].append(String(definition.id))
		if not CardDB.deck_error(ids[0], ids[1], ids[2]).is_empty():
			return {"error": "Колода NPC не соответствует правилам"}
	var ctrl := MatchController.new(deck_a, deck_b, match_seed)
	ctrl.landing_window = true
	var bots: Array = [AIPlayer.new(0, match_seed ^ 0x157a, 0.0, difficulty), AIPlayer.new(1, match_seed ^ 0x3a61, 0.0, difficulty)]
	for side in range(mini(personalities.size(), 2)):
		if personalities[side] is Dictionary:
			bots[side].configure_personality(personalities[side])
	ctrl.start(first_player)
	var pending_uid := -1
	var pending_slot := -1
	var steps := 0
	while ctrl.get_phase() != MatchController.Phase.GAME_OVER:
		steps += 1
		if steps > step_limit:
			return {"error": "Симуляция NPC превысила предел действий", "seed": match_seed, "steps": steps}
		var p: int = ctrl.get_active_player()
		var bot: AIPlayer = bots[p]
		var code: Error = OK
		match ctrl.get_phase():
			MatchController.Phase.SETUP:
				var choice: Dictionary = bot.choose_setup(ctrl.get_view(p), ctrl.legal_setup_slots(), ctrl.can_skip_gate())
				if choice.is_empty():
					code = ctrl.skip_gate(p)
				elif choice.has("throw_uid"):
					pending_uid = int(choice.throw_uid)
					pending_slot = int(choice.slot)
					code = ctrl.throw_with_gate(p, choice.card_id, pending_slot, pending_uid)
				else:
					code = ctrl.place_arena_card(p, choice.card_id, int(choice.slot))
			MatchController.Phase.AWAIT_THROW:
				var choice: Dictionary = bot.choose_throw(ctrl.get_view(p))
				pending_uid = int(choice.uid)
				pending_slot = int(choice.target_slot)
				code = ctrl.select_creature(p, pending_uid)
			MatchController.Phase.AWAIT_LANDING:
				if pending_uid != ctrl.get_selected_uid() or pending_slot < 0 or pending_slot >= ctrl.state.slots.size() or not ctrl.state.slots[pending_slot].has_card:
					return {"error": "NPC выбрал недопустимую цель броска", "seed": match_seed, "steps": steps}
				ctrl.report_landing(pending_uid, pending_slot)
			MatchController.Phase.AFTER_LANDING:
				var pick := bot.choose_attach(ctrl.get_view(p), ctrl.get_landed_uid(), ctrl.legal_abilities(p))
				code = ctrl.pass_ability(p) if pick == &"" else ctrl.play_ability(p, pick)
			MatchController.Phase.ABILITY_WINDOW:
				if ctrl.can_reveal_gate(p) and bot.should_open_gate(ctrl.get_view(p), ctrl.get_battle_preview()):
					code = ctrl.reveal_gate(p)
				else:
					var pick := bot.choose_ability(ctrl.get_view(p), ctrl.get_battle_preview(), ctrl.legal_abilities(p))
					code = ctrl.pass_ability(p) if pick == &"" else ctrl.play_ability(p, pick)
			_:
				return {"error": "Неожиданная фаза симуляции NPC", "seed": match_seed, "steps": steps}
		if code != OK:
			return {"error": "Действие NPC отклонено: %d" % code, "seed": match_seed, "steps": steps}
	return {"error": "", "winner": ctrl.winner, "alive": [ctrl.state.alive_count(0), ctrl.state.alive_count(1)], "reason": String(ctrl.game_over_reason), "steps": steps, "trace": ctrl.debug_snapshot()}
