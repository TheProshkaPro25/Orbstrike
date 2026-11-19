extends BoxContainer
## Показывает пары и переходы по открытому расписанию Tournament.

const NEXT := Color("82d7df")
const THROUGH := Color("a8dfb8")
const GROUP_A := Color("8fdbde")
const GROUP_B := Color("cdb9f6")
const FINAL := Color("f4d18a")
const BORDER := Color("3a5667")
const SURFACE := Color("112331")

var _cup: Tournament
var _semis: BoxContainer
var _semi_cards: Array[PanelContainer] = []
var _final_card: PanelContainer
var _final_slots: Array[PanelContainer] = []
var _advancers: Array[int] = []


func build(cup: Tournament, seeds: Dictionary, next_id: String) -> void:
	_cup = cup
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pairs := {"SF1": [], "SF2": [], "FINAL": []}
	for match_record: Dictionary in cup.state.matches:
		var pair_id := String(match_record.id).trim_suffix("-replay")
		if pairs.has(pair_id):
			pairs[pair_id].append(match_record)

	_semis = BoxContainer.new()
	_semis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_semis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_semis.add_theme_constant_override("separation", 12)
	add_child(_semis)
	_semis.item_rect_changed.connect(queue_redraw)
	var semi_seeds := [["A1", "B2"], ["B1", "A2"]]
	for i in range(2):
		var sources: Array = semi_seeds[i]
		var entrants := [int(seeds.get(sources[0], -1)), int(seeds.get(sources[1], -1))]
		var attempts: Array = pairs["SF%d" % (i + 1)]
		_advancers.append(_advancer(attempts))
		var card := _pair("Полуфинал %d" % (i + 1), sources, entrants, attempts, next_id)
		_semis.add_child(card)
		_semi_cards.append(card)
		card.item_rect_changed.connect(queue_redraw)

	var final_column := VBoxContainer.new()
	final_column.alignment = BoxContainer.ALIGNMENT_CENTER
	final_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	final_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(final_column)
	final_column.item_rect_changed.connect(queue_redraw)
	_final_card = _pair("Финал", ["ПФ 1", "ПФ 2"], _advancers, pairs.FINAL, next_id, true)
	final_column.add_child(_final_card)
	_final_card.item_rect_changed.connect(queue_redraw)
	resized.connect(_adapt_layout)
	_adapt_layout()


func _pair(title: String, sources: Array, entrants: Array, attempts: Array, next_id: String, is_final: bool = false) -> PanelContainer:
	var latest: Dictionary = attempts.back() if not attempts.is_empty() else {}
	var result: Dictionary = latest.get("result", {})
	var advancing := int(result.get("advancing", -1))
	var is_next := not latest.is_empty() and String(latest.id) == next_id
	var accent := NEXT if is_next else (FINAL if is_final else BORDER)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var border := UiTheme.box(SURFACE, accent, 1, 3, 12)
	border.border_width_left = 3
	card.add_theme_stylebox_override("panel", border)
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 5)
	card.add_child(body)

	var caption := _label(title, 18, FINAL if is_final else UiTheme.TEXT)
	caption.add_theme_font_override("font", UiTheme.heading_font())
	body.add_child(caption)
	var ids := entrants if latest.is_empty() else [int(latest.a), int(latest.b)]
	var alive: Array = result.get("alive", [])
	for side in range(2):
		var id := int(ids[side])
		var score := "—" if alive.is_empty() else str(int(alive[side]))
		var slot := _slot(String(sources[side]), id, score, id >= 0 and id == advancing)
		body.add_child(slot)
		if is_final:
			_final_slots.append(slot)
			slot.item_rect_changed.connect(queue_redraw)

	if attempts.size() > 1:
		var first_alive: Array = attempts[0].result.alive
		body.add_child(_label("Первая встреча · %d : %d · ничья" % [int(first_alive[0]), int(first_alive[1])], 13, UiTheme.TEXT_DIM))
	var status := _pair_status(result, latest, is_next, is_final)
	var status_color := UiTheme.TEXT_DIM
	if is_next:
		status_color = NEXT
	elif advancing >= 0:
		status_color = FINAL if is_final else THROUGH
	body.add_child(_label(status, 14, status_color))
	return card


func _slot(source: String, id: int, score: String, advanced: bool) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	var own := id == 0
	var name_text := _cup.participant_name(id) if id >= 0 else "Не определён"
	var color := NEXT if own else (THROUGH if advanced else (UiTheme.TEXT if id >= 0 else UiTheme.TEXT_DIM))
	var source_color := GROUP_A if source.begins_with("A") else (GROUP_B if source.begins_with("B") else UiTheme.TEXT_DIM)
	var edge := color.darkened(0.35) if own or advanced else Color("2c4656")
	var style := UiTheme.box(Color("192f3b") if own or advanced else Color("10202a"), edge, 1, 3, 5)
	slot.add_theme_stylebox_override("panel", style)
	slot.tooltip_text = ("%s · %s" % [source, name_text]) + (" · Вы" if own else "")
	if score != "—":
		slot.tooltip_text += " · Осталось существ: " + score
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	slot.add_child(row)
	var seed := _label(source, 13, source_color)
	seed.autowrap_mode = TextServer.AUTOWRAP_OFF
	seed.custom_minimum_size.x = 32
	row.add_child(seed)
	var name_label := _label(("Вы · " if own else "") + name_text, 16, color)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var score_label := _label(score, 16, color)
	score_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.custom_minimum_size.x = 15
	row.add_child(score_label)
	return slot


func _pair_status(result: Dictionary, latest: Dictionary, is_next: bool, is_final: bool) -> String:
	if latest.is_empty():
		return "Ждёт победителей полуфиналов" if is_final else "Ждёт итогов групп"
	var replay := int(latest.get("attempt", 0)) > 0
	if result.is_empty():
		if is_next:
			return "Следующая встреча · переигровка" if replay else "Следующая встреча"
		return "Ожидает переигровки" if replay else "В расписании"
	var advancing := int(result.get("advancing", -1))
	if advancing < 0:
		return "Ничья · назначена переигровка"
	var name_text := _cup.participant_name(advancing)
	var outcome := "Чемпион · " if is_final else "В финал · "
	if int(result.get("winner", -1)) < 0:
		return ("Повторная ничья · чемпион " if is_final else "Повторная ничья · в финал ") + name_text
	return ("Переигровка · " if replay else "") + outcome + name_text


func _advancer(attempts: Array) -> int:
	if attempts.is_empty():
		return -1
	var latest: Dictionary = attempts.back()
	var result: Dictionary = latest.get("result", {})
	return int(result.get("advancing", -1))


func _adapt_layout() -> void:
	vertical = size.x < 625.0
	_semis.vertical = not vertical
	add_theme_constant_override("separation", 30 if vertical else 38)
	queue_redraw()


func _draw() -> void:
	if _final_slots.size() != 2:
		return
	var to_local := get_global_transform().affine_inverse()
	var final_position := to_local * _final_card.global_position
	for i in range(2):
		var card := _semi_cards[i]
		var origin := to_local * card.global_position
		var slot := _final_slots[i]
		var destination := to_local * slot.global_position
		var start_point: Vector2
		var end_point: Vector2
		var path: PackedVector2Array
		if vertical:
			start_point = origin + Vector2(card.size.x * 0.5, card.size.y)
			end_point = final_position + Vector2(_final_card.size.x * (0.25 + 0.5 * i), 0)
			var bend_y := (start_point.y + end_point.y) * 0.5
			path = PackedVector2Array([start_point, Vector2(start_point.x, bend_y), Vector2(end_point.x, bend_y), end_point])
		else:
			start_point = origin + Vector2(card.size.x, card.size.y * 0.5)
			end_point = Vector2(final_position.x, destination.y + slot.size.y * 0.5)
			var bend_x := (start_point.x + end_point.x) * 0.5
			path = PackedVector2Array([start_point, Vector2(bend_x, start_point.y), Vector2(bend_x, end_point.y), end_point])
		var color := NEXT if _advancers[i] == 0 else (THROUGH if _advancers[i] > 0 else BORDER.lightened(0.24))
		draw_polyline(path, color, 2.0, true)
		draw_circle(end_point, 3.0, color, true, -1.0, true)


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := VisualUtil.label(value, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	return label
