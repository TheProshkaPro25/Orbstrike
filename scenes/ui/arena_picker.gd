class_name ArenaPicker
extends Control
const Locations := preload("res://data/arena_locations.gd")
signal preview_requested(index: int)
signal chosen(index: int)
signal canceled
var _buttons: Array[Button] = []
var _description: Label
var _name: Label
var _selected := 0
var _confirm_button: Button
var _cancel_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var title := VisualUtil.label("ВЫБЕРИТЕ АРЕНУ", 28)
	VisualUtil.place(title, .5, 0, 0, 22)
	add_child(title)
	_name = VisualUtil.label("", 19)
	_name.add_theme_color_override("font_color", UiTheme.GOLD)
	VisualUtil.place(_name, .5, 0, 0, 60)
	add_child(_name)
	var panel := PanelContainer.new()
	panel.anchor_left = .04
	panel.anchor_right = .96
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -218
	panel.offset_bottom = -18
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var group := ButtonGroup.new()
	for i in Locations.LOCATIONS.size():
		var b := Button.new()
		b.text = str(Locations.definition(i).name).replace(" ", "\n")
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(select.bind(i))
		row.add_child(b)
		_buttons.append(b)
	_description = VisualUtil.label("", 16)
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_description)
	var note := VisualUtil.label("Расположение ворот и правила одинаковы на всех аренах.", 13)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	vb.add_child(note)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	vb.add_child(actions)
	_confirm_button = Button.new()
	_confirm_button.text = "Выбрать арену"
	_confirm_button.custom_minimum_size = Vector2(180, 42)
	_confirm_button.pressed.connect(confirm)
	actions.add_child(_confirm_button)
	_cancel_button = Button.new()
	_cancel_button.text = "Отмена"
	_cancel_button.custom_minimum_size = Vector2(140, 42)
	_cancel_button.pressed.connect(cancel)
	actions.add_child(_cancel_button)
	var focus_order: Array[Button] = _buttons.duplicate()
	focus_order.append_array([_confirm_button, _cancel_button])
	for i in focus_order.size():
		var button := focus_order[i]
		button.focus_previous = button.get_path_to(focus_order[posmod(i - 1, focus_order.size())])
		button.focus_next = button.get_path_to(focus_order[(i + 1) % focus_order.size()])
	visible = false

func open(index: int) -> void:
	show_selection(index)
	show()
	_buttons[_selected].grab_focus()
	select(index)

func select(index: int) -> void:
	preview_requested.emit(clampi(index, 0, Locations.LOCATIONS.size() - 1))

func confirm() -> void:
	chosen.emit(_selected)

func cancel() -> void:
	canceled.emit()

func show_selection(index: int) -> void:
	_selected = clampi(index, 0, Locations.LOCATIONS.size() - 1)
	var data: Dictionary = Locations.definition(_selected)
	_description.remove_theme_color_override("font_color")
	_description.text = data.description
	_name.text = data.name
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == _selected)

func show_error(message: String) -> void:
	show_selection(_selected)
	_description.add_theme_color_override("font_color", Color.SALMON)
	_description.text = message

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()
		return
	if not event is InputEventKey:
		return
	var focused := _buttons.find(get_viewport().gui_get_focus_owner())
	if focused == -1:
		return
	if event.keycode in [KEY_LEFT, KEY_RIGHT] and event.pressed:
		get_viewport().set_input_as_handled()
		if event.echo:
			return
		var direction := -1 if event.keycode == KEY_LEFT else 1
		select(posmod(_selected + direction, _buttons.size()))
		_buttons[_selected].grab_focus()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		if not event.pressed:
			if focused == _selected:
				confirm()
			else:
				select(focused)
