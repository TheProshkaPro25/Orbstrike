class_name MenuSettings
extends Control
## Окно «Настройки» главного меню: уровень графики и лимит кадров (GraphicsSettings, применяются сразу и к пейзажу),
## громкость эффектов и музыки (AudioSettings). Всё сохраняется в user://settings.cfg.

signal closed

var city: MenuCity
var _built := false
var _first: Control
var _last_preview := 0
var _panel: PanelContainer


func _ready() -> void:
	_build()


func open() -> void:
	_build()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	_center_panel.call_deferred()
	_first.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.02, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(dim)

	var panel := PanelContainer.new()
	_panel = panel
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(540, 0)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	panel.add_child(vb)
	var t := VisualUtil.label("Настройки", 28)
	t.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(t)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)

	var gfx := OptionButton.new()
	for n in GraphicsSettings.NAMES:
		gfx.add_item(n)
	gfx.select(GraphicsSettings.current())
	gfx.item_selected.connect(func(i: int) -> void:
		GraphicsSettings.set_level(i)
		if city != null:
			city.apply_quality(i))
	_row(grid, "Графика", gfx)
	_first = gfx

	var fps := OptionButton.new()
	for v in GraphicsSettings.FPS_OPTIONS:
		fps.add_item(GraphicsSettings.fps_name(v))
	fps.select(maxi(GraphicsSettings.FPS_OPTIONS.find(GraphicsSettings.fps_limit()), 0))
	fps.item_selected.connect(func(i: int) -> void: GraphicsSettings.set_fps(GraphicsSettings.FPS_OPTIONS[i]))
	_row(grid, "Лимит кадров", fps)

	var reduced_motion := CheckButton.new()
	reduced_motion.text = "Уменьшить"
	reduced_motion.name = "ReduceInterfaceMotion"
	reduced_motion.tooltip_text = "Электронный HUD появляется сразу, без сдвигов и анимации счётчика силы."
	reduced_motion.button_pressed = DeviceSettings.reduce_motion()
	reduced_motion.toggled.connect(func(value: bool) -> void:
		if DeviceSettings.set_reduce_motion(value) != OK:
			reduced_motion.set_pressed_no_signal(DeviceSettings.reduce_motion()))
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
	done.text = "Готово"
	done.custom_minimum_size = Vector2(160, 46)
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.pressed.connect(close)
	vb.add_child(done)
	get_viewport().size_changed.connect(_center_panel)
	_center_panel.call_deferred()


func _center_panel() -> void:
	if not is_instance_valid(_panel): return
	var available := get_viewport_rect().size
	var natural := _panel.get_combined_minimum_size()
	var factor := minf(1.0, minf((available.x-28.0)/natural.x, (available.y-28.0)/natural.y))
	_panel.scale = Vector2.ONE * maxf(0.1, factor)
	_panel.position = (available-natural*_panel.scale) * 0.5


func _row(grid: GridContainer, title: String, ctrl: Control) -> void:
	var l := VisualUtil.label(title, 19)
	grid.add_child(l)
	ctrl.custom_minimum_size = Vector2(280, 40)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctrl)


func _slider(v: float, bus_name: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = roundf(maxf(v, 0.0) * 100.0) if v >= 0.0 else 100.0
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(x: float) -> void:
		AudioSettings.set_volume(bus_name, x / 100.0)
		# короткий щелчок для пробы громкости эффектов (не чаще 4 раз в секунду)
		if bus_name in ["SFX", "Interface"] and Time.get_ticks_msec() - _last_preview > 250:
			_last_preview = Time.get_ticks_msec()
			SoundFx.i().play("ui_click" if bus_name == "Interface" else "card_select", -4.0))
	return s
