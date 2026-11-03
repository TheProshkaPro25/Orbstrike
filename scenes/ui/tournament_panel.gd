class_name TournamentPanel
extends Control
## Турнирное табло: получает открытые данные ядра, не читает составы колод ИИ.

signal play_requested
signal advance_requested
signal exit_requested

const SURFACE := Color("111e30")
const BORDER := Color("34475f")
const ACCENT := Color("82d7df")
const GOOD := Color("a8dfb8")
const BAD := Color("ffb4a5")

## Открыты для узких проверок и управления состоянием из Main.
var primary_button: Button
var content: VBoxContainer
var exit_button: Button
var scroll: ScrollContainer

var _tournament
var _campaign
var _built := false
var _busy := false
var _play_next := false
var _title: Label
var _subtitle: Label
var _notice: Label
var _groups: GridContainer
var _participants: GridContainer
var _margin: MarginContainer
var _warning: Label


func _ready() -> void:
	_build()
	resized.connect(_adapt_layout)
	_adapt_layout()


func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	var background := ColorRect.new()
	background.color = Color("080f1b")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	_margin.add_child(shell)
	_title = _label("Турнир стихий", 32, UiTheme.GOLD)
	_title.add_theme_font_override("font", UiTheme.heading_font())
	shell.add_child(_title)
	_subtitle = _label("", 16, UiTheme.TEXT_DIM)
	shell.add_child(_subtitle)
	var line := HSeparator.new()
	shell.add_child(line)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)
	_notice = _label("", 15, UiTheme.TEXT_DIM)
	_notice.visible = false
	shell.add_child(_notice)
	_warning = _label("Если выйти во время встречи, она начнётся заново с тем же начальным раскладом. Результаты завершённых встреч сохраняются.", 14, UiTheme.TEXT_DIM)
	shell.add_child(_warning)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	shell.add_child(actions)
	primary_button = Button.new()
	primary_button.custom_minimum_size = Vector2(0, 50)
	primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary_button.add_theme_color_override("font_color", ACCENT)
	primary_button.pressed.connect(_on_primary)
	actions.add_child(primary_button)
	exit_button = Button.new()
	exit_button.text = "В главное меню"
	exit_button.custom_minimum_size = Vector2(0, 50)
	exit_button.pressed.connect(func() -> void:
		if not _busy:
			exit_requested.emit())
	actions.add_child(exit_button)


func display(tournament, history_entries: Array = [], campaign = null) -> void:
	_build()
	_tournament = tournament
	_campaign = campaign
	_title.text = campaign.cup_title() if campaign != null else "Турнир стихий"
	visible = true
	_busy = false
	_notice.visible = false
	_clear(content)
	_groups = null
	_participants = null
	if _tournament == null:
		_subtitle.text = "Турнир недоступен"
		primary_button.visible = false
		_warning.visible = false
		exit_button.disabled = false
		return
	var state: Dictionary = _tournament.state
	var finished: bool = _tournament.completed()
	var played := 0
	var total := 15
	for entry in state.get("matches", []):
		if int(entry.get("attempt", 0)) > 0:
			total += 1
		if not entry.get("result", {}).is_empty():
			played += 1
	_subtitle.text = "8 участников · 2 группы → полуфиналы → финал · Сложность: %s (фиксирована)\nЗавершено встреч: %d / %d" % [AIPlayer.difficulty_name(int(state.get("difficulty", 1))), played, total]
	if _campaign != null:
		_subtitle.text = _campaign.progress_text() + "\n" + _subtitle.text
	_warning.visible = not finished
	_build_next(finished)
	_build_groups()
	_build_bracket()
	_build_participants()
	_build_results()
	if finished:
		_build_history(history_entries)
	primary_button.visible = not finished or (_campaign != null and _campaign.can_advance())
	if finished and _campaign != null and _campaign.can_advance():
		_play_next = false
		primary_button.text = "Следующий кубок →"
	primary_button.disabled = false
	exit_button.disabled = false
	_adapt_layout()


## Статус сохранения/подсчёта приходит от Main; ошибка остаётся читаемой вне прокрутки.
func show_notice(message: String, is_error: bool = false) -> void:
	_build()
	_notice.text = message
	_notice.add_theme_color_override("font_color", BAD if is_error else GOOD)
	_notice.visible = not message.is_empty()


func set_busy(value: bool) -> void:
	_busy = value
	primary_button.disabled = value
	exit_button.disabled = value


func _build_next(finished: bool) -> void:
	var box := _card(content, true)
	if finished:
		var champion: int = _tournament.champion()
		var own: bool = champion == 0
		box.add_child(_label("ВЫ — ЧЕМПИОН!" if own else "ТУРНИР ЗАВЕРШЁН", 18, GOOD if own else ACCENT))
		box.add_child(_label(_name(champion), 30, UiTheme.GOLD))
		box.add_child(_label("Победитель турнира. Все встречи и итог сохранены.", 16, UiTheme.TEXT_DIM))
		if _campaign != null:
			box.add_child(_label("Кампания завершена: все три кубка сохранены." if _campaign.completed() else "Следующий кубок открыт. Соперники сохранят опыт ваших встреч; команда и сложность прежние.", 16, GOOD))
		return
	var next: Dictionary = _tournament.next_match()
	var eliminated: bool = _tournament.player_eliminated()
	_play_next = not next.is_empty() and (int(next.a) == 0 or int(next.b) == 0)
	if eliminated:
		box.add_child(_label("ВАШЕ УЧАСТИЕ ЗАВЕРШЕНО", 18, BAD))
		box.add_child(_label("Турнир продолжается", 27))
		box.add_child(_label("Можно досчитать оставшиеся встречи и узнать чемпиона. Ваши результаты останутся в таблицах.", 16, UiTheme.TEXT_DIM))
		primary_button.text = "Узнать чемпиона"
	elif _play_next:
		box.add_child(_label("ВАША СЛЕДУЮЩАЯ ВСТРЕЧА", 17, ACCENT))
		primary_button.text = "Играть встречу"
	else:
		box.add_child(_label("БЛИЖАЙШАЯ ВСТРЕЧА", 17, ACCENT))
		primary_button.text = "Следующие встречи"
	if not next.is_empty():
		box.add_child(_label("%s  —  %s" % [_name(int(next.a)), _name(int(next.b))], 25))
		var extra := " · переигровка" if int(next.get("attempt", 0)) > 0 else ""
		box.add_child(_label(_stage(str(next.get("stage", ""))) + extra, 15, UiTheme.TEXT_DIM))
		if _play_next:
			var opponent: int = int(next.b) if int(next.a) == 0 else int(next.a)
			box.add_child(_label(_campaign.opponent_brief(opponent) if _campaign != null else "Стиль соперника: %s" % _tournament.participant_style(opponent), 16, UiTheme.TEXT_DIM))
		elif not eliminated:
			box.add_child(_label("Встречи соперников будут рассчитаны до вашего следующего выхода.", 16, UiTheme.TEXT_DIM))
	else:
		box.add_child(_label("Подготовка следующего этапа", 22))
		primary_button.text = "Следующие встречи"


func _build_groups() -> void:
	content.add_child(_label("Групповой этап", 23, UiTheme.GOLD))
	_groups = GridContainer.new()
	_groups.columns = 2
	_groups.add_theme_constant_override("h_separation", 16)
	_groups.add_theme_constant_override("v_separation", 16)
	content.add_child(_groups)
	for group in ["A", "B"]:
		var box := _card(_groups)
		box.add_child(_label("Группа " + group, 20, ACCENT))
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 10)
		box.add_child(grid)
		for heading in ["№", "Участник", "И", "В–Н–П", "±", "О"]:
			var head := _label(heading, 13, UiTheme.TEXT_DIM)
			head.autowrap_mode = TextServer.AUTOWRAP_OFF
			head.tooltip_text = "И — встречи; В–Н–П — победы, ничьи, поражения; ± — разница оставшихся существ; О — очки."
			grid.add_child(head)
		for row in _tournament.standings(group):
			var values: Array = [str(row.rank), _name(int(row.id)), str(row.played), "%d–%d–%d" % [int(row.wins), int(row.draws), int(row.losses)], "%+d" % int(row.diff), str(row.points)]
			for i in values.size():
				var cell := _label(values[i], 16, ACCENT if int(row.id) == 0 else UiTheme.TEXT)
				if i == 1:
					cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				else:
					cell.autowrap_mode = TextServer.AUTOWRAP_OFF
				grid.add_child(cell)
	content.add_child(_label("По два лучших выходят из группы. При равенстве очков: личные встречи (мини-таблица), общая разница оставшихся существ, победы, сохранённый жребий.", 14, UiTheme.TEXT_DIM))


func _build_bracket() -> void:
	var box := _card(content)
	box.add_child(_label("Плей-офф", 23, UiTheme.GOLD))
	var semifinals: Array = []
	var finals: Array = []
	for entry in _tournament.state.get("matches", []):
		if str(entry.get("stage", "")) == "semifinal":
			semifinals.append(entry)
		elif str(entry.get("stage", "")) == "final":
			finals.append(entry)
	box.add_child(_label("Полуфиналы", 17, ACCENT))
	if semifinals.is_empty():
		box.add_child(_label("1-е место A  —  2-е место B\n1-е место B  —  2-е место A", 17))
	else:
		for entry in semifinals:
			box.add_child(_label(_match_line(entry), 17))
	box.add_child(HSeparator.new())
	box.add_child(_label("Финал", 17, ACCENT))
	if finals.is_empty():
		box.add_child(_label("Победители полуфиналов", 17, UiTheme.TEXT_DIM))
	else:
		for entry in finals:
			box.add_child(_label(_match_line(entry), 18, UiTheme.GOLD))
	box.add_child(_label("Ничья в плей-офф: одна переигровка. При повторной ничьей учитываются место в группе, очки, разница оставшихся существ, победы, затем сохранённый жребий.", 14, UiTheme.TEXT_DIM))


func _build_participants() -> void:
	content.add_child(_label("Участники и стили", 23, UiTheme.GOLD))
	_participants = GridContainer.new()
	_participants.columns = 2
	_participants.add_theme_constant_override("h_separation", 16)
	_participants.add_theme_constant_override("v_separation", 10)
	content.add_child(_participants)
	for participant in _tournament.state.get("participants", []):
		var id: int = int(participant.id)
		var box := _card(_participants)
		box.add_child(_label(_name(id), 18, ACCENT if id == 0 else UiTheme.TEXT))
		box.add_child(_label(str(_tournament.participant_style(id)), 15, UiTheme.TEXT_DIM))


func _build_results() -> void:
	var box := _card(content)
	box.add_child(_label("Результаты встреч", 23, UiTheme.GOLD))
	var any_result := false
	for entry in _tournament.state.get("matches", []):
		if entry.get("result", {}).is_empty():
			continue
		any_result = true
		box.add_child(_label("%s · %s" % [_stage(str(entry.get("stage", ""))), _match_line(entry)], 16))
	if not any_result:
		box.add_child(_label("Первые результаты появятся после завершения встреч.", 16, UiTheme.TEXT_DIM))


func _build_history(entries: Array) -> void:
	if entries.is_empty():
		return
	var box := _card(content)
	box.add_child(_label("История турниров", 23, UiTheme.GOLD))
	var begin := maxi(0, entries.size() - 8)
	for i in range(entries.size() - 1, begin - 1, -1):
		var entry: Dictionary = entries[i]
		var rank := int(entry.get("player_rank", 0))
		var result := "победа" if rank == 1 else ("финалист" if rank == 2 else ("полуфинал" if rank == 3 else "групповой этап"))
		box.add_child(_label("%s · Чемпион: %s · Ваш итог: %s" % [str(entry.get("name", "Турнир стихий")), str(entry.get("champion_name", "Не определён")), result], 16))


func _match_line(entry: Dictionary) -> String:
	var names := "%s  —  %s" % [_name(int(entry.a)), _name(int(entry.b))]
	var result: Dictionary = entry.get("result", {})
	if result.is_empty():
		return names + " · ожидает"
	var alive: Array = result.get("alive", [0, 0])
	var score := "%d : %d" % [int(alive[0]), int(alive[1])]
	var winner: int = int(result.get("winner", -1))
	var outcome := "ничья" if winner < 0 else "победа: " + _name(winner)
	if winner < 0 and int(result.get("advancing", -1)) >= 0:
		outcome += "; проходит " + _name(int(result.advancing))
	var retry := " · после переигровки" if int(entry.get("attempt", 0)) > 0 else ""
	return "%s · %s · %s%s" % [names, score, outcome, retry]


func _name(id: int) -> String:
	if id < 0:
		return "Не определён"
	return str(_tournament.participant_name(id)) + (" (вы)" if id == 0 else "")


func _stage(value: String) -> String:
	match value:
		"group_A": return "Группа A"
		"group_B": return "Группа B"
		"semifinal": return "Полуфинал"
		"final": return "Финал"
	return "Встреча"


func _on_primary() -> void:
	if _busy:
		return
	if _play_next:
		play_requested.emit()
	else:
		advance_requested.emit()


func _adapt_layout() -> void:
	if not _built:
		return
	var narrow := size.x < 1000.0
	var pad := 18 if narrow else 32
	for edge in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + edge, pad)
	_title.add_theme_font_size_override("font_size", 26 if narrow else 32)
	if is_instance_valid(_groups):
		_groups.columns = 1 if narrow else 2
	if is_instance_valid(_participants):
		_participants.columns = 1 if narrow else 2


func _label(text: String, font_size: int, color: Color = UiTheme.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _card(parent: Node, accent: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiTheme.box(SURFACE, ACCENT.darkened(0.42) if accent else BORDER, 1, 12, 18))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(box)
	return box


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
