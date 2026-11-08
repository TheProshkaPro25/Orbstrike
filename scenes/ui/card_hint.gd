extends PanelContainer
## Plain rule disclosure: bounded text, no nested CardView/material/tooltip lifecycle.
static var build_count := 0
var _title: Label
var _kind: Label
var _body: Label
var _scroll: ScrollContainer
var _footer: Label
var _viewport_size := Vector2.ZERO

func configure(lines: Array) -> Control:
	build_count += 1
	name = "CardHintPanel"
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.INK, lines[2], 1, 8, 10))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	add_child(column)
	_title = _label(str(lines[0]), 16, UiTheme.TEXT)
	_kind = _label(str(lines[1]), 12, lines[2])
	column.add_child(_title)
	column.add_child(_kind)
	_scroll = ScrollContainer.new()
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	column.add_child(_scroll)
	var body := str(lines[4])
	if lines.size() > 6 and not str(lines[6]).is_empty(): body += "\n\n" + str(lines[6])
	if not str(lines[5]).is_empty(): body += "\n\nКогда: " + str(lines[5])
	_body = _label(body, 14, UiTheme.TEXT)
	_scroll.add_child(_body)
	_footer = _label("Полные условия: фокус карты → PgUp / PgDn", 11, UiTheme.TEXT_DIM)
	column.add_child(_footer)
	fit_viewport(_logical_viewport())
	return self

func _label(value: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.focus_mode = Control.FOCUS_NONE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	return label

func _logical_viewport() -> Vector2:
	var tree := Engine.get_main_loop() as SceneTree
	return Vector2(960, 540) if tree == null else tree.root.get_visible_rect().size

func _height(label: Label, width: float, font_size: int) -> float:
	var paragraph := TextParagraph.new()
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.width = width
	paragraph.add_string(label.text, label.get_theme_font("font"), font_size)
	return ceilf(paragraph.get_size().y) + 4.0

func fit_viewport(viewport: Vector2) -> void:
	if viewport.is_equal_approx(_viewport_size): return
	_viewport_size = viewport
	var width := minf(320.0, maxf(160.0, viewport.x - 32.0))
	var content := width - 24.0
	for label in [_title, _kind, _footer]:
		label.custom_minimum_size.x = content
		label.size.x = content
	var header := _height(_title, content, 16) + _height(_kind, content, 12) + 32.0
	var body_width := content - 14.0 # Stable scrollbar gutter; opening it does not rewrap.
	var natural := _height(_body, body_width, 14)
	var budget := maxf(70.0, minf(320.0, viewport.y - 32.0) - header)
	_footer.visible = natural > budget
	if _footer.visible: budget -= _height(_footer, content, 11) + 5.0
	_body.custom_minimum_size = Vector2(body_width, natural)
	_body.size = _body.custom_minimum_size
	_scroll.custom_minimum_size = Vector2(content, minf(natural + 8.0, budget))
	custom_minimum_size.x = width
	size = Vector2(width, 0)

func scroll_page(direction: int) -> void:
	var bar := _scroll.get_v_scroll_bar()
	bar.value += direction * maxf(40.0, bar.page * .8)


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not _footer.visible: return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		scroll_page(-1 if event.keycode == KEY_PAGEUP else 1)
		get_viewport().set_input_as_handled()
