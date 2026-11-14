class_name AbilityPanel
extends Control
## Рука способностей и действия в окнах до броска, после приземления и в бою.

signal ability_chosen(card_id: StringName)
signal gate_open_requested
signal passed
signal unavailable(reason: String)
var reason_for_card: Callable
var warning_for_card: Callable
var _page := 0
var _capacity := 5
var _pager: HBoxContainer
var _previous: Button
var _next: Button
var _page_label: Label

enum Mode { IDLE, WINDOW, PRETHROW }

const MAX_CARDS := 3        # лимит карт на бой (MatchController.MAX_BATTLE_ABILITIES)

var _card := Vector2(150, 210)
var _fan_h := 320.0
var _step := 122.0
var _hand_center := 450.0
var _fan: Control
var _caption: Label
var _device_dock: Panel
var _panel: PanelContainer   # заголовок окна, счётчик карт и «Пас»; виден только в окне
var _title: Label
var _note: Label
var _pips: HBoxContainer
var _gate_btn: Button
var _pass_btn: Button
var _cards: Array[CardView] = []
var _hand: Array[StringName] = []
var _legal: Array[StringName] = []
var _mode := Mode.IDLE
var _info: Dictionary = {}
var _hovered: CardView = null
var _built := false
var _pending_focus_id: StringName = &""
var _pending_focus_index := -1


func _ready() -> void:
	_build()
	UiTheme.apply_device_frame(self, "СПОСОБНОСТИ", false)


## Размер карт зависит от высоты окна: в 1080p крупнее, в 768p компактнее.
func _calc_sizes() -> void:
	var vp := get_viewport_rect().size
	_card = UiTheme.device_hand_card(vp)
	_fan_h = _card.y + 82.0
	_step = _card.x + 8.0
	var lane := UiTheme.device_hand_lane(vp)
	_capacity = clampi(int((lane - 4.0) / _step), 1, 4)
	_hand_center = vp.x - 14.0 - lane * 0.5


func _build() -> void:
	if _built:
		return
	_built = true
	VisualUtil.full_rect_ignore(self)
	theme = UiTheme.get_theme()
	_calc_sizes()
	_device_dock = UiTheme.device_hand_background()
	add_child(_device_dock)

	_fan = Control.new()
	_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fan.anchor_left = 0.0
	_fan.anchor_right = 0.0
	_fan.anchor_top = 1.0
	_fan.anchor_bottom = 1.0
	_fan.offset_left = 0.0
	_fan.offset_right = 0.0
	_fan.offset_top = -_fan_h
	_fan.offset_bottom = 0.0
	_fan.visible = false
	add_child(_fan)

	_caption = VisualUtil.label("СПОСОБНОСТИ", 14)
	_caption.add_theme_color_override("font_color", UiTheme.DEVICE_ACCENT)
	_caption.position = Vector2(10, 3)
	_device_dock.add_child(_caption)
	_fan.visibility_changed.connect(_place_device_dock)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEVICE_INK, UiTheme.DEVICE_DIM, 1, 5, 10))
	add_child(_panel)
	_panel.resized.connect(_place_device_actions)
	var hb := VBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	_panel.add_child(hb)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	hb.add_child(left)
	_title = VisualUtil.label("", 15)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(232, 0)
	left.add_child(_title)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	left.add_child(prow)
	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 4)
	prow.add_child(_pips)
	_note = VisualUtil.label("", 13)
	_note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(232, 0)
	left.add_child(_note)
	_gate_btn = Button.new()
	_gate_btn.text = "Открыть мои ворота"
	_gate_btn.custom_minimum_size = Vector2(176, 44)
	_gate_btn.pressed.connect(func() -> void: gate_open_requested.emit())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	hb.add_child(actions)
	actions.add_child(_gate_btn)
	_pass_btn = Button.new()
	_pass_btn.text = "Пас"
	_pass_btn.custom_minimum_size = Vector2(92, 44)
	_pass_btn.pressed.connect(_on_pass)
	actions.add_child(_pass_btn)
	_panel.visible = false
	_pager = HBoxContainer.new()
	add_child(_pager)
	_previous = Button.new()
	_previous.text = "‹"
	_previous.custom_minimum_size = Vector2(40, 36)
	_previous.pressed.connect(_change_page.bind(-1))
	_previous.gui_input.connect(_page_input)
	_pager.add_child(_previous)
	_page_label = VisualUtil.label("", 13)
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pager.add_child(_page_label)
	_next = Button.new()
	_next.text = "›"
	_next.custom_minimum_size = Vector2(40, 36)
	_next.pressed.connect(_change_page.bind(1))
	_next.gui_input.connect(_page_input)
	_pager.add_child(_next)
	_pager.tooltip_text = "Страницы способностей: кнопки, ← / → при фокусе в этой руке или колёсико над картой. Tab — сменить руку. Фокус / наведение — полный текст."
	_pager.visible = false
	get_viewport().size_changed.connect(_on_resized)
	_place_device_dock()


func _place_device_actions() -> void:
	var vp := get_viewport_rect().size
	_panel.position = Vector2((vp.x - _panel.size.x) * 0.5, vp.y - _panel.size.y - 8.0)


func _place_device_dock() -> void:
	if _pager == null: return
	_device_dock.visible = _fan.visible and not _hand.is_empty()
	_caption.text = "СПОСОБНОСТИ · %d" % _hand.size()
	var vp := get_viewport_rect().size
	var lane := UiTheme.device_hand_lane(vp)
	_device_dock.position = Vector2(vp.x - lane - 14.0, vp.y - _card.y - 76.0)
	_device_dock.size = Vector2(lane, _card.y + 68.0)
	VisualUtil.place(_pager, 1.0, 1.0, -24.0, -8.0)
	_pager.visible = _fan.visible and _hand.size() > _capacity


func _on_resized() -> void:
	var focused := get_viewport().gui_get_focus_owner() as CardView
	var focused_id := focused.card_id if focused != null and focused.get_parent() == _fan else &""
	_calc_sizes()
	_fan.offset_top = -_fan_h
	_panel.reset_size()
	_place_device_actions()
	_rebuild(focused_id)


## Карты способностей в руке игрока (ещё не сыгранные).
func set_hand(ids: Array) -> void:
	_build()
	var fresh: Array[StringName] = []
	for id in ids:
		if StringName(str(id)) != &"":
			fresh.append(StringName(str(id)))
	if fresh == _hand and _cards.size() == _hand.size():
		return
	_hand = fresh
	_rebuild()


## entries: [{id:StringName, name:String, text:String}] — доступные сейчас карты.
## info: {moment: &"battle"/&"pre_throw"/&"after_landing", used: сколько карт уже сыграно (из лимита 3),
## pass_text: подпись кнопки, note: пояснение под заголовком}.
func show_options(entries: Array, header: String = "Окно способностей", info: Dictionary = {}) -> void:
	_build()
	_legal.clear()
	for e in entries:
		var cid := StringName(str(e["id"]))
		_legal.append(cid)
		if not _hand.has(cid):
			_hand.append(cid)
	_page = 0
	_info = info
	var moment: StringName = StringName(str(info.get("moment", &"battle")))
	_info["header"] = header
	_mode = Mode.PRETHROW if moment == &"pre_throw" else Mode.WINDOW
	_title.text = header
	_note.text = str(info.get("note", ""))
	# Длинная справка не должна растить боевой блок поверх последней сыгранной карты.
	_update_option_note()
	_panel.tooltip_text = _note.text + ("\nКарты играются по очереди, до трёх за бой. Наведите на название сыгранной карты, чтобы прочитать полные условия. Отдых — два следующих боя, даже после отмены. Последнему сразу возвращаются только синие усиления; явный возврат карты действует раньше." if moment == &"battle" else "")
	_gate_btn.visible = bool(info.get("can_open_gate", false))
	_pass_btn.visible = _mode == Mode.WINDOW
	_pass_btn.text = str(info.get("pass_text", "Пас"))
	_pass_btn.tooltip_text = str(info.get("pass_tip", ""))
	_fill_pips(int(info.get("used", 0)))
	_panel.visible = true
	_panel.reset_size()
	_place_device_actions()
	_fan.visible = true
	# Отмена выбора цели не тратит карту в контроллере: show_options получает
	# её снова. Старый CardView уже удалён, поэтому возвращаемся по ID.
	var restore_id := _pending_focus_id if _legal.has(_pending_focus_id) else &""
	if restore_id != &"" and _pending_focus_index >= 0:
		_hand.erase(restore_id)
		_hand.insert(mini(_pending_focus_index, _hand.size()), restore_id)
	_pending_focus_id = &""
	_pending_focus_index = -1
	_rebuild(restore_id)


## Счётчик карт: сыгранные закрашены, оставшиеся — пустые кружки (лимит 3 на бой).
func _fill_pips(used: int) -> void:
	VisualUtil.clear_children(_pips)
	var cap := VisualUtil.label("Карт за бой:", 13)
	cap.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_pips.add_child(cap)
	for i in range(MAX_CARDS):
		var l := VisualUtil.label("●" if i < used else "○", 20)
		l.add_theme_color_override("font_color", UiTheme.GOLD if i < used else UiTheme.TEXT_DIM)
		_pips.add_child(l)
	var cnt := VisualUtil.label("%d/%d" % [mini(used, MAX_CARDS), MAX_CARDS], 14)
	cnt.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_pips.add_child(cnt)


func _update_option_note() -> void:
	var battle := StringName(str(_info.get("moment", &""))) == &"battle"
	_pips.get_parent().visible = not battle
	_note.visible = not _note.text.is_empty()


func hide_panel() -> void:
	_build()
	_mode = Mode.IDLE
	_legal.clear()
	_panel.visible = false
	_layout()
	for cv in _cards:
		cv.set_meta("silent_select", true)
		cv.set_dimmed(false)
		cv.set_playable(false)


## Показать или скрыть руку целиком (меню, конец игры).
func set_dock_visible(on: bool) -> void:
	_build()
	if not on:
		_pending_focus_id = &""
		_pending_focus_index = -1
	_fan.visible = on
	_place_device_dock()


func _rebuild(focus_id: StringName = &"") -> void:
	var focused := get_viewport().gui_get_focus_owner() as CardView
	var restore_focus := focused != null and focused.get_parent() == _fan
	for cv in _cards:
		_fan.remove_child(cv)
		cv.queue_free()
	_cards.clear()
	_hovered = null
	var ordered: Array[StringName] = []
	for cid in _hand:
		if _legal.has(cid):
			ordered.append(cid)
	for cid in _hand:
		if not ordered.has(cid):
			ordered.append(cid)
	var pages := maxi(1, ceili(float(ordered.size()) / _capacity))
	if focus_id != &"" and ordered.has(focus_id):
		_page = int(ordered.find(focus_id) / _capacity)
	_page = clampi(_page, 0, pages - 1)
	_place_device_dock()
	_page_label.text = "  %d карт · %d/%d  " % [_hand.size(), _page + 1, pages]
	_previous.disabled = _page == 0
	_next.disabled = _page >= pages - 1
	_previous.focus_mode = Control.FOCUS_NONE if _previous.disabled else Control.FOCUS_ALL
	_next.focus_mode = Control.FOCUS_NONE if _next.disabled else Control.FOCUS_ALL
	for cid in ordered.slice(_page * _capacity, (_page + 1) * _capacity):
		var def: CardDef = CardDB.card(cid)
		if def == null:
			continue
		var cv := CardView.new().for_card(def, _card)
		cv.set_meta("device_hand_card", true)
		cv.pivot_offset = Vector2(_card.x * 0.5, _card.y)
		cv.mouse_entered.connect(_on_hover.bind(cv, true))
		cv.mouse_exited.connect(_on_hover.bind(cv, false))
		cv.focus_entered.connect(_on_hover.bind(cv, true))
		cv.focus_exited.connect(func() -> void: _on_hover(cv, cv.is_hovered()))
		cv.pressed.connect(_on_card_pressed.bind(cv))
		cv.gui_input.connect(_page_input)
		var reason := str(reason_for_card.call(cid)) if reason_for_card.is_valid() else "Сейчас эта карта недоступна"
		cv._help[6] = reason if not _legal.has(cid) else _playable_help(cid)
		cv.set_meta("silent_select", not _legal.has(cid) or _mode == Mode.IDLE)
		if _mode != Mode.IDLE:
			var ok: bool = _legal.has(cid)
			cv.set_dimmed(not ok, true)
			cv.disabled = false  # Недоступную карту можно изучить и получить объяснение.
		_fan.add_child(cv)
		_cards.append(cv)
		if _mode != Mode.IDLE and _legal.has(cid):
			cv.set_playable(true)
	_layout()
	if focus_id != &"":
		for cv in _cards:
			if cv.card_id == focus_id: VisualUtil.focus_if_present.call_deferred(cv)
	elif restore_focus and not _cards.is_empty():
		VisualUtil.focus_if_present.call_deferred(_cards[0])


func _layout() -> void:
	var mid := (_cards.size() - 1) * 0.5
	for i in _cards.size():
		var cv := _cards[i]
		cv.position = Vector2(_hand_center + (i - mid) * _step - _card.x * 0.5, _fan_h - _card.y - 50.0)
		cv.z_index = 50 if cv == _hovered else i


func _on_hover(cv: CardView, on: bool) -> void:
	if on:
		if reason_for_card.is_valid():
			cv._help[6] = str(reason_for_card.call(cv.card_id)) if _mode == Mode.IDLE or not _legal.has(cv.card_id) else _playable_help(cv.card_id)
		_hovered = cv
	elif _hovered == cv:
		_hovered = cv if cv.has_focus() else null
	var warning := _warning(cv.card_id) if on and _mode != Mode.IDLE and _legal.has(cv.card_id) else ""
	_title.text = _warning_title(cv.card_id) if warning != "" else str(_info.get("header", ""))
	_title.tooltip_text = warning
	_layout()


func _warning(id: StringName) -> String:
	return str(warning_for_card.call(id)) if warning_for_card.is_valid() else ""


func _warning_title(id: StringName) -> String:
	var card := CardDB.card(id)
	if CardEffects.is_effect(card, &"swap_fighter"): return "Внимание: замена бойца"
	if CardEffects.is_effect(card, &"shift_gate"): return "Внимание: обмен воротами"
	if CardEffects.is_effect(card, &"ebb"): return "Внимание: условие прерывания"
	return "Внимание: запрет дальнейших карт"


func _playable_help(id: StringName) -> String:
	var warning := _warning(id)
	return "ДОСТУПНА · щелчок, чтобы сыграть" + ("\n" + warning if warning != "" else "")


func _on_card_pressed(cv: CardView) -> void:
	var cid: StringName = cv.card_id
	if _mode == Mode.IDLE or not _legal.has(cid):
		unavailable.emit(str(reason_for_card.call(cid)) if reason_for_card.is_valid() else "Сейчас эта карта недоступна")
		return
	_pending_focus_id = cid if cv.has_focus() else &""
	_pending_focus_index = _hand.find(cid) if cv.has_focus() else -1
	_mode = Mode.IDLE
	_panel.visible = false
	_hovered = null
	_cards.erase(cv)
	_hand.erase(cid)
	_fan.remove_child(cv)
	cv.queue_free()
	_rebuild()
	ability_chosen.emit(cid)


func _on_pass() -> void:
	passed.emit()


func _change_page(delta: int) -> void:
	var pages := maxi(1, ceili(float(_hand.size()) / _capacity))
	var next_page := clampi(_page + delta, 0, pages - 1)
	if next_page != _page:
		_page = next_page
		_rebuild()


func _unhandled_key_input(event: InputEvent) -> void:
	if _owns_focus(): _page_input(event)


func _owns_focus() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	return owner != null and (_fan.is_ancestor_of(owner) or _pager.is_ancestor_of(owner) or _panel.is_ancestor_of(owner))


func _page_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not _fan.visible: return
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
