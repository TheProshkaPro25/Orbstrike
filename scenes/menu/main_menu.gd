class_name MainMenu
extends Node
## Главное меню после начальной загрузки: живой пейзаж города (MenuCity) и кнопки «Играть», «Мой персонаж», «Как играть», «Настройки»,
## «Выход». «Играть» — затемнение и переход в подготовленную сцену выбора команды; сцена меню
## при этом освобождается целиком. Клавиатура/геймпад: фокус по кнопкам, Esc/«назад» закрывает окна.

const GAME_SCENE := "res://scenes/main.tscn"
const LOGO_SIZE := 68

var city: MenuCity
var ui: Control
var _column: VBoxContainer
var _buttons: Array[Button] = []
var _home_buttons: Array[Button] = []
var _mode_buttons: Array[Button] = []
var _brand: VBoxContainer
var _mode_title: Label
var _home_actions: VBoxContainer
var _mode_actions: VBoxContainer
var _modes_open := false
var _campaign_continue: Button
var _tournament_continue: Button
var _fade: ColorRect
var _clock: Label
var _settings: MenuSettings
var _help: HelpOverlay
var _character_editor: CharacterEditor
var _leaving := false
var _mouse_hover := false


func _ready() -> void:
	if not GameLoading.i().preparing:
		SoundFx.i().play_music(SoundFx.MUSIC_MENU)
	AudioSettings.load_and_apply()
	city = MenuCity.new()
	city.name = "City"
	add_child(city)
	_build_ui()
	get_viewport().size_changed.connect(_fit_column)
	_fit_column()
	_appear()


func _process(_d: float) -> void:
	if _clock != null and city != null:
		_clock.text = DayCycle.clock_text(city.phase)


func _unhandled_input(e: InputEvent) -> void:
	if is_instance_valid(_character_editor):
		return
	if e.is_action_pressed("ui_cancel"):
		if _help != null and is_instance_valid(_help):
			_help.queue_free()
			get_viewport().set_input_as_handled()
		elif _settings != null and _settings.visible:
			_settings.close()
			get_viewport().set_input_as_handled()
		elif _modes_open and not _leaving:
			_show_home()
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_mouse_hover = true
	elif e is InputEventKey or e is InputEventJoypadButton or e is InputEventJoypadMotion:
		_mouse_hover = false
		# Первый ввод без фокуса выбирает начало текущего уровня.
		if get_viewport().gui_get_focus_owner() == null and not _buttons.is_empty() and not _leaving:
			if e.is_action_pressed("ui_down") or e.is_action_pressed("ui_up") or e.is_action_pressed("ui_accept"):
				_visible_buttons()[0].grab_focus()
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- интерфейс

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UiTheme.get_theme()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	# подложка слева: затемнение к краю, чтобы логотип и кнопки читались и днём, и ночью
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ssh := Shader.new()
	ssh.code = """shader_type canvas_item;
void fragment() {
	float l = 1.0 - smoothstep(0.0, 0.5, UV.x);
	float v = smoothstep(0.45, 0.9, length((UV - 0.5) * vec2(1.1, 1.0)));
	COLOR = vec4(0.01, 0.012, 0.03, clamp(l * l * 0.78 + v * 0.45, 0.0, 0.9));
}"""
	var smat := ShaderMaterial.new()
	smat.shader = ssh
	shade.material = smat
	ui.add_child(shade)

	_column = VBoxContainer.new()
	_column.anchor_top = 0.5
	_column.anchor_bottom = 0.5
	_column.anchor_left = 0.0
	_column.offset_left = 80
	_column.offset_top = -310
	_column.offset_bottom = 310
	_column.offset_right = 80 + 520
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_theme_constant_override("separation", 6)
	ui.add_child(_column)
	_brand = VBoxContainer.new()
	_brand.add_theme_constant_override("separation", 6)
	_column.add_child(_brand)

	var logo := VisualUtil.label("Orbstrike", LOGO_SIZE)
	logo.add_theme_color_override("font_color", UiTheme.GOLD)
	logo.add_theme_color_override("font_outline_color", Color(0.10, 0.05, 0.0, 0.95))
	logo.add_theme_constant_override("outline_size", 12)
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	logo.add_theme_constant_override("shadow_offset_x", 0)
	logo.add_theme_constant_override("shadow_offset_y", 5)
	logo.add_theme_constant_override("shadow_outline_size", 18)
	_brand.add_child(logo)

	# шесть стихий — цветные точки под логотипом, подзаголовок — отдельной строкой ниже (в одном ряду с точками
	# он налезал на них при другой ширине шрифта/окна)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var row_pad := MarginContainer.new()
	row_pad.add_theme_constant_override("margin_left", 6)
	row_pad.add_theme_constant_override("margin_top", 2)
	row_pad.add_child(row)
	_brand.add_child(row_pad)
	for a in range(6):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var c: Color = VisualUtil.attr_color(a)
		dot.add_theme_stylebox_override("panel", UiTheme.box(c, c.lightened(0.5), 1, 7, 0))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot)
	var sub := VisualUtil.label("битва шести стихий", 20)
	sub.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	sub.add_theme_constant_override("outline_size", 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var sub_pad := MarginContainer.new()
	sub_pad.add_theme_constant_override("margin_left", 6)
	sub_pad.add_child(sub)
	_brand.add_child(sub_pad)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	_brand.add_child(gap)
	_mode_title = VisualUtil.label("Играть · выбор режима", 32)
	_mode_title.add_theme_color_override("font_color", UiTheme.GOLD)
	_mode_title.hide()
	_column.add_child(_mode_title)

	var panel := PanelContainer.new()
	var pst := UiTheme.box(Color(0.05, 0.05, 0.09, 0.72), UiTheme.GOLD_DIM, 2, 14, 18)
	pst.shadow_color = Color(0, 0, 0, 0.45)
	pst.shadow_size = 10
	panel.add_theme_stylebox_override("panel", pst)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_column.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	_home_actions = VBoxContainer.new()
	_home_actions.add_theme_constant_override("separation", 6)
	vb.add_child(_home_actions)
	_mode_actions = VBoxContainer.new()
	_mode_actions.add_theme_constant_override("separation", 6)
	_mode_actions.hide()
	vb.add_child(_mode_actions)
	for spec in [["Играть", _show_modes], ["Мой персонаж", _on_character], ["Как играть", _on_help], ["Настройки", _on_settings], ["Выход", _on_quit]]:
		_home_buttons.append(_add_action(_home_actions, spec[0], spec[1]))
	for spec in [["Карьера", _on_career], ["Дуэль", _on_play], ["Игра через интернет", _on_online], ["Новая кампания", _on_new_campaign], ["Продолжить кампанию", _on_continue_campaign], ["Новый турнир", _on_new_tournament], ["Продолжить турнир", _on_continue_tournament], ["Назад", _show_home]]:
		var button := _add_action(_mode_actions, spec[0], spec[1])
		_mode_buttons.append(button)
		if button.text == "Продолжить кампанию": _campaign_continue = button
		if button.text == "Продолжить турнир": _tournament_continue = button
	_buttons[0].add_theme_color_override("font_color", UiTheme.GOLD)
	_link_focus(_home_buttons)

	var hint := VisualUtil.label("↑ ↓ — выбор   Enter — подтвердить   Esc — назад", 14)
	hint.add_theme_color_override("font_color", Color(UiTheme.TEXT_DIM, 0.8))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 24
	hint.offset_top = -38
	hint.offset_bottom = -14
	ui.add_child(hint)

	_clock = VisualUtil.label("", 22)
	_clock.add_theme_color_override("font_color", Color(UiTheme.GOLD, 0.85))
	_clock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_clock.offset_left = -110
	_clock.offset_right = -24
	_clock.offset_top = -44
	_clock.offset_bottom = -14
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(_clock)

	# версия игры (application/config/version в project.godot — её же берёт экспорт)
	var ver := VisualUtil.label("версия " + str(ProjectSettings.get_setting("application/config/version", "")), 14)
	ver.add_theme_color_override("font_color", Color(UiTheme.TEXT_DIM, 0.85))
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))  # читается и на дневном небе
	ver.add_theme_constant_override("outline_size", 5)
	ver.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	ver.offset_left = -200
	ver.offset_right = -24
	ver.offset_top = 14
	ver.offset_bottom = 38
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(ver)

	_settings = MenuSettings.new()
	_settings.city = city
	_settings.visible = false
	_settings.closed.connect(func() -> void: _focus_button("Настройки"))
	ui.add_child(_settings)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_fade)
	UiTheme.apply_device_frame(ui, "ГЛАВНОЕ МЕНЮ")


func _add_action(parent: VBoxContainer, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(380, 48)
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(action)
	button.mouse_entered.connect(button.grab_focus)
	button.focus_entered.connect(_on_focus.bind(button))
	parent.add_child(button)
	_buttons.append(button)
	return button


func _visible_buttons() -> Array[Button]:
	var result: Array[Button] = []
	for button in (_mode_buttons if _modes_open else _home_buttons):
		if button.visible and not button.disabled: result.append(button)
	return result


func _link_focus(buttons: Array[Button]) -> void:
	for i in buttons.size():
		var button := buttons[i]
		button.focus_neighbor_top = buttons[(i - 1 + buttons.size()) % buttons.size()].get_path()
		button.focus_neighbor_bottom = buttons[(i + 1) % buttons.size()].get_path()
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom


func _has_saved_run(path: String) -> bool:
	# Существующее, в том числе повреждённое, сохранение открывает прежний путь
	# продолжения: его проверка и объяснение ошибки остаются в Main.
	return FileAccess.file_exists(path)


func _show_modes() -> void:
	if _leaving: return
	_modes_open = true
	_home_actions.hide()
	_brand.hide()
	_mode_title.show()
	_campaign_continue.visible = _has_saved_run(Campaign.SAVE_PATH)
	_tournament_continue.visible = _has_saved_run(Tournament.SAVE_PATH)
	_mode_actions.show()
	_link_focus(_visible_buttons())
	_fit_column()
	_mode_buttons[0].grab_focus()


func _show_home() -> void:
	if _leaving: return
	_modes_open = false
	_mode_actions.hide()
	_mode_title.hide()
	_brand.show()
	_home_actions.show()
	_fit_column()
	_home_buttons[0].grab_focus()


## Появление: из чёрного, логотип и кнопки по очереди.
func _appear() -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.4).set_ease(Tween.EASE_OUT)
	_column.modulate.a = 0.0
	var x0 := _column.offset_left
	_column.offset_left = x0 - 40
	_column.offset_right -= 40
	var tc := create_tween().set_parallel()
	tc.tween_property(_column, "modulate:a", 1.0, 0.9).set_delay(0.35)
	tc.tween_property(_column, "offset_left", x0, 1.0).set_delay(0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tc.tween_property(_column, "offset_right", x0 + 520, 1.0).set_delay(0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in range(_home_buttons.size()):
		var b := _home_buttons[i]
		b.modulate.a = 0.0
		tc.tween_property(b, "modulate:a", 1.0, 0.45).set_delay(0.7 + 0.1 * i)
	tc.chain().tween_callback(func() -> void:
		if not _leaving and get_viewport().gui_get_focus_owner() == null:
			_mouse_hover = true   # первый фокус — без звука
			_visible_buttons()[0].grab_focus())


func _on_focus(b: Button) -> void:
	# звук наведения с клавиатуры/геймпада (мышью его играет SoundFx по mouse_entered)
	if not _mouse_hover and b.modulate.a > 0.9:
		SoundFx.i().play("ui_hover", -10.0, 0.06)


# ---------------------------------------------------------------- кнопки

func _focus_button(title: String) -> void:
	for button in _buttons:
		if button.text == title:
			button.grab_focus()
			return


func _on_career() -> void:
	_enter_game("career")


func _on_play() -> void:
	_enter_game("")


func _on_new_tournament() -> void:
	_enter_game("new")


func _on_continue_tournament() -> void:
	_enter_game("continue")


func _enter_game(mode: String) -> void:
	if _leaving:
		return
	TournamentSession.entry_mode = mode
	_leaving = true
	for b in _buttons:
		b.disabled = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.45)
	tw.tween_callback(func() -> void:
		if GameLoading.i().ready_to_play:
			GameLoading.i().show_game()
			get_tree().current_scene.enter_requested_mode()
		else:
			get_tree().change_scene_to_file(GAME_SCENE))


func _on_help() -> void:
	_help = HelpOverlay.open_on(ui)
	for n in _help.find_children("*", "Button", true, false):
		(n as Button).grab_focus()
		break
	_help.tree_exited.connect(func() -> void:
		if is_inside_tree() and not _leaving:
			_focus_button("Как играть"))


func _on_settings() -> void:
	_settings.open()


func _on_quit() -> void:
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	tw.tween_callback(get_tree().quit)


func _on_character() -> void:
	if is_instance_valid(_character_editor): return
	_character_editor = CharacterEditor.new()
	ui.add_child(_character_editor)
	_column.hide()
	_character_editor.closed.connect(func() -> void:
		_column.show()
		_focus_button("Мой персонаж"))


func _on_new_campaign() -> void:
	_enter_game("campaign_new")

func _on_continue_campaign() -> void:
	_enter_game("campaign_continue")


func _fit_column() -> void:
	if not is_instance_valid(_column): return
	var viewport := get_viewport().get_visible_rect().size
	# Два коротких уровня помещаются в штатный logical1280×720 без уменьшения
	# текста. Размер окна меняет stretch, а не кегль/масштаб всей колонки.
	var natural_height := _column.get_combined_minimum_size().y
	_column.scale = Vector2.ONE
	_column.offset_top = -natural_height * .5 - 12.0
	_column.offset_bottom = _column.offset_top + natural_height
	_column.offset_left = clampf(viewport.x * .0625, 32.0, 80.0)
	_column.offset_right = _column.offset_left + 520.0


func _on_online() -> void:
	if _leaving: return
	_leaving = true
	for button in _buttons: button.disabled = true
	if GameLoading.i().ready_to_play: GameLoading.i().show_online()
	else: get_tree().change_scene_to_file("res://scenes/online/online_game.tscn")
