class_name MenuSettings
extends Control
## Настройки применяются сразу; двумерный интерфейс сохраняет чёткость при уменьшении 3D.
signal closed
var city: MenuCity
var _built := false
var _first: Control
var _last_preview := 0
var _panel: PanelContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _grids: Array[GridContainer] = []
var _fields: Array[Control] = []
var _controls: Dictionary = {}
var _quality_note: Label


func _ready() -> void:
	_build()


func open() -> void:
	_build()
	_sync_controls()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	_center_panel.call_deferred()
	_first.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	if _built: return
	_built = true
	z_index = 30
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.02, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed: close())
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.name = "SettingsPanel"
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_panel.add_child(vb)
	var title := VisualUtil.label("Настройки", 28)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.name = "SettingsScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	vb.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)
	var grid := _section("Графика и производительность")
	var gfx := OptionButton.new()
	gfx.name = "GraphicsPreset"
	for text in GraphicsSettings.NAMES: gfx.add_item(text)
	gfx.item_selected.connect(GraphicsSettings.set_level)
	_row(grid, "Готовый профиль", gfx)
	_controls["preset"] = gfx
	_first = gfx
	_quality_note = VisualUtil.label("", 14)
	_quality_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quality_note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_body.add_child(_quality_note)
	grid = _section("Дополнительная графика")
	_option_row(grid, "Тени солнца и луны", "shadow_quality", "ShadowQuality", "Качество динамических теней. Выключение снижает число проходов отрисовки; свет и витражные проекции сохраняются.")
	var scale_option := OptionButton.new()
	scale_option.name = "RenderScale"
	for scale_value in GraphicsSettings.RENDER_SCALES: scale_option.add_item(str(roundi(scale_value * 100.0)) + "%")
	scale_option.tooltip_text = "Разрешение трёхмерной сцены и предпросмотра. 75% уменьшает число пикселей примерно на 44%; текст и кнопки остаются чёткими."
	scale_option.item_selected.connect(func(i: int) -> void: GraphicsSettings.set_option("render_scale", GraphicsSettings.RENDER_SCALES[i]))
	_row(grid, "Разрешение 3D", scale_option)
	_controls["render_scale"] = scale_option
	_option_row(grid, "Сглаживание", "antialiasing", "Antialiasing", "FXAA смягчает края с небольшой нагрузкой. MSAA лучше сохраняет мелкие детали, но требует больше памяти и мощности GPU.")
	_option_row(grid, "Экранные эффекты", "screen_effects", "ScreenEffects", "Умеренные: свечение и затенение углублений (SSAO). Полные добавляют непрямой свет и отражения (SSIL/SSR). В пейзаже меню — свечение и размытие дали.")
	_option_row(grid, "Детализация декора", "scene_detail", "SceneDetail", "Число фоновых частиц, дополнительные огни и движение декора. Низкая детализация уменьшает работу CPU и GPU.")
	var vsync := CheckButton.new()
	vsync.name = "VSync"
	vsync.text = "Включена"
	vsync.tooltip_text = "Согласует кадры с частотой монитора и убирает разрывы изображения. Ограничитель FPS действует дополнительно."
	vsync.toggled.connect(func(value: bool) -> void: GraphicsSettings.set_option("vsync", value))
	_row(grid, "Вертикальная синхр.", vsync)
	_controls["vsync"] = vsync
	var fps := OptionButton.new()
	fps.name = "FrameLimit"
	for value in GraphicsSettings.FPS_OPTIONS: fps.add_item(GraphicsSettings.fps_name(value))
	fps.tooltip_text = "30 или 45 FPS заметно снижают нагрузку и нагрев. Без лимита игра использует все доступные ресурсы."
	fps.item_selected.connect(func(i: int) -> void: GraphicsSettings.set_fps(GraphicsSettings.FPS_OPTIONS[i]))
	_row(grid, "Лимит кадров", fps)
	_controls["fps"] = fps
	grid = _section("Интерфейс и звук")
	var reduced_motion := CheckButton.new()
	reduced_motion.text = "Уменьшить"
	reduced_motion.name = "ReduceInterfaceMotion"
	reduced_motion.tooltip_text = "Электронный HUD появляется сразу, без сдвигов и анимации счётчика силы."
	reduced_motion.button_pressed = DeviceSettings.reduce_motion()
	reduced_motion.toggled.connect(func(value: bool) -> void:
		if DeviceSettings.set_reduce_motion(value) != OK: reduced_motion.set_pressed_no_signal(DeviceSettings.reduce_motion()))
	_row(grid, "Анимация интерфейса", reduced_motion)
	_row(grid, "Звуки", _slider(AudioSettings.sfx, "SFX"))
	_row(grid, "Музыка", _slider(AudioSettings.music, "Music"))
	_row(grid, "Звуки интерфейса", _slider(AudioSettings.interface_volume, "Interface"))
	var muted := CheckButton.new()
	muted.text = "Включить"
	muted.button_pressed = AudioSettings.interface_muted
	muted.toggled.connect(AudioSettings.set_interface_muted)
	_row(grid, "Тихий интерфейс", muted)
	var done := Button.new()
	done.name = "SettingsDone"
	done.text = "Готово"
	done.custom_minimum_size = Vector2(160, 44)
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.pressed.connect(close)
	vb.add_child(done)
	_fields.append(done)
	for i in _fields.size():
		var field := _fields[i]
		field.focus_next = field.get_path_to(_fields[(i + 1) % _fields.size()])
		field.focus_previous = field.get_path_to(_fields[posmod(i - 1, _fields.size())])
	GraphicsSettings.watch(self, "_sync_controls")
	get_viewport().size_changed.connect(_center_panel)
	_sync_controls()
	_center_panel.call_deferred()


func _sync_controls() -> void:
	if not _built: return
	_controls.preset.select(GraphicsSettings.current())
	for key in GraphicsSettings.OPTION_NAMES: _controls[key].select(int(GraphicsSettings.option(key)))
	_controls.render_scale.select(GraphicsSettings.RENDER_SCALES.find(GraphicsSettings.option("render_scale")))
	_controls.vsync.set_pressed_no_signal(bool(GraphicsSettings.option("vsync")))
	_controls.fps.select(maxi(GraphicsSettings.FPS_OPTIONS.find(GraphicsSettings.fps_limit()), 0))
	_quality_note.text = "Свои настройки на основе профиля «%s». Выбор профиля сбросит ручные изменения графики." % GraphicsSettings.level_name() if GraphicsSettings.is_custom() else "Изменения действуют сразу и сохраняются. Для слабой видеокарты начните с профиля «Низкие»."


func _section(title: String) -> GridContainer:
	var label := VisualUtil.label(title, 18)
	label.add_theme_color_override("font_color", UiTheme.GOLD)
	_body.add_child(label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 5)
	_body.add_child(grid)
	_grids.append(grid)
	return grid


func _option_row(grid: GridContainer, title: String, key: String, control_name: String, hint: String) -> void:
	var choice := OptionButton.new()
	choice.name = control_name
	choice.tooltip_text = hint
	for text in GraphicsSettings.OPTION_NAMES[key]: choice.add_item(text)
	choice.item_selected.connect(func(i: int) -> void: GraphicsSettings.set_option(key, i))
	_row(grid, title, choice)
	_controls[key] = choice


func _center_panel() -> void:
	if not is_instance_valid(_panel): return
	var available := get_viewport_rect().size
	for grid in _grids: grid.columns = 1 if available.x < 640.0 else 2
	_panel.size = Vector2(minf(700.0, available.x - 28.0), minf(720.0, available.y - 28.0))
	_panel.position = (available - _panel.size) * 0.5


func _row(grid: GridContainer, title: String, ctrl: Control) -> void:
	var label := VisualUtil.label(title, 18)
	grid.add_child(label)
	ctrl.custom_minimum_size = Vector2(260, 40)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctrl)
	_fields.append(ctrl)


func _slider(value: float, bus_name: String) -> HSlider:
	var slider := HSlider.new()
	slider.theme_type_variation = &"VolumeSlider"
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = roundf(maxf(value, 0.0) * 100.0) if value >= 0.0 else 100.0
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(x: float) -> void:
		AudioSettings.set_volume(bus_name, x / 100.0)
		if bus_name in ["SFX", "Interface"] and Time.get_ticks_msec() - _last_preview > 250:
			_last_preview = Time.get_ticks_msec()
			SoundFx.i().play("ui_click" if bus_name == "Interface" else "card_select", -4.0))
	return slider
