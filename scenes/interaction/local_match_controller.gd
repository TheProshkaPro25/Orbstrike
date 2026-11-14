extends MatchController
## The local client confirms a human turn before any turn-start effects occur.

signal turn_waiting(next_turn: int)

const HUMAN := 0

var _waiting_for_turn := false
var _turn_notice_sent := false


func _init(deck0: DeckDef, deck1: DeckDef, rng_seed: int, ruleset: int = MatchRules.Ruleset.ANIME_INSPIRED, card_pool: int = CardDB.Pool.BASE) -> void:
	super(deck0, deck1, rng_seed, ruleset, card_pool)


func is_turn_waiting() -> bool:
	return _waiting_for_turn


func confirm_turn() -> bool:
	if not _waiting_for_turn or _flushing:
		return false
	_waiting_for_turn = false
	_turn_notice_sent = false
	super._begin_turn(HUMAN)
	_flush()
	return true


func _begin_turn(player: int) -> void:
	if player != HUMAN or state.turn >= MAX_TURNS:
		super._begin_turn(player)
		return
	_waiting_for_turn = true


func _flush() -> void:
	if _flushing:
		return
	super._flush()
	# Queue the prompt after the previous action's animations. It is UI-only,
	# so it never enters the replay's action trace or the domain event log.
	if _waiting_for_turn and not _turn_notice_sent:
		_turn_notice_sent = true
		turn_waiting.emit(get_turn() + 1)


func legal_setup_slots() -> Array[int]:
	return [] if _waiting_for_turn else super.legal_setup_slots()


func can_skip_gate() -> bool:
	return not _waiting_for_turn and super.can_skip_gate()


func legal_abilities(player: int) -> Array[StringName]:
	return [] if _waiting_for_turn else super.legal_abilities(player)


func can_reveal_gate(player: int) -> bool:
	return not _waiting_for_turn and super.can_reveal_gate(player)


func ability_unavailable_reason(player: int, id: StringName) -> String:
	return tr("Сначала нажмите «Следующий ход»") if _waiting_for_turn else super.ability_unavailable_reason(player, id)


func place_arena_card(player: int, card_id: StringName, slot: int) -> Error:
	return ERR_UNAUTHORIZED if _waiting_for_turn else super.place_arena_card(player, card_id, slot)


func skip_gate(player: int) -> Error:
	return ERR_UNAUTHORIZED if _waiting_for_turn else super.skip_gate(player)


func throw_with_gate(player: int, card_id: StringName, slot: int, uid: int) -> Error:
	return ERR_UNAUTHORIZED if _waiting_for_turn else super.throw_with_gate(player, card_id, slot, uid)


func select_creature(player: int, uid: int) -> Error:
	return ERR_UNAUTHORIZED if _waiting_for_turn else super.select_creature(player, uid)


func report_landing(uid: int, slot: int) -> void:
	if not _waiting_for_turn:
		super.report_landing(uid, slot)


func play_ability(player: int, card_id: StringName, target: Dictionary = {}) -> Error:
	return ERR_UNAUTHORIZED if _waiting_for_turn else super.play_ability(player, card_id, target)


func pass_ability(player: int) -> Error:
	return ERR_UNAUTHORIZED if _waiting_for_turn else super.pass_ability(player)


func reveal_gate(player: int) -> Error:
	return ERR_UNAUTHORIZED if _waiting_for_turn else super.reveal_gate(player)
