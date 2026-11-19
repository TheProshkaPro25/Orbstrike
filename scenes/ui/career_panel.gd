class_name CareerPanel
extends Control
## Менеджер локальной карьеры. Здесь только данные и 2D: каталог моделей не затрагивается.

signal create_requested(element: int, difficulty: int)
signal registration_requested(creatures: Array[StringName], gates: Array[StringName], abilities: Array[StringName], levels: Dictionary)
signal continue_requested
signal advance_requested
signal replay_requested
signal exit_requested

const TAB_NAMES := ["01  Команда", "02  Колода", "Магазин", "Путь карьеры"]
const SHOP_KINDS := ["Существа", "Ворота", "Способности"]
const SHOP_TILE_WIDTH := 245
const SHOP_GAP := 12
const SHOP_WARNING := Color(1.0, 0.76, 0.54)
const PORTRAITS := preload("res://scenes/ui/creature_portrait.gd")
const ICONS := preload("res://scenes/element_icon.gd")
const ART := preload("res://scenes/ui/card_artwork.gd")
const CLASS_NAMES := {&"gold": "Ворота стихии", &"silver": "Ворота вида", &"bronze": "Командные ворота", &"red": "Стихийная способность", &"blue": "Усиление", &"green": "Видовая способность"}
const PROFILE := preload("res://data/player_profile.gd")
const CAREER := preload("res://core/career.gd")

class DialogTextScroll extends ScrollContainer:
	func _input(event: InputEvent) -> void:
		if get_window().visible and VisualUtil.scroll_navigation(self, event):
			get_viewport().set_input_as_handled()

var _career: RefCounted
var _team: Array[StringName] = []
var _picks: Dictionary = {}
var _levels: Dictionary = {}
var _tab := 0
var _shop_kind := 0
var _card_kind := 0
var _built := false
var _navigation_generation := 0
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
var _summary: Label
var _starter_preview: HBoxContainer
var _shop_bar: HFlowContainer
var _shop_filters: HBoxContainer
var _shop_balance: Label
var _shop_grid: GridContainer
var _shop_confirmation: ConfirmationDialog


func _ready() -> void:
	_build()
	_redraw()


## null открывает первый шаг; существующее сохранение никогда не удаляется этим экраном.
func display(career: RefCounted, notice: String = "") -> void:
	_close_shop_confirmation()
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
		margins.add_theme_constant_override("margin_" + side, 18)
	add_child(margins)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margins.add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	_head = _label("Карьера", 23)
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_head)
	var help := _button("Как играть в карьеру")
	help.name = "CareerHelp"
	help.pressed.connect(_show_guide)
	heading.add_child(help)
	var back := _button("В меню")
	back.name = "CareerExit"
	back.pressed.connect(func() -> void: exit_requested.emit())
	heading.add_child(back)
	_summary = _label("", 14)
	_summary.autowrap_mode = TextServer.AUTOWRAP_OFF
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_summary.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	layout.add_child(_summary)
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
	_build_shop_bar(layout)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree(): _close_shop_confirmation())
	_scroll = ScrollContainer.new()
	_scroll.name = "CareerScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.resized.connect(_fit_shop_grid)
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
	_validation.add_theme_color_override("font_color", UiTheme.accent())
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


func _redraw(preferred_focus: String = "") -> void:
	_navigation_generation += 1
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_name := String(focused.name) if focused != null and is_ancestor_of(focused) else ""
	if not preferred_focus.is_empty(): focus_name = preferred_focus
	var scroll_position := _scroll.scroll_vertical
	if focused != null and is_ancestor_of(focused): focused.release_focus()
	_shop_grid = null
	_clear(_page)
	_status.text = _notice
	_status.visible = not _notice.is_empty()
	_tabs.visible = _career != null
	_shop_bar.visible = _career != null and _tab == 2
	_extra.hide()
	_action.disabled = false
	if _career == null:
		_head.text = "Начните свой путь"
		_summary.text = "Выберите стихию → получите команду → сыграйте первый кубок"
		_build_onboarding()
		_action.text = "Начать карьеру"
		_validation.text = "Стихия и сложность выбираются один раз. Прогресс сохраняется автоматически."
		_restore_navigation.call_deferred(focus_name, scroll_position, _navigation_generation)
		return
	_head.text = "Карьера  /  " + _career.cup_title()
	var balance_summary := "" if _tab == 2 else "  ·  %d кредитов" % int(_career.state.credits)
	_summary.text = "%s%s  ·  %d существ в коллекции  |  %s" % [Attr.display_name(_element()), balance_summary, _career.state.owned_creatures.size(), str(_career.state.name)]
	_summary.tooltip_text = _summary.text
	for i in _tabs.get_child_count():
		(_tabs.get_child(i) as Button).set_pressed_no_signal(i == _tab)
	match _tab:
		0: _build_team()
		1: _build_cards()
		2: _build_shop()
		3: _build_progress()
	_update_footer()
	_restore_navigation.call_deferred(focus_name, scroll_position, _navigation_generation)


func _restore_navigation(focus_name: String, scroll_position: int, generation: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _navigation_generation or not visible or not is_inside_tree():
		return
	_scroll.scroll_vertical = scroll_position
	if not focus_name.is_empty():
		var control := find_child(focus_name, true, false) as Control
		if control != null and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
			control.grab_focus()
	# ScrollContainer follows focus at the next layout pass. Restore the visible
	# catalog position after that pass rather than following a removed old tile.
	await get_tree().process_frame
	if generation == _navigation_generation:
		_scroll.scroll_vertical = scroll_position


func _switch_tab(index: int) -> void:
	if index != 2: _close_shop_confirmation()
	_tab = index
	_scroll.scroll_vertical = 0
	_redraw()


func _build_onboarding() -> void:
	_page.add_child(_label("1. Выберите стихию команды", 20))
	_element_choice = _option()
	_element_choice.name = "CareerElement"
	_element_choice.hide()
	_page.add_child(_element_choice)
	for i in Attr.COUNT:
		_element_choice.add_item(Attr.display_name(i), i)
	var profile := PROFILE.new()
	profile.load_from()
	_element_choice.select(int(profile.value.get("element", 0)))
	var elements := _grid(6)
	_page.add_child(elements)
	for i in Attr.COUNT:
		var button := _button(Attr.display_name(i))
		button.name = "CareerElementTile%d" % i
		button.icon = ICONS.badge(i)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 38)
		button.custom_minimum_size.y = 64
		button.toggle_mode = true
		button.set_pressed_no_signal(_element_choice.selected == i)
		button.pressed.connect(_choose_element.bind(i))
		elements.add_child(button)
	_page.add_child(_label("Ваша стартовая тройка · все существа одной стихии", 15))
	_starter_preview = HBoxContainer.new()
	_starter_preview.add_theme_constant_override("separation", 12)
	_page.add_child(_starter_preview)
	_update_starter_preview()
	_page.add_child(_label("2. Выберите сложность", 20))
	_difficulty_choice = _option()
	_difficulty_choice.name = "CareerDifficulty"
	_difficulty_choice.hide()
	_page.add_child(_difficulty_choice)
	var difficulties := _grid(3)
	_page.add_child(difficulties)
	var descriptions := ["Учитесь в своём темпе", "Соперник отвечает на карты", "Сочетания карт и сильные ответы"]
	for i in 3:
		_difficulty_choice.add_item(["Новичок", "Боец", "Мастер"][i])
		var button := _button(["Новичок", "Боец", "Мастер"][i] + "\n" + descriptions[i])
		button.name = "CareerDifficultyTile%d" % i
		button.custom_minimum_size.y = 58
		button.add_theme_font_size_override("font_size", 15)
		button.toggle_mode = true
		button.set_pressed_no_signal(i == 1)
		button.pressed.connect(_choose_difficulty.bind(i))
		difficulties.add_child(button)
	_difficulty_choice.select(1)


func _choose_element(index: int) -> void:
	_element_choice.select(index)
	for i in Attr.COUNT:
		(find_child("CareerElementTile%d" % i, true, false) as Button).set_pressed_no_signal(i == index)
	_update_starter_preview()


func _choose_difficulty(index: int) -> void:
	_difficulty_choice.select(index)
	for i in 3:
		(find_child("CareerDifficultyTile%d" % i, true, false) as Button).set_pressed_no_signal(i == index)


func _update_starter_preview() -> void:
	_clear(_starter_preview)
	for species in ["gorgul", "rogozhuk", "klykar"]:
		var def := CardDB.creature(StringName("creature_%s_%s" % [species, GameData.ATTR_KEYS[_element_choice.selected]]))
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_starter_preview.add_child(row)
		row.add_child(_creature_portrait(def.id, Vector2(64, 64)))
		row.add_child(_label(def.display_name, 16))


func _build_team() -> void:
	var locked := _roster_locked()
	_page.add_child(_label("Ваша тройка  ·  %d / 3" % _team.size(), 20))
	_page.add_child(_label("Состав закреплён до конца кубка." if locked else "Нажмите «Убрать», чтобы освободить место. Затем выберите существо из коллекции.", 14))
	var grid := _grid(3)
	grid.name = "CareerSquad"
	_page.add_child(grid)
	for slot in 3:
		if slot < _team.size():
			grid.add_child(_creature_tile(_team[slot], true))
		else:
			var empty := _tile()
			grid.add_child(empty)
			empty.get_node("Content").add_child(_label("+\nСвободное место\nВыберите существо ниже", 20))
	var total := _team_power()
	var rules: Dictionary = _career.league_rules()
	var power_row := HBoxContainer.new()
	_page.add_child(power_row)
	power_row.add_child(_label("Сила команды  %d / %d G" % [total, int(rules.max_total)], 16))
	var meter := _meter(total, int(rules.max_total))
	meter.custom_minimum_size.x = 180
	power_row.add_child(meter)
	var limits := _button("Лимиты лиги")
	limits.pressed.connect(func() -> void: _text_dialog("Лимиты лиги", _rules_text() + "\n\nБоевой уровень можно понизить под портретом. Заработанный опыт сохраняется."))
	power_row.add_child(limits)
	var bench: Array[StringName] = []
	for value in _career.state.owned_creatures:
		if not _team.has(StringName(value)):
			bench.append(StringName(value))
	if not bench.is_empty():
		_page.add_child(_label("Коллекция · выберите замену", 19))
		var collection := _grid(3)
		_page.add_child(collection)
		for id in bench:
			collection.add_child(_creature_tile(id, false))
	elif not locked:
		var shop := _button("Расширить команду → Магазин")
		shop.name = "CareerOpenShop"
		shop.pressed.connect(_switch_tab.bind(2))
		_page.add_child(shop)


func _creature_tile(id: StringName, selected: bool) -> PanelContainer:
	var box := _tile(selected)
	var def := CardDB.creature(id)
	var top := HBoxContainer.new()
	box.get_node("Content").add_child(top)
	var name_label := _label(def.display_name, 18)
	name_label.custom_minimum_size.y = 28
	top.add_child(name_label)
	var earned: int = _career.level(id)
	var effective: int = int(_levels.get(String(id), mini(earned, int(_career.league_rules().max_level))))
	var portrait := _creature_portrait(id, Vector2(72, 72))
	portrait.name = "CareerPortrait_" + String(id)
	box.get_node("Content").add_child(portrait)
	var stat := _label("%d G   ·   Уровень %d" % [int(_career.power(id, effective if selected else earned)), earned], 16)
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.get_node("Content").add_child(stat)
	var xp: int = int(_career.state.owned_creatures[String(id)])
	var base: int = CAREER.xp_for_level(earned)
	var goal: int = CAREER.xp_for_level(earned + 1)
	box.get_node("Content").add_child(_meter(1 if earned == int(_career.max_level()) else xp - base, maxi(1, goal - base)))
	box.get_node("Content").add_child(_label("Максимальный уровень" if earned == int(_career.max_level()) else "%d / %d XP до уровня %d" % [xp - base, goal - base, earned + 1], 13))
	var row := HBoxContainer.new()
	box.get_node("Content").add_child(row)
	if selected:
		var levels := _option()
		levels.name = "CareerLevel_" + String(id)
		levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for level in range(1, mini(earned, int(_career.league_rules().max_level)) + 1):
			levels.add_item("Бой: ур. %d · %d G" % [level, int(_career.power(id, level))], level)
		levels.select(maxi(0, levels.get_item_index(effective)))
		levels.disabled = _roster_locked()
		levels.item_selected.connect(func(index: int) -> void:
			_levels[String(id)] = levels.get_item_id(index)
			_redraw())
		row.add_child(levels)
	var select := _button("Убрать" if selected else "В команду")
	select.name = "CareerCreature_" + String(id)
	select.disabled = _roster_locked() or (not selected and _team.size() >= 3)
	select.tooltip_text = "Сначала уберите одного участника из тройки." if not selected and _team.size() >= 3 else ""
	select.pressed.connect(_toggle_creature.bind(id))
	row.add_child(select)
	return box


func _build_cards() -> void:
	var heading := HBoxContainer.new()
	_page.add_child(heading)
	heading.add_child(_label("Ваша колода  ·  6 / 6" if _ids(CardDB.GATE_CLASSES).size() + _ids(CardDB.ABILITY_CLASSES).size() == 6 else "Соберите колоду", 20))
	for i in 2:
		var category := _button(["Ворота · 3", "Способности · 3"][i])
		category.name = "CareerDeckKind%d" % i
		category.toggle_mode = true
		category.set_pressed_no_signal(_card_kind == i)
		category.pressed.connect(func() -> void:
			_card_kind = i
			_scroll.scroll_vertical = 0
			_redraw())
		heading.add_child(category)
	_page.add_child(_label("Три класса ворот + три класса способностей. Нажмите «Заменить», чтобы увидеть доступные варианты.", 14))
	if _team.size() != 3:
		var team := _button("Сначала соберите тройку → Команда")
		team.pressed.connect(_switch_tab.bind(0))
		_page.add_child(team)
		return
	var grid := _grid(3)
	_page.add_child(grid)
	for cls in (CardDB.GATE_CLASSES if _card_kind == 0 else CardDB.ABILITY_CLASSES):
		var box := _tile()
		grid.add_child(box)
		box.get_node("Content").add_child(_label(CLASS_NAMES[cls], 14))
		var chosen := CardDB.card(StringName(_picks.get(cls, &"")))
		if chosen == null:
			box.get_node("Content").add_child(_label("Нет подходящей карты", 18))
		else:
			_card_summary(box.get_node("Content"), chosen)
		var row := HBoxContainer.new()
		box.get_node("Content").add_child(row)
		var replace := _button("Заменить")
		replace.name = "CareerCard_" + String(cls)
		replace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		replace.disabled = _roster_locked() or _eligible_cards(cls).is_empty()
		replace.pressed.connect(_choose_card.bind(cls))
		row.add_child(replace)
		if chosen != null:
			var details := _button("Условия")
			details.pressed.connect(_show_card.bind(chosen.id))
			row.add_child(details)


func _card_summary(box: VBoxContainer, card: CardDef) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_image(ART.texture_for(card), Vector2(56, 56)))
	var title := _label(card.display_name, 18)
	title.custom_minimum_size.y = 48
	row.add_child(title)
	var description := _label(card.text, 15)
	description.custom_minimum_size.y = 54
	box.add_child(description)


func _choose_card(cls: StringName) -> void:
	if _roster_locked(): return
	var dialog := _new_dialog(CLASS_NAMES[cls])
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 290)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for id in _eligible_cards(cls):
		var card := CardDB.card(id)
		var tile := _tile(id == _picks.get(cls))
		list.add_child(tile)
		_card_summary(tile.get_node("Content"), card)
		var row := HBoxContainer.new()
		tile.get_node("Content").add_child(row)
		var use := _button("✓ Выбрана" if id == _picks.get(cls) else "Выбрать")
		use.name = "CareerPick_" + String(id)
		use.pressed.connect(func() -> void:
			_picks[cls] = id
			dialog.hide()
			dialog.queue_free()
			_redraw())
		row.add_child(use)
		var details := _button("Все условия")
		details.pressed.connect(_show_card.bind(id))
		row.add_child(details)
	dialog.popup_centered_clamped(Vector2i(660, 390), 0.9)


func _build_shop_bar(layout: VBoxContainer) -> void:
	_shop_bar = HFlowContainer.new()
	_shop_bar.name = "CareerShopBar"
	_shop_bar.add_theme_constant_override("h_separation", SHOP_GAP)
	_shop_bar.add_theme_constant_override("v_separation", 6)
	_shop_bar.hide()
	layout.add_child(_shop_bar)
	_shop_filters = HBoxContainer.new()
	_shop_filters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_filters.add_theme_constant_override("separation", 8)
	_shop_bar.add_child(_shop_filters)
	for i in SHOP_KINDS.size():
		var button := _button(SHOP_KINDS[i])
		button.name = "CareerShopKind%d" % i
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_switch_shop_kind.bind(i))
		_shop_filters.add_child(button)
	var wallet := PanelContainer.new()
	wallet.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.panel_color().lightened(0.05), UiTheme.accent_dim(), 1, 6, 10))
	_shop_bar.add_child(wallet)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	wallet.add_child(row)
	var caption := _label("На счёте", 15)
	caption.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(caption)
	_shop_balance = _label("", 22)
	_shop_balance.name = "CareerShopBalance"
	_shop_balance.autowrap_mode = TextServer.AUTOWRAP_OFF
	_shop_balance.add_theme_font_override("font", UiTheme.heading_font())
	_shop_balance.add_theme_color_override("font_color", UiTheme.GOLD)
	row.add_child(_shop_balance)


func _switch_shop_kind(index: int) -> void:
	_shop_kind = index
	_scroll.scroll_vertical = 0
	_redraw()


func _build_shop() -> void:
	_shop_balance.text = "%d кр." % int(_career.state.credits)
	for i in _shop_filters.get_child_count():
		(_shop_filters.get_child(i) as Button).set_pressed_no_signal(i == _shop_kind)
	if _shop_locked():
		var notice := _label("Во время кубка каталог открыт для просмотра. Покупки доступны после завершения кубка.", 15)
		notice.name = "CareerShopLocked"
		notice.add_theme_color_override("font_color", SHOP_WARNING)
		_page.add_child(notice)
	_shop_grid = _grid(1)
	_shop_grid.name = "CareerShopCatalog"
	_shop_grid.add_theme_constant_override("h_separation", SHOP_GAP)
	_shop_grid.add_theme_constant_override("v_separation", SHOP_GAP)
	_page.add_child(_shop_grid)
	_fit_shop_grid()
	var ids: Array[StringName] = CardDB.creatures_of(_element()) if _shop_kind == 0 else (CardDB.arena_ids() if _shop_kind == 1 else CardDB.ability_ids())
	ids.sort_custom(_shop_before)
	for id in ids:
		var price: int = _career.price(String(id))
		if price > 0 and id != CardDB.RARE_SHADOW_ID:
			_shop_grid.add_child(_shop_tile(id, price))
	if _shop_grid.get_child_count() == 0:
		_page.add_child(_label("В этой категории нет предложений для вашей стихии.", 16))


func _fit_shop_grid() -> void:
	if not is_instance_valid(_shop_grid):
		return
	var scrollbar := _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var width := _scroll.size.x - scrollbar
	var columns := clampi(floori((width + SHOP_GAP) / (SHOP_TILE_WIDTH + SHOP_GAP)), 1, 4)
	if _shop_grid.columns != columns:
		_shop_grid.columns = columns


func _shop_tile(id: StringName, price: int) -> PanelContainer:
	var card := CardDB.card(id)
	var box := _tile()
	var content := box.get_node("Content") as VBoxContainer
	content.add_theme_constant_override("separation", 7)
	content.add_child(_shop_art(id, card, 112))
	var kind := _label(Attr.display_name(_element()) if card == null else str(CLASS_NAMES[CardDB.card_class(card)]), 14)
	kind.add_theme_color_override("font_color", UiTheme.accent())
	content.add_child(kind)
	var title := _label(_shop_item_name(id), 20)
	title.add_theme_font_override("font", UiTheme.heading_font())
	content.add_child(title)
	var description := _label("%d G · уровень 1" % int(_career.power(id, 1)) if card == null else card.text, 15)
	description.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	description.max_lines_visible = 3
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(description)
	if card != null:
		var species := CardEffects.species_lock(card)
		if species != &"":
			var requirement := _label("Для этой карты нужен боец вида «%s»" % CardDB.species_name(species), 14)
			requirement.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
			content.add_child(requirement)
	var owned := _owned(id)
	var reason := _shop_block_reason(id, price, owned)
	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 8)
	content.add_child(price_row)
	var cost := _label("%d кр." % price, 21)
	cost.autowrap_mode = TextServer.AUTOWRAP_OFF
	cost.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cost.add_theme_color_override("font_color", UiTheme.TEXT_DIM if owned else UiTheme.GOLD)
	cost.add_theme_font_override("font", UiTheme.heading_font())
	price_row.add_child(cost)
	var status := _label("Можно купить" if reason.is_empty() else reason, 14)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_theme_color_override("font_color", UiTheme.accent() if reason.is_empty() else (UiTheme.TEXT_DIM if owned else SHOP_WARNING))
	price_row.add_child(status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	if card != null:
		var details := _button("Условия")
		details.name = "CareerShopDetails_" + String(id)
		details.pressed.connect(_show_card.bind(id, true))
		actions.add_child(details)
	var buy := _button("Куплено" if owned else "Купить")
	buy.name = "CareerBuy_" + String(id)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.disabled = not reason.is_empty()
	buy.tooltip_text = reason if buy.disabled else "Купить за %d кр." % price
	if not buy.disabled:
		buy.add_theme_stylebox_override("normal", UiTheme.box(Color(0.06, 0.25, 0.27), UiTheme.accent_dim(), 1, 3, 10))
		buy.add_theme_stylebox_override("hover", UiTheme.box(Color(0.09, 0.34, 0.36), UiTheme.accent(), 1, 3, 10))
	buy.pressed.connect(_confirm_shop_purchase.bind(id, buy))
	actions.add_child(buy)
	return box


func _shop_art(id: StringName, card: CardDef, height: int) -> PanelContainer:
	var art := PanelContainer.new()
	var tint: Color = VisualUtil.attr_color(_element()) if card == null else UiTheme.card_colors(card)[0]
	var wash := Color(0.04, 0.08, 0.12).lerp(tint, 0.35)
	var style := UiTheme.box(wash, tint.darkened(0.45), 1, 5, 4)
	style.set_meta("device_styled", true)
	art.add_theme_stylebox_override("panel", style)
	if card == null:
		art.add_child(_creature_portrait(id, Vector2(0, height)))
	else:
		var texture := ART.texture_for(card)
		art.add_child(_image(texture if texture != null else ICONS.badge(_element()), Vector2(0, height)))
	return art


func _shop_locked() -> bool:
	return _career.cup != null and not _career.cup.completed()


func _shop_block_reason(id: StringName, price: int, owned: bool) -> String:
	if owned:
		return "В коллекции"
	var unlock := _unlock_reason(id)
	if _shop_locked():
		return "После завершения кубка" + ("\n" + unlock if not unlock.is_empty() else "")
	if not unlock.is_empty():
		return unlock
	var missing := price - int(_career.state.credits)
	return "Не хватает %d кр." % missing if missing > 0 else ""


func _shop_item_name(id: StringName) -> String:
	var creature := CardDB.creature(id)
	var card := CardDB.card(id)
	if creature != null:
		return creature.display_name
	return card.display_name if card != null else String(id)


func _confirm_shop_purchase(id: StringName, origin: Button) -> void:
	if _career == null or _tab != 2 or origin.disabled or is_instance_valid(_shop_confirmation):
		return
	var price: int = _career.price(String(id))
	var reason := _shop_block_reason(id, price, _owned(id))
	if price <= 0 or not reason.is_empty():
		_notice = "Покупка недоступна. %s" % reason if not reason.is_empty() else "Предложение недоступно."
		_redraw("CareerShopKind%d" % _shop_kind)
		return
	var balance: int = int(_career.state.credits)
	var dialog := _new_dialog("Подтверждение покупки", true) as ConfirmationDialog
	_shop_confirmation = dialog
	dialog.name = "CareerPurchaseConfirmation"
	dialog.ok_button_text = "Купить"
	dialog.cancel_button_text = "Отмена"
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	dialog.add_child(content)
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 12)
	content.add_child(item)
	var art := _shop_art(id, CardDB.card(id), 66)
	art.custom_minimum_size.x = 80
	item.add_child(art)
	var item_name := _label(_shop_item_name(id), 22)
	item_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	item_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	item_name.tooltip_text = item_name.text
	item_name.mouse_filter = Control.MOUSE_FILTER_PASS
	item_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item_name.add_theme_font_override("font", UiTheme.heading_font())
	item.add_child(item_name)
	var amounts := _grid(2)
	content.add_child(amounts)
	var captions := ["На счёте", "Стоимость", "После покупки"]
	var values := [balance, price, balance - price]
	for i in captions.size():
		var caption := _label(captions[i], 16)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		amounts.add_child(caption)
		var amount := _label("%d кр." % values[i], 18)
		amount.autowrap_mode = TextServer.AUTOWRAP_OFF
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.add_theme_color_override("font_color", UiTheme.GOLD if i == 1 else UiTheme.TEXT)
		amounts.add_child(amount)
	dialog.confirmed.connect(func() -> void:
		if _shop_confirmation != dialog:
			return
		_shop_confirmation = null
		_purchase(id, "CareerShopKind%d" % _shop_kind))
	dialog.canceled.connect(func() -> void:
		if _shop_confirmation != dialog:
			return
		_shop_confirmation = null
		if is_instance_valid(origin) and origin.is_visible_in_tree():
			origin.grab_focus.call_deferred())
	dialog.popup_centered_clamped(Vector2i(410, 255), 0.9)
	dialog.get_cancel_button().grab_focus.call_deferred()


func _close_shop_confirmation() -> void:
	if is_instance_valid(_shop_confirmation):
		var dialog := _shop_confirmation
		_shop_confirmation = null
		dialog.hide()
		dialog.queue_free()


func _shop_before(a: StringName, b: StringName) -> bool:
	var a_rank := 2 if not _unlock_reason(a).is_empty() else (1 if _owned(a) else 0)
	var b_rank := 2 if not _unlock_reason(b).is_empty() else (1 if _owned(b) else 0)
	if a_rank != b_rank: return a_rank < b_rank
	var a_price: int = _career.price(String(a))
	var b_price: int = _career.price(String(b))
	return String(a) < String(b) if a_price == b_price else a_price < b_price


func _build_progress() -> void:
	_page.add_child(_label("Три кубка — одна карьера", 20))
	_page.add_child(_label(str(_career.progress_text()), 15))
	var grid := _grid(3)
	_page.add_child(grid)
	for index in 3:
		var rules: Dictionary = _career.league_rules(index)
		var current := index == int(_career.state.league)
		var available: bool = index == int(_career.state.league) + 1 and _career.can_advance()
		var cleared: bool = _career._cleared_leagues().has(index)
		var box := _tile(current)
		grid.add_child(box)
		box.get_node("Content").add_child(_label("%02d   %s" % [index + 1, "✓ Пройдена" if cleared else ("● Вы здесь" if current else ("Доступна →" if available else "Закрыта"))], 16))
		box.get_node("Content").add_child(_label(str(rules.title), 22))
		box.get_node("Content").add_child(_label("%d G\nлимит команды" % int(rules.max_total), 20))
		box.get_node("Content").add_child(_label("До уровня %d · до %d G на существо" % [int(rules.max_level), int(rules.max_power)], 14))
		box.get_node("Content").add_child(_label("150 кр. за первое завершение\n+150 кр. за первое чемпионство", 14))
	_page.add_child(_label("Развивайте команду в каждом матче", 19))
	var rewards := _grid(3)
	_page.add_child(rewards)
	for text in ["Победа\n60 кр. + 50 XP", "Поражение с участием\n15 кр. + 20 XP", "Ничья с участием\n25 XP"]:
		var box := _tile()
		rewards.add_child(box)
		box.get_node("Content").add_child(_label(text, 17))
	_page.add_child(_label("Награды за первую встречу. XP получает каждый участник вашей тройки.", 14))
	var reward: Dictionary = _career.last_reward
	if not reward.is_empty():
		_page.add_child(_label("Последняя награда: +%d кр. · +%d XP" % [int(reward.get("credits", 0)), int(reward.get("xp", 0))], 17))
	var help := _button("Повторные встречи, опыт и все правила наград")
	help.pressed.connect(_show_guide)
	_page.add_child(help)


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
		total += int(_career.power(id, int(_levels.get(String(id), mini(int(_career.level(id)), int(_career.league_rules().max_level))))))
	_validation.text = "Команда: %d / 3 · %d / %d G. %s" % [_team.size(), total, int(_career.league_rules().max_total), error if not error.is_empty() else "Колода готова к регистрации."]
	_action.text = "Начать кубок →"
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


func _purchase(id: StringName, preferred_focus: String = "") -> void:
	var price: int = _career.price(String(id))
	var error: int = _career.purchase(String(id))
	if error == OK:
		_notice = "Куплено «%s» за %d кр. На счёте %d кр." % [_shop_item_name(id), price, int(_career.state.credits)]
	else:
		_notice = "Покупка не состоялась. %s" % str(_career.last_error)
	_fix_cards()
	_redraw(preferred_focus)


func _show_card(id: StringName, shop_details: bool = false) -> void:
	var def := CardDB.card(id)
	if def == null:
		return
	var help := UiTheme.card_help(def)
	_text_dialog(def.display_name, "%s\n\n%s\n\n%s\n\n%s" % [str(help[1]), str(help[4]), str(help[5]), str(help[6])], shop_details)


func _new_dialog(title: String, confirm: bool = false) -> AcceptDialog:
	var dialog: AcceptDialog = ConfirmationDialog.new() if confirm else AcceptDialog.new()
	dialog.title = title
	dialog.theme = theme
	dialog.ok_button_text = "Закрыть"
	dialog.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.panel_color(), UiTheme.accent_dim(), 1, 8, 16))
	dialog.add_theme_stylebox_override("embedded_border", UiTheme.box(UiTheme.panel_color(), UiTheme.accent_dim(), 1, 8, 8))
	dialog.add_theme_color_override("title_color", UiTheme.accent())
	var host: Node = self
	for window in find_children("*", "AcceptDialog", true, false):
		if window.visible: host = window
	host.add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	return dialog


func _text_dialog(title: String, text: String, shop_details: bool = false) -> void:
	var dialog := _new_dialog(title)
	var scroll := DialogTextScroll.new()
	if not shop_details: scroll.custom_minimum_size = Vector2(600, 290)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var label := _label(text, 17)
	if not shop_details: label.custom_minimum_size.x = 560
	scroll.add_child(label)
	dialog.popup_centered_clamped(Vector2i(530, 320) if shop_details else Vector2i(660, 390), 0.9)


func _show_guide() -> void:
	_text_dialog("Как устроена карьера", "СОБЕРИТЕ ТРОЙКУ\nВыберите 3 существ одной стихии. Под портретом задайте боевой уровень в пределах лиги: заработанный опыт не теряется. Для замены сначала уберите одного участника.\n\nПОДГОТОВЬТЕ КОЛОДУ\nПо одной карте каждого из шести классов: 3 ворот и 3 способности. «Заменить» показывает только купленные совместимые карты. «Условия» открывают полное описание.\n\nИГРАЙТЕ КУБОК\nСостав, карты и боевые уровни фиксируются при старте. Новые уровни можно использовать со следующего кубка. Покупки доступны между кубками. Каждая следующая лига открывается после завершения предыдущей независимо от места.\n\nПОЛУЧАЙТЕ НАГРАДЫ\nПервая встреча с соперником лиги: победа — 60 кредитов и 50 XP каждому участнику команды; поражение с участием — 15 кредитов и 20 XP; ничья с участием — 25 XP без кредитов. Участие: не меньше 2 бросков или 1 боя.\n\nПовторная встреча: победа — 15 кредитов и 12 XP; поражение — без награды; ничья с участием — 6 XP без кредитов. Прерванный матч награды не даёт. За первое завершение лиги — 150 кредитов; за первое чемпионство — ещё 150.\n\nРАСШИРЯЙТЕ КОЛЛЕКЦИЮ\nГрифалон — 400 кредитов. После первой лиги: Левиан и Ратник по 650. После второй: Драгнар и Колоссар по 900. Повторные кубки помогают получить кредиты и опыт. Сохранение автоматическое и отдельное от остальных режимов.")


func _team_power() -> int:
	var total := 0
	for id in _team:
		total += int(_career.power(id, int(_levels.get(String(id), mini(int(_career.level(id)), int(_career.league_rules().max_level))))))
	return total


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.child_entered_tree.connect(func(node: Node) -> void:
		if node is Control: node.size_flags_horizontal = Control.SIZE_EXPAND_FILL)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	return grid


func _tile(selected: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.panel_color().lightened(0.035), UiTheme.accent() if selected else UiTheme.accent_dim().darkened(0.4), 1, 8, 10))
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	return panel


func _creature_portrait(id: StringName, dimensions: Vector2) -> TextureRect:
	var portrait := _image(PORTRAITS.presentation_texture(id), dimensions)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return portrait


func _image(texture: Texture2D, dimensions: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.custom_minimum_size = dimensions
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


func _meter(value: int, maximum: int) -> ProgressBar:
	var meter := ProgressBar.new()
	meter.max_value = maximum
	meter.value = value
	meter.show_percentage = false
	meter.custom_minimum_size.y = 5
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.add_theme_stylebox_override("background", UiTheme.box(Color(0.04, 0.065, 0.1), Color.TRANSPARENT, 0, 3, 0))
	meter.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.accent(), Color.TRANSPARENT, 0, 3, 0))
	return meter


func _label(value: String, font_size: int = 16) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
