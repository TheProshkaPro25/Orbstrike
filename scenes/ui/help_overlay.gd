class_name HelpOverlay
extends Control
## Экран «Как играть»: правила простыми словами, типы карт и цикл стихий. Закрывается кнопкой или кликом по фону.

const SECTIONS := [
	["Цель", "Выбей всех трёх существ соперника. Существа бросаются шарами на карты ворот и сражаются на них."],
	["Ход", "На старте у каждого 3 карты ворот и 3 способности. Со второго своего хода получаешь одну случайную новую карту: ворота или способность. Карты подбираются под команду и не повторяются; когда запас исчерпан, добор прекращается. Перезарядка сыгранных способностей сохраняется.\n1. Положи карту ворот (по желанию; обязательно, если на поле нет ворот) — ближе к сопернику, рядом с другими картами. Или выбери «Ворота + бросок»: карта ложится и существо сразу летит на неё — всё за один ход.\n2. Выбери существо (шар) и брось: выбери подсвеченные ворота щелчком или кнопкой «Выбрать ворота для броска…». Для выкладки выбери карту и кнопку «Место на поле…». В карте поля стрелки / Tab выбирают место, Enter подтверждает, Esc возвращает без расхода действия. Начальная скорость рассчитана заранее; силу броска настраивать не нужно."],
	["Куда попал шар", "• Выбранные ворота задают цель броска. Сфера отскакивает и катится; учитывается фактическая точка остановки.\n• Остановка за пределами ворот — промах: существо уходит в использованные, ход переходит сопернику.\n• Пустые ворота — существо встаёт на них (после приземления можно прикрепить способность).\n• Ворота с существом соперника — бой.\n• Ворота со своим существом — оно переходит на другие ворота; если некуда, карта засчитывается тебе."],
	["Три момента способностей", "Карту способности можно сыграть в один из трёх моментов:\n• ДО БРОСКА — когда существо выбрано, карта прикрепляется к нему и сработает в его следующем бою;\n• ПОСЛЕ ПРИЗЕМЛЕНИЯ — когда существо встало на пустые ворота, можно прикрепить карту (кнопка «Завершить ход» — без карты);\n• В БОЮ — обмен картами по очереди.\nПрикреплённые карты видны сопернику."],
	["Бой и обмен картами", "Ворота открывает их владелец кнопкой «Открыть мои ворота» в свой ответ и только во время боя. Пока они закрыты, сила G и ловушки не действуют. Игроки по очереди играют способности: первым отвечает атакующий, в том числе после жребия тупика. На каждой стороне не больше 3 карт за бой (прикреплённые тоже считаются). Бой пошаговый: «Пас» — пропуск хода; если соперник после этого сыграет карту, можно ответить снова. Бой решается, когда оба спасовали подряд. Побеждает большая сила: базовая + сила G ворот + способности. Ничья — победа того, кто встал первым. Проигравший выбывает, победитель уходит в зону использованных и ходит следующим."],
	["Зона использованных", "Когда бросать некого, существа из зоны использованных возвращаются в руку. Если все живые стоят на воротах, ход пропускается. При двух пропусках подряд жребий определяет атакующего: его сильнейшее стоящее существо идёт к сильнейшему сопернику. Первый ответ — у атакующего. Снять существо с ворот вручную нельзя."],
	["Карты ворот и ловушки", "Ворота стихии: «Поле» даёт силу только своей стихии (Камень +150 … Тень +80), «Алтарь силы» +300 защитнику-владельцу. Ворота вида удваивают базовую силу существа этого вида — у любой стороны. Командные ворота меняют правила: «Воронка» перекачивает 100 силы, «Удержание» оставляет победителя на воротах, «Зов павших» возвращает выбывших, «Трон сумрака» отдаёт победу Тени. Ловушки («Зеркало», «Предел», «Обоюдный удар», «Глухие врата») срабатывают при открытии ворот."],
	["Способности", "Стихийные — только своя стихия: Пламя жжёт и перекачивает силу, Буря переносит существ, Свет возрождает выбывших ценой силы, Камень сдвигает ворота и копирует, Тень губит обоих бойцов, Прилив глушит и уносит. Усиления — лесенка +30…+300 своей стихии (большие — для отстающих и возвращаются в руку). Видовые — только для своего вида: отмена, сброс силы, «нельзя отменить». До 3 карт на бой (по очереди с соперником); сыгранная карта отдыхает 2 следующих боя. Последний рывок сразу возвращает только синие усиления; красные и зелёные отдыхают полный срок, даже после отмены. Явный возврат на карте и «Второе дыхание» действуют раньше. У каждой стихии есть красная ответная отмена без прибавки силы: только в бою на последнюю действующую основную карту соперника; не отменяет мгновенные, слияния напрямую и неотменяемые. Такой реакцией можно снять саму «Тишь», но не «Глухие врата». Копия наследует запрет дальнейших карт от скопированного эффекта. В бою условное усиление доступно только при выполненном условии; иначе подсказка объясняет причину. Отменённая основа не подходит для слияния, отменённая блокировка больше не запрещает следующие карты. Наведи мышь на карту, чтобы прочитать подробности и причину недоступности."],
	["Стихии", "Стихия определяет, какие стихийные способности может использовать существо и сколько силы оно получает от ворот. Сама по себе стихия не даёт преимущества над стихией соперника."],
	["Сложность соперника", "В меню команды выбери Новичка, Бойца или Мастера. Мастер выбирает цели и сочетания карт, держит запас силы на ответ и ставит ловушки-приманки."],
	["Рука и темп", "Большая рука разделена на страницы: кнопки ‹ / ›, стрелки ← / → или колёсико над картами. Доступные карты показаны первыми. Наведение поднимает карту и показывает полный текст. Темп справа меняет скорость постановки ×0.75 / ×1 / ×1.5 / ×2; время на чтение не ускоряется. Итог боя остаётся до нажатия «Дальше»."],
]

var _built := false
var _return_focus: Control
var _close_button: Button
var _scroll: ScrollContainer


func _ready() -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	_build()


## Открыть поверх всего (parent — слой интерфейса).
static func open_on(parent: Node) -> HelpOverlay:
	var h := HelpOverlay.new()
	parent.add_child(h)
	return h


func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0.02, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close())
	add_child(dim)
	var panel := PanelContainer.new()
	# Keep the close button and the scroll area inside the viewport at any aspect ratio.
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.05
	panel.anchor_bottom = 0.95
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := VisualUtil.label("Как играть", 28)
	t.add_theme_color_override("font_color", UiTheme.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	_close_button = close
	close.text = "Понятно"
	close.custom_minimum_size = Vector2(130, 40)
	close.pressed.connect(_close)
	head.add_child(close)
	var sc := ScrollContainer.new()
	_scroll = sc
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for sec in SECTIONS:
		var h := VisualUtil.label(sec[0], 19)
		h.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		list.add_child(h)
		var body := VisualUtil.label(sec[1], 15)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(body)
	close.focus_next = close.get_path_to(close)
	close.focus_previous = close.focus_next
	VisualUtil.focus_if_present.call_deferred(close)


func _close() -> void:
	hide()
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree(): _return_focus.grab_focus()
	var game := get_parent().get_parent() if get_parent() != null else null
	if game != null and game.has_method("_resume_keyboard_focus"): game.call_deferred("_resume_keyboard_focus")
	queue_free()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed: return
	if event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and not event.echo:
		get_viewport().set_input_as_handled()
		_close()
	elif event.keycode in [KEY_TAB, KEY_LEFT, KEY_RIGHT]:
		get_viewport().set_input_as_handled()
		_close_button.grab_focus()
	elif event.keycode in [KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END]:
		get_viewport().set_input_as_handled()
		var step := 64 if event.keycode in [KEY_UP, KEY_DOWN] else 240
		_scroll.scroll_vertical += -step if event.keycode in [KEY_UP, KEY_PAGEUP] else step
		if event.keycode == KEY_HOME: _scroll.scroll_vertical = 0
		if event.keycode == KEY_END: _scroll.scroll_vertical = int(_scroll.get_child(0).size.y)
