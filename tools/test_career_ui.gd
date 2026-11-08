extends SceneTree
## Узкий 2D-стенд: отдельная карьера без пользовательского сохранения и без GLB.
const PANEL := preload("res://scenes/ui/career_panel.gd")
const CAREER := preload("res://core/career.gd")
const DEVICE := preload("res://scenes/ui/device_settings.gd")
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
	DEVICE.settings_path = _out.path_join("device-settings.cfg")
	DEVICE.reload_settings()
	DEVICE.set_style(DEVICE.CLASSIC)
	_panel = PANEL.new()
	root.add_child(_panel)
	_panel.create_requested.connect(func(element: int, difficulty: int) -> void: _create_args = [element, difficulty])
	_panel.registration_requested.connect(func(creatures: Array[StringName], gates: Array[StringName], abilities: Array[StringName], levels: Dictionary) -> void: _registration = [creatures, gates, abilities, levels])
	_panel.display(null)
	await _settle(Vector2i(960, 540))
	_check(_panel._element_choice.item_count == 6, "первый шаг: шесть стихий")
	_panel._element_choice.select(4)
	_panel._difficulty_choice.select(2)
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
	for id in CardDB.arena_ids() + CardDB.ability_ids():
		if not career.state.owned_cards.has(String(id)) and career.price(id) > 0 and career.price(id) <= before:
			item = id
			break
	_check(item != &"", "есть точная покупка по средствам")
	if item != &"":
		var price: int = career.price(item)
		_panel._purchase(item)
		_check(career.state.credits == before - price and career.state.owned_cards.has(String(item)), "кнопка покупки выдаёт указанный предмет за указанную цену")
		_panel._purchase(item)
		_check(career.state.credits == before - price, "повторная покупка не списывает кредиты")
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
	_check(DEVICE.set_style(DEVICE.DEVICE) == OK, "выбран прибор в изолированных настройках")
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
	_finish()


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
