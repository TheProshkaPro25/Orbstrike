extends SceneTree
## CARD-10. Ограниченные парные серии: одна замена, те же команды/seed, обе стороны.
## Решения принимает настоящий ИИ через скрытый get_view; приземление точное, без графики.
const RED := ["fire_drain", "gale_swap", "light_crown", "stone_copy", "shadow_pact", "tide_hush"]
const WEAK := ["fire_spark", "gale_gust", "light_glint", "stone_firm", "shadow_haze", "tide_spray"]
const RETURNING := ["fire_last", "gale_vengeance", "light_dawn", "stone_wrath", "shadow_revenge", "tide_ninth"]
var failures := 0
var matches: Array = []

func verify(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func deck(element: int, gold: StringName = &"arena_altar", bronze: StringName = &"arena_funnel", blue: StringName = &"", green: StringName = &"ability_ratnik_oath", silver: StringName = &"arena_den_dragnar") -> DeckDef:
	var creatures: Array = []
	for species in ["dragnar", "ratnik", "levian"]:
		creatures.append(StringName("creature_%s_%s" % [species, GameData.ATTR_KEYS[element]]))
	var abilities: Array = [StringName("ability_" + RED[element]), StringName("ability_" + WEAK[element]) if blue == &"" else blue, green]
	var arenas: Array = [gold, silver, bronze]
	verify(CardDB.deck_error(creatures, arenas, abilities).is_empty(), "допустимая колода: " + CardDB.deck_error(creatures, arenas, abilities))
	return CardDB.build_deck(creatures, arenas, abilities)

func ids(d: DeckDef) -> Array:
	var out: Array = [[], [], []]
	for pair in [[d.creatures, 0], [d.arena, 1], [d.abilities, 2]]:
		for c in pair[0]: out[pair[1]].append(String(c.id))
	return out

func compare(group: String, sample: String, baseline: DeckDef, candidate: DeckDef, foe: DeckDef, target: StringName, alternate: StringName, seeds: Array) -> void:
	for seed_value in seeds:
		for side in [0, 1]:
			for variant in [0, 1]:
				var subject: DeckDef = baseline if variant == 0 else candidate
				var row := run_match(subject, foe, int(seed_value), side, target if variant == 0 else alternate, [target, alternate])
				row["group"] = group
				row["sample"] = sample
				row["variant"] = variant
				matches.append(row)
	print("CARD-10 ", group, "/", sample, ": ", seeds.size() * 4, " матчей, всего ", matches.size())

func run_match(subject: DeckDef, foe: DeckDef, seed_value: int, side: int, target: StringName, excluded: Array) -> Dictionary:
	var decks: Array = [subject, foe] if side == 0 else [foe, subject]
	var ctrl := MatchController.new(decks[0], decks[1], seed_value)
	ctrl.landing_window = true
	# Исключаем ОБЕ альтернативы только из добора исследуемой стороны, чтобы замена
	# стартовой карты не меняла размер/порядок её пула и другая версия не пришла позже.
	for pool in ctrl._draw_pools[side]:
		for id in excluded: pool.erase(id)
	var pool_hash := hash(ctrl._draw_pools)
	var ais: Array = []
	for player in [0, 1]:
		# Один seed привязан к роли команды, а не к номеру стороны.
		ais.append(AIPlayer.new(player, seed_value * 7 + (1 if player == side else 2), -1.0, AIPlayer.Difficulty.HARD))
	var m := {"seed": seed_value, "side": side, "target": String(target), "decks": [ids(subject), ids(foe)], "pool_hash": pool_hash,
		"steps": 0, "hand_windows": 0, "legal_windows": 0, "plays": 0, "attached": 0, "placed": 0, "open_opportunities": 0, "opened": 0,
		"battles": 0, "active_battles": 0, "cancelled": 0, "local_outcome_changes": 0, "returned_target": 0, "returned_other": 0,
		"natural_recharged_target": 0, "reused": 0, "opponent_cards_muted": 0, "block_battles": 0,
		"recall_remaining": [], "last_creature_returns": 0, "early_returns": 0, "gate_battle_roles": [0, 0], "seen_cards": {}, "played_cards": {},
		"events": [], "snapshot": null, "battle_traces": []}
	ctrl.card_drawn.connect(func(p: int, id: StringName) -> void:
		if p == side: m.seen_cards[String(id)] = int(m.seen_cards.get(String(id), 0)) + 1)
	ctrl.arena_card_placed.connect(func(p: int, slot: int) -> void:
		if p == side and ctrl.state.slots[slot].card_id == target: m.placed += 1)
	ctrl.card_revealed.connect(func(slot: int, id: StringName) -> void:
		if id == target and (ctrl.state.slots[slot].card_owner == side or (m.snapshot != null and m.snapshot.slots[slot].card_owner == side)): m.opened += 1)
	ctrl.ability_played.connect(func(p: int, id: StringName) -> void:
		if p == side:
			m.played_cards[String(id)] = int(m.played_cards.get(String(id), 0)) + 1
			if id == target:
				m.plays += 1
				if m.plays + m.attached > 1: m.reused += 1)
	ctrl.ability_attached.connect(func(p: int, _u: int, id: StringName) -> void:
		if p == side:
			m.played_cards[String(id)] = int(m.played_cards.get(String(id), 0)) + 1
			if id == target:
				m.attached += 1
				if m.plays + m.attached > 1: m.reused += 1)
	ctrl.abilities_recalled.connect(func(p: int, cards: Array) -> void:
		if p != side: return
		if cards.has(target):
			m.returned_target += 1
			if ctrl.state.alive_count(side) > 1: m.early_returns += 1
			else: m.last_creature_returns += 1
		# Сначала контроллер возвращает карты именно через recall, затем пассивные returns.
		for id in cards:
			if m.recall_remaining.has(id):
				m.returned_other += 1
				m.recall_remaining.erase(id))
	ctrl.abilities_recharged.connect(func(p: int, cards: Array) -> void:
		if p == side and cards.has(target): m.natural_recharged_target += 1)
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: record_battle(ctrl, m, r, side, target))
	ctrl.start()
	var pending := -1
	while ctrl.get_phase() != MatchController.Phase.GAME_OVER and m.steps < 3000:
		m.steps += 1
		var p := ctrl.get_active_player()
		var err := OK
		m.snapshot = ctrl.state.duplicate_full()
		match ctrl.get_phase():
			MatchController.Phase.SETUP:
				var ch: Dictionary = ais[p].choose_setup(ctrl.get_view(p), ctrl.legal_setup_slots(), ctrl.can_skip_gate())
				if ch.is_empty(): err = ctrl.skip_gate(p)
				elif ch.has("throw_uid"):
					pending = int(ch.slot)
					err = ctrl.throw_with_gate(p, ch.card_id, ch.slot, ch.throw_uid)
				else: err = ctrl.place_arena_card(p, ch.card_id, ch.slot)
			MatchController.Phase.AWAIT_THROW:
				var ch: Dictionary = ais[p].choose_throw(ctrl.get_view(p))
				pending = int(ch.target_slot)
				err = ctrl.select_creature(p, ch.uid)
			MatchController.Phase.AWAIT_LANDING:
				ctrl.report_landing(ctrl.get_selected_uid(), pending)
			MatchController.Phase.AFTER_LANDING, MatchController.Phase.ABILITY_WINDOW:
				var legal := ctrl.legal_abilities(p)
				if p == side and ctrl.state.players[p].ability_hand.has(target):
					m.hand_windows += 1
					if legal.has(target): m.legal_windows += 1
				if ctrl.get_phase() == MatchController.Phase.AFTER_LANDING:
					var pick: StringName = ais[p].choose_attach(ctrl.get_view(p), ctrl.get_landed_uid(), legal)
					err = ctrl.pass_ability(p) if pick == &"" else ctrl.play_ability(p, pick)
				else:
					if ctrl.can_reveal_gate(p):
						if p == side and ctrl.state.slots[ctrl._b_slot].card_id == target: m.open_opportunities += 1
						if ais[p].should_open_gate(ctrl.get_view(p), ctrl.get_battle_preview()):
							err = ctrl.reveal_gate(p)
							verify(err == OK, "открытие ворот")
							continue
					var pick: StringName = ais[p].choose_ability(ctrl.get_view(p), ctrl.get_battle_preview(), legal)
					err = ctrl.pass_ability(p) if pick == &"" else ctrl.play_ability(p, pick)
		verify(err == OK, "действие seed=%d step=%d err=%d" % [seed_value, m.steps, err])
		if err != OK: break
	verify(ctrl.get_phase() == MatchController.Phase.GAME_OVER, "матч завершён seed=%d" % seed_value)
	m["finished"] = ctrl.get_phase() == MatchController.Phase.GAME_OVER
	m["win"] = 1 if ctrl.winner == side else (0 if ctrl.winner >= 0 else -1)
	m["reason"] = String(ctrl.game_over_reason)
	m["turns"] = ctrl.get_turn()
	m["trace_hash"] = hash(ctrl.action_trace)
	m["actions"] = ctrl.action_trace.duplicate(true)
	m.erase("snapshot")
	m.erase("recall_remaining")
	# RefCounted-контроллер не должен удерживаться собственными замыканиями сигналов.
	for signal_info in ctrl.get_signal_list():
		for connection in ctrl.get_signal_connection_list(signal_info.name):
			ctrl.disconnect(signal_info.name, connection.callable)
	return m

func record_battle(ctrl: MatchController, m: Dictionary, r: BattleResult, player: int, target: StringName) -> void:
	m.battles += 1
	m.recall_remaining = []
	var snapshot: MatchState = m.snapshot
	var side: int = 0 if snapshot.creatures[r.attacker_uid].owner == player else 1
	var ability_active := false
	for play in r.plays:
		if int(play[0]) == side and StringName(play[1]) == target:
			if r.cancelled_plays.has(play): m.cancelled += 1
			else: ability_active = true
	if r.recall[side] == target:
		for play in r.plays:
			if int(play[0]) == side and StringName(play[1]) != target:
				m.recall_remaining.append(StringName(play[1]))
	var gate_active: bool = r.arena_card_id == target and r.gate_owner_side == side and not r.arena_cancelled
	if ability_active or gate_active:
		m.active_battles += 1
		if gate_active: m.gate_battle_roles[side] += 1
		var without := snapshot.duplicate_full()
		# Только локальный пересчёт той же последовательности, не контрфактический матч.
		without.slots[r.slot].card_id = r.arena_card_id
		without.slots[r.slot].revealed = r.arena_card_id != &""
		without.slots[r.slot].card_owner = snapshot.creatures[r.attacker_uid if r.gate_owner_side == 0 else r.defender_uid].owner
		if gate_active: without.slots[r.slot].card_id = &""
		for uid in [r.attacker_uid, r.defender_uid]:
			if without.creatures[uid].owner == player:
				without.creatures[uid].attached = without.creatures[uid].attached.filter(func(a: Array) -> bool: return StringName(a[1]) != target)
		var bp := r.battle_plays.filter(func(a: Array) -> bool: return not (int(a[0]) == side and StringName(a[1]) == target))
		var cf := PowerCalc.compute_seq(without, r.attacker_uid, r.defender_uid, r.slot, bp)
		if cf.winner_uid != r.winner_uid or cf.interrupted != r.interrupted or cf.both_lose != r.both_lose: m.local_outcome_changes += 1
		m.battle_traces.append({"plays": r.plays, "powers": r.powers, "winner": r.winner_uid, "without_target_powers": cf.powers, "without_target_winner": cf.winner_uid, "gate": String(r.arena_card_id)})
	if (gate_active and r.gate_effect == &"mute") or (ability_active and CardEffects.is_effect(CardDB.card(target), &"silence")):
		m.block_battles += 1
		for cancelled in r.cancelled_plays:
			if int(cancelled[0]) != side: m.opponent_cards_muted += 1

func _initialize() -> void:
	CardDB.load_all()
	# 24 матча: поле против Алтаря на всех стихиях.
	for el in 6:
		var field := StringName("arena_field_" + GameData.ATTR_KEYS[el])
		compare("field_altar", GameData.ATTR_KEYS[el], deck(el, field), deck(el), deck((el + 3) % 6), field, &"arena_altar", [101 + el])
	# 24 матча: слабое неусловное усиление против возвращаемого условного в том же синем слоте.
	for el in 6:
		var weak := StringName("ability_" + WEAK[el])
		var comeback := StringName("ability_" + RETURNING[el])
		compare("boost_return", GameData.ATTR_KEYS[el], deck(el), deck(el, &"arena_altar", &"arena_funnel", comeback), deck((el + 2) % 6), weak, comeback, [201 + el])
	# 16 матчей: Трон с единственной Тенью, двумя Тенями и без Тени.
	for pair in [[4, 2], [4, 4], [2, 4], [2, 0]]:
		compare("throne", "%d-%d" % pair, deck(pair[0]), deck(pair[0], &"arena_altar", &"arena_dusk_throne"), deck(pair[1]), &"arena_funnel", &"arena_dusk_throne", [301 + pair[0] * 6 + pair[1]])
	# По 16: блокировка, возврат текущего боя. Два состава против разных стихий, два seed.
	for el in [0, 5]:
		compare("mute", GameData.ATTR_KEYS[el], deck(el), deck(el, &"arena_altar", &"arena_mute"), deck((el + 2) % 6), &"arena_funnel", &"arena_mute", [401, 419])
		compare("recall", GameData.ATTR_KEYS[el], deck(el), deck(el, &"arena_altar", &"arena_funnel", &"", &"ability_ratnik_rearm"), deck((el + 4) % 6), &"ability_ratnik_oath", &"ability_ratnik_rearm", [503, 521])
	# 8: виды ворот в отдельном серебряном слоте при том же золотом Алтаре.
	for el in [1, 3]:
		compare("species_gate", GameData.ATTR_KEYS[el], deck(el), deck(el, &"arena_altar", &"arena_funnel", &"", &"ability_ratnik_oath", &"arena_den_levian"), deck((el + 1) % 6), &"arena_den_dragnar", &"arena_den_levian", [601 + el])
	# Варианты имеют одинаковый начальный пул добора, одинаковые команды и только одну замену.
	for i in range(0, matches.size(), 2):
		verify(matches[i].pool_hash == matches[i + 1].pool_hash, "одинаковый добор пары")
	var report := {"method": "104 парных матча HARD/HARD, ANIME_INSPIRED, точные приземления; одна замена; одинаковый seed и обе стороны. Обе альтернативы исключены из добора только исследуемой стороны.",
		"failures": failures, "matches": matches, "limits": "Малая целевая выборка, не общий винрейт каталога. Локальный пересчёт исхода не моделирует иной ответ ИИ. Физика, редкая встреча и слабые сложности не оцениваются."}
	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else "user://card-balance-matches.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	verify(f != null, "отчёт записывается")
	if f != null:
		f.store_string(JSON.stringify(report, "\t") + "\n")
		f.close()
	print("CARD-10: ", matches.size(), " матчей, ошибок ", failures)
	quit(1 if failures else 0)
