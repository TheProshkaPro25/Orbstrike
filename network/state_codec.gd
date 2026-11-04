class_name OnlineStateCodec
extends RefCounted
## Only call encode_view on MatchController.get_view(recipient). Never serialize the controller.
static func encode_view(view: MatchState) -> Dictionary:
	var out := {"ruleset": view.ruleset, "manual_gates": view.manual_gates, "turn": view.turn,
		"phase": view.phase, "active_player": view.active_player, "final_round": view.final_round,
		"play_stamp": view.play_stamp, "players": [], "slots": [], "creatures": [], "battle_context": {}}
	for p in view.players:
		out.players.append({"index": p.index, "creature_uids": p.creature_uids.duplicate(),
			"arena_hand": p.arena_hand.duplicate(), "ability_hand": p.ability_hand.duplicate(),
			"abilities_used": p.abilities_used.duplicate(), "ability_cooldown": p.ability_cooldown.duplicate(),
			"captured": p.captured.duplicate(), "momentum": p.momentum})
	for s in view.slots:
		out.slots.append({"card_id": String(s.card_id), "card_owner": s.card_owner,
			"revealed": s.revealed, "occupant_uid": s.occupant_uid, "has_card": s.has_card})
	for uid in view.creatures:
		var c: CreatureState = view.creatures[uid]
		out.creatures.append({"uid": c.uid, "def_id": String(c.def_id), "owner": c.owner,
			"alive": c.alive, "slot": c.slot, "used": c.used, "recalled_from": c.recalled_from,
			"attached": c.attached.duplicate(true), "marks": c.marks.duplicate(true)})
	if view.battle_context != null:
		out.battle_context = {"slot": view.battle_context.slot, "participants": []}
		for p in view.battle_context.participants:
			out.battle_context.participants.append([p.player_id, p.creature_uid, p.side_id, p.team_id])
	return out

static func decode_view(data: Dictionary) -> MatchState:
	# Source is the connected server; construct fixed data classes, never scripts from the wire.
	var view := MatchState.new()
	for key in ["ruleset", "manual_gates", "turn", "phase", "active_player", "final_round", "play_stamp"]:
		view.set(key, data[key])
	for i in range(2):
		var row: Dictionary = data.players[i]
		var p := PlayerState.new(i)
		for uid in row.creature_uids: p.creature_uids.append(int(uid))
		for key in ["arena_hand", "ability_hand", "abilities_used", "captured"]:
			for id in row[key]: p.get(key).append(StringName(id))
		p.ability_cooldown = row.ability_cooldown.duplicate()
		p.momentum = int(row.momentum)
		view.players[i] = p
	for i in range(6):
		var row: Dictionary = data.slots[i]
		var s := SlotState.new()
		s.card_id = StringName(row.card_id)
		s.card_owner = int(row.card_owner)
		s.revealed = row.revealed
		s.occupant_uid = int(row.occupant_uid)
		s.has_card = row.has_card
		view.slots[i] = s
	for row in data.creatures:
		var c := CreatureState.new(int(row.uid), StringName(row.def_id), int(row.owner))
		c.alive = row.alive
		c.slot = int(row.slot)
		c.used = row.used
		c.recalled_from = int(row.recalled_from)
		c.attached = row.attached.duplicate(true)
		c.marks = row.marks.duplicate(true)
		view.creatures[c.uid] = c
	if not data.battle_context.is_empty():
		view.battle_context = BattleContext.new()
		view.battle_context.slot = int(data.battle_context.slot)
		for p in data.battle_context.participants:
			view.battle_context.add(BattleParticipant.new(int(p[0]), int(p[1]), int(p[2]), int(p[3])))
	return view

static func preview(result: BattleResult) -> Dictionary:
	if result == null: return {}
	var data: Dictionary = {}
	for key in BATTLE_FIELDS:
		var value: Variant = result.get(key)
		data[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return data

const BATTLE_FIELDS := ["slot", "attacker_uid", "defender_uid", "winner_uid", "loser_uid", "powers", "breakdown", "atk_ability", "def_ability", "atk_cancelled", "def_cancelled", "arena_card_id", "arena_cancelled", "attr_atk", "attr_def", "atk_fusion", "def_fusion", "plays", "ability_counts", "battle_plays", "passed", "cancelled_plays", "trap_id", "sealed", "mirrored", "final_round", "momentum", "gate_effect", "gate_owner_side", "silenced", "interrupted", "relocate_uid", "relocate_to", "both_lose", "winner_stays", "auto_win", "revive", "recall", "marks", "copies", "ordinary", "called_uids", "reserve_cards", "triumph", "valor_saved_uid"]

static func decode_battle(data: Dictionary, view: MatchState = null) -> BattleResult:
	if data.is_empty(): return null
	var result := BattleResult.new()
	for key in BATTLE_FIELDS:
		if not data.has(key): continue
		var old: Variant = result.get(key)
		var value: Variant = data[key]
		match typeof(old):
			TYPE_STRING_NAME: result.set(key, StringName(value))
			TYPE_INT: result.set(key, int(value))
			TYPE_ARRAY:
				var values: Array = old
				values.clear()
				for item in value:
					match values.get_typed_builtin():
						TYPE_INT: values.append(int(item))
						TYPE_STRING_NAME: values.append(StringName(item))
						_: values.append(item)
			_: result.set(key, value)
	for key in ["plays", "battle_plays", "cancelled_plays"]:
		for play in result.get(key):
			if play.size() == 3:
				var target: Dictionary = play[2]
				play[2] = {"target_uid":int(target.target_uid)} if target.has("target_uid") else {"target_card":StringName(target.target_card)}
	if view != null and view.creatures.has(result.attacker_uid) and view.creatures.has(result.defender_uid):
		result.context = BattleContext.duel(view, result.attacker_uid, result.defender_uid, result.slot)
	return result

## Validate untrusted server data before any typed construction or scene access.
static func valid_view(data: Variant) -> bool:
	if not data is Dictionary or not _fields(data,["ruleset","manual_gates","turn","phase","active_player","final_round","play_stamp","players","slots","creatures","battle_context"]): return false
	if not _int(data.ruleset,0,1) or not data.manual_gates is bool or not _int(data.turn,0,10000) or not _int(data.phase,0,6) or not _int(data.active_player,0,1) or not data.final_round is bool or not _int(data.play_stamp,0,100000): return false
	if not _array(data.players,2,2) or not _array(data.slots,6,6) or not _array(data.creatures,6,6): return false
	for i in 2:
		var p: Variant = data.players[i]
		if not p is Dictionary or not _fields(p,["index","creature_uids","arena_hand","ability_hand","abilities_used","ability_cooldown","captured","momentum"]): return false
		if not _int(p.index,i,i) or not _array(p.creature_uids,3,3) or not _int(p.momentum,0,100): return false
		for j in 3:
			if not _int(p.creature_uids[j],i*3+j,i*3+j): return false
		for key in ["arena_hand","ability_hand","abilities_used","captured"]:
			if not _array(p[key],0,64): return false
			for id in p[key]:
				if not _card_id(id,true): return false
		if not p.ability_cooldown is Dictionary or p.ability_cooldown.size() > 64: return false
		for id in p.ability_cooldown:
			if not _card_id(id,false) or not _int(p.ability_cooldown[id],0,100): return false
	for s in data.slots:
		if not s is Dictionary or not _fields(s,["card_id","card_owner","revealed","occupant_uid","has_card"]): return false
		if not _card_id(s.card_id,true) or not _int(s.card_owner,-1,1) or not s.revealed is bool or not _int(s.occupant_uid,-1,5) or not s.has_card is bool: return false
		if s.has_card and (int(s.card_owner) < 0 or (s.revealed and s.card_id.is_empty())): return false
	var seen: Array = []
	var species_seen: Array = [[],[]]
	for c in data.creatures:
		if not c is Dictionary or not _fields(c,["uid","def_id","owner","alive","slot","used","recalled_from","attached","marks"]): return false
		if not _int(c.uid,0,5) or seen.has(int(c.uid)) or not _int(c.owner,0,1) or int(c.owner) != int(c.uid)/3: return false
		seen.append(int(c.uid))
		if not c.def_id is String or not CardDB.creature_ids().has(StringName(c.def_id)) or not c.alive is bool or not _int(c.slot,-1,5) or not c.used is bool or not _int(c.recalled_from,-1,5): return false
		if species_seen[int(c.owner)].has(c.def_id): return false
		species_seen[int(c.owner)].append(c.def_id)
		if not _array(c.attached,0,3) or not _array(c.marks,0,64): return false
		for play in c.attached:
			if not _array(play,2,2) or not _int(play[0],0,100000) or not _card_id(play[1],false): return false
		for mark in c.marks:
			if not _mark(mark): return false
	var context: Variant = data.battle_context
	if not context is Dictionary: return false
	if not context.is_empty():
		if not _fields(context,["slot","participants"]) or not _int(context.slot,0,5) or not _array(context.participants,2,2): return false
		for p in context.participants:
			if not _array(p,4,4) or not _int(p[0],0,1) or not _int(p[1],0,5) or not _int(p[2],0,1) or not _int(p[3],-1,1): return false
	return true

static func valid_battle(data: Variant) -> bool:
	if not data is Dictionary: return false
	if data.is_empty(): return true
	if not _fields(data,BATTLE_FIELDS) or not _plain(data,0): return false
	var model := BattleResult.new()
	for key in BATTLE_FIELDS:
		var old: Variant = model.get(key)
		var value: Variant = data[key]
		match typeof(old):
			TYPE_INT:
				if not _int(value,-100000,100000): return false
			TYPE_BOOL:
				if not value is bool: return false
			TYPE_STRING_NAME:
				if not value is String or value.length() > 80: return false
			TYPE_ARRAY:
				if not value is Array or value.size() > 128: return false
			_:
				return false
	for key in ["attacker_uid","defender_uid"]:
		if not _int(data[key],0,5): return false
	for key in ["winner_uid","loser_uid","relocate_uid"]:
		if not _int(data[key],-1,5): return false
	if not _int(data.slot,0,5) or not _int(data.relocate_to,-1,5): return false
	for key in ["powers","momentum"]:
		if not _array(data[key],2,2): return false
		for value in data[key]:
			if not _int(value,-100000,100000): return false
	if not _array(data.ability_counts,2,2): return false
	for value in data.ability_counts:
		if not _int(value,0,MatchRules.MAX_BATTLE_ABILITIES): return false
	for key in ["passed","silenced","revive"]:
		if not _array(data[key],2,2): return false
		for value in data[key]:
			if not value is bool: return false
	for key in ["atk_ability","def_ability","arena_card_id","atk_fusion","def_fusion","trap_id"]:
		if not _card_id(data[key],true): return false
	for key in ["plays","battle_plays","cancelled_plays"]:
		for play in data[key]:
			if not _array(play,2,3) or not _int(play[0],0,1) or not _card_id(play[1],false): return false
			if play.size() == 3 and not OnlineProtocol.ability_target(play[2]): return false
	if not _int(data.valor_saved_uid,-1,5) or not _array(data.called_uids,2,2) or not _array(data.reserve_cards,2,2) or not _array(data.triumph,2,2): return false
	for i in 2:
		if not _int(data.called_uids[i],-1,5) or not _card_id(data.reserve_cards[i],true) or not data.triumph[i] is bool: return false
	for row in data.breakdown:
		if not row is Dictionary or not _fields(row,["side","source","delta"]) or not _int(row.side,0,1) or not row.source is String or row.source.length() > 256 or not _int(row.delta,-100000,100000): return false
	if not _array(data.recall,2,2): return false
	for id in data.recall:
		if not _card_id(id,true): return false
	for row in data.marks:
		if not _array(row,2,2) or not _int(row[0],0,5) or not _mark(row[1]): return false
	for row in data.copies:
		if not _array(row,3,3) or not _int(row[0],0,1) or not _card_id(row[1],false) or not _card_id(row[2],false): return false
	return true

static func _mark(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 2 or not _card_id(data.get("src"),false): return false
	if data.has("delta"): return _int(data.delta,-100000,100000)
	return data.has("fix") and _int(data.fix,-100000,100000)

static func _fields(data: Dictionary, keys: Array) -> bool:
	if data.size() != keys.size(): return false
	for key in keys:
		if not data.has(key): return false
	return true

static func _array(value: Variant, low: int, high: int) -> bool:
	return value is Array and value.size() >= low and value.size() <= high

static func _int(value: Variant, low: int, high: int) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= low and float(value) <= high

static func _card_id(value: Variant, hidden: bool) -> bool:
	return value is String and ((hidden and value.is_empty()) or (value.length() <= 80 and CardDB.card(StringName(value)) != null))

static func _plain(value: Variant, depth: int) -> bool:
	if depth > 5: return false
	if value is bool: return true
	if value is String: return value.length() <= 256
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT: return is_finite(float(value)) and absf(float(value)) <= 100000
	if value is Array:
		if value.size() > 128: return false
		for item in value:
			if not _plain(item,depth+1): return false
		return true
	if value is Dictionary:
		if value.size() > 64: return false
		for key in value:
			if not key is String or not _plain(value[key],depth+1): return false
		return true
	return false
