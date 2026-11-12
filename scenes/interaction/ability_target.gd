extends RefCounted
## Typed card target. Existing controller/UI dictionaries are boundary serialization only.
enum Kind { NONE, CREATURE, CARD }
var kind: Kind = Kind.NONE
var uid := -1
var card_id: StringName = &""
var valid := true

func assign_core(value: Dictionary) -> void:
	kind = Kind.NONE
	uid = -1
	card_id = &""
	valid = true
	if value.is_empty(): return
	# Legal-target descriptors also contain a display label. It is not command data.
	for key in value:
		if key not in ["target_uid","target_card","label"]:
			valid = false
			return
	if value.has("target_uid") == value.has("target_card"):
		valid = false
	elif value.has("target_uid"):
		kind = Kind.CREATURE
		uid = int(value.target_uid)
		valid = uid >= 0
	elif value.has("target_card"):
		kind = Kind.CARD
		card_id = StringName(value.target_card)
		valid = card_id != &""
	else: valid = false

func to_core() -> Dictionary:
	match kind:
		Kind.CREATURE: return {"target_uid":uid}
		Kind.CARD: return {"target_card":card_id}
	return {}
