class_name MatchPresentation
extends Node
## Owns the match's visible sequence, FX, tooltip cache and contextual portraits.
## MatchController remains the rules authority. Input and persistence use signal ports.
const Resources := preload("res://scenes/match_resources.gd")
const State := preload("res://scenes/presentation/match_presentation_state.gd")
const Request := preload("res://scenes/interaction/interaction_request.gd")
const Metrics := preload("res://scenes/performance_metrics.gd")
const HUMAN := 0
const AI_PLAYER := 1
const BALL_Y := 0.36
const THROW_Z := Arena.STEP_Z * 0.5 + Arena.CARD_H * 0.5 + 0.8 * Arena.WORLD
signal input_requested(request: Request)
signal pre_throw_requested
signal runtime_failed(message: String)
signal result_ready(winner: int, reason: StringName)
signal landing_ready(uid: int, slot: int)

var state := State.new()
var resources: Resources
var ctrl: MatchController
var world: Node3D
var cam: CameraRig
var events: EventPlayer
var director: ArenaDirector
var hud: HudUI
var battle_hud: BattleHud
var setup_panel: SetupPanel
var ability_panel: AbilityPanel
var battle_overlay: BattleOverlay
var game_over_ui: GameOverUI
var rng: RandomNumberGenerator
var fighter_portraits: Array[FighterPortrait] = []
var roster_names: Array[String] = ["Игрок", "Соперник"]
var result_suffix := ""
var restart_text := ""
var slot_help: Callable
var creature_help: Callable
var interaction_blocked := true
var finished := false
var arena: Arena:
	get: return resources.arena if resources != null else null
var balls: Dictionary:
	get: return resources.active if resources != null else {}
var fighters: Array[VrmFighter]:
	get: return resources.fighters if resources != null else []
var _tip_signature: Array = []
var _tip_result: Dictionary = {}
var _tip_state_signature: Array = []
var _tip_view: MatchState
var _tip_lines: Dictionary = {}
var _queued_battle_result: BattleResult

func configure(match_resources: Resources, stage_world: Node3D, camera: CameraRig,
		queue: EventPlayer, arena_director: ArenaDirector, match_hud: HudUI,
		powers_hud: BattleHud, setup: SetupPanel, abilities: AbilityPanel,
		results: BattleOverlay, match_result: GameOverUI, random: RandomNumberGenerator) -> void:
	resources = match_resources
	world = stage_world
	cam = camera
	events = queue
	director = arena_director
	hud = match_hud
	battle_hud = powers_hud
	setup_panel = setup
	ability_panel = abilities
	battle_overlay = results
	game_over_ui = match_result
	rng = random
	director.configure(resources,state,world,cam,hud,battle_hud,ability_panel,battle_overlay,rng)
	director.labels_requested.connect(focus_labels)
	director.creature_opened.connect(public_creature_opened)
	director.battle_presented.connect(present_battle_opponent)
	director.battle_cleared.connect(finish_opponent_battle)
	director.landing_ready.connect(func(uid: int, slot: int) -> void: landing_ready.emit(uid,slot))
	ability_panel._panel.visibility_changed.connect(opponent_panel_layout)
	hud.battle_mode_changed.connect(func(_on: bool) -> void: opponent_panel_layout())
	battle_hud.effect_visibility_changed.connect(hud.set_battle_event_visible)

## Career uses the controller's PowerCalc snapshot, ordinary decks use catalog definitions.
func bind_controller(controller: MatchController, runtime_power: bool = false) -> void:
	ctrl = controller
	if is_instance_valid(director): director.bind_controller(controller)
	state.definitions.clear()
	state.owners.clear()
	_tip_signature.clear()
	_tip_state_signature.clear()
	_tip_lines.clear()
	if ctrl == null: return
	var view: MatchState = ctrl.get_view(HUMAN)
	for side in 2:
		for uid in view.players[side].creature_uids:
			var creature: CreatureState = view.creature(uid)
			var definition := CardDB.creature(creature.def_id)
			if definition == null: continue
			if runtime_power:
				definition = definition.duplicate() as CreatureDef
				definition.base_power = PowerCalc.base_power(view,uid)
			state.definitions[uid] = definition
			state.owners[uid] = creature.owner

func set_roster_names(player: String, opponent: String) -> void:
	roster_names.assign([player,opponent])

func set_result_context(suffix: String, restart: String = "") -> void:
	result_suffix = suffix
	restart_text = restart

func set_interaction_blocked(blocked: bool) -> void:
	interaction_blocked = blocked

func set_finished(value: bool) -> void:
	finished = value

## Keep resource lease ownership in MatchResources; only visible match nodes are retired here.
func clear() -> void:
	interaction_blocked = true
	finished = true
	if is_instance_valid(director) and is_instance_valid(director.effects):
		director.effects.clear()
	clear_match_portraits()
	for node in state.card_nodes.values():
		if is_instance_valid(node): node.queue_free()
	state.card_nodes.clear()
	state.active_ball = null
	state.battle_uids.clear()
	_queued_battle_result = null
	_tip_signature.clear()
	_tip_state_signature.clear()
	_tip_lines.clear()

func present_match_roster() -> void:
	bind_match_portraits()
	hud.set_hint("Orbstrike")
	director.play_match_music()
	var view: MatchState = ctrl.get_view(HUMAN)
	var cols: Array = [[], []]
	var elems: Array = [[], []]
	for p in range(2):
		var idx := 0
		for uid in view.players[p].creature_uids:
			cols[p].append(VisualUtil.attr_color(creature_def(uid).attribute))
			elems[p].append(creature_def(uid).attribute)
			state.pip_indices[uid] = idx
			idx += 1
	hud.setup_plates(cols[0], cols[1], elems)
	hud.set_names(roster_names[0], roster_names[1])
	hud.set_captures(0, 0)

func bind_match_portraits() -> void:
	for side in fighters.size():
		var portrait := FighterPortrait.new()
		add_child(portrait)
		portrait.bind(fighters[side],side)
		fighter_portraits.append(portrait)
		hud.set_portrait(side,portrait.get_texture())
		portrait.watch_consumer(hud.portrait_consumer(side),hud)


## В бою остаются видимыми только два участника.

func focus_labels(uids: Array) -> void:
	state.label_focus = uids.duplicate()
	for u in balls.keys():
		var b: CreatureBall = balls[u]
		b.set_label_allowed(false)
		b.visible = uids.size() < 2 or uids.has(u)


## 3D-эффект способности у своего существа (и у соперника, если карта бьёт по нему).

func ability_fx(player: int, def: CardDef) -> void:
	if def == null or state.battle_uids.size() != 2:
		return
	var mine: int = state.battle_uids[0] if owner_of(state.battle_uids[0]) == player else state.battle_uids[1]
	var foe: int = state.battle_uids[1] if mine == state.battle_uids[0] else state.battle_uids[0]
	var mb: CreatureBall = balls.get(mine)
	var fb: CreatureBall = balls.get(foe)
	if mb == null:
		return
	var h: float = Arena.FIG_H * 0.7
	var r: float = Arena.FIG_W * 0.32
	var base: Vector3 = mb.global_position - Vector3(0, CreatureBall.RADIUS, 0)
	var foe_base: Vector3 = fb.global_position - Vector3(0, CreatureBall.RADIUS, 0) if fb != null else base
	var cls: StringName = CardDB.card_class(def)
	var eff := String(def.effect_id)
	# Одна карта — один короткий обмен: движение, ответ, затем новое число силы.
	if eff in ["negate", "cap_own_base", "aloft"]:
		mb.ability_pulse()
	elif eff in ["siphon", "strip", "reset_base", "weaken_mark", "drain", "scorch", "radiance", "eclipse", "pact", "doom"]:
		if is_instance_valid(fb) and mb.is_figure_shown() and fb.is_figure_shown():
			mb.counter_lunge(fb.global_position)
			if not await director.wait_for_strike(mb, fb):
				return
			director.play_strike(mb, fb, 0.72)
			fb.take_hit(VisualUtil.attr_color(creature_def(mine).attribute).lightened(0.2))
		else:
			mb.ability_pulse()
	else:
		mb.ability_pulse()
	if CardEffects.is_fusion(def):
		var tc := UiTheme.FUSION_GLOW
		VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), tc, r * 2.2, 0.6)
		get_tree().create_timer(0.2).timeout.connect(func() -> void: VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), tc, r * 3.0, 0.7))
		VisualUtil.spiral(world, base, tc, h, r, 1.0)
	elif cls == &"red":
		var lock: int = CardEffects.lock_attr(def)
		var ec: Color = VisualUtil.attr_color(lock if lock >= 0 else creature_def(mine).attribute).lightened(0.25)
		VisualUtil.light_pillar(mb, Vector3(0, -CreatureBall.RADIUS, 0), ec, h * 1.8, r * 0.9, 0.9)
		VisualUtil.spiral(world, base, ec, h * 1.2, r * 1.2, 1.1)
		VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), ec, r * 3.0, 0.7)
		if eff in ["drain", "scorch", "radiance", "eclipse", "pact", "doom"]:
			VisualUtil.burst(world, foe_base + Vector3(0, h * 0.5, 0), Color(0.8, 0.15, 0.2), Arena.WORLD * 0.7)
		if eff in ["purge_gate", "eclipse", "shift_gate"]:
			gate_fx(base, foe_base)
	elif cls == &"blue":
		var bc: Color = VisualUtil.attr_color(CardEffects.lock_attr(def)).lightened(0.3) if CardEffects.lock_attr(def) >= 0 else Color(1.0, 0.8, 0.35)
		VisualUtil.spiral(world, base, bc, h * 1.1, r, 1.0)
		VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), bc, r * 2.5, 0.6)
	else:
		var gc := UiTheme.SPECIES_GLOW
		match eff:
			"negate", "cap_own_base":
				VisualUtil.dome(world, base, gc, r * 1.9, 1.6)
			"nullify_gate", "aloft":
				gate_fx(base, foe_base)
			"siphon", "strip", "reset_base", "weaken_mark", "scorch":
				VisualUtil.spiral(world, foe_base, Color(0.85, 0.15, 0.2), h, r, 1.0)
				VisualUtil.burst(world, foe_base + Vector3(0, h * 0.5, 0), Color(0.8, 0.1, 0.15), Arena.WORLD * 0.7)
				if eff == "reset_base":
					VisualUtil.spiral(world, base, gc, h, r, 1.0)
			_:
				VisualUtil.spiral(world, base, gc, h, r, 1.0)
				VisualUtil.ring_wave(world, base + Vector3(0, 0.1, 0), gc, r * 2.5, 0.7)


## Вспышка на воротах между бойцами (отмена или сдвиг ворот).

func gate_fx(base: Vector3, foe_base: Vector3) -> void:
	var cardpos: Vector3 = (base + foe_base) * 0.5
	VisualUtil.ring_wave(world, cardpos + Vector3(0, 0.1, 0), Color(0.9, 0.95, 1.0), Arena.CARD_H * 0.9, 0.8)
	VisualUtil.burst(world, cardpos + Vector3(0, 0.5, 0), Color(0.8, 0.9, 1.0), Arena.WORLD)


## Крик существа по uid (с задержкой, чтобы совпасть с анимацией).

func cry(uid: int, kind: String, delay: float = 0.0, db: float = -1.0) -> void:
	var d: CreatureDef = creature_def(uid)
	if d != null:
		SoundFx.i().cry(d.id, kind, delay, db)


## Рука способностей игрока внизу справа.

func refresh_hand() -> void:
	if ctrl == null:
		return
	ability_panel.set_hand(ctrl.get_view(HUMAN).players[HUMAN].ability_hand)
	setup_panel.set_hand(ctrl.get_view(HUMAN).players[HUMAN].arena_hand)

func clear_match_portraits() -> void:
	if is_instance_valid(hud):
		if is_instance_valid(hud.opponent_panel): hud.opponent_panel.reset()
		if is_instance_valid(hud.own_panel): hud.own_panel.reset()
	state.own_uid = -1
	state.own_power = -1
	for portrait in fighter_portraits:
		portrait.fighter = null
		portrait.render_target_update_mode = SubViewport.UPDATE_DISABLED
		portrait.queue_free()
	fighter_portraits.clear()
	if is_instance_valid(hud):
		for side in 2: hud.set_portrait(side,null)

func creature_def(uid: int) -> CreatureDef:
	return state.definitions.get(uid) as CreatureDef

func owner_of(uid: int) -> int:
	return int(state.owners.get(uid, -1))

func cname(uid: int) -> String:
	var d: CreatureDef = creature_def(uid)
	if d == null:
		return "Существо #%d" % uid
	return d.display_name

func names_for(r: BattleResult) -> Dictionary:
	var out: Dictionary = {}
	for u in [r.attacker_uid, r.defender_uid]:
		var d: CreatureDef = creature_def(u)
		if d != null:
			out[u] = "%s (%s)" % [d.display_name, VisualUtil.attr_name(d.attribute)]
	return out

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func tip_at(mp: Vector2) -> Dictionary:
	if ctrl == null or interaction_blocked or finished or hud._battle or cam == null or not is_instance_valid(arena) or events.is_busy() or director.flying:
		return {}
	Metrics.add("hover_queries")
	var state_signature: Array = [ctrl.get_instance_id(), ctrl.event_log.size(), ctrl.action_trace.size(), ctrl.get_phase(), ctrl.get_active_player()]
	if state_signature != _tip_state_signature:
		_tip_state_signature = state_signature
		_tip_view = ctrl.get_view(HUMAN)
		_tip_lines.clear()
		Metrics.add("hover_snapshots")
	# Rules append to event_log after each complete mutation. Camera/projection,
	# viewport and every actor's actual input geometry also invalidate the cache,
	# so a stationary pointer still follows moving creatures and camera tweens.
	var signature: Array = [state_signature, mp, cam.get_camera_transform(),
		cam.get_camera_projection(), get_viewport().get_visible_rect(), arena.global_transform,
		arena.location_id]
	for uid in balls:
		var ball: CreatureBall = balls[uid]
		if not is_instance_valid(ball):
			signature.append([uid, null])
		else:
			signature.append([uid, ball.get_instance_id(), ball.visible, ball.global_transform, ball.figure_height()])
	if signature == _tip_signature:
		Metrics.add("hover_cache_hits")
		return _tip_result
	_tip_signature = signature
	var begin := Time.get_ticks_usec()
	_tip_result = tip_at_uncached(mp, _tip_view)
	Metrics.add("hover_rebuilds")
	Metrics.add("hover_rebuild_usec", Time.get_ticks_usec() - begin)
	return _tip_result

func tip_at_uncached(mp: Vector2, cached_view: MatchState = null) -> Dictionary:
	var view: MatchState = cached_view if cached_view != null else ctrl.get_view(HUMAN)
	# существа и шар перед броском
	var best_uid := -1
	var best_d := 1e9
	var best_rect := Rect2()
	for u in balls.keys():
		var b: CreatureBall = balls[u]
		if b == null or not is_instance_valid(b) or not b.visible:
			continue
		var base: Vector3 = b.global_position - Vector3(0, CreatureBall.RADIUS, 0)
		var on_field: bool = view.creature(u).slot >= 0
		var h: float = b.figure_height() if on_field else CreatureBall.RADIUS * 2.0
		var top: Vector3 = base + Vector3(0, h, 0)
		if cam.is_position_behind(base) or cam.is_position_behind(top):
			continue
		var p0: Vector2 = cam.unproject_position(base)
		var p1: Vector2 = cam.unproject_position(top)
		var rad: float = maxf(24.0, p0.distance_to(p1) * 0.22)
		var d: float = Geometry2D.get_closest_point_to_segment(mp, p0, p1).distance_to(mp)
		if d < rad and d / rad < best_d:
			best_d = d / rad
			best_uid = u
			best_rect = Rect2(p0, Vector2.ZERO).expand(p1).grow(rad)
	if best_uid >= 0:
		var key := "c%d" % best_uid
		if cached_view == null: return {"key": key, "lines": resolved_creature_help(best_uid, view), "rect": best_rect}
		if not _tip_lines.has(key): _tip_lines[key] = resolved_creature_help(best_uid, view)
		return {"key": key, "lines": _tip_lines[key], "rect": best_rect}
	# карты ворот: попадание в проекцию прямоугольника карты
	for i in range(view.slots.size()):
		var sl: SlotState = view.slots[i]
		var c: Vector3 = arena.slot_position(i)
		var hw: float = Arena.CARD_W * 0.5
		var hh: float = Arena.CARD_H * 0.5
		var poly := PackedVector2Array()
		var ok := true
		for corner in [Vector3(-hw, 0, -hh), Vector3(hw, 0, -hh), Vector3(hw, 0, hh), Vector3(-hw, 0, hh)]:
			var wp: Vector3 = c + corner
			if cam.is_position_behind(wp):
				ok = false
				break
			poly.append(cam.unproject_position(wp))
		if not ok or not Geometry2D.is_point_in_polygon(mp, poly):
			continue
		var key := "s%d:%s" % [i, str(sl.card_id) + str(sl.revealed)]
		var lines: Array
		if cached_view != null:
			if not _tip_lines.has(key): _tip_lines[key] = resolved_slot_help(i, sl, view)
			lines = _tip_lines[key]
		else: lines = resolved_slot_help(i, sl, view)
		if not lines.is_empty():
			var sr := Rect2(poly[0], Vector2.ZERO)
			for q in poly:
				sr = sr.expand(q)
			return {"key": key, "lines": lines, "rect": sr}
	return {}

func invalidate_tooltips() -> void:
	_tip_signature.clear()
	_tip_state_signature.clear()
	_tip_lines.clear()

func resolved_slot_help(index: int, slot: SlotState, view: MatchState) -> Array:
	return slot_help.call(index,slot,view) if slot_help.is_valid() else slot_tip(index,slot,view)

func resolved_creature_help(uid: int, view: MatchState) -> Array:
	return creature_help.call(uid,view) if creature_help.is_valid() else creature_tip(uid,view)

func slot_tip(i: int, sl: SlotState, view: MatchState) -> Array:
	if not sl.has_card:
		if ctrl.get_phase() == MatchController.Phase.SETUP and ctrl.get_active_player() == HUMAN and ctrl.legal_setup_slots().has(i):
			return ["Свободное место", "Выкладка ворот", UiTheme.GOLD, "Сюда можно положить карту ворот: рядом с уже лежащими картами.", "Бросок на пустое место — промах.", "", ""]
		return []
	var mine: bool = sl.card_owner == HUMAN
	var occ := ""
	if sl.occupant_uid >= 0:
		occ = "На воротах стоит: %s (%s)." % [cname(sl.occupant_uid), "ваше" if owner_of(sl.occupant_uid) == HUMAN else "существо соперника"]
	var def: CardDef = CardDB.card(sl.card_id)
	if def == null:
		return ["Закрытые ворота соперника", "Ворота · рубашкой вверх", UiTheme.GOLD_DIM,
			"Владелец может открыть карту во время боя. Пока ворота закрыты, их бонусы и ловушки не действуют.", "Закрытая карта соперника.", "", occ]
	var lines: Array = UiTheme.card_help(def)
	if not sl.revealed:
		lines[1] = "%s · ваша закрытая карта" % lines[1] if mine else lines[1]
		lines[5] = "Соперник не видит эту карту до боя. " + str(lines[5]) if mine else lines[5]
	lines[6] = (str(lines[6]) + "\n" + occ).strip_edges() if occ != "" else lines[6]
	return lines

func creature_tip(uid: int, view: MatchState) -> Array:
	var d: CreatureDef = creature_def(uid)
	var cs: CreatureState = view.creature(uid)
	var lines: Array = UiTheme.creature_help(d)
	var mine: bool = owner_of(uid) == HUMAN
	lines[1] = "%s · %s" % [lines[1], "ваше существо" if mine else "существо соперника"]
	var power: int = d.base_power
	var extra: Array[String] = ["Базовая сила: %d" % power]
	if cs.slot >= 0:
		var sl: SlotState = view.slots[cs.slot]
		var cd: CardDef = CardDB.card(sl.card_id)
		# сила с воротами: бонус открытой карты (те же правила, что в PowerCalc, роль защитника)
		if sl.revealed and cd != null:
			var gate: int = PowerCalc.gate_bonus_for(view, uid, cs.slot)
			if gate != 0:
				extra.append("Сила %d %s %d ворота = %d" % [power, "+" if gate > 0 else "−", absi(gate), power + gate])
			else:
				extra.append("Сила %d (ворота бонуса не дают)" % power)
		else:
			extra.append("Сила %d (ворота закрыты)" % power)
		extra.append("Стоит на воротах №%d%s" % [cs.slot + 1, (": «%s»" % cd.display_name) if cd != null else " (карта закрыта)"])
	else:
		extra.append("Выберите подсвеченные ворота для броска сферы" if mine else "Шар соперника")
	for mk in cs.marks:
		extra.append("Метка «%s»: %s в следующем бою" % [card_name(StringName(mk.get("src", ""))),
			("сила ровно %d" % int(mk["fix"])) if mk.has("fix") else "%+d" % int(mk.get("delta", 0))])
	if not cs.attached.is_empty():
		var names: Array[String] = []
		for a in cs.attached:
			names.append("«%s»" % card_name(StringName(a[1])))
		extra.append("Прикреплено: " + ", ".join(names))
	lines[6] = "\n".join(extra)
	return lines


## Строка в ленту событий — в порядке очереди анимаций.

func log_event(text: String, c: Color = UiTheme.TEXT) -> void:
	events.push(func() -> void: hud.log_event(text, c))

func say(player: int, you: String, foe: String) -> String:
	return you if player == HUMAN else foe

func on_arena_card_placed(player: int, slot: int) -> void:
	log_event(say(player, "Вы кладёте карту ворот", "Соперник кладёт карту ворот"))
	events.push(anim_card_placed.bind(player, slot))

func on_creature_selected(player: int, uid: int, recalled: bool) -> void:
	log_event("%s: %s" % [say(player, "Вы бросаете", "Соперник бросает"), cname(uid)])
	events.push(anim_selected.bind(player, uid, recalled))

func on_creature_returned(uid: int, reason: StringName) -> void:
	if reason == &"miss":
		log_event("Промах: %s" % cname(uid), Color(1.0, 0.7, 0.6))
	elif reason == &"breakaway":
		log_event("Отрыв: %s снова готов к броску" % cname(uid), UiTheme.GOLD)
	events.push(anim_returned.bind(uid, reason))

func on_creature_stood(uid: int, slot: int) -> void:
	log_event("%s встаёт на ворота" % cname(uid))
	events.push(anim_stood.bind(uid, slot))

func on_battle_started(slot: int, attacker_uid: int, defender_uid: int) -> void:
	var pre: BattleResult = ctrl.get_battle_preview()
	var pw: Array = [pre.powers[0], pre.powers[1]] if pre != null else []
	var mo: Array = [pre.momentum[0], pre.momentum[1]] if pre != null else [0, 0]
	log_event("Бой: %s против %s" % [cname(attacker_uid), cname(defender_uid)], UiTheme.GOLD)
	events.push(anim_battle_started.bind(slot, attacker_uid, defender_uid, pw, mo))
	if pre != null:
		events.push(battle_hud.set_chain.bind(pre.plays.duplicate(true), [false, false], -1, pre.cancelled_plays.duplicate(true), pre.ability_counts.duplicate(), battle_blocks(pre)))  # прикреплённые карты

func on_card_revealed(slot: int, card_id: StringName) -> void:
	var owner: int = ctrl.get_view(HUMAN).slots[slot].card_owner
	var preview := ctrl.get_battle_preview()
	var powers: Array = preview.powers.duplicate() if preview != null else []
	events.push(anim_card_revealed.bind(slot, card_id, owner, powers))

func on_ability_played(player: int, card_id: StringName) -> void:
	refresh_hand()
	state.stats["abilities"][player] += 1
	log_event("%s «%s»" % [say(player, "Вы играете", "Соперник играет"), card_name(card_id)], Color(0.75, 0.6, 1.0))
	var pre: BattleResult = ctrl.get_battle_preview()
	var pw: Array = [pre.powers[0], pre.powers[1]] if pre != null else []
	events.push(anim_ability_msg.bind(player, card_id, false, pw, pre))
	if pre != null:
		events.push(battle_hud.set_chain.bind(pre.plays.duplicate(true), pre.passed.duplicate(), -1, pre.cancelled_plays.duplicate(true), pre.ability_counts.duplicate(), battle_blocks(pre)))

func on_ability_cancelled(player: int, card_id: StringName) -> void:
	events.push(anim_ability_msg.bind(player, card_id, true))

func on_battle_resolved(result: BattleResult) -> void:
	_queued_battle_result = result
	refresh_hand()
	if result.winner_uid < 0:
		var what: String = "Бой прерван: Отлив" if result.interrupted else "Выбывают оба бойца"
		state.stats["battles"].append({"turn": ctrl.get_turn(), "winner": "—", "loser": "%s и %s" % [cname(result.attacker_uid), cname(result.defender_uid)],
			"wp": result.powers[0], "lp": result.powers[1], "mine": false})
		events.push(anim_battle_resolved.bind(result))
		log_event(what, UiTheme.GOLD)
		return
	var win_p: int = owner_of(result.winner_uid)
	var atk_won: bool = result.winner_uid == result.attacker_uid
	var wp: int = result.powers[0 if atk_won else 1]
	var lp: int = result.powers[1 if atk_won else 0]
	state.stats["wins"][win_p] += 1
	state.stats["battles"].append({"turn": ctrl.get_turn(), "winner": cname(result.winner_uid), "loser": cname(result.loser_uid),
		"wp": wp, "lp": lp, "mine": win_p == HUMAN})
	events.push(anim_battle_resolved.bind(result))
	log_event("Побеждает %s (%d : %d)" % [cname(result.winner_uid), wp, lp], Color(0.6, 1.0, 0.6) if win_p == HUMAN else Color(1.0, 0.6, 0.55))

func on_creature_eliminated(uid: int) -> void:
	events.push(anim_remove_ball.bind(uid, true))
	events.push(func() -> void: hud.kill_creature(owner_of(uid), int(state.pip_indices.get(uid, -1))))

func on_card_captured(player: int, slot: int, _card_id: StringName) -> void:
	log_event("%s: ворота захвачены" % say(player, "Вы", "Соперник"), UiTheme.GOLD)
	events.push(anim_captured.bind(player, slot))

func on_turn_started(player: int, turn: int) -> void:
	refresh_hand()
	events.push(anim_turn.bind(player, turn))

func on_ability_attached(player: int, uid: int, card_id: StringName) -> void:
	refresh_hand()
	state.stats["abilities"][player] += 1
	log_event("%s «%s» → %s" % [say(player, "Вы прикрепляете", "Соперник прикрепляет"), card_name(card_id), cname(uid)], Color(0.75, 0.6, 1.0))
	events.push(anim_attached.bind(player, uid, card_id))

func on_gate_thrown(player: int, slot: int, uid: int) -> void:
	log_event("%s: ворота + бросок" % say(player, "Вы", "Соперник"), UiTheme.GOLD)
	events.push(anim_gate_thrown.bind(player, slot, uid))

func on_gate_trap(slot: int, card_id: StringName, effect: StringName) -> void:
	state.stats["traps"] += 1
	log_event("ЛОВУШКА: %s" % card_name(card_id), Color(1.0, 0.45, 0.35))
	events.push(anim_trap.bind(slot, card_id, effect))

func on_momentum_changed(player: int, value: int) -> void:
	events.push(anim_momentum.bind(player, value))

func on_final_round(player: int) -> void:
	if not MatchRules.author_bonuses(ctrl.get_view(HUMAN).ruleset):
		return
	log_event("ФИНАЛЬНЫЙ БОЙ", Color(1.0, 0.45, 0.35))
	events.push(anim_final_round.bind(player))


## Выбывшее существо вернулось в игру (в зону использованных): шарик на плашке снова горит.

func on_creature_revived(uid: int) -> void:
	log_event("%s возвращается в игру" % cname(uid), Color(1.0, 0.95, 0.6))
	events.push(func() -> void:
		var p: int = owner_of(uid)
		state.alive[p] += 1
		refresh_status()
		hud.revive_creature(p, int(state.pip_indices.get(uid, -1)))
		SoundFx.i().play("power_up", -4.0)
		hud.screen_flash(Color(1.0, 0.95, 0.7, 0.3))
		await hud.banner("ВОЗВРАЩЕНИЕ", "%s снова в игре (зона использованных)" % cname(uid), Color(1.0, 0.92, 0.55), 0.8, true))


## Метка на следующий бой: строка в ленте и вспышка у шара.

func on_creature_marked(uid: int, card_id: StringName, mark: Dictionary) -> void:
	var txt: String = "сила ровно %d" % int(mark["fix"]) if mark.has("fix") else "%+d" % int(mark.get("delta", 0))
	log_event("%s: %s в следующем бою («%s»)" % [cname(uid), txt, card_name(card_id)], Color(0.85, 0.75, 1.0))
	events.push(func() -> void:
		var b: CreatureBall = balls.get(uid)
		if b != null and is_instance_valid(b):
			b.ability_pulse()
			var good: bool = mark.has("fix") or int(mark.get("delta", 0)) > 0
			VisualUtil.ring_wave(world, b.global_position - Vector3(0, CreatureBall.RADIUS - 0.1, 0), Color(0.6, 1.0, 0.6) if good else Color(1.0, 0.35, 0.3), Arena.FIG_W * 0.5, 0.5))


## «Вихревая подмена»: прежний боец исчезает, новый появляется на его месте в бою.

func on_fighter_swapped(old_uid: int, new_uid: int, slot: int) -> void:
	log_event("Подмена: %s вместо %s" % [cname(new_uid), cname(old_uid)], Color(0.75, 0.6, 1.0))
	var preview := ctrl.get_battle_preview()
	var powers: Array = preview.powers.duplicate() if preview != null else []
	events.push(anim_fighter_swapped.bind(old_uid, new_uid, slot, powers))

func on_gates_swapped(a: int, b: int) -> void:
	log_event("Сдвиг плит: ворота меняются местами", Color(0.75, 0.6, 1.0))
	events.push(func() -> void:
		var na: ArenaCardNode = state.card_nodes.get(a)
		var nb: ArenaCardNode = state.card_nodes.get(b)
		state.card_nodes.erase(a)
		state.card_nodes.erase(b)
		if na != null:
			state.card_nodes[b] = na
			na.slot = b
			na.create_tween().tween_property(na, "position", arena.slot_position(b), 0.45).set_trans(Tween.TRANS_QUAD)
		if nb != null:
			state.card_nodes[a] = nb
			nb.slot = a
			nb.create_tween().tween_property(nb, "position", arena.slot_position(a), 0.45).set_trans(Tween.TRANS_QUAD)
		cam.shake(0.4, 0.3)
		SoundFx.i().play("card_place")
		await wait(0.55))


## Ворота сгорели без захвата (оба бойца выбыли).

func on_gate_discarded(slot: int, _card_id: StringName) -> void:
	log_event("Ворота сгорают", Color(1.0, 0.6, 0.4))
	events.push(func() -> void:
		var node: ArenaCardNode = state.card_nodes.get(slot)
		state.card_nodes.erase(slot)
		if node == null:
			return
		VisualUtil.burst(world, node.global_position + Vector3(0, 0.3, 0), Color(1.0, 0.5, 0.25), Arena.WORLD * 0.6)
		var tw := node.create_tween()
		tw.tween_property(node, "scale", Vector3(0.01, 0.01, 0.01), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		await tw.finished
		node.queue_free())


## Сыгранные способности вернулись в руку («Второе дыхание», карты камбэка).

func on_abilities_recalled(player: int, card_ids: Array) -> void:
	refresh_hand()
	var names: PackedStringArray = PackedStringArray()
	for id in card_ids:
		names.append(card_name(StringName(id)))
	log_event("%s в руку: %s" % [say(player, "Карты возвращаются", "К сопернику возвращаются"), ", ".join(names)], Color(0.75, 0.6, 1.0))


## Перезарядка: карты, отдыхавшие один бой, снова в руке.

func on_abilities_recharged(player: int, card_ids: Array) -> void:
	refresh_hand()
	var names: PackedStringArray = PackedStringArray()
	for id in card_ids:
		names.append(card_name(StringName(id)))
	log_event("%s: %s" % [say(player, "Перезарядка, снова в руке", "Перезарядка соперника"), ", ".join(names)], Color(0.6, 0.75, 1.0))

func anim_fighter_swapped(old_uid: int, new_uid: int, _slot: int, powers: Array = []) -> void:
	var ob: CreatureBall = balls.get(old_uid)
	var pos: Vector3 = ob.global_position if ob != null else Vector3.ZERO
	var facing: Vector3 = Vector3.ZERO
	if state.battle_uids.size() == 2:
		var foe: int = state.battle_uids[1] if state.battle_uids[0] == old_uid else state.battle_uids[0]
		var fb: CreatureBall = balls.get(foe)
		if fb != null:
			facing = fb.global_position
		state.battle_uids[state.battle_uids.find(old_uid)] = new_uid
	if ob != null:
		await anim_remove_ball(old_uid)
	var nb: CreatureBall = balls.get(new_uid)
	if nb == null:
		nb = spawn_ball(new_uid)
		if nb == null: return
	nb.freeze_at(pos)
	if facing != Vector3.ZERO:
		nb.face_toward(facing)
	director.open_creature(nb)  # выход со стойкой и рёвом (CreatureAnim.appear)
	if powers.is_empty() and _queued_battle_result != null:
		powers = _queued_battle_result.powers
	if powers.size() == 2:
		present_battle_powers(powers)
		battle_hud.set_powers(powers)
	else:
		public_creature_opened(new_uid)
	cry(new_uid, "appear", 0.2)
	VisualUtil.ring_wave(world, pos - Vector3(0, CreatureBall.RADIUS - 0.1, 0), VisualUtil.attr_color(creature_def(new_uid).attribute), Arena.FIG_W * 0.7, 0.55)
	focus_labels(state.battle_uids)
	await read_battle_effect("Вихревая подмена", "%s вступает в бой" % cname(new_uid), side_title(owner_of(old_uid)), cname(old_uid))


## «Сдвиг плит»: карты ворот меняются местами (узлы карт переезжают, существа остаются).

func anim_phase(_phase: int, active_player: int) -> void:
	hud.set_phase(_phase)
	state.active_player = active_player
	refresh_status()

func anim_turn(player: int, turn: int) -> void:
	if player == AI_PLAYER and is_instance_valid(hud.opponent_panel): hud.opponent_panel.feedback("turn")
	for side in fighters.size(): fighters[side].active_turn = side == player
	state.active_player = player
	state.turn = turn
	refresh_status()
	if turn > 0:
		SoundFx.i().play("turn_yours" if player == HUMAN else "turn_opponent", -5.0)

func anim_set_pending(request: Request) -> void:
	input_requested.emit(request)

func anim_attached(player: int, uid: int, card_id: StringName) -> void:
	await director.ability_action(player,card_id,uid)
	cam.overview()
	refresh_hand()
	var b: CreatureBall = balls.get(uid)
	if b != null:
		b.ability_pulse()
		var c: Color = VisualUtil.attr_color(creature_def(uid).attribute).lightened(0.3)
		VisualUtil.ring_wave(world, b.global_position - Vector3(0, CreatureBall.RADIUS - 0.1, 0), c, Arena.FIG_W * 0.6, 0.6)
	await read_battle_effect(card_name(card_id), "Прикреплена к следующему бою существа", side_title(player), cname(uid))
	if player == HUMAN and ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING and state.active_ball != null and not director.flying:
		pre_throw_requested.emit()

func anim_gate_thrown(player: int, _slot: int, uid: int) -> void:
	SoundFx.i().play("card_select")
	hud.set_hint("Ворота + бросок: %s летит на новую карту" % cname(uid))
	await hud.banner("ВОРОТА + БРОСОК", "%s: карта и бросок за один ход" % say(player, "Вы", "Соперник"), UiTheme.GOLD, 0.55)

func anim_trap(slot: int, card_id: StringName, effect: StringName) -> void:
	var sub: String = "Ловушка сработала"
	match effect:
		&"mute":
			sub = "Сопернику владельца способности запрещены"
		&"mirror":
			sub = "Силы бойцов меняются местами"
		&"limit":
			sub = "Кто сильнее 400 — проигрывает"
		&"clash":
			sub = "Оба бойца выбывают"
	SoundFx.i().play("gate_trap", -2.0)
	cam.impact(arena.slot_position(slot) + Vector3(0, Arena.FIG_H * 0.2, 0))
	cam.shake(0.7, 0.4)
	hud.screen_flash(Color(1.0, 0.3, 0.2, 0.35))
	await read_battle_effect(card_name(card_id), sub, "Ворота %d" % (slot + 1), "Бой", Color(1.0, 0.61, 0.46))
	cam.battle_wide()

func anim_momentum(player: int, value: int) -> void:
	if not MatchRules.author_bonuses(ctrl.get_view(HUMAN).ruleset):
		hud.set_momentum(player, 0)
		return
	hud.set_momentum(player, value)
	if value > 0:
		SoundFx.i().play("power_up", -8.0)
		hud.log_event("%s: натиск +%d к силе" % [say(player, "Вы", "Соперник"), value * PowerCalc.MOMENTUM_STEP], Color(1.0, 0.7, 0.3))

func anim_final_round(_player: int) -> void:
	if not MatchRules.author_bonuses(ctrl.get_view(HUMAN).ruleset):
		return
	hud.set_final_round(true)
	SoundFx.i().play("battle_start", 0.0)
	cam.shake(0.8, 0.5)
	hud.screen_flash(Color(1.0, 0.5, 0.3, 0.3))
	await hud.banner("ФИНАЛЬНЫЙ БОЙ", "Остались последние существа: преимущество стихии ×2", Color(1.0, 0.5, 0.25), 1.2, true)

func anim_card_placed(player: int, slot: int) -> void:
	await director.card_placed(player, slot)

func anim_selected(player: int, uid: int, recalled: bool) -> void:
	if player == AI_PLAYER: clear_opponent_panel()
	else: clear_own_panel()
	var b: CreatureBall = balls.get(uid)
	if b == null:
		b = spawn_ball(uid)
		if b == null: return
	elif recalled:
		b.unfreeze()
		b.close_up()
		b.slot = -1
	b.freeze_at(start_pos(player))
	cam.overview()
	focus_labels([])
	state.active_ball = b
	input_requested.emit(Request.make(Request.Kind.LAUNCH,player,uid))
	await wait(0.25)


## Существо уходит в зону использованных: промах, после боя или со своих засчитанных ворот.

func anim_returned(uid: int, reason: StringName) -> void:
	match reason:
		&"miss":
			SoundFx.i().play("miss", -2.0)
			hud.set_hint("Промах: %s уходит в зону использованных" % cname(uid))
		&"gate_won":
			hud.set_hint("Свои ворота: карта засчитана")
		&"lost":
			await anim_remove_ball(uid, true)
			return
	cam.overview()
	focus_labels([])
	await anim_remove_ball(uid)


## Попадание на свои ворота: существо переходит на другие ворота.

func anim_relocated(uid: int, _from: int, to: int) -> void:
	var b: CreatureBall = balls.get(uid)
	hud.set_hint("%s остаётся на воротах" % cname(uid) if _from == to else "%s переходит на другие ворота" % cname(uid))
	if b == null:
		return
	b.slot = to
	var target := arena.slot_position(to) + Vector3(0.0, BALL_Y + 0.02, 0.0)
	b.freeze_at(b.global_position)
	cam.overview()
	var tw := create_tween() # Владелец — матч, а не сохраняемый каталогом шар.
	tw.tween_property(b, "global_position", target + Vector3(0, Arena.FIG_W * 0.4, 0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "global_position", target, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	b.freeze_at(target)

func anim_refilled(player: int) -> void:
	hud.coach("used", "Зона использованных: существа после промаха или боя отдыхают. Когда бросать некого, они все возвращаются в руку.")
	hud.flash("Существа вернулись из зоны использованных" if player == HUMAN else "У соперника вернулись существа")
	await hud.wait_read(1.4)
	hud.clear_flash()

func anim_remove_ball(uid: int, eliminated: bool = false) -> void:
	if uid == state.opponent_uid: clear_opponent_panel()
	if uid == state.own_uid: clear_own_panel()
	var b: CreatureBall = balls.get(uid)
	if b == null:
		return
	SoundFx.i().play("eliminated" if eliminated else "vanish", -2.0 if eliminated else -6.0)
	if eliminated:
		state.alive[owner_of(uid)] -= 1
		refresh_status()
		VisualUtil.burst(world, b.global_position + Vector3(0, Arena.FIG_H * 0.2, 0), creature_def(uid).color, Arena.WORLD * 0.8)
	var retirement := resources.begin_retire(uid)
	if b == state.active_ball:
		state.active_ball = null
	await b.vanish(eliminated)
	resources.finish_retire(retirement)

func anim_stood(uid: int, slot: int) -> void:
	var b: CreatureBall = balls.get(uid)
	if b == null:
		return
	b.slot = slot
	hud.set_hint("%s встаёт на карту" % cname(uid))
	# короткий наезд на фактическую точку остановки, потом кат на облёт
	if cam.mode == CameraRig.Mode.STATIC and not cam.is_overview():
		await wait(0.4)
	var facing := Vector3(0.0, 0.0, -1.0 if owner_of(uid) == HUMAN else 1.0)
	b.hold_landing_pose()
	b.face_toward(b.global_position + facing)
	var orbit_t: float = cam.reveal_orbit(b.global_position - Vector3(0, BALL_Y, 0), b.figure_height(), facing, b.figure_size())
	focus_labels([uid])
	SoundFx.i().play("ball_land", -3.0)
	VisualUtil.ring_wave(world, Vector3(b.global_position.x, .08, b.global_position.z), VisualUtil.attr_color(creature_def(uid).attribute), Arena.FIG_W * 0.7, 0.55)
	SoundFx.i().play_later("capsule_open", 0.05)
	cry(uid, "appear", 0.4)
	director.open_creature(b)  # выход со стойкой и рёвом (CreatureAnim.appear), пик — к тряске камеры
	public_creature_opened(uid)
	get_tree().create_timer(0.8).timeout.connect(func() -> void: cam.shake(0.3, 0.2))
	await wait(orbit_t)
	# Плавный возврат после раскрытия.
	cam.overview()
	await wait(0.3)

func anim_battle_started(slot: int, attacker_uid: int, defender_uid: int, powers: Array = [], momentum: Array = [0, 0]) -> void:
	if powers.is_empty() and _queued_battle_result != null:
		powers = _queued_battle_result.powers
		momentum = _queued_battle_result.momentum
	await director.battle_started(slot, attacker_uid, defender_uid, powers, momentum)

func anim_card_revealed(slot: int, card_id: StringName, owner: int = -1, powers: Array = []) -> void:
	await director.fighter_action(owner,"gate")
	cam.battle_wide(true)
	var card := CardDB.card(card_id)
	var node: ArenaCardNode = state.card_nodes.get(slot)
	if node != null:
		node.reveal(card)
		SoundFx.i().play("card_flip")
	# Read the card on the settled board after the reveal animation.
	if node != null: await wait(0.47)
	if powers.is_empty() and _queued_battle_result != null and _queued_battle_result.slot == slot:
		powers = _queued_battle_result.powers
	if powers.size() == 2:
		battle_hud.set_powers(powers)
		present_battle_powers(powers)
	if not CardEffects.is_gate_trap(card):
		await read_battle_effect(card_name(card_id), card.text if card != null else "Ворота открыты", side_title(owner), "Ворота %d" % (slot + 1))

func anim_ability_msg(player: int, card_id: StringName, cancelled: bool, powers: Array = [], preview: BattleResult = null) -> void:
	if player == AI_PLAYER and is_instance_valid(hud.opponent_panel): hud.opponent_panel.feedback("activation")
	if not cancelled: await director.ability_action(player,card_id)
	var c: CardDef = CardDB.card(card_id)
	var title := card_name(card_id)
	if not cancelled and preview == null and state.battle_uids.size() == 2:
		# The controller may resolve immediately when neither side can respond.
		# Its result signal arrives before EventPlayer starts the presentation.
		preview = _queued_battle_result
		if preview != null: powers = preview.powers
	if cancelled: SoundFx.i().ability(c,true)
	if not cancelled:
		if player == HUMAN and state.battle_uids.size() == 2:
			hud.own_panel.feedback("activation")
		if c != null and CardEffects.is_fusion(c):
			anim_ability_cam(player)
		else:
			cam.battle_wide()
		await ability_fx(player, c)
	else:
		# Срыв карты виден на самом бойце, даже без изменения силы.
		for uid in state.battle_uids:
			if owner_of(uid) == player:
				var b: CreatureBall = balls.get(uid)
				if b != null:
					b.take_hit(Color(0.65, 0.7, 0.85))
					VisualUtil.ring_wave(world, b.global_position, Color(0.6, 0.68, 0.8), Arena.FIG_W * 0.6, 0.45)
		cam.shake(0.16, 0.18)
	await wait(0.22)
	var swap := not cancelled and CardEffects.is_effect(c, &"swap_fighter")
	var shift := not cancelled and CardEffects.is_effect(c, &"shift_gate")
	if powers.size() == 2 and not (swap or shift):
		battle_hud.set_powers(powers)
		present_battle_powers(powers)
	if not swap:
		if preview != null:
			battle_hud.set_chain(preview.plays, preview.passed, -1, preview.cancelled_plays, preview.ability_counts, battle_blocks(preview))
		var summary := c.text if c != null else "Способность сыграна"
		var inactive := cancelled
		if not inactive and preview != null:
			var side := 0 if owner_of(preview.attacker_uid) == player else 1
			for play in preview.cancelled_plays:
				if int(play[0]) == side and play[1] == card_id: inactive = true
		if inactive: summary = "Эффект отменён или подавлен. Карта учтена в лимите."
		var source := side_title(player)
		for uid in state.battle_uids:
			if owner_of(uid) == player:
				source += " · " + cname(uid)
				break
		var target := effect_target(player, card_id, preview) if not inactive else ""
		var color := Color(1.0, 0.69, 0.54) if inactive else UiTheme.DEVICE_ACCENT
		await read_battle_effect(("× " if inactive else "") + title, summary, source, target, color)
	if not cancelled and state.battle_uids.size() == 2:
		cam.battle_wide()


func side_title(player: int) -> String:
	return "Вы" if player == HUMAN else ("Соперник" if player == AI_PLAYER else "")


## Show only the public targets identified by the calculation or the played card.
func effect_target(player: int, card_id: StringName, preview: BattleResult) -> String:
	if preview == null: return ""
	var side := 0 if owner_of(preview.attacker_uid) == player else 1
	var card := CardDB.card(card_id)
	if CardEffects.is_effect(card, &"gale_call") and preview.called_uids[side] >= 0:
		return cname(preview.called_uids[side])
	if CardEffects.is_effect(card, &"light_reserve") and preview.reserve_cards[side] != &"":
		return card_name(preview.reserve_cards[side])
	if CardEffects.is_negate(card) and bool(card.params.get("reactive", false)):
		var cancelled_by_side: Array[StringName] = []
		for play in preview.cancelled_plays:
			if int(play[0]) != side: cancelled_by_side.append(StringName(play[1]))
		if cancelled_by_side.size() == 1: return card_name(cancelled_by_side[0])
		if cancelled_by_side.size() > 1: return "Способность соперника"
	if card != null and card.effect_id in [&"shift_gate", &"nullify_gate", &"purge_gate"]:
		return "Ворота %d" % (preview.slot + 1)
	var source := "ability:" + String(card_id)
	var affected := [false, false]
	for line: Dictionary in preview.breakdown:
		if str(line.source) == source and int(line.delta) != 0:
			affected[int(line.side)] = true
	if affected[0] and affected[1]: return "Оба бойца"
	if affected[0]: return cname(preview.attacker_uid)
	if affected[1]: return cname(preview.defender_uid)
	return ""


func read_battle_effect(title: String, summary: String, source: String, target: String, color: Color = UiTheme.DEVICE_ACCENT) -> void:
	battle_hud.show_effect(title, summary, source, target, color)
	await hud.wait_read(clampf(HudUI.read_time(1.05, summary), 1.05, 2.2))
	battle_hud.clear_effect()


## Кат на автора способности с рывком камеры.

func anim_ability_cam(player: int) -> void:
	if state.battle_uids.size() != 2:
		return
	var mine: int = state.battle_uids[0] if owner_of(state.battle_uids[0]) == player else state.battle_uids[1]
	var foe: int = state.battle_uids[1] if mine == state.battle_uids[0] else state.battle_uids[0]
	var mb: CreatureBall = balls.get(mine)
	var fb: CreatureBall = balls.get(foe)
	if mb == null:
		return
	var facing: Vector3 = (fb.global_position - mb.global_position) if fb != null else Vector3(0, 0, 1)
	cam.ability_jerk(mb.global_position - Vector3(0, CreatureBall.RADIUS, 0), facing, mb.figure_height(), mb.figure_size())

func anim_battle_resolved(result: BattleResult) -> void:
	_queued_battle_result = null
	present_battle_powers(result.powers)
	if fighters.size() == 2 and result.winner_uid >= 0:
		var winning_side := owner_of(result.winner_uid)
		fighters[winning_side].play_motion("victory")
		fighters[1-winning_side].play_motion("defeat")
	await director.battle_resolved(result)

func anim_no_winner(result: BattleResult) -> void:
	await director.no_winner(result)

func anim_captured(player: int, slot: int) -> void:
	var node: ArenaCardNode = state.card_nodes.get(slot)
	cam.overview()
	focus_labels([])
	state.captures[player] += 1
	refresh_status()
	if node == null:
		return
	state.card_nodes.erase(slot)
	SoundFx.i().play("card_capture")
	director.effects.gate_capture(node.global_position + Vector3.UP * 0.8)
	node.tray_offset = float(state.captures[player] - 1) * 1.0 * Arena.WORLD
	await node.play_capture(player)

func anim_game_over(winner: int, reason: StringName) -> void:
	clear_opponent_panel()
	clear_own_panel()
	if fighters.size() == 2:
		for side in 2:
			if winner < 0: fighters[side].reset_motion()
			else: fighters[side].play_motion("victory" if side == winner else "defeat")
	result_ready.emit(winner,reason)
	finished = true
	SoundFx.i().stop_music(1.0)
	SoundFx.i().play("victory" if winner == HUMAN else "defeat")
	state.stats["alive"] = [state.alive[0], state.alive[1]]
	state.stats["captures"] = [state.captures[0], state.captures[1]]
	state.stats["turns"] = ctrl.get_turn()
	var explanation := reason_text(reason)
	explanation += result_suffix
	if not restart_text.is_empty(): game_over_ui.set_restart_text(restart_text)
	game_over_ui.show_result(winner, explanation, state.stats)

func refresh_status() -> void:
	hud.set_status(state.turn, state.active_player, state.alive[0], state.alive[1])
	hud.set_captures(state.captures[0], state.captures[1])

func card_name(id: StringName) -> String:
	var c: CardDef = CardDB.card(id)
	return c.display_name if c != null else String(id)


## Карта прикреплена к существу вне боя: вспышка у шара, карта соперника показывается обоим.

func spawn_ball(uid: int) -> CreatureBall:
	var result := resources.activate(uid,creature_def(uid),start_pos(owner_of(uid)))
	if not result.is_ok():
		runtime_failed.emit(result.message)
		return null
	return result.actor

func start_pos(player: int) -> Vector3:
	return Vector3(0.0, BALL_Y, THROW_Z if player == HUMAN else -THROW_Z)

func reason_text(reason: StringName) -> String:
	match reason:
		&"knockout":
			return "Все три существа проигравшего выбиты"
		&"turn_limit":
			return "Лимит ходов (%d): по числу оставшихся существ" % MatchController.MAX_TURNS
		&"stalemate", &"no_gates":
			return "Бросать больше некому: по числу оставшихся существ"
	return String(reason)

func gate_slots() -> Array:
	var out: Array = []
	var view: MatchState = ctrl.get_view(HUMAN)
	for i in range(view.slots.size()):
		if (view.slots[i] as SlotState).has_card:
			out.append(i)
	return out

func on_card_drawn(player: int, card_id: StringName) -> void:
	events.push(func() -> void:
		refresh_hand()
		SoundFx.i().play("card_select", -6.0)
		hud.draw_notice(card_name(card_id) if player == HUMAN else "Соперник получает карту")
		await wait(0.25))
	if player == HUMAN:
		log_event("Получена карта «%s»" % CardDB.card(card_id).display_name, UiTheme.GOLD)
	else:
		log_event("Соперник получает карту", UiTheme.TEXT_DIM)

func clear_opponent_panel() -> void:
	state.opponent_uid = -1
	state.opponent_power = -1
	if is_instance_valid(hud) and is_instance_valid(hud.opponent_panel): hud.opponent_panel.show_unknown()

func clear_own_panel() -> void:
	state.own_uid = -1
	state.own_power = -1
	if is_instance_valid(hud) and is_instance_valid(hud.own_panel): hud.own_panel.show_unknown()

func present_own(uid: int, power: int) -> void:
	var actor: CreatureBall = balls.get(uid)
	if owner_of(uid) != HUMAN or actor == null or not actor._open or not actor.visible:
		clear_own_panel()
		return
	state.own_uid = uid
	state.own_power = power
	hud.own_panel.present(creature_def(uid),uid,power)
	hud.own_panel.bind_actor(actor)

func public_creature_opened(uid: int) -> void:
	if ctrl == null: return
	var power := PowerCalc.base_power(ctrl.get_view(HUMAN),uid)
	if owner_of(uid) == HUMAN:
		present_own(uid,power)
		if state.own_uid == uid: hud.own_panel.show_context("reveal")
	elif owner_of(uid) == AI_PLAYER:
		present_opponent(uid,power)
		if state.opponent_uid == uid: hud.opponent_panel.show_context("reveal")

func present_opponent(uid: int, power: int) -> void:
	var actor: CreatureBall = balls.get(uid)
	if owner_of(uid) != AI_PLAYER or actor == null or not actor._open or not actor.visible:
		clear_opponent_panel()
		return
	state.opponent_uid = uid
	state.opponent_power = power
	hud.opponent_panel.present(creature_def(uid),uid,power)
	hud.opponent_panel.bind_actor(actor)
	opponent_panel_layout()

func present_battle_opponent(attacker: int, defender: int, powers: Array) -> void:
	var index := 0 if owner_of(attacker) == AI_PLAYER else 1
	battle_hud.set_opponent_side(index)
	var uid := attacker if index == 0 else defender
	if powers.size() == 2:
		present_opponent(uid,int(powers[index]))
		if state.opponent_uid == uid: hud.opponent_panel.show_context("battle")
		var own_uid := defender if index == 0 else attacker
		present_own(own_uid,int(powers[1-index]))
		if state.own_uid == own_uid: hud.own_panel.show_context("battle")
	battle_hud.set_external_panels(hud.own_panel,hud.opponent_panel,index)

func present_battle_powers(powers: Array) -> void:
	if state.battle_uids.size() != 2 or powers.size() != 2: return
	present_battle_opponent(state.battle_uids[0],state.battle_uids[1],powers)

func opponent_panel_layout() -> void:
	if not is_instance_valid(hud) or not is_instance_valid(hud.opponent_panel): return
	hud.opponent_panel.set_compact(ability_panel._panel.visible and not hud._battle)

func finish_opponent_battle() -> void:
	clear_opponent_panel()
	clear_own_panel()
	battle_hud.set_external_panels(null,null,-1)
	battle_hud.set_opponent_side(-1)


func battle_blocks(result: BattleResult) -> Array:
	return [MatchController.battle_ability_block_reason(result,0),MatchController.battle_ability_block_reason(result,1)]

## Presentation subscribes only to visible consequences. Input/game-over routing is composition.
func connect_controller() -> void:
	if ctrl == null: return
	ctrl.card_drawn.connect(on_card_drawn)
	ctrl.arena_card_placed.connect(on_arena_card_placed)
	ctrl.creature_selected.connect(on_creature_selected)
	ctrl.creature_returned.connect(on_creature_returned)
	ctrl.creature_stood.connect(on_creature_stood)
	ctrl.battle_started.connect(on_battle_started)
	ctrl.card_revealed.connect(on_card_revealed)
	ctrl.ability_played.connect(on_ability_played)
	ctrl.ability_cancelled.connect(on_ability_cancelled)
	ctrl.battle_resolved.connect(on_battle_resolved)
	ctrl.creature_eliminated.connect(on_creature_eliminated)
	ctrl.card_captured.connect(on_card_captured)
	ctrl.turn_started.connect(on_turn_started)
	ctrl.ability_attached.connect(on_ability_attached)
	ctrl.gate_thrown.connect(on_gate_thrown)
	ctrl.gate_trap_triggered.connect(on_gate_trap)
	ctrl.momentum_changed.connect(on_momentum_changed)
	ctrl.final_round_started.connect(on_final_round)
	ctrl.creature_revived.connect(on_creature_revived)
	ctrl.creature_marked.connect(on_creature_marked)
	ctrl.fighter_swapped.connect(on_fighter_swapped)
	ctrl.gates_swapped.connect(on_gates_swapped)
	ctrl.gate_discarded.connect(on_gate_discarded)
	ctrl.abilities_recalled.connect(on_abilities_recalled)
	ctrl.abilities_recharged.connect(on_abilities_recharged)
	ctrl.creature_relocated.connect(on_creature_relocated)
	ctrl.gates_recycled.connect(on_gates_recycled)
	ctrl.creatures_refilled.connect(on_creatures_refilled)
	ctrl.standoff.connect(on_standoff)
	ctrl.turn_skipped.connect(on_turn_skipped)

func on_creature_relocated(uid: int, previous: int, target: int) -> void:
	if previous != target: log_event("%s переходит на другие ворота" % cname(uid))
	events.push(anim_relocated.bind(uid,previous,target))

func on_creatures_refilled(player: int) -> void:
	events.push(anim_refilled.bind(player))

func on_gates_recycled() -> void:
	events.push(func() -> void:
		hud.flash("Ворота кончились: выигранные карты вернулись в руки")
		await hud.wait_read(HudUI.read_time(1.2,"Ворота кончились: выигранные карты вернулись в руки"))
		hud.clear_flash())

func on_standoff(attacker: int, defender: int) -> void:
	events.push(func() -> void:
		var message := "Тупик: жребий выбрал атакующего — %s идёт на %s!" % [cname(attacker),cname(defender)]
		hud.flash(message)
		await hud.wait_read(HudUI.read_time(1.4,message))
		hud.clear_flash())

func on_turn_skipped(player: int) -> void:
	events.push(func() -> void:
		var message := "Все ваши существа на воротах — ход переходит сопернику" if player == HUMAN else "Все существа соперника на воротах — ваш ход"
		hud.flash(message)
		await hud.wait_read(HudUI.read_time(1.2,message))
		hud.clear_flash())
