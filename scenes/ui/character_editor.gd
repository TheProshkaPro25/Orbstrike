class_name CharacterEditor
extends VrmPreview
## The accepted VRM foundation is now the normal editor, with an isolated draft.
var store := PlayerProfile.new()
var draft: Dictionary
var saved: Dictionary
var name_field: LineEdit
var selectors: Dictionary = {}
var save_button: Button
var status: Label
var confirm: ConfirmationDialog
var close_after_save := false
const CATALOGS := [preload("res://assets/avatars/editor/catalog_0.png"), preload("res://assets/avatars/editor/catalog_1.png")]
const MOTIONS := ["idle", "throw", "card_throw", "command", "gate", "victory", "defeat"]
const MOTION_LABELS := ["Ожидание", "Бросок сферы", "Бросок карты", "Способность", "Открытие ворот", "Победа", "Поражение"]
## Keep the criticised side-part ID10 available to existing profiles/manual selection,
## but do not introduce it through automatic outfit/random presets.
const RANDOM_HAIR_STYLES: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
var categories: Dictionary = {}
var category_buttons: Dictionary = {}
var gallery_buttons: Dictionary = {}
var gallery_labels: Dictionary = {}
var motion_select: OptionButton
var play_button: Button
var speed_select: OptionButton
var repeat_button: CheckButton
var timeline: HSlider
var time_label: Label
var preview_motion := "idle"
var preview_time := 0.0
var preview_playing := true
var preview_speed := 1.0
var preview_repeat := true

func _create_avatar() -> VrmAvatar:
	var fighter := VrmFighter.new()
	fighter.set_process(false)
	return fighter

func _options_width() -> float:
	return 350.0

func _process(delta: float) -> void:
	if avatar == null or timeline == null or not preview_playing: return
	var duration := _motion_duration()
	preview_time += delta * preview_speed
	if preview_time >= duration:
		if preview_repeat: preview_time = fposmod(preview_time, duration)
		else:
			preview_time = duration
			_set_playing(false)
	_sample_preview()

func _motion_duration() -> float:
	return 2.5 if preview_motion == "idle" else VrmFighter.DURATIONS[preview_motion]

func _sample_preview() -> void:
	var fighter := avatar as VrmFighter
	fighter.sample_motion(preview_time)
	timeline.set_value_no_signal(preview_time)
	time_label.text = "%.1f / %.1f с" % [preview_time, _motion_duration()]

func _set_playing(value: bool) -> void:
	if value and preview_time >= _motion_duration(): _start_motion(motion_select.selected)
	preview_playing = value
	play_button.text = "Пауза" if value else "Продолжить"

func _start_motion(index: int) -> void:
	motion_select.select(index)
	preview_motion = MOTIONS[index]
	preview_time = 0.0
	var fighter := avatar as VrmFighter
	if preview_motion == "idle": fighter.reset_motion()
	else: fighter.play_motion(preview_motion)
	if preview_motion == "command": fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]), 0)
	_restore_expression()
	timeline.max_value = _motion_duration()
	_sample_preview()

func _restore_expression() -> void:
	if expression_select != null and expression_select.selected >= 0:
		avatar.set_expression(expression_select.get_item_metadata(expression_select.selected))

func set_face_view(value: bool) -> void:
	super.set_face_view(value)
	if value and avatar.skeleton != null:
		avatar.skeleton.force_update_all_bone_transforms()
		var head := avatar.skeleton.find_bone("Head")
		if head >= 0:
			var target: Vector3 = avatar.skeleton.global_transform * avatar.skeleton.get_bone_global_pose(head).origin
			target.y += .09 * avatar.actor.scale.y
			camera.global_position = target + Vector3(0, 0, .96 * avatar.actor.scale.y)
			camera.look_at(target)
	elif not value:
		camera.position.z *= 1.22

func _show_category(key: String) -> void:
	if options_scroll != null: options_scroll.scroll_vertical = 0
	if camera != null:
		if key in ["hair", "face"]: set_face_view(true)
		elif key in ["clothes", "motions"]: set_face_view(false)
	for category in categories:
		categories[category].visible = category == key
		category_buttons[category].button_pressed = category == key

func _make_gallery(parent: VBoxContainer, key: String, count: int) -> void:
	var selected_label := _label(parent, "")
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gallery_labels[key] = selected_label
	var grid := GridContainer.new()
	grid.columns = 3
	parent.add_child(grid)
	var buttons: Array = []
	for index in count:
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(96, 130)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.text = str(index + 1)
		button.pressed.connect(_select.bind(index, key))
		grid.add_child(button)
		buttons.append(button)
	gallery_buttons[key] = buttons

func _refresh_galleries() -> void:
	if gallery_buttons.is_empty(): return
	for key in gallery_buttons:
		gallery_labels[key].text = "Выбрано: " + selectors[key].get_item_text(draft[key])
		for index in gallery_buttons[key].size():
			var button: Button = gallery_buttons[key][index]
			var atlas := AtlasTexture.new()
			atlas.atlas = CATALOGS[draft.vrm_model]
			var tile: int = index + (VrmParts.HAIR_STYLE_COUNT if key == "vrm_clothes" else 0)
			atlas.region = Rect2((tile % 5) * 160, (tile / 5) * 192, 160, 192)
			button.icon = atlas
			button.visible = key != "vrm_clothes" or index < VrmParts.BODY[draft.vrm_model].size()
			button.button_pressed = index == draft[key]
			button.tooltip_text = selectors[key].get_item_text(index)


func _ready() -> void:
	store.load_from()
	saved = store.value.duplicate(true)
	draft = saved.duplicate(true)
	super._ready()
	avatar.set_process(false)
	_apply(saved)
	status.text = store.notice if not store.notice.is_empty() else "Выберите образ. Внешность не влияет на силу бойца."
	name_field.grab_focus()

func _title_text() -> String:
	return "МОЙ ПЕРСОНАЖ"

func _build_options_header(panel: VBoxContainer) -> void:
	var tabs := GridContainer.new()
	tabs.columns = 3
	panel.add_child(tabs)
	for entry in [["Образ", "image"], ["Лицо", "face"], ["Волосы", "hair"], ["Одежда", "clothes"], ["Детали", "details"], ["Движения", "motions"]]:
		var button := Button.new()
		button.text = entry[0]
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_show_category.bind(entry[1]))
		tabs.add_child(button)
		category_buttons[entry[1]] = button

func _build_options(options: VBoxContainer) -> void:
	for key in ["image", "face", "hair", "clothes", "details", "motions"]:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 8)
		options.add_child(section)
		categories[key] = section
	var image: VBoxContainer = categories.image
	_label(image,"Имя бойца")
	name_field = LineEdit.new()
	name_field.max_length = 24
	name_field.text = draft.name
	name_field.text_changed.connect(func(text: String) -> void: draft.name = text)
	image.add_child(name_field)
	_label(image,"Основа персонажа")
	model_select = OptionButton.new()
	for text in ["Юноша · Sakurada","Девушка · Vita"]: model_select.add_item(text)
	model_select.item_selected.connect(select_model)
	image.add_child(model_select)
	_button(image,"Уличный образ",_street_preset)
	_button(image,"Спортивный образ",_sport_preset)
	for spec in [
		["vrm_style","Причёска",["Исходная","Острые пряди","Хвосты с ушками","Боб с чёлкой","Альтернативная чёлка","Взъерошенные","Асимметричная чёлка","Короткие пряди","Каре с пробором","Высокий хвост","Боковой пробор"],"hair"],
		["vrm_clothes","Костюм",["Комплект 1","Комплект 2","Комплект 3","Комплект 4","Комплект 5","Комплект 6","Комплект 7","Комплект 8"],"clothes"],
		["vrm_denim","Джинсы",DenimWardrobe.NAMES,"clothes"],
		["vrm_case","Футляр для сфер",["Без футляра","Три сферы · для бомбера"],"details"],
		["vrm_eye_shape","Форма глаз",["Обычная","Строже","Мягче"],"face"],
		["vrm_brows","Брови",["Обычные","Строгие","Приподнятые"],"face"],
		["vrm_mouth","Линия рта",["Обычная","Мягкая улыбка","Сдержанная"],"face"],
		["vrm_hair","Цвет волос",["Исходный","Каштановый","Чёрный","Золотистый","Серебристый","Медный"],"hair"],
		["vrm_eyes","Цвет глаз",["Исходный","Синий","Зелёный","Рубиновый","Карий","Фиолетовый"],"face"],
		["vrm_skin","Тон кожи",["Исходный","Тёплый","Золотистый","Смуглый"],"face"],
		["vrm_outfit","Палитра костюма",["Исходная","Бордовая","Синяя","Изумрудная","Фиолетовая"],"clothes"],
		["vrm_height","Рост",["Ниже","Средний","Выше"],"details"]
	]:
		var section: VBoxContainer = categories[spec[3]]
		_label(section,spec[1])
		var select := OptionButton.new()
		for text in spec[2]: select.add_item(text)
		select.item_selected.connect(_select.bind(spec[0]))
		section.add_child(select)
		selectors[spec[0]] = select
		if spec[0] in ["vrm_style", "vrm_clothes"]:
			select.hide()
			_make_gallery(section,spec[0],spec[2].size())
	var face: VBoxContainer = categories.face
	_label(face,"Выражение для просмотра")
	expression_select = OptionButton.new()
	expression_select.item_selected.connect(func(index: int) -> void: avatar.set_expression(expression_select.get_item_metadata(index)))
	face.add_child(expression_select)
	_label(image,"Свет для просмотра")
	light_select = OptionButton.new()
	for text in ["Студийный","Тёплый","Холодный"]: light_select.add_item(text)
	light_select.item_selected.connect(set_lighting)
	image.add_child(light_select)
	caption = _label(image,"Внешность не влияет на силу бойца. Выражение и свет используются только для просмотра.")
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size",16)
	_build_motion_controls(categories.motions)
	_show_category("image")

func _build_motion_controls(section: VBoxContainer) -> void:
	_label(section,"Движение для просмотра")
	motion_select = OptionButton.new()
	for label in MOTION_LABELS: motion_select.add_item(label)
	motion_select.item_selected.connect(_start_motion)
	section.add_child(motion_select)
	var controls := HBoxContainer.new()
	section.add_child(controls)
	play_button = _button(controls,"Пауза",func() -> void: _set_playing(not preview_playing))
	_button(controls,"Заново",func() -> void: _start_motion(motion_select.selected))
	_label(section,"Скорость")
	speed_select = OptionButton.new()
	for label in ["0,5×", "1×", "1,5×"]: speed_select.add_item(label)
	speed_select.select(1)
	speed_select.item_selected.connect(func(index: int) -> void: preview_speed = [0.5, 1.0, 1.5][index])
	section.add_child(speed_select)
	repeat_button = CheckButton.new()
	repeat_button.text = "Повторять"
	repeat_button.button_pressed = true
	repeat_button.toggled.connect(func(value: bool) -> void: preview_repeat = value)
	section.add_child(repeat_button)
	timeline = HSlider.new()
	timeline.min_value = 0
	timeline.max_value = 2.5
	timeline.step = 0.01
	timeline.value_changed.connect(func(value: float) -> void:
		_set_playing(false)
		preview_time = value
		_sample_preview())
	section.add_child(timeline)
	time_label = _label(section,"0.0 / 2.5 с")

func _build_extra_actions(stack: VBoxContainer) -> void:
	status = _label(stack,"")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size",16)
	var actions := HBoxContainer.new()
	stack.add_child(actions)
	_button(actions,"Случайный образ",_randomize)
	_button(actions,"Отменить изменения",func() -> void: _apply(saved))
	_button(actions,"Сбросить",func() -> void: _apply(PlayerProfile.DEFAULT))
	save_button = _button(actions,"Сохранить",save_profile)
	save_button.disabled = not store.writable
	confirm = ConfirmationDialog.new()
	confirm.title = "Несохранённые изменения"
	confirm.dialog_text = "Сохранить новый образ перед выходом?"
	confirm.ok_button_text = "Сохранить"
	confirm.cancel_button_text = "Продолжить"
	confirm.add_button("Отбросить",false,"discard")
	confirm.confirmed.connect(func() -> void:
		close_after_save = true
		save_profile())
	confirm.custom_action.connect(func(_action: StringName) -> void: _close())
	add_child(confirm)

func select_model(index: int) -> void:
	var expression = expression_select.get_item_metadata(expression_select.selected) if expression_select.selected >= 0 else "RESET"
	var previous_model: int = draft.vrm_model
	if index != previous_model and draft.vrm_clothes == VrmParts.SPORT_IDS[previous_model]:
		draft.vrm_clothes = VrmParts.SPORT_IDS[index]
	draft.vrm_model = index
	draft = PlayerProfile.normalized(draft)
	for item in selectors.vrm_clothes.item_count:
		selectors.vrm_clothes.set_item_disabled(item,item >= VrmParts.BODY[index].size())
	selectors.vrm_clothes.select(draft.vrm_clothes)
	var outfits: Array = ["Школьный","Худи","Короткое худи","Удлинённая куртка","Контрастное худи","Бомбер","Спортивный костюм","—"] if index == 0 else ["Сценический","Платье-рубашка","Летнее платье","Короткое худи","Удлинённая куртка","Контрастное худи","Бомбер","Спортивный костюм"]
	for item in outfits.size(): selectors.vrm_clothes.set_item_text(item,outfits[item])
	selectors.vrm_style.set_item_text(4,"Каре с украшениями" if index == 0 else "Мягкая чёлка")
	selectors.vrm_denim.disabled = not VrmParts.supports_denim(index,draft.vrm_clothes)
	selectors.vrm_denim.tooltip_text = "Джинсы недоступны с этим костюмом. Для спортивного образа выбор запоминается."
	selectors.vrm_denim.select(draft.vrm_denim)
	selectors.vrm_case.disabled = not VrmParts.supports_case(index,draft.vrm_clothes)
	selectors.vrm_case.tooltip_text = "Футляр крепится к поясу бомбера. Выбор запоминается при смене одежды."
	avatar.apply_profile(draft)
	model_select.select(index)
	_update_expressions()
	for item in expression_select.item_count:
		if expression_select.get_item_metadata(item) == expression: expression_select.select(item)
	_refresh_galleries()
	_start_motion(motion_select.selected)
	set_face_view(face_view)

func _select(index: int,key: String) -> void:
	draft[key] = index
	if key == "vrm_clothes":
		select_model(draft.vrm_model)
		return
	selectors[key].select(index)
	avatar.apply_profile(draft)
	_refresh_galleries()
	_start_motion(motion_select.selected)
	if key == "vrm_height": set_face_view(face_view)

func _apply(value: Dictionary) -> void:
	draft = PlayerProfile.normalized(value)
	name_field.text = draft.name
	for key in selectors: selectors[key].select(draft[key])
	select_model(draft.vrm_model)
	_restore_expression()
	status.text = "Изменения в предпросмотре. Нажмите «Сохранить», чтобы применить."

func _street_preset() -> void:
	var value := draft.duplicate(true)
	value.vrm_style = 9
	value.vrm_clothes = VrmParts.BOMBER_IDS[value.vrm_model]
	value.vrm_case = 1
	_apply(value)
	set_face_view(false)

func _sport_preset() -> void:
	var value := draft.duplicate(true)
	value.vrm_clothes = VrmParts.SPORT_IDS[value.vrm_model]
	_apply(value)
	set_face_view(false)

func _randomize() -> void:
	var value := draft.duplicate(true)
	for key in PlayerProfile.LIMITS:
		if key.begins_with("vrm_") and key != "vrm_style": value[key] = randi() % PlayerProfile.LIMITS[key]
	value.vrm_style = RANDOM_HAIR_STYLES.pick_random()
	value.vrm_clothes = randi()%VrmParts.BODY[value.vrm_model].size()
	_apply(value)

func save_profile() -> void:
	var error := store.save_to(draft)
	if error != OK:
		status.text = "Не удалось сохранить образ (%s). Изменения остаются в редакторе." % error_string(error)
		close_after_save = false
		return
	saved = store.value.duplicate(true)
	draft = saved.duplicate(true)
	name_field.text = draft.name
	status.text = "Образ сохранён."
	if close_after_save: _close()

func request_close() -> void:
	if draft != saved: confirm.popup_centered()
	else: _close()

func close() -> void:
	request_close()

func _close() -> void:
	super.close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if confirm.visible: confirm.hide()
		else: request_close()
		get_viewport().set_input_as_handled()
