extends Control

signal closed

const CREATURE_MOTIONS := {
	&"idle": "Ожидание", &"sphere": "Сфера", &"reveal": "Раскрытие сферы",
	&"stance": "Боевая стойка", &"roar": "Рёв", &"attack": "Атака",
	&"counter": "Контратака", &"brace": "Защита", &"hit": "Попадание",
	&"ability": "Импульс способности",
}
const INITIAL_ORBIT := Vector2(0.34, 0.13)
const REPEAT_RECOVERY := 0.22
const RATNIK_SOURCE := "res://assets/creatures_cmp/ratnik_light_pixal3d_1024_source.glb"
const RATNIK_COMPARISON := {
	"Pixal3D 1024 (пересобранная сетка)": "res://assets/creatures_cmp/ratnik_light_pixal3d_1024.glb",
	"UniForge3D Shape-1024": "res://assets/creatures_cmp/ratnik_light_uniforge3d.glb",
}
const CURRENT_RATNIK := &"creature_ratnik_light"
const COMPARISON_MOTIONS := [&"idle", &"stance", &"roar", &"attack", &"hit"]

enum Category { CREATURE, FIGHTER, RATNIK_COMPARISON }

var _catalog: GameLoading
var _arena: Arena
var _ball: CreatureBall
var _fighter: VrmFighter
var _world: Node3D
var _sample: Node3D
var _camera: Camera3D
var _viewport: SubViewport
var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _key_light: DirectionalLight3D
var _arena_light_energy := 0.9
var _orbit := INITIAL_ORBIT
var _zoom := 1.0
var _profiles: Array[Dictionary] = []
var _creatures_by_species: Dictionary[StringName, Array] = {}
var _map: OptionButton
var _category: OptionButton
var _species: OptionButton
var _element: OptionButton
var _element_field: VBoxContainer
var _people: OptionButton
var _variant: OptionButton
var _source_hint: Label
var _source_neutral: CheckButton
var _source_material: StandardMaterial3D
var _comparison: Node3D
var _comparison_current: CreatureBall
var _comparison_frame := Transform3D.IDENTITY
var _comparison_bounds: AABB
var _comparison_variants: Dictionary[String, Node3D] = {}
var _comparison_players: Array[AnimationPlayer] = []
var _comparison_is_static := false
var _motion: OptionButton
var _pause: Button
var _replay: Button
var _repeat: CheckButton
var _repeat_elapsed := 0.0
var _status: Label
var _closing := false


func _ready() -> void:
	name = "AnimationRoom"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color("09171e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_build_ui()
	_catalog = GameLoading.i()
	if not _catalog.ready_to_play:
		_report_unavailable("Каталог игры недоступен. Войдите через обычный экран загрузки.")
		_map.disabled = true
		_category.disabled = true
		_species.disabled = true
		_element.disabled = true
		return
	_catalog.release_parked_game()
	_select_arena(ArenaLocations.current())
	_select_category(Category.CREATURE)
	_map.grab_focus()


func _process(delta: float) -> void:
	if _comparison_is_static: return
	if is_instance_valid(_comparison) and _sample.process_mode != Node.PROCESS_MODE_DISABLED:
		for player in _comparison_players:
			if player.is_playing(): player.advance(delta)
	if _repeat.disabled or not _repeat.button_pressed:
		_repeat_elapsed = 0.0
		return
	if _sample.process_mode == Node.PROCESS_MODE_DISABLED: return
	var playing := true
	if is_instance_valid(_fighter):
		playing = _fighter.motion != "idle"
	elif is_instance_valid(_ball) and _ball._anim != null:
		playing = _ball._anim._action != &"" or (_ball._open_tween != null and _ball._open_tween.is_running())
	elif is_instance_valid(_comparison):
		playing = _comparison_players[0].is_playing()
	if playing:
		_repeat_elapsed = 0.0
		return
	# Let the normal blend back to idle finish before starting another gesture.
	_repeat_elapsed += delta
	if _repeat_elapsed >= REPEAT_RECOVERY: _replay_motion(false)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := _label(header, "Комната анимаций", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", UiTheme.accent())
	_button(header, "В главное меню", close)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	_build_controls(body)
	_build_stage(body)


func _build_controls(body: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 302
	body.add_child(panel)
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 12)
	panel.add_child(fields)
	_map = _option(fields, "Арена", _select_arena)
	for data in ArenaLocations.LOCATIONS:
		_map.add_item(data.name)
	_category = _option(fields, "Тип модели", _select_category)
	_category.add_item("Существо")
	_category.add_item("Боец")
	_species = _option(fields, "Существо", _select_species)
	_element = _option(fields, "Стихия", _select_creature)
	_element_field = _element.get_parent() as VBoxContainer
	_people = _option(fields, "Боец", _select_fighter)
	_people.get_parent().hide()
	_variant = _option(fields, "Версия Ратника Света", _show_comparison_variant)
	_variant.add_theme_font_size_override("font_size", 16)
	_variant.get_parent().hide()
	_add_comparison_variant("Pixal3D 1024 (исходная сетка)", RATNIK_SOURCE)
	for title: String in RATNIK_COMPARISON:
		_add_comparison_variant(title, RATNIK_COMPARISON[title])
	if _variant.item_count > 0:
		_category.add_item("Сравнение Ратника Света")
	_variant.add_item("Текущая игровая (TRELLIS.2)")
	_variant.set_item_metadata(_variant.item_count - 1, String(CURRENT_RATNIK))
	_source_hint = _label(fields, "Статичный осмотр исходной сетки", 16)
	_source_hint.hide()
	_source_neutral = CheckButton.new()
	_source_neutral.text = "Нейтральный материал"
	_source_neutral.toggled.connect(_toggle_source_material)
	fields.add_child(_source_neutral)
	_source_neutral.hide()
	_populate_models()
	_motion = _option(fields, "Анимация", _select_motion)
	var playback := HBoxContainer.new()
	fields.add_child(playback)
	_replay = _button(playback, "Повторить", _replay_motion)
	_pause = _button(playback, "Пауза", _toggle_pause)
	_replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_repeat = CheckButton.new()
	_repeat.text = "Повторять автоматически"
	_repeat.tooltip_text = "Воспроизводить выбранное действие по кругу"
	_repeat.disabled = true
	fields.add_child(_repeat)
	_status = _label(fields, "", 16)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", UiTheme.GOLD)
	_status.hide()


func _build_stage(body: HBoxContainer) -> void:
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(layout)
	var preview := SubViewportContainer.new()
	preview.stretch = true
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.gui_input.connect(_camera_input)
	layout.add_child(preview)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.gui_disable_input = true
	preview.add_child(_viewport)
	preview.resized.connect(_frame_camera)
	_world = Node3D.new()
	_viewport.add_child(_world)
	_sample = Node3D.new()
	_world.add_child(_sample)
	_camera = Camera3D.new()
	_camera.fov = 38.0
	_camera.near = 0.01
	_camera.far = 1600
	_world.add_child(_camera)
	_build_lighting()
	var camera_bar := HBoxContainer.new()
	layout.add_child(camera_bar)
	var hint := _label(camera_bar, "Перетащите кадр, чтобы повернуть камеру. Колесо меняет масштаб.", 15)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(camera_bar, "Влево", _turn_camera.bind(-PI / 6.0))
	_button(camera_bar, "Вправо", _turn_camera.bind(PI / 6.0))
	_button(camera_bar, "−", _zoom_camera.bind(1.18)).tooltip_text = "Отдалить камеру"
	_button(camera_bar, "+", _zoom_camera.bind(1.0 / 1.18)).tooltip_text = "Приблизить камеру"
	_button(camera_bar, "Сбросить вид", _reset_camera)


func _build_lighting() -> void:
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = _sky_material
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.fog_enabled = true
	_environment.fog_density = 0.0025
	var lighting := WorldEnvironment.new()
	lighting.environment = _environment
	_world.add_child(lighting)
	_key_light = DirectionalLight3D.new()
	_key_light.rotation_degrees = Vector3(-35.0, 28.0, 0.0)
	_key_light.shadow_enabled = true
	_key_light.shadow_opacity = 0.62
	_world.add_child(_key_light)
	GraphicsSettings.apply_world(_viewport, _environment, _key_light)


func _populate_models() -> void:
	var player := PlayerProfile.new()
	player.load_from()
	_profiles.append(player.value)
	_people.add_item("Мой персонаж")
	for index in VrmAvatar.TITLES.size():
		_profiles.append(PlayerProfile.normalized({"vrm_model": index}))
		_people.add_item(VrmAvatar.TITLES[index])
	for index in PlayerProfile.NPC_PRESETS.size():
		var profile := PlayerProfile.npc_profile(index + 1)
		_profiles.append(profile)
		_people.add_item(profile.name)
	for definition in CreatureModels.catalog_defs():
		if not _creatures_by_species.has(definition.species):
			_creatures_by_species[definition.species] = []
		_creatures_by_species[definition.species].append(definition)
	for species in GameData.ALL_SPECIES:
		var id := StringName(species.id)
		if _creatures_by_species.has(id):
			_add_species(species.name, id)
	_add_species("Ликорез", &"likorez")


func _add_species(title: String, species: StringName) -> void:
	_species.add_item(title)
	_species.set_item_metadata(_species.item_count - 1, species)


func _select_arena(index: int) -> void:
	if is_instance_valid(_arena) and _arena.location_id == index: return
	var replacement := _catalog.take_arena(index)
	if replacement == null:
		if is_instance_valid(_arena): _map.select(_arena.location_id)
		_report_unavailable("Эта арена сейчас недоступна.")
		return
	if is_instance_valid(_arena): _catalog.return_arena(_arena)
	_arena = replacement
	_arena.reparent(_world, false)
	_arena.apply_quality()
	_map.select(index)
	var data := ArenaLocations.definition(index)
	_sky_material.sky_top_color = data.zenith
	_sky_material.sky_horizon_color = data.horizon
	_sky_material.ground_horizon_color = data.horizon
	_environment.ambient_light_color = Color(data.ambient).lerp(Color.WHITE, 0.55)
	_environment.fog_light_color = data.fog
	_key_light.light_color = Color(data.sun).lerp(Color.WHITE, 0.45)
	_arena_light_energy = 0.9 if index == 0 else float(data.sun_energy) * 0.66
	_update_subject_lighting()
	_status.hide()


func _select_category(index: int) -> void:
	var creatures := index == Category.CREATURE
	_species.get_parent().visible = creatures
	_element_field.visible = creatures
	_people.get_parent().visible = index == Category.FIGHTER
	_variant.get_parent().visible = index == Category.RATNIK_COMPARISON
	_source_hint.hide()
	_source_neutral.hide()
	_motion.get_parent().show()
	_motion.clear()
	if creatures:
		for id in CREATURE_MOTIONS:
			_add_motion(CREATURE_MOTIONS[id], id)
		_motion.select(0)
		_select_species(_species.selected)
	elif index == Category.FIGHTER:
		for motion_index in CharacterEditor.MOTIONS.size():
			_add_motion(CharacterEditor.MOTION_LABELS[motion_index], StringName(CharacterEditor.MOTIONS[motion_index]))
		_motion.select(0)
		_select_fighter(_people.selected)
	else:
		_add_motion("Осмотр", &"inspect")
		for id: StringName in COMPARISON_MOTIONS:
			_add_motion(CREATURE_MOTIONS[id], id)
		_motion.select(0)
		_select_comparison()


func _add_motion(title: String, id: StringName) -> void:
	_motion.add_item(title)
	_motion.set_item_metadata(_motion.item_count - 1, id)


func _select_species(index: int) -> void:
	var attribute := _ball.def.attribute if is_instance_valid(_ball) else -1
	var definitions: Array = _creatures_by_species[_species.get_item_metadata(index)]
	_element.clear()
	var selected := 0
	for definition: CreatureDef in definitions:
		_element.add_item(VisualUtil.attr_name(definition.attribute))
		var entry := _element.item_count - 1
		_element.set_item_metadata(entry, definition.id)
		if definition.attribute == attribute: selected = entry
	_element.select(selected)
	_select_creature(selected)


func _select_creature(index: int) -> void:
	_release_model()
	var id: StringName = _element.get_item_metadata(index)
	_ball = _catalog.take_ball(id, -1, Vector3.UP * CreatureBall.RADIUS)
	if _ball == null:
		_report_unavailable("Эта модель сейчас недоступна.")
		return
	_ball.reparent(_sample, false)
	_update_subject_lighting()
	_motion.disabled = false
	_status.hide()
	_select_motion(_motion.selected)


func _select_fighter(index: int) -> void:
	_release_model()
	_fighter = _catalog.take_fighter(_profiles[index])
	if _fighter == null:
		_report_unavailable("Этот боец сейчас недоступен.")
		return
	_fighter.reparent(_sample, false)
	_update_subject_lighting()
	_motion.disabled = false
	_status.hide()
	_select_motion(_motion.selected)


func _select_comparison() -> void:
	_release_model()
	_comparison = Node3D.new()
	_sample.add_child(_comparison)
	_comparison_current = _catalog.take_ball(CURRENT_RATNIK, -1, Vector3.UP * CreatureBall.RADIUS)
	if _comparison_current == null:
		_release_model()
		_report_unavailable("Игровая модель Ратника Света сейчас недоступна.")
		return
	_comparison_current.reparent(_comparison, false)
	_comparison_current.show_preview_form(true)
	var animator := _comparison_current._anim
	# Sample authored clips on the same clock while keeping the prepared materials and cloth.
	animator.set_process(false)
	_comparison_players.append(animator._player)
	_comparison_variants[String(CURRENT_RATNIK)] = _comparison_current
	var normalization := animator._model.get_child(0) as Node3D
	_comparison_frame = _comparison.global_transform.affine_inverse() * normalization.global_transform
	_comparison_bounds = CreatureModels.world_aabb(animator._model)
	for index in _variant.item_count:
		var path: String = _variant.get_item_metadata(index)
		if path == RATNIK_SOURCE or path == String(CURRENT_RATNIK): continue
		var model := _load_comparison_variant(path)
		if model == null: continue
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player == null or not COMPARISON_MOTIONS.all(player.has_animation):
			_comparison_variants[path] = null
			model.free()
			continue
		player.get_animation(&"idle").loop_mode = Animation.LOOP_LINEAR
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_comparison_players.append(player)
		_comparison_bounds = _comparison_bounds.merge(CreatureModels.world_aabb(model))
	_show_comparison_variant(_variant.selected)
	_update_subject_lighting()
	_select_motion(_motion.selected)


func _add_comparison_variant(title: String, path: String) -> void:
	if not ResourceLoader.exists(path, "PackedScene"): return
	_variant.add_item(title)
	_variant.set_item_metadata(_variant.item_count - 1, path)


func _load_comparison_variant(path: String) -> Node3D:
	var scene := load(path) as PackedScene
	var instance := scene.instantiate() if scene != null else null
	var model := instance as Node3D
	if model != null:
		_comparison.add_child(model)
		model.transform = _comparison_frame * model.transform
		_apply_comparison_vertex_colors(model)
	elif instance != null:
		instance.free()
	_comparison_variants[path] = model
	return model


func _apply_comparison_vertex_colors(model: Node3D) -> void:
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := instance.mesh as ArrayMesh
		if mesh == null: continue
		for surface in mesh.get_surface_count():
			if (mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR) == 0: continue
			var material := instance.get_active_material(surface) as StandardMaterial3D
			if material == null or material.vertex_color_use_as_albedo: continue
			# The importer can keep COLOR_0 but leave it disabled on some surfaces.
			var colored := material.duplicate() as StandardMaterial3D
			colored.vertex_color_use_as_albedo = true
			instance.set_surface_override_material(surface, colored)


func _show_comparison_variant(index: int) -> void:
	if not is_instance_valid(_comparison): return
	var id: String = _variant.get_item_metadata(index)
	_comparison_is_static = id == RATNIK_SOURCE
	if _comparison_is_static and not _comparison_variants.has(id):
		_load_comparison_variant(id)
		_toggle_source_material(_source_neutral.button_pressed)
	for key: String in _comparison_variants:
		var model: Node3D = _comparison_variants[key]
		if is_instance_valid(model): model.visible = key == id
	_source_hint.visible = _comparison_is_static
	_source_neutral.visible = _comparison_is_static
	_motion.get_parent().visible = not _comparison_is_static
	_motion.disabled = _comparison_is_static
	if _comparison_variants.get(id) == null:
		_report_unavailable("Выбранная модель сейчас недоступна.")
	else:
		_status.hide()
		_set_paused(_sample.process_mode == Node.PROCESS_MODE_DISABLED)


func _toggle_source_material(neutral: bool) -> void:
	var source: Node3D = _comparison_variants.get(RATNIK_SOURCE)
	if not is_instance_valid(source): return
	if neutral and _source_material == null:
		_source_material = StandardMaterial3D.new()
		_source_material.albedo_color = Color("bcb7ad")
		_source_material.roughness = 0.8
		_source_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for instance: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		instance.material_override = _source_material if neutral else null


func _select_motion(_index: int) -> void:
	_replay_motion()
	_frame_camera()


func _update_subject_lighting() -> void:
	# MToon fighter materials need less direct light than creatures on the same stage.
	var fighter := is_instance_valid(_fighter)
	_environment.ambient_light_energy = 0.37 if fighter else 0.58
	_key_light.light_energy = 0.60 if fighter else _arena_light_energy


func _replay_motion(reset_model: bool = true) -> void:
	if _motion.selected < 0: return
	var id: StringName = _motion.get_item_metadata(_motion.selected)
	_clear_effects()
	_set_paused(false)
	_repeat_elapsed = 0.0
	if is_instance_valid(_fighter):
		if reset_model: _fighter.reset_motion()
		_fighter.play_motion(String(id))
		if id == &"command":
			_fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]), _fighter.appearance_profile.element)
		_fighter.sample_motion(0)
	elif is_instance_valid(_ball):
		var revealed := id not in [&"sphere", &"reveal"]
		if reset_model or not revealed: _ball.show_preview_form(revealed)
		var attack_target := Vector3.BACK * _ball.figure_height()
		match id:
			&"reveal": _ball.open_animated()
			&"stance": _ball._anim.appear()
			&"roar": _ball.roar()
			&"attack": _ball.lunge(attack_target)
			&"counter": _ball.counter_lunge(attack_target)
			&"brace": _ball.brace()
			&"hit": _ball.take_hit(Color("b8dcff"))
			&"ability": _ball.ability_pulse()
	elif is_instance_valid(_comparison):
		for player in _comparison_players:
			player.stop()
			if id != &"inspect":
				player.play(id)
				player.advance(0.0)
		if id == &"inspect":
			for skeleton: Skeleton3D in _comparison.find_children("*", "Skeleton3D", true, false):
				skeleton.reset_bone_poses()


func _toggle_pause() -> void:
	_set_paused(_sample.process_mode != Node.PROCESS_MODE_DISABLED)


func _set_paused(paused: bool) -> void:
	_sample.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	_pause.text = "Продолжить" if paused else "Пауза"
	var has_actor := is_instance_valid(_ball) or is_instance_valid(_fighter) or (is_instance_valid(_comparison) and not _comparison_is_static and not _motion.disabled)
	var id: StringName = _motion.get_item_metadata(_motion.selected) if _motion.selected >= 0 else &""
	_pause.disabled = not has_actor or id in [&"sphere", &"inspect"]
	_replay.disabled = _pause.disabled
	_repeat.disabled = not has_actor or id in [&"", &"idle", &"sphere", &"inspect"]


func _turn_camera(radians: float) -> void:
	_orbit.x = wrapf(_orbit.x + radians, -PI, PI)
	_frame_camera()


func _zoom_camera(multiplier: float) -> void:
	_zoom = clampf(_zoom * multiplier, 0.55, 3.0)
	_frame_camera()


func _reset_camera() -> void:
	_orbit = INITIAL_ORBIT
	_zoom = 1.0
	_frame_camera()


func _camera_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_orbit.y = clampf(_orbit.y + event.relative.y * 0.007, 0.04, 1.1)
		_turn_camera(-event.relative.x * 0.009)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: _zoom_camera(1.0 / 1.1)
			MOUSE_BUTTON_WHEEL_DOWN: _zoom_camera(1.1)


func _frame_camera() -> void:
	if not is_instance_valid(_camera): return
	var height := 2.0
	var width := 2.0
	var model_bounds := AABB()
	var pivot := Vector3.ZERO
	var figure_scale := 1.0
	if is_instance_valid(_ball):
		height = _ball.figure_height()
		width = _ball.figure_size()
		if _motion.get_item_metadata(_motion.selected) == &"sphere":
			height = CreatureBall._shell_r() * 2.0
			width = height
		elif is_instance_valid(_ball._anim):
			model_bounds = CreatureModels.world_aabb(_ball._anim._model)
			pivot = _ball._figure.global_position
			figure_scale = _ball._figure.scale.x
	elif is_instance_valid(_fighter):
		var head := _fighter.skeleton.find_bone("Head")
		if head >= 0:
			height = (_fighter.skeleton.get_bone_global_rest(head).origin.y + 0.23) * _fighter.actor.scale.y
		width = height * 0.8
	elif is_instance_valid(_comparison):
		model_bounds = _comparison_bounds
		height = model_bounds.size.y
		width = maxf(model_bounds.size.x, model_bounds.size.z)
	var size := _viewport.size
	var aspect := float(maxi(size.x, 1)) / float(maxi(size.y, 1))
	var half_fov := tan(deg_to_rad(_camera.fov) * 0.5)
	var distance := maxf(height, width / aspect) * 1.35 / (2.0 * half_fov)
	var target := Vector3.UP * height * 0.49
	var direction := Vector3(sin(_orbit.x) * cos(_orbit.y), sin(_orbit.y), cos(_orbit.x) * cos(_orbit.y))
	if model_bounds.has_volume():
		var view := Basis.looking_at(-direction).transposed()
		for index in 8:
			# Frame the full figure even while it is still growing out of the sphere.
			var corner := pivot + (model_bounds.get_endpoint(index) - pivot) / figure_scale
			var local := view * (corner - target)
			var span := maxf(absf(local.x) / aspect, absf(local.y))
			distance = maxf(distance, local.z + span / (half_fov * 0.86))
	_camera.look_at_from_position(target + direction * distance * _zoom, target)


func _clear_effects() -> void:
	for child: Node3D in _sample.get_children():
		if child != _fighter and child != _ball and child != _comparison:
			child.hide()
			child.queue_free()


func _release_model() -> void:
	_clear_effects()
	if is_instance_valid(_ball):
		_catalog.return_ball(_ball)
		_ball = null
	if is_instance_valid(_fighter):
		_catalog.return_fighter(_fighter)
		_fighter = null
	if is_instance_valid(_comparison_current):
		_comparison_current._anim.set_process(true)
		_catalog.return_ball(_comparison_current)
		_comparison_current = null
	if is_instance_valid(_comparison):
		_comparison.hide()
		_comparison.queue_free()
		_comparison = null
		_comparison_players.clear()
		_comparison_variants.clear()
		_comparison_is_static = false


func _report_unavailable(message: String) -> void:
	_status.text = message
	_status.show()
	_motion.disabled = not is_instance_valid(_ball) and not is_instance_valid(_fighter)
	_set_paused(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _closing: return
	_closing = true
	_release_model()
	if is_instance_valid(_arena):
		_catalog.return_arena(_arena)
		_arena = null
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	hide()
	closed.emit()
	queue_free()


func _label(parent: Node, title: String, font_size: int) -> Label:
	var label := VisualUtil.label(title, font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(label)
	return label


func _option(parent: Node, title: String, action: Callable) -> OptionButton:
	var field := VBoxContainer.new()
	parent.add_child(field)
	_label(field, title, 17).add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	var choice := OptionButton.new()
	choice.custom_minimum_size.y = 38
	choice.fit_to_longest_item = false
	choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	choice.item_selected.connect(action)
	field.add_child(choice)
	return choice


func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(38, 38)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
