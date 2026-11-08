extends SceneTree
## Production Main/UI/controller integration. Human commands use root.push_input only.
## Deterministic landing replaces 3D physics; this is NOT GPU/physics acceptance.

class BareArena extends Arena:
	func _ready() -> void:
		_built = true
	func _build() -> void:
		_built = true

class BareBall extends CreatureBall:
	func _ensure_built() -> void:
		_built = true
	func _ready() -> void:
		_label = Label3D.new()
		add_child(_label)
		freeze = true
		set_physics_process(false)
		set_process(false)

class PredictableAI extends AIPlayer:
	func choose_setup(view: MatchState, legal = null, can_skip: bool = false) -> Dictionary:
		if can_skip: return {}
		if legal == null or legal.is_empty() or view.players[player].arena_hand.is_empty(): return {}
		return {"card_id": view.players[player].arena_hand[0], "slot": legal[0]}
	func choose_throw(view: MatchState) -> Dictionary:
		var candidates := _candidates(view)
		var target := -1
		for i in view.slots.size():
			var state: SlotState = view.slots[i]
			if not state.has_card: continue
			if target < 0: target = i
			if state.occupant_uid >= 0 and view.creature(state.occupant_uid).owner != player:
				target = i
				break
		return {"uid": candidates[0] if not candidates.is_empty() else -1, "target_slot": target}
	func should_open_gate(_view: MatchState, _preview: BattleResult) -> bool:
		return false
	func choose_ability(_view: MatchState, _preview: BattleResult, _legal = null) -> StringName:
		return &""
	func choose_attach(_view: MatchState, _uid: int, _legal: Array, _moment: StringName = &"after_landing") -> StringName:
		return &""

class DeterministicDirector extends ArenaDirector:
	var landings: Array = []
	func launch_to(slot: int) -> void:
		if flying or game._active_ball == null or not game._gate_slots().has(slot): return
		flying = true
		var uid: int = game._active_ball.uid
		game.arena.set_highlight([])
		game.ability_panel.hide_panel()
		await get_tree().process_frame
		flying = false
		landings.append({"uid": uid, "slot": slot})
		game._report(uid, slot)

class PresentationQueue extends EventPlayer:
	var game: Node
	func push(animation: Callable) -> void:
		# Keep the actual sequential EventPlayer/drained barrier. Replace only
		# presentation entries that load/stage models, delay, or play 3D effects.
		var method := String(animation.get_method())
		if method in ["_anim_phase", "_anim_turn", "_anim_set_pending"]:
			super.push(animation)
		elif method == "_anim_game_over":
			super.push(game.stage_game_over.bind(animation))
		elif method == "_anim_selected":
			var args := animation.get_bound_arguments()
			super.push(game.stage_selected.bind(int(args[0]), int(args[1])))
		elif method == "_anim_battle_resolved":
			super.push(game.stage_result.bind(animation.get_bound_arguments()[0]))
		elif method == "_anim_remove_ball":
			super.push(game.stage_removed.bind(int(animation.get_bound_arguments()[0])))
		elif method == "_anim_captured":
			super.push(game.stage_capture.bind(int(animation.get_bound_arguments()[0])))
		elif method == "_anim_attached":
			super.push(game.stage_attached.bind(int(animation.get_bound_arguments()[0])))

class MatchFixture extends "res://scenes/main.gd":
	var restarts := 0
	var resolved: Array[BattleResult] = []
	var late_help: HelpOverlay
	var game_over_help: HelpOverlay
	func _ready() -> void:
		world = Node3D.new()
		add_child(world)
		arena = BareArena.new()
		world.add_child(arena)
		cam = CameraRig.new()
		world.add_child(cam)
		events = PresentationQueue.new()
		events.game = self
		add_child(events)
		director = DeterministicDirector.new()
		director.game = self
		add_child(director)
		# A deliberately empty prepared catalog suppresses TeamMenu's GLB fallback
		# during the real _build_ui. The hidden team menu is outside this scenario.
		var pool := GameLoading.i()
		pool.ready_to_play = true
		_build_ui()
		team_menu.hide()
		pool.ready_to_play = false
		_build_logic()
		ai = PredictableAI.new(AI_PLAYER, 771)
		for player in 2:
			var powers: Dictionary = {}
			for uid in ctrl.state.players[player].creature_uids:
				powers[String(ctrl.state.creature(uid).def_id)] = 420 if player == HUMAN else 190
			assert(PowerCalc.apply_power_snapshot(ctrl.state, player, powers) == OK)
		_refresh_hand()
		_duel_menu.show()
	func _build_decks() -> Array[DeckDef]:
		return [CardDB.preset_deck(0), CardDB.preset_deck(1)]
	func _wait(_seconds: float) -> void:
		await get_tree().process_frame
	func _on_restart() -> void:
		# The real GameOverUI signal reaches this endpoint without reloading
		# the fixture into Boot; no gameplay/controller command is overridden.
		restarts += 1
	func stage_selected(player: int, uid: int) -> void:
		if not balls.has(uid):
			var ball := BareBall.new()
			ball.uid = uid
			world.add_child(ball)
			balls[uid] = ball
		_active_ball = balls[uid]
		_pending = {"kind": "launch", "player": player, "uid": uid}
	func stage_result(result: BattleResult) -> void:
		resolved.append(result)
		if resolved.size() == 1:
			late_help = HelpOverlay.open_on(ui_layer)
			await get_tree().process_frame
		await battle_overlay.show_result(result, _names_for(result))
	func stage_game_over(animation: Callable) -> void:
		game_over_help = HelpOverlay.open_on(ui_layer)
		await get_tree().process_frame
		await animation.call()
	func stage_removed(uid: int) -> void:
		_alive.assign([ctrl.state.alive_count(0), ctrl.state.alive_count(1)])
		if balls.has(uid): balls[uid].hide()
	func stage_capture(player: int) -> void:
		captures[player] += 1
	func stage_attached(player: int) -> void:
		# Preserve the real _anim_attached continuation after skipping only its
		# 3D pulse/ability shot and timed message.
		_refresh_hand()
		if player == HUMAN and ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING and _active_ball != null and not director.flying:
			_show_pre_throw()

var checks := 0
var failures := 0
var human_attacks := 0
var human_defences := 0
var post_landing_passes := 0
var opened_gates := 0
var invalid_tab_focus := false
var layout_evidence: Array = []
var native_escape_observations: Array = []
const OUT := "res://build/checks/ui-match-keyboard-2026-11-06"


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1
	print("PASS: " if condition else "FAIL: ", message)


func frames(count: int = 3) -> void:
	for _i in count: await process_frame


func key(code: Key, echo: bool = false, surface: Viewport = null, backwards: bool = false) -> void:
	if surface == null: surface = root
	var event := InputEventKey.new()
	event.keycode = code
	event.shift_pressed = backwards
	event.pressed = true
	surface.push_input(event)
	if echo:
		var repeat := InputEventKey.new()
		repeat.keycode = code
		repeat.shift_pressed = backwards
		repeat.pressed = true
		repeat.echo = true
		surface.push_input(repeat)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.shift_pressed = backwards
	event.pressed = false
	surface.push_input(event)
	await frames(2)


func tab_to(target: Control) -> bool:
	var route: Array = []
	for _step in 80:
		if root.gui_get_focus_owner() == target: return true
		await key(KEY_TAB)
		var owner := root.gui_get_focus_owner()
		if owner != null:
			var path := str(owner.get_path())
			if not route.has(path): route.append(path)
			if not owner.is_visible_in_tree() or (owner is BaseButton and owner.disabled):
				invalid_tab_focus = true
				print("INVALID TAB FOCUS: ", owner.get_path(), " visible=", owner.is_visible_in_tree(), " disabled=", owner.disabled if owner is BaseButton else false, " mode=", owner.focus_mode)
	print("TAB TARGET UNREACHED: ", target.get_path(), " visible=", target.is_visible_in_tree(), " mode=", target.focus_mode, " rect=", target.get_global_rect(), " route=", route)
	return root.gui_get_focus_owner() == target


func stable(game: MatchFixture) -> void:
	for _i in 90:
		await process_frame
		if game.battle_overlay._open or game.game_over_ui._panel.visible: return
		if not game.events.is_busy() and not game.director.flying and game._pending.is_empty() and game.ctrl.get_active_player() == 0:
			await frames(2)
			return


func select_field_slot(game: MatchFixture, slot: int) -> bool:
	var target: Button = game.arena_slot_picker._buttons[slot]
	if not await tab_to(target):
		check(false, "legal field slot is reachable with Tab")
		return false
	await key(KEY_ENTER, true)
	await stable(game)
	return true


func modal_checks(game: MatchFixture) -> void:
	var picker := game.arena_slot_picker
	var before := game.ctrl.debug_snapshot()
	# Fixture preconditions put a second modal above an existing field choice;
	# closing it still uses real keyboard dispatch, never a game handler.
	var help := HelpOverlay.open_on(game.ui_layer)
	await frames()
	await key(KEY_DOWN)
	check(help._scroll.scroll_vertical > 0 and picker.visible, "help owns arrow input over an open field picker")
	await key(KEY_ENTER)
	check(not is_instance_valid(help) and picker.visible, "help Enter closes help without choosing the underlying slot")
	check(game.ctrl.debug_snapshot() == before, "help navigation spends no card/turn/throw")
	await key(KEY_ESCAPE)
	check(not picker.visible and game.setup_panel._selected != &"", "field Escape restores selected gate without spending it")
	check(game.ctrl.debug_snapshot() == before, "field cancellation changes no controller state")
	check(game.setup_panel._slot_btn.has_focus(), "field cancellation restores its initiating keyboard button")
	var reached := await tab_to(game._duel_menu)
	check(reached, "production duel exit reachable by keyboard")
	if not reached:
		await tab_to(game.setup_panel._slot_btn)
		return
	await key(KEY_ENTER)
	var confirm := game._duel_exit_confirm
	check(is_instance_valid(confirm) and confirm.visible and not picker.visible, "production confirmation opens while field picker stays dismissed")
	if not is_instance_valid(confirm): return
	await frames()
	await key(KEY_ESCAPE, false, confirm)
	var escape_closed := not confirm.visible
	var action_closed := false
	if confirm.visible:
		for pressed in [true, false]:
			var cancel_action := InputEventAction.new()
			cancel_action.action = &"ui_cancel"
			cancel_action.pressed = pressed
			confirm.push_input(cancel_action)
			await frames(1)
		action_closed = not confirm.visible
	native_escape_observations.append({"key_press_release_closed": escape_closed, "action_closed": action_closed, "display": DisplayServer.get_name()})
	print("Native dialog Escape diagnostic: key=", escape_closed, ", ui_cancel=", action_closed, "; native OS delivery is outside this headless test")
	if not confirm.visible:
		# Reopen the same production Dialog to check its explicit Cancel button.
		confirm.popup_centered()
		await frames()
	# Native Window close/Escape notification belongs to the OS. Here keyboard
	# dispatch uses the actual dialog Viewport and its standard Cancel button.
	for _i in 6:
		if confirm.gui_get_focus_owner() == confirm.get_cancel_button(): break
		await key(KEY_TAB, false, confirm)
	check(confirm.gui_get_focus_owner() == confirm.get_cancel_button(), "confirmation Cancel reachable with keyboard")
	await key(KEY_ENTER, false, confirm)
	check(not confirm.visible and not picker.visible, "production confirmation Cancel Enter returns to duel without field activation")
	check(game.ctrl.debug_snapshot() == before, "confirmation cancellation leaves controller unchanged")
	check(await tab_to(game.setup_panel._slot_btn), "Tab returns from confirmation to selected gate field action")


func field_layout_checks(game: MatchFixture) -> void:
	var picker := game.arena_slot_picker
	for dimensions in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1024, 768)]:
		root.size = dimensions
		await frames(4)
		var bounds := picker._panel.get_global_rect()
		check(root.get_visible_rect().encloses(bounds), "field dialog fits production stretched viewport: " + str(dimensions))
		var cells: Array = []
		for button in picker._buttons:
			check(bounds.encloses(button.get_global_rect()), "field cell stays within modal at " + str(dimensions))
			var cell := button.get_global_rect()
			cells.append([cell.position.x, cell.position.y, cell.size.x, cell.size.y])
		layout_evidence.append({"physical": str(dimensions), "logical": str(root.get_visible_rect().size), "panel": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y], "cells": cells, "description": picker._description.text})
	root.size = Vector2i(1280, 720)
	await frames()


func setup_with_keyboard(game: MatchFixture, extras: bool) -> bool:
	if game.ctrl.can_skip_gate():
		check(await tab_to(game.setup_panel._skip_btn), "setup skip reachable by keyboard")
		await key(KEY_ENTER)
		await stable(game)
		return true
	var card: CardView = game.setup_panel._card_buttons.values()[0]
	check(await tab_to(card), "setup card reachable by keyboard")
	var old_hand := game.ctrl.get_view(0).players[0].arena_hand.size()
	await key(KEY_ENTER)
	check(game.setup_panel._selected != &"" and not game.setup_panel._slot_btn.disabled, "Enter selects gate and enables field action")
	check(await tab_to(game.setup_panel._slot_btn), "Tab reaches field action after selecting gate")
	await key(KEY_ENTER)
	var picker := game.arena_slot_picker
	check(picker.visible and picker.is_ancestor_of(root.gui_get_focus_owner()), "Enter opens production field picker with immediate focus")
	if not picker.visible: return false
	var legal := game.ctrl.legal_setup_slots()
	for i in 6:
		check(picker._buttons[i].disabled == not legal.has(i), "setup cell availability matches controller: %d" % i)
	if extras:
		await field_layout_checks(game)
		for _i in legal.size() + 1:
			await key(KEY_TAB)
			var focused := root.gui_get_focus_owner()
			var index := picker._buttons.find(focused)
			check(focused == picker._cancel or (index >= 0 and legal.has(index)), "Tab visits available cells and Cancel only")
		if legal.has(0) and legal.has(1) and picker._buttons[0].has_focus():
			await key(KEY_RIGHT, true)
			check(picker._buttons[1].has_focus(), "held arrow advances exactly one legal field cell")
		for code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			await key(code, true)
			var slot := picker._buttons.find(root.gui_get_focus_owner())
			check(picker.is_ancestor_of(root.gui_get_focus_owner()) and (slot < 0 or legal.has(slot)), "arrow stays within legal field choices")
			check(game.arena._hover == slot, "keyboard field focus updates production arena hover")
			if slot >= 0: check(picker._description.text == picker._buttons[slot].tooltip_text, "focused field description is visible without mouse")
		await modal_checks(game)
		await key(KEY_ENTER)
		check(picker.visible, "restored source Enter reopens field picker")
	if not await select_field_slot(game, int(legal[0])): return false
	check(not picker.visible and game.ctrl.get_view(0).players[0].arena_hand.size() == old_hand - 1, "one Enter places exactly one gate and closes old-phase picker")
	check(game.ctrl.get_phase() == MatchController.Phase.AWAIT_THROW, "placement enters creature selection without an accidental launch")
	return true


func run_match(first: int) -> void:
	var game := MatchFixture.new()
	root.add_child(game)
	await frames()
	game.ctrl.start(first)
	await stable(game)
	var used_extras := false
	var action_count := 0
	var confirmed_results := 0
	var launch_navigation_checked := false
	while not game.game_over_ui._panel.visible and action_count < 80:
		action_count += 1
		if game.battle_overlay._open:
			if is_instance_valid(game.late_help):
				await frames()
				check(game.late_help._close_button.has_focus(), "late battle result preserves help keyboard focus")
				await key(KEY_ENTER, true)
				check(not is_instance_valid(game.late_help) and game.battle_overlay._open, "first Enter closes late help while leaving battle result open")
				check(game.battle_overlay._continue_button.has_focus(), "closing help transfers focus to late battle result")
			check(game.events.is_busy(), "battle result retains sequential EventPlayer barrier")
			var count := game.resolved.size()
			check(root.gui_get_focus_owner() == game.battle_overlay._continue_button, "battle result takes keyboard focus")
			await key(KEY_ENTER, true)
			confirmed_results += 1
			check(not game.battle_overlay._open and game.resolved.size() == count, "one Enter closes exactly one result without another human action")
			await stable(game)
			continue
		if game.ctrl.get_active_player() != 0 or game.events.is_busy() or game.director.flying:
			await stable(game)
			continue
		match game.ctrl.get_phase():
			MatchController.Phase.SETUP:
				if not await setup_with_keyboard(game, not used_extras): break
				used_extras = true
			MatchController.Phase.AWAIT_THROW:
				var orb := game.hud._creature_box.get_child(0) as Control
				check(await tab_to(orb), "creature orb reachable by keyboard")
				await key(KEY_ENTER)
				await stable(game)
				check(game.ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING and game._launch_target.visible, "creature Enter exposes production launch action")
			MatchController.Phase.AWAIT_LANDING:
				check(await tab_to(game._launch_target), "launch action reachable by keyboard")
				if not launch_navigation_checked:
					for card in game.ability_panel._cards:
						if card.is_visible_in_tree() and card.focus_mode == Control.FOCUS_ALL and not card.disabled:
							check(await tab_to(card), "launch action can reach optional pre-throw card by Tab")
							check(await tab_to(game._launch_target), "Tab returns from pre-throw card to launch action")
							break
					await key(KEY_TAB)
					var next := root.gui_get_focus_owner()
					check(next != game._launch_target, "Tab leaves launch for another live interface action")
					await key(KEY_TAB, false, null, true)
					check(game._launch_target.has_focus(), "Shift-Tab reverses the cross-panel launch navigation")
					launch_navigation_checked = true
				await key(KEY_ENTER)
				check(game.arena_slot_picker.visible, "launch action opens field choice")
				if not game.arena_slot_picker.visible: break
				var targets := game._gate_slots()
				for i in targets:
					var state: SlotState = game.ctrl.state.slots[i]
					if state.card_owner == 1 and not state.revealed:
						var secret := CardDB.card(state.card_id).display_name
						check(not game.arena_slot_picker._buttons[i].text.contains(secret) and not game.arena_slot_picker._buttons[i].tooltip_text.contains(secret), "masked enemy gate stays private in field label and full description")
				var target: int = targets[0]
				for i in targets:
					var occupant := game.ctrl.state.slots[i].occupant_uid
					if occupant >= 0 and game.ctrl.state.creature(occupant).owner == 1: target = i
				var old_landings: int = game.director.landings.size()
				if not await select_field_slot(game, target): break
				check(game.director.landings.size() == old_landings + 1 and not game.arena_slot_picker.visible, "single keyboard confirmation causes one deterministic landing and retires picker")
			MatchController.Phase.AFTER_LANDING:
				check(await tab_to(game.ability_panel._pass_btn), "post-landing finish action reachable by keyboard")
				await key(KEY_ENTER)
				post_landing_passes += 1
				await stable(game)
			MatchController.Phase.ABILITY_WINDOW:
				var preview := game.ctrl.get_battle_preview()
				if game.ctrl.state.creature(preview.attacker_uid).owner == 0: human_attacks += 1
				else: human_defences += 1
				if game.ctrl.can_reveal_gate(0):
					check(await tab_to(game.ability_panel._gate_btn), "open-own-gate action reachable by keyboard")
					var slot: int = preview.slot
					await key(KEY_ENTER)
					await stable(game)
					check(game.ctrl.state.slots[slot].revealed, "keyboard opens owned gate through production handler/controller")
					opened_gates += 1
				else:
					check(await tab_to(game.ability_panel._pass_btn), "battle pass reachable by keyboard")
					await key(KEY_ENTER)
					await stable(game)
			_:
				await stable(game)
	check(game.ctrl.get_phase() == MatchController.Phase.GAME_OVER and game._game_over and game.game_over_ui._panel.visible, "complete controller match reaches real GameOverUI; first player %d" % first)
	check(game.resolved.size() >= 3 and confirmed_results == game.resolved.size(), "every battle result acknowledged using keyboard before game over")
	check(not game.arena_slot_picker.visible and not game._launch_target.visible, "game over leaves no stale field or launch action")
	if game.game_over_ui._panel.visible:
		await frames()
		if is_instance_valid(game.game_over_help):
			check(game.game_over_help._close_button.has_focus(), "late game over preserves help keyboard focus")
			await key(KEY_ENTER, true)
			check(not is_instance_valid(game.game_over_help) and game.game_over_ui._panel.visible and game.restarts == 0, "first game-over Enter closes help without requesting repeat")
		check(game.game_over_ui._restart_button.has_focus(), "game over focuses repeat action")
		await key(KEY_ENTER, true)
		check(game.restarts == 1, "game over Enter requests one repeat through production signal")
	game.events.stop()
	game.queue_free()
	await frames(4)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	CardDB.load_all()
	AudioServer.set_bus_mute(0, true)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.theme = UiTheme.get_theme()
	check(Engine.max_fps == 60, "shared wrapper limits test to 60 FPS")
	# The fixture has already learned the optional coach tips; regular keyboard
	# targets remain production Controls and receive no forced focus in this test.
	for id in ["gate", "throw", "prethrow", "attach"]: HudUI._coached[id] = true
	if OS.get_cmdline_user_args().has("--combo-only"):
		await _run_combo_checks()
		return
	await scroll_description_check()
	await run_match(0)
	await run_match(1)
	check(human_attacks > 0 and human_defences > 0, "keyboard battle exchange exercised as human attacker and defender")
	check(post_landing_passes > 0 and opened_gates > 0, "post-landing pass and manual gate opening exercised")
	check(not invalid_tab_focus, "Tab never focuses hidden or disabled controls during both matches")
	var file := FileAccess.open(OUT.path_join("layout-and-keyboard.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "visual_acceptance": false, "physics_acceptance": false, "layouts": layout_evidence, "native_dialog_escape": native_escape_observations}, "\t"))
	file.close()
	print("UI keyboard match: %d checks, %d failures; deterministic landing, no GPU/physics/Windows claims" % [checks, failures])
	var sound := SoundFx.i()
	sound.cancel_match_sfx()
	for child in sound.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	sound._cache.clear()
	await frames(6)
	sound.queue_free()
	await frames(4)
	quit(1 if failures else 0)


func scroll_description_check() -> void:
	var picker := ArenaSlotPicker.new()
	root.add_child(picker)
	var paragraph := "Полное описание эффекта ворот доступно с клавиатуры. "
	var complete := paragraph.repeat(60)
	picker.show_slots([0, 3], MatchState.new(), "Чтение полного эффекта", func(_slot: int) -> String: return complete)
	await frames()
	var focused := root.gui_get_focus_owner()
	await key(KEY_PAGEDOWN)
	check(picker._description_scroll.scroll_vertical > 0 and root.gui_get_focus_owner() == focused, "PgDn scrolls a long full gate description while retaining slot focus")
	await key(KEY_END)
	var bottom := picker._description_scroll.scroll_vertical
	await key(KEY_PAGEUP)
	check(picker._description_scroll.scroll_vertical < bottom, "PgUp returns within long full description")
	await key(KEY_HOME)
	check(picker._description_scroll.scroll_vertical == 0 and picker._description.text == complete, "Home returns to start without shortening full gate text")
	check(root.get_visible_rect().encloses(picker._panel.get_global_rect()), "long description scrolls inside modal without expanding beyond 720p viewport")
	await key(KEY_ESCAPE)
	picker.queue_free()
	await frames()


func trace_count(game: MatchFixture, action: String, player: int = 0) -> int:
	var count := 0
	for entry in game.ctrl.action_trace:
		if entry[0] == action and not entry[1].is_empty() and int(entry[1][0]) == player: count += 1
	return count


func open_combo_selector(game: MatchFixture) -> bool:
	var cards := game.setup_panel._card_buttons.values()
	check(not cards.is_empty(), "combo fixture exposes real gate cards")
	if cards.is_empty(): return false
	check(await tab_to(cards[0]), "combo gate card reached with Tab")
	await key(KEY_ENTER)
	check(await tab_to(game.setup_panel._throw_btn), "gate-plus-throw toggle reached with Tab")
	await key(KEY_ENTER)
	check(game.setup_panel._throw_btn.button_pressed, "Enter enables actual gate-plus-throw toggle")
	check(await tab_to(game.setup_panel._slot_btn), "compound gate field action reached with Tab")
	await key(KEY_ENTER)
	check(game.arena_slot_picker.visible, "compound gate opens production field picker")
	if not game.arena_slot_picker.visible: return false
	await key(KEY_ENTER, true)
	await stable(game)
	check(not game.arena_slot_picker.visible and not game._gate_pick.is_empty() and game.hud._creature_panel.visible and game.hud._cancel_btn.visible, "field Enter opens reversible compound creature selector")
	return not game._gate_pick.is_empty() and game.hud._creature_panel.visible


func combo_scenario() -> Dictionary:
	var game := MatchFixture.new()
	root.add_child(game)
	await frames()
	game.ctrl.start(0)
	await stable(game)
	var original := game.ctrl.debug_snapshot()
	var hand_size := game.ctrl.state.players[0].arena_hand.size()
	if await open_combo_selector(game):
		var pick := game._gate_pick.duplicate()
		check(game.ctrl.debug_snapshot() == original and game.director.landings.is_empty(), "compound card/slot staging spends no controller action or throw")
		check(await tab_to(game.hud._help_btn), "Help reachable from compound creature selector")
		await key(KEY_ENTER)
		var help: HelpOverlay
		for child in game.ui_layer.get_children():
			if child is HelpOverlay: help = child
		check(is_instance_valid(help), "Help opens through actual HUD keyboard action")
		await key(KEY_ESCAPE)
		check(not is_instance_valid(help) and game._gate_pick == pick and game.hud._creature_panel.visible, "Help Escape returns to still-pending compound choice")
		check(game.hud._creature_box.get_child(0).has_focus(), "Help returns focus to compound creature, ahead of setup cards")
		check(game.ctrl.debug_snapshot() == original, "reading Help during compound choice spends no action")
		await key(KEY_ESCAPE)
		await stable(game)
		check(game._gate_pick.is_empty() and not game.hud._creature_panel.visible and game.setup_panel._panel.visible, "compound Escape returns to gate setup")
		check(game.ctrl.debug_snapshot() == original and game.ctrl.state.players[0].arena_hand.size() == hand_size and game.director.landings.is_empty(), "compound cancellation preserves hand, turn and all controller commands")
		check(root.gui_get_focus_owner() is CardView and game.setup_panel._owns_focus(), "compound cancellation focuses a live setup card")
		if await open_combo_selector(game):
			var final_pick := game._gate_pick.duplicate()
			var orb := game.hud._creature_box.get_child(0) as OrbButton
			var uid: int = orb.uid
			check(await tab_to(orb), "compound creature reachable with Tab after cancellation")
			await key(KEY_ENTER, true)
			await stable(game)
			check(trace_count(game, "throw_with_gate") == 1 and trace_count(game, "select_creature") == 0, "single creature Enter invokes actual throw_with_gate exactly once")
			check(game.ctrl.state.players[0].arena_hand.size() == hand_size - 1, "actual compound command spends exactly one gate")
			check(game.director.landings.size() == 1 and int(game.director.landings[0].uid) == uid and int(game.director.landings[0].slot) == int(final_pick.slot), "actual compound command launches exactly one selected creature to its chosen gate")
			check(game.ctrl.get_phase() == MatchController.Phase.AFTER_LANDING and game.ctrl.state.slots[int(final_pick.slot)].occupant_uid == uid, "compound deterministic landing reaches real controller post-landing window")
			check(game._gate_pick.is_empty() and not game.arena_slot_picker.visible, "compound completion retires its reversible choice and field modal")
	var result := {"actions": game.ctrl.action_trace.duplicate(true), "landings": game.director.landings.duplicate(true)}
	game.events.stop()
	game.queue_free()
	await frames(4)
	return result


func prethrow_scenario() -> Dictionary:
	var game := MatchFixture.new()
	root.add_child(game)
	await frames()
	game.ctrl.start(0)
	await stable(game)
	if await setup_with_keyboard(game, false):
		var orb := game.hud._creature_box.get_child(0) as OrbButton
		var uid: int = orb.uid
		check(await tab_to(orb), "pre-throw fixture selects creature through real keyboard orb")
		await key(KEY_ENTER)
		await stable(game)
		check(game.ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING and game.ctrl.get_ability_moment() == &"pre_throw", "pre-throw card is played in actual controller pre_throw moment")
		var chosen: CardView
		for card in game.ability_panel._cards:
			if game.ctrl.legal_abilities(0).has(card.card_id) and CardDB.card(card.card_id).effect_id == &"boost":
				chosen = card
				break
		check(is_instance_valid(chosen), "fixture exposes a legal boost card in actual pre-throw hand")
		if is_instance_valid(chosen):
			var cid := chosen.card_id
			var hand_size := game.ctrl.state.players[0].ability_hand.size()
			var attached_count := game.ctrl.state.creature(uid).attached.size()
			check(await tab_to(chosen), "legal pre-throw ability reached with Tab")
			await key(KEY_ENTER, true)
			await stable(game)
			check(trace_count(game, "play_ability") == 1 and game.ctrl.state.players[0].ability_hand.size() == hand_size - 1, "pre-throw Enter plays exactly one actual ability through Main and controller")
			var attached: Array = game.ctrl.state.creature(uid).attached
			check(attached.size() == attached_count + 1 and attached[-1][1] == cid, "played pre-throw card attaches exactly once to selected creature")
			check(game.ctrl.get_phase() == MatchController.Phase.AWAIT_LANDING and game.director.landings.is_empty() and game._launch_target.visible, "playing pre-throw card preserves pending launch without throwing early")
			check(await tab_to(game._launch_target), "launch remains keyboard reachable after actual ability play")
			await key(KEY_ENTER)
			check(game.arena_slot_picker.visible, "post-ability launch action opens real field picker")
			if game.arena_slot_picker.visible:
				await key(KEY_ENTER, true)
				await stable(game)
				check(game.director.landings.size() == 1 and game.ctrl.get_phase() == MatchController.Phase.AFTER_LANDING, "ability-enhanced creature launches once and reaches actual post-landing phase")
				check(game.ctrl.state.creature(uid).attached.size() == attached_count + 1, "pre-throw attachment survives deterministic landing")
	var result := {"actions": game.ctrl.action_trace.duplicate(true), "landings": game.director.landings.duplicate(true)}
	game.events.stop()
	game.queue_free()
	await frames(4)
	return result


func _run_combo_checks() -> void:
	var combo := await combo_scenario()
	var prethrow := await prethrow_scenario()
	check(not invalid_tab_focus, "combo and ability keyboard routes skip hidden/disabled controls")
	var file := FileAccess.open(OUT.path_join("combo-only.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "combo": combo, "prethrow": prethrow, "visual_acceptance": false, "physics_acceptance": false}, "\t"))
	file.close()
	print("UI keyboard combo: %d checks, %d failures; isolated compound/pre-throw scenarios, deterministic landing" % [checks, failures])
	var sound := SoundFx.i()
	sound.cancel_match_sfx()
	for child in sound.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	sound._cache.clear()
	await frames(6)
	sound.queue_free()
	await frames(4)
	quit(1 if failures else 0)
