class_name BattleHud
extends Control
## Подача боя как в аниме: чёрные полосы сверху и снизу, две скошенные плашки бойцов
## (имя, стихия, сила с бегущим счётчиком) и «VS» по центру. Итог: победитель вспыхивает, проигравший гаснет.

const BAR_H := 64.0

var _top: ColorRect
var _bot: ColorRect
var _plates: Array[PanelContainer] = []
var _plate_contents: Array[VBoxContainer] = []
var _plate_accents: Array[Color] = [Color(0.5,0.75,1.0),Color(1.0,0.55,0.5)]
var _names: Array[Label] = []
var _attrs: Array[Label] = []
var _powers: Array[Label] = []
var _counts: Array[Label] = []        # «СПОСОБНОСТИ ●●○ 2/3» под силой (лимит карт на бой)
var _shown: Array[float] = [0.0, 0.0]
var _vs: Label
var _target: Array[int] = [0, 0]     # последние заданные силы (для всплывающих +/−)
var _chain: HFlowContainer            # лента карт боя: «Пожирающий жар → Волчья хватка → ПАС»
var _chain_state: Array = []
var _chain_width := 0.0
var _chain_turn := -1
var _chain_counts: Array = []
var _chain_blocks: Array = []
var _chain_help: Control
var _help_chip: PlayedCardChip
var _help_wait := 0.0
var _help_lost := 0.0
var _mouse_position := Vector2.ZERO
var _keyboard_help := false
var _entrance_tween: Tween
var _power_tweens: Array[Tween] = [null, null]
var _feedback_tweens: Array[Tween] = []
var _floating_numbers: Array[Label] = []
var _resolved := false
var _winner_side := -1
## Battle side represented by the external opponent panel; -1 keeps both plates.
var opponent_side: int = -1
## Компактные панели принадлежат основному HUD; ссылки индексируются стороной боя.
var _power_anchors: Array[Control] = [null, null]


## Сыгранная карта остаётся читаемой, но не становится игровым действием.
class PlayedCardChip extends PanelContainer:
	var help: Array = []
	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
	func _draw() -> void:
		if has_focus():
			draw_style_box(get_theme_stylebox("focus", "Button"), Rect2(Vector2.ZERO, size))
	func _gui_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"):
			release_focus()
			accept_event()
	func _has_point(point: Vector2) -> bool:
		# Вся плашка — одна цель, включая поля и скруглённые углы рамки.
		return Rect2(Vector2.ZERO, size).has_point(point)


var _open := false
var _built := false


func _ready() -> void:
	_build()
	_mouse_position = get_viewport().get_mouse_position()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_position = event.position
		_keyboard_help = false


func _process(delta: float) -> void:
	if not _open or not _chain.visible:
		_clear_chain_help()
		return
	var hovered := get_viewport().gui_get_hovered_control()
	var focused := get_viewport().gui_get_focus_owner()
	if _keyboard_help and focused is PlayedCardChip and focused.get_parent() == _chain:
		hovered = focused
	if hovered is PlayedCardChip and hovered.get_parent() == _chain and not hovered.help.is_empty():
		_help_lost = 0.0
		if hovered != _help_chip:
			_clear_chain_help()
			_help_chip = hovered
		_help_wait += delta
		if _chain_help == null and _help_wait >= .3:
			# Только прямоугольник читаемой карты закрывает hover лежащего
			# под ней UI, иначе его подсказка возникает поверх раскрытия.
			_chain_help = PanelContainer.new()
			_chain_help.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			_chain_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_chain_help.add_child(UiTheme.help_panel(_help_chip.help))
			_chain_help.z_index = 100
			add_child(_chain_help)
		if _chain_help != null:
			_place_chain_help()
	else:
		_help_lost += delta
		if _help_lost > .14: _clear_chain_help()


func _clear_chain_help() -> void:
	if is_instance_valid(_chain_help):
		_chain_help.queue_free()
	_chain_help = null
	_help_chip = null
	_help_wait = 0.0
	_help_lost = 0.0


func _exit_tree() -> void:
	_cancel_entrance()
	_stop_power_counters()
	_stop_feedback()
	_clear_chain_help()


func _place_chain_help() -> void:
	var rect := _help_chip.get_global_rect()
	var sz := _chain_help.get_combined_minimum_size()
	var vp := get_viewport_rect().size
	# Штатный PopupPanel при малой высоте сдвигался поверх собственной
	# надписи. Позиция привязана ко всей плашке, а не к движущемуся курсору.
	var x := rect.end.x + 10.0
	if x + sz.x > vp.x - 8.0: x = rect.position.x - sz.x - 10.0
	_chain_help.position = Vector2(clampf(x, 8.0, vp.x - sz.x - 8.0), clampf(rect.get_center().y - sz.y * .5, 8.0, maxf(8.0, vp.y - sz.y - 8.0)))


func _build() -> void:
	if _built:
		return
	_built = true
	VisualUtil.full_rect_ignore(self)
	theme = UiTheme.get_theme()
	_top = _bar(true)
	_bot = _bar(false)
	for side in range(2):
		var p := PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vb := VBoxContainer.new()
		_plate_contents.append(vb)
		vb.add_theme_constant_override("separation", -4)
		p.add_child(vb)
		var n := VisualUtil.label("", 24)
		var a := VisualUtil.label("", 14)
		var pw := VisualUtil.label("0", 46)
		pw.add_theme_color_override("font_color", UiTheme.GOLD)
		pw.add_theme_constant_override("outline_size", 10)
		var cn := VisualUtil.label("", 15)
		cn.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		cn.custom_minimum_size = Vector2(300, 0)  # ширина не скачет от «ПАС»/«▶»
		for l in [n, a, pw, cn]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			vb.add_child(l)
		_counts.append(cn)
		add_child(p)
		_plates.append(p)
		_names.append(n)
		_attrs.append(a)
		_powers.append(pw)
		p.visible = false
	_vs = VisualUtil.label("VS", 64)
	_vs.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	_vs.add_theme_constant_override("outline_size", 14)
	_vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs.visible = false
	add_child(_vs)
	_chain = HFlowContainer.new()
	_chain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chain.add_theme_constant_override("h_separation", 6)
	_chain.add_theme_constant_override("v_separation", 4)
	_chain.alignment = FlowContainer.ALIGNMENT_CENTER
	_chain.anchor_left = 0.0
	_chain.anchor_right = 1.0
	_chain.offset_top = BAR_H + 170.0
	_chain.offset_bottom = BAR_H + 208.0
	add_child(_chain)
	get_viewport().size_changed.connect(_resize_chain)
	UiTheme.apply_device_frame(self, "БОЕВОЙ КОНТУР", false)
	DeviceSettings.events().changed.connect(_device_style_changed)
	DeviceSettings.events().motion_changed.connect(_motion_changed)


func _bar(top: bool) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0.92)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = 0.0 if top else 1.0
	r.anchor_bottom = 0.0 if top else 1.0
	r.offset_top = -BAR_H if top else 0.0
	r.offset_bottom = 0.0 if top else BAR_H
	add_child(r)
	return r


func _device_style_changed(_style: int) -> void:
	_top.color = Color(0.01, 0.045, 0.065, 0.94) if DeviceSettings.is_device() else Color(0, 0, 0, 0.92)
	_bot.color = _top.color
	_vs.text = "СХВАТКА" if DeviceSettings.is_device() else "VS"
	_vs.add_theme_font_size_override("font_size", 27 if DeviceSettings.is_device() else 64)
	for power in _powers:
		power.add_theme_color_override("font_color", UiTheme.accent())
	for side in range(_plates.size()):
		_plates[side].add_theme_stylebox_override("panel", _plate_style(_plate_accents[side], side))
		_align_plate(side)
	_cancel_entrance()
	_stop_power_counters()
	_stop_feedback()
	if _open:
		_settle_open_layout()
	else:
		_hide_layout()
	if _chain_state.size() == 4:
		set_chain(_chain_state[0], _chain_state[1], _chain_turn, _chain_state[2], _chain_counts, _chain_blocks)


## Call only after the external opponent panel has usable public battle data.
## The setting is presentation only; both sides retain their real power/card state.
func set_opponent_side(side: int) -> void:
	var next := side if side in [0,1] else -1
	if next == opponent_side: return
	opponent_side = next
	if not _built or not DeviceSettings.is_device(): return
	_cancel_entrance()
	_stop_power_counters()
	_stop_feedback()
	if _open: _settle_open_layout()


## own/enemy — публичные панели основного HUD; opponent_battle_side:0 атакующий,1 защитник.
## null,null снимает привязки. Повторный вызов не создаёт эффекты изменения силы.
func set_external_panels(own: Control, enemy: Control, opponent_battle_side: int) -> void:
	var next_side := opponent_battle_side if opponent_battle_side in [0,1] else -1
	var anchors: Array[Control] = [null, null]
	if next_side >= 0:
		anchors[next_side] = enemy
		anchors[1 - next_side] = own
	if anchors == _power_anchors and next_side == opponent_side:
		if _built: _sync_external_counts()
		return
	_watch_power_anchors(false)
	_power_anchors = anchors
	_watch_power_anchors(true)
	opponent_side = next_side
	if not _built: return
	_cancel_entrance()
	_stop_power_counters()
	_stop_feedback()
	if _open: _settle_open_layout()
	else: _sync_external_counts()


func _watch_power_anchors(connect_signals: bool) -> void:
	for anchor in _power_anchors:
		if not is_instance_valid(anchor): continue
		for event in [anchor.visibility_changed, anchor.item_rect_changed]:
			if connect_signals and not event.is_connected(_sync_external_counts):
				event.connect(_sync_external_counts)
			elif not connect_signals and event.is_connected(_sync_external_counts):
				event.disconnect(_sync_external_counts)


func _has_power_anchor(side: int) -> bool:
	return DeviceSettings.is_device() and is_instance_valid(_power_anchors[side])


func _has_external_opponent(side: int) -> bool:
	return _has_power_anchor(side) or (DeviceSettings.is_device() and opponent_side == side)


func _power_anchor_rect(side: int) -> Rect2:
	var anchor: Control = _power_anchors[side] if _has_power_anchor(side) else _plates[side]
	var relative := get_global_transform_with_canvas().affine_inverse() * anchor.get_global_transform_with_canvas()
	return relative * Rect2(Vector2.ZERO, anchor.size)


## Счётчики остаются видимыми после скрытия больших плашек; classic возвращает их в VBox.
func _sync_external_counts() -> void:
	for side in range(_counts.size()):
		var count := _counts[side]
		var external := _has_power_anchor(side)
		var parent: Node = self if external else _plate_contents[side]
		if count.get_parent() != parent:
			count.reparent(parent)
		count.custom_minimum_size.x = 0.0 if external else 300.0
		count.add_theme_font_size_override("font_size", 14 if external else 15)
		count.visible = _open and _power_anchors[side].is_visible_in_tree() if external else true
		if external:
			var rect := _power_anchor_rect(side)
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			count.size = Vector2(rect.size.x, count.get_minimum_size().y)
			count.position = Vector2(rect.position.x, rect.end.y + 4.0)
			count.z_index = 2
		else:
			count.z_index = 0
	_layout_chain()


## The compact panels and their counters own the side lanes. Keep this contract
## even while a contextual portrait is hidden, so the hand does not jump on reveal.
func _layout_chain() -> void:
	if _chain == null: return
	var left := 14.0
	var right := get_viewport_rect().size.x - 14.0
	if DeviceSettings.is_device():
		for side in range(2):
			if not _has_power_anchor(side): continue
			var rect := _power_anchor_rect(side)
			if _power_anchors[side].has_method("get_settled_global_rect"):
				rect = get_global_transform_with_canvas().affine_inverse() * _power_anchors[side].call("get_settled_global_rect")
			if rect.get_center().x < get_viewport_rect().size.x * .5:
				left = maxf(left, rect.end.x + 14.0)
			else:
				right = minf(right, rect.position.x - 14.0)
	_chain.offset_left = left
	_chain.offset_right = right - get_viewport_rect().size.x


func _plate_slot(side: int) -> int:
	# Own battle data stays on the left when the external panel occupies the right.
	if DeviceSettings.is_device() and opponent_side in [0,1]:
		return 1 if side == opponent_side else 0
	return side


func _align_plate(side: int) -> void:
	var alignment := HORIZONTAL_ALIGNMENT_LEFT if _plate_slot(side) == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	for label in [_names[side],_attrs[side],_powers[side],_counts[side]]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if label == _counts[side] and _has_power_anchor(side) else alignment


func _motion_changed(_reduced: bool) -> void:
	if not DeviceSettings.is_device(): return
	_cancel_entrance()
	_stop_power_counters()
	_stop_feedback()
	if _open:
		_settle_open_layout()
	else:
		_hide_layout()


func _cancel_entrance() -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_entrance_tween = null


func _new_entrance_tween() -> Tween:
	_cancel_entrance()
	var tween := create_tween().set_parallel(true)
	_entrance_tween = tween
	tween.finished.connect(func() -> void:
		if _entrance_tween == tween: _entrance_tween = null)
	return tween


func _stop_power_counters() -> void:
	for side in range(2):
		if _power_tweens[side] != null and _power_tweens[side].is_valid():
			_power_tweens[side].kill()
		_power_tweens[side] = null
		if side < _powers.size(): _set_shown(_target[side], side)


func _track_feedback(tween: Tween) -> void:
	_feedback_tweens.append(tween)
	tween.finished.connect(func() -> void: _feedback_tweens.erase(tween))


func _stop_feedback(keep_device_power: bool = false) -> void:
	var preserved_tweens: Array[Tween] = []
	for tween in _feedback_tweens:
		if keep_device_power and tween.is_valid() and tween.get_meta("device_power_delta", false):
			preserved_tweens.append(tween)
			continue
		if tween.is_valid(): tween.kill()
	_feedback_tweens = preserved_tweens
	var preserved_numbers: Array[Label] = []
	for number in _floating_numbers:
		if keep_device_power and is_instance_valid(number) and number.has_meta("battle_side"):
			preserved_numbers.append(number)
			continue
		if is_instance_valid(number): number.queue_free()
	_floating_numbers = preserved_numbers
	for label in _powers + _counts:
		label.scale = Vector2.ONE
		label.modulate = Color.WHITE
	for plate in _plates:
		plate.scale = Vector2.ONE
	if _chain != null:
		for chip in _chain.get_children():
			if chip is Control: chip.modulate = Color.WHITE


func _set_bar_positions(opened: bool) -> void:
	_top.offset_top = 0.0 if opened else -BAR_H
	_top.offset_bottom = BAR_H if opened else 0.0
	_bot.offset_top = -BAR_H if opened else 0.0
	_bot.offset_bottom = 0.0 if opened else BAR_H
	_top.modulate = Color.WHITE
	_bot.modulate = Color.WHITE


func _settle_open_layout() -> void:
	_set_bar_positions(true)
	_sync_external_counts()
	var vp := get_viewport_rect().size
	for side in range(2):
		var plate := _plates[side]
		plate.reset_size()
		plate.position = Vector2(30.0 if _plate_slot(side) == 0 else vp.x-plate.size.x-30.0, BAR_H+18.0)
		plate.scale = Vector2.ONE
		plate.visible = not _has_external_opponent(side)
		_align_plate(side)
		if not _resolved:
			plate.modulate = Color.WHITE
		elif side == _winner_side:
			plate.modulate = Color.WHITE
		else:
			plate.modulate = Color(0.55,0.55,0.6,0.7) if _winner_side < 0 and not DeviceSettings.is_device() else Color(0.45,0.45,0.5,0.6)
	_vs.size = Vector2(200,80)
	_vs.pivot_offset = _vs.size*.5
	_vs.position = Vector2(vp.x*.5-100.0, BAR_H+22.0)
	_vs.scale = Vector2.ONE
	_vs.modulate = Color.WHITE
	_vs.visible = not _resolved


func _hide_layout() -> void:
	_set_bar_positions(false)
	_sync_external_counts()
	for plate in _plates:
		plate.visible = false
		plate.modulate = Color.WHITE
		plate.scale = Vector2.ONE
	_vs.visible = false
	_vs.modulate = Color.WHITE
	_vs.scale = Vector2.ONE


func _open_device(names: Array, attrs: Array, powers: Array, momentum: Array) -> void:
	_open = true
	_resolved = false
	_target = [int(powers[0]), int(powers[1])]
	set_chain([], [false,false])
	for side in range(2):
		var color: Color = VisualUtil.attr_color(int(attrs[side]))
		_plate_accents[side] = color
		_plates[side].add_theme_stylebox_override("panel", _plate_style(color,side))
		_names[side].text = str(names[side])
		_attrs[side].text = ("АТАКА · " if side == 0 else "ЗАЩИТА · ") + VisualUtil.attr_name(int(attrs[side])).to_upper()
		if momentum.size() == 2 and int(momentum[side]) > 0:
			_attrs[side].text += "  ·  НАТИСК +%d" % int(momentum[side])
		_attrs[side].add_theme_color_override("font_color", color.lightened(.35))
		_set_shown(_target[side],side)
	_settle_open_layout()
	if DeviceSettings.reduce_motion(): return
	var tween := _new_entrance_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for side in range(2):
		var plate := _plates[side]
		if _has_external_opponent(side): continue
		var destination := plate.position
		plate.position.x += -16.0 if _plate_slot(side) == 0 else 16.0
		plate.modulate.a = 0.0
		tween.tween_property(plate,"position",destination,.28)
		tween.tween_property(plate,"modulate:a",1.0,.28)
	var title_position := _vs.position
	_vs.position.y += 12.0
	_vs.modulate.a = 0.0
	tween.tween_property(_vs,"position",title_position,.28)
	tween.tween_property(_vs,"modulate:a",1.0,.28)
	for bar in [_top,_bot]:
		bar.modulate.a = 0.0
		tween.tween_property(bar,"modulate:a",1.0,.28)


func _plate_style(c: Color, side: int) -> StyleBoxFlat:
	if DeviceSettings.is_device():
		var device := UiTheme.box(UiTheme.DEVICE_INK, UiTheme.DEVICE_DIM, 1, 3, 14)
		device.border_width_top = 3
		device.content_margin_left = 26
		device.content_margin_right = 26
		return device
	var sb := UiTheme.box(Color(0.03, 0.03, 0.05, 0.88), c, 0, 0, 14)
	sb.border_width_left = 6 if side == 0 else 0
	sb.border_width_right = 6 if side == 1 else 0
	sb.border_width_bottom = 2
	sb.skew = Vector2(-0.25 if side == 0 else 0.25, 0.0)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.shadow_color = Color(c.r, c.g, c.b, 0.35)
	sb.shadow_size = 12
	return sb


## Открыть подачу боя. Сторона 0 — атакующий (слева), 1 — защитник.
func open(names: Array, attrs: Array, powers: Array, momentum: Array = [0, 0]) -> void:
	_build()
	_device_style_changed(DeviceSettings.current())
	if DeviceSettings.is_device():
		_open_device(names,attrs,powers,momentum)
		return
	_open = true
	_resolved = false
	_target = [0, 0]
	set_chain([], [false, false])
	var vp := get_viewport_rect().size
	var tw := _new_entrance_tween()
	tw.tween_property(_top, "offset_top", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_top, "offset_bottom", BAR_H, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bot, "offset_top", -BAR_H, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bot, "offset_bottom", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for side in range(2):
		var c: Color = VisualUtil.attr_color(int(attrs[side]))
		_plate_accents[side] = c
		var p: PanelContainer = _plates[side]
		p.add_theme_stylebox_override("panel", _plate_style(c, side))
		p.modulate = Color.WHITE
		_names[side].text = str(names[side])
		_attrs[side].text = ("АТАКА · " if side == 0 else "ЗАЩИТА · ") + VisualUtil.attr_name(int(attrs[side])).to_upper()
		if momentum.size() == 2 and int(momentum[side]) > 0:
			_attrs[side].text += "  ·  НАТИСК +%d" % int(momentum[side])
		_attrs[side].add_theme_color_override("font_color", c.lightened(0.35))
		_shown[side] = 0.0
		_powers[side].text = "0"
		p.visible = true
		p.reset_size()
		var y: float = BAR_H + 18.0
		var x_in: float = 30.0 if side == 0 else vp.x - p.size.x - 30.0
		var x_out: float = -p.size.x - 40.0 if side == 0 else vp.x + 40.0
		p.position = Vector2(x_out, y)
		tw.tween_property(p, "position:x", x_in, 0.35).set_delay(0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_vs.visible = true
	_vs.size = Vector2(200, 80)
	_vs.pivot_offset = _vs.size * 0.5
	_vs.position = Vector2(vp.x * 0.5 - 100.0, BAR_H + 22.0)
	_vs.scale = Vector2(3, 3)
	_vs.modulate.a = 0.0
	tw.tween_property(_vs, "scale", Vector2.ONE, 0.3).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_vs, "modulate:a", 1.0, 0.2).set_delay(0.3)
	set_powers(powers)


## Сила бойцов: числа «бегут» к новым значениям, разница всплывает над плашкой (+120 / −80) с пружиной.
func set_powers(powers: Array) -> void:
	if not _open:
		return
	for side in range(2):
		var to: float = float(powers[side])
		var delta: int = int(to) - _target[side]
		if DeviceSettings.is_device() and delta == 0:
			continue
		if _power_tweens[side] != null and _power_tweens[side].is_valid():
			_power_tweens[side].kill()
		_power_tweens[side] = null
		if _has_external_opponent(side) or (DeviceSettings.is_device() and DeviceSettings.reduce_motion()):
			_set_shown(to,side)
		else:
			var tween := create_tween()
			_power_tweens[side] = tween
			tween.tween_method(_set_shown.bind(side), _shown[side], to, .24 if DeviceSettings.is_device() else .5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.finished.connect(func() -> void:
				if _power_tweens[side] == tween: _power_tweens[side] = null)
		var feedback_visible := not _has_power_anchor(side) or _power_anchors[side].is_visible_in_tree()
		if delta != 0 and (DeviceSettings.is_device() or _target[side] > 0) and feedback_visible:
			if DeviceSettings.is_device(): SoundFx.i().play_device_power(delta)
			if not _has_external_opponent(side):
				_pulse(_powers[side], Color(0.6, 1.0, 0.6) if delta > 0 else Color(1.0, 0.45, 0.4))
			_float_number(side, delta)
		_target[side] = int(to)


## Всплывающее число изменения силы: выскакивает с пружиной, плывёт вверх и гаснет.
func _float_number(side: int, delta: int) -> void:
	if DeviceSettings.is_device():
		_float_device_power(side, delta)
		return
	var p: PanelContainer = _plates[side]
	var l := VisualUtil.label(("+%d" if delta > 0 else "−%d") % absi(delta), 54)
	l.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55) if delta > 0 else Color(1.0, 0.4, 0.35))
	l.add_theme_constant_override("outline_size", 14)
	add_child(l)
	_floating_numbers.append(l)
	l.size = l.get_minimum_size()
	l.pivot_offset = l.size * 0.5
	var x: float = p.position.x + (p.size.x * 0.5 if side == 0 else p.size.x * 0.5) - l.size.x * 0.5
	var y: float = p.position.y + p.size.y + 4.0
	l.position = Vector2(x, y)
	l.scale = Vector2(0.2, 0.2)
	var tw := l.create_tween()
	_track_feedback(tw)
	tw.finished.connect(func() -> void: _floating_numbers.erase(l))
	tw.tween_property(l, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", y + 40.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


## Изменение реального итогового G; начальные силы задаются в open без этого вызова.
func _float_device_power(side: int, delta: int) -> void:
	if _has_power_anchor(side) and not _power_anchors[side].is_visible_in_tree(): return
	var label := VisualUtil.label(("+%d G" if delta > 0 else "−%d G") % absi(delta), 32)
	label.name = "PowerDelta" + str(side)
	label.set_meta("battle_side", side)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color(0.3, 0.96, 1.0) if delta > 0 else Color(1.0, 0.61, 0.24))
	label.add_theme_constant_override("outline_size", 6)
	label.z_index = 45
	add_child(label)
	label.size = label.get_minimum_size()
	label.pivot_offset = label.size * .5
	var rect := _power_anchor_rect(side)
	var below := _counts[side].size.y + 10.0 if _has_power_anchor(side) else 4.0
	var row := 0
	for previous in _floating_numbers:
		if is_instance_valid(previous) and int(previous.get_meta("battle_side", -1)) == side:
			row += 1
	var vp := get_viewport_rect().size
	label.position = Vector2(clampf(rect.get_center().x - label.size.x * .5, 8.0, maxf(8.0, vp.x - label.size.x - 8.0)), clampf(rect.end.y + below + (row % 3) * 36.0, 8.0, maxf(8.0, vp.y - label.size.y - 8.0)))
	_floating_numbers.append(label)
	var tween := label.create_tween()
	tween.set_meta("device_power_delta", true)
	_track_feedback(tween)
	tween.finished.connect(func() -> void: _floating_numbers.erase(label))
	if DeviceSettings.reduce_motion():
		tween.tween_interval(.9)
	else:
		label.scale = Vector2(.78, .78)
		tween.tween_property(label, "scale", Vector2.ONE, .14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_interval(.65)
		tween.tween_property(label, "modulate:a", 0.0, .25)
		tween.parallel().tween_property(label, "position:y", label.position.y - 10.0, .25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(label.queue_free)


## Лента карт боя по порядку (прикреплённые — первыми): plays — [[сторона, card_id], ...], passed — кто спасовал.
## Лента карт боя и счётчики «Способности N/3» на плашках. turn — чья очередь обмена (сторона, -1 — ничья).
func set_chain(plays: Array, passed: Array, turn: int = -1, cancelled: Array = [], ability_counts: Array = [], block_reasons: Array = []) -> void:
	_build()
	_layout_chain()
	_chain_turn = turn
	_chain_counts = ability_counts.duplicate()
	_chain_blocks = block_reasons.duplicate()
	var used: Array[int] = [0, 0]
	for pl in plays:
		used[int(pl[0])] += 1
	if ability_counts.size() == 2: used.assign(ability_counts)
	# Повторный сетевой снимок не пересоздаёт Control под мышью и его подсказку.
	var snapshot: Array = [plays, passed, cancelled, block_reasons]
	var width := _chain.size.x
	if snapshot != _chain_state or width != _chain_width:
		_clear_chain_help()
		_chain_state = snapshot.duplicate(true)
		_chain_width = width
		VisualUtil.clear_children(_chain)
		for pl in plays:
			var side: int = int(pl[0])
			var c: CardDef = CardDB.card(StringName(pl[1]))
			var inactive := cancelled.has(pl)
			var chip := _chip(("× " if inactive else "") + (c.display_name if c != null else str(pl[1])), side, inactive)
			if c != null:
				chip.help = UiTheme.card_help(c)
				chip.help[6] = ("Атакующий. " if side == 0 else "Защитник. ") + ("Карта отменена или подавлена в расчёте этого боя." if inactive else "Карта сыграна в этом бою.")
				# Собственное раскрытие сохраняет всю область текста доступной.
				chip.tooltip_text = ""
				chip.mouse_filter = Control.MOUSE_FILTER_STOP
			_chain.add_child(chip)
		for side in range(2):
			if side < passed.size() and bool(passed[side]):
				var reason := str(block_reasons[side]) if side < block_reasons.size() else ""
				var chip := _chip("АВТОПАС" if reason != "" else "ПАС", side, true)
				chip.tooltip_text = reason
				chip.help = ["АВТОПАС" if reason != "" else "ПАС", "Атакующий" if side == 0 else "Защитник", UiTheme.accent(), "", reason if reason != "" else "Сторона пропустила ответ. Если соперник сыграет карту, можно ответить снова.", "", ""]
				chip.mouse_filter = Control.MOUSE_FILTER_STOP
				_chain.add_child(chip)
	_chain.visible = _open and not _resolved and _chain.get_child_count() > 0
	for side in range(2):
		_set_count(side, used[side], side < passed.size() and bool(passed[side]), side == turn, str(block_reasons[side]) if side < block_reasons.size() else "")


func _resize_chain() -> void:
	if DeviceSettings.is_device():
		_cancel_entrance()
		_stop_power_counters()
		_stop_feedback()
		if _open: _settle_open_layout()
		else: _hide_layout()
	if _chain_state.size() == 4:
		set_chain(_chain_state[0], _chain_state[1], _chain_turn, _chain_state[2], _chain_counts, _chain_blocks)


## Счётчик карт стороны: закрашенные кружки — сыгранные (с прикреплёнными), «ПАС» — сторона вышла из обмена.
func _set_count(side: int, used: int, passed: bool, turn: bool, block_reason: String = "") -> void:
	var cap: int = MatchController.MAX_BATTLE_ABILITIES
	var dots := ""
	for i in range(cap):
		dots += "●" if i < used else "○"
	var t := "СПОСОБНОСТИ %s %d/%d" % [dots, mini(used, cap), cap]
	if _has_power_anchor(side):
		t = "%s %d/%d" % [dots, mini(used, cap), cap]
	if block_reason != "":
		t = "ЗАКРЫТО · %d/%d" % [mini(used, cap), cap] if _has_power_anchor(side) else "%d/%d · КАРТЫ ЗАКРЫТЫ" % [mini(used, cap), cap]
	elif passed:
		t += "  ·  ПАС"
	elif turn:
		t = t + " · ХОД" if _has_power_anchor(side) else (("▶ " + t) if side == 0 else (t + " ◀"))
	var l: Label = _counts[side]
	l.tooltip_text = block_reason
	l.mouse_filter = Control.MOUSE_FILTER_STOP if block_reason != "" else Control.MOUSE_FILTER_IGNORE
	var was: String = l.text
	l.text = t
	var c: Color = UiTheme.TEXT_DIM
	if turn and not passed:
		c = UiTheme.accent()
	elif used >= cap:
		c = Color(1.0, 0.75, 0.45)
	l.add_theme_color_override("font_color", c)
	_sync_external_counts()
	if was != "" and was != t and _open and not _has_external_opponent(side):
		_pulse(l, Color(1.4, 1.3, 1.0))


func _chip(text: String, side: int, dim: bool = false) -> PlayedCardChip:
	var c: Color = Color(0.5, 0.75, 1.0) if side == 0 else Color(1.0, 0.55, 0.5)
	if dim:
		c = c.darkened(0.35)
	var pc := PlayedCardChip.new()
	pc.focus_entered.connect(func() -> void:
		_keyboard_help = true
		_clear_chain_help())
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.custom_minimum_size.y = 36.0
	pc.add_theme_stylebox_override("panel", UiTheme.box(Color(c.r * 0.15, c.g * 0.15, c.b * 0.15, 0.9), c, 2, 6, 5))
	var l := VisualUtil.label(text, 16)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = minf(180.0, get_viewport_rect().size.x / 6.0 - 26.0) if text != "ПАС" else 40.0
	l.add_theme_color_override("font_color", c.lightened(0.4))
	pc.add_child(l)
	# Появление не двигает и не сжимает область наведения под курсором.
	if not (DeviceSettings.is_device() and DeviceSettings.reduce_motion()):
		pc.modulate.a = 0.0
		var tween := pc.create_tween()
		_track_feedback(tween)
		tween.tween_property(pc, "modulate:a", 1.0, 0.15 if DeviceSettings.is_device() else 0.2)
	return pc


func _set_shown(v: float, side: int) -> void:
	_shown[side] = v
	_powers[side].text = str(int(round(v)))


func _pulse(l: Label, c: Color) -> void:
	if DeviceSettings.is_device() and DeviceSettings.reduce_motion(): return
	l.pivot_offset = l.size * 0.5
	var tw := l.create_tween()
	_track_feedback(tw)
	if DeviceSettings.is_device():
		tw.tween_property(l,"modulate",c,.08)
		tw.tween_property(l,"modulate",Color.WHITE,.14)
		return
	tw.tween_property(l, "modulate", c, 0.1)
	tw.parallel().tween_property(l, "scale", Vector2(1.25, 1.25), 0.1)
	tw.tween_property(l, "modulate", Color.WHITE, 0.35)
	tw.parallel().tween_property(l, "scale", Vector2.ONE, 0.35)


## Итог: плашка победителя вспыхивает, проигравшего гаснет.
## winner_side -1 — победителя нет (бой прерван или выбыли оба): обе плашки гаснут.
func resolve(winner_side: int) -> void:
	if not _open:
		return
	_cancel_entrance()
	_stop_power_counters()
	_stop_feedback(DeviceSettings.is_device())
	_settle_open_layout()
	_resolved = true
	_winner_side = winner_side
	if DeviceSettings.is_device():
		_vs.visible = false
		_chain.visible = false
		for side in range(2):
			if _has_external_opponent(side): continue
			var color := Color.WHITE if side == winner_side else Color(0.45,0.45,0.5,0.6)
			if DeviceSettings.reduce_motion():
				_plates[side].modulate = color
			else:
				var tween := create_tween()
				_track_feedback(tween)
				tween.tween_property(_plates[side],"modulate",color,.22)
		return
	if winner_side < 0:
		var tw0 := create_tween().set_parallel(true)
		_track_feedback(tw0)
		for pl in _plates:
			tw0.tween_property(pl, "modulate", Color(0.55, 0.55, 0.6, 0.7), 0.3)
		_vs.visible = false
		return
	var w: PanelContainer = _plates[winner_side]
	var l: PanelContainer = _plates[1 - winner_side]
	w.pivot_offset = w.size * 0.5
	var tw := create_tween().set_parallel(true)
	_track_feedback(tw)
	tw.tween_property(w, "scale", Vector2(1.12, 1.12), 0.15)
	tw.tween_property(w, "modulate", Color(1.6, 1.5, 1.2), 0.15)
	tw.tween_property(l, "modulate", Color(0.45, 0.45, 0.5, 0.6), 0.3)
	tw.chain().tween_property(w, "scale", Vector2.ONE, 0.25)
	tw.parallel().tween_property(w, "modulate", Color.WHITE, 0.25)
	_vs.visible = false
	_chain.visible = false


func close() -> void:
	if not _open:
		return
	_cancel_entrance()
	_stop_power_counters()
	_stop_feedback()
	_clear_chain_help()
	_open = false
	if DeviceSettings.is_device():
		_hide_layout()
		_chain.visible = false
		return
	var vp := get_viewport_rect().size
	var tw := _new_entrance_tween()
	tw.tween_property(_top, "offset_top", -BAR_H, 0.25)
	tw.tween_property(_top, "offset_bottom", 0.0, 0.25)
	tw.tween_property(_bot, "offset_top", 0.0, 0.25)
	tw.tween_property(_bot, "offset_bottom", BAR_H, 0.25)
	tw.tween_property(_plates[0], "position:x", -_plates[0].size.x - 40.0, 0.25)
	tw.tween_property(_plates[1], "position:x", vp.x + 40.0, 0.25)
	_vs.visible = false
	_chain.visible = false
