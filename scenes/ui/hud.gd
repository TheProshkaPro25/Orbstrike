class_name HudUI
extends Control
## Плашки игроков, ход, лента событий, уведомления и выбор существа.

signal creature_chosen(uid: int)
signal creature_cancelled
signal battle_mode_changed(on: bool)

const LOG_LINES := 3
const DEVICE_MOTION := preload("res://scenes/ui/device_motion.gd")

var _hint: Label
var _hint_plate: PanelContainer
var _turn_clip: Control
var _turn_label: Label
var _turn_key := ""
var _phase_label: Label
var _phase := -1
var _final_round := false
var _active_side := 0
var _turn := 0
var _event_showing := false
var _plates: Array[FighterPlate] = []
var _log_box: VBoxContainer
var _log_lines: Array[Label] = []
var _flash: Label
var _creature_panel: PanelContainer
var _creature_title: Label
var _creature_box: HBoxContainer
var _cancel_btn: Button
var _help_btn: Button
var _tempo: OptionButton
var _hint_layout_pending := false
var _hint_tw: Tween
var _battle := false
var _built := false
var _reading := 0
var _skip_flag := false
var opponent_panel: OpponentPanel
var own_panel: OpponentPanel
var _interface_watchers: Array[Node] = []
var _match_intro_started := false
var _skip_hint: Label


func _ready() -> void:
	_build()
	UiTheme.apply_device_frame(self, "")
	get_viewport().size_changed.connect(_layout_opponent_toolbar)
	_layout_opponent_toolbar()
	_turn_clip.set_meta("device_reveal_region",true)
	_log_box.set_meta("device_reveal_region",true)
	register_interface(self)


func _build() -> void:
	if _built:
		return
	_built = true
	VisualUtil.full_rect_ignore(self)
	theme = UiTheme.get_theme()

	for side in range(2):
		var fp := FighterPlate.new(side, "Вы" if side == 0 else "Соперник")
		VisualUtil.place(fp, float(side), 0.0, 14.0 if side == 0 else -14.0, 8.0)
		fp.visible = false
		add_child(fp)
		_plates.append(fp)
		fp.resized.connect(_queue_hint_layout)

	_turn_clip = Control.new()
	_turn_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_clip.clip_contents = true
	_turn_clip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var tbg := Panel.new()
	tbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tbg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tbg.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEVICE_INK, UiTheme.DEVICE_DIM, 1, 4, 0))
	_turn_clip.add_child(tbg)
	_turn_label = VisualUtil.label("", 22)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_clip.add_child(_turn_label)
	_turn_clip.visible = false
	add_child(_turn_clip)
	_phase_label = VisualUtil.label("", 14)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_color_override("font_color", Color(0.60, 0.85, 0.95))
	_phase_label.add_theme_constant_override("outline_size", 4)
	VisualUtil.place(_phase_label, 0.5, 0.0, 0.0, 49.0)
	add_child(_phase_label)

	_hint_plate = PanelContainer.new()
	_hint_plate.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEVICE_INK, UiTheme.DEVICE_DIM, 1, 4, 5))
	_hint_plate.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hint_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_plate.minimum_size_changed.connect(_queue_hint_layout)
	add_child(_hint_plate)
	_hint = VisualUtil.label("", 15)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_plate.add_child(_hint)
	_hint_plate.visible = false

	# лента событий под левой плашкой: 3 последние строки, старые бледнеют
	_log_box = VBoxContainer.new()
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_box.add_theme_constant_override("separation", 0)
	VisualUtil.place(_log_box, 0.0, 0.0, 16.0, 108.0)
	add_child(_log_box)

	_flash = VisualUtil.label("", 28)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # не заходит на ленту событий слева и плашки по углам
	_flash.custom_minimum_size = Vector2(maxf(420.0, get_viewport_rect().size.x * 0.46), 0)
	_flash.add_theme_color_override("font_color", UiTheme.GOLD)
	_flash.add_theme_color_override("font_outline_color", Color.BLACK)
	_flash.add_theme_constant_override("outline_size", 10)
	_flash.visible = false
	VisualUtil.place(_flash, 0.5, 0.0, 0.0, 128.0)
	add_child(_flash)
	_skip_hint = VisualUtil.label("Enter / Пробел / клик — дальше", 15)
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_hint.modulate = Color(1, 1, 1, 0.7)
	_skip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_hint.visible = false
	VisualUtil.place(_skip_hint, 0.5, 0.56, 0.0, 0.0)
	add_child(_skip_hint)

	_help_btn = Button.new()
	_help_btn.text = "?"
	_help_btn.tooltip_text = "Как играть"
	_help_btn.custom_minimum_size = Vector2(44, 44)
	VisualUtil.place(_help_btn, 1.0, 0.0, -12.0, 10.0)
	_help_btn.pressed.connect(func() -> void: HelpOverlay.open_on(get_parent()))
	add_child(_help_btn)

	_tempo = OptionButton.new()
	for n in BattleTempo.NAMES:
		_tempo.add_item(n)
	_tempo.select(BattleTempo.selected)
	_tempo.tooltip_text = "Темп постановки. Сообщения можно читать в своём темпе; Enter — дальше."
	VisualUtil.place(_tempo, 1.0, 0.0, -16.0, 114.0)
	_tempo.item_selected.connect(BattleTempo.set_tempo)
	add_child(_tempo)

	own_panel = OpponentPanel.new()
	if own_panel.has_method("configure_side"): own_panel.call("configure_side",0)
	add_child(own_panel)
	own_panel.visibility_changed.connect(_layout_owned_context)
	opponent_panel = OpponentPanel.new()
	if opponent_panel.has_method("configure_side"): opponent_panel.call("configure_side",1)
	add_child(opponent_panel)

	_creature_panel = PanelContainer.new()
	_creature_panel.visible = false
	VisualUtil.place(_creature_panel, 0.5, 1.0, 0.0, -92.0)  # над опущенной рукой способностей
	add_child(_creature_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_creature_panel.add_child(vb)
	_creature_title = VisualUtil.label("Выберите существо", 20)
	_creature_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_creature_title)
	_creature_box = HBoxContainer.new()
	_creature_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_creature_box.add_theme_constant_override("separation", 14)
	vb.add_child(_creature_box)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Назад"
	_cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cancel_btn.custom_minimum_size = Vector2(120, 36)
	_cancel_btn.pressed.connect(func() -> void: creature_cancelled.emit())
	_cancel_btn.visible = false
	vb.add_child(_cancel_btn)


## Called once after Main exposes both hands. It never waits or changes input.
func begin_match_interface(hands: Array[Control] = []) -> void:
	if _match_intro_started: return
	_match_intro_started = true
	UiTheme.begin_hud_intro(self)
	for hand in hands: UiTheme.begin_hud_intro(hand)
	SoundFx.i().play("device_power", -10.0, 0.0)
	_start_boot_motion.call_deferred(hands)


## Registers late-show/rebuilt controls too. Main can attach its menu/score toolbar.
func register_interface(control: Control) -> void:
	if not is_instance_valid(control): return
	var watcher := DEVICE_MOTION.watch_tree(control,false)
	if not _interface_watchers.has(watcher): _interface_watchers.append(watcher)
	if _match_intro_started: watcher.call("start")


func _start_boot_motion(hands: Array[Control]) -> void:
	if not is_inside_tree(): return
	for hand in hands: register_interface(hand)
	if DeviceSettings.reduce_motion(): return
	DEVICE_MOTION.stop_on(_turn_clip,"turn")
	for watcher in _interface_watchers:
		if is_instance_valid(watcher): watcher.call("start")


func _layout_owned_context() -> void:
	_queue_hint_layout()
	if _log_box == null: return
	var y := own_panel.get_rect().end.y + 8.0 if _own_context_visible() else OpponentPanel.SIDE_TOP
	VisualUtil.place(_log_box, 0.0, 0.0, 14.0, y)
	_log_box.size.x = clampf(get_viewport_rect().size.x * 0.24, 190.0, 318.0)
	_place_coach()


func _own_context_visible() -> bool:
	return is_instance_valid(own_panel) and own_panel.is_visible_in_tree()


func _layout_opponent_toolbar() -> void:
	_queue_hint_layout()
	if _tempo == null: return
	VisualUtil.place(_help_btn, 1.0, 0.0, -14.0, 97.0)
	VisualUtil.place(_tempo, 1.0, 0.0, -66.0, 97.0)
	_tempo.custom_minimum_size.y = 44
	var viewport := get_viewport_rect().size
	var turn_width := UiTheme.device_status_width(viewport)
	_turn_clip.custom_minimum_size.x = turn_width
	VisualUtil.place(_turn_clip, 0.5, 0.0, 0.0, 8.0)
	_turn_clip.size = Vector2(turn_width, 40)
	_turn_label.size = _turn_clip.size
	_place_flash()
	var bottom := -UiTheme.device_hand_card(viewport).y - 76.0
	VisualUtil.place(_creature_panel, 0.5, 1.0, 0.0, bottom)
	_layout_owned_context()


## Имена и цвета стихий существ бойцов: colors0/colors1 — по существу в порядке колоды; elems — их стихии (значки).
func setup_plates(colors0: Array, colors1: Array, elems: Array = [[], []]) -> void:
	_build()
	_plates[0].set_team(colors0, elems[0])
	_plates[1].set_team(colors1, elems[1])
	for p in _plates:
		p.visible = true


func set_names(n0: String, n1: String) -> void:
	_build()
	_plates[0].set_title(n0)
	_plates[1].set_title(n1)


func set_portrait(side: int,texture: Texture2D) -> void:
	_build()
	_plates[side].set_portrait(texture)


## The portrait viewport follows this consumer's effective visibility.
func portrait_consumer(side: int) -> CanvasItem:
	_build()
	return _plates[side]._portrait


func kill_creature(player: int, idx: int) -> void:
	_build()
	_plates[player].kill(idx)


func revive_creature(player: int, idx: int) -> void:
	_build()
	_plates[player].revive(idx)


func set_captures(c0: int, c1: int) -> void:
	_build()
	_plates[0].set_gates(c0)
	_plates[1].set_gates(c1)


func set_momentum(player: int, v: int) -> void:
	_build()
	_plates[player].set_momentum(v)


func set_final_round(on: bool) -> void:
	_build()
	_final_round = on
	_update_phase_text()


## Плашка хода обновляется при смене игрока или номера хода.
func set_status(turn: int, active: int, _alive0: int, _alive1: int) -> void:
	_build()
	_turn = turn
	_active_side = active
	var key := "%d:%d" % [turn, active]
	_plates[0].set_active(active == 0)
	_plates[1].set_active(active == 1)
	if key == _turn_key:
		return
	_turn_key = key
	var mine: bool = active == 0
	_update_turn_text()
	_turn_clip.visible = true
	var overlay := DEVICE_MOTION.reveal_on(_turn_clip, 0.0, Vector2(32 if mine else -32, 0), "turn")
	if overlay != null: overlay.set("direction", 1.0 if mine else -1.0)


func _update_turn_text() -> void:
	var mine := _active_side == 0
	var action := "ВАШ ХОД" if mine else "ХОД СОПЕРНИКА"
	if _phase == MatchController.Phase.RESOLVING:
		action = "БОЙ ЗАВЕРШЁН"
	elif _battle:
		action = "ВАШ ОТВЕТ" if mine else "ОТВЕТ СОПЕРНИКА"
		if _phase != MatchController.Phase.ABILITY_WINDOW: action = "СХВАТКА"
	_turn_label.text = "ХОД %d  ·  %s" % [_turn, action]
	_turn_label.add_theme_color_override("font_color", UiTheme.accent() if mine else Color(1.0, 0.72, 0.65))


func set_hint(text: String) -> void:
	_build()
	_hint.text = text
	_queue_hint_layout()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_plate.visible = text != "" and not _event_showing


func _queue_hint_layout() -> void:
	if _hint_layout_pending or not is_inside_tree(): return
	_hint_layout_pending = true
	_layout_hint.call_deferred()


func _layout_hint() -> void:
	_hint_layout_pending = false
	if not is_instance_valid(_hint_plate) or not _hint_plate.visible: return
	var viewport := get_viewport_rect().size
	_hint.custom_minimum_size.x = UiTheme.device_status_width(viewport) - 10.0
	_hint_plate.reset_size()
	_hint_plate.position = Vector2((viewport.x - _hint_plate.size.x) * 0.5, 71.0)


func reject_action(reason: String) -> void:
	SoundFx.i().play("ui_denied", -4.0, 0.0)
	set_hint(reason)
	if _hint_tw != null and _hint_tw.is_valid():
		_hint_tw.kill()
	_hint.modulate = Color(1.0, 0.57, 0.42)
	_hint_tw = create_tween()
	_hint_tw.tween_property(_hint, "modulate", Color.WHITE, 0.7)


func flash(text: String) -> void:
	_build()
	_flash.text = text
	_flash.show()


## Время на прочтение надписи: короткие не затягиваем, длинные держим дольше (≈ 0.035 с на символ).
static func read_time(base: float, text: String = "") -> float:
	return maxf(base, 0.5 + 0.035 * float(text.length()))


## Пауза «на прочтение»: заканчивается по таймеру или раньше — по Enter / Пробелу / ЛКМ (не по клику на кнопке UI,
## такой клик забирает интерфейс). Если пауза длинная, внизу показывается подпись «Enter — дальше».
func wait_read(sec: float) -> void:
	_build()
	_skip_flag = false
	_reading += 1
	var show_hint := sec >= 0.8
	if show_hint:
		_skip_hint.visible = true
	var started := Time.get_ticks_usec()
	while (Time.get_ticks_usec() - started) / 1000000.0 < sec and not _skip_flag and is_inside_tree():
		await get_tree().process_frame
	_reading -= 1
	if _reading <= 0:
		_reading = 0
		_skip_hint.visible = false
	_skip_flag = false


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE and _creature_panel.visible and _cancel_btn.visible:
		get_viewport().set_input_as_handled()
		creature_cancelled.emit()
		return
	var pressed := false
	var is_key := false
	if e is InputEventKey:
		var k := e as InputEventKey
		if k.pressed and not k.echo and k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			pressed = true
			is_key = true
	elif e is InputEventMouseButton:
		var m := e as InputEventMouseButton
		# ЛКМ пропускает только ожидание надписи: в прицеле и броске _reading == 0
		if m.pressed and m.button_index == MOUSE_BUTTON_LEFT and _reading > 0:
			pressed = true
	if not pressed:
		return
	if _reading > 0:
		_skip_flag = true
		get_viewport().set_input_as_handled()
	elif is_key and _coach != null and is_instance_valid(_coach):
		_close_coach()
		get_viewport().set_input_as_handled()


func clear_flash() -> void:
	_build()
	_flash.visible = false


## Лента событий: новая строка въезжает снизу, три последние остаются на экране.
func log_event(text: String, c: Color = UiTheme.TEXT) -> void:
	_build()
	var l := VisualUtil.label(text, 15)
	l.add_theme_color_override("font_color", c)
	l.add_theme_constant_override("outline_size", 5)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_log_box.add_child(l)
	_log_lines.append(l)
	while _log_lines.size() > LOG_LINES:
		var old: Label = _log_lines.pop_front()
		old.queue_free()
	for i in range(_log_lines.size()):
		var age: int = _log_lines.size() - 1 - i
		_log_lines[i].modulate.a = [1.0, 0.7, 0.45][mini(age, 2)]
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.25)


## Широкий баннер через экран («ФИНАЛЬНЫЙ БОЙ», «ЛОВУШКА!»): влетает слева, замирает, улетает вправо.
func banner(title: String, sub: String, c: Color, hold: float = 1.0, battle_notice: bool = false) -> void:
	_build()
	var vp := get_viewport_rect().size
	var band := ColorRect.new()
	band.color = Color(c.r * 0.12, c.g * 0.12, c.b * 0.12, 0.88)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.position = Vector2(0.0, vp.y * 0.30)
	band.size = Vector2(vp.x, 128.0)
	add_child(band)
	var edge := ColorRect.new()
	edge.color = c
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.size = Vector2(vp.x, 3.0)
	band.add_child(edge)
	var edge2 := ColorRect.new()
	edge2.color = c
	edge2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge2.size = Vector2(vp.x, 3.0)
	edge2.position = Vector2(0.0, 125.0)
	band.add_child(edge2)
	var t := VisualUtil.label(title, 64)
	t.add_theme_color_override("font_color", c.lightened(0.45))
	t.add_theme_constant_override("outline_size", 14)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(vp.x, 78.0)
	t.position = Vector2(vp.x, 6.0)
	band.add_child(t)
	var s := VisualUtil.label(sub, 22)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.size = Vector2(vp.x, 30.0)
	s.position = Vector2(-vp.x, 88.0)
	band.add_child(s)
	band.scale = Vector2(1.0, 0.0)
	band.pivot_offset = Vector2(vp.x * 0.5, 64.0)
	if battle_notice and band.is_visible_in_tree():
		SoundFx.i().play_battle_popup()
	var tw := create_tween()
	tw.tween_property(band, "scale:y", 1.0, 0.12)
	tw.tween_property(t, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(s, "position:x", 0.0, 0.36).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	await tw.finished
	await wait_read(read_time(hold, sub))
	tw = create_tween()
	tw.tween_property(t, "position:x", -vp.x, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(s, "position:x", vp.x, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(band, "scale:y", 0.0, 0.1)
	await tw.finished
	band.queue_free()


## entries: [{uid:int, def:CreatureDef, note:String}] (без def - запасной вариант {uid, text}).
func show_creatures(entries: Array, title: String = "Выберите существо для броска", can_cancel: bool = false) -> void:
	_build()
	VisualUtil.clear_children(_creature_box)
	_creature_title.text = title
	for e in entries:
		var uid: int = int(e["uid"])
		var d: CreatureDef = e.get("def")
		var ob := OrbButton.new()
		if d != null:
			ob.for_creature(d, uid, str(e.get("note", "")))
		else:
			ob.title = str(e.get("text", "?"))
			ob.uid = uid
		ob.pressed.connect(_on_creature_pressed.bind(uid))
		_creature_box.add_child(ob)
	_cancel_btn.visible = can_cancel
	_creature_panel.visible = true
	_creature_panel.call_deferred("reset_size")
	var watcher := get_node_or_null("DeviceRevealWatcher")
	if watcher != null: watcher.call("request",_creature_panel)


func hide_creatures() -> void:
	_build()
	_creature_panel.visible = false
	VisualUtil.clear_children(_creature_box)


func _on_creature_pressed(uid: int) -> void:
	creature_chosen.emit(uid)


## В бою основная лента сворачивается, чтобы освободить место для обмена способностями.
func set_battle_mode(on: bool) -> void:
	_build()
	_battle = on
	var reveal_watcher := get_node_or_null("DeviceRevealWatcher")
	if on and reveal_watcher != null: reveal_watcher.call("_settle")
	if on:
		for region in [_plates[0],_plates[1],_turn_clip,_hint_plate]: DEVICE_MOTION.stop_on(region)
		# Недочитанные советы постановки/прикрепления уже не относятся к бою
		# и занимали место компактного блока ответа на невысоком экране.
		_coach_queue.clear()
		_close_coach()
	if not on: _event_showing = false
	_log_box.modulate.a = 0.0 if on else 1.0
	_update_phase_text()
	_update_turn_text()
	_place_flash()
	# Battle changes opacity rather than visibility; explicitly reveal the restored regions.
	if not on and _match_intro_started and reveal_watcher != null: reveal_watcher.call("start")
	_layout_owned_context()
	battle_mode_changed.emit(on)


func set_battle_event_visible(on: bool) -> void:
	_event_showing = on
	set_hint(_hint.text)


func _place_flash() -> void:
	_flash.add_theme_font_size_override("font_size", 18)
	_flash.custom_minimum_size.x = UiTheme.device_status_width(get_viewport_rect().size)
	_flash.add_theme_color_override("font_color", UiTheme.DEVICE_ACCENT)
	VisualUtil.place(_flash, 0.5, 0.0, 0.0, 102.0)


## Короткая вспышка всего экрана (удар).
func screen_flash(c: Color) -> void:
	var r := ColorRect.new()
	r.color = Color(c, minf(c.a, 0.22))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(r)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.35)
	tw.tween_callback(r.queue_free)


static var _coached: Dictionary = {}
var _coach: PanelContainer


## В бою подсказка уезжает под левую плашку бойца (ниже поле свободно), иначе — в левый нижний угол.
func _place_coach() -> void:
	if _coach == null or not is_instance_valid(_coach):
		return
	if _battle:
		var x := own_panel.position.x + own_panel.size.x + 14.0 if _own_context_visible() else 16.0
		VisualUtil.place(_coach, 0.0, 0.0, x, 232.0)
	else:
		var x := own_panel.position.x + own_panel.size.x + 14.0 if _own_context_visible() else 12.0
		VisualUtil.place(_coach, 0.0, 0.0, x, 116.0)


## Подсказка-наставник: один раз за запуск для каждого ключа. Компактная карточка в левом нижнем углу.
## Висит, пока игрок не нажмёт «Ясно» (или Enter / Пробел); новые подсказки ждут своей очереди и не сменяют её.
func coach(key: String, text: String) -> void:
	_build()
	if _coached.has(key):
		return
	_coached[key] = true
	_coach_queue.append([key, text])
	if _coach == null or not is_instance_valid(_coach):
		_show_next_coach()


var _coach_queue: Array = []  # [ключ, текст]
var _coach_key: String = ""


## Подсказка про действие, которое игрок уже сделал, больше не нужна: закрыть (или убрать из очереди).
func dismiss_coach(key: String) -> void:
	_coach_queue = _coach_queue.filter(func(e: Array) -> bool: return e[0] != key)
	if _coach_key == key and _coach != null and is_instance_valid(_coach):
		_close_coach()


func _close_coach() -> void:
	if _coach != null and is_instance_valid(_coach):
		_coach.queue_free()
	_coach = null
	_coach_key = ""
	_show_next_coach()


func _show_next_coach() -> void:
	if _coach_queue.is_empty():
		return
	var e: Array = _coach_queue.pop_front()
	_coach_key = e[0]
	var text: String = e[1]
	_coach = PanelContainer.new()
	_coach.mouse_filter = Control.MOUSE_FILTER_IGNORE  # мышь ловит только кнопка: бросок можно тянуть и поверх подсказки
	_coach.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.06, 0.1, 0.9), Color(0.45, 0.8, 1.0), 2, 10, 10))
	_place_coach()
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	_coach.add_child(vb)
	var head := VisualUtil.label("Подсказка", 13)
	head.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	vb.add_child(head)
	var l := VisualUtil.label(text, 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A slightly wider text column reduces the height of long instructions,
	# leaving more of the playing field visible while the player reads them.
	l.custom_minimum_size = Vector2(300, 0)
	vb.add_child(l)
	var b := Button.new()
	b.text = "Ясно (Enter)" if _coach_queue.is_empty() else "Далее (Enter) · ещё %d" % _coach_queue.size()
	b.custom_minimum_size = Vector2(110, 30)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	var wr: WeakRef = weakref(_coach)
	b.pressed.connect(func() -> void:
		if wr.get_ref() != null:
			_close_coach())
	vb.add_child(b)
	add_child(_coach)


func set_phase(phase: int) -> void:
	_build()
	_phase = phase
	_update_phase_text()
	_update_turn_text()


func _update_phase_text() -> void:
	var titles := {MatchController.Phase.SETUP: "КАРТА ВОРОТ", MatchController.Phase.AWAIT_THROW: "ВЫБОР СУЩЕСТВА",
		MatchController.Phase.AWAIT_LANDING: "ВЫБОР ЦЕЛИ", MatchController.Phase.AFTER_LANDING: "ПРИКРЕПЛЕНИЕ",
		MatchController.Phase.ABILITY_WINDOW: "ОБМЕН СПОСОБНОСТЯМИ", MatchController.Phase.RESOLVING: "ИТОГ БОЯ"}
	_phase_label.text = titles.get(_phase, "")
	if _battle and _phase not in [MatchController.Phase.ABILITY_WINDOW, MatchController.Phase.RESOLVING]:
		_phase_label.text = "НАЧАЛО БОЯ"
	if _final_round:
		_phase_label.text = "ФИНАЛЬНЫЙ БОЙ" + (" · " + _phase_label.text if not _phase_label.text.is_empty() else "")
