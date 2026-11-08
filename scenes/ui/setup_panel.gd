class_name SetupPanel
extends Control
## Левая рука ворот. Место выбирается на арене мышью или отдельным клавиатурным выбором.

signal placed(card_id: StringName, slot: int)
signal placed_throw(card_id: StringName, slot: int)
signal skipped
signal slot_hovered(slot: int)
signal slot_pick_requested

var _panel: VBoxContainer
var _title: Label
var _cards_box: HBoxContainer
var _card_buttons: Dictionary = {}
var _selected: StringName = &""
var _legal: Array = []
var _built := false
var _skip_btn: Button
var _slot_btn: Button
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
	UiTheme.apply_device_frame(self, "ВОРОТА", false)

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
	_slot_btn = Button.new()
	_slot_btn.text = "Место на поле…"
	_slot_btn.disabled = true
	_slot_btn.focus_mode = Control.FOCUS_NONE
	_slot_btn.tooltip_text = "Выберите карту и перейдите Tab к этой кнопке. Enter откроет карту поля; стрелки выбирают место, Esc возвращает без расхода хода."
	_slot_btn.pressed.connect(func() -> void:
		if _panel.visible and _selected != &"": slot_pick_requested.emit())
	_panel.add_child(_slot_btn)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_panel.add_child(actions)
	_throw_btn = Button.new()
	_throw_btn.text = "Ворота + бросок"
	_throw_btn.toggle_mode = true
	_throw_btn.tooltip_text = "После выбора места на поле выберите существо. Назад / Esc вернёт к карте без расхода хода."
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
	_pager.tooltip_text = "Страницы ворот: кнопки, ← / → при фокусе в этой руке или колёсико над картой. Tab — сменить руку."
	add_child(_pager)
	_previous = Button.new()
	_previous.text = "‹"
	_previous.pressed.connect(_change_page.bind(-1))
	_previous.gui_input.connect(_page_input)
	_pager.add_child(_previous)
	_page_label = VisualUtil.label("",13)
	_pager.add_child(_page_label)
	_next = Button.new()
	_next.text = "›"
	_next.pressed.connect(_change_page.bind(1))
	_next.gui_input.connect(_page_input)
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
	_panel.position = Vector2(16, vp.y - _size.y - (130 if _hand.size() > 3 else 98) - (_slot_btn.get_combined_minimum_size().y + 5 if _slot_btn.visible else 0.0))
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
	var restore_focus := _owns_focus()
	VisualUtil.clear_children(_cards_box)
	_card_buttons.clear()
	var pages := maxi(1,ceili(float(_hand.size())/3.0))
	_page = clampi(_page,0,pages-1)
	_previous.disabled = _page == 0
	_next.disabled = _page == pages-1
	_previous.focus_mode = Control.FOCUS_NONE if _previous.disabled else Control.FOCUS_ALL
	_next.focus_mode = Control.FOCUS_NONE if _next.disabled else Control.FOCUS_ALL
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
		b.gui_input.connect(_page_input)
		_cards_box.add_child(b)
		_card_buttons[cid] = b
	_layout()
	if restore_focus and not _card_buttons.is_empty():
		VisualUtil.focus_if_present.call_deferred(_card_buttons.values()[0] as Control)

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
	_slot_btn.disabled = _selected == &""
	_back_btn.focus_mode = Control.FOCUS_NONE if _back_btn.disabled else Control.FOCUS_ALL
	_slot_btn.focus_mode = Control.FOCUS_NONE if _slot_btn.disabled else Control.FOCUS_ALL
	_title.text = "ВОРОТА · выберите карту слева" if _selected == &"" else "ВОРОТА · «Место на поле…» или щелчок по арене"

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
	var pages := maxi(1, ceili(float(_hand.size()) / 3.0))
	var next_page := clampi(_page + delta, 0, pages - 1)
	if next_page == _page: return
	_page = next_page
	_rebuild()
	_refresh_selection()


func _owns_focus() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	return owner != null and (_dock.is_ancestor_of(owner) or _pager.is_ancestor_of(owner) or _panel.is_ancestor_of(owner))


func focus_selected_card() -> void:
	_build()
	if not is_visible_in_tree() or not _dock_visible or _hand.is_empty(): return
	var index := _hand.find(_selected)
	if index < 0: index = mini(_page * 3, _hand.size() - 1)
	var changed_page := _page != index / 3
	if changed_page:
		_page = index / 3
		_rebuild()
	var id := StringName(str(_hand[index]))
	if _card_buttons.has(id): (_card_buttons[id] as Control).grab_focus()
	# _rebuild() также ставит отложенный focus: выбранный ID должен выиграть,
	# но только пока фокус остаётся в этой руке, без перехвата новой модали.
	if changed_page: _finish_selected_card_focus.call_deferred(id)


func _finish_selected_card_focus(id: StringName) -> void:
	if _owns_focus() and _card_buttons.has(id): (_card_buttons[id] as Control).grab_focus()


func _page_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not _dock.visible: return
	var delta := 0
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: delta = -1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: delta = 1
	elif event is InputEventKey and event.pressed and not event.echo and _owns_focus():
		if event.keycode == KEY_LEFT: delta = -1
		elif event.keycode == KEY_RIGHT: delta = 1
	if delta != 0:
		_change_page(delta)
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if _owns_focus(): _page_input(event)
