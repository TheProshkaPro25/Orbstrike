extends SceneTree
## Match UI, real queued effects and 3D actors. The encounter is seeded at the
## landing slot to make the defender, powers and card sequence reproducible.

class CounterAI extends AIPlayer:
	var counter: StringName
	func choose_ability(_view: MatchState, preview: BattleResult, legal = null) -> StringName:
		if legal != null and legal.has(counter):
			for play in preview.plays:
				if play[1] == &"ability_fire_drain": return counter
		return &""
	func should_open_gate(_view: MatchState, _preview: BattleResult) -> bool:
		return false

const DRAIN := &"ability_fire_drain"
const BOOST := &"ability_fire_spark"
const FIELD := &"arena_field_fire"
const GALE_CALL := &"ability_gale_call"
const GALE_SWAP := &"ability_gale_swap"
const SIZES := [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1024, 768)]
const POPUP_PATH := SoundFx.SFX_DIR + "ui_battle_popup"

var game: Node
var out: String
var checks := 0
var failures := 0
var popup: AudioStream


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if not args.is_empty() else "res://build/checks/presentation/device-battle-hud"
	var bright := OS.get_environment("ORBSTRIKE_DEVICE_BRIGHT") == "1"
	if bright: out = out.path_join("canyon")
	DirAccess.make_dir_recursive_absolute(out)
	DeviceSettings.settings_path = out.path_join("isolated-settings.cfg")
	DeviceSettings.reload_settings()
	DeviceSettings.set_reduce_motion(false)
	AudioSettings.settings_path = DeviceSettings.settings_path
	AudioSettings.load_and_apply()
	AudioSettings.set_interface_muted(false)
	AudioSettings.set_volume("Interface", 0.6)
	var sound := SoundFx.i()
	sound.preload_catalog()
	popup = sound._cache.get(POPUP_PATH)
	_check(popup is AudioStreamOggVorbis and popup.get_length() > .35 and popup.get_length() < .42, "short popup recording is cached at boot")
	CardDB.load_all()
	preload("res://data/arena_locations.gd").choose(1 if bright else 0)
	_size(SIZES[0])
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.rng.seed = 62831
	var deck := CardDB.preset_deck(0)
	var creatures: Array[StringName] = []
	var gates: Array[StringName] = []
	var abilities: Array[StringName] = []
	for creature in deck.creatures: creatures.append(creature.id)
	for card in deck.arena: gates.append(card.id)
	for card in deck.abilities: abilities.append(card.id)
	var field := FIELD
	if bright:
		field = &"arena_field_gale"
		creatures.assign([&"creature_dragnar_gale", &"creature_klykar_gale", &"creature_grifalon_gale"])
		gates[0] = field
		abilities.assign([GALE_CALL, &"ability_gale_gust", &"ability_dragnar_heart"])
	game.team_menu.hide()
	game._on_deck_chosen(creatures, gates, abilities)
	if not await _until(func() -> bool: return game._next_turn.is_visible_in_tree() and not game.events.is_busy(), "first turn waits for the player"):
		await _finish()
		return
	_check(game.ctrl.get_turn() == 0 and not game.setup_panel._panel.visible, "waiting does not open the gate action")
	await _click(game._next_turn)
	if not await _until(func() -> bool: return game.setup_panel._panel.visible and not game.events.is_busy(), "setup opens"):
		await _finish()
		return
	game.hud._close_coach()
	game.hud.set_names("Александра Северная", "Мирослав Ветров")
	var ctrl: MatchController = game.ctrl
	var setup: SetupPanel = game.setup_panel
	var ability: AbilityPanel = game.ability_panel
	var battle: BattleHud = game.battle_hud
	var hud: HudUI = game.hud
	var slot := ctrl.legal_setup_slots()[0]
	var gate: CardView = setup._card_buttons[field]
	await _click(gate)
	_check(setup._selected == gate.card_id and not setup._slot_btn.disabled, "gate click selects card and enables field picker")
	for _i in 14:
		if root.gui_get_focus_owner() == setup._slot_btn: break
		await _key(KEY_TAB)
	await _key(KEY_ENTER)
	_check(game.arena_slot_picker.visible, "keyboard opens field picker")
	await _key(KEY_ESCAPE)
	_check(not game.arena_slot_picker.visible and setup._selected == gate.card_id, "Esc returns to selected gate")
	await _save("setup")
	game._on_slot_picked(slot)
	if not await _until(func() -> bool: return hud._creature_panel.visible and not game.events.is_busy(), "gate is placed and throw selector opens"):
		await _finish()
		return

	# Match starts with the player defending their own still-closed gate.
	hud.hide_creatures()
	game.interaction.clear_request()
	var rival := CounterAI.new(1, 803)
	game.interaction.ai = rival
	var defender_uid := ctrl.state.players[0].creature_uids[0]
	var attacker_uid := ctrl.state.players[1].creature_uids[0]
	ctrl.state.slots[slot].card_id = field
	ctrl.state.slots[slot].card_owner = 0
	ctrl.state.slots[slot].revealed = false
	ctrl.state.slots[slot].occupant_uid = defender_uid
	ctrl.state.creature(defender_uid).slot = slot
	ctrl.state.players[0].arena_hand.assign(CardDB.arena_ids().slice(0, 12))
	var hand: Array = CardDB.ability_ids().slice(0, 16)
	for id in ([GALE_SWAP, GALE_CALL] if bright else [BOOST, DRAIN]):
		hand.erase(id)
		hand.push_front(id)
	ctrl.state.players[0].ability_hand.assign(hand)
	if bright:
		var support_slot := posmod(slot + 1, ctrl.state.slots.size())
		var support := ctrl.state.players[0].creature_uids[1]
		ctrl.state.creature(support).slot = support_slot
		ctrl.state.slots[support_slot].has_card = true
		ctrl.state.slots[support_slot].card_id = field
		ctrl.state.slots[support_slot].card_owner = 0
		ctrl.state.slots[support_slot].occupant_uid = support
		for uid in ctrl.state.players[0].creature_uids:
			CreaturePortrait._prepare_reference(game.presentation.creature_def(uid).id)
	var boosts := [&"ability_fire_spark", &"ability_gale_gust", &"ability_light_glint", &"ability_stone_firm", &"ability_shadow_haze", &"ability_tide_spray"]
	var counters := [&"ability_fire_counter", &"ability_gale_rebuttal", &"ability_light_counter", &"ability_stone_counter", &"ability_shadow_counter", &"ability_tide_counter"]
	var attr: int = game.presentation.creature_def(attacker_uid).attribute
	rival.counter = counters[attr]
	ctrl.state.players[1].ability_hand.assign([boosts[attr], rival.counter])
	for uid in [defender_uid, attacker_uid]:
		CreaturePortrait._prepare_reference(game.presentation.creature_def(uid).id)
		var actor: CreatureBall = game.presentation.spawn_ball(uid)
		actor.freeze_at(game.arena.slot_position(slot) + Vector3(0, CreatureBall.RADIUS, 0))
		if uid == defender_uid: game.director.open_creature(actor, false)
	game.presentation.refresh_hand()
	BattleTempo.set_tempo(3)
	hud._tempo.select(3)
	ctrl._start_battle(attacker_uid, defender_uid, slot)
	if not await _until(func() -> bool: return ability._panel.visible and not game.events.is_busy(), "defender's real battle response opens"):
		await _finish()
		return
	var before := ctrl.get_battle_preview()
	_check(before != null and not ctrl.state.slots[slot].revealed, "gate remains closed at the response")
	_check(hud.own_panel._uid == defender_uid and hud.opponent_panel._uid == attacker_uid, "HUD keeps player on the left while defending")
	await _frames(28)
	for dimensions in ([SIZES[1], SIZES[2]] if bright else SIZES):
		_size(dimensions)
		await _frames(6)
		_verify_layout(hud, setup, ability, battle)
		await _save("reply-%dx%d" % [dimensions.x, dimensions.y])
	_size(SIZES[1])
	await _frames(5)
	if bright:
		await _test_target_and_swap(ctrl, hud, ability, battle, defender_uid)
		await _finish()
		return
	var idle_gate: CardView = setup._card_buttons.values()[0]
	await _click(idle_gate)
	_check(not idle_gate.button_pressed and setup._selected == &"" and idle_gate._help[6].contains("выкладки"), "gate outside setup shows the reason without selecting")
	AudioSettings.set_interface_muted(true)
	await _click(ability._gate_btn)
	if not await _until(func() -> bool: return battle._effect.visible, "queued gate effect becomes visible"):
		await _finish()
		return
	_check(battle._effect_title.text == "Поле Пламени" and battle._effect_target.text.ends_with(str(slot + 1)), "gate event identifies public card and slot")
	_check(not sound._last_play.has("ui_battle_popup"), "muted Interface skips the gate popup cue")
	AudioSettings.set_interface_muted(false)
	await _frames(4)
	await _save("opened-gate")
	await _key(KEY_ENTER)
	if not await _until(func() -> bool: return ability._panel.visible and not game.events.is_busy(), "control returns after gate effect"):
		await _finish()
		return
	_check(not ability._gate_btn.visible and ctrl.state.slots[slot].revealed, "opened gate is no longer an available action")
	var after_gate := ctrl.get_battle_preview()
	_check(after_gate.powers[1] == before.powers[1] + 120, "closed gate gave no G before opening")
	var drain: CardView
	for card in ability._cards:
		if card.card_id == DRAIN: drain = card
	if not _check(drain != null, "legal drain is visible on the first page"):
		await _finish()
		return
	BattleTempo.set_tempo(0)
	hud._tempo.select(0)
	DeviceSettings.set_reduce_motion(true)
	await _click(drain)
	if not await _until(func() -> bool: return battle._effect.visible, "queued ability effect becomes visible"):
		await _finish()
		return
	_check(battle._effect_title.text == "Пожирающий жар" and battle._effect_source.text.contains("Драгнар") and battle._effect_target.text.ends_with("Оба бойца"), "ability event identifies card, source and affected fighters")
	_check_popup_sound("ability event")
	var shown := ctrl.get_battle_preview()
	_check(hud.own_panel._power.text == "%d" % shown.powers[1] and hud.opponent_panel._power.text == "%d" % shown.powers[0], "applied G matches calculation in the same frame under reduced motion")
	_check(shown.powers[1] == after_gate.powers[1] + 100 and shown.powers[0] == after_gate.powers[0] - 100, "drain changes correct sides")
	_check(battle._floating_numbers.size() == 2, "two simultaneous deltas")
	await _frames(4)
	await _save("ability-960x540")
	_size(SIZES[2])
	await _frames(6)
	_check(root.get_visible_rect().encloses(battle._effect.get_global_rect()), "event stays inside resized viewport")
	await _save("ability-1024x768")
	await _key(KEY_ENTER)
	if not await _until(func() -> bool: return battle._effect.visible and battle._effect_title.text != "Пожирающий жар", "opponent can answer after the earlier pass"):
		await _finish()
		return
	_check(battle._effect_target.text.contains("Пожирающий жар"), "counter identifies the cancelled card")
	_check_popup_sound("counter event")
	await _key(KEY_ENTER)
	if not await _until(func() -> bool: return ability._panel.visible and not game.events.is_busy(), "player gets another response after counter"):
		await _finish()
		return
	var cancelled := ctrl.get_battle_preview()
	_check(cancelled.cancelled_plays.has([1, DRAIN]) and cancelled.ability_counts[1] == 1, "cancelled drain keeps its spent ability")
	_check(battle._chain.get_child(0).get_child(0).text.begins_with("×"), "chain marks cancelled card")
	_check(hud.own_panel._power.text == "%d" % after_gate.powers[1] and hud.opponent_panel._power.text == "%d" % after_gate.powers[0], "cancelled drain restores calculated powers")
	await _save("counter")
	var boost := _visible_card(ability, BOOST)
	if not _check(boost != null, "ordinary G boost is available in the reply"):
		await _finish()
		return
	await _click(boost)
	var boost_banner_seen := [false]
	if not await _until(func() -> bool:
		boost_banner_seen[0] = boost_banner_seen[0] or battle._effect.visible
		return battle._floating_numbers.any(func(delta: Label) -> bool: return delta.text == "+30" and delta.get_meta("battle_side", -1) == 1),
		"ordinary boost shows +30 on the defender"):
		await _finish()
		return
	var boosted := ctrl.get_battle_preview()
	_check(boosted.powers[1] == after_gate.powers[1] + 30 and boosted.powers[0] == after_gate.powers[0],
		"ordinary boost updates only its author's power")
	_check(battle._chain.visible and battle._chain.get_children().any(func(chip: Control) -> bool:
		return chip.get_child(0).text == CardDB.card(BOOST).display_name), "ordinary boost remains in the played-card row")
	await _save("ordinary-boost")
	if not await _until(func() -> bool:
		boost_banner_seen[0] = boost_banner_seen[0] or battle._effect.visible
		return ability._panel.visible and not game.events.is_busy(), "ordinary boost returns to the response without acknowledgment"):
		await _finish()
		return
	_check(not boost_banner_seen[0], "ordinary boost never opens a center announcement")
	await _click(ability._pass_btn)
	if await _until(func() -> bool: return game.battle_overlay._open, "two passes show the result", 900):
		_check_popup_sound("battle result")
		await _save("result")
		await _key(KEY_ENTER)
		await _until(func() -> bool: return not game.battle_overlay._open, "Enter confirms result")
	await _test_popup_scope(hud)
	await _finish()


func _test_popup_scope(hud: HudUI) -> void:
	var sound := SoundFx.i()
	sound._last_play.erase("ui_battle_popup")
	hud.flash("Промах")
	hud.clear_flash()
	_check(not sound._last_play.has("ui_battle_popup"), "turn messages do not use the battle popup cue")
	var before := sound._next
	hud.banner("БОЙ ПРЕРВАН", "Отлив", Color.WHITE, 0.05, true)
	_check(sound._next == (before + 1) % SoundFx.POOL, "special-result banner plays exactly one cue")
	_check_popup_sound("special-result banner")
	sound._last_play.erase("ui_battle_popup")
	AudioSettings.set_volume("Interface", 0.0)
	hud.banner("ВОЗВРАЩЕНИЕ", "Существо снова в игре", Color.WHITE, 0.05, true)
	_check(not sound._last_play.has("ui_battle_popup"), "zero Interface volume skips the popup cue")


func _check_popup_sound(label: String) -> void:
	var sound := SoundFx.i()
	var player := sound._pool[posmod(sound._next - 1, SoundFx.POOL)]
	var interface_bus := AudioServer.get_bus_index("Interface")
	_check(player.stream != null and player.stream == popup and player.bus == "Interface" and is_equal_approx(player.pitch_scale, 1.0), "%s plays the cached popup cue through Interface" % label)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(interface_bus), SoundFx.SFX_DB + linear_to_db(.6)), "%s respects Interface volume" % label)


func _test_target_and_swap(ctrl: MatchController, hud: HudUI, ability: AbilityPanel, battle: BattleHud, defender_uid: int) -> void:
	var call_card := _visible_card(ability, GALE_CALL)
	if not _check(call_card != null, "targeted card is visible in bright battle"): return
	await _click(call_card)
	var picker: AbilityTargetPicker = game.ability_target_picker
	_check(picker.visible and ctrl.legal_ability_targets(0, GALE_CALL).size() == 1, "only the legal support target is offered")
	await _frames(4)
	var target_card := root.gui_get_focus_owner() as CardView
	if _check(target_card != null and is_instance_valid(target_card._focus_disclosure), "keyboard opens full support conditions"):
		var hint: Control = target_card._focus_disclosure._panel
		_check(not hint.get_global_rect().intersects(target_card.get_global_rect()), "target conditions stay beside the selected card")
	await _save("target")
	await _key(KEY_ESCAPE)
	var focused := root.gui_get_focus_owner() as CardView
	_check(not picker.visible and focused != null and focused.card_id == GALE_CALL, "Esc returns focus to the targeted card")
	_check(ctrl.get_battle_preview().ability_counts[1] == 0 and ctrl.state.players[0].ability_hand.has(GALE_CALL), "cancelled choice spends no ability")
	var swap_card := _visible_card(ability, GALE_SWAP)
	if not _check(swap_card != null, "replacement card is visible"): return
	DeviceSettings.set_reduce_motion(true)
	await _click(swap_card)
	if not await _until(func() -> bool: return battle._effect.visible and battle._effect_title.text == "Вихревая подмена", "replacement event shown after the new fighter enters"):
		return
	var preview := ctrl.get_battle_preview()
	_check(preview.defender_uid != defender_uid and hud.own_panel._uid == preview.defender_uid, "new defender occupies the same left HUD lane")
	_check(hud.own_panel._power.text == "%d" % preview.powers[1] and hud.opponent_panel._power.text == "%d" % preview.powers[0], "replacement updates identity and calculated G together")
	_check(battle._effect_target.text.contains("Драгнар"), "replacement identifies the departing fighter")
	await _frames(4)
	await _save("swap")
	await _key(KEY_ENTER)
	await _until(func() -> bool: return not game.events.is_busy(), "replacement presentation completes")


func _visible_card(ability: AbilityPanel, id: StringName) -> CardView:
	for card: CardView in ability._cards:
		if card.card_id == id: return card
	return null


func _verify_layout(hud: HudUI, setup: SetupPanel, ability: AbilityPanel, battle: BattleHud) -> void:
	var viewport := root.get_visible_rect()
	var left := hud.own_panel.get_global_rect()
	var right := hud.opponent_panel.get_global_rect()
	var left_dock := setup._device_dock.get_global_rect()
	var right_dock := ability._device_dock.get_global_rect()
	var actions := ability._panel.get_global_rect()
	_check(viewport.encloses(left) and viewport.encloses(right) and left.size == right.size, "symmetric public side panels fit")
	_check(left.end.x < viewport.size.x * .25 and right.position.x > viewport.size.x * .75, "fighter panels leave the arena center open")
	_check(not left.intersects(left_dock) and not right.intersects(right_dock), "fighter panels clear the hands")
	_check(not actions.intersects(left_dock) and not actions.intersects(right_dock) and viewport.encloses(actions), "response buttons have their own lane")
	for card: CardView in ability._cards:
		_check(right_dock.encloses(card.get_global_rect()), "ability fits inside right dock")
	for card: CardView in setup._card_buttons.values():
		_check(left_dock.encloses(card.get_global_rect()), "gate fits inside left dock")
	_check(battle._chain.visible and not battle._chain.get_global_rect().intersects(left) and not battle._chain.get_global_rect().intersects(right), "played-card row avoids the fighters")


func _size(dimensions: Vector2i) -> void:
	root.size = dimensions
	root.content_scale_size = dimensions


func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	await process_frame
	for down in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.position = at
		button.pressed = down
		root.push_input(button, true)
		await process_frame


func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame


func _frames(count: int) -> void:
	for _i in count: await process_frame


func _until(condition: Callable, message: String, budget: int = 1400) -> bool:
	for _i in budget:
		if condition.call(): return _check(true, message)
		await process_frame
	return _check(false, message)


func _check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL: ") + message)
	return ok


func _save(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture.get_size() == root.size and picture.save_png(out.path_join(label + ".png")) == OK, "rendered " + label)
	if label.begins_with("reply-"):
		for panel: OpponentPanel in [game.hud.own_panel, game.hud.opponent_panel]:
			_check_rounded_portrait(picture, panel._portrait.get_global_rect())


func _check_rounded_portrait(picture: Image, rect: Rect2) -> void:
	var start := Vector2i(rect.position.round())
	var end := Vector2i(rect.end.round()) - Vector2i.ONE
	for side in [1, -1]:
		for height in [1, -1]:
			var vertex := Vector2i(start.x if side == 1 else end.x, start.y if height == 1 else end.y)
			var direction := Vector2i(side, height)
			var panel_ink := picture.get_pixelv(vertex + Vector2i(-side, height))
			var corner := picture.get_pixelv(vertex + direction)
			var field := picture.get_pixelv(vertex + direction * 9)
			_check(_rgb_distance(corner, panel_ink) < 0.04, "portrait corner reveals the containing panel")
			_check(_rgb_distance(field, panel_ink) > 0.10, "rounded corner still encloses a filled element field")


func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func _finish() -> void:
	game.queue_free()
	await _frames(5)
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await _frames(5)
	print("DEVICE BATTLE HUD %d/%d" % [checks, failures])
	quit(1 if failures else 0)
