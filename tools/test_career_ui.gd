extends SceneTree
## Узкий 2D-стенд: отдельная карьера без пользовательского сохранения и без GLB.
const PANEL := preload("res://scenes/ui/career_panel.gd")
const CAREER := preload("res://core/career.gd")
var _out := "res://build/checks/career-ui"
var _panel: CareerPanel
var _checks := 0
var _failures := 0
var _create_args: Array = []
var _registration: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	# Mirror Boot preparation for this isolated 2D fixture; getters do no work.
	preload("res://scenes/ui/creature_portrait.gd").preload_catalog()
	_panel = PANEL.new()
	root.add_child(_panel)
	_panel.create_requested.connect(func(element: int, difficulty: int) -> void: _create_args = [element, difficulty])
	_panel.registration_requested.connect(func(creatures: Array[StringName], gates: Array[StringName], abilities: Array[StringName], levels: Dictionary) -> void: _registration = [creatures, gates, abilities, levels])
	_panel.display(null)
	await _settle(Vector2i(960, 540))
	_check(_panel._element_choice.item_count == 6, "первый шаг: шесть стихий")
	await _click(_panel.find_child("CareerElementTile4", true, false))
	await _click(_panel.find_child("CareerDifficultyTile2", true, false))
	_panel._action.pressed.emit()
	_check(_create_args == [4, 2], "создание передаёт выбранные стихию и сложность")
	await _shot("onboarding-960")
	var career := CAREER.create("fire", 1, 771, "UI fixture", "")
	_check(career != null, "изолированная карьера без записи пользовательских данных")
	if career == null:
		_finish()
		return
	_panel.display(career)
	_check(_panel._team.size() == 3, "сразу выбрана законная стартовая тройка")
	_check(not _panel._action.disabled, "законная стартовая колода готова к регистрации")
	_panel._action.pressed.emit()
	_check(_registration.size() == 4 and _registration[0].size() == 3 and _registration[1].size() == 3 and _registration[2].size() == 3, "регистрация передаёт 3 существ, 3 ворот, 3 способности и уровни")
	for dimensions in [Vector2i(960, 540), Vector2i(1280, 720)]:
		await _settle(dimensions)
		for tab in range(4):
			_panel._switch_tab(tab)
			await process_frame
			await process_frame
			_check_layout(dimensions)
			await _shot("tab-%d-%d" % [tab, dimensions.x])
	var before: int = career.state.credits
	var item := &""
	for id in CardDB.ability_ids():
		if CardDB.card_class(CardDB.card(id)) == &"blue" and not career.state.owned_cards.has(String(id)) and career.price(id) > 0 and career.price(id) <= before:
			item = id
			break
	_check(item != &"", "есть точная покупка по средствам")
	if item != &"":
		var price: int = career.price(item)
		_panel._purchase(item)
		_check(career.state.credits == before - price and career.state.owned_cards.has(String(item)), "кнопка покупки выдаёт указанный предмет за указанную цену")
		_panel._purchase(item)
		_check(career.state.credits == before - price, "повторная покупка не списывает кредиты")
	_panel.show_error("")
	_panel._switch_tab(1)
	await _click(_panel.find_child("CareerDeckKind1", true, false))
	await process_frame
	_check(_panel.find_child("CareerCard_blue", true, false) != null and _panel.find_child("CareerCard_gold", true, false) == null, "способности переключаются отдельным явным действием")
	await _shot("abilities-1280")
	await _click(_panel.find_child("CareerCard_blue", true, false))
	await process_frame
	await _shot("choose-card-1280")
	# The conditions window must be a modal child of the card chooser.
	_panel._show_card(StringName(_panel._picks[&"blue"]))
	await process_frame
	var nested := _panel.find_children("*", "AcceptDialog", true, false)
	_check(nested.size() == 2 and nested[1].get_parent() == nested[0], "полные условия вложены в выбор карты без конфликта modal")
	nested[1].hide()
	nested[1].queue_free()
	await process_frame
	var selected_card := item
	_check(selected_card != _panel._picks[&"blue"], "для замены выбран новый id карты")
	await _click(_panel.find_child("CareerPick_" + String(selected_card), true, false))
	await process_frame
	_check(_panel.find_child("CareerPick_" + String(selected_card), true, false) == null, "реальный щелчок закрывает выбор карты")
	_check(_panel._picks[&"blue"] == selected_card, "выбор варианта меняет карту нужного класса")
	_panel._action.pressed.emit()
	_check(_registration[2].has(selected_card), "новая карта передана в регистрацию кубка")
	_panel._show_card(selected_card)
	await process_frame
	await _shot("card-conditions-1280")
	for dialog in _panel.find_children("*", "AcceptDialog", true, false):
		dialog.hide()
		dialog.queue_free()
	await process_frame
	_panel._show_guide()
	await process_frame
	await _shot("career-guide-1280")
	for dialog in _panel.find_children("*", "AcceptDialog", true, false):
		dialog.hide()
		dialog.queue_free()
	await process_frame
	_panel._switch_tab(2)
	await process_frame
	for kind in 3:
		await _click(_panel.find_child("CareerShopKind%d" % kind, true, false))
		_check(_panel._shop_kind == kind, "реальный щелчок переключает категорию магазина")
		await _shot("shop-kind-%d-1280" % kind)
	_panel._tab = 0
	_panel._toggle_creature(_panel._team[0])
	_check(_panel._team.size() == 2 and _panel._action.disabled, "нельзя зарегистрировать неполную команду")
	_panel.display(null)
	_panel.display(career)
	_check(career.start_cup(CardDB.build_deck(_panel._team, _panel._ids(CardDB.GATE_CLASSES), _panel._ids(CardDB.ABILITY_CLASSES)), _panel._levels) == OK, "регистрация из выбора UI")
	_panel.display(career)
	var locked := _panel._team.duplicate()
	_panel._toggle_creature(_panel._team[0])
	_check(_panel._team == locked and _panel._action.text == "Продолжить кубок", "состав закреплён и доступно продолжение")
	_check(_panel._levels == career.state.active.levels, "видимые боевые уровни равны снимку кубка")
	await _settle(Vector2i(960, 540))
	_panel._switch_tab(0)
	await process_frame
	_check_layout(Vector2i(960, 540))
	await _shot("device-team-960")
	await _settle(Vector2i(1280, 720))
	_panel._switch_tab(1)
	await process_frame
	_check_layout(Vector2i(1280, 720))
	await _shot("device-cards-1280")
	# Cup completion fixtures only test dashboard transitions, not physical matches.
	while not career.cup.completed():
		var duel: Dictionary = career.cup.next_match()
		_check(career.record_result(String(duel.id), int(duel.a), [3, 0], "ui-fixture", {"throws": 3, "battles": 1}) == OK, "фикстура завершает встречу для экрана прогресса")
	_panel.display(career)
	_panel._switch_tab(3)
	await process_frame
	_check(_panel._action.text == "Следующая лига" and _panel._extra.visible, "после кубка явные действия следующей лиги и повтора")
	await _shot("completed-cup-1280")
	_check(career.advance_cup() == OK, "переход к следующей регистрации")
	_panel.display(career)
	_panel._switch_tab(0)
	await process_frame
	_check(not _panel._roster_locked() and not _panel._action.disabled, "новая лига разрешает состав и готовую регистрацию")
	await _shot("next-league-1280")
	_finish()


func _click(button: Control) -> void:
	await process_frame
	var ancestor := button.get_parent()
	while ancestor != null and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer:
		ancestor.ensure_control_visible(button)
		await process_frame
		await process_frame
	var point := button.get_global_rect().get_center()
	if button.get_window() != root:
		point += Vector2(button.get_window().position)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	var press := InputEventMouseButton.new()
	press.position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = point
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	await process_frame


func _settle(dimensions: Vector2i) -> void:
	root.size = dimensions
	root.content_scale_size = dimensions
	await process_frame
	await process_frame
	await process_frame


func _check_layout(dimensions: Vector2i) -> void:
	var footer := _panel.find_child("CareerFooter", true, false) as Control
	_check(footer.get_global_rect().end.y <= dimensions.y + 1, "footer помещается при %dx%d, вкладка %d" % [dimensions.x, dimensions.y, _panel._tab])
	_check(_panel._scroll.size.y > 120, "область прокрутки остаётся доступной")
	_check(_panel._action.get_global_rect().end.x <= dimensions.x, "главное действие в окне")
	if _panel._tab == 0 and _panel._career != null:
		for id in _panel._team:
			var select := _panel.find_child("CareerCreature_" + String(id), true, false) as Button
			_check(select.get_global_rect().end.y <= _panel._scroll.get_global_rect().end.y + 1, "выбор тройки без прокрутки при %dpx" % dimensions.x)
	for button in _panel.find_children("Career*", "Button", true, false):
		_check(button.focus_mode != Control.FOCUS_NONE, "кнопка %s доступна клавиатурой" % button.name)


func _shot(name: String) -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("career-ui: PNG skipped (headless, no visual acceptance): " + name)
		return
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	_check(image.save_png(_out.path_join(name + ".png")) == OK, "PNG " + name)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("career-ui: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
