extends SceneTree
## Default 186-match comparison or preregistered configured validation.
## Never included automatically in gameplay/full checks.
## Test-only independent draw streams remove interleaved turn-order RNG confounding.
## Rules, pools, probability distribution and live AI remain production code.

var ROSTERS = [["dragnar", "ratnik", "levian"], ["klykar", "grifalon", "rogozhuk"], ["kolossar", "gorgul", "ratnik"]]
var GREEN = ["ratnik_oath", "klykar_bite", "kolossar_wall"]
var RED = ["fire_drain", "gale_swap", "light_crown", "stone_copy", "shadow_pact", "tide_hush"]
var BLUE = ["fire_spark", "gale_gust", "light_glint", "stone_firm", "shadow_haze", "tide_spray"]
var SEEDS = [18401, 18427, 18457]
const NEW := ["ability_fire_toll", "ability_gale_call", "ability_light_reserve", "ability_stone_ceiling", "ability_shadow_triumph", "ability_tide_wash", "arena_valor"]
var failures: Array = []
var rows: Array = []
var include_mirrors := true
var label := "baseline-grid"
var random_starting_cards := false
var pair_seeded_streams := false
var pair_seeded_decks := false
var common_deck_seed := false
var gold_roles: Array = []

class MatchedController extends MatchController:
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

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func match_seed_for(roster: int, a: int, b: int) -> int:
	return int(SEEDS[roster]) * 100000 + roster * 1000 + a * 10 + b if pair_seeded_streams else int(SEEDS[roster])

func deck_seed_for(el: int, roster: int, a: int = -1, b: int = -1) -> int:
	var base: int = match_seed_for(roster, a, b) if pair_seeded_decks and a >= 0 else int(SEEDS[roster])
	return base * 313 + (0 if common_deck_seed else el)

func make_deck(el: int, roster: int, a: int = -1, b: int = -1) -> DeckDef:
	var creatures: Array = []
	for species in ROSTERS[roster]:
		creatures.append(StringName("creature_%s_%s" % [species, GameData.ATTR_KEYS[el]]))
	if random_starting_cards:
		var deck_rng := RandomNumberGenerator.new()
		deck_rng.seed = deck_seed_for(el, roster, a, b)
		var deck := CardDB.deck_from_creatures(creatures, deck_rng)
		check(deck != null, "nonempty randomized deck %d/%d" % [el, roster])
		if deck == null: return null
		if not gold_roles.is_empty():
			for index in deck.arena.size():
				if CardDB.card_class(deck.arena[index]) == &"gold":
					deck.arena[index] = CardDB.card(StringName("arena_field_" + GameData.ATTR_KEYS[el]) if gold_roles[roster] == "field" else &"arena_altar")
		var ids := deck_ids(deck)
		check(CardDB.deck_error(ids[0], ids[1], ids[2]).is_empty(), "legal randomized deck %d/%d" % [el, roster])
		return deck
	var gates: Array = [StringName("arena_field_" + GameData.ATTR_KEYS[el]), StringName("arena_den_" + ROSTERS[roster][0]), &"arena_funnel"]
	var abilities: Array = [StringName("ability_" + RED[el]), StringName("ability_" + BLUE[el]), StringName("ability_" + GREEN[roster])]
	check(CardDB.deck_error(creatures, gates, abilities).is_empty(), "legal deck %d/%d: %s" % [el, roster, CardDB.deck_error(creatures, gates, abilities)])
	return CardDB.build_deck(creatures, gates, abilities)

func deck_ids(deck: DeckDef) -> Array:
	var out: Array = [[], [], []]
	for pair in [[deck.creatures, 0], [deck.arena, 1], [deck.abilities, 2]]:
		for item in pair[0]: out[pair[1]].append(String(item.id))
	return out

func catalog() -> Dictionary:
	var creatures: Array = []
	var cards: Array = []
	var elements: Array = []
	for id in CardDB.creature_ids():
		var d := CardDB.creature(id)
		creatures.append({"id": String(id), "species": String(d.species), "element": d.attribute, "power": d.base_power})
	for id in CardDB.arena_ids() + CardDB.ability_ids():
		var d := CardDB.card(id)
		cards.append({"id": String(id), "name": d.display_name, "kind": d.kind, "class": String(CardDB.card_class(d)), "effect": String(d.effect_id), "params": d.params, "text": d.full_text()})
	for el in 6:
		var powers: Array = []
		var sum_power := 0
		var teams: Array = []
		for sp in GameData.SPECIES:
			var p := CardDB.creature(StringName("creature_%s_%s" % [sp.id, GameData.ATTR_KEYS[el]])).base_power
			powers.append(p)
			sum_power += p
		for a in 8:
			for b in range(a + 1, 8):
				for c in range(b + 1, 8):
					if powers[a] + powers[b] + powers[c] <= GameData.TEAM_POWER_LIMIT: teams.append([a, b, c, powers[a] + powers[b] + powers[c]])
		var available: Array = []
		for card in cards:
			if CardDB.card_fits(CardDB.card(StringName(card.id)), el): available.append(card.id)
		elements.append({"element": el, "key": GameData.ATTR_KEYS[el], "powers": powers, "sum_power": sum_power, "mean_power": sum_power / 8.0, "legal_distinct_species_teams": teams, "available_cards_all_species": available})
	return {"creatures": creatures, "cards": cards, "elements": elements, "rare_excluded": String(CardDB.RARE_SHADOW_ID)}

func count_key(dict: Dictionary, id: String) -> void:
	dict[id] = int(dict.get(id, 0)) + 1

func battle_record(ctrl: MatchController, m: Dictionary, r: BattleResult) -> void:
	var item := {"attacker": r.attacker_uid, "defender": r.defender_uid, "winner": r.winner_uid, "loser": r.loser_uid, "powers": r.powers.duplicate(), "elements": [r.attr_atk, r.attr_def], "gate": String(r.arena_card_id), "gate_cancelled": r.arena_cancelled, "gate_owner_side": r.gate_owner_side, "plays": r.plays.duplicate(true), "cancelled": r.cancelled_plays.duplicate(true), "ordinary": r.ordinary, "both_lose": r.both_lose, "interrupted": r.interrupted, "revive_intentions": r.revive.duplicate(), "called_uids": r.called_uids.duplicate(), "reserve_intentions": r.reserve_cards.duplicate(), "triumph_intentions": r.triumph.duplicate(), "valor_saved_uid": r.valor_saved_uid, "breakdown": r.breakdown.duplicate(true)}
	m.battles.append(item)
	for play in r.plays:
		var owner: int = ctrl.state.creatures[r.attacker_uid if int(play[0]) == 0 else r.defender_uid].owner
		if not r.cancelled_plays.has(play): count_key(m.active[owner], String(play[1]))

func run_match(a: int, b: int, roster: int, swapped: bool, first_role: int, mirror: bool = false) -> Dictionary:
	var elements: Array = [b, a] if swapped else [a, b]
	var first_player: int = (1 - first_role) if swapped else first_role
	var case_seed: int = SEEDS[roster]
	var seed_value: int = match_seed_for(roster, a, b)
	var decks: Array = [make_deck(elements[0], roster, a, b), make_deck(elements[1], roster, a, b)]
	var ctrl := MatchedController.new(decks[0], decks[1], seed_value)
	ctrl.landing_window = true
	ctrl.configure_streams([seed_value * 101 + int(elements[0]), seed_value * 101 + int(elements[1])])
	var ais: Array = []
	for p in 2: ais.append(AIPlayer.new(p, seed_value * 31 + int(elements[p]), -1.0, AIPlayer.Difficulty.HARD))
	var m := {"a": a, "b": b, "roster": roster, "seed": seed_value, "case_seed": case_seed, "swapped": swapped, "first_role": first_role, "first_player": first_player, "elements": elements, "mirror": mirror, "decks": [deck_ids(decks[0]), deck_ids(decks[1])], "initial_pools": ctrl._draw_pools.duplicate(true), "drawn": [[], []], "played": [{}, {}], "attached": [{}, {}], "active": [{}, {}], "opened": [{}, {}], "legal_new": [{}, {}], "eliminated": [], "revived": [], "returned": [], "recalled": [], "battles": [], "steps": 0}
	ctrl.card_drawn.connect(func(p: int, id: StringName) -> void: m.drawn[p].append(String(id)))
	ctrl.ability_played.connect(func(p: int, id: StringName) -> void: count_key(m.played[p], String(id)))
	ctrl.ability_attached.connect(func(p: int, _uid: int, id: StringName) -> void: count_key(m.attached[p], String(id)))
	ctrl.card_revealed.connect(func(slot: int, id: StringName) -> void: count_key(m.opened[ctrl.state.slots[slot].card_owner], String(id)))
	ctrl.creature_eliminated.connect(func(uid: int) -> void: m.eliminated.append([uid, ctrl.state.creatures[uid].owner, ctrl.get_turn()]))
	ctrl.creature_revived.connect(func(uid: int) -> void: m.revived.append([uid, ctrl.state.creatures[uid].owner, ctrl.get_turn()]))
	ctrl.creature_returned.connect(func(uid: int, reason: StringName) -> void: m.returned.append([uid, String(reason), ctrl.get_turn()]))
	ctrl.abilities_recalled.connect(func(p: int, ids: Array) -> void: m.recalled.append([p, ids.duplicate(), ctrl.get_turn()]))
	ctrl.battle_resolved.connect(func(r: BattleResult) -> void: battle_record(ctrl, m, r))
	ctrl.start(first_player)
	var pending := -1
	while ctrl.get_phase() != MatchController.Phase.GAME_OVER and int(m.steps) < 3000 and failures.is_empty():
		m.steps += 1
		var p := ctrl.get_active_player()
		var err := OK
		match ctrl.get_phase():
			MatchController.Phase.SETUP:
				var choice: Dictionary = ais[p].choose_setup(ctrl.get_view(p), ctrl.legal_setup_slots(), ctrl.can_skip_gate())
				if choice.is_empty(): err = ctrl.skip_gate(p)
				elif choice.has("throw_uid"):
					pending = int(choice.slot)
					err = ctrl.throw_with_gate(p, choice.card_id, choice.slot, choice.throw_uid)
				else: err = ctrl.place_arena_card(p, choice.card_id, choice.slot)
			MatchController.Phase.AWAIT_THROW:
				var choice: Dictionary = ais[p].choose_throw(ctrl.get_view(p))
				pending = int(choice.target_slot)
				err = ctrl.select_creature(p, choice.uid)
			MatchController.Phase.AWAIT_LANDING:
				ctrl.report_landing(ctrl.get_selected_uid(), pending)
			MatchController.Phase.AFTER_LANDING, MatchController.Phase.ABILITY_WINDOW:
				var legal := ctrl.legal_abilities(p)
				for id in legal:
					if String(id) in NEW: count_key(m.legal_new[p], String(id))
				var pick: StringName = &""
				if ctrl.get_phase() == MatchController.Phase.AFTER_LANDING:
					pick = ais[p].choose_attach(ctrl.get_view(p), ctrl.get_landed_uid(), legal)
				else:
					if ctrl.can_reveal_gate(p) and ais[p].should_open_gate(ctrl.get_view(p), ctrl.get_battle_preview()):
						err = ctrl.reveal_gate(p)
						check(err == OK, "reveal")
						continue
					pick = ais[p].choose_ability(ctrl.get_view(p), ctrl.get_battle_preview(), legal)
				var target: Dictionary = {} if pick == &"" else ais[p].choose_ability_target(ctrl.get_view(p), ctrl.get_battle_preview(), pick, ctrl.legal_ability_targets(p, pick))
				err = ctrl.pass_ability(p) if pick == &"" else ctrl.play_ability(p, pick, target)
		check(err == OK, "action a=%d b=%d roster=%d swap=%s first=%d step=%d error=%d" % [a, b, roster, swapped, first_role, m.steps, err])
	check(ctrl.get_phase() == MatchController.Phase.GAME_OVER, "finished")
	m["finished"] = ctrl.get_phase() == MatchController.Phase.GAME_OVER
	m["winner_player"] = ctrl.winner
	m["winner_element"] = -1 if ctrl.winner < 0 else elements[ctrl.winner]
	m["a_score"] = 0.5 if ctrl.winner < 0 else (1.0 if ctrl.winner == (1 if swapped else 0) else 0.0)
	m["turns"] = ctrl.get_turn()
	m["reason"] = String(ctrl.game_over_reason)
	m["final_alive"] = [ctrl.state.alive_count(0), ctrl.state.alive_count(1)]
	m["survivors"] = []
	for cs in ctrl.state.creatures.values():
		if cs.alive: m.survivors.append([cs.owner, String(cs.def_id), CardDB.creature(cs.def_id).base_power])
	m["actions"] = ctrl.action_trace.duplicate(true)
	m["events"] = ctrl.event_log.duplicate()
	for info in ctrl.get_signal_list():
		for connection in ctrl.get_signal_connection_list(info.name): ctrl.disconnect(info.name, connection.callable)
	return m

func write_report(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	check(f != null, "write report")
	if f != null: f.store_string(JSON.stringify(data, "\t") + "\n")

func _initialize() -> void:
	Engine.max_fps = 60
	AudioServer.set_bus_mute(0, true)
	CardDB.load_all()
	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else "user://element-balance.json"
	if args.size() > 1 and args[1] != "catalog":
		var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		ROSTERS = config.rosters
		SEEDS = config.seeds
		random_starting_cards = bool(config.get("random_starting_cards", false))
		pair_seeded_streams = bool(config.get("pair_seeded_streams", false))
		pair_seeded_decks = bool(config.get("pair_seeded_decks", false))
		common_deck_seed = bool(config.get("common_deck_seed", false))
		gold_roles = config.get("gold_roles", [])
		if not random_starting_cards:
			GREEN = config.green
			RED = config.red
			BLUE = config.blue
		include_mirrors = bool(config.get("mirrors", false))
		label = String(config.label)
		check(ROSTERS.size() == SEEDS.size() and (random_starting_cards or GREEN.size() == ROSTERS.size()), "config case dimensions")
		check(gold_roles.is_empty() or gold_roles.size() == ROSTERS.size(), "gold role dimensions")
		for role in gold_roles: check(role in ["field", "altar"], "known gold role")
	var data := catalog()
	write_report(path.get_basename() + "-catalog.json", data)
	if args.size() > 1 and args[1] == "catalog":
		quit(1 if not failures.is_empty() else 0)
		return
	if args.size() > 2 and args[2] == "manifest":
		var cases: Array = []
		if pair_seeded_decks:
			for roster in ROSTERS.size():
				for a in 6:
					for b in range(a + 1, 6):
						for el in [a,b]:
							cases.append({"case": roster, "pair": [a,b], "element": el, "seed": SEEDS[roster], "deck_seed": deck_seed_for(el, roster, a, b), "gold_role": gold_roles[roster], "deck": deck_ids(make_deck(el, roster, a, b))})
		else:
			for roster in ROSTERS.size():
				for el in 6: cases.append({"case": roster, "element": el, "seed": SEEDS[roster], "deck_seed": deck_seed_for(el, roster), "deck": deck_ids(make_deck(el, roster))})
		var streams: Array = []
		for roster in ROSTERS.size():
			for a in 6:
				for b in range(a + 1, 6):
					streams.append({"case": roster, "pair": [a,b], "match_seed": match_seed_for(roster, a, b)})
		write_report(path, {"label": label, "cases": cases, "match_streams": streams, "failures": failures})
		quit(1 if not failures.is_empty() else 0)
		return
	for roster in ROSTERS.size():
		for a in 6:
			for b in range(a + 1, 6):
				for swapped in [false, true]:
					for first_role in 2:
						if not failures.is_empty(): break
						rows.append(run_match(a, b, roster, swapped, first_role))
				print("ELEMENT BALANCE roster=", roster, " pair=", a, "/", b, " total=", rows.size(), " failures=", failures.size())
	if include_mirrors:
		for el in 6:
			if failures.is_empty(): rows.append(run_match(el, el, el % ROSTERS.size(), false, 0, true))
	# Across all four orientations, each role must receive the same card prefix.
	var expected_cross: int = 60 * ROSTERS.size()
	for start in range(0, mini(rows.size(), expected_cross), 4):
		if start + 3 >= rows.size(): break
		for role in 2:
			var prefixes: Array = []
			for index in range(start, start + 4):
				var row: Dictionary = rows[index]
				var player: int = 1 - role if row.swapped else role
				prefixes.append(row.drawn[player])
			for seq in prefixes:
				for other in prefixes:
					for k in mini(seq.size(), other.size()): check(seq[k] == other[k], "paired draw prefix")
	check(rows.size() == expected_cross + (6 if include_mirrors else 0), "fixed configured grid")
	write_report(path, {"method": "Configured cross-element matches: 15 pairs x preregistered roster/seed cases x 2 playerID layouts x 2 first movers; draw and AI stream seeds follow element, not playerID. Production HARD uses get_view; real controller outcomes/signals; exact landings without physics. Optional six equal-element smoke controls use identical draw/AI streams. Test-only RNG schedule differs from ordinary game; no rule or probability changes.", "label": label, "rosters": ROSTERS, "seeds": SEEDS, "random_starting_cards": random_starting_cards, "pair_seeded_streams": pair_seeded_streams, "pair_seeded_decks": pair_seeded_decks, "common_deck_seed": common_deck_seed, "gold_roles": gold_roles, "match_seed_method": "case_seed * 100000 + case_index * 1000 + a * 10 + b (a < b)" if pair_seeded_streams else "one case seed reused across pairs", "deck_seed_method": "independent pair/case seed * 313; shared quantile across elements; gold roles stratified" if common_deck_seed else ("case_seed * 313 + element; CardDB.deck_from_creatures" if random_starting_cards else "fixed starting cards"), "starting_green": [] if random_starting_cards else GREEN, "starting_red": [] if random_starting_cards else RED, "starting_blue": [] if random_starting_cards else BLUE, "stopping": "Fixed configured grid or first action/unfinished/invariant error; no expansion for significance", "flag": "Descriptive thresholds and case manifest: tools/checkpoints/element-balance-acceptance-2026-11-04.md; not proof of universal balance", "failures": failures, "matches": rows})
	print("ELEMENT BALANCE: ", rows.size(), " matches; ", failures.size(), " failures")
	quit(1 if not failures.is_empty() else 0)
