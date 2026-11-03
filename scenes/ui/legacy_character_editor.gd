class_name LegacyCharacterEditor
extends Control
signal closed
var store := PlayerProfile.new()
var draft: Dictionary
var saved: Dictionary
var avatar: FighterAvatar
var viewport: SubViewport
var camera: Camera3D
var name_field: LineEdit
var status: Label
var save_button: Button
var selectors: Dictionary = {}
var confirm: ConfirmationDialog
var preview: SubViewportContainer
var turn := 0.0
var close_after_save := false
var vrm_preview: VrmPreview

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	store.load_from()
	saved = store.value.duplicate(true)
	draft = saved.duplicate(true)
	var bg := ColorRect.new()
	bg.color = Color("101723")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,16)
	add_child(margin)
	var stack := VBoxContainer.new()
	margin.add_child(stack)
	var title := Label.new()
	title.text = "МОЙ ПЕРСОНАЖ"
	title.add_theme_color_override("font_color",UiTheme.GOLD)
	title.add_theme_font_size_override("font_size",26)
	stack.add_child(title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",16)
	stack.add_child(row)
	preview = SubViewportContainer.new()
	preview.stretch = true
	preview.custom_minimum_size = Vector2(160,160)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.gui_input.connect(_preview_input)
	row.add_child(preview)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.size = Vector2i(320,320)
	viewport.msaa_3d = Viewport.MSAA_4X
	preview.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("344459")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b7c5d9")
	env.ambient_light_energy = .25
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30,-30,0)
	light.light_color = Color("fff4e8")
	light.light_energy = .85
	light.shadow_enabled = true
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15,140,0)
	fill.light_color = Color("a3c7ed")
	fill.light_energy = .25
	world.add_child(fill)
	# A quiet studio plinth anchors the feet without obscuring the silhouette.
	for level in 2:
		var plinth := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = .48 if level == 0 else .465
		cylinder.bottom_radius = cylinder.top_radius
		cylinder.height = .014 if level == 0 else .024
		cylinder.radial_segments = 64
		plinth.mesh = cylinder
		plinth.position.y = -.035 if level == 0 else -.016
		var plinth_material := StandardMaterial3D.new()
		plinth_material.albedo_color = Color("6389a0") if level == 0 else Color("263344")
		plinth_material.roughness = 1.0
		plinth.material_override = plinth_material
		world.add_child(plinth)
	avatar = FighterAvatar.new()
	world.add_child(avatar)
	avatar.build(draft)
	camera = Camera3D.new()
	camera.fov = 32
	world.add_child(camera)
	_camera_full()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 300
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var options := VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_theme_constant_override("separation",8)
	scroll.add_child(options)
	var label := Label.new()
	label.text = "Имя бойца"
	options.add_child(label)
	name_field = LineEdit.new()
	name_field.max_length = 24
	name_field.text = draft.name
	name_field.text_changed.connect(func(text: String) -> void: draft.name = text)
	options.add_child(name_field)
	for spec in [["body","Телосложение",["Сбалансированное","Стройное","Атлетичное"]],["face","Лицо",["Спокойное","Узкое","Широкое"]],["hair","Причёска",["Взъерошенная","С хвостом","Набок"]],["skin","Тон кожи",["Фарфор","Светлый","Золотистый","Смуглый","Бронзовый","Тёмный"]],["hair_color","Цвет волос",["Каштановый","Угольный","Пепельный","Пшеничный","Медный","Сине-чёрный"]],["eyes","Цвет глаз",["Рубин","Зелёный","Карий","Серый","Янтарный","Ореховый"]],["jacket","Цвет куртки",["Алый","Индиго","Нефрит","Сумрак"]],["element","Акцент стихии",["Огонь","Вода","Земля","Ветер","Свет","Тьма"]]]:
		var caption := Label.new()
		caption.text = spec[1]
		options.add_child(caption)
		var select := OptionButton.new()
		for text in spec[2]: select.add_item(text)
		select.select(draft[spec[0]])
		select.item_selected.connect(_select.bind(spec[0]))
		options.add_child(select)
		selectors[spec[0]] = select
	var camera_row := HBoxContainer.new()
	stack.add_child(camera_row)
	_button(camera_row,"↶",func() -> void: _rotate(-.35))
	_button(camera_row,"↷",func() -> void: _rotate(.35))
	_button(camera_row,"Лицо",_camera_face)
	_button(camera_row,"Весь рост",_camera_full)
	_button(camera_row,"Случайно",_randomize)
	_button(camera_row,"Аниме-модели",_open_vrm_preview)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = store.notice if not store.notice.is_empty() else "Внешность не влияет на силу. Мышь: поворот и колесо для приближения."
	stack.add_child(status)
	var actions := HBoxContainer.new()
	stack.add_child(actions)
	_button(actions,"Назад",request_close)
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
	name_field.grab_focus()

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _select(index: int, key: String) -> void:
	draft[key] = index
	if selectors.has(key): selectors[key].select(index)
	avatar.build(draft)

func _apply(value: Dictionary) -> void:
	draft = value.duplicate(true)
	name_field.text = draft.name
	for key in selectors: selectors[key].select(draft[key])
	avatar.build(draft)
	status.text = "Изменения в предпросмотре. Нажмите «Сохранить», чтобы применить."

func _randomize() -> void:
	var value := draft.duplicate(true)
	for key in PlayerProfile.LIMITS: value[key] = randi() % PlayerProfile.LIMITS[key]
	_apply(value)

func save_profile() -> void:
	var error := store.save_to(draft)
	if error != OK:
		status.text = "Не удалось сохранить профиль (%s). Изменения остаются в редакторе." % error_string(error)
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

func _close() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(vrm_preview): return
	if event.is_action_pressed("ui_cancel"):
		if confirm.visible: confirm.hide()
		else: request_close()
		get_viewport().set_input_as_handled()

func _rotate(amount: float) -> void:
	turn += amount
	avatar.rotation.y = turn

func _camera_full() -> void:
	camera.position = Vector3(0,1.02,3.55)
	camera.look_at(Vector3(0,.94,0))

func _camera_face() -> void:
	camera.position = Vector3(0,1.48,1.20)
	camera.look_at(Vector3(0,1.48,0))

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_rotate(event.relative.x * .01)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: camera.position.z = maxf(.48,camera.position.z*.9)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera.position.z = minf(4,camera.position.z*1.1)

func _open_vrm_preview() -> void:
	if is_instance_valid(vrm_preview): return
	vrm_preview = VrmPreview.new()
	get_parent().add_child(vrm_preview)
	hide()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vrm_preview.closed.connect(func() -> void:
		show()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		name_field.grab_focus())
