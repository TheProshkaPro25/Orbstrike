class_name TournamentPanel
extends Control
## Турнирное табло: получает открытые данные ядра, не читает составы колод ИИ.

signal play_requested
signal advance_requested
signal exit_requested

const Bracket := preload("res://scenes/ui/tournament_bracket.gd")
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

var _tournament: Tournament
var _campaign: Campaign
var _built := false
var _busy := false
var _play_next := false
var _title: Label
var _subtitle: Label
var _notice: Label
var _overview: BoxContainer
var _group_section: VBoxContainer
var _groups: GridContainer
var _fixtures: GridContainer
var _participants: GridContainer
var _margin: MarginContainer
var _warning: Label
var _actions: BoxContainer


func _ready() -> void:
	_build()
	UiTheme.apply_device_frame(self, "ТУРНИР")
	resized.connect(_adapt_layout)
	_adapt_layout()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and not is_ancestor_of(owner):
		return
	if VisualUtil.scroll_navigation(scroll, event):
		get_viewport().set_input_as_handled()


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
	_warning = _label("Прерванная встреча начнётся заново с тем же раскладом. Завершённые встречи сохраняются.", 14, UiTheme.TEXT_DIM)
	shell.add_child(_warning)
	_actions = BoxContainer.new()
	_actions.add_theme_constant_override("separation", 12)
	shell.add_child(_actions)
	primary_button = Button.new()
	primary_button.custom_minimum_size = Vector2(0, 50)
	primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary_button.add_theme_color_override("font_color", ACCENT)
	primary_button.pressed.connect(_on_primary)
	_actions.add_child(primary_button)
	exit_button = Button.new()
	exit_button.text = "В главное меню"
	exit_button.custom_minimum_size = Vector2(0, 50)
	exit_button.pressed.connect(func() -> void:
		if not _busy:
			exit_requested.emit())
	_actions.add_child(exit_button)


func display(tournament: Tournament, history_entries: Array = [], campaign: Campaign = null) -> void:
	_build()
	_tournament = tournament
	_campaign = campaign
	_title.text = campaign.cup_title() if campaign != null else "Турнир стихий"
	visible = true
	_busy = false
	_play_next = false
	_notice.visible = false
	_clear(content)
	scroll.scroll_vertical = 0
	_overview = null
	_group_section = null
	_groups = null
	_fixtures = null
	_participants = null
	if _tournament == null:
		_subtitle.text = "Турнир недоступен"
		primary_button.visible = false
		_warning.visible = false
		exit_button.disabled = false
		return
	var state := _tournament.state
	var finished := _tournament.completed()
	var next := _tournament.next_match()
	var next_id := String(next.get("id", ""))
	var group_fixtures := {"A": [], "B": []}
	var played := 0
	var total := 15
	for entry: Dictionary in state.matches:
		var stage := String(entry.stage)
		if stage.begins_with("group_"):
			group_fixtures[stage.trim_prefix("group_")].append(entry)
		if int(entry.get("attempt", 0)) > 0:
			total += 1
		if entry.has("result"):
			played += 1
	_subtitle.text = "%s · Встречи: %d / %d · Сложность: %s" % [_current_stage(next, finished), played, total, AIPlayer.difficulty_name(int(state.get("difficulty", 1)))]
	if _campaign != null:
		_subtitle.text = _campaign.progress_text() + "\n" + _subtitle.text
	_warning.visible = not finished
	_build_next(next, finished)
	_build_overview(group_fixtures, next_id)
	_build_fixtures(group_fixtures, next_id)
	_build_participants()
	if finished:
		_build_history(history_entries)
	primary_button.visible = not finished or (_campaign != null and _campaign.can_advance())
	if finished and _campaign != null and _campaign.can_advance():
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


func _build_next(next: Dictionary, finished: bool) -> void:
	var box := _card(content, true)
	box.add_theme_constant_override("separation", 4)
	if finished:
		var champion: int = _tournament.champion()
		var own: bool = champion == 0
		box.add_child(_label("ВЫ — ЧЕМПИОН!" if own else "ТУРНИР ЗАВЕРШЁН", 18, GOOD if own else ACCENT))
		box.add_child(_label(_name(champion), 26, UiTheme.GOLD))
		box.add_child(_label("Итог турнира сохранён.", 15, UiTheme.TEXT_DIM))
		if _campaign != null:
			box.add_child(_label("Кампания завершена: все три кубка сохранены." if _campaign.completed() else "Следующий кубок открыт. Соперники сохранят опыт ваших встреч; команда и сложность прежние.", 16, GOOD))
		return
	var eliminated: bool = _tournament.player_eliminated()
	_play_next = not next.is_empty() and (int(next.a) == 0 or int(next.b) == 0)
	if eliminated:
		box.add_child(_label("ВАШЕ УЧАСТИЕ ЗАВЕРШЕНО", 16, BAD))
		primary_button.text = "Узнать чемпиона"
	elif _play_next:
		box.add_child(_label("ВАША СЛЕДУЮЩАЯ ВСТРЕЧА", 16, ACCENT))
		primary_button.text = "Играть встречу"
	else:
		box.add_child(_label("БЛИЖАЙШАЯ ВСТРЕЧА", 16, ACCENT))
		primary_button.text = "Следующие встречи"
	if not next.is_empty():
		box.add_child(_label("%s  —  %s" % [_name(int(next.a)), _name(int(next.b))], 22))
		var detail := _stage(String(next.stage))
		if String(next.stage).begins_with("group_"):
			detail += " · тур %d" % int(next.round)
		if int(next.get("attempt", 0)) > 0:
			detail += " · переигровка"
		box.add_child(_label(detail, 15, UiTheme.TEXT_DIM))
		if _play_next:
			var opponent: int = int(next.b) if int(next.a) == 0 else int(next.a)
			box.add_child(_label(_campaign.opponent_brief(opponent) if _campaign != null else "Стиль соперника: %s" % _tournament.participant_style(opponent), 16, UiTheme.TEXT_DIM))
		elif not eliminated:
			box.add_child(_label("Встречи соперников будут рассчитаны до вашего следующего выхода.", 15, UiTheme.TEXT_DIM))
	else:
		box.add_child(_label("Подготовка следующего этапа", 22))
		primary_button.text = "Следующие встречи"


func _build_overview(group_fixtures: Dictionary, next_id: String) -> void:
	_overview = BoxContainer.new()
	_overview.add_theme_constant_override("separation", 18)
	content.add_child(_overview)
	_group_section = VBoxContainer.new()
	_group_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_group_section.size_flags_stretch_ratio = 0.9
	_group_section.add_theme_constant_override("separation", 8)
	_overview.add_child(_group_section)
	_group_section.add_child(_label("Групповой этап", 23, UiTheme.GOLD))
	_groups = GridContainer.new()
	_groups.add_theme_constant_override("h_separation", 12)
	_groups.add_theme_constant_override("v_separation", 10)
	_group_section.add_child(_groups)

	var seeds := {}
	for group in ["A", "B"]:
		_build_group(group, group_fixtures[group], seeds)

	var playoff := VBoxContainer.new()
	playoff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playoff.size_flags_stretch_ratio = 1.9
	playoff.add_theme_constant_override("separation", 8)
	_overview.add_child(playoff)
	playoff.add_child(_label("Плей-офф", 23, UiTheme.GOLD))
	var bracket := Bracket.new()
	playoff.add_child(bracket)
	bracket.build(_tournament, seeds, next_id)
	playoff.add_child(_label("Счёт показывает число оставшихся существ. При ничьей назначается одна переигровка. При повторной ничьей учитываются место в группе, очки, разница существ, победы и жребий.", 14, UiTheme.TEXT_DIM))


func _build_group(group: String, fixtures: Array, seeds: Dictionary) -> void:
	var played := 0
	for entry: Dictionary in fixtures:
		if entry.has("result"):
			played += 1
	var settled := played == fixtures.size()
	var color := Bracket.GROUP_A if group == "A" else Bracket.GROUP_B
	var box := _card(_groups, false, 11)
	box.add_theme_constant_override("separation", 4)
	box.add_child(_label("Группа %s · %d/%d встреч" % [group, played, fixtures.size()], 18, color))
	for row: Dictionary in _tournament.standings(group):
		var id := int(row.id)
		var rank := int(row.rank)
		var qualified := settled and rank <= 2
		var place := group + str(rank) if qualified else str(rank)
		if qualified:
			seeds[place] = id
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(line)
		var seed_label := _label(place, 14, color if qualified else UiTheme.TEXT_DIM)
		seed_label.custom_minimum_size.x = 24
		line.add_child(seed_label)
		var entrant := ("Вы · " if id == 0 else "") + _tournament.participant_name(id)
		var name_label := _label(entrant, 15, ACCENT if id == 0 else UiTheme.TEXT)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var points := _label("%d очк." % int(row.points), 14, UiTheme.TEXT_DIM)
		points.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.add_child(points)
		line.tooltip_text = "%s · Победы: %d · Ничьи: %d · Поражения: %d · Разница: %+d" % [entrant, int(row.wins), int(row.draws), int(row.losses), int(row.diff)]
	var qualification := _label("%s1 и %s2 вышли в полуфиналы" % [group, group] if settled else "Первые два места выходят в полуфиналы", 13, color if settled else UiTheme.TEXT_DIM)
	qualification.mouse_filter = Control.MOUSE_FILTER_PASS
	qualification.tooltip_text = "При равенстве очков учитываются личные встречи, общая разница оставшихся существ, победы и жребий."
	box.add_child(qualification)


func _build_fixtures(group_fixtures: Dictionary, next_id: String) -> void:
	content.add_child(_label("Результаты встреч", 23, UiTheme.GOLD))
	content.add_child(_label("Расписание группового этапа", 14, UiTheme.TEXT_DIM))
	_fixtures = GridContainer.new()
	_fixtures.add_theme_constant_override("h_separation", 16)
	_fixtures.add_theme_constant_override("v_separation", 12)
	content.add_child(_fixtures)
	for group in ["A", "B"]:
		var box := _card(_fixtures, false, 13)
		box.add_child(_label("Группа " + group, 19, Bracket.GROUP_A if group == "A" else Bracket.GROUP_B))
		var previous_round := 0
		for entry: Dictionary in group_fixtures[group]:
			var round_number := int(entry.round)
			if round_number != previous_round:
				box.add_child(_label("Тур %d" % round_number, 14, UiTheme.TEXT_DIM))
				previous_round = round_number
			_build_fixture(box, entry, next_id)


func _build_fixture(parent: VBoxContainer, entry: Dictionary, next_id: String) -> void:
	var is_next := String(entry.id) == next_id
	var own := int(entry.a) == 0 or int(entry.b) == 0
	var box := _card(parent, is_next, 8)
	box.add_theme_constant_override("separation", 2)
	box.add_child(_label("%s  —  %s" % [_name(int(entry.a)), _name(int(entry.b))], 16, ACCENT if own or is_next else UiTheme.TEXT))
	var result: Dictionary = entry.get("result", {})
	var status := "Следующая встреча" if is_next else "В расписании"
	if not result.is_empty():
		var alive: Array = result.alive
		var winner := int(result.winner)
		status = "%d : %d · %s" % [int(alive[0]), int(alive[1]), "Ничья" if winner < 0 else "Победа · " + _name(winner)]
	box.add_child(_label(status, 14, ACCENT if is_next else UiTheme.TEXT_DIM))


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


func _current_stage(next: Dictionary, finished: bool) -> String:
	if finished:
		return "Турнир завершён"
	var stage := String(next.get("stage", ""))
	if stage.begins_with("group_"):
		return "Групповой этап"
	return _stage(stage)


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
	var side_by_side := size.x >= 1120.0
	var pad := 18 if narrow else 32
	for edge in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + edge, pad)
	_title.add_theme_font_size_override("font_size", 26 if narrow else 32)
	_actions.vertical = size.x < 420.0
	if is_instance_valid(_overview):
		_overview.vertical = not side_by_side
		var group_index := 0 if side_by_side else 1
		if _group_section.get_index() != group_index:
			_overview.move_child(_group_section, group_index)
		_groups.columns = 1 if narrow or side_by_side else 2
	if is_instance_valid(_fixtures):
		_fixtures.columns = 1 if narrow else 2
	if is_instance_valid(_participants):
		_participants.columns = 1 if narrow else 2


func _label(text: String, font_size: int, color: Color = UiTheme.TEXT) -> Label:
	var label := VisualUtil.label(text, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	return label


func _card(parent: Node, accent: bool = false, pad: int = 14) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiTheme.box(SURFACE, ACCENT.darkened(0.22) if accent else BORDER, 1, 3, pad))
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
