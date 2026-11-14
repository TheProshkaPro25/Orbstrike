class_name MatchReplay
extends RefCounted
## Воспроизведение только команд конечного автомата, без визуала и ИИ.
const ALLOWED := ["start", "place_arena_card", "skip_gate", "throw_with_gate", "select_creature", "report_landing", "play_ability", "pass_ability", "reveal_gate"]

static func restore(data: Dictionary) -> Dictionary:
	if data.get("version", 0) != 1 or data.get("decks", []).size() != 2:
		return {"error": "Некорректная запись матча"}
	var elemental_cards: Variant = data.get("elemental_cards", false)
	if not elemental_cards is bool:
		return {"error": "Некорректный набор карт матча"}
	var stored_pool: Variant = data.get("card_pool", int(elemental_cards))
	if typeof(stored_pool) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(stored_pool)) or float(stored_pool) != floorf(float(stored_pool)) or stored_pool < CardDB.Pool.BASE or stored_pool > CardDB.Pool.SPECIES:
		return {"error": "Некорректный набор карт матча"}
	var decks: Array[DeckDef] = []
	for row in data.decks:
		for id in row[1] + row[2]:
			var card := CardDB.card(StringName(id))
			if card == null or (card.params.get("local_species_set", false) and (int(stored_pool) != CardDB.Pool.SPECIES or int(data.ruleset) != MatchRules.Ruleset.ANIME_INSPIRED)):
				return {"error": "Карта недоступна для набора карт матча"}
		decks.append(CardDB.build_deck(row[0], row[1], row[2]))
	var ctrl := MatchController.new(decks[0], decks[1], int(data.seed), int(data.ruleset), int(stored_pool))
	ctrl.landing_window = bool(data.landing_window)
	ctrl.state.manual_gates = bool(data.get("manual_gates", false))
	var power_snapshots: Variant = data.get("power_snapshots", [])
	if not power_snapshots is Array or (not power_snapshots.is_empty() and power_snapshots.size() != 2):
		return {"error": "Некорректный снимок силы матча"}
	for side in range(power_snapshots.size()):
		if not power_snapshots[side] is Dictionary or power_snapshots[side].size() != ctrl.state.players[side].creature_uids.size():
			return {"error": "Некорректный снимок силы матча"}
		if PowerCalc.apply_power_snapshot(ctrl.state, side, power_snapshots[side]) != OK:
			return {"error": "Некорректный снимок силы матча"}
	var index := 0
	for action in data.actions:
		var name := String(action[0])
		if not ALLOWED.has(name):
			return {"error": "Неизвестное действие: " + name, "index": index}
		var args: Array = action[1].duplicate()
		for i in range(args.size()):
			if typeof(args[i]) == TYPE_STRING:
				args[i] = StringName(args[i])
			elif typeof(args[i]) == TYPE_FLOAT:
				args[i] = int(args[i])
		var result: Variant = ctrl.callv(name, args)
		if result != null and int(result) != OK:
			return {"error": "Действие отклонено", "index": index, "code": int(result), "controller": ctrl}
		index += 1
	return {"error": "", "controller": ctrl, "actions": index}
