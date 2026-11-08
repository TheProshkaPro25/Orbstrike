class_name OrbButton
extends Button
## Шар существа: кружок цвета стихии с бликом, силой в центре и именем снизу (вместо карточной кнопки).
## Рисуется кодом (_draw): сфера из вложенных кругов, золотое кольцо, подсветка при наведении.

const R := 44.0

var uid: int = -1
var color: Color = Color(0.6, 0.6, 0.6)
var title: String = ""
var power: int = 0
var note: String = ""
var _hover := 0.0
var _tw: Tween
var _help: Array = []
var _focus_disclosure: CanvasLayer


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	custom_minimum_size = Vector2(118, 158)
	mouse_entered.connect(_set_hover.bind(1.0))
	mouse_exited.connect(_set_hover.bind(0.0))
	focus_entered.connect(_focus_changed.bind(true))
	focus_exited.connect(_focus_changed.bind(false))


## Заполнить из определения существа.
func for_creature(def: CreatureDef, p_uid: int, p_note: String = "") -> OrbButton:
	uid = p_uid
	color = VisualUtil.attr_color(def.attribute)
	title = def.display_name
	power = def.base_power
	note = p_note
	_help = UiTheme.creature_help(def)
	tooltip_text = "%s\n%s\n%s" % [_help[0], _help[1], _help[4]]
	pivot_offset = Vector2(custom_minimum_size.x * 0.5, 54.0)
	return self


func _set_hover(to: float) -> void:
	if has_focus(): to = 1.0
	if _tw != null:
		_tw.kill()
	if not is_inside_tree():
		_hover = to
		queue_redraw()
		return
	_tw = create_tween().set_parallel(true)
	_tw.tween_method(func(v: float) -> void:
		_hover = v
		queue_redraw(), _hover, to, 0.14)
	# Геометрия кнопки и подписи остаётся в своей колонке даже при фокусе.


func _focus_changed(on: bool) -> void:
	_set_hover(1.0 if on or is_hovered() else 0.0)
	queue_redraw()
	if is_instance_valid(_focus_disclosure): _focus_disclosure.queue_free()
	_focus_disclosure = null
	if on: _focus_disclosure = preload("res://scenes/ui/card_hover.gd").open_on(self, _help)


## Две полные строки: вид / стихия. Все 49 имён сохраняются без сокращения.
func name_layout() -> Dictionary:
	var words := title.split(" ", false, 1)
	var lines: PackedStringArray = words if words.size() > 1 else PackedStringArray([title])
	var font := get_theme_default_font()
	var fs := 17
	while fs > 13:
		var widest := 0.0
		for line in lines: widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if widest <= size.x - 12.0: break
		fs -= 1
	return {"lines": lines, "font_size": fs}


func _draw() -> void:
	var c := Vector2(size.x * 0.5, 54.0)
	# мягкое свечение
	for i in range(5):
		draw_circle(c, R + 16.0 - i * 3.0, Color(color.r, color.g, color.b, (0.05 + 0.04 * i) * (1.0 + _hover)))
	# сфера: вложенные круги от тёмного края к светлому ядру, сдвинутому к блику
	var hl := Vector2(-R * 0.28, -R * 0.32)
	for i in range(10):
		var t: float = float(i) / 9.0
		var rad: float = lerpf(R, R * 0.2, t)
		var col: Color = color.darkened(0.6).lerp(color.lightened(0.45), t)
		draw_circle(c + hl * t, rad, col)
	draw_circle(c + hl * 1.05, R * 0.2, Color(1, 1, 1, 0.45))
	draw_arc(c, R, 0.0, TAU, 56, UiTheme.GOLD if _hover > 0.5 else UiTheme.GOLD_DIM, 3.0 if _hover > 0.5 else 2.0, true)
	if has_focus():
		draw_style_box(UiTheme.box(Color.TRANSPARENT, Color(1.0, .95, .65), 3, 8, 0), Rect2(Vector2.ZERO, size))
	var font: Font = get_theme_default_font()
	# сила в центре
	var ps := str(power)
	var psz: Vector2 = font.get_string_size(ps, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
	draw_string_outline(font, c + Vector2(-psz.x * 0.5, 9.0), ps, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color(0, 0, 0, 0.8))
	draw_string(font, c + Vector2(-psz.x * 0.5, 9.0), ps, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	# имя
	var fitted := name_layout()
	var fs := int(fitted.font_size)
	var lines: PackedStringArray = fitted.lines
	for i in lines.size():
		var line := lines[i]
		var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2((size.x - width) * .5, 117.0 + i * 20.0)
		draw_string_outline(font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, .85))
		draw_string(font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)
	if note != "":
		var zsz: Vector2 = font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		draw_string(font, Vector2((size.x - zsz.x) * 0.5, 154.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT_DIM)
