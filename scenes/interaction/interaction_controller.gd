extends Node
## Owns reversible selections and human/AI interaction. Rules stay in MatchController.
const Request := preload("res://scenes/interaction/interaction_request.gd")
const Action := preload("res://scenes/interaction/card_action.gd")
const GatePick := preload("res://scenes/interaction/gate_throw_selection.gd")
const View := preload("res://scenes/interaction/interaction_view.gd")
const Presentation := preload("res://scenes/presentation/match_presentation.gd")
const Resources := preload("res://scenes/match_resources.gd")
const Lifecycle := preload("res://scenes/match_lifecycle.gd")
const HUMAN := 0
const AI_PLAYER := 1
enum State { WAITING_PRESENTATION, CHOOSING_GATE, CHOOSING_CREATURE, CHOOSING_LAUNCH, CHOOSING_ABILITY, CHOOSING_ATTACHMENT, CONFIRMING_GATE_THROW, CHOOSING_ABILITY_TARGET, IN_FLIGHT, STOPPED }
var state := State.STOPPED
var keyboard_enabled := false
var pending: Request = Request.make(Request.Kind.NONE,0) as Request
var gate_pick := GatePick.new()
var ability_target_card: StringName = &""
var ability_target_moment: StringName = &""
var ai_target_slot := -1
var ctrl: MatchController
var ai: AIPlayer
var presentation: Presentation
var resources: Resources
var lifecycle: Lifecycle
var director: ArenaDirector
var events: EventPlayer
var view: View
var battle_hud: BattleHud
var battle_overlay: BattleOverlay
var hud: HudUI
var setup_panel: SetupPanel
var ability_panel: AbilityPanel
var ability_target_picker: AbilityTargetPicker
var arena_slot_picker: ArenaSlotPicker
var launch_target: Button
var team_menu: TeamMenu
var game_over_ui: GameOverUI
var cam: CameraRig
var arena: Arena:
	get: return resources.arena if resources != null else null
var active_ball: CreatureBall:
	get: return presentation.state.active_ball if is_instance_valid(presentation) else null
	set(value):
		if is_instance_valid(presentation): presentation.state.active_ball = value
var preparing: bool:
	get: return is_instance_valid(lifecycle) and lifecycle.preparing()
var finished: bool:
	get: return is_instance_valid(lifecycle) and lifecycle.is_finished() or ctrl != null and ctrl.get_phase() == MatchController.Phase.GAME_OVER

func configure(ui: View, visible: Presentation, lease: Resources, stage: Lifecycle, queue: EventPlayer, camera: CameraRig, arena_director: ArenaDirector) -> void:
	view = ui
	presentation = visible
	resources = lease
	lifecycle = stage
	events = queue
	cam = camera
	director = arena_director
	hud = ui.hud
	battle_hud = visible.battle_hud
	battle_overlay = visible.battle_overlay
	setup_panel = ui.setup
	ability_panel = ui.ability
	ability_target_picker = ui.ability_picker
	arena_slot_picker = ui.arena_picker
	launch_target = ui.launch
	team_menu = ui.team_menu
	game_over_ui = ui.game_over

func bind_controller(controller: MatchController, opponent: AIPlayer) -> void:
	ctrl = controller
	ai = opponent
	keyboard_enabled = true
	clear_request()
	gate_pick.clear()
	ability_target_card = &""
	state = State.WAITING_PRESENTATION

func clear_request() -> void:
	pending = Request.make(Request.Kind.NONE,0) as Request

func queue_request(request: Request) -> void:
	if state == State.STOPPED: return
	pending = request
	state = State.WAITING_PRESENTATION

func assign_legacy(value: Dictionary) -> void:
	queue_request(Request.from_legacy(value) as Request)

func stop() -> void:
	clear_request()
	gate_pick.clear()
	ability_target_card = &""
	state = State.STOPPED
	if view != null:
		view.launch.hide()
		view.arena_picker.dismiss()
		view.ability_picker.hide()

func invalidate(phase: int, _side: int) -> void:
	launch_target.hide()
	arena_slot_picker.dismiss()
	if ability_target_picker.visible:
		ability_target_picker.hide()
		ability_target_card = &""
	if phase == MatchController.Phase.GAME_OVER: stop()

func _execute(kind: Action.Kind, player: int = HUMAN, card_id: StringName = &"", uid: int = -1, slot: int = -1, target: Dictionary = {}) -> Error:
	var action := Action.new()
	action.kind = kind
	action.player = player
	action.card_id = card_id
	action.uid = uid
	action.slot = slot
	action.target.assign_core(target)
	return action.execute(ctrl)

func gate_slots() -> Array:
	var out: Array = []
	var view: MatchState = ctrl.get_view(HUMAN)
	for i in range(view.slots.size()):
		if (view.slots[i] as SlotState).has_card:
			out.append(i)
	return out



func report(uid: int, slot: int) -> void:
	if finished:
		return
	_execute(Action.Kind.REPORT_LANDING,HUMAN,&"",uid,slot)


# ---------------------------------------------------------------- ответы игроков (только после drained)


func pump() -> void:
	if state == State.STOPPED or finished or events.is_busy() or pending.is_empty(): return
	if is_instance_valid(lifecycle) and not lifecycle.input_allowed(): return
	var request := pending
	clear_request()
	if ctrl.get_phase() != request.expected_phase() or (request.kind != Request.Kind.LAUNCH and ctrl.get_active_player() != request.player): return
	match request.kind:
		Request.Kind.SETUP: do_setup(request.player)
		Request.Kind.THROW: do_throw_select(request.player)
		Request.Kind.LAUNCH:
			do_launch(request.player)
			if request.player == HUMAN: show_pre_throw()
		Request.Kind.ABILITY: do_ability(request.player)
		Request.Kind.ATTACH: do_attach(request.player)


func do_setup(player: int) -> void:
	state = State.CHOOSING_GATE
	if player == HUMAN:
		var cards: Array = []
		for cid in ctrl.get_view(HUMAN).players[HUMAN].arena_hand:
			var c: CardDef = CardDB.card(cid)
			cards.append({"id": c.id, "name": c.display_name, "text": c.text})
		var legal: Array[int] = ctrl.legal_setup_slots()
		arena.set_highlight(legal, true)
		hud.set_hint("Карта ворот на поле? Положите карту или пропустите" if ctrl.can_skip_gate() else "Положите карту ворот на поле")
		setup_panel.begin(cards, legal, ctrl.can_skip_gate(), not throwable_entries().is_empty())
		focus_action.call_deferred(setup_panel._card_buttons.values()[0] if not setup_panel._card_buttons.is_empty() else setup_panel._skip_btn)
		hud.coach("gate", "Карта ворот — поле боя: выбери карту и место (подсвечено). Соперник не видит её до боя — там могут быть ловушки. «Ворота + бросок» — положить карту и сразу бросить на неё существо.")
	else:
		hud.set_hint("Соперник выбирает карту ворот...")
		var choice: Dictionary = ai.choose_setup(ctrl.get_view(AI_PLAYER), ctrl.legal_setup_slots(), ctrl.can_skip_gate())
		var err: int = OK
		if choice.is_empty():
			err = _execute(Action.Kind.SKIP_GATE,AI_PLAYER)
		elif int(choice.get("throw_uid", -1)) >= 0:
			# «ворота + бросок»: цель броска — только что положенная карта
			ai_target_slot = int(choice["slot"])
			err = _execute(Action.Kind.THROW_WITH_GATE,AI_PLAYER,StringName(choice["card_id"]),int(choice["throw_uid"]),int(choice["slot"]))
		else:
			err = _execute(Action.Kind.PLACE_GATE,AI_PLAYER,StringName(choice["card_id"]),-1,int(choice["slot"]))
		if err != OK:
			ctrl.save_debug_trace("user://replays/last_error.json")
			push_error("ИИ: выкладка ворот вернула ошибку %d" % err)



func do_throw_select(player: int) -> void:
	state = State.CHOOSING_CREATURE
	if player == HUMAN:
		var view: MatchState = ctrl.get_view(HUMAN)
		var entries: Array = []
		for u in ctrl.legal_creatures(HUMAN):
			var d: CreatureDef = presentation.creature_def(u)
			var note := "с карты" if view.creature(u).slot >= 0 else ""
			entries.append({"uid": u, "def": d, "text": "Существо #%d" % u, "note": note})
		hud.set_hint("Ваш бросок: выберите шар-существо")
		hud.show_creatures(entries)
		if not hud._creature_box.get_children().is_empty():
			focus_action.call_deferred(hud._creature_box.get_child(0))
	else:
		hud.set_hint("Соперник выбирает существо…")
		var c: Dictionary = ai.choose_throw(ctrl.get_view(AI_PLAYER))
		ai_target_slot = int(c["target_slot"])
		var err: int = _execute(Action.Kind.SELECT_CREATURE,AI_PLAYER,&"",int(c["uid"]))
		if err != OK:
			ctrl.save_debug_trace("user://replays/last_error.json")
			push_error("ИИ: select_creature вернул ошибку %d" % err)



func do_launch(player: int) -> void:
	state = State.CHOOSING_LAUNCH
	var uid: int = ctrl.get_selected_uid()
	var ball: CreatureBall = resources.active.get(uid)
	if ball == null:
		push_error("Нет шара для uid %d" % uid)
		return
	active_ball = ball
	presentation.focus_labels([])
	cam.overview()
	if ctrl.get_throw_gate_slot() >= 0:
		state = State.IN_FLIGHT
		await director.launch_to(ctrl.get_throw_gate_slot())
	elif player == HUMAN:
		hud.set_hint("РАЗМЕЩЕНИЕ · выберите подсвеченные ворота для сферы")
		hud.coach("throw", "Выбери цель броска — карту ворот на поле. Сфера отскакивает и катится; учитывается место остановки, возможен промах. Способность можно прикрепить до выбора цели.")
		arena.set_highlight(gate_slots(), true)
		launch_target.show()
		focus_action.call_deferred(launch_target)
	else:
		hud.set_hint("Соперник выбирает цель…")
		await presentation.wait(0.45)
		var target: int = ai_target_slot
		if not gate_slots().has(target):
			target = int(gate_slots()[0])
		state = State.IN_FLIGHT
		await director.launch_to(target)



func on_slot_picked(slot: int) -> void:
	if not human_field_input_allowed():
		return
	if ctrl.get_phase() == MatchController.Phase.SETUP and ctrl.get_active_player() == HUMAN:
		setup_panel.pick_slot(slot)
	elif ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING and ctrl.get_active_player() == HUMAN:
		if not gate_slots().has(slot): return
		launch_target.hide()
		arena_slot_picker.dismiss()
		state = State.IN_FLIGHT
		await director.launch_to(slot)



func human_field_input_allowed() -> bool:
	return ctrl != null and (not is_instance_valid(lifecycle) or lifecycle.input_allowed()) and not preparing and not finished and state != State.STOPPED and not events.is_busy() and not director.flying and ctrl.get_active_player() == HUMAN and not blocking_modal()


## Фокус передаётся только после постановки; справка, подтверждение и цели сохраняют свой ввод.

func blocking_modal() -> bool:
	return view.blocking_modal()


func input(event: InputEvent) -> void:
	if not keyboard_enabled or preparing or state == State.STOPPED or team_menu.visible: return
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_TAB: return
	if blocking_modal() or arena_slot_picker.visible or game_over_ui._panel.visible: return
	var choices: Array[Control] = []
	for region in [hud, setup_panel, ability_panel, launch_target]:
		collect_keyboard_controls(region, choices)
	for extra in view.extra_focus_controls(): collect_keyboard_controls(extra, choices)
	if choices.is_empty(): return
	var index := choices.find(get_viewport().gui_get_focus_owner())
	var next := posmod(index + (-1 if event.shift_pressed else 1), choices.size())
	choices[next].grab_focus()
	get_viewport().set_input_as_handled()



func collect_keyboard_controls(node: Node, choices: Array[Control]) -> void:
	if node.is_queued_for_deletion() or node is Window: return
	if node is Control:
		if not node.is_visible_in_tree(): return
		if node.focus_mode == Control.FOCUS_ALL and not (node is BaseButton and node.disabled): choices.append(node)
	for child in node.get_children(): collect_keyboard_controls(child, choices)



func focus_action(control: Control) -> void:
	if is_instance_valid(control) and control.is_visible_in_tree() and not blocking_modal() and not arena_slot_picker.visible:
		control.grab_focus()



func resume_keyboard_focus() -> void:
	if blocking_modal():
		if battle_overlay._open: battle_overlay.focus_primary()
		return
	if game_over_ui._panel.visible:
		game_over_ui.focus_primary()
	elif arena_slot_picker.visible:
		return  # Модальная карта поля сама владеет навигацией.
	elif ctrl != null and ctrl.get_active_player() == HUMAN and not events.is_busy():
		if hud._creature_panel.visible and hud._creature_box.get_child_count() > 0:
			focus_action(hud._creature_box.get_child(0))
			return
		match ctrl.get_phase():
			MatchController.Phase.SETUP: setup_panel.focus_selected_card()
			MatchController.Phase.AWAIT_THROW:
				if hud._creature_box.get_child_count() > 0: focus_action(hud._creature_box.get_child(0))
			MatchController.Phase.AWAIT_LANDING:
				focus_action(launch_target)
			MatchController.Phase.ABILITY_WINDOW, MatchController.Phase.AFTER_LANDING: focus_ability_action()



func request_setup_slot() -> void:
	if not human_field_input_allowed() or ctrl.get_phase() != MatchController.Phase.SETUP or setup_panel._selected == &"": return
	arena_slot_picker.show_slots(ctrl.legal_setup_slots(), ctrl.get_view(HUMAN), "Куда положить выбранные ворота?", field_slot_description)



func request_launch_slot() -> void:
	if not human_field_input_allowed() or ctrl.get_phase() != MatchController.Phase.AWAIT_LANDING: return
	arena_slot_picker.show_slots(gate_slots(), ctrl.get_view(HUMAN), "Выберите ворота для броска", field_slot_description)



func field_slot_description(slot: int) -> String:
	var view := ctrl.get_view(HUMAN)
	var lines := presentation.slot_tip(slot, view.slots[slot], view)
	return "\n".join(PackedStringArray([str(lines[0]), str(lines[1]), str(lines[3]), str(lines[4]), str(lines[6])])) if lines.size() >= 7 else "Свободное место для карты ворот"



func do_ability(player: int) -> void:
	state = State.CHOOSING_ABILITY
	var preview: BattleResult = ctrl.get_battle_preview()
	if preview == null:
		push_error("Окно способностей без предпросмотра боя")
		return
	battle_hud.set_chain(preview.plays, preview.passed, 0 if presentation.owner_of(preview.attacker_uid) == player else 1, preview.cancelled_plays, preview.ability_counts, presentation.battle_blocks(preview))
	if player == HUMAN:
		var entries: Array = []
		for cid in ctrl.legal_abilities(HUMAN):
			var c: CardDef = CardDB.card(cid)
			entries.append({"id": c.id, "name": c.display_name, "text": c.text})
		var hdr := "Ваш ответ: способность или пас"
		var fusion_only := not entries.is_empty()
		for e in entries:
			if not CardEffects.is_fusion(CardDB.card(e["id"])):
				fusion_only = false
		if fusion_only:
			hdr = "Ваш ответ: слияние или пас"
		var my_side: int = 0 if presentation.owner_of(preview.attacker_uid) == HUMAN else 1
		var note := "Два паса подряд завершат бой. На карту соперника можно ответить."
		if preview.passed.size() == 2 and preview.passed[1 - my_side]:
			note = "Соперник спасовал. Ваш пас завершит бой."
		if not ctrl.state.slots[preview.slot].revealed:
			note = ("Ворота закрыты. " if ctrl.can_reveal_gate(HUMAN) else "Закрытые ворота соперника. ") + note
		if entries.is_empty():
			hud.set_hint("Откройте свои ворота или пропустите ответ")
		elif ctrl.can_reveal_gate(HUMAN):
			hud.set_hint("Сыграйте карту, откройте ворота или спасуйте")
		else:
			hud.set_hint("Сыграйте слияние или спасуйте" if fusion_only else "Сыграйте способность или спасуйте")
		# Справка доступна наведением на блок ответа; отдельная большая карточка
		# наставника закрывала ленту и управление на невысоком экране.
		ability_panel.show_options(entries, hdr, {"moment": &"battle", "used": MatchController.MAX_BATTLE_ABILITIES - ctrl.abilities_left(HUMAN),
			"can_open_gate": ctrl.can_reveal_gate(HUMAN), "pass_text": "Пас", "pass_tip": "Пропустить ход обмена. Спасуют оба подряд — бой решится.", "note": note})
		focus_ability_action.call_deferred()
	else:
		hud.set_hint("Соперник думает...")
		if ctrl.can_reveal_gate(AI_PLAYER) and ai.should_open_gate(ctrl.get_view(AI_PLAYER), preview):
			_execute(Action.Kind.OPEN_GATE,AI_PLAYER)
			return
		var cid: StringName = ai.choose_ability(ctrl.get_view(AI_PLAYER), preview, ctrl.legal_abilities(AI_PLAYER))
		var err: int = OK
		if cid == &"":
			err = _execute(Action.Kind.PASS_ABILITY,AI_PLAYER)
		else:
			var target := ai.choose_ability_target(ctrl.get_view(AI_PLAYER), preview, cid, ctrl.legal_ability_targets(AI_PLAYER, cid))
			err = _execute(Action.Kind.PLAY_ABILITY,AI_PLAYER,cid,-1,-1,target)
		if err != OK:
			ctrl.save_debug_trace("user://replays/last_error.json")
			push_error("ИИ: ошибка способности %d" % err)


## Окно «после приземления»: прикрепить способность к существу, что встало на пустые ворота, или завершить ход.

func do_attach(player: int) -> void:
	state = State.CHOOSING_ATTACHMENT
	var uid: int = ctrl.get_landed_uid()
	if player == HUMAN:
		var entries: Array = []
		for cid in ctrl.legal_abilities(HUMAN):
			var c: CardDef = CardDB.card(cid)
			entries.append({"id": c.id, "name": c.display_name, "text": c.text})
		hud.set_hint("%s на воротах: прикрепить способность?" % presentation.cname(uid))
		hud.coach("attach", "Существо встало на пустые ворота. Можно прикрепить карту: она сработает в его следующем бою (видна сопернику). Или завершить ход без неё.")
		ability_panel.show_options(entries, "Прикрепить способность к «%s»?" % presentation.cname(uid), {"moment": &"after_landing",
			"used": MatchController.MAX_BATTLE_ABILITIES - ctrl.abilities_left(HUMAN), "pass_text": "Завершить ход",
			"pass_tip": "Не прикреплять карту — ход переходит сопернику.",
			"note": "Прикреплённая карта входит в лимит 3 карт на бой."})
		focus_ability_action.call_deferred()
	else:
		hud.set_hint("Соперник думает...")
		var cid: StringName = ai.choose_attach(ctrl.get_view(AI_PLAYER), uid, ctrl.legal_abilities(AI_PLAYER))
		var err: int = OK
		if cid == &"":
			err = _execute(Action.Kind.PASS_ABILITY,AI_PLAYER)
		else:
			err = _execute(Action.Kind.PLAY_ABILITY,AI_PLAYER,cid)
		if err != OK:
			ctrl.save_debug_trace("user://replays/last_error.json")
			push_error("ИИ: ошибка прикрепления %d" % err)


## До броска: рука приподнята, играбельные карты светятся; карта прикрепится к выбранному существу.

func show_pre_throw() -> void:
	if finished or director.flying or ctrl.get_phase() != MatchController.Phase.AWAIT_LANDING:
		return
	var legal: Array[StringName] = ctrl.legal_abilities(HUMAN)
	if legal.is_empty():
		return
	var entries: Array = []
	for cid in legal:
		var c: CardDef = CardDB.card(cid)
		entries.append({"id": c.id, "name": c.display_name, "text": c.text})
	var uid: int = ctrl.get_selected_uid()
	hud.coach("prethrow", "Перед броском можно прикрепить способность к шару: она сработает в его бое. Это необязательно — просто выбери ворота.")
	ability_panel.show_options(entries, "До броска: прикрепить карту к «%s» (необязательно)" % presentation.cname(uid), {"moment": &"pre_throw",
		"used": MatchController.MAX_BATTLE_ABILITIES - ctrl.abilities_left(HUMAN), "note": ""})


## Существа, которых можно бросить в фазе выкладки (в руке, не на воротах и не в зоне использованных).

func throwable_entries() -> Array:
	var view: MatchState = ctrl.get_view(HUMAN)
	var entries: Array = []
	for u in view.players[HUMAN].creature_uids:
		var cs: CreatureState = view.creature(u)
		if cs.alive and cs.slot < 0 and not cs.used:
			entries.append({"uid": u, "def": presentation.creature_def(u), "text": "Существо #%d" % u, "note": ""})
	return entries



func on_setup_placed_throw(card_id: StringName, slot: int) -> void:
	var entries: Array = throwable_entries()
	if entries.is_empty():
		on_setup_placed(card_id, slot)
		return
	gate_pick.card_id = card_id
	gate_pick.slot = slot
	state = State.CONFIRMING_GATE_THROW
	setup_panel.hide_panel()
	arena.set_highlight([slot])
	hud.set_hint("Ворота + бросок: кого бросить на новую карту?")
	hud.show_creatures(entries, "Кого бросить на новые ворота?", true)
	arena_slot_picker.dismiss()
	if not hud._creature_box.get_children().is_empty(): focus_action.call_deferred(hud._creature_box.get_child(0))



func focus_ability_action() -> void:
	if ability_panel._owns_focus(): return
	if ability_panel._gate_btn.visible:
		focus_action(ability_panel._gate_btn)
	elif ability_panel._pass_btn.visible:
		focus_action(ability_panel._pass_btn)
	elif not ability_panel._cards.is_empty():
		focus_action(ability_panel._cards[0])



func on_gate_throw_cancelled() -> void:
	if finished or events.is_busy() or ctrl.get_phase() != MatchController.Phase.SETUP or ctrl.get_active_player() != HUMAN: return
	gate_pick.clear()
	hud.hide_creatures()
	do_setup(HUMAN)



func on_creature_chosen(uid: int) -> void:
	hud.hide_creatures()
	if not gate_pick.is_empty():
		var selected_card := gate_pick.card_id
		var selected_slot := gate_pick.slot
		gate_pick.clear()
		arena.set_highlight([])
		var gerr: int = _execute(Action.Kind.THROW_WITH_GATE,HUMAN,selected_card,uid,selected_slot)
		if gerr != OK:
			ctrl.save_debug_trace("user://replays/last_error.json")
			hud.reject_action("Не получилось: ворота + бросок")
			do_setup(HUMAN)
		return
	var err: int = _execute(Action.Kind.SELECT_CREATURE,HUMAN,&"",uid)
	if err != OK:
		ctrl.save_debug_trace("user://replays/last_error.json")
		hud.reject_action("Нельзя выбрать это существо")
		queue_request(Request.make(Request.Kind.THROW,HUMAN) as Request)
		pump()



func on_setup_skipped() -> void:
	if _execute(Action.Kind.SKIP_GATE) != OK:
		hud.reject_action("Ворот на поле нет: карту нужно положить")
		queue_request(Request.make(Request.Kind.SETUP,HUMAN) as Request)
		pump()
		return
	setup_panel.hide_panel()
	arena.set_highlight([])



func on_setup_placed(card_id: StringName, slot: int) -> void:
	var err: int = _execute(Action.Kind.PLACE_GATE,HUMAN,card_id,-1,slot)
	if err != OK:
		ctrl.save_debug_trace("user://replays/last_error.json")
		hud.reject_action("Нельзя положить карту в этот слот")
		queue_request(Request.make(Request.Kind.SETUP,HUMAN) as Request)
		pump()
		return
	setup_panel.hide_panel()
	arena.set_highlight([])



func on_ability_chosen(card_id: StringName) -> void:
	arena_slot_picker.dismiss()
	var targets := ctrl.legal_ability_targets(HUMAN, card_id)
	if not targets.is_empty():
		ability_target_card = card_id
		ability_target_moment = ctrl.get_ability_moment()
		state = State.CHOOSING_ABILITY_TARGET
		ability_panel.hide_panel()
		ability_target_picker.show_targets(card_id, targets, ctrl.get_view(HUMAN))
		return
	play_chosen_ability(card_id)



func on_ability_target_chosen(target: Dictionary) -> void:
	if ability_target_card == &"" or state != State.CHOOSING_ABILITY_TARGET: return
	var card_id := ability_target_card
	ability_target_card = &""
	play_chosen_ability(card_id, target)



func on_ability_target_cancelled() -> void:
	if state != State.CHOOSING_ABILITY_TARGET or ability_target_card == &"": return
	ability_target_card = &""
	match ability_target_moment:
		&"pre_throw": show_pre_throw()
		&"after_landing": do_attach(HUMAN)
		_: do_ability(HUMAN)



func play_chosen_ability(card_id: StringName, target: Dictionary = {}) -> void:
	var moment: StringName = ctrl.get_ability_moment()
	ability_panel.hide_panel()
	var err: int = _execute(Action.Kind.PLAY_ABILITY,HUMAN,card_id,-1,-1,target)
	if err != OK:
		ctrl.save_debug_trace("user://replays/last_error.json")
		hud.reject_action(ctrl.ability_unavailable_reason(HUMAN, card_id))
		match moment:
			&"after_landing":
				queue_request(Request.make(Request.Kind.ATTACH,HUMAN) as Request)
			&"pre_throw":
				show_pre_throw()
				return
			_:
				queue_request(Request.make(Request.Kind.ABILITY,HUMAN) as Request)
		pump()



func on_gate_open_requested() -> void:
	if events.is_busy():
		return
	ability_panel.hide_panel()
	if _execute(Action.Kind.OPEN_GATE) != OK:
		hud.reject_action("Свои ворота можно открыть только в свой ответ во время боя")
		queue_request(Request.make(Request.Kind.ABILITY,HUMAN) as Request)
		pump()



func on_ability_passed() -> void:
	state = State.WAITING_PRESENTATION
	ability_panel.hide_panel()
	_execute(Action.Kind.PASS_ABILITY)


