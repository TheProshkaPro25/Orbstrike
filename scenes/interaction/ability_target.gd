extends RefCounted
## Typed card target. Existing controller/UI dictionaries are boundary serialization only.
enum Kind { NONE, CREATURE, CARD, SLOT }
var kind: Kind = Kind.NONE
var uid := -1
var slot := -1
var card_id: StringName = &""
var valid := true

func assign_core(value: Dictionary) -> void:
	kind = Kind.NONE
	uid = -1
	slot = -1
	card_id = &""
	valid = true
	if value.is_empty(): return
	# Legal-target descriptors also contain a display label. It is not command data.
	var keys := value.keys()
	keys.erase("label")
	if keys.size() != 1:
		valid = false
		return
	for key in keys:
		if key not in ["target_uid","target_card","target_slot"]:
			valid = false
			return
	if value.has("target_uid"):
		kind = Kind.CREATURE
		uid = int(value.target_uid)
		valid = uid >= 0
	elif value.has("target_card"):
		kind = Kind.CARD
		card_id = StringName(value.target_card)
		valid = card_id != &""
	elif value.has("target_slot"):
		var target_slot: Variant = value.target_slot
		kind = Kind.SLOT
		valid = typeof(target_slot) in [TYPE_INT, TYPE_FLOAT] and target_slot >= 0 and target_slot < 6 and float(target_slot) == floorf(float(target_slot))
		if valid:
			slot = int(target_slot)

func to_core() -> Dictionary:
	match kind:
		Kind.CREATURE: return {"target_uid":uid}
		Kind.CARD: return {"target_card":card_id}
		Kind.SLOT: return {"target_slot":slot}
	return {}
