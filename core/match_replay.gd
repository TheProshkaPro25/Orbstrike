class_name MatchReplay
extends RefCounted
## Воспроизведение только команд конечного автомата, без визуала и ИИ.
const ALLOWED := ["start", "place_arena_card", "skip_gate", "throw_with_gate", "select_creature", "report_landing", "play_ability", "pass_ability", "reveal_gate"]

static func restore(data: Dictionary) -> Dictionary:
	if data.get("version", 0) != 1 or data.get("decks", []).size() != 2:
		return {"error": "Некорректная запись матча"}
	var decks: Array[DeckDef] = []
	for row in data.decks:
		decks.append(CardDB.build_deck(row[0], row[1], row[2]))
	var ctrl := MatchController.new(decks[0], decks[1], int(data.seed), int(data.ruleset))
	ctrl.landing_window = bool(data.landing_window)
	ctrl.state.manual_gates = bool(data.get("manual_gates", false))
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
