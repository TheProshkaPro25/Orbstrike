class_name AIPlayer
extends RefCounted
## ИИ-игрок. Видит только MatchState из MatchController.get_view(player) (чужие закрытые карты пусты).
## Не мутирует состояние; все решения детерминированы по rng_seed.
##
## Уровни сложности (Difficulty):
## - EASY («Новичок»): большой разброс броска, шумная оценка целей, часто пасует, карты выбирает наугад.
## - NORMAL («Боец»): бой с перевесом, своя подходящая карта, самая дешёвая выигрышная способность, в обмене держит
##   запас перевеса 80 против ответа соперника и план на две карты; «ворота + бросок» с оценкой угрозы; ставит существо
##   на своё «Зеркало» (приманка) с учётом угрозы; после приземления прикрепляет защиту.
## - HARD («Мастер»): плюс блеф (ловушку кладёт первой и сажает на неё приманку), оценка риска ловушки на чужих
##   закрытых воротах (по уже раскрытым картам соперника), оценка ворот соперника под его существом (скорее всего
##   «Поле» его стихии), счёт карт: возможные способности — по стихии, видам, публичным ID и размеру руки после добора;
##   в обмене выбирает пас или карту по шансу, что соперник не перевернёт бой одним ответом/ограниченным набором пар (минус цена карты), цель броска —
##   по шансу выиграть бой со своими картами; розыгрыш пары карт, если одной мало. Ворота кладёт каждый ход,
##   защитные карты после приземления не прикрепляет.
## Новые карты (2026-10-28) ИИ понимает через предпросмотр PowerCalc.compute_with (мгновенные «Сдвиг плит» и
## «Вихревая подмена» считаются на копии состояния) и оценку исхода _margin («Отлив», «Общая бездна», «Трон сумрака»,
## «Предел»); «Попутный шквал» — в choose_attach на всех уровнях.

enum Difficulty { EASY, NORMAL, HARD }

const DIFFICULTY_NAMES: Array[String] = ["Новичок", "Боец", "Мастер"]
## Разброс броска (для физики в main.gd) по уровню сложности.
const AIM_ERROR: Array[float] = [0.62, 0.42, 0.30]

const WIN_MARGIN: float = 40.0
## Порядок «дешевизны» способностей (по effect_id): от наименее ценных к самым рискованным.
## Карты-«спасатели» (doom, ebb) и мгновенные стоят дороже: их ценность не в силе, а в исходе.
const ABILITY_COST_ORDER: Array[String] = [
	"boost", "pact", "radiance", "scorch", "purge_gate", "eclipse", "nullify_gate", "aloft", "weaken_mark",
	"boost_fix", "fusion_boost", "drain", "tide_wash", "flame_toll", "stone_ceiling", "gale_call", "copy", "shift_gate", "silence", "negate", "cap_own_base", "strip",
	"reset_base", "siphon", "swap_fighter", "revive", "recall", "light_reserve", "shadow_triumph", "doom", "ebb",
]
## Штраф оценки броска в бой на чужие закрытые ворота за вероятность ловушки (HARD).
const TRAP_RISK_PENALTY: float = 300.0
## Мастер: цена разовой способности в долях шанса победы в бою (тратить карту ради малого прироста невыгодно);
## карты, возвращающиеся в руку после боя, почти бесплатны.
const CARD_COST: float = 0.12
const CARD_COST_RETURNS: float = 0.02

var player: int = 1
var difficulty: int = Difficulty.NORMAL
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _aim_error: float = 0.42
## Все увиденные свои ворота, включая добор: совпавший ID захвата не раскрывает прежнего владельца.
var _my_gates: Dictionary = {}
## Ограниченные предпочтения NPC: меняют оценку решений, не правила/силу/точность.
var personality: Dictionary = {"attack_bias": 0.0, "trap_bias": 0.0, "safe_margin": 0.0, "card_cost_bias": 0.0}

func configure_personality(preferences: Dictionary) -> void:
	for key in personality:
		var limit: float = 0.04 if key == "card_cost_bias" else (25.0 if key == "safe_margin" else 60.0)
		var value: Variant = preferences.get(key, 0.0)
		personality[key] = clampf(float(value), -limit, limit) if (value is float or value is int) and is_finite(float(value)) else 0.0



## aim_error < 0 — разброс по уровню сложности (AIM_ERROR).
func _init(p_player: int = 1, rng_seed: int = 0, aim_error: float = -1.0, p_difficulty: int = Difficulty.NORMAL) -> void:
	player = p_player
	_rng.seed = rng_seed
	difficulty = clampi(p_difficulty, Difficulty.EASY, Difficulty.HARD)
	_aim_error = aim_error if aim_error >= 0.0 else AIM_ERROR[difficulty]


func get_aim_error() -> float:
	return _aim_error


static func difficulty_name(d: int) -> String:
	return DIFFICULTY_NAMES[clampi(d, 0, DIFFICULTY_NAMES.size() - 1)]


## legal — MatchController.legal_setup_slots(). -> {card_id, slot[, throw_uid]}; {} = не класть (если можно пропустить).
## throw_uid — «ворота + бросок»: вызвать ctrl.throw_with_gate(p, card_id, slot, throw_uid) и бросать в slot.
## Кладёт карту, если ворот на поле мало (или с вероятностью), выбирая карту под стихии своих существ.
func choose_setup(view: MatchState, legal = null, can_skip: bool = false) -> Dictionary:
	_remember_gates(view)
	var ps: PlayerState = view.players[player]
	var slots: Array = legal.duplicate() if legal != null else []
	if legal == null:
		for i in range(view.slots.size()):
			if not view.slots[i].has_card:
				slots.append(i)
	if ps.arena_hand.is_empty() or slots.is_empty():
		return {}
	var gates: int = 0
	for sl in view.slots:
		if sl.has_card:
			gates += 1
	# Мастер ворота не пропускает: свои ворота под своим существом — главный козырь защитника (по симуляции +2 %)
	if can_skip and gates >= 2 and difficulty != Difficulty.HARD and _rng.randf() < 0.45:
		return {}
	var best: StringName = ps.arena_hand[0]
	var slot: int = int(slots[0])
	var pick: int = -1
	var best_value: float = -INF
	var ready: Array[int] = _ready(view)
	for id in ps.arena_hand:
		var card: CardDef = CardDB.card(id)
		for target in slots:
			var candidates: Array = ready if not ready.is_empty() else [-1]
			for uid in candidates:
				var value: float = _rng.randf() * (100.0 if difficulty == Difficulty.EASY else 2.0)
				if difficulty != Difficulty.EASY and uid >= 0:
					var trial: MatchState = view.duplicate_full()
					trial.slots[int(target)].has_card = true
					trial.slots[int(target)].card_id = id
					trial.slots[int(target)].card_owner = player
					value += 100.0 if _fits(card, CardDB.creature(view.creatures[uid].def_id)) else 0.0
					value -= _exposure(trial, uid, int(target))
					if CardEffects.is_gate_trap(card):
						value += _trap_bait_score(view, uid, card) - 650.0 + float(personality.trap_bias)
				if value > best_value:
					best_value = value
					best = id
					slot = int(target)
					pick = uid
	var out: Dictionary = {"card_id": best, "slot": slot}
	if difficulty != Difficulty.EASY and pick >= 0:
		var attack: bool = false
		for uid in ready:
			for i in range(view.slots.size()):
				var occ: int = view.slots[i].occupant_uid
				if view.slots[i].has_card and occ >= 0 and view.creatures[occ].owner != player and _score(view, uid, i) >= 900.0:
					attack = true
		if not attack and difficulty == Difficulty.HARD and ready.size() >= 2:
			attack = _reserve_attack_better_than_stand(view, ready, best, slot, pick)
		if not attack:
			out["throw_uid"] = pick
	return out


## Автопосадка не должна закрывать резерв, когда обычный выбор броска уже предпочёл бы
## полезную атаку с доступной Подменой. Без реального вклада карты прежний порог900 сохранён.
func _reserve_attack_better_than_stand(view: MatchState, ready: Array[int], gate_id: StringName, gate_slot: int, stand_uid: int) -> bool:
	var reserve_cards: Array[StringName] = []
	for id in view.players[player].ability_hand:
		if CardEffects.is_effect(CardDB.card(id), &"swap_fighter"): reserve_cards.append(id)
	if reserve_cards.is_empty(): return false
	var trial := view.duplicate_full()
	trial.slots[gate_slot].has_card = true
	trial.slots[gate_slot].card_id = gate_id
	trial.slots[gate_slot].card_owner = player
	# Обычный choose_throw добавляет шум до2: реальная атака должна выигрывать и этот запас.
	var best_value := _score(trial, stand_uid, gate_slot) + 2.0
	var best_uid := -1
	var best_slot := -1
	var best_card: StringName = &""
	for uid in ready:
		for slot in range(trial.slots.size()):
			var occ: int = trial.slots[slot].occupant_uid
			if occ < 0 or trial.creatures[occ].owner == player: continue
			var r := PowerCalc.compute_seq(trial, uid, occ, slot, [])
			for id in reserve_cards:
				if not _forecast_legal(trial, r, id, 0): continue
				var value := _score(trial, uid, slot)
				if value > best_value:
					best_value = value
					best_uid = uid
					best_slot = slot
					best_card = id
	if best_uid < 0: return false
	# Один дополнительный прогноз только лучшей атаки: карта в руке должна действительно помогать.
	var without := trial.duplicate_full()
	without.players[player].ability_hand.erase(best_card)
	return best_value > _score(without, best_uid, best_slot) + 0.001


## Существа в руке (можно бросить).
func _ready(view: MatchState) -> Array[int]:
	var out: Array[int] = []
	for uid in view.players[player].creature_uids:
		var c: CreatureState = view.creatures[uid]
		if c.alive and c.slot < 0 and not c.used:
			out.append(uid)
	return out


func ps_uids(view: MatchState) -> Array[int]:
	return view.players[player].creature_uids


## -> {uid: int, target_slot: int}
func choose_throw(view: MatchState) -> Dictionary:
	_remember_gates(view)
	var cands: Array[int] = _candidates(view)
	var best_uid: int = -1
	var best_slot: int = -1
	var best_score: float = -INF
	var noise: float = 250.0 if difficulty == Difficulty.EASY else 2.0
	for uid in cands:
		for slot in range(view.slots.size()):
			var score: float = _score(view, uid, slot)
			if score <= -500.0:
				continue
			var occupant: int = view.slots[slot].occupant_uid
			if occupant >= 0 and view.creatures[occupant].owner != player:
				score += float(personality.attack_bias)
			score += _rng.randf() * noise
			if score > best_score:
				best_score = score
				best_uid = uid
				best_slot = slot
	if best_uid < 0:
		# нет осмысленной цели: любое существо, любой слот (будет возврат в резерв)
		if cands.is_empty():
			return {"uid": -1, "target_slot": -1}
		best_uid = cands[0]
		best_slot = _rng.randi_range(0, view.slots.size() - 1)
	return {"uid": best_uid, "target_slot": best_slot}


## preview — MatchController.get_battle_preview(). &"" = пас (если соперник уже спасовал — бой решается;
## после моей карты соперник снова может ответить).
## legal: карты, разрешённые контроллером сейчас; null — вся рука, пустой список — пас.
## Обмен способностями: проигрываю — самая дешёвая карта, после которой выигрываю (HARD ищет и пару карт);
## выигрываю — пас, если соперник уже не может ответить или запас перевеса достаточен, иначе карта «про запас».
func should_open_gate(view: MatchState, preview: BattleResult) -> bool:
	if preview == null or preview.slot < 0:
		return false
	var gate: SlotState = view.slots[preview.slot]
	if gate.revealed or gate.card_owner != player:
		return false
	var opened := PowerCalc.preview_open_gate(view, preview.slot)
	var after := PowerCalc.compute_seq(opened, preview.attacker_uid, preview.defender_uid, preview.slot, preview.battle_plays)
	var side := 0 if view.creatures[preview.attacker_uid].owner == player else 1
	if CardEffects.is_effect(CardDB.card(gate.card_id), &"fallen_call"):
		# Ворота возвращают обе команды ещё до боя. Считать живых из opened,
		# а материальное изменение — относительно исходного вида, включая готовый KO.
		var before_value := _outcome_utility(view, preview, side)
		var after_value := _outcome_utility(view, after, side, opened)
		if not is_equal_approx(before_value, after_value): return after_value > before_value
		var before_material := _alive_after(view, preview, side) - _alive_after(view, preview, 1 - side)
		var after_material := _alive_after(opened, after, side) - _alive_after(opened, after, 1 - side)
		return after_material > before_material
	if _alive_after(view, after, side) > _alive_after(view, preview, side):
		return true
	if _margin(after, side) > _margin(preview, side):
		return true
	# Обычное усиление можно заглушить следующим ответом, сохранив ловушку до траты карты.
	# Но Сдвиг/Подмена меняют позицию необратимо: после паса прежнее окно уже не вернуть.
	# Проверяем только публично возможный ответ, без настоящих ID чужой руки/закрытых ворот.
	return after.sealed and not preview.sealed and _margin(after, side) >= _margin(preview, side) and _gate_escape_possible(view, preview, side)


func _gate_escape_possible(view: MatchState, preview: BattleResult, side: int) -> bool:
	if _foe_plays_left(view, preview, side, true) <= 0:
		return false
	var fs: int = 1 - side
	var fighter: int = preview.attacker_uid if fs == 0 else preview.defender_uid
	var foe: int = view.creatures[fighter].owner
	for group in _foe_pool(view, foe):
		for id in group:
			var card: CardDef = CardDB.card(id)
			if CardEffects.is_effect(card, &"swap_fighter") and _forecast_legal(view, preview, id, fs):
				return true
			if not CardEffects.is_effect(card, &"shift_gate") or not _forecast_shift_fighter(view, preview, fs, card):
				continue
			for i in range(view.slots.size()):
				var sl: SlotState = view.slots[i]
				if i != preview.slot and sl.has_card and sl.card_owner == foe and sl.occupant_uid < 0:
					# Неизвестные ворота могут оказаться допустимой целью Сдвига; открытая ловушка — нет.
					if not sl.revealed or not CardEffects.is_gate_trap(CardDB.card(sl.card_id)):
						return true
	return false


func _forecast_shift_fighter(view: MatchState, preview: BattleResult, side: int, card: CardDef) -> bool:
	var fighter: int = preview.attacker_uid if side == 0 else preview.defender_uid
	return CardEffects.lock_attr(card) == CardDB.creature(view.creatures[fighter].def_id).attribute and not preview.silenced[side] and not PowerCalc.side_locked(preview, side)


## При выборе будущего боя владелец знает свои ворота и сохраняет право открыть их.
## Рассматриваем открытие только на копии и только если текущая политика выбрала бы его.
func _planned_gate_state(view: MatchState, preview: BattleResult) -> MatchState:
	if view.manual_gates and should_open_gate(view, preview):
		return PowerCalc.preview_open_gate(view, preview.slot)
	return view


func choose_ability(view: MatchState, preview: BattleResult, legal = null) -> StringName:
	if preview == null:
		return &""
	var side: int = 0 if view.creatures[preview.attacker_uid].owner == player else 1
	var cards: Array[StringName] = []
	for id in (legal if legal != null else view.players[player].ability_hand):
		if id != &"" and _forecast_legal(view, preview, StringName(id), side):
			cards.append(StringName(id))
	if cards.is_empty():
		return &""
	var foe_can: int = _foe_plays_left(view, preview, side)  # ответит ли соперник на мой пас
	var foe_reply: int = _foe_plays_left(view, preview, side, true)  # ...и на мою карту (пас не окончателен)
	var margin: float = _margin(preview, side)
	if difficulty == Difficulty.EASY:
		if margin > 0.0 or _rng.randf() < 0.35:
			return &""
		_shuffle(cards)
		for id in cards:
			if _margin(_with_card(view, preview, id, side), side) > 0.0:
				return id
		return &""
	cards.sort_custom(_cheaper)
	if difficulty == Difficulty.HARD:
		var pick: StringName = _choose_hard(view, preview, cards, side)
		if pick != &"":
			return pick
		if margin > 0.0:
			return _choose_revival(view, preview, cards, side)
	# запас перевеса, при котором можно спокойно пасовать: соперник ещё может ответить картами
	var safe: float = 0.0
	if foe_can > 0:
		safe = (80.0 if difficulty == Difficulty.NORMAL else 60.0 + 40.0 * foe_can) + float(personality.safe_margin)
	# запас после своей карты: на неё соперник ответит, даже если до этого пасовал
	var safe_play: float = 0.0
	if foe_reply > 0:
		safe_play = (80.0 if difficulty == Difficulty.NORMAL else 60.0 + 40.0 * foe_reply) + float(personality.safe_margin)
	if margin > 0.0:
		if margin >= safe:
			return _choose_revival(view, preview, cards, side)
		# выигрываю впритык, а соперник ещё ответит: усилиться, если это даёт запас
		for id in cards:
			if _margin(_with_card(view, preview, id, side), side) >= safe_play:
				return id
		return _choose_revival(view, preview, cards, side)
	var best_id: StringName = &""
	var best_m: float = -INF
	for id in cards:
		var m: float = _margin(_with_card(view, preview, id, side), side)
		if m > 0.0:
			if difficulty == Difficulty.NORMAL or m >= safe_play:
				return id
			if m > best_m:
				best_m = m
				best_id = id
	if best_id != &"":
		return best_id
	# Одной карты мало — начать с пары, которая выигрывает (если лимит позволяет).
	if difficulty != Difficulty.EASY and not cards.is_empty() and view.players[player].ability_hand.size() >= 2 and _my_plays_left(view, preview, side) >= 2:
		for i in range(cards.size()):
			for second in view.players[player].ability_hand:
				if cards[i] == second:
					continue
				var ci: CardDef = CardDB.card(cards[i])
				var cj: CardDef = CardDB.card(second)
				if CardEffects.is_instant(ci) or CardEffects.is_instant(cj) or CardEffects.is_lockout(ci):
					continue
				if not _forecast_legal(view, preview, second, side, cards[i]):
					continue
				var bp: Array = preview.battle_plays.duplicate(true)
				var first_target := choose_ability_target(view, preview, cards[i])
				bp.append([side, cards[i], first_target] if not first_target.is_empty() else [side, cards[i]])
				var first_result := PowerCalc.compute_seq(view, preview.attacker_uid, preview.defender_uid, preview.slot, bp)
				var second_target := choose_ability_target(view, first_result, second)
				bp.append([side, second, second_target] if not second_target.is_empty() else [side, second])
				var r: BattleResult = PowerCalc.compute_seq(view, preview.attacker_uid, preview.defender_uid, preview.slot, bp)
				if _margin(r, side) > 0.0:
					return cards[i]
	return _choose_revival(view, preview, cards, side)


## Число живых после показанного исхода и Возрождения, включая только что проигравшего.
## Это локальный прогноз, не симуляция скрытых ответов или следующего боя.
func _alive_after(view: MatchState, r: BattleResult, side: int) -> int:
	var uid: int = r.attacker_uid if side == 0 else r.defender_uid
	var owner: int = view.creatures[uid].owner
	var alive: int = view.alive_count(owner)
	if not r.interrupted and (r.both_lose or r.loser_uid == uid) and r.valor_saved_uid != uid:
		alive -= 1
	if r.revive[side] and alive < view.players[owner].creature_uids.size():
		alive += 1
	return alive


## Когда обычная политика собиралась пасовать, не забывать послебоевое спасение.
## Оно должно дать ещё одного живого союзника без уступки победы/размена сопернику.
## Скрытые ID не нужны: действующий эффект Копии/Возрождения берётся из PowerCalc.
func _choose_revival(view: MatchState, preview: BattleResult, cards: Array[StringName], side: int) -> StringName:
	var own_before: int = _alive_after(view, preview, side)
	var foe_before: int = _alive_after(view, preview, 1 - side)
	if foe_before == 0 and own_before > 0:
		return &"" # матч уже выигрывается без траты карты
	for id in cards:
		var card := CardDB.card(id)
		if card.effect_id not in [&"revive", &"copy"]:
			continue
		var after := _with_card(view, preview, id, side)
		if after.revive[side] and _alive_after(view, after, side) > own_before and _alive_after(view, after, 1 - side) <= foe_before:
			return id
	return _choose_postbattle(view, preview, cards, side)


## Полезные последствия без немедленного выигрыша силы: резерв, отзыв союзника и следующий ход.
func _choose_postbattle(view: MatchState, preview: BattleResult, cards: Array[StringName], side: int) -> StringName:
	var uid: int = preview.attacker_uid if side == 0 else preview.defender_uid
	var owner: int = view.creatures[uid].owner
	for id in cards:
		var effect: StringName = CardDB.card(id).effect_id
		if effect not in [&"gale_call", &"light_reserve", &"shadow_triumph", &"flame_toll"]:
			continue
		var after := _with_card(view, preview, id, side)
		if _alive_after(view, after, side) < _alive_after(view, preview, side) or (_margin(preview, side) > 0.0 and _margin(after, side) <= 0.0):
			continue
		if _alive_after(view, after, 1 - side) == 0 or _alive_after(view, after, side) == 0:
			continue # нет следующего хода, на котором использовать преимущество
		if after.reserve_cards[side] != &"" and preview.reserve_cards[side] == &"":
			return id
		if after.ordinary and after.winner_uid == uid and after.called_uids[side] >= 0 and preview.called_uids[side] < 0:
			return id
		if after.ordinary and after.loser_uid == uid and after.valor_saved_uid != uid and after.triumph[side] and not preview.triumph[side] and not after.revive[side]:
			return id
		# Пошлина без стартовой силы нужна до возможных ответов, а не после их исчерпания.
		if effect == &"flame_toll" and _margin(preview, side) > 0.0 and _margin(preview, side) <= 120.0 and _foe_plays_left(view, preview, side, true) > 0:
			return id
	return &""


## Прикрепить способность вне боя: moment &"after_landing" (существо uid встало на пустые ворота) или &"pre_throw".
## NORMAL/HARD после приземления прикрепляют самую дешёвую карту, которая снимает угрозу атаки на эти ворота.
## До броска ИИ не играет: в бою та же карта сильнее (видно ворота и ответ соперника). &"" — пас.
## «Попутный шквал» (все уровни): перелететь к слабейшему стоящему сопернику, если бой там выгоден
## (Новичок — при любом перевесе и через раз, Боец — перевес > 40, Мастер — > 60).
func choose_attach(view: MatchState, uid: int, legal: Array, moment: StringName = &"after_landing") -> StringName:
	if moment != &"after_landing" or legal.is_empty():
		return &""
	var c: CreatureState = view.creatures[uid]
	if c.slot < 0:
		return &""
	for id in legal:
		var gc: CardDef = CardDB.card(StringName(id))
		if CardEffects.is_effect(gc, &"gust"):
			var target: int = PowerCalc.gust_target(view, player)
			if target >= 0:
				if difficulty == Difficulty.HARD:
					# Тот же прогноз атаки, что у обычного броска: открытие чужих
					# ворот и возможные ответы важнее нейтрального перевеса +100.
					# Шквал уже потрачен и прикреплён; исходный слот освобождён.
					var trial := view.duplicate_full()
					trial.slots[c.slot].occupant_uid = -1
					trial.creatures[uid].slot = -1
					trial.players[player].ability_hand.erase(StringName(id))
					trial.creatures[uid].attached.append([trial.play_stamp, StringName(id)])
					trial.play_stamp += 1
					if _score(trial, uid, trial.creatures[target].slot) >= 900.0:
						return StringName(id)
					continue
				var r: BattleResult = PowerCalc.compute_seq(view, uid, target, view.creatures[target].slot, [[0, StringName(id)]])
				var need: float = [0.0, 40.0, 60.0][difficulty]
				if _margin(r, 0) > need and (difficulty != Difficulty.EASY or _rng.randf() < 0.5):
					return StringName(id)
	# Мастер защитных карт заранее не прикрепляет: прикреплённая карта видна сопернику, тратится, даже если атаки
	# не будет, и в бою слабее ответа в обмене (по симуляции +2 %)
	if difficulty != Difficulty.NORMAL:
		return &""
	if _exposure(view, uid, c.slot) <= 0.0:
		return &""
	var cards: Array[StringName] = []
	for id in legal:
		if not CardEffects.is_instant(CardDB.card(StringName(id))):
			cards.append(StringName(id))
	cards.sort_custom(_cheaper)
	for id in cards:
		if _exposure(view, uid, c.slot, id) <= 0.0:
			return id
	return &""


# ---------------------------------------------------------------- внутреннее

## Предпросмотр боя, если сторона side сыграет id следующей картой обмена.
func _with_card(view: MatchState, preview: BattleResult, id: StringName, side: int) -> BattleResult:
	var owner: int = view.creatures[preview.attacker_uid if side == 0 else preview.defender_uid].owner
	var target := _best_ability_target(view, id, owner, _ability_targets(view, preview, id, owner))
	return PowerCalc.compute_with(view, preview.attacker_uid, preview.defender_uid, preview.slot, preview.battle_plays, side, id, [preview.ability_count(0), preview.ability_count(1)], target)


## Цель передаётся контроллеру явно; список контроллера имеет приоритет над локальным прогнозом.
func choose_ability_target(view: MatchState, preview: BattleResult, id: StringName, legal_targets: Array = []) -> Dictionary:
	var targets: Array = legal_targets if not legal_targets.is_empty() else _ability_targets(view, preview, id, player)
	return _best_ability_target(view, id, player, targets)


func _ability_targets(view: MatchState, preview: BattleResult, id: StringName, owner: int) -> Array:
	var out: Array = []
	var card := CardDB.card(id)
	if card == null or preview == null:
		return out
	if card.effect_id == &"gale_call":
		for uid in PowerCalc.support_targets(view, owner, [preview.attacker_uid, preview.defender_uid]):
			out.append({"target_uid": uid})
	elif card.effect_id == &"light_reserve":
		for used in PowerCalc.reserve_targets(view, owner, preview.plays, 0 if view.creatures[preview.attacker_uid].owner == owner else 1):
			out.append({"target_card": used})
	return out


func _best_ability_target(view: MatchState, id: StringName, owner: int, targets: Array) -> Dictionary:
	if targets.is_empty():
		return {}
	var best: Dictionary = targets[0]
	var best_score := -INF
	for target in targets:
		var score := 0.0
		if target.has("target_uid"):
			# Сильного союзника выгоднее оставить защищать ворота; слабого вывести из риска.
			score = -float(PowerCalc.base_power(view, int(target.target_uid)))
		elif target.has("target_card"):
			var card := CardDB.card(StringName(target.target_card))
			score = float(view.players[owner].ability_cooldown.get(StringName(target.target_card), 0)) * 100.0
			if card != null:
				score += float(card.params.get("amount", 0))
		if score > best_score:
			best_score = score
			best = target
	return best.duplicate(true)


## Перевес стороны side (ничья — в пользу защитника: атакующему нужен перевес > 0).
## «Отлив» (боя нет) — чуть лучше ничьей для обоих; оба выбывают: ворота «Предел»/«Обоюдный удар» — нейтрально,
## «Общая бездна» — спасение для того, кто проигрывал, и беда для того, кто выигрывал.
## «Трон сумрака» и «Предел» решают бой без сравнения сил.
func _margin(r: BattleResult, side: int) -> float:
	if r.interrupted:
		return 0.25
	var m: float = float(r.powers[0] - r.powers[1])
	var raw: float = m if side == 0 else -m + 0.5  # защитник выигрывает и при равенстве
	if r.both_lose:
		if r.gate_effect == &"clash" or r.gate_effect == &"limit":
			return -0.1
		return 0.25 if raw <= 0.0 else -60.0
	if r.winner_uid >= 0 and (r.auto_win or r.gate_effect == &"limit"):
		var won: bool = r.winner_uid == (r.attacker_uid if side == 0 else r.defender_uid)
		if won != (raw > 0.0):
			return 200.0 if won else -200.0
	return raw


## Сколько карт ещё может сыграть соперник в этом бою (0, если ему запрещены способности или он спасовал
## и мой пас решает бой). after_play — ответ на мою карту: пас соперника тогда не мешает.
func _foe_plays_left(view: MatchState, preview: BattleResult, side: int, after_play: bool = false) -> int:
	var foe: int = 1 - side
	if (preview.passed[foe] and not after_play) or (preview.silenced[foe] and not PowerCalc.reactive_allowed(preview, foe)):
		return 0
	var used: int = preview.ability_count(foe)
	var foe_player: int = view.creatures[preview.defender_uid if foe == 1 else preview.attacker_uid].owner
	return mini(view.players[foe_player].ability_hand.size(), MatchController.MAX_BATTLE_ABILITIES - used)


func _my_plays_left(view: MatchState, preview: BattleResult, side: int) -> int:
	var used: int = preview.ability_count(side)
	return mini(view.players[player].ability_hand.size(), MatchController.MAX_BATTLE_ABILITIES - used)


func _cost_rank(id: StringName) -> int:
	var c: CardDef = CardDB.card(id)
	if c == null:
		return 99
	var k: int = ABILITY_COST_ORDER.find(String(c.effect_id))
	if k < 0:
		return 98
	return k


func _cheaper(a: StringName, b: StringName) -> bool:
	return _cost_rank(a) < _cost_rank(b)


## Перемешивание по своему rng (детерминированно).
func _shuffle(arr: Array[StringName]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var t: StringName = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _candidates(view: MatchState) -> Array[int]:
	var ready: Array[int] = []
	for uid in view.players[player].creature_uids:
		var c: CreatureState = view.creatures[uid]
		if c.alive and c.slot < 0 and not c.used:
			ready.append(uid)
	if ready.is_empty():
		for uid in view.players[player].creature_uids:
			var c2: CreatureState = view.creatures[uid]
			if c2.alive and c2.slot >= 0:
				ready.append(uid)
	return ready


## Запоминать свои доступные карты при каждом решении, включая поздний добор.
func _remember_gates(view: MatchState) -> void:
	for id in view.players[player].arena_hand:
		_my_gates[String(id)] = true
	for s in view.slots:
		if s.has_card and s.card_owner == player and s.card_id != &"":
			_my_gates[String(s.card_id)] = true


## Доля ловушек среди неизвестных ворот: старт по классам + добор без повторов.
## Захват не хранит прежнего владельца; совпадающий со своими ID остаётся неопределённым.
func _foe_trap_prob(view: MatchState) -> float:
	_remember_gates(view)
	var foe: int = 1 - player
	var known: Dictionary = {}
	for p in range(2):
		for id in view.players[p].captured:
			if not _my_gates.has(String(id)):
				known[id] = true
	var unknown: int = view.players[foe].arena_hand.size()
	for s in view.slots:
		if s.has_card and s.card_owner == foe:
			if s.revealed:
				known[s.card_id] = true
			else:
				unknown += 1
	var groups: Array = _public_card_pool(view, foe, CardDef.Kind.ARENA)
	var counts: Array[int] = _remove_known_cards(groups, known)
	var traps: Dictionary = {}
	for group in groups:
		for id in group:
			if CardEffects.is_gate_trap(CardDB.card(id)):
				traps[id] = true
	return _hidden_card_odds(groups, counts, traps, unknown).share


## Оценка цели: больше — лучше; <= -500 — слот бессмыслен.
## Приоритет: забрать карту со своих ворот; бой с перевесом > 40; своя закрытая карта по атрибуту; свободные ворота.
func _score(view: MatchState, uid: int, slot: int) -> float:
	var c: CreatureState = view.creatures[uid]
	var cdef: CreatureDef = CardDB.creature(c.def_id)
	var s: SlotState = view.slots[slot]
	if not s.has_card:
		return -1000.0
	var occ: int = s.occupant_uid
	if occ == uid:
		return 300.0  # снятое с этих ворот существо просто встанет обратно
	if occ >= 0 and view.creatures[occ].owner == player:
		# свои ворота: перестановка (бой там, где соперник; иначе на пустые ворота) или карта засчитывается
		var foe_slot: int = -1
		var empty_slot: int = -1
		for i in range(view.slots.size()):
			var si: SlotState = view.slots[i]
			if not si.has_card:
				continue
			if si.occupant_uid < 0:
				if empty_slot < 0:
					empty_slot = i
			elif view.creatures[si.occupant_uid].owner != player and foe_slot < 0:
				foe_slot = i
		if foe_slot >= 0:
			return _score(view, uid, foe_slot) - 50.0
		if empty_slot >= 0:
			return 400.0
		return 1500.0
	if occ >= 0:
		# чужая закрытая карта в виде пуста = нейтральная арена (своя карта, в том числе ловушка, учтена)
		var r: BattleResult = PowerCalc.compute(view, uid, occ, slot, &"", &"")
		var planned := _planned_gate_state(view, r)
		if planned != view:
			r = PowerCalc.compute(planned, uid, occ, slot, &"", &"")
		if r.both_lose:
			return 450.0  # размен один на один
		var margin: float = _margin(r, 0)
		var risk: float = 0.0
		if difficulty == Difficulty.HARD:
			# Мастер: ценность исхода с учётом своих карт и вероятного ответа соперника (счёт карт)
			var pw: float = _attack_win_prob(view, uid, occ, slot)
			if s.card_owner != player and s.card_id == &"":
				risk = _foe_trap_prob(view) * TRAP_RISK_PENALTY
				if view.creatures[occ].owner == s.card_owner:
					var guard := _hidden_guard_gate(view, uid, occ, slot)
					if guard != &"":
						pw = 0.5 * pw + 0.5 * _attack_win_prob(view, uid, occ, slot, guard)
			return 300.0 + 900.0 * pw - risk
		if margin > WIN_MARGIN:
			return 1000.0 + margin - risk
		return 300.0 + margin * 0.5 - risk
	var stand: float = 600.0
	if s.card_owner == player:
		var card: CardDef = CardDB.card(s.card_id)
		if difficulty != Difficulty.EASY and CardEffects.is_gate_trap(card):
			return _trap_bait_score(view, uid, card) - _exposure(view, uid, slot)
		stand = 800.0 if _fits(card, cdef) else 650.0
	if difficulty != Difficulty.EASY:
		stand -= _exposure(view, uid, slot)
	return stand


## Проверка следующей предполагаемой карты с учётом бойца и последней своей карты.
func _forecast_legal(view: MatchState, r: BattleResult, id: StringName, side: int, previous: StringName = &"") -> bool:
	if previous != &"":
		r = _with_card(view, r, previous, side)
	var c: CardDef = CardDB.card(id)
	if c == null or CardEffects.moment(c) == &"landing" or r.ability_count(side) >= MatchRules.MAX_BATTLE_ABILITIES or PowerCalc.side_locked(r, side):
		return false
	if bool(c.params.get("reactive", false)):
		if not PowerCalc.reactive_allowed(r, side):
			return false
	elif r.silenced[side]:
		return false
	var fighter: int = r.attacker_uid if side == 0 else r.defender_uid
	var d: CreatureDef = CardDB.creature(view.creatures[fighter].def_id)
	var species: StringName = CardEffects.species_lock(c)
	var attr: int = CardEffects.lock_attr(c)
	if (species != &"" and species != d.species) or (attr >= 0 and attr != d.attribute):
		return false
	if c.effect_id in [&"gale_call", &"light_reserve"] and _ability_targets(view, r, id, view.creatures[fighter].owner).is_empty():
		return false
	if c.effect_id == &"tide_wash" and r.powers[side] >= PowerCalc.base_power(view, fighter):
		return false
	var last: StringName = &""
	for pl in r.plays:
		if int(pl[0]) == side and not r.cancelled_plays.has(pl):
			last = StringName(pl[1])
	if CardEffects.is_fusion(c) and (last == &"" or CardEffects.is_fusion(CardDB.card(last))):
		return false
	if CardEffects.is_effect(c, &"swap_fighter"):
		var spent: int = r.ability_count(side) + 1
		return PowerCalc.swap_candidate(view, view.creatures[fighter].owner, [r.attacker_uid, r.defender_uid], maxi(0, MatchRules.MAX_BATTLE_ABILITIES - spent)) >= 0
	if CardEffects.is_effect(c, &"shift_gate"):
		return PowerCalc.best_gate_swap(view, r.attacker_uid, r.defender_uid, r.slot, r.battle_plays, side) >= 0
	return true


## Мастер: обмен картами по ценности исхода. Варианты — пас или одна карта из cards;
## ценность исхода × (1 − риск ответа _flip_prob), минус цена потраченной карты
## (CARD_COST; карты returns почти бесплатны). Проигрышные варианты не рассматриваются. &"" — пас (или ничего не нашлось).
func _choose_hard(view: MatchState, preview: BattleResult, cards: Array[StringName], side: int) -> StringName:
	var best_id: StringName = &""
	var before_utility := _outcome_utility(view, preview, side)
	var best_v: float = before_utility * (1.0 - _flip_prob(view, preview, side)) if before_utility > 0.0 else 0.0
	for id in cards:
		var r: BattleResult = _with_card(view, preview, id, side)
		var combo := _swap_combo_plan(view, preview, r, id, side)
		if not combo.is_empty():
			var paired: BattleResult = combo.result
			paired.passed = [false, false]
			var pair_value: float = _outcome_utility(view, paired, side) * (1.0 - _flip_prob(view, paired, side)) - float(combo.cost)
			if pair_value > best_v + 0.001:
				best_v = pair_value
				best_id = id
		var utility := _outcome_utility(view, r, side)
		if utility <= 0.0:
			continue
		r.passed = [false, false]  # на карту соперник может ответить, даже если пасовал
		var cost: float = CARD_COST_RETURNS if CardEffects.returns_to_hand(CardDB.card(id)) else CARD_COST + float(personality.card_cost_bias)
		var v: float = utility * (1.0 - _flip_prob(view, r, side)) - cost
		if v > best_v + 0.001:
			best_v = v
			best_id = id
	return best_id


## Только Подмена + одно силовое продолжение: последовательность уже умеет PowerCalc.
## Сдвиг, цели союзников и остальные мгновенные карты требуют иного вида состояния.
## Все продолжения ранжируются без _flip_prob; дорогая оценка нужна только одному лучшему.
func _swap_combo_plan(view: MatchState, initial: BattleResult, swapped: BattleResult, swap_id: StringName, side: int) -> Dictionary:
	if not CardEffects.is_effect(CardDB.card(swap_id), &"swap_fighter") or _my_plays_left(view, initial, side) < 2:
		return {}
	if not _forecast_legal(view, initial, swap_id, side) or swapped.ability_count(side) >= MatchRules.MAX_BATTLE_ABILITIES:
		return {}
	var before_value := _outcome_utility(view, swapped, side)
	if before_value >= 1.0: return {}
	var best: Dictionary = {}
	var best_value := before_value
	var best_margin := -INF
	for id in view.players[player].ability_hand:
		var card := CardDB.card(id)
		if id == swap_id or card == null or CardEffects.is_instant(card) or card.effect_id not in [&"boost", &"fusion_boost", &"gust", &"boost_fix"]:
			continue
		if not _forecast_legal(view, swapped, id, side): continue
		var result := _with_card(view, swapped, id, side)
		var value := _outcome_utility(view, result, side)
		var margin := _margin(result, side)
		if value <= before_value or value < best_value or (is_equal_approx(value, best_value) and margin <= best_margin):
			continue
		var first_cost: float = CARD_COST_RETURNS if CardEffects.returns_to_hand(CardDB.card(swap_id)) else CARD_COST + float(personality.card_cost_bias)
		var second_cost: float = CARD_COST_RETURNS if CardEffects.returns_to_hand(card) else CARD_COST + float(personality.card_cost_bias)
		best = {"id": id, "result": result, "cost": first_cost + second_cost}
		best_value = value
		best_margin = margin
	return best


## Ценность настоящего изменения числа живых, включая спасение обеих сторон.
## Победа в матче важнее локального размена; один флаг победы не гарантирует выбытие.
func _outcome_utility(view: MatchState, r: BattleResult, side: int, outcome_view: MatchState = null) -> float:
	var uid: int = r.attacker_uid if side == 0 else r.defender_uid
	var own: int = view.creatures[uid].owner
	var foe: int = 1 - own
	var resolved_view: MatchState = view if outcome_view == null else outcome_view
	var own_after := _alive_after(resolved_view, r, side)
	var foe_after := _alive_after(resolved_view, r, 1 - side)
	if own_after == 0 or foe_after == 0:
		if own_after == foe_after: return 0.5
		return 1.0 if own_after > 0 else 0.0
	var material: int = (own_after - view.alive_count(own)) - (foe_after - view.alive_count(foe))
	return clampf(0.5 + 0.5 * float(material), 0.0, 1.0)


## Совместимый публичный каталог; содержимое чужой руки не читается.
func _public_card_pool(view: MatchState, foe: int, kind: int) -> Array:
	var el: int = -1
	var species: Array = []
	for u in view.players[foe].creature_uids:
		var d: CreatureDef = CardDB.creature(view.creatures[u].def_id)
		if el < 0:
			el = d.attribute
		if not species.has(d.species):
			species.append(d.species)
	var out: Array = []
	for cls in (CardDB.ABILITY_CLASSES if kind == CardDef.Kind.ABILITY else CardDB.GATE_CLASSES):
		out.append(CardDB.cards_of(kind, cls, el, species))
	return out


func _remove_known_cards(groups: Array, known: Dictionary) -> Array[int]:
	var counts: Array[int] = []
	for group in groups:
		var count: int = 0
		for id in group.duplicate():
			if known.has(id):
				group.erase(id)
				count += 1
		counts.append(count)
	return counts


## Сыгранный ID временно недоступен; другие карты того же класса могли прийти добором.
func _foe_pool(view: MatchState, foe: int) -> Array:
	var groups: Array = _public_card_pool(view, foe, CardDef.Kind.ABILITY)
	var known: Dictionary = {}
	for id in view.players[foe].abilities_used:
		known[id] = true
	_remove_known_cards(groups, known)
	return groups


func _combinations(n: int, k: int) -> float:
	if k < 0 or k > n:
		return 0.0
	var result: float = 1.0
	for i in range(1, mini(k, n - k) + 1):
		result *= float(n - i + 1) / float(i)
	return result


## Вероятностная модель, а не знание выбранной колоды: старт по одному ID каждого класса,
## затем равномерный добор без повторов. Публичны только ID вне руки и её размер.
## Набор уже полученных карт имеет вес произведения численностей его классов:
## столько стартовых троек могло дать тот же набор. Маленький DP суммирует эти веса.
## any — шанс хотя бы одного matching в руке; share — их ожидаемая доля.
func _hidden_card_odds(groups: Array, known_counts: Array[int], matching: Dictionary, hidden: int) -> Dictionary:
	if hidden <= 0:
		return {"any": 0.0, "share": 0.0}
	var total: int = 0
	var hits: int = 0
	for group in groups:
		total += group.size()
		for id in group:
			if matching.has(id):
				hits += 1
	if total <= 0 or hits <= 0:
		return {"any": 0.0, "share": 0.0}
	hidden = mini(hidden, total)
	var weight: Array[float] = []
	var safe: Array[float] = []
	var matched: Array[float] = []
	weight.resize(hidden + 1)
	safe.resize(hidden + 1)
	matched.resize(hidden + 1)
	weight[0] = 1.0
	safe[0] = 1.0
	for g in range(groups.size()):
		var n: int = groups[g].size()
		var used: int = known_counts[g]
		if n + used == 0:
			continue
		var found: int = 0
		for id in groups[g]:
			if matching.has(id):
				found += 1
		var next_weight: Array[float] = []
		var next_safe: Array[float] = []
		var next_matched: Array[float] = []
		next_weight.resize(hidden + 1)
		next_safe.resize(hidden + 1)
		next_matched.resize(hidden + 1)
		for before in range(hidden + 1):
			for k in range(mini(n, hidden - before) + 1):
				var choices: float = float(used + k)
				var w: float = choices * _combinations(n, k)
				var target: int = before + k
				next_weight[target] += weight[before] * w
				next_safe[target] += safe[before] * choices * _combinations(n - found, k)
				next_matched[target] += matched[before] * w
				if n > 0:
					next_matched[target] += weight[before] * w * float(k * found) / float(n)
		weight = next_weight
		safe = next_safe
		matched = next_matched
	if weight[hidden] > 0.0:
		return {"any": clampf(1.0 - safe[hidden] / weight[hidden], 0.0, 1.0), "share": clampf(matched[hidden] / weight[hidden] / float(hidden), 0.0, 1.0)}
	# Изолированный стенд/неполная стартовая рука: равномерная выборка оставшихся ID.
	return {"any": clampf(1.0 - _combinations(total - hits, hidden) / _combinations(total, hidden), 0.0, 1.0), "share": float(hits) / float(total)}


## Мастер: шанс допустимого ответа, переворачивающего бой. Размер скрытой руки и публичные
## использованные ID учитываются; даже сыгранный класс может снова оказаться в руке после добора.
func _flip_prob(view: MatchState, r: BattleResult, side: int) -> float:
	var fs: int = 1 - side
	if r.passed[fs] or _foe_plays_left(view, r, side) <= 0:
		return 0.0
	var fighter: int = r.attacker_uid if fs == 0 else r.defender_uid
	var foe: int = view.creatures[fighter].owner
	var groups: Array = _public_card_pool(view, foe, CardDef.Kind.ABILITY)
	var known: Dictionary = {}
	for id in view.players[foe].abilities_used:
		known[id] = true
	var counts: Array[int] = _remove_known_cards(groups, known)
	var flips: Dictionary = {}
	var setup: Array = []
	for cands in groups:
		for id in cands:
			if not _forecast_legal(view, r, id, fs):
				continue
			var after := _with_card(view, r, id, fs)
			var margin := _margin(after, side)
			if margin <= 0.0:
				flips[id] = true
			elif margin < _margin(r, side) and not CardEffects.is_instant(CardDB.card(id)):
				setup.append({"id": id, "margin": margin, "result": after})
	var hidden: int = view.players[foe].ability_hand.size()
	var single: float = _hidden_card_odds(groups, counts, flips, hidden).any
	if single >= 1.0 or hidden < 2 or _foe_plays_left(view, r, side) < 2 or setup.size() < 2:
		return single
	# Не полный поиск скрытых рук: четыре лучших обычных начала, не более 12 порядков.
	# Пара оценивается при пасе между ответами; наша следующая карта пересчитает прогноз.
	setup.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.margin < b.margin or (is_equal_approx(a.margin, b.margin) and String(a.id) < String(b.id)))
	setup.resize(mini(setup.size(), 4))
	var pair_risk := 0.0
	for first in setup:
		for second in setup:
			if first.id == second.id or not _forecast_legal(view, first.result, second.id, fs):
				continue
			if _margin(_with_card(view, first.result, second.id, fs), side) > 0.0:
				continue
			# P(оба ID и ни одного одиночного flip), через включение-исключение.
			# Максимум одной пары — нижняя оценка; коррелирующие пары не складываем.
			var one := flips.duplicate()
			var two := flips.duplicate()
			var both := flips.duplicate()
			one[first.id] = true
			two[second.id] = true
			both[first.id] = true
			both[second.id] = true
			var extra: float = _hidden_card_odds(groups, counts, one, hidden).any + _hidden_card_odds(groups, counts, two, hidden).any - _hidden_card_odds(groups, counts, both, hidden).any - single
			pair_risk = maxf(pair_risk, extra)
	return clampf(single + pair_risk, 0.0, 1.0)


## Неизвестные обычные ворота: ограниченный осторожный сценарий вместо одного Поля.
## Две дорогие ветки сохраняются; каталог дёшево ранжируется без способностей.
## Это гипотеза риска, а не вероятность выбранного защитником ID.
func _hidden_guard_gate(view: MatchState, uid: int, occ: int, slot: int) -> StringName:
	var foe: int = view.creatures[occ].owner
	var known: Dictionary = {}
	for s in view.slots:
		if s.has_card and s.card_owner == foe and s.revealed:
			known[s.card_id] = true
	var best: StringName = &""
	var worst := INF
	for group in _public_card_pool(view, foe, CardDef.Kind.ARENA):
		for id in group:
			if known.has(id) or CardEffects.is_gate_trap(CardDB.card(id)):
				continue
			var trial := view.duplicate_full()
			trial.slots[slot].card_id = id
			trial.slots[slot].revealed = true
			var margin := _margin(PowerCalc.compute_seq(trial, uid, occ, slot, []), 0)
			if margin < worst:
				worst = margin
				best = id
	return best


## Мастер: ценность атаки uid на occ (0..1 с ценой карты): лучший вариант «без карты» или «одна своя карта».
## первым ходом обмена (см. _choose_hard). gate_id — предполагаемая карта закрытых ворот соперника (&"" — как видно).
func _attack_win_prob(view: MatchState, uid: int, occ: int, slot: int, gate_id: StringName = &"") -> float:
	if gate_id != &"":
		view = view.duplicate_full()
		view.slots[slot].card_id = gate_id
		# Предполагаемое Поле оценивается открытым: закрытая карта не даёт G.
		view.slots[slot].revealed = true
	var r: BattleResult = PowerCalc.compute_seq(view, uid, occ, slot, [])
	var planned := _planned_gate_state(view, r)
	if planned != view:
		view = planned
		r = PowerCalc.compute_seq(view, uid, occ, slot, [])
	var before_utility := _outcome_utility(view, r, 0)
	var best: float = before_utility * (1.0 - _flip_prob(view, r, 0)) if before_utility > 0.0 else 0.0
	for id in view.players[player].ability_hand:
		var c: CardDef = CardDB.card(id)
		if _my_plays_left(view, r, 0) <= 0 or not _forecast_legal(view, r, id, 0):
			continue
		var r2: BattleResult = _with_card(view, r, id, 0)
		var combo := _swap_combo_plan(view, r, r2, id, 0)
		if not combo.is_empty():
			var paired: BattleResult = combo.result
			var pair_value: float = _outcome_utility(view, paired, 0) * (1.0 - _flip_prob(view, paired, 0)) - float(combo.cost)
			best = maxf(best, pair_value)
		var utility := _outcome_utility(view, r2, 0)
		if utility <= 0.0:
			continue
		var cost: float = CARD_COST_RETURNS if CardEffects.returns_to_hand(c) else CARD_COST + float(personality.card_cost_bias)
		best = maxf(best, utility * (1.0 - _flip_prob(view, r2, 0)) - cost)
	return best


## «Поле» стихии существа.
func _field_of(c: CreatureState) -> StringName:
	return StringName("arena_field_" + String(GameData.ATTR_KEYS[CardDB.creature(c.def_id).attribute]))


## Угроза для существа, вставшего на ворота: насколько сильнейший готовый к броску боец соперника
## перебьёт его здесь. Базовая оценка — без карт, отдельно учитывается публичная вероятность
## первого необратимого Сдвига/Подмены до ответа защитника; остальные чужие карты не ищутся.
## Чужая закрытая карта нейтральна в базе, для Сдвига рассматриваются явные гипотезы. 0 — угрозы нет.
## extra — карта, которую защитник прикрепил бы к себе (для choose_attach).
func _exposure(view: MatchState, uid: int, slot: int, extra: StringName = &"") -> float:
	var worst: float = 0.0
	var bp: Array = [[1, extra]] if extra != &"" else []
	var ready: Array[int] = []
	for fu in view.players[1 - player].creature_uids:
		var f: CreatureState = view.creatures[fu]
		if f.alive and f.slot < 0 and not f.used:
			ready.append(fu)
	if ready.is_empty():
		for fu in view.players[1 - player].creature_uids:
			var f: CreatureState = view.creatures[fu]
			if f.alive and f.slot >= 0:
				ready.append(fu)
	for fu in ready:
		var r: BattleResult = PowerCalc.compute_seq(view, fu, uid, slot, bp)
		var planned := _planned_gate_state(view, r)
		if planned != view:
			r = PowerCalc.compute_seq(planned, fu, uid, slot, bp)
		var base: float = _exposure_cost(r)
		# Атакующий отвечает первым. Открытый в базовом прогнозе Алтарь/Глухие
		# не должен задним числом запрещать ему мгновенную карту на закрытых воротах.
		var closed := PowerCalc.compute_seq(view, fu, uid, slot, bp)
		worst = maxf(worst, base + _first_irreversible_exposure(view, closed, base))
	return worst


func _exposure_cost(result: BattleResult) -> float:
	var margin := _margin(result, 0)
	return 150.0 + margin * 0.5 if margin > 0.0 else 0.0


## Дополнительный риск первого ответа: ID руки не читаются. Максимальный ущерб
## публично совместимой мгновенной карты взвешивается вероятностью её наличия.
## Это локальный прогноз, а не гарантия безопасности или поиск цепочек ответов.
func _first_irreversible_exposure(view: MatchState, before: BattleResult, base: float) -> float:
	if _foe_plays_left(view, before, 1) <= 0:
		return 0.0
	var foe: int = view.creatures[before.attacker_uid].owner
	var groups: Array = _public_card_pool(view, foe, CardDef.Kind.ABILITY)
	var known: Dictionary = {}
	for id in view.players[foe].abilities_used:
		known[id] = true
	var counts: Array[int] = _remove_known_cards(groups, known)
	var threats: Dictionary = {}
	var worst: float = base
	for group in groups:
		for id in group:
			var card: CardDef = CardDB.card(id)
			var danger: float = base
			if CardEffects.is_effect(card, &"swap_fighter") and _forecast_legal(view, before, id, 0):
				var swapped := _with_card(view, before, id, 0)
				# Открытие разрешено лишь после замены. Подавление бонуса Подмены
				# не возвращает прежнего бойца и не убирает прикрепления нового.
				var after := _planned_gate_state(view, swapped)
				if after != view:
					swapped = PowerCalc.compute_seq(after, swapped.attacker_uid, swapped.defender_uid, swapped.slot, swapped.battle_plays)
				danger = _exposure_cost(swapped)
			elif CardEffects.is_effect(card, &"shift_gate") and _forecast_shift_fighter(view, before, 0, card):
				danger = _first_shift_exposure(view, before, id)
			if danger > base:
				threats[id] = true
				worst = maxf(worst, danger)
	return (worst - base) * _hidden_card_odds(groups, counts, threats, view.players[foe].ability_hand.size()).any


## Известная открытая цель считается как есть. Для закрытой цели подставляется
## совместимый публичный каталог, а не её настоящий ID; это верхняя оценка ущерба
## при наличии Сдвига, не утверждение о конкретной карте в конкретном слоте.
func _first_shift_exposure(view: MatchState, before: BattleResult, id: StringName) -> float:
	var foe: int = view.creatures[before.attacker_uid].owner
	var worst: float = 0.0
	if _forecast_legal(view, before, id, 0):
		worst = _exposure_cost(_with_card(view, before, id, 0))
	var possible: Array = []
	for group in _public_card_pool(view, foe, CardDef.Kind.ARENA):
		for gate_id in group:
			if not CardEffects.is_gate_trap(CardDB.card(gate_id)):
				possible.append(gate_id)
	for j in range(view.slots.size()):
		var target: SlotState = view.slots[j]
		if j == before.slot or not target.has_card or target.card_owner != foe or target.occupant_uid >= 0 or target.revealed:
			continue
		for gate_id in possible:
			var trial := view.duplicate_full()
			trial.slots[j].card_id = gate_id
			if _forecast_legal(trial, before, id, 0):
				worst = maxf(worst, _exposure_cost(_with_card(trial, before, id, 0)))
	return worst


## Своя ловушка без существа: «Зеркало», «Обоюдный удар», «Предел» — приманка для слабейшего (размен в нашу пользу),
## «Глухие врата» — когда у соперника больше способностей в руке.
func _trap_bait_score(view: MatchState, uid: int, card: CardDef) -> float:
	match String(card.effect_id):
		"mirror", "clash", "limit":
			var rank: int = 0
			var bp: int = PowerCalc.base_power(view, uid)
			for u in ps_uids(view):
				var o: CreatureState = view.creatures[u]
				if o.alive and u != uid and PowerCalc.base_power(view, u) < bp:
					rank += 1
			return 860.0 - rank * 150.0
		"mute":
			var diff: int = view.players[1 - player].ability_hand.size() - view.players[player].ability_hand.size()
			return 700.0 + diff * 40.0
	return 640.0


## Ворота подходят существу: Поле его стихии, Алтарь силы, ворота его вида, Трон сумрака для Тени.
func _fits(card: CardDef, d: CreatureDef) -> bool:
	if card == null or d == null:
		return false
	if CardEffects.field_attr(card) == d.attribute:
		return true
	match String(card.effect_id):
		"owner_power", "web", "funnel":
			return true
		"species_double":
			return CardEffects.species_lock(card) == d.species
		"dusk_throne":
			return d.attribute == Attr.A.SHADOW
	return false
