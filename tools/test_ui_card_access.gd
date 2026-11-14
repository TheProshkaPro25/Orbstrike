extends SceneTree
## Узкая проверка D04/D06/D08/D09. Только через check.py/test_window, без 3D-моделей.

class TeamFixture extends TeamMenu:
	var shown: StringName = &""
	func _show_preview(id: StringName, _pose: bool) -> void:
		shown = id
		if _preview != null: _preview.show_hint("Предпросмотр без загрузки модели")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1
	print("PASS: " if condition else "FAIL: ", message)


func frames(n: int = 3) -> void:
	for _i in n: await process_frame


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.pressed = false
	root.push_input(event)
	await frames()


func wheel(control: Control, up: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.position = control.get_global_rect().get_center()
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	root.push_input(event)
	await frames()


func _run() -> void:
	CardDB.load_all()
	AudioServer.set_bus_mute(0, true)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.theme = UiTheme.get_theme()
	check(Engine.max_fps == 60, "shared wrapper limits tests to 60 FPS")
	var orb := OrbButton.new()
	root.add_child(orb)
	orb.size = orb.custom_minimum_size
	var count := 0
	for definition in CreatureModels.catalog_defs():
		orb.for_creature(definition, count)
		var fitted := orb.name_layout()
		var lines: PackedStringArray = fitted.lines
		var font := orb.get_theme_default_font()
		check(" ".join(lines) == definition.display_name and lines.size() <= 2, "full two-line name: " + definition.display_name)
		var inside := true
		for line in lines:
			inside = inside and font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted.font_size).x <= orb.size.x - 6.0
		check(inside and fitted.font_size >= 13, "name fits its own 118px button: " + definition.display_name)
		count += 1
	check(count == 61, "all 61 creature definitions covered")
	orb.grab_focus()
	await frames()
	check(orb.has_focus() and is_instance_valid(orb._focus_disclosure), "orb keyboard focus opens full creature help")
	var orb_activations: Array = []
	orb.pressed.connect(func() -> void: orb_activations.append(true))
	await key(KEY_ENTER)
	check(orb_activations.size() == 1, "Enter selects focused orb once")
	orb.queue_free()
	await frames()
	var gates: Array = []
	var abilities: Array = []
	for cls in CardDB.GATE_CLASSES:
		gates.append_array(CardDB.cards_of(CardDef.Kind.ARENA, cls, 0, []))
	for cls in CardDB.ABILITY_CLASSES:
		abilities.append_array(CardDB.cards_of(CardDef.Kind.ABILITY, cls, 0, []))
	# Species-free fixtures need only two pages; repeated IDs are avoided.
	check(gates.size() > 3 and abilities.size() > 4, "fixture has multiple pages in both hands")
	var setup := SetupPanel.new()
	var ability := AbilityPanel.new()
	root.add_child(setup)
	root.add_child(ability)
	var defs: Array = []
	for id in gates: defs.append(CardDB.card(id))
	setup.begin(defs, [0, 1], true)
	ability.set_hand(abilities)
	ability.set_dock_visible(true)
	await frames()
	var selected: StringName = setup._card_buttons.keys()[0]
	setup._on_card_pressed(selected)
	var card: CardView = setup._card_buttons.values()[0]
	card.grab_focus()
	await frames()
	check(is_instance_valid(card._focus_disclosure), "gate focus opens complete card")
	check(root.get_visible_rect().encloses(card._focus_disclosure._panel.get_global_rect()), "focus disclosure stays inside logical viewport")
	await key(KEY_RIGHT)
	check(setup._page == 1 and ability._page == 0, "right arrow in gate hand changes only gate page")
	check(setup._selected == selected, "paging preserves selected gate without spending it")
	check(setup._owns_focus(), "gate page rebuild keeps keyboard focus in gate hand")
	await key(KEY_LEFT)
	check(setup._page == 0 and ability._page == 0, "left arrow returns gate page only")
	await wheel(setup._card_buttons.values()[0])
	check(setup._page == 1 and ability._page == 0, "wheel over gate changes only gate page")
	check(setup._selected == selected, "wheel preserves chosen gate")
	ability._cards[0].grab_focus()
	await frames()
	await key(KEY_RIGHT)
	check(ability._page == 1 and setup._page == 1, "right arrow in ability hand changes only ability page")
	check(ability._owns_focus(), "ability page rebuild keeps keyboard focus in ability hand")
	await key(KEY_LEFT)
	check(ability._page == 0 and setup._page == 1, "left arrow returns ability page only")
	await wheel(ability._cards[0])
	check(ability._page == 1 and setup._page == 1, "wheel over ability changes only ability page")
	setup._card_buttons.values()[0].grab_focus()
	await key(KEY_ESCAPE)
	check(setup._selected == &"", "Escape clears gate choice without placement")
	var outsider := Button.new()
	outsider.text = "Outside both hands"
	root.add_child(outsider)
	outsider.grab_focus()
	await key(KEY_LEFT)
	check(setup._page == 1 and ability._page == 1, "arrows outside both hands do not page either hand")
	setup.queue_free()
	ability.queue_free()
	outsider.queue_free()
	await frames()
	var team := TeamFixture.new()
	root.add_child(team)
	await frames()
	team._show_step(0)
	await frames()
	for button in team._filters.get_children():
		check(button.focus_mode == Control.FOCUS_ALL and button.tooltip_text.contains("Автоматического преимущества") and not button.tooltip_text.contains("бьёт"), "element focus and truthful compatibility help")
	var creature_id: StringName = team._team[0]
	var creature: CardView = team._cards[creature_id]
	creature.grab_focus()
	await frames()
	check(team.shown == creature_id and creature.has_focus(), "team creature focus updates permanent large preview")
	var before := team._team.has(creature_id)
	await key(KEY_ENTER)
	check(team._team.has(creature_id) != before, "Enter toggles focused team creature")
	team._show_step(1)
	await frames()
	var gate_id: StringName = team._cards.keys()[0]
	var gate: CardView = team._cards[gate_id]
	gate.grab_focus()
	await frames()
	check(team.shown == gate_id, "team gate focus updates full card preview")
	var cls := CardDB.card_class(CardDB.card(gate_id))
	var picked: bool = team._pick.get(cls, &"") == gate_id
	var gate_presses: Array = []
	gate.pressed.connect(func() -> void: gate_presses.append(true))
	await key(KEY_ENTER)
	check((team._pick.get(cls, &"") == gate_id) != picked and gate_presses.size() == 1, "Enter toggles focused deck card once")
	team.queue_free()
	await frames()
	var source := CardView.new().for_card(CardDB.card(abilities[0]))
	root.add_child(source)
	source.grab_focus()
	var picker := AbilityTargetPicker.new()
	root.add_child(picker)
	await frames()
	picker.show_targets(abilities[0], [{"target_card": gates[0]}, {"target_card": gates[1]}], null)
	await frames()
	check(picker._choices.get_child(0).has_focus(), "target dialog starts focused on first legal target")
	var visits: Array = []
	for i in 3:
		await key(KEY_TAB)
		visits.append(root.gui_get_focus_owner())
	check(visits[0] == picker._choices.get_child(1) and visits[1] == picker._cancel and visits[2] == picker._choices.get_child(0), "Tab cycles only legal targets and cancel")
	for code in [KEY_LEFT, KEY_UP, KEY_DOWN, KEY_RIGHT]:
		await key(code)
		check(picker.is_ancestor_of(root.gui_get_focus_owner()), "modal arrow stays within targets/cancel: " + str(code))
	await key(KEY_ESCAPE)
	check(not picker.visible and source.has_focus(), "Escape closes target dialog and restores source focus")
	var chosen: Array = []
	picker.chosen.connect(func(target: Dictionary) -> void: chosen.append(target))
	picker.show_targets(abilities[0], [{"target_card": gates[0]}], null)
	await frames()
	await key(KEY_ENTER)
	check(chosen.size() == 1 and chosen[0].target_card == gates[0], "Enter confirms exactly the focused legal target")
	picker.queue_free()
	source.queue_free()
	await frames()
	# Production ordering: animation removes the source before Main opens targets.
	# Cancellation rebuilds from controller entries, rather than restoring a Node.
	var hand := AbilityPanel.new()
	root.add_child(hand)
	var modal := AbilityTargetPicker.new()
	root.add_child(modal)
	var entries: Array = []
	for id in abilities: entries.append({"id": id})
	hand.set_hand(abilities)
	hand.show_options(entries)
	hand._change_page(1)
	await frames()
	var cancelled_id := hand._cards[0].card_id
	var source_node := hand._cards[0]
	hand.ability_chosen.connect(func(id: StringName) -> void:
		hand.hide_panel()
		modal.show_targets(id, [{"target_card": gates[0]}], null))
	modal.cancelled.connect(func() -> void: hand.show_options(entries))
	source_node.grab_focus()
	await frames()
	await key(KEY_ENTER)
	check(modal.visible and source_node.focus_mode == Control.FOCUS_NONE and not hand._cards.has(source_node), "production ability activation removes source before target choice")
	await key(KEY_ESCAPE)
	var restored := root.gui_get_focus_owner() as CardView
	check(not modal.visible and restored != null and restored != source_node and restored.card_id == cancelled_id and hand._page == 1, "cancel restores rebuilt ability by ID and returns to its page")
	check(hand._pending_focus_id == &"", "source focus request is consumed once")
	hand.queue_free()
	modal.queue_free()
	await frames()
	print("UI card access: %d checks, %d failures; headless assertions are not GPU/visual acceptance" % [checks, failures])
	quit(1 if failures else 0)
