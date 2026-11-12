extends RefCounted
## Typed scene-side command. MatchController remains the authority on legality.
enum Kind { PLACE_GATE, SKIP_GATE, SELECT_CREATURE, THROW_WITH_GATE, PLAY_ABILITY, PASS_ABILITY, OPEN_GATE, REPORT_LANDING }
const Target := preload("res://scenes/interaction/ability_target.gd")
var kind: Kind
var player := 0
var card_id: StringName = &""
var uid := -1
var slot := -1
var target := Target.new()

func execute(controller: MatchController) -> Error:
	match kind:
		Kind.PLACE_GATE: return controller.place_arena_card(player,card_id,slot)
		Kind.SKIP_GATE: return controller.skip_gate(player)
		Kind.SELECT_CREATURE: return controller.select_creature(player,uid)
		Kind.THROW_WITH_GATE: return controller.throw_with_gate(player,card_id,slot,uid)
		Kind.PLAY_ABILITY:
			if not target.valid: return ERR_INVALID_PARAMETER
			return controller.play_ability(player,card_id,target.to_core())
		Kind.PASS_ABILITY: return controller.pass_ability(player)
		Kind.OPEN_GATE: return controller.reveal_gate(player)
		Kind.REPORT_LANDING:
			controller.report_landing(uid,slot)
			return OK
	return ERR_INVALID_PARAMETER
