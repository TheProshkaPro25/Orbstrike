extends MatchController
## Presentation adapter. This holds only the recipient-filtered snapshot, never runs rules.
func _init() -> void:
	super(CardDB.preset_deck(0), CardDB.preset_deck(1), 0)

func get_view(_player: int) -> MatchState:
	return state
