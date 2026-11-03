class_name VrmPreview
extends Control
signal closed
var options_scroll: ScrollContainer
var viewport: SubViewport
var camera: Camera3D
var avatar: VrmAvatar
var model_select: OptionButton
var expression_select: OptionButton
var light_select: OptionButton
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var environment: Environment
var caption: Label
var turn := 0.0
var face_view := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color("101723")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,16)
	add_child(margin)
	var stack := VBoxContainer.new()
	margin.add_child(stack)
	var title := Label.new()
	title.text = _title_text()
	title.add_theme_font_size_override("font_size",26)
	title.add_theme_color_override("font_color",UiTheme.GOLD)
	stack.add_child(title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(row)
	var preview := SubViewportContainer.new()
	preview.stretch = true
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.gui_input.connect(_preview_input)
	row.add_child(preview)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	preview.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var env_node := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("354356")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dbe3f1")
	environment.ambient_light_energy = .30
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = environment
	world.add_child(env_node)
	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-25,-30,0)
	key_light.light_energy = .75
	world.add_child(key_light)
	fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-15,140,0)
	fill_light.light_energy = .15
	world.add_child(fill_light)
	avatar = _create_avatar()
	world.add_child(avatar)
	avatar.select_model(0)
	camera = Camera3D.new()
	camera.fov = 30
	world.add_child(camera)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size.x = _options_width()
	row.add_child(panel)
	_build_options_header(panel)
	var scroll := ScrollContainer.new()
	options_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var options := VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.custom_minimum_size.x = 260
	options.add_theme_constant_override("separation",10)
	scroll.add_child(options)
	_build_options(options)
	var actions := HBoxContainer.new()
	stack.add_child(actions)
	_button(actions,"↶",func() -> void: rotate_model(-.35))
	_button(actions,"↷",func() -> void: rotate_model(.35))
	_button(actions,"Лицо",func() -> void: set_face_view(true))
	_button(actions,"Весь рост",func() -> void: set_face_view(false))
	var back := _button(actions,"Назад",close)
	back.grab_focus()
	_build_extra_actions(stack)
	_update_expressions()
	set_face_view(false)

func _title_text() -> String:
	return "АНИМЕ-МОДЕЛИ · ПРЕДПРОСМОТР"

func _create_avatar() -> VrmAvatar:
	return VrmAvatar.new()

func _options_width() -> float:
	return 280.0

func _build_options_header(_panel: VBoxContainer) -> void:
	pass

func _build_extra_actions(_stack: VBoxContainer) -> void:
	pass

func _build_options(options: VBoxContainer) -> void:
	_label(options,"Готовая модель")
	model_select = OptionButton.new()
	for text in VrmAvatar.TITLES: model_select.add_item(text)
	model_select.item_selected.connect(select_model)
	options.add_child(model_select)
	_label(options,"Выражение лица")
	expression_select = OptionButton.new()
	expression_select.item_selected.connect(func(index: int) -> void: avatar.set_expression(expression_select.get_item_metadata(index)))
	options.add_child(expression_select)
	_label(options,"Освещение")
	light_select = OptionButton.new()
	for text in ["Студийное","Тёплое","Холодное"]: light_select.add_item(text)
	light_select.item_selected.connect(set_lighting)
	options.add_child(light_select)
	caption = _label(options,"""Модели pixiv

Сравните лицо, пропорции,
волосы и одежду.

Предпросмотр не меняет
вашего сохранённого бойца.""")
	caption.add_theme_font_size_override("font_size",16)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.x = 260

func _label(parent: Node,text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _button(parent: Node,text: String,action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func select_model(index: int) -> void:
	avatar.select_model(index)
	model_select.select(index)
	_update_expressions()
	set_face_view(face_view)

func _update_expressions() -> void:
	expression_select.clear()
	var labels := {"RESET":"Спокойное","happy":"Улыбка","angry":"Серьёзное","sad":"Грусть","blink":"Закрытые глаза","relaxed":"Расслабленное","Surprised":"Удивление"}
	for expression in labels:
		if not expression in avatar.expression_names(): continue
		expression_select.add_item(labels[expression])
		expression_select.set_item_metadata(expression_select.item_count-1,expression)
	expression_select.select(0)

func set_face_view(value: bool) -> void:
	face_view = value
	var height := 1.42
	if avatar.skeleton != null:
		var head := avatar.skeleton.find_bone("Head")
		if head >= 0: height = avatar.skeleton.get_bone_global_rest(head).origin.y + .09
	height *= avatar.actor.scale.y
	var full_height := height + .20 * avatar.actor.scale.y
	var distance := full_height / (2.0*tan(deg_to_rad(camera.fov)*.5)) * 1.10
	camera.position = Vector3(0,height,.96 * avatar.actor.scale.y) if value else Vector3(0,full_height*.51,distance)
	camera.look_at(Vector3(0,height,0) if value else Vector3(0,full_height*.50,0))

func set_lighting(index: int) -> void:
	light_select.select(index)
	key_light.light_color = [Color.WHITE,Color("ffd0a1"),Color("a2c8ff")][index]
	fill_light.light_color = [Color("dce8ff"),Color("b0c9f5"),Color("d9c7f0")][index]

func rotate_model(amount: float) -> void:
	turn += amount
	avatar.rotation.y = turn

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT: rotate_model(event.relative.x*.01)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: camera.position.z = maxf(.45,camera.position.z*.9)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera.position.z = minf(4.5,camera.position.z*1.1)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	closed.emit()
	queue_free()
