class_name ArenaSlotPicker
extends Control
## Обратимый выбор места из списка, уже разрешённого контроллером матча.

signal chosen(slot: int)
signal cancelled
signal slot_hovered(slot: int)

var _panel: PanelContainer
var _title: Label
var _description: Label
var _description_scroll: ScrollContainer
var _grid: GridContainer
var _buttons: Array[Button] = []
var _cancel: Button
var _return_focus: Control
var _built := false


func _init() -> void:
	hide()


func _ready() -> void:
	_build()


func _build() -> void:
	if _built: return
	_built = true
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.022, 0.04, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.box(Color(0.045, 0.065, 0.10), UiTheme.GOLD_DIM, 2, 12, 20))
	center.add_child(_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	_panel.add_child(body)
	_title = VisualUtil.label("Выберите место на поле", 22)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_title)
	var far_row := VisualUtil.label("Дальний ряд арены", 14)
	far_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(far_row)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	body.add_child(_grid)
	for slot in range(6):
		var button := Button.new()
		button.focus_mode = Control.FOCUS_ALL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 16)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_choose.bind(slot))
		button.focus_entered.connect(_hover.bind(slot))
		button.mouse_entered.connect(_hover.bind(slot))
		button.mouse_exited.connect(_hover_focused)
		_grid.add_child(button)
		_buttons.append(button)
	var near_row := VisualUtil.label("Ближний ряд · ваша сторона", 14)
	near_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(near_row)
	_description_scroll = ScrollContainer.new()
	_description_scroll.custom_minimum_size.y = 104.0
	_description_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_description_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(_description_scroll)
	_description = VisualUtil.label("", 14)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description_scroll.add_child(_description)
	var help := VisualUtil.label("Стрелки — место · Tab — следующий выбор · PgUp/PgDn — описание\nEnter — подтвердить · Esc / правая кнопка — назад", 14)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(help)
	_cancel = Button.new()
	_cancel.text = "Назад · действие не потрачено"
	_cancel.custom_minimum_size.y = 42
	_cancel.pressed.connect(_on_cancel)
	_cancel.focus_entered.connect(_hover.bind(-1))
	body.add_child(_cancel)
	get_viewport().size_changed.connect(_layout)
	_layout()


func show_slots(slots: Array, view: MatchState, title: String, description_for_slot: Callable = Callable()) -> void:
	_build()
	if not visible: _return_focus = get_viewport().gui_get_focus_owner()
	_title.text = title
	for slot in range(6):
		var button := _buttons[slot]
		button.disabled = not slots.has(slot)
		button.text = _slot_label(slot, view)
		button.tooltip_text = button.text
		if description_for_slot.is_valid():
			button.tooltip_text = str(description_for_slot.call(slot))
		if button.disabled: button.text += "\nНедоступно"
	show()
	_layout()
	var choices := _focusables()
	for i in choices.size():
		choices[i].focus_next = choices[i].get_path_to(choices[(i + 1) % choices.size()])
		choices[i].focus_previous = choices[i].get_path_to(choices[posmod(i - 1, choices.size())])
	choices[0].grab_focus()


func _slot_label(slot: int, view: MatchState) -> String:
	var text := "№ %d" % (slot + 1)
	if view == null or slot >= view.slots.size(): return text + "\nПустое место"
	var state := view.slots[slot]
	text += "\n" + ("Ваши ворота" if state.card_owner == 0 else "Ворота соперника") if state.has_card else "\nПустое место"
	if state.occupant_uid >= 0:
		var creature := view.creature(state.occupant_uid)
		if creature != null:
			var definition := CardDB.creature(creature.def_id)
			if definition != null: text += "\n" + definition.display_name
	return text


func _layout() -> void:
	if not _built: return
	var width := minf(720.0, maxf(240.0, get_viewport_rect().size.x - 48.0))
	_panel.custom_minimum_size.x = width
	_title.custom_minimum_size.x = width - 40.0
	for button in _buttons:
		button.custom_minimum_size = Vector2((width - 60.0) / 3.0, 112.0)
	_panel.reset_size()


func _focusables() -> Array[Control]:
	var result: Array[Control] = []
	for button in _buttons:
		if not button.disabled: result.append(button)
	result.append(_cancel)
	return result


func _hover(slot: int) -> void:
	if not is_visible_in_tree(): return
	if slot >= 0 and _buttons[slot].disabled: return
	_description.text = _buttons[slot].tooltip_text if slot >= 0 else "Назад — вернуться к выбору без расхода действия."
	_description_scroll.scroll_vertical = 0
	slot_hovered.emit(slot)


func _hover_focused() -> void:
	var index := _buttons.find(get_viewport().gui_get_focus_owner())
	_hover(index)


func _choose(slot: int) -> void:
	if not is_visible_in_tree() or _buttons[slot].disabled: return
	dismiss()
	chosen.emit(slot)


func _on_cancel() -> void:
	if not is_visible_in_tree(): return
	dismiss()
	cancelled.emit()


## Завершение фазы закрывает выбор без сигнала пользовательской отмены.
func dismiss() -> void:
	var was_visible := visible
	hide()
	if was_visible: slot_hovered.emit(-1)
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree() and _return_focus.focus_mode != Control.FOCUS_NONE:
		if not (_return_focus is BaseButton and _return_focus.disabled): _return_focus.grab_focus()
	_return_focus = null


func _move_focus(key: Key, backwards: bool) -> void:
	var choices := _focusables()
	var owner := get_viewport().gui_get_focus_owner()
	var index := choices.find(owner)
	if key == KEY_TAB:
		choices[posmod(index + (-1 if backwards else 1), choices.size())].grab_focus()
		return
	var slot := _buttons.find(owner)
	if slot < 0:
		choices[0 if key == KEY_RIGHT or key == KEY_DOWN else choices.size() - 2 if choices.size() > 1 else 0].grab_focus()
		return
	var column := slot % 3
	var row: int = slot / 3
	for step in range(1, 4 if key == KEY_LEFT or key == KEY_RIGHT else 3):
		var next_slot := row * 3 + posmod(column + step * (-1 if key == KEY_LEFT else 1), 3) if key == KEY_LEFT or key == KEY_RIGHT else posmod(row + step * (-1 if key == KEY_UP else 1), 2) * 3 + column
		if next_slot != slot and not _buttons[next_slot].disabled:
			_buttons[next_slot].grab_focus()
			return
	# В разреженном наборе целей соседний ряд/столбец может быть пуст: цикл
	# по разрешённым местам сохраняет достижимость всех кнопок стрелками.
	choices[posmod(index + (-1 if key == KEY_LEFT or key == KEY_UP else 1), choices.size())].grab_focus()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	for sibling in get_parent().get_children():
		if sibling != self and ((sibling is HelpOverlay and sibling.is_visible_in_tree()) or (sibling is Window and sibling.visible)):
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		_on_cancel()
	elif event is InputEventKey:
		var key: Key = event.keycode
		if key in [KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END]:
			get_viewport().set_input_as_handled()
			if event.pressed:
				if key == KEY_HOME: _description_scroll.scroll_vertical = 0
				elif key == KEY_END: _description_scroll.scroll_vertical = int(_description.get_combined_minimum_size().y)
				else: _description_scroll.scroll_vertical += -92 if key == KEY_PAGEUP else 92
			return
		if key not in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_TAB, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]: return
		get_viewport().set_input_as_handled()
		if not event.pressed or event.echo: return
		if key == KEY_ESCAPE:
			_on_cancel()
		elif key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			var slot := _buttons.find(get_viewport().gui_get_focus_owner())
			if slot >= 0: _choose(slot)
			else: _on_cancel()
		else:
			_move_focus(key, event.shift_pressed)
