extends SceneTree
## Узкий MainMenu: настоящие Controls/stretch/keyboard, без города, GLB и перехода в матч.
const WINDOW := preload("res://tools/test_window.gd")
var _checks := 0
var _failures := 0
var _out := "res://build/checks/ui-menu-access"
var _rows: Array = []

class MenuFixture extends MainMenu:
	var saved_campaign := false
	var saved_tournament := false
	var requested: Array[String] = []
	func _ready() -> void:
		_build_ui()
		get_viewport().size_changed.connect(_fit_column)
		_fit_column()
	func _process(_delta: float) -> void: pass
	func _has_saved_run(path: String) -> bool:
		return saved_campaign if path == Campaign.SAVE_PATH else saved_tournament
	func _enter_game(mode: String) -> void: requested.append(mode)
	func _on_online() -> void: requested.append("online")

func _initialize() -> void:
	# check.py уже устанавливает wrapper; прямой узкий запуск использует тот же.
	if not has_meta("sfery_background_draw"): WINDOW.background(self)
	_run.call_deferred()

func _finalize() -> void:
	WINDOW.finish(self)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	DeviceSettings.settings_path = _out.path_join("device-settings.cfg")
	DeviceSettings.reload_settings()
	AudioServer.set_bus_mute(0, true)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var menu := MenuFixture.new()
	root.add_child(menu)
	for style in [DeviceSettings.CLASSIC, DeviceSettings.DEVICE]:
		DeviceSettings.set_style(style)
		for physical in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1024, 768)]:
			root.size = physical
			await _frames()
			menu._show_home()
			await _frames()
			_check(menu._visible_buttons().size() == 5, "главный уровень содержит пять действий")
			_check_layout(menu, physical, "home", style)
			await _key(KEY_ENTER)
			_check(menu._modes_open and root.gui_get_focus_owner() == menu._mode_buttons[0], "Enter открывает режимы и фокусирует карьеру")
			for mask in range(4):
				menu.saved_campaign = bool(mask & 1)
				menu.saved_tournament = bool(mask & 2)
				menu._show_modes()
				await _frames()
				_check(menu._campaign_continue.visible == menu.saved_campaign, "продолжение кампании контекстно")
				_check(menu._tournament_continue.visible == menu.saved_tournament, "продолжение турнира контекстно")
				_check(menu._visible_buttons().size() == 6 + int(menu.saved_campaign) + int(menu.saved_tournament), "нет пустых строк продолжения")
				_check_layout(menu, physical, "modes-%d" % mask, style)
				await _check_keyboard(menu)
			await _key(KEY_ESCAPE)
			_check(not menu._modes_open and root.gui_get_focus_owner() == menu._home_buttons[0], "Esc возвращает на Играть")
			menu._show_modes()
			menu._mode_buttons[-1].grab_focus()
			await _key(KEY_ENTER)
			_check(not menu._modes_open and root.gui_get_focus_owner() == menu._home_buttons[0], "кнопка Назад возвращает фокус")
	# Реальные production-сигналы сохраняют прежние значения намерения перехода.
	menu.saved_campaign = true
	menu.saved_tournament = true
	menu._show_modes()
	var routes := {"Карьера": "career", "Дуэль": "", "Игра через интернет": "online", "Новая кампания": "campaign_new", "Продолжить кампанию": "campaign_continue", "Новый турнир": "new", "Продолжить турнир": "continue"}
	for title in routes:
		menu._focus_button(title)
		await _key(KEY_ENTER)
		_check(not menu.requested.is_empty() and menu.requested.back() == routes[title], "Enter передаёт прежний режим: " + title)
	menu._show_home()
	menu._focus_button("Как играть")
	await _key(KEY_ENTER)
	_check(is_instance_valid(menu._help), "справка открывается клавиатурой")
	await _key(KEY_ESCAPE)
	_check(not is_instance_valid(menu._help) and root.gui_get_focus_owner().text == "Как играть", "Esc закрывает справку и восстанавливает фокус")
	menu._focus_button("Настройки")
	await _key(KEY_ENTER)
	_check(menu._settings.visible, "настройки открываются клавиатурой")
	await _key(KEY_ESCAPE)
	_check(not menu._settings.visible and root.gui_get_focus_owner().text == "Настройки", "Esc закрывает настройки и восстанавливает фокус")
	_check(Engine.max_fps == 60, "штатный wrapper ограничивает60FPS")
	var report := FileAccess.open(_out.path_join("menu-access.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": _checks, "failures": _failures, "display": DisplayServer.get_name(), "visual_acceptance": false, "rows": _rows}, "\t"))
	report.close()
	menu.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await _frames()
	print("menu-access: %d checks, %d failures; headless geometry/keyboard, no visual acceptance" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _check_layout(menu: MainMenu, physical: Vector2i, level: String, style: int) -> void:
	var logical := root.get_visible_rect()
	var physical_scale := physical.y / logical.size.y
	_check(menu._column.scale.is_equal_approx(Vector2.ONE), "колонка не уменьшает текст")
	var previous := Rect2()
	for button in menu._visible_buttons():
		var rect := button.get_global_rect()
		_check(logical.encloses(rect), "кнопка в логическом viewport: " + button.text)
		_check(rect.end.y <= logical.end.y - 54, "кнопка не пересекает нижнюю подсказку")
		_check(previous.size == Vector2.ZERO or not previous.intersects(rect), "кнопки не пересекаются")
		_check(button.focus_mode == Control.FOCUS_ALL, "кнопка принимает keyboard focus")
		var font_size := button.get_theme_font_size("font_size")
		_check(font_size >= 24 and font_size * physical_scale >= 18 - .01, "минимальный читаемый кегль сохранён")
		var text_width := button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_check(text_width + button.get_theme_stylebox("normal").get_minimum_size().x <= rect.size.x + 1, "подпись помещается без сжатия")
		previous = rect
	_rows.append({"physical": [physical.x, physical.y], "logical": [logical.size.x, logical.size.y], "level": level, "style": style, "column_scale": menu._column.scale.x, "font_physical": 24 * physical_scale, "buttons": menu._visible_buttons().size()})

func _check_keyboard(menu: MainMenu) -> void:
	var buttons := menu._visible_buttons()
	for button in buttons:
		_check(root.gui_get_focus_owner() == button, "вниз обходит только текущие действия: " + button.text)
		await _key(KEY_DOWN)
	_check(root.gui_get_focus_owner() == buttons[0], "вниз зациклен в текущем уровне")
	await _key(KEY_UP)
	_check(root.gui_get_focus_owner() == buttons[-1], "вверх возвращает к Назад")
	await _key(KEY_TAB)
	_check(root.gui_get_focus_owner() == buttons[0], "Tab замкнут в текущем уровне")

func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await process_frame

func _frames() -> void:
	for i in 4: await process_frame

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
