extends RefCounted
## Reversible compound gate+throw selection; independent of controller state.
var card_id: StringName = &""
var slot := -1

func clear() -> void:
	card_id = &""
	slot = -1

func is_empty() -> bool:
	return card_id == &""

func to_legacy() -> Dictionary:
	return {} if is_empty() else {"card":card_id,"slot":slot}

func assign_legacy(value: Dictionary) -> void:
	card_id = StringName(value.get("card",&""))
	slot = int(value.get("slot",-1))
