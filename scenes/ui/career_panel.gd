class_name CareerPanel
extends Control
## Менеджер локальной карьеры. Здесь только данные и 2D: каталог моделей не затрагивается.

signal create_requested(element: int, difficulty: int)
signal registration_requested(creatures: Array[StringName], gates: Array[StringName], abilities: Array[StringName], levels: Dictionary)
signal continue_requested
signal advance_requested
signal replay_requested
signal exit_requested

const TAB_NAMES := ["Команда", "Карты", "Магазин", "Прогресс"]
const CLASS_NAMES := {&"gold": "Ворота стихии", &"silver": "Ворота вида", &"bronze": "Командные ворота", &"red": "Стихийная способность", &"blue": "Усиление", &"green": "Видовая способность"}
const PROFILE := preload("res://data/player_profile.gd")
const CAREER := preload("res://core/career.gd")

var _career: RefCounted
var _team: Array[StringName] = []
var _picks: Dictionary = {}
var _levels: Dictionary = {}
var _tab := 0
var _shop_kind := 0
var _built := false
var _notice := ""
var _head: Label
var _status: Label
var _tabs: HBoxContainer
var _scroll: ScrollContainer
var _page: VBoxContainer
var _validation: Label
var _action: Button
var _extra: Button
var _element_choice: OptionButton
var _difficulty_choice: OptionButton


func _ready() -> void:
	_build()
	_redraw()


## null открывает первый шаг; существующее сохранение никогда не удаляется этим экраном.
func display(career: RefCounted, notice: String = "") -> void:
	var changed := _career != career
	_career = career
	_notice = notice
	if changed:
		_team.clear()
		_picks.clear()
		_levels.clear()
		_tab = 0
		if _career != null:
			_set_deck(_career.starter_deck())
	if _career != null and _career.cup != null:
		var active: Dictionary = _career.state.active
		var deck: Array = active.get("deck", [])
		if deck.size() == 3:
			_set_deck(CardDB.build_deck(deck[0], deck[1], deck[2]))
			_levels = (active.get("levels", {}) as Dictionary).duplicate()
	_build()
	_redraw()
	show()


func show_error(message: String) -> void:
	_notice = message
	if _built:
		_status.text = _notice
		_status.visible = not _notice.is_empty()


func _build() -> void:
	if _built:
		return
	_built = true
	CardDB.load_all()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.name = "CareerBackground"
	background.color = Color(0.025, 0.035, 0.055, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	UiTheme.apply_device_frame(self, "КАРЬЕРА")
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 20)
	add_child(margins)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margins.add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	_head = _label("Карьера", 23)
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_head)
	var back := _button("В меню")
	back.name = "CareerExit"
	back.pressed.connect(func() -> void: exit_requested.emit())
	heading.add_child(back)
	_status = _label("", 15)
	_status.name = "CareerNotice"
	layout.add_child(_status)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	layout.add_child(_tabs)
	for i in TAB_NAMES.size():
		var button := _button(TAB_NAMES[i])
		button.name = "CareerTab%d" % i
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_switch_tab.bind(i))
		_tabs.add_child(button)
	_scroll = ScrollContainer.new()
	_scroll.name = "CareerScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	layout.add_child(_scroll)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 12)
	_scroll.add_child(_page)
	var footer := VBoxContainer.new()
	footer.name = "CareerFooter"
	footer.add_theme_constant_override("separation", 6)
	layout.add_child(footer)
	_validation = _label("", 15)
	_validation.name = "CareerValidation"
	footer.add_child(_validation)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	footer.add_child(actions)
	_extra = _button("Повторить кубок")
	_extra.name = "CareerReplay"
	_extra.pressed.connect(func() -> void: replay_requested.emit())
	actions.add_child(_extra)
	_action = _button("Начать карьеру")
	_action.name = "CareerAction"
	_action.custom_minimum_size.x = 220
	_action.pressed.connect(_activate)
	actions.add_child(_action)


func _redraw() -> void:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_name := String(focused.name) if focused != null and is_ancestor_of(focused) else ""
	var scroll_position := _scroll.scroll_vertical
	_clear(_page)
	_status.text = _notice
	_status.visible = not _notice.is_empty()
	_tabs.visible = _career != null
	_extra.hide()
	_action.disabled = false
	if _career == null:
		_head.text = "Карьера · первый шаг"
		_build_onboarding()
		_action.text = "Начать карьеру"
		_validation.text = "Стихия и сложность сохраняются для всей карьеры. Имя берётся из вашего персонажа."
		_restore_navigation.call_deferred(focus_name, scroll_position)
		return
	_head.text = "%s · %d кр." % [_career.cup_title(), int(_career.state.credits)]
	for i in _tabs.get_child_count():
		(_tabs.get_child(i) as Button).set_pressed_no_signal(i == _tab)
	match _tab:
		0: _build_team()
		1: _build_cards()
		2: _build_shop()
		3: _build_progress()
	_update_footer()
	_restore_navigation.call_deferred(focus_name, scroll_position)


func _restore_navigation(focus_name: String, scroll_position: int) -> void:
	if not visible or not is_inside_tree():
		return
	_scroll.scroll_vertical = scroll_position
	if not focus_name.is_empty():
		var control := find_child(focus_name, true, false) as Control
		if control != null and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
			control.grab_focus()


func _switch_tab(index: int) -> void:
	_tab = index
	_scroll.scroll_vertical = 0
	_redraw()


func _build_onboarding() -> void:
	var profile := PROFILE.new()
	profile.load_from()
	_page.add_child(_label("Добро пожаловать, %s" % str(profile.value.name), 22))
	_page.add_child(_label("Соберите команду одной стихии, пройдите три лиги и развивайте собственных существ. Победы и поражения приносят опыт; кредиты открывают точные покупки без случайных наборов.", 17))
	_page.add_child(_label("Ваша стихия", 17))
	_element_choice = _option()
	_element_choice.name = "CareerElement"
	for i in Attr.COUNT:
		_element_choice.add_item(Attr.display_name(i), i)
	_element_choice.select(int(profile.value.get("element", 0)))
	_page.add_child(_element_choice)
	_page.add_child(_label("Сложность соперников", 17))
	_difficulty_choice = _option()
	_difficulty_choice.name = "CareerDifficulty"
	for title in ["Новичок", "Боец", "Мастер"]:
		_difficulty_choice.add_item(title)
	_difficulty_choice.select(1)
	_page.add_child(_difficulty_choice)
	_page.add_child(_label("Новичок чаще ошибается в бросках и картах. Боец отвечает на способности. Мастер точнее бросает и бережёт силу для ответа. Карьера сохраняется отдельно от быстрой дуэли и обычного турнира.", 15))


func _build_team() -> void:
	var locked := _roster_locked()
	_page.add_child(_label("Ваша команда · %d / 3" % _team.size(), 20))
	_page.add_child(_label("Состав и боевые уровни закреплены до конца кубка." if locked else "Выберите ровно трёх существ. Опыт остаётся навсегда; боевой уровень можно понизить для лимитов текущей лиги.", 15))
	_page.add_child(_label(_rules_text(), 15))
	var ids: Array = _career.state.owned_creatures.keys()
	ids.sort()
	for value in ids:
		var id := StringName(value)
		var def := CardDB.creature(id)
		if def == null:
			continue
		var box := _section()
		_page.add_child(box)
		var row := HBoxContainer.new()
		box.add_child(row)
		var name_label := _label(def.display_name, 18)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var selected := _team.has(id)
		var select := _button("✓ В команде" if selected else "В команду")
		select.name = "CareerCreature_" + String(id)
		select.toggle_mode = true
		select.set_pressed_no_signal(selected)
		select.disabled = locked or (not selected and _team.size() >= 3)
		select.pressed.connect(_toggle_creature.bind(id))
		row.add_child(select)
		var earned: int = _career.level(id)
		var xp: int = int(_career.state.owned_creatures[value])
		var growth := "максимальный уровень" if earned == int(_career.max_level()) else "%d XP до уровня %d" % [CAREER.xp_for_level(earned + 1) - xp, earned + 1]
		box.add_child(_label("Опыт: %d XP · уровень: %d / %d · %d G · %s" % [xp, earned, int(_career.max_level()), int(_career.power(id)), growth], 15))
		if selected:
			var effective_row := HBoxContainer.new()
			effective_row.add_child(_label("В кубке:", 16))
			var levels := _option()
			levels.name = "CareerLevel_" + String(id)
			levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for level in range(1, mini(earned, int(_career.league_rules().max_level)) + 1):
				levels.add_item("Уровень %d · %d G" % [level, int(_career.power(id, level))], level)
			var effective: int = int(_levels.get(String(id), earned))
			levels.select(maxi(0, levels.get_item_index(effective)))
			levels.disabled = locked
			levels.item_selected.connect(func(index: int) -> void:
				_levels[String(id)] = levels.get_item_id(index)
				_update_footer())
			effective_row.add_child(levels)
			box.add_child(effective_row)


func _build_cards() -> void:
	_page.add_child(_label("Колода · 3 ворот и 3 способности", 20))
	_page.add_child(_label("По одной карте каждого класса. Здесь доступны купленные карты, совместимые со стихией и видами вашей команды. Полные условия открываются кнопкой «Подробнее».", 15))
	if _team.size() != 3:
		_page.add_child(_label("Сначала выберите трёх существ во вкладке «Команда».", 18))
		return
	for cls in CardDB.GATE_CLASSES + CardDB.ABILITY_CLASSES:
		var box := _section()
		_page.add_child(box)
		box.add_child(_label(CLASS_NAMES[cls], 18))
		var row := HBoxContainer.new()
		box.add_child(row)
		var picker := _option()
		picker.name = "CareerCard_" + String(cls)
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var options := _eligible_cards(cls)
		if options.is_empty():
			picker.add_item("Нет подходящих карт — проверьте магазин")
			picker.disabled = true
		else:
			for id in options:
				picker.add_item(CardDB.card(id).display_name)
			var index := options.find(StringName(_picks.get(cls, &"")))
			picker.select(maxi(0, index))
			picker.disabled = _roster_locked()
			picker.item_selected.connect(func(selected: int) -> void:
				_picks[cls] = options[selected]
				_redraw())
		row.add_child(picker)
		var chosen := CardDB.card(StringName(_picks.get(cls, &"")))
		if chosen != null:
			var details := _button("Подробнее")
			details.pressed.connect(_show_card.bind(chosen.id))
			row.add_child(details)
			box.add_child(_label(chosen.full_text(), 16))


func _build_shop() -> void:
	_page.add_child(_label("Магазин · %d кредитов" % int(_career.state.credits), 20))
	_page.add_child(_label("Вы покупаете указанный предмет. Уже купленные карты и существа остаются с вами; опыт получают только участники команды.", 15))
	var shop_locked: bool = _career.cup != null and not _career.cup.completed()
	if shop_locked:
		var notice := _label("Покупки после завершения кубка. Коллекцию и цены можно просматривать сейчас.", 17)
		notice.name = "CareerShopLocked"
		_page.add_child(notice)
	var filter := _option()
	filter.name = "CareerShopFilter"
	for title in ["Существа", "Карты ворот", "Способности"]:
		filter.add_item(title)
	filter.select(_shop_kind)
	filter.item_selected.connect(func(index: int) -> void:
		_shop_kind = index
		_scroll.scroll_vertical = 0
		_redraw())
	_page.add_child(filter)
	var ids: Array[StringName] = CardDB.creatures_of(_element()) if _shop_kind == 0 else (CardDB.arena_ids() if _shop_kind == 1 else CardDB.ability_ids())
	for id in ids:
		if id == CardDB.RARE_SHADOW_ID:
			continue
		var creature := CardDB.creature(id) if _shop_kind == 0 else null
		var card := CardDB.card(id) if _shop_kind != 0 else null
		if card != null and not CardDB.card_fits(card, _element()):
			continue
		var owned := _owned(id)
		var reason := _unlock_reason(id)
		var price: int = _career.price(String(id))
		var box := _section()
		_page.add_child(box)
		var row := HBoxContainer.new()
		box.add_child(row)
		var title := _label(creature.display_name if creature != null else card.display_name, 18)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		if card != null:
			var preview := _button("Подробнее")
			preview.pressed.connect(_show_card.bind(id))
			row.add_child(preview)
		var buy := _button("Куплено" if owned else "Купить · %d кр." % price)
		buy.name = "CareerBuy_" + String(id)
		buy.disabled = owned or shop_locked or not reason.is_empty() or int(_career.state.credits) < price
		buy.tooltip_text = "Покупки после завершения кубка." if shop_locked and not owned else reason
		buy.pressed.connect(_purchase.bind(id))
		row.add_child(buy)
		if creature != null:
			box.add_child(_label("Существо · %s · начальная сила: %d G" % [Attr.display_name(creature.attribute), int(_career.power(id, 1))], 15))
		else:
			box.add_child(_label("%s · %s" % [UiTheme.card_kind(card), card.full_text()], 15))
			var species: StringName = CardEffects.species_lock(card)
			if species != &"" and not CardDB.team_species(_team).has(species):
				box.add_child(_label("Для команды с видом «%s»." % CardDB.species_name(species), 15))
		if not owned:
			if reason.is_empty() and int(_career.state.credits) < price:
				reason = "Не хватает %d кредитов." % (price - int(_career.state.credits))
			if not reason.is_empty():
				box.add_child(_label(reason, 15))


func _build_progress() -> void:
	_page.add_child(_label("Три лиги · ваш путь", 20))
	_page.add_child(_label(str(_career.progress_text()), 17))
	_page.add_child(_label("Кредиты: %d · существ: %d · карт: %d" % [int(_career.state.credits), _career.state.owned_creatures.size(), _career.state.owned_cards.size()], 17))
	for index in range(3):
		var rules: Dictionary = _career.league_rules(index)
		var box := _section()
		_page.add_child(box)
		var state := "Текущая лига" if index == int(_career.state.league) else ("Пройдена" if index < int(_career.state.league) else "Откроется после предыдущей лиги")
		box.add_child(_label("%s · %s" % [str(rules.title), state], 18))
		box.add_child(_label("Боевой уровень ≤ %d · одно существо ≤ %d G · команда ≤ %d G" % [int(rules.max_level), int(rules.max_power), int(rules.max_total)], 15))
	var reward: Dictionary = _career.last_reward
	if not reward.is_empty():
		_page.add_child(_label("Последняя награда: %d кредитов · %d XP" % [int(reward.get("credits", 0)), int(reward.get("xp", 0))], 17))
	_page.add_child(_label("Первая встреча с соперником лиги: победа — 60 кредитов и 50 XP каждому участнику команды; поражение с участием — 15 кредитов и 20 XP. Повторная встреча: победа — 15 кредитов и 12 XP; поражение — без награды. Участие: не меньше двух бросков или одного боя.", 15))
	_page.add_child(_label("Ничья с участием: 25 XP каждому участнику команды, повторная — 6 XP; без кредитов. Завершение каждой лиги: 150 кредитов один раз; первое чемпионство в ней: ещё 150. Следующая лига открывается независимо от места. Прерванный матч награды не даёт.", 15))
	_page.add_child(_label("Цены существ: Грифалон — 400 кредитов, Левиан и Ратник — 650 после первой лиги, Драгнар и Колоссар — 900 после второй. Покупки доступны между кубками. Повторные кубки помогают пополнить коллекцию.", 15))
	_page.add_child(_label("Состав и сила фиксируются при регистрации в кубке. Новые уровни опыта можно использовать со следующего кубка. Повторение кубка доступно после его завершения; для лимита лиги можно понизить боевой уровень, сохранив весь опыт.", 15))


func _update_footer() -> void:
	_extra.hide()
	_action.disabled = false
	if _career.cup != null:
		var done: bool = bool(_career.cup.state.get("completed", false))
		if done:
			_extra.show()
			if _career.can_advance():
				_action.text = "Следующая лига"
			else:
				_action.text = "Карьера завершена"
				_action.disabled = true
			_validation.text = "Кубок завершён. Можно повторить его или перейти дальше." if _career.can_advance() else "Все лиги завершены. Можно повторить последний кубок и развивать коллекцию."
		else:
			_action.text = "Продолжить кубок"
			_validation.text = "Кубок сохранён. Состав и боевые уровни закреплены до его завершения."
		return
	var error: String = _career.deck_error(_team, _ids(CardDB.GATE_CLASSES), _ids(CardDB.ABILITY_CLASSES), _levels)
	var total := 0
	for id in _team:
		total += int(_career.power(id, int(_levels.get(String(id), _career.level(id)))))
	_validation.text = "Команда: %d / 3 · %d G. %s" % [_team.size(), total, error if not error.is_empty() else "Колода готова к регистрации."]
	_action.text = "Зарегистрироваться в кубке"
	_action.disabled = not error.is_empty()


func _activate() -> void:
	if _career == null:
		create_requested.emit(_element_choice.selected, _difficulty_choice.selected)
	elif _career.cup != null:
		if bool(_career.cup.state.get("completed", false)):
			if _career.can_advance():
				advance_requested.emit()
		else:
			continue_requested.emit()
	else:
		var error: String = _career.deck_error(_team, _ids(CardDB.GATE_CLASSES), _ids(CardDB.ABILITY_CLASSES), _levels)
		if not error.is_empty():
			show_error(error)
			return
		registration_requested.emit(_team.duplicate(), _ids(CardDB.GATE_CLASSES), _ids(CardDB.ABILITY_CLASSES), _levels.duplicate())


func _toggle_creature(id: StringName) -> void:
	if _roster_locked():
		return
	if _team.has(id):
		_team.erase(id)
		_levels.erase(String(id))
	elif _team.size() < 3:
		_team.append(id)
		_levels[String(id)] = mini(int(_career.level(id)), int(_career.league_rules().max_level))
	_fix_cards()
	_redraw()


func _set_deck(deck: DeckDef) -> void:
	if deck == null:
		return
	_team.clear()
	_picks.clear()
	_levels.clear()
	for creature in deck.creatures:
		_team.append(creature.id)
		_levels[String(creature.id)] = mini(int(_career.level(creature.id)), int(_career.league_rules().max_level))
	for card in deck.arena + deck.abilities:
		_picks[CardDB.card_class(card)] = card.id


func _fix_cards() -> void:
	for cls in CardDB.GATE_CLASSES + CardDB.ABILITY_CLASSES:
		var options := _eligible_cards(cls)
		if not options.has(StringName(_picks.get(cls, &""))):
			_picks[cls] = options[0] if not options.is_empty() else &""


func _eligible_cards(cls: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	var species := CardDB.team_species(_team)
	for value in _career.state.owned_cards:
		var def := CardDB.card(StringName(value))
		if def != null and CardDB.card_class(def) == cls and CardDB.card_fits(def, _element(), species):
			ids.append(def.id)
	return ids


func _ids(classes: Array[StringName]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for cls in classes:
		var id := StringName(_picks.get(cls, &""))
		if id != &"":
			ids.append(id)
	return ids


func _element() -> int:
	return GameData.ATTR_KEYS.find(str(_career.state.element))


func _roster_locked() -> bool:
	return _career != null and _career.cup != null


func _rules_text() -> String:
	var rules: Dictionary = _career.league_rules()
	return "Лимиты лиги: уровень ≤ %d · существо ≤ %d G · сумма команды ≤ %d G" % [int(rules.max_level), int(rules.max_power), int(rules.max_total)]


func _owned(id: StringName) -> bool:
	return _career.state.owned_creatures.has(String(id)) or _career.state.owned_cards.has(String(id))


func _unlock_reason(id: StringName) -> String:
	var creature := CardDB.creature(id)
	var species: StringName = creature.species if creature != null else &""
	if species == &"" or _career.available_species().has(species):
		return ""
	return "Откроется после второй лиги." if species in [&"dragnar", &"kolossar"] else "Откроется после первой лиги."


func _purchase(id: StringName) -> void:
	var error: int = _career.purchase(String(id))
	_notice = "Куплено: %s" % (CardDB.creature(id).display_name if CardDB.creature(id) != null else CardDB.card(id).display_name) if error == OK else str(_career.last_error)
	_fix_cards()
	_redraw()


func _show_card(id: StringName) -> void:
	var def := CardDB.card(id)
	if def == null:
		return
	var dialog := AcceptDialog.new()
	dialog.title = def.display_name
	dialog.theme = theme
	dialog.ok_button_text = "Закрыть"
	var help := UiTheme.card_help(def)
	dialog.dialog_text = "%s\n\n%s\n\n%s\n\n%s" % [str(help[1]), str(help[4]), str(help[5]), str(help[6])]
	dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.get_label().add_theme_font_size_override("font_size", 16)
	dialog.min_size = Vector2i(560, 240)
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_clamped(Vector2i(680, 300), 0.85)


func _section() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	return box


func _label(value: String, font_size: int = 16) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 40
	button.add_theme_font_size_override("font_size", 16)
	button.focus_mode = Control.FOCUS_ALL
	return button


func _option() -> OptionButton:
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 40
	picker.add_theme_font_size_override("font_size", 16)
	picker.focus_mode = Control.FOCUS_ALL
	picker.fit_to_longest_item = false
	return picker


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
