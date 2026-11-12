extends RefCounted
## Typed presentation→interaction request. Dictionaries exist only at legacy/test edges.
enum Kind { NONE, SETUP, THROW, LAUNCH, ABILITY, ATTACH }
var kind: Kind = Kind.NONE
var player := 0
var uid := -1

static func make(value: Kind, side: int, actor: int = -1) -> RefCounted:
	var result: RefCounted = load("res://scenes/interaction/interaction_request.gd").new()
	result.kind = value
	result.player = side
	result.uid = actor
	return result

func expected_phase() -> int:
	match kind:
		Kind.SETUP: return MatchController.Phase.SETUP
		Kind.THROW: return MatchController.Phase.AWAIT_THROW
		Kind.LAUNCH: return MatchController.Phase.AWAIT_LANDING
		Kind.ABILITY: return MatchController.Phase.ABILITY_WINDOW
		Kind.ATTACH: return MatchController.Phase.AFTER_LANDING
	return -1

static func from_legacy(value: Dictionary) -> RefCounted:
	var names := {"setup":Kind.SETUP,"throw":Kind.THROW,"launch":Kind.LAUNCH,"ability":Kind.ABILITY,"attach":Kind.ATTACH}
	return make(names.get(str(value.get("kind","")),Kind.NONE),int(value.get("player",0)),int(value.get("uid",-1)))

func to_legacy() -> Dictionary:
	if kind == Kind.NONE: return {}
	var names := {Kind.SETUP:"setup",Kind.THROW:"throw",Kind.LAUNCH:"launch",Kind.ABILITY:"ability",Kind.ATTACH:"attach"}
	var result := {"kind":names[kind],"player":player}
	if uid >= 0: result.uid = uid
	return result

func is_empty() -> bool:
	return kind == Kind.NONE
