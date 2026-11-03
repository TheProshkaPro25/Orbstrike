class_name ArenaPicker
extends Control
const Locations := preload("res://data/arena_locations.gd")
signal chosen(index: int)
signal closed
var _buttons: Array[Button] = []
var _description: Label
var _name: Label
var _selected := 0

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
		b.text = str(Locations.definition(i).name)
		b.custom_minimum_size = Vector2(0, 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 18)
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
	var done := Button.new()
	done.text = "Выбрать и вернуться к команде"
	done.custom_minimum_size = Vector2(340, 42)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(func() -> void: visible = false; closed.emit())
	vb.add_child(done)
	visible = false

func open(index: int) -> void:
	visible = true
	select(index)

func select(index: int) -> void:
	_selected = clampi(index, 0, Locations.LOCATIONS.size() - 1)
	var data: Dictionary = Locations.definition(_selected)
	_description.text = data.description
	_name.text = data.name
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == _selected)
	chosen.emit(_selected)

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_LEFT, KEY_RIGHT]:
		select(posmod(_selected + (-1 if event.keycode == KEY_LEFT else 1), Locations.LOCATIONS.size()))
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		visible = false
		closed.emit()
	else:
		return
	get_viewport().set_input_as_handled()
