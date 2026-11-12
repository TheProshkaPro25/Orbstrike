extends RefCounted
## Complete offline match input. Scene coordination consumes this value, not mode internals.
var mode := "duel"
var decks: Array[DeckDef] = []
var seed := 0
var first_side := 0
var difficulty := AIPlayer.Difficulty.NORMAL
var ai_preferences: Dictionary = {}
var profiles: Array[Dictionary] = []
var names: Array[String] = []
var arena_id := 0
var power_snapshots: Array[Dictionary] = [{}, {}]
var fixture: Dictionary = {}

func apply_power_snapshots(controller: MatchController) -> void:
	for side in 2:
		if not power_snapshots[side].is_empty():
			PowerCalc.apply_power_snapshot(controller.state,side,power_snapshots[side])
