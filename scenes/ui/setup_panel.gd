class_name SetupPanel
extends Control
## Левая рука ворот. Выбранная карта кладётся только щелчком по подсвеченному полю арены.

signal placed(card_id: StringName, slot: int)
signal placed_throw(card_id: StringName, slot: int)
signal skipped
signal slot_hovered(slot: int)

var _panel: VBoxContainer
var _title: Label
var _cards_box: HBoxContainer
var _card_buttons: Dictionary = {}
var _selected: StringName = &""
var _legal: Array = []
var _built := false
var _skip_btn: Button
var _throw_btn: Button
var _back_btn: Button
var _dock: Control
var _hand: Array = []
var _size := Vector2(110, 154)
var _dock_visible := true
var _page := 0
var _pager: HBoxContainer
var _page_label: Label
var _previous: Button
var _next: Button

func _ready() -> void:
	_build()

func _build() -> void:
	if _built: return
	_built = true
	VisualUtil.full_rect_ignore(self)
	theme = UiTheme.get_theme()
	_dock = Control.new()
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dock)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 8)
	_dock.add_child(_cards_box)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 5)
	add_child(_panel)
	_title = VisualUtil.label("ВОРОТА · выберите карту слева", 14)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = 340
	_panel.add_child(_title)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_panel.add_child(actions)
	_throw_btn = Button.new()
	_throw_btn.text = "Ворота + бросок"
	_throw_btn.toggle_mode = true
	_throw_btn.tooltip_text = "После щелчка по полю выберите существо. Назад вернёт к карте без расхода хода."
	actions.add_child(_throw_btn)
	_back_btn = Button.new()
	_back_btn.text = "Отмена"
	_back_btn.tooltip_text = "Снять выбор карты (Esc / правая кнопка мыши)"
	_back_btn.pressed.connect(_cancel_selection)
	actions.add_child(_back_btn)
	_skip_btn = Button.new()
	_skip_btn.text = "Не класть"
	_skip_btn.pressed.connect(func() -> void: skipped.emit())
	actions.add_child(_skip_btn)
	_pager = HBoxContainer.new()
	add_child(_pager)
	_previous = Button.new()
	_previous.text = "‹"
	_previous.pressed.connect(_change_page.bind(-1))
	_pager.add_child(_previous)
	_page_label = VisualUtil.label("",13)
	_pager.add_child(_page_label)
	_next = Button.new()
	_next.text = "›"
	_next.pressed.connect(_change_page.bind(1))
	_pager.add_child(_next)
	_panel.visible = false
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	if not _built: return
	var vp := get_viewport_rect().size
	var w := clampf((vp.x * .46 - 40.0) / 3.0, 96.0, 142.0)
	_size = Vector2(w, roundf(w * 1.4))
	_dock.position = Vector2(16, vp.y - (_size.y + (58 if _hand.size() > 3 else 26) if _panel.visible else 72))
	_panel.position = Vector2(16, vp.y - _size.y - (130 if _hand.size() > 3 else 98))
	_title.custom_minimum_size.x = vp.x * .46 - 20
	_panel.reset_size()
	for cv in _card_buttons.values():
		cv.custom_minimum_size = _size
		cv.size = _size
	_dock.visible = _dock_visible and not _hand.is_empty()
	_pager.position = Vector2(16,vp.y-44)
	_pager.visible = _dock_visible and _hand.size() > 3

func set_hand(ids: Array) -> void:
	_build()
	if ids == _hand: return
	_hand = ids.duplicate()
	_rebuild()

func _rebuild() -> void:
	VisualUtil.clear_children(_cards_box)
	_card_buttons.clear()
	var pages := maxi(1,ceili(float(_hand.size())/3.0))
	_page = clampi(_page,0,pages-1)
	_previous.disabled = _page == 0
	_next.disabled = _page == pages-1
	_page_label.text = "Ворота · %d/%d" % [_page+1,pages]
	for id in _hand.slice(_page*3,(_page+1)*3):
		var cid := StringName(str(id))
		var def := CardDB.card(cid)
		if def == null: continue
		var b := CardView.new().for_card(def, _size)
		b.toggle_mode = true
		b.button_pressed = cid == _selected
		b.pressed.connect(_on_card_pressed.bind(cid))
		b.set_meta("silent_select", not _panel.visible)
		_cards_box.add_child(b)
		_card_buttons[cid] = b
	_layout()

func set_dock_visible(on: bool) -> void:
	_build()
	_dock_visible = on
	_layout()

## cards — карты из руки контроллера; legal_slots — исключительно его допустимые места.
func begin(cards: Array, legal_slots: Array, can_skip: bool = false, can_throw: bool = false) -> void:
	_build()
	_selected = &""
	_page = 0
	_legal = legal_slots.duplicate()
	_hand.clear()
	for c in cards: _hand.append(StringName(str(c.id)))
	_panel.visible = true
	_skip_btn.visible = can_skip
	_throw_btn.visible = can_throw
	_throw_btn.button_pressed = false
	_rebuild()
	_refresh_selection()

func hide_panel() -> void:
	_build()
	_panel.visible = false
	_selected = &""
	_legal.clear()
	_rebuild()

func _on_card_pressed(cid: StringName) -> void:
	if not _panel.visible: return
	_selected = cid
	_refresh_selection()

func _refresh_selection() -> void:
	for cid in _card_buttons:
		_card_buttons[cid].button_pressed = cid == _selected
	_back_btn.disabled = _selected == &""
	_title.text = "ВОРОТА · выберите карту слева" if _selected == &"" else "ВОРОТА · щёлкните по подсвеченному полю арены"

func _cancel_selection() -> void:
	_selected = &""
	_refresh_selection()

func pick_slot(slot: int) -> void:
	if not _panel.visible or not _legal.has(slot): return
	if _selected == &"" and _hand.size() == 1:
		_on_card_pressed(_card_buttons.keys()[0])
	if _selected == &"":
		_title.text = "Сначала выберите карту ворот слева"
		SoundFx.i().play("ui_denied", -4.0)
		return
	var cid := _selected
	_selected = &""
	if _throw_btn.visible and _throw_btn.button_pressed:
		placed_throw.emit(cid, slot)
	else:
		placed.emit(cid, slot)

func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible or _selected == &"": return
	if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		_cancel_selection()
		get_viewport().set_input_as_handled()

func _change_page(delta: int) -> void:
	_selected = &""
	_page += delta
	_rebuild()
	_refresh_selection()
