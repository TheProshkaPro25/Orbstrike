class_name AbilityPanel
extends Control
## Рука карт способностей внизу экрана, веером, как настоящие карты в руке.
## Вне окон рука опущена (видны верхушки карт); наведение поднимает карту.
## Три момента: «в бою» (обмен по очереди, рука поднята), «до броска» (рука приподнята, ход не ждёт),
## «после приземления» (рука поднята, можно прикрепить карту или завершить ход).
## Играбельные карты светятся и пульсируют, остальные гаснут; сыгранная карта вылетает к центру экрана.

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
var _layout_tweens: Dictionary = {}

enum Mode { IDLE, WINDOW, PRETHROW }

const PEEK := 84.0          # сколько карты видно в опущенной руке
const PEEK_PRETHROW := 150.0
const SPREAD_DEG := 7.0     # поворот соседних карт
const MAX_CARDS := 3        # лимит карт на бой (MatchController.MAX_BATTLE_ABILITIES)

var _card := Vector2(150, 210)
var _fan_h := 320.0
var _step := 122.0
var _hand_center := 450.0
var _fan: Control
var _caption: Label
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


func _ready() -> void:
	_build()


## Размер карт зависит от высоты окна: в 1080p крупнее, в 768p компактнее.
func _calc_sizes() -> void:
	var vh: float = get_viewport_rect().size.y
	var h: float = clampf(vh * 0.255, 190.0, 262.0)
	_card = Vector2(roundf(h * 0.715), roundf(h))
	_fan_h = _card.y + 110.0
	_step = _card.x * 1.06
	var vp := get_viewport_rect().size
	var available := maxf(250.0, vp.x * .48 - 32.0)
	_step = _card.x * 1.04
	_capacity = clampi(int(available / _step), 1, 4)
	_hand_center = vp.x * .75 - 8.0


func _build() -> void:
	if _built:
		return
	_built = true
	VisualUtil.full_rect_ignore(self)
	theme = UiTheme.get_theme()
	_calc_sizes()

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

	_caption = VisualUtil.label("Ваши способности", 13)
	_caption.visible = false
	_fan.add_child(_caption)

	_panel = PanelContainer.new()
	VisualUtil.place(_panel, 1.0, 1.0, -16.0, -_card.y - 96.0)
	add_child(_panel)
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
	_note = VisualUtil.label("", 12)
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
	VisualUtil.place(_pager, 1.0, 1.0, -18.0, -20.0)
	add_child(_pager)
	_previous = Button.new()
	_previous.text = "‹"
	_previous.custom_minimum_size = Vector2(40, 36)
	_previous.pressed.connect(_change_page.bind(-1))
	_pager.add_child(_previous)
	_page_label = VisualUtil.label("", 13)
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pager.add_child(_page_label)
	_next = Button.new()
	_next.text = "›"
	_next.custom_minimum_size = Vector2(40, 36)
	_next.pressed.connect(_change_page.bind(1))
	_pager.add_child(_next)
	_pager.tooltip_text = "Страницы руки: кнопки, ← / → или колёсико над картой. Наведение — полный текст."
	_pager.visible = false
	get_viewport().size_changed.connect(_on_resized)


## В бою блок лежит над опущенной рукой ворот, не закрывая бойцов и ленту карт.
func _place_panel() -> void:
	if StringName(str(_info.get("moment", &""))) == &"battle":
		VisualUtil.place(_panel, 0.0, 1.0, 16.0, -110.0)
	else:
		VisualUtil.place(_panel, 1.0, 1.0, -16.0, -_card.y - 96.0)


func _on_resized() -> void:
	_calc_sizes()
	_fan.offset_top = -_fan_h
	_place_panel()
	_rebuild()


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
	_note.visible = _note.text != "" and moment != &"battle"
	_panel.tooltip_text = _note.text + ("\nКарты играются по очереди, до трёх за бой. Наведите на название сыгранной карты, чтобы прочитать полные условия. Отдых — два следующих боя, даже после отмены. Последнему сразу возвращаются только синие усиления; явный возврат карты действует раньше." if moment == &"battle" else "")
	_gate_btn.visible = bool(info.get("can_open_gate", false))
	_pass_btn.visible = _mode == Mode.WINDOW
	_pass_btn.text = str(info.get("pass_text", "Пас"))
	_pass_btn.tooltip_text = str(info.get("pass_tip", ""))
	_fill_pips(int(info.get("used", 0)))
	_panel.visible = true
	_place_panel()
	_fan.visible = true
	_rebuild()


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


func hide_panel() -> void:
	_build()
	_mode = Mode.IDLE
	_legal.clear()
	_panel.visible = false
	_layout(true)
	for cv in _cards:
		cv.set_meta("silent_select", true)
		cv.set_dimmed(false)
		cv.set_playable(false)


## Показать или скрыть руку целиком (меню, конец игры).
func set_dock_visible(on: bool) -> void:
	_build()
	_fan.visible = on
	_pager.visible = on and not _hand.is_empty()


## Карта, сыгранная соперником: появляется сверху по центру и гаснет.
func show_played(card_id: StringName, by_opponent: bool) -> void:
	var def: CardDef = CardDB.card(card_id)
	if def == null or not by_opponent:
		return
	_build()
	var cv := CardView.new().for_card(def, _card)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cv)
	var vp := get_viewport_rect().size
	cv.pivot_offset = _card * 0.5
	cv.position = Vector2(vp.x * 0.5 - _card.x * 0.5, -_card.y)
	cv.scale = Vector2(0.8, 0.8)
	var tw := cv.create_tween()
	tw.tween_property(cv, "position:y", vp.y * 0.32, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cv, "scale", Vector2(1.25, 1.25), 0.35)
	tw.tween_interval(0.9)
	tw.tween_property(cv, "modulate:a", 0.0, 0.35)
	tw.tween_callback(cv.queue_free)


func _rebuild() -> void:
	for tw in _layout_tweens.values():
		if tw.is_valid():
			tw.kill()
	_layout_tweens.clear()
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
	_page = clampi(_page, 0, pages - 1)
	_pager.visible = _fan.visible and not _hand.is_empty()
	_page_label.text = "  %d карт · %d/%d  " % [_hand.size(), _page + 1, pages]
	_previous.disabled = _page == 0
	_next.disabled = _page >= pages - 1
	for cid in ordered.slice(_page * _capacity, (_page + 1) * _capacity):
		var def: CardDef = CardDB.card(cid)
		if def == null:
			continue
		var cv := CardView.new().for_card(def, _card)
		cv.pivot_offset = Vector2(_card.x * 0.5, _card.y)
		cv.mouse_entered.connect(_on_hover.bind(cv, true))
		cv.mouse_exited.connect(_on_hover.bind(cv, false))
		cv.pressed.connect(_on_card_pressed.bind(cv))
		cv.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed:
				if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
					_change_page(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
					get_viewport().set_input_as_handled())
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
	_layout(false)


## Раскладка веером. Опущенная рука показывает только верх карт; в окне играбельные карты приподняты выше.
func _layout(animate: bool) -> void:
	var n: int = _cards.size()
	var mid: float = (n - 1) * 0.5
	var peek: float = PEEK_PRETHROW if _mode == Mode.PRETHROW else PEEK
	for i in range(n):
		var cv: CardView = _cards[i]
		var k: float = i - mid
		var playable: bool = _mode != Mode.IDLE and _legal.has(cv.card_id)
		var top: float = _fan_h - peek
		if _mode == Mode.WINDOW:
			top = _fan_h - _card.y - 62.0 + (0.0 if playable else 8.0)
		elif cv == _hovered:
			top = _fan_h - _card.y - 18.0
		if cv == _hovered:
			top -= 22.0
		var pos := Vector2(_hand_center + k * _step - _card.x * 0.5, top + k * k * 1.4)
		var rot: float = 0.0 if cv == _hovered else deg_to_rad(k * 1.8)
		var sc: Vector2 = Vector2(1.12, 1.12) if cv == _hovered else Vector2.ONE
		cv.z_index = 50 if cv == _hovered else i
		if _layout_tweens.has(cv) and _layout_tweens[cv].is_valid():
			_layout_tweens[cv].kill()
		if animate:
			var tw := cv.create_tween().set_parallel(true)
			_layout_tweens[cv] = tw
			tw.tween_property(cv, "position", pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(cv, "rotation", rot, 0.16)
			tw.tween_property(cv, "scale", sc, 0.16)
		else:
			cv.position = pos
			cv.rotation = rot
			cv.scale = sc


func _on_hover(cv: CardView, on: bool) -> void:
	if on:
		if reason_for_card.is_valid():
			cv._help[6] = str(reason_for_card.call(cv.card_id)) if _mode == Mode.IDLE or not _legal.has(cv.card_id) else _playable_help(cv.card_id)
		_hovered = cv
	elif _hovered == cv:
		_hovered = null
	var warning := _warning(cv.card_id) if on and _mode != Mode.IDLE and _legal.has(cv.card_id) else ""
	_title.text = _warning_title(cv.card_id) if warning != "" else str(_info.get("header", ""))
	_title.tooltip_text = warning
	_layout(true)


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
	_mode = Mode.IDLE
	_panel.visible = false
	# сыгранная карта вылетает к центру экрана и гаснет, остальные опускаются
	if _layout_tweens.has(cv) and _layout_tweens[cv].is_valid():
		_layout_tweens[cv].kill()
	_layout_tweens.erase(cv)
	_hovered = null
	_cards.erase(cv)
	_hand.erase(cid)
	_pager.visible = not _hand.is_empty()
	var gp := cv.global_position
	_fan.remove_child(cv)
	add_child(cv)
	cv.global_position = gp
	cv.z_index = 20
	cv.set_playable(false)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport_rect().size
	var tw := cv.create_tween()
	tw.tween_property(cv, "position", Vector2(vp.x * 0.5 - _card.x * 0.5, vp.y * 0.28), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cv, "rotation", 0.0, 0.3)
	tw.parallel().tween_property(cv, "scale", Vector2(1.5, 1.5), 0.3)
	tw.tween_interval(0.5)
	tw.tween_property(cv, "modulate:a", 0.0, 0.3)
	tw.tween_callback(cv.queue_free)
	for c in _cards:
		c.set_dimmed(false)
		c.set_playable(false)
	_layout(true)
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
	if not _fan.visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_LEFT, KEY_RIGHT]:
		_change_page(-1 if event.keycode == KEY_LEFT else 1)
		get_viewport().set_input_as_handled()
