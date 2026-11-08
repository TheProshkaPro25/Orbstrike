class_name OpponentPanel
extends PanelContainer
## Main supplies public identity, then explicitly opens a reveal or battle context.
const PORTRAIT := preload("res://scenes/ui/creature_portrait.gd")
const DEVICE := preload("res://scenes/ui/device_settings.gd")
const MOTION := preload("res://scenes/ui/device_motion.gd")
const INK := UiTheme.DEVICE_INK
const BORDER := UiTheme.DEVICE_DIM
const CYAN := UiTheme.DEVICE_ACCENT
const REVEAL_SECONDS := 2.2

var _portrait: CreaturePortrait
var _name: Label
var _element: Label
var _power: Label
var _definition: CreatureDef
var _uid := -1
var _current_power := -1
var _compact := false
var player_side := 1
var _context_mode := ""
var _context_deadline_usec := 0
var _context_timer: Timer
var _shown_uid := -1
var _content: VBoxContainer
var _portrait_row: HBoxContainer
var _identity: VBoxContainer
var _tween: Tween
var _power_tween: Tween
var _accent_tween: Tween
var _frame_style: StyleBoxFlat
var _base_position := Vector2.ZERO


func _init() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	hide()
	_frame_style = UiTheme.box(INK, BORDER, 1, 3, 6)
	_frame_style.border_width_top = 3
	add_theme_stylebox_override("panel", _frame_style)
	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("separation", 4)
	add_child(_content)
	_portrait_row = HBoxContainer.new()
	_portrait_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_row.add_theme_constant_override("separation", 4)
	_portrait_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_portrait_row)
	_portrait = PORTRAIT.new()
	_portrait.name = "ResidentCreaturePortrait"
	_portrait.custom_minimum_size.x = 72
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait_row.add_child(_portrait)
	_identity = VBoxContainer.new()
	_identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_identity.alignment = BoxContainer.ALIGNMENT_CENTER
	_identity.add_theme_constant_override("separation", 2)
	_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_portrait_row.add_child(_identity)
	_name = _label("", 14)
	_name.name = "PublicOpponentName"
	_identity.add_child(_name)
	_element = _label("", 14)
	_element.name = "PublicOpponentElement"
	_element.add_theme_color_override("font_color", CYAN)
	_identity.add_child(_element)
	_power = _label("", 28)
	_power.name = "PublicOpponentPower"
	_power.add_theme_color_override("font_color", CYAN)
	_content.add_child(_power)
	_context_timer = Timer.new()
	_context_timer.one_shot = true
	_context_timer.ignore_time_scale = true
	_context_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_context_timer.timeout.connect(_context_timeout)
	add_child(_context_timer)


func _enter_tree() -> void:
	if not get_viewport().size_changed.is_connected(_layout): get_viewport().size_changed.connect(_layout)
	if not DEVICE.events().changed.is_connected(_style_changed): DEVICE.events().changed.connect(_style_changed)
	if not DEVICE.events().motion_changed.is_connected(_motion_changed): DEVICE.events().motion_changed.connect(_motion_changed)
	_resume.call_deferred()


func _ready() -> void:
	visibility_changed.connect(_visibility_changed)
	_layout()
	_apply_visibility()


func _resume() -> void:
	if not is_inside_tree(): return
	_layout()
	_apply_visibility()


## Cache only: receiving an identity must never open an out-of-context card.
func present(definition: CreatureDef, uid: int, power: int, _label_text: String = "") -> void:
	if definition == null or uid < 0 or power < 0:
		show_unknown()
		return
	var changed := _uid != uid or _definition == null or _definition.id != definition.id
	_definition = definition
	_uid = uid
	_portrait.set_definition(definition, uid)
	_name.text = definition.display_name.trim_suffix(" " + str(GameData.ATTR_GENITIVE[definition.attribute]))
	_element.text = Attr.display_name(definition.attribute)
	if changed:
		_set_power_immediate(power)
	else:
		set_power(power)


func show_context(mode: String = "reveal") -> void:
	if not _valid_public() or mode not in ["reveal", "battle"]:
		hide_context()
		return
	if _context_mode != mode or mode == "reveal":
		_settle()
		if mode == "reveal": _shown_uid = -1
	_context_mode = mode
	_context_timer.stop()
	_context_deadline_usec = 0
	if mode == "reveal":
		_context_deadline_usec = Time.get_ticks_usec() + int(REVEAL_SECONDS * 1000000)
		_context_timer.start(REVEAL_SECONDS - 0.18)
	_apply_visibility(true)


func hide_context() -> void:
	_context_mode = ""
	_context_deadline_usec = 0
	_context_timer.stop()
	_shown_uid = -1
	_settle()
	hide()
	_portrait.stop()


func show_unknown() -> void:
	hide_context()
	_definition = null
	_uid = -1
	_current_power = -1
	_portrait.reset()
	_name.text = ""
	_element.text = ""
	_power.text = ""


func reset() -> void:
	show_unknown()


## Called before Main returns resident actors to the catalog.
func stop() -> void:
	hide_context()


func bind_actor(ball: CreatureBall) -> void:
	_portrait.bind_actor(ball)


## Same public card layout for both sides; no ownership or roster information is inferred here.
func configure_side(side: int) -> void:
	player_side = clampi(side, 0, 1)
	if is_inside_tree(): _layout()


## Suppress the whole card during a right-hand prompt without pausing its deadline.
func set_compact(value: bool) -> void:
	if _compact == value: return
	_compact = value
	_settle()
	_apply_visibility()


func set_power(value: int) -> void:
	if _definition == null or value == _current_power: return
	var previous := _current_power
	_current_power = value
	_kill(_power_tween)
	_power_tween = null
	if not _animate() or previous < 0:
		_set_power_immediate(value)
		return
	_power.pivot_offset = _power.size * 0.5
	_power_tween = create_tween().set_ignore_time_scale(true).set_parallel(true)
	_power_tween.tween_method(func(number: float) -> void: _power.text = "%d G" % roundi(number), float(previous), float(value), 0.35)
	_power_tween.tween_method(func(progress: float) -> void:
		_power.scale = Vector2.ONE * (1.0 + 0.12 * sin(PI * progress))
		_power.modulate = Color.WHITE * (1.0 + 0.45 * (1.0 - progress))
		_power.modulate.a = 1.0, 0.0, 1.0, 0.35)
	_play_motion("power", CYAN)


func feedback(kind: String, attribute: int = -1) -> void:
	if not _animate():
		_settle()
		return
	_kill(_accent_tween)
	_frame_style = get_theme_stylebox("panel") as StyleBoxFlat
	var accent := VisualUtil.attr_color(attribute).lightened(0.28) if attribute >= 0 and attribute < Attr.COUNT else CYAN
	if kind in ["turn", "activation", "ability", "power", "appearance", "swap"]:
		_frame_style.border_color = accent
		_accent_tween = create_tween().set_ignore_time_scale(true)
		_accent_tween.tween_property(_frame_style, "border_color", BORDER, 0.35)
		_play_motion("activation" if kind == "ability" else kind, accent)


func _valid_public() -> bool:
	return _definition != null and _uid >= 0 and _current_power >= 0


func _context_active() -> bool:
	return _valid_public() and not _context_mode.is_empty() and (_context_deadline_usec == 0 or Time.get_ticks_usec() < _context_deadline_usec)


func _context_timeout() -> void:
	if _context_mode != "reveal": return
	var remaining := float(_context_deadline_usec - Time.get_ticks_usec()) / 1000000.0
	if remaining > 0.001:
		_context_timer.start(remaining)
		if remaining <= 0.20 and _animate():
			_kill(_tween)
			_tween = create_tween().set_ignore_time_scale(true)
			_tween.tween_property(self, "modulate:a", 0.0, remaining)
	else:
		hide_context()


func _apply_visibility(animate: bool = false) -> void:
	if not _context_mode.is_empty() and not _context_active():
		hide_context()
		return
	var should_show := _context_active() and not _compact and DEVICE.is_device() and is_inside_tree()
	var newly_shown := should_show and (not visible or _shown_uid != _uid)
	visible = should_show
	if should_show:
		_portrait._sync()
		if newly_shown and animate:
			_appear()
			_play_motion("scan", CYAN)
		_shown_uid = _uid
	else:
		_settle()
		_portrait._deactivate()


func _set_power_immediate(value: int) -> void:
	_kill(_power_tween)
	_power_tween = null
	_current_power = value
	_power.text = "%d G" % value
	_power.modulate = Color.WHITE
	_power.scale = Vector2.ONE


func _appear() -> void:
	_settle()
	if not _animate(): return
	modulate.a = 0.0
	position = _base_position + Vector2(-12 if player_side == 0 else 12, 0)
	_tween = create_tween().set_ignore_time_scale(true).set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.25)
	_tween.tween_property(self, "position", _base_position, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _animate() -> bool:
	return is_inside_tree() and is_visible_in_tree() and _context_active() and DEVICE.is_device() and not DEVICE.reduce_motion()


## Stable occupied lane for neighbouring HUD controls, independent of entrance Tween.
func get_settled_global_rect() -> Rect2:
	var parent_canvas := get_parent() as CanvasItem
	if parent_canvas == null: return Rect2(_base_position, size)
	return parent_canvas.get_global_transform_with_canvas() * Rect2(_base_position, size)


func _layout() -> void:
	_settle()
	var viewport := get_viewport_rect().size
	var width := 156.0
	var height := 156.0
	_base_position = Vector2(14 if player_side == 0 else viewport.x - width - 14, 110)
	var text_width := width - 12.0
	_content.size.x = text_width
	_portrait_row.size.x = text_width
	var identity_width := text_width - 72.0 - 4.0
	_identity.size.x = identity_width
	for label in [_name, _element]:
		label.custom_minimum_size.x = identity_width
		label.size.x = identity_width
	_power.custom_minimum_size.x = text_width
	_power.size.x = text_width
	custom_minimum_size = Vector2(width, height)
	size = Vector2(width, height)
	position = _base_position


func _settle() -> void:
	MOTION.stop_on(_portrait)
	MOTION.stop_on(_power)
	MOTION.stop_on(self)
	_kill(_tween)
	_kill(_power_tween)
	_kill(_accent_tween)
	_tween = null
	_power_tween = null
	_accent_tween = null
	modulate = Color.WHITE
	_power.modulate = Color.WHITE
	_power.scale = Vector2.ONE
	if _current_power >= 0 and _definition != null:
		_power.text = "%d G" % _current_power
	_frame_style = get_theme_stylebox("panel") as StyleBoxFlat
	_frame_style.border_color = BORDER
	if is_inside_tree(): position = _base_position


func _visibility_changed() -> void:
	if not is_visible_in_tree():
		_settle()
		_portrait._deactivate()


func _style_changed(_style: int) -> void:
	_settle()
	_apply_visibility()
	_layout.call_deferred()


func _motion_changed(reduced: bool) -> void:
	if reduced: _settle()


func _play_motion(kind: String, color: Color) -> void:
	if not _animate(): return
	_start_motion.call_deferred(kind, color, _uid, _context_mode)


func _start_motion(kind: String, color: Color, uid: int, context: String) -> void:
	if not _animate() or uid != _uid or context != _context_mode: return
	var target: Control = _portrait if kind == "scan" else (_power if kind == "power" else self)
	MOTION.play_on(target, kind, color)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid(): tween.kill()


func _exit_tree() -> void:
	hide_context()
	if get_viewport() != null and get_viewport().size_changed.is_connected(_layout): get_viewport().size_changed.disconnect(_layout)
	if DEVICE.events().changed.is_connected(_style_changed): DEVICE.events().changed.disconnect(_style_changed)
	if DEVICE.events().motion_changed.is_connected(_motion_changed): DEVICE.events().motion_changed.disconnect(_motion_changed)
