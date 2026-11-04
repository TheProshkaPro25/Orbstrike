extends SceneTree
## Five saved baseline prefixes, three calls per implementation; no new matches.
const SOURCE := "res://build/checks/element-balance-20261104/element-balance.json"
const CASES := [
	[20, 7, "early_setup"], [20, 8, "early_throw"], [20, 10, "early_ability"],
	[101, 34, "late_setup"], [101, 71, "late_ability"],
]
var failures: Array = []
var memo_experiment := false

class CachedAI extends AIPlayer:
	var odds_cache: Dictionary = {}
	var cache_hits := 0
	var cache_misses := 0
	func _hidden_card_odds(groups: Array, known_counts: Array[int], matching: Dictionary, hidden: int) -> Dictionary:
		var ids := matching.keys()
		ids.sort()
		var signature := JSON.stringify([groups, known_counts, ids, hidden])
		if odds_cache.has(signature):
			cache_hits += 1
			return odds_cache[signature]
		cache_misses += 1
		var result := super._hidden_card_odds(groups, known_counts, matching, hidden)
		odds_cache[signature] = result
		return result

class BeforeAI extends AIPlayer:
	# Exact pre-forecast implementations; retain all prior uncommitted card support.
	func _hidden_guard_gate(view: MatchState, _uid: int, occ: int, _slot: int) -> StringName:
		return _field_of(view.creatures[occ])
	func _flip_prob(view: MatchState, r: BattleResult, side: int) -> float:
		var fs: int = 1 - side
		if r.passed[fs] or _foe_plays_left(view, r, side) <= 0:
			return 0.0
		var fighter: int = r.attacker_uid if fs == 0 else r.defender_uid
		var foe: int = view.creatures[fighter].owner
		var groups: Array = _public_card_pool(view, foe, CardDef.Kind.ABILITY)
		var known: Dictionary = {}
		for id in view.players[foe].abilities_used:
			known[id] = true
		var counts: Array[int] = _remove_known_cards(groups, known)
		var flips: Dictionary = {}
		for cands in groups:
			for id in cands:
				if _forecast_legal(view, r, id, fs) and _margin(_with_card(view, r, id, fs), side) <= 0.0:
					flips[id] = true
		return _hidden_card_odds(groups, counts, flips, view.players[foe].ability_hand.size()).any

class ReplayController extends MatchController:
	var draw_states: Array = []
	func configure_streams(seeds: Array) -> void:
		for value in seeds:
			var stream := RandomNumberGenerator.new()
			stream.seed = int(value)
			draw_states.append(stream.state)
	func _draw_turn_card(player: int) -> void:
		var saved := _rng.state
		_rng.state = draw_states[player]
		super._draw_turn_card(player)
		draw_states[player] = _rng.state
		_rng.state = saved
	func _standoff(player: int) -> void:
		# Restore only the historical baseline standoff schedule for prefix replay.
		var atk := _strongest_standing(player)
		var dfn := _strongest_standing(1 - player)
		if atk < 0 or dfn < 0:
			_finish_by_limit(&"stalemate")
			return
		var from: int = state.creatures[atk].slot
		var to: int = state.creatures[dfn].slot
		state.slots[from].occupant_uid = -1
		state.creatures[atk].slot = -1
		_ev(&"standoff", [atk, dfn])
		_ev(&"creature_relocated", [atk, from, to])
		_start_battle(atk, dfn, to)

func restore(row: Dictionary, prefix: int) -> MatchController:
	var decks: Array = []
	for ids in row.decks:
		decks.append(CardDB.build_deck(ids[0], ids[1], ids[2]))
	var ctrl := ReplayController.new(decks[0], decks[1], int(row.seed))
	ctrl.landing_window = true
	ctrl.configure_streams([int(row.seed) * 101 + int(row.elements[0]), int(row.seed) * 101 + int(row.elements[1])])
	for i in prefix:
		var action: Array = row.actions[i]
		var args: Array = action[1].duplicate(true)
		for j in args.size():
			if args[j] is String: args[j] = StringName(args[j])
			elif args[j] is float: args[j] = int(args[j])
		var result: Variant = ctrl.callv(String(action[0]), args)
		if result != null and int(result) != OK:
			failures.append("prefix rejected action %d: %s/%s" % [i, str(action), str(result)])
			return null
	return ctrl

func measure(ctrl: MatchController, before: bool, seed_value: int) -> Dictionary:
	var p := ctrl.get_active_player()
	var ai: AIPlayer
	if memo_experiment:
		ai = AIPlayer.new(p, seed_value, -1.0, AIPlayer.Difficulty.HARD) if before else CachedAI.new(p, seed_value, -1.0, AIPlayer.Difficulty.HARD)
	else:
		ai = BeforeAI.new(p, seed_value, -1.0, AIPlayer.Difficulty.HARD) if before else AIPlayer.new(p, seed_value, -1.0, AIPlayer.Difficulty.HARD)
	var view := ctrl.get_view(p)
	var slots := ctrl.legal_setup_slots()
	var can_skip := ctrl.can_skip_gate()
	var legal := ctrl.legal_abilities(p)
	var preview := ctrl.get_battle_preview()
	var result: Variant
	var start := Time.get_ticks_usec()
	match ctrl.get_phase():
		MatchController.Phase.SETUP: result = ai.choose_setup(view, slots, can_skip)
		MatchController.Phase.AWAIT_THROW: result = ai.choose_throw(view)
		MatchController.Phase.ABILITY_WINDOW: result = ai.choose_ability(view, preview, legal)
		_: failures.append("unsupported decision phase %d" % ctrl.get_phase())
	var elapsed := Time.get_ticks_usec() - start
	var sample := {"ms": float(elapsed) / 1000.0, "decision": str(result)}
	if ai is CachedAI:
		sample["cache_hits"] = ai.cache_hits
		sample["cache_misses"] = ai.cache_misses
		sample["cache_entries"] = ai.odds_cache.size()
	return sample

func summarize(samples: Array) -> Dictionary:
	var times: Array = []
	for sample in samples: times.append(sample.ms)
	times.sort()
	return {"samples": samples, "median_ms": times[1], "max_ms": times[-1]}

func _initialize() -> void:
	Engine.max_fps = 60
	CardDB.load_all()
	var args := OS.get_cmdline_user_args()
	memo_experiment = args.size() > 1 and args[1] == "memo"
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	var positions: Array = []
	for spec in CASES:
		var ctrl := restore(raw.matches[spec[0]], spec[1])
		if ctrl == null: break
		var p := ctrl.get_active_player()
		var entry := {"name": spec[2], "raw_match": spec[0], "prefix_actions": spec[1], "turn": ctrl.get_turn(), "phase": ctrl.get_phase(), "player": p, "own_ability_count": ctrl.state.players[p].ability_hand.size(), "foe_ability_count": ctrl.state.players[1 - p].ability_hand.size(), "own_gate_count": ctrl.state.players[p].arena_hand.size()}
		var before: Array = []
		var after: Array = []
		for run in 3:
			# Fresh equal seed per call, alternate order; timing excludes fixture/API setup.
			if run % 2 == 0:
				before.append(measure(ctrl, true, 91701))
				after.append(measure(ctrl, false, 91701))
			else:
				after.append(measure(ctrl, false, 91701))
				before.append(measure(ctrl, true, 91701))
		entry["before"] = summarize(before)
		entry["after"] = summarize(after)
		for run in 3:
			if memo_experiment and before[run].decision != after[run].decision:
				failures.append("memo changed decision %s run %d" % [spec[2], run])
		positions.append(entry)
		print("FORECAST TIMING ", spec[2], " before=", entry.before.median_ms, "ms after=", entry.after.median_ms, "ms max=", entry.after.max_ms, "ms")
	var report := {"method": "Five saved baseline action prefixes; independent historical draw streams and deterministic historical standoffs restored locally. Catalog preloaded, three calls per implementation/position, fresh identical AI seeds, alternating implementation order. Only decision body timed. BeforeAI restores exactly old one-card flip and fixed-Field guard, leaving prior uncommitted cards intact. No new match series; shared-host wall times do not establish FPS or universal worst-case latency.", "source": SOURCE, "positions": positions, "failures": failures}
	if memo_experiment:
		report["method"] = "Memoization experiment only: before=current frozen forecast; after=test subclass CachedAI caches exactly the same _hidden_card_odds arithmetic by complete input signature. Same five baseline action prefixes, three calls per implementation, fresh seeds, alternating order; decision equality asserted. No production edits/new matches. Shared-host wall times, no FPS claim."
	var output: String = args[0] if not args.is_empty() else "res://build/checks/element-balance-20261104/performance.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: failures.append("cannot write report")
	else: file.store_string(JSON.stringify(report, "\t") + "\n")
	quit(1 if not failures.is_empty() else 0)
