class_name OnlineProtocol
extends RefCounted
## JSON only: no Variant deserialization, object construction or remote method names.
const VERSION := 1
const MAX_PACKET := 16384
const MAX_SERVER_PACKET := 262144
const COMMANDS := ["place_gate", "skip_gate", "select", "launch", "ability", "pass", "reveal_gate", "throw_with_gate"]

static func content_tag() -> String:
	# Bump online-rules when a rule or physics implementation changes independently of data.
	return JSON.stringify(["online-rules-10", GameData.SPECIES, GameData.CARDS,
		GameData.ATTR_POWER_SHIFT, GameData.TEAM_POWER_LIMIT]).sha256_text()

static func integer(value: Variant, low: int, high: int) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= low and float(value) <= high

static func ids(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for id in value:
		if not id is String or id.is_empty() or id.length() > 80:
			return false
	return true

static func _keys(packet: Dictionary, keys: Array) -> bool:
	if packet.size() != keys.size(): return false
	for key in keys:
		if not packet.has(key): return false
	return true

static func validate(packet: Dictionary) -> String:
	if not packet.get("t") is String: return "Нет типа сообщения"
	match packet.t:
		"hello":
			if not _keys(packet, ["t", "version", "content"]) or not integer(packet.get("version"), 1, 10000) or not packet.get("content") is String or packet.content.length() > 128: return "Неверное приветствие"
		"create":
			if not _keys(packet, ["t", "name"]) or not _name(packet.get("name")): return "Неверное имя"
		"join":
			if not _keys(packet, ["t", "name", "code"]) or not _name(packet.get("name")) or not packet.get("code") is String or packet.code.length() != 8: return "Неверный код комнаты"
		"deck":
			if not _keys(packet, ["t", "creatures", "gates", "abilities"]) or not ids(packet.get("creatures")) or not ids(packet.get("gates")) or not ids(packet.get("abilities")): return "Неверная колода"
		"ready":
			if not _keys(packet, ["t", "ready"]) or not packet.get("ready") is bool: return "Неверная готовность"
		"action":
			if not _keys(packet, ["t", "command", "args"]) or not packet.get("command") is String or not COMMANDS.has(packet.command) or not packet.get("args") is Dictionary: return "Неизвестное действие"
			var args: Dictionary = packet.args
			match packet.command:
				"throw_with_gate":
					if not _keys(args, ["card", "slot", "uid"]) or not _card(args.get("card")) or not integer(args.get("slot"), 0, 5) or not integer(args.get("uid"), 0, 5): return "Неверные ворота или существо"
				"place_gate":
					if not _keys(args, ["card", "slot"]) or not _card(args.get("card")) or not integer(args.get("slot"), 0, 5): return "Неверная карта или место"
				"ability":
					if not (_keys(args, ["card"]) or _keys(args, ["card", "target"])) or not _card(args.get("card")) or (args.has("target") and not ability_target(args.target)): return "Неверная способность или её цель"
				"select":
					if not _keys(args, ["uid"]) or not integer(args.get("uid"), 0, 5): return "Неверное существо"
				"launch":
					if not _keys(args, ["slot"]) or not integer(args.get("slot"), 0, 5): return "Неверная цель"
				_:
					if not args.is_empty(): return "Лишние параметры"
		"leave", "rematch", "ping":
			if not _keys(packet, ["t"]): return "Лишние параметры"
		_:
			return "Неизвестное сообщение"
	return ""

static func _card(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 80

static func _name(value: Variant) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length() > 32: return false
	for ch in value:
		if ch.unicode_at(0) < 32: return false
	return true

static func deck_error(packet: Dictionary) -> String:
	if not ids(packet.get("creatures")) or not ids(packet.get("gates")) or not ids(packet.get("abilities")): return "Неверная колода"
	# CardDB's rare encounter is an NPC special, unavailable in a player's deck.
	for id in packet.creatures:
		if not CardDB.creature_ids().has(StringName(id)): return "Существо недоступно игроку"
	for id in packet.gates:
		var card := CardDB.card(StringName(id))
		if card == null or card.kind != CardDef.Kind.ARENA: return "Неверный тип ворот"
	for id in packet.abilities:
		var card := CardDB.card(StringName(id))
		if card == null or card.kind != CardDef.Kind.ABILITY: return "Неверный тип способности"
	return CardDB.deck_error(packet.creatures, packet.gates, packet.abilities)

## The selected public server is still an untrusted network endpoint. Bound and
## type-check each message before the client hands it to the typed scene adapter.
static func validate_server(packet: Dictionary) -> bool:
	if not packet.get("t") is String: return false
	match packet.t:
		"hello":
			return _keys(packet,["t","version","content"]) and integer(packet.version,1,10000) and packet.content is String and packet.content.length() <= 128
		"pong": return _keys(packet,["t"])
		"error":
			return _keys(packet,["t","code","message"]) and _text(packet.code,80) and _text(packet.message,512)
		"ended": return _keys(packet,["t","reason"]) and _text(packet.reason,80)
		"lobby":
			if not _keys(packet,["t","code","player","players","rematch","in_match"]) or not packet.code is String or packet.code.length() != 8 or not integer(packet.player,0,1) or not _list(packet.players,2,2) or not _list(packet.rematch,2,2) or not packet.in_match is bool: return false
			for value in packet.rematch:
				if not value is bool: return false
			for p in packet.players:
				if not p is Dictionary or not _keys(p,["name","connected","ready","has_deck","creatures"]) or not _text(p.name,32) or not p.connected is bool or not p.ready is bool or not p.has_deck is bool or not _list(p.creatures,0,3): return false
				for id in p.creatures:
					if not id is String or id.length() > 80 or CardDB.creature(StringName(id)) == null: return false
			return true
		"state": return _server_state(packet)
		"flight":
			if not _keys(packet,["t","uid","slot","samples","duration","position","quaternion","bounces","timed_out","owner","target_slot"]): return false
			if not integer(packet.uid,0,5) or not integer(packet.owner,0,1) or not integer(packet.slot,-1,5) or not integer(packet.target_slot,0,5) or not integer(packet.bounces,0,600) or not packet.timed_out is bool: return false
			if not _number(packet.duration,0.01,10) or not _list(packet.samples,2,600) or not _numbers(packet.position,3,200) or not _numbers(packet.quaternion,4,1.001): return false
			if absf(float(packet.duration)-float(packet.samples.size()-1)/60.0) > .001: return false
			for sample in packet.samples:
				if not _list(sample,7,7): return false
				for i in 3:
					if not _number(sample[i],-200,200): return false
				var norm := 0.0
				for i in range(3,7):
					if not _number(sample[i],-1.001,1.001): return false
					norm += float(sample[i])*float(sample[i])
				if absf(norm-1.0) > .01: return false
			var last: Array = packet.samples.back()
			return packet.position == last.slice(0,3) and packet.quaternion == last.slice(3,7)
	return false

static func _server_state(packet: Dictionary) -> bool:
	const Codec = preload("res://network/state_codec.gd")
	if not _keys(packet,["t","player","view","legal","selected_uid","landed_uid","throw_gate_slot","ability_moment","preview","busy","winner","reason","last_battle","battle_serial","last_standoff","standoff_serial"]): return false
	if not integer(packet.standoff_serial,0,10000) or not _list(packet.last_standoff,0,2) or packet.last_standoff.size() == 1: return false
	for uid in packet.last_standoff:
		if not integer(uid,0,5): return false
	if packet.last_standoff.size() == 2 and int(packet.last_standoff[0]) / 3 == int(packet.last_standoff[1]) / 3: return false
	if (int(packet.standoff_serial) == 0) != packet.last_standoff.is_empty(): return false
	if not integer(packet.player,0,1) or not Codec.valid_view(packet.view) or not packet.legal is Dictionary or not packet.busy is bool or not integer(packet.winner,-2,1) or not _text(packet.reason,80) or not integer(packet.battle_serial,0,10000): return false
	if not integer(packet.selected_uid,-1,5) or not integer(packet.landed_uid,-1,5) or not integer(packet.throw_gate_slot,-1,5) or packet.ability_moment not in ["","battle","pre_throw","after_landing"]: return false
	if not Codec.valid_battle(packet.preview) or not Codec.valid_battle(packet.last_battle): return false
	var legal: Dictionary = packet.legal
	if not _keys(legal,["setup_slots","creatures","abilities","can_skip_gate","can_reveal_gate","abilities_left","ability_reasons","ability_targets"]): return false
	if not legal.can_skip_gate is bool or not legal.can_reveal_gate is bool or not integer(legal.abilities_left,0,3) or not legal.ability_reasons is Dictionary or legal.ability_reasons.size() > 64: return false
	for key in ["setup_slots","creatures"]:
		if not _list(legal[key],0,6): return false
		for value in legal[key]:
			if not integer(value,0,5): return false
	if not _list(legal.abilities,0,64): return false
	for id in legal.abilities:
		if not _known_card(id): return false
	if not legal.ability_targets is Dictionary or legal.ability_targets.size() > 64: return false
	for id in legal.ability_targets:
		if not _known_card(id) or not legal.abilities.has(id) or not _list(legal.ability_targets[id],1,6): return false
		for target in legal.ability_targets[id]:
			if not ability_target(target): return false
	for id in legal.ability_reasons:
		if not _known_card(id) or not _text(legal.ability_reasons[id],512): return false
	return true

static func _known_card(value: Variant) -> bool:
	return value is String and value.length() <= 80 and CardDB.card(StringName(value)) != null
static func _text(value: Variant, limit: int) -> bool:
	return value is String and value.length() <= limit
static func _list(value: Variant, low: int, high: int) -> bool:
	return value is Array and value.size() >= low and value.size() <= high
static func _number(value: Variant, low: float, high: float) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) >= low and float(value) <= high
static func _numbers(value: Variant, size: int, bound: float) -> bool:
	if not _list(value,size,size): return false
	for item in value:
		if not _number(item,-bound,bound): return false
	return true

## Target metadata is deliberately narrow; the server still checks membership and legality.
static func ability_target(value: Variant) -> bool:
	if not value is Dictionary: return false
	if _keys(value, ["target_uid"]): return integer(value.target_uid,0,5)
	if _keys(value, ["target_card"]): return _known_card(value.target_card)
	return false
