extends "res://tools/card_balance_matches.gd"
## Preregistered 400 targeted matches, real controller signals, mirrored seed pairs.
## No physical landing: HARD only sees get_view. All card numbers stay authoritative.
const PREREG := {"matches": 400, "score": "win1/draw0.5/loss0", "bootstrap_repeats": 10000, "bootstrap_seed": 11703, "cluster": "composition,seed; preserve both sides", "change_signal": "paired_abs_delta>=0.20 AND 95%CI lower>0.05 in same direction AND >=75% compositions positive AND >=20 active target battles", "stopping": "exact fixed grid or first controller/cooldown/pairing error; no expansion for significance", "hypotheses": ["gold role tradeoff", "species specialization and mirror symmetry", "mute strong but no universal dominance", "conditional return compensates disadvantage", "rescue actual revival with two-battle passive cooldown"]}
class RescuePolicy extends AIPlayer:
	var enabled := true
	func _choose_revival(view: MatchState, preview: BattleResult, cards: Array[StringName], side: int) -> StringName:
		return super._choose_revival(view, preview, cards, side) if enabled else &""

var rescue_enabled := true
var subject_side := 0

func make_ai(player: int, rng_seed: int) -> AIPlayer:
	var ai := RescuePolicy.new(player, rng_seed, -1.0, AIPlayer.Difficulty.HARD)
	ai.enabled = rescue_enabled if player == subject_side else true
	return ai

func species_deck(index: int, element: int, gate: StringName) -> DeckDef:
	var species: String = GameData.SPECIES[index].id
	var names: Array = [species]
	for companion in ["gorgul", "klykar", "grifalon"]:
		if names.size() < 3 and not names.has(companion): names.append(companion)
	var creatures: Array = []
	for name in names: creatures.append(StringName("creature_%s_%s" % [name, GameData.ATTR_KEYS[element]]))
	var green: String = ["dragnar_rush", "klykar_bite", "grifalon_dive", "kolossar_wall", "rogozhuk_shell", "levian_coil", "ratnik_oath", "gorgul_gaze"][index]
	var arenas: Array = [&"arena_altar", gate, &"arena_funnel"]
	var abilities: Array = [StringName("ability_" + RED[element]), StringName("ability_" + WEAK[element]), StringName("ability_" + green)]
	verify(CardDB.deck_error(creatures, arenas, abilities).is_empty(), "легальная видовая команда: " + CardDB.deck_error(creatures, arenas, abilities))
	return CardDB.build_deck(creatures, arenas, abilities)

func series(group: String, sample: String, a: DeckDef, b: DeckDef, foe: DeckDef, target_a: StringName, target_b: StringName, seeds: Array, policy: bool = false) -> void:
	if failures: return # Global fail-fast: later groups cannot start more matches.
	for seed_value in seeds:
		for side in [0, 1]:
			var pool_hash := 0
			for variant in [0, 1]:
				subject_side = side
				rescue_enabled = not policy or variant == 1
				var row := run_match(a if variant == 0 else b, foe, seed_value, side, target_a if variant == 0 else target_b, [target_a, target_b])
				if variant == 0: pool_hash = int(row.pool_hash)
				else: verify(int(row.pool_hash) == pool_hash, "парный добор совпадает")
				row["group"] = group
				row["sample"] = sample
				row["variant"] = variant
				matches.append(row)
				if failures: return
	print(group, "/", sample, ": total=", matches.size(), " failures=", failures)

func run_match(subject: DeckDef, foe: DeckDef, seed_value: int, side: int, target: StringName, excluded: Array) -> Dictionary:
	verify(CardDB.deck_error(ids(subject)[0], ids(subject)[1], ids(subject)[2]).is_empty(), "subject deck valid after mutation")
	verify(CardDB.deck_error(ids(foe)[0], ids(foe)[1], ids(foe)[2]).is_empty(), "foe deck valid after mutation")
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
		ais.append(make_ai(player, seed_value * 7 + (1 if player == side else 2)))
	var m := {"seed": seed_value, "side": side, "target": String(target), "decks": [ids(subject), ids(foe)], "pool_hash": pool_hash,
		"steps": 0, "hand_windows": 0, "legal_windows": 0, "plays": 0, "attached": 0, "placed": 0, "open_opportunities": 0, "opened": 0,
		"battles": 0, "active_battles": 0, "cancelled": 0, "local_outcome_changes": 0, "returned_target": 0, "returned_other": 0,
		"natural_recharged_target": 0, "reused": 0, "opponent_cards_muted": 0, "block_battles": 0,
		"recall_remaining": [], "last_creature_returns": 0, "early_returns": 0, "gate_battle_roles": [0, 0], "seen_cards": {}, "played_cards": {},
		"events": [], "snapshot": null, "battle_traces": [],
        "actual_revived": 0, "target_revived": 0, "eliminated": 0, "late_opened": 0,
        "last_target_battle": -100, "rescue_cooldown_gaps": [], "final_alive": [], "last_result": null}
	ctrl.creature_revived.connect(func(uid: int) -> void:
		if ctrl.state.creatures[uid].owner != side: return
		m.actual_revived += 1
		var result: BattleResult = m.last_result
		if result != null and CardDB.card(target).effect_id in [&"revive", &"copy"]:
			var owner_side := 0 if ctrl.state.creatures[result.attacker_uid].owner == side else 1
			if result.revive[owner_side]:
				for play in result.plays:
					if int(play[0]) == owner_side and StringName(play[1]) == target and not result.cancelled_plays.has(play):
						m.target_revived += 1
		m.events.append({"event": "revived", "battle": m.battles, "uid": uid, "phase": ctrl.state.phase, "source": "ability_resolution" if m.last_result != null else "gate_reveal"}))
	ctrl.creature_eliminated.connect(func(uid: int) -> void:
		if ctrl.state.creatures[uid].owner == side: m.eliminated += 1)
	ctrl.card_drawn.connect(func(p: int, id: StringName) -> void:
		if p == side: m.seen_cards[String(id)] = int(m.seen_cards.get(String(id), 0)) + 1)
	ctrl.arena_card_placed.connect(func(p: int, slot: int) -> void:
		if p == side and ctrl.state.slots[slot].card_id == target: m.placed += 1)
	ctrl.card_revealed.connect(func(slot: int, id: StringName) -> void:
		m.last_result = null # Queued card reveal identifies any subsequent gate revival.
		if id == target and (ctrl.state.slots[slot].card_owner == side or (m.snapshot != null and m.snapshot.slots[slot].card_owner == side)):
			m.opened += 1
			var foe_side := 0 if ctrl.state.creatures[ctrl._b_atk].owner != side else 1
			for play in ctrl._b_plays:
				if int(play[0]) == foe_side:
					m.late_opened += 1
					break)
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
		if p == side and cards.has(target):
			m.natural_recharged_target += 1
			if CardDB.card(target).effect_id in [&"revive", &"copy"]:
				var gap: int = m.battles - m.last_target_battle
				m.rescue_cooldown_gaps.append(gap)
				verify(gap >= 2, "реальный отдых спасения минимум два последующих боя"))
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: record_battle(ctrl, m, r, side, target))
	ctrl.start()
	var pending := -1
	while ctrl.get_phase() != MatchController.Phase.GAME_OVER and m.steps < 3000 and failures == 0:
		m.steps += 1
		var p := ctrl.get_active_player()
		var err := OK
		m.snapshot = ctrl.state.duplicate_full()
		m.last_result = null # Signals flush after command: attribute by event order, never phase.
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
					var ability_target: Dictionary = {} if pick == &"" else ais[p].choose_ability_target(ctrl.get_view(p), ctrl.get_battle_preview(), pick, ctrl.legal_ability_targets(p, pick))
					err = ctrl.pass_ability(p) if pick == &"" else ctrl.play_ability(p, pick, ability_target)
		verify(err == OK, "действие seed=%d step=%d err=%d" % [seed_value, m.steps, err])
		if err != OK: break
	verify(ctrl.get_phase() == MatchController.Phase.GAME_OVER, "матч завершён seed=%d" % seed_value)
	m["finished"] = ctrl.get_phase() == MatchController.Phase.GAME_OVER
	m["win"] = 1 if ctrl.winner == side else (0 if ctrl.winner >= 0 else -1)
	m["reason"] = String(ctrl.game_over_reason)
	m["turns"] = ctrl.get_turn()
	m["final_alive"] = [ctrl.state.alive_count(side), ctrl.state.alive_count(1 - side)]
	verify(ctrl.get_turn() < MatchController.MAX_TURNS, "целевой матч не достиг лимита60")
	m["trace_hash"] = hash(ctrl.action_trace)
	m["actions"] = ctrl.action_trace.duplicate(true)
	m.erase("snapshot")
	m.erase("last_result")
	m.erase("recall_remaining")
	# RefCounted-контроллер не должен удерживаться собственными замыканиями сигналов.
	for signal_info in ctrl.get_signal_list():
		for connection in ctrl.get_signal_connection_list(signal_info.name):
			ctrl.disconnect(signal_info.name, connection.callable)
	return m

func record_battle(ctrl: MatchController, m: Dictionary, r: BattleResult, player: int, target: StringName) -> void:
	m.battles += 1
	m.last_result = r
	m.recall_remaining = []
	var snapshot: MatchState = m.snapshot
	var side: int = 0 if snapshot.creatures[r.attacker_uid].owner == player else 1
	var ability_active := false
	for play in r.plays:
		if int(play[0]) == side and StringName(play[1]) == target:
			if r.cancelled_plays.has(play): m.cancelled += 1
			else: ability_active = true
	for play in r.plays:
		if int(play[0]) == side and StringName(play[1]) == target:
			m.last_target_battle = m.battles
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


func rescue_foe(copy: bool, foe_el: int) -> DeckDef:
	var foe := deck(2 if copy else foe_el)
	if copy:
		foe.abilities[0] = CardDB.card(&"ability_light_revive")
		if foe_el == 0: foe.creatures[2] = CardDB.creature(&"creature_gorgul_light")
	return foe

## Replacement of exactly one invalid draft fixture, not extra statistical sampling.
func repair_copy_fixture(path: String) -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var subject := deck(3)
	subject.abilities[0] = CardDB.card(&"ability_stone_copy")
	series("rescue", "copy-0", subject, subject, rescue_foe(true, 0), &"ability_stone_copy", &"ability_stone_copy", [11703, 11717, 11731, 11749], true)
	verify(matches.size() == 16, "only16invalidcopyfixture matches replaced")
	var replacement := 0
	for i in report.matches.size():
		var row: Dictionary = report.matches[i]
		if row.group == "rescue" and row.sample == "copy-0":
			report.matches[i] = matches[replacement]
			replacement += 1
	verify(replacement == 16, "exact16draft rows replaced")
	report["fixture_repair"] = {"discarded": 16, "replaced": 16, "unchanged": 384, "reason": "draft copy-0 had Light revival in all-Fire foe deck; replaced with second legal Light roster before any score analysis", "raw_historical": "card-audit-balance-fixture-draft-uncorrected.json"}
	report.failures = failures
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("REPAIRED COPY FIXTURE: ", replacement, ", failures=", failures)
	quit(1 if failures else 0)

## Replays only traces that actually revived a subject creature. This is not another
## AI series; it validates event provenance and the unchanged realized outcome.
func validate_revival_traces(path: String) -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var validation := {"replayed_matches": 0, "events": 0, "target_revived_before": 0, "target_revived_after": 0, "failures": 0}
	for index in report.matches.size():
		var row: Dictionary = report.matches[index]
		for deck_row in row.decks:
			verify(CardDB.deck_error(deck_row[0], deck_row[1], deck_row[2]).is_empty(), "every retained deck valid after mutation")
		if int(row.actual_revived) == 0: continue
		validation.replayed_matches += 1
		var pair: Dictionary = report.matches[index + 1 if int(row.variant) == 0 else index - 1]
		var side := int(row.side)
		var decks: Array = []
		for deck_row in row.decks: decks.append(CardDB.build_deck(deck_row[0], deck_row[1], deck_row[2]))
		var ctrl := MatchController.new(decks[0] if side == 0 else decks[1], decks[1] if side == 0 else decks[0], int(row.seed))
		ctrl.landing_window = true
		for pool in ctrl._draw_pools[side]:
			pool.erase(StringName(row.target))
			pool.erase(StringName(pair.target))
		verify(hash(ctrl._draw_pools) == int(row.pool_hash), "replay keeps identical draw pools")
		var context := {"battle": 0, "result": null, "action": -1, "target_revived": 0, "events": []}
		ctrl.battle_resolved.connect(func(result: BattleResult) -> void:
			context.battle += 1
			context.result = result)
		ctrl.card_revealed.connect(func(_slot: int, _id: StringName) -> void: context.result = null)
		ctrl.creature_revived.connect(func(uid: int) -> void:
			if ctrl.state.creatures[uid].owner != side: return
			var from_target := false
			if context.result != null and CardDB.card(StringName(row.target)).effect_id in [&"revive", &"copy"]:
				var result: BattleResult = context.result
				var rs := 0 if ctrl.state.creatures[result.attacker_uid].owner == side else 1
				if result.revive[rs]:
					for play in result.plays:
						if int(play[0]) == rs and String(play[1]) == row.target and not result.cancelled_plays.has(play): from_target = true
			if from_target: context.target_revived += 1
			context.events.append({"event": "revived", "battle": context.battle, "action": context.action, "uid": uid, "phase": ctrl.state.phase, "source": "ability_resolution" if context.result != null else "gate_reveal", "from_target": from_target}))
		for action_index in row.actions.size():
			context.action = action_index
			context.result = null # Command-local queued source, not callback state.phase.
			var action: Array = row.actions[action_index]
			var args: Array = action[1].duplicate()
			for i in args.size():
				if typeof(args[i]) == TYPE_STRING: args[i] = StringName(args[i])
				elif typeof(args[i]) == TYPE_FLOAT: args[i] = int(args[i])
			verify(MatchReplay.ALLOWED.has(String(action[0])), "allowed replay command")
			var result: Variant = ctrl.callv(StringName(action[0]), args)
			verify(result == null or int(result) == OK, "saved action is legal")
			if failures: break
		var realized_win := 1 if ctrl.winner == side else (0 if ctrl.winner >= 0 else -1)
		verify(realized_win == int(row.win) and ctrl.get_turn() == int(row.turns), "replay outcome and turn identical")
		verify(ctrl.state.alive_count(side) == int(row.final_alive[0]) and ctrl.state.alive_count(1 - side) == int(row.final_alive[1]), "replay final alive identical")
		verify(context.events.size() == int(row.actual_revived), "all actual revivals reproduced")
		validation.events += context.events.size()
		validation.target_revived_before += int(row.target_revived)
		validation.target_revived_after += int(context.target_revived)
		row.target_revived = context.target_revived
		row.events = context.events
		for signal_info in ctrl.get_signal_list():
			for connection in ctrl.get_signal_connection_list(signal_info.name): ctrl.disconnect(signal_info.name, connection.callable)
		if failures: break
	validation.failures = failures
	report["revival_trace_validation"] = validation
	report["revival_attribution_contract"] = "Queued signals: reset source before each command; card_revealed selects gate source; battle_resolved selects ability source/result. target_revived requires effect revive/copy, active uncancelled target play and result.revive. Callback phase is diagnostic only (already advanced). Corrected JSON is source of truth; raw historical draft preserved separately."
	var file := FileAccess.open(path, FileAccess.WRITE)
	verify(file != null, "validation report writable")
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("REVIVAL TRACE VALIDATION: ", JSON.stringify(validation))
	quit(1 if failures else 0)

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	var validation_args := OS.get_cmdline_user_args()
	if validation_args.size() == 2 and validation_args[0] == "--repair-copy-fixture":
		repair_copy_fixture(validation_args[1])
		return
	if validation_args.size() == 2 and validation_args[0] == "--validate-revivals":
		validate_revival_traces(validation_args[1])
		return
	var seeds4: Array = [11703, 11717, 11731, 11749]
	for el in 6:
		var field := StringName("arena_field_" + GameData.ATTR_KEYS[el])
		series("gold", GameData.ATTR_KEYS[el], deck(el, field), deck(el), deck((el + 3) % 6), field, &"arena_altar", seeds4)
	for i in 8:
		var species: String = GameData.SPECIES[i].id
		var gate := StringName("arena_den_" + species)
		var alternate := &"arena_den_klykar" if species != "klykar" else &"arena_den_gorgul"
		for j in 3:
			var el: int = (i + j) % 6
			var foe := species_deck(i, (el + 3) % 6, gate) if j == 1 else deck((el + 2) % 6)
			series("species", species + ("-mirror" if j == 1 else "-mixed"), species_deck(i, el, alternate), species_deck(i, el, gate), foe, alternate, gate, [seeds4[j]])
	for el in [0, 3, 5]:
		series("mute", GameData.ATTR_KEYS[el], deck(el), deck(el, &"arena_altar", &"arena_mute"), deck((el + 2) % 6), &"arena_funnel", &"arena_mute", seeds4)
	for el in 6:
		var weak := StringName("ability_" + WEAK[el])
		var comeback := StringName("ability_" + RETURNING[el])
		series("conditional", GameData.ATTR_KEYS[el], deck(el), deck(el, &"arena_altar", &"arena_funnel", comeback), deck((el + 2) % 6), weak, comeback, seeds4)
	for copy in [false, true]:
		for foe_el in [0, 2]:
			var subject := deck(3 if copy else 2)
			var foe := rescue_foe(copy, foe_el)
			var target := &"ability_stone_copy" if copy else &"ability_light_revive"
			subject.abilities[0] = CardDB.card(target)
			series("rescue", ("copy" if copy else "revive") + "-" + str(foe_el), subject, subject, foe, target, target, seeds4, true)
	verify(matches.size() == 400, "ровно400 preregistered матчей")
	var report := {"method": "400 targeted HARD/HARD matches; 200 paired replacements/policy comparisons; exact landing; get_view only; gold96/species96/mute48/conditional96/rescue64; seeds11703/11717/11731/11749 mirrored; real revive/recall/recharge signals", "preregistered": PREREG, "failures": failures, "matches": matches, "limits": "Purposive grid, not global meta or human play. Paired local ablation is not an alternate match. No graphics/physical landing. Rescue toggles only fallback, not all use of card. Late opening counts opposing prior exchange cards only; attached cards counted separately as suppressed plays."}
	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else "user://card-audit-balance.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	verify(file != null, "report writable")
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("CARD AUDIT BALANCE: ", matches.size(), " matches, ", failures, " failures")
	quit(1 if failures else 0)
