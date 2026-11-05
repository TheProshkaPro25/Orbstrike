class_name GameLoading
extends Node
## Владелец резидентных ресурсов. Тяжёлая подготовка происходит единожды до меню.
static var _inst: GameLoading
var ready_to_play := false
var preparing := false
var moving_scene := false
var preparation_count := 0
var actor_build_count := 0
var arena_build_count := 0
var fighter_build_count := 0
var _fighters: Dictionary = {}
var preparation_times_ms: Dictionary = {}
var resources: Dictionary = {}
var _balls: Dictionary = {} # id -> два экземпляра; не узлы прошедшего матча
var _arenas: Dictionary = {}
var _leased: Dictionary = {}
var _storage: Node3D
var _viewport: SubViewport
var _game: Node
var _menu: Node
var _warm_draw: Callable


static func i() -> GameLoading:
	if not is_instance_valid(_inst):
		_inst = GameLoading.new()
		_inst.name = "GameLoading"
		(Engine.get_main_loop() as SceneTree).root.add_child(_inst)
	return _inst


func prepare(progress: Callable = Callable()) -> void:
	if preparing:
		while preparing:
			await get_tree().process_frame
		return
	if ready_to_play:
		return
	preparing = true
	preparation_count += 1
	# Обычный запуск тоже может быть свёрнут. Компиляция материалов должна
	# завершиться под Boot, а не откладываться до восстановления окна.
	if DisplayServer.get_name() != "headless" and not get_tree().has_meta("sfery_background_draw"):
		_warm_draw = func() -> void:
			if get_tree().root.mode == Window.MODE_MINIMIZED:
				RenderingServer.viewport_set_update_mode(get_tree().root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
				RenderingServer.force_draw(false)
		get_tree().process_frame.connect(_warm_draw)
	AudioSettings.load_and_apply()
	CreatureModels.resident_catalog = true
	resources = await StartupCatalog.preload_resources(func(done: int, total: int, _path: String) -> void:
		_report(progress, .22 * float(done) / total, "Загрузка ресурсов · %d / %d" % [done, total]))
	SoundFx.i().preload_catalog()
	CreatureModels.preload_all_catalog()
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(256, 256)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_storage = Node3D.new()
	_viewport.add_child(_storage)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 9, 34)
	_storage.add_child(camera)
	camera.look_at(Vector3(0, 6, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	_storage.add_child(light)
	await prepare_fighters(_storage)
	var defs := CreatureModels.catalog_defs()
	var ball_scene: PackedScene = resources["res://scenes/creature_ball.tscn"]
	var warm_batch: Array[CreatureBall] = []
	var frame_budget := Time.get_ticks_usec()
	for index in defs.size():
		var d: CreatureDef = defs[index]
		_balls[d.id] = []
		for copy in 2:
			_report(progress, .22 + .65 * float(index * 2 + copy) / (defs.size() * 2),
				"Подготовка существ · %d / %d" % [index * 2 + copy + 1, defs.size() * 2])
			var begin := Time.get_ticks_usec()
			var ball := ball_scene.instantiate() as CreatureBall
			_storage.add_child(ball)
			ball.setup(d, -1)
			ball.freeze_at(Vector3(0, CreatureBall.RADIUS, 0))
			ball._apply_owner_marks()
			ball._make_halves()
			ball._figure.visible = true
			preparation_times_ms[d.id] = (Time.get_ticks_usec() - begin) / 1000.0
			actor_build_count += 1
			warm_batch.append(ball)
			# Один кадр прогревает небольшую группу. Второй экземпляр использует
			# те же материалы/вершинный формат, его GPU-буферы остаются отдельными.
			if Time.get_ticks_usec()-frame_budget >= 8000 or warm_batch.size() >= 8:
				await get_tree().process_frame
				for prepared in warm_batch: _park_ball(prepared)
				warm_batch.clear()
				frame_budget = Time.get_ticks_usec()
	if not warm_batch.is_empty():
		await get_tree().process_frame
		for prepared in warm_batch: _park_ball(prepared)
	var arena_scene: PackedScene = resources["res://scenes/arena.tscn"]
	_report(progress, .87, "Подготовка эффектов…")
	await StartupCatalog.warm_effects(_storage)
	for index in 3:
		_report(progress, .87 + float(index) * .025, "Подготовка арен · %d / 3" % [index + 1])
		await get_tree().process_frame
		var arena := arena_scene.instantiate() as Arena
		arena.location_id = index
		_storage.add_child(arena)
		arena.apply_quality()
		await get_tree().process_frame
		arena_build_count += 1
		return_arena(arena)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Меню и интерфейс команды тоже создаются под единственным экраном загрузки.
	ready_to_play = true
	_report(progress, .96, "Подготовка интерфейса…")
	var menu_time_scale := Engine.time_scale
	_game = (resources["res://scenes/main.tscn"] as PackedScene).instantiate()
	add_child(_game)
	Engine.time_scale = menu_time_scale
	_game.process_mode = Node.PROCESS_MODE_DISABLED
	# Рендер настоящего игрового viewport под непрозрачным Boot выделяет карты
	# теней и компилирует варианты материалов до первого входа в команду.
	var selected_location := ArenaLocations.current()
	for index in 3:
		_report(progress, .96 + float(index) * .008, "Подготовка освещения · %d / 3" % [index + 1])
		_game._preview_arena_location(index, false)
		await get_tree().process_frame
		await get_tree().process_frame
	_game._preview_arena_location(selected_location, false)
	_game.cam.snap_overview()
	_game.hud.visible = true
	_set_scene_enabled(_game, false)
	await get_tree().process_frame
	_menu = (resources["res://scenes/menu/main_menu.tscn"] as PackedScene).instantiate()
	add_child(_menu)
	await get_tree().process_frame
	_set_scene_enabled(_menu, false)
	preparing = false
	_stop_warm_draw()
	_report(progress, 1.0, "Готово")


func prepare_fighters(parent: Node3D) -> void:
	for model in 2:
		_fighters[model] = []
		for copy in 2:
			var fighter := VrmFighter.new()
			parent.add_child(fighter)
			var profile := PlayerProfile.DEFAULT.duplicate(true)
			profile.vrm_model = model
			fighter.apply_profile(profile)
			fighter.play_motion("command")
			fighter.prepare_ability(CardDB.card(CardDB.ability_ids()[0]),model)
			fighter.sample_motion(.9)
			fighter_build_count += 1
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			fighter.reset_motion()
			fighter.hide()
			fighter.process_mode = Node.PROCESS_MODE_DISABLED
			_fighters[model].append(fighter)


func take_fighter(profile: Dictionary) -> VrmFighter:
	var model: int = PlayerProfile.normalized(profile).vrm_model
	if not _fighters.has(model) or _fighters[model].is_empty(): return null
	var fighter: VrmFighter = _fighters[model].pop_back()
	fighter.apply_profile(profile)
	fighter.process_mode = Node.PROCESS_MODE_INHERIT
	fighter.show()
	return fighter


func return_fighter(fighter: VrmFighter) -> void:
	if not is_instance_valid(fighter): return
	fighter.reset_motion()
	fighter.hide()
	fighter.process_mode = Node.PROCESS_MODE_DISABLED
	if fighter.get_parent() != _storage: fighter.reparent(_storage,false)
	fighter.transform = Transform3D.IDENTITY
	if not _fighters[fighter.selected].has(fighter): _fighters[fighter.selected].append(fighter)


func _report(callback: Callable, value: float, text: String) -> void:
	if callback.is_valid():
		callback.call(value, text)


func has_ball(id: StringName) -> bool:
	return _balls.has(id)


func take_ball(id: StringName, uid: int, origin: Vector3) -> CreatureBall:
	if not _balls.has(id) or _balls[id].is_empty():
		return null
	var ball: CreatureBall = _balls[id].pop_back()
	_leased[ball.get_instance_id()] = weakref(ball)
	ball.process_mode = Node.PROCESS_MODE_INHERIT
	ball.set_process(true)
	ball.set_physics_process(true)
	ball.uid = uid
	ball._home_set = false
	ball.freeze_at(origin)
	ball._shape.disabled = false
	ball.slot = -1
	ball._figure.rotation = Vector3.ZERO
	ball._foot_ring.visible = true
	ball._label_allowed = true
	ball.visible = true
	return ball


func return_ball(ball: CreatureBall) -> void:
	if not is_instance_valid(ball):
		return
	_leased.erase(ball.get_instance_id())
	_park_ball(ball)


func _park_ball(ball: CreatureBall) -> void:
	# Без close_up() на живом дереве: оно порождает одноразовую вспышку.
	ball.reset_match_presentation()
	if ball.get_parent() != _storage:
		ball.reparent(_storage, false)
	ball.visible = false
	ball.freeze_at(Vector3(0, CreatureBall.RADIUS, 0))
	ball._open = false
	ball._figure.visible = false
	ball._figure.scale = Vector3.ONE
	ball._figure.rotation = Vector3.ZERO
	ball._anim.visible = true
	ball._anim.idle_on = false
	ball._show_closed()
	ball._set_glow(0)
	ball._set_dim(0)
	ball._set_crack(0)
	ball._visual.scale = Vector3.ONE
	ball._label.visible = false
	ball.slot = -1
	ball.process_mode = Node.PROCESS_MODE_DISABLED
	if not _balls.has(ball.def.id):
		_balls[ball.def.id] = []
	if not _balls[ball.def.id].has(ball):
		_balls[ball.def.id].append(ball)


func take_arena(index: int) -> Arena:
	var arena: Arena = _arenas.get(index)
	if arena == null:
		return null
	_arenas.erase(index)
	arena.process_mode = Node.PROCESS_MODE_INHERIT
	arena.visible = true
	if arena._motes != null:
		arena._motes.emitting = true
	preload("res://scenes/landscape_atmosphere.gd").active(arena,true)
	return arena


func return_arena(arena: Arena) -> void:
	if not is_instance_valid(arena):
		return
	if arena.get_parent() != _storage:
		arena.reparent(_storage, false)
	for entry in arena.slot_clicked.get_connections():
		arena.slot_clicked.disconnect(entry.callable)
	for entry in arena.invalid_pick.get_connections():
		arena.invalid_pick.disconnect(entry.callable)
	if arena._wave_tw != null:
		arena._wave_tw.kill()
	arena._floor_mat.set_shader_parameter("wave_strength", 0.0)
	arena.set_highlight([])
	arena.visible = false
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	if arena._motes != null:
		arena._motes.emitting = false
	preload("res://scenes/landscape_atmosphere.gd").active(arena,false)
	_arenas[arena.location_id] = arena


func show_menu() -> void:
	_replace_scene(_menu)
	_menu = null
	SoundFx.i().play_music(SoundFx.MUSIC_MENU)


func show_game() -> void:
	var prepared_before_menu := _game != null
	if _game == null:
		_game = (resources["res://scenes/main.tscn"] as PackedScene).instantiate()
		add_child(_game)
	var game := _game
	_game = null
	_replace_scene(game)
	if prepared_before_menu:
		game._previous_time_scale = Engine.time_scale
		BattleTempo.load_settings()
		if is_equal_approx(Engine.time_scale, 1.0):
			BattleTempo.apply()
	game.apply_graphics()
	game.team_menu.refresh_settings_labels()
	game.cam.current = true
	SoundFx.i().play_music(SoundFx.MUSIC_TEAM)


func show_online() -> void:
	# Return the parked offline arena before taking the resident online resources.
	if is_instance_valid(_game):
		_game._release_game_resources()
		_game.queue_free()
		_game = null
	var scene := (resources["res://scenes/online/online_game.tscn"] as PackedScene).instantiate()
	add_child(scene)
	_replace_scene(scene)


func _replace_scene(scene: Node) -> void:
	var tree := get_tree()
	var old := tree.current_scene
	if is_instance_valid(old) and old != scene:
		_set_scene_enabled(old, false)
	moving_scene = true
	scene.reparent(tree.root, false)
	moving_scene = false
	_set_scene_enabled(scene, true)
	tree.current_scene = scene
	if is_instance_valid(old) and old != scene:
		old.queue_free()


func _set_scene_enabled(scene: Node, enabled: bool) -> void:
	scene.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	if scene is CanvasLayer or scene is Node3D:
		scene.visible = enabled
	# WorldEnvironment не учитывает видимость Node3D и продолжает владеть общим
	# World3D. Скрытая заранее созданная Main иначе оставляет своё постоянное
	# освещение в городе, пока его горы/небо меняются по отдельным uniforms.
	for child in scene.find_children("*", "WorldEnvironment", true, false):
		var environment_node := child as WorldEnvironment
		if environment_node.get_viewport() != scene.get_viewport():
			continue # Предпросмотры в своих SubViewport уже изолированы.
		if enabled:
			if environment_node.has_meta("loading_parked_environment"):
				environment_node.environment = environment_node.get_meta("loading_parked_environment")
				environment_node.remove_meta("loading_parked_environment")
		elif environment_node.environment != null:
			environment_node.set_meta("loading_parked_environment", environment_node.environment)
			environment_node.environment = null
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = enabled
		elif child is Node3D:
			child.visible = enabled


func _exit_tree() -> void:
	_stop_warm_draw()
	CreatureModels.resident_catalog = false
	CreatureModels.clear()
	resources.clear()
	PreparationStore.clear()
	_inst = null


func _stop_warm_draw() -> void:
	if _warm_draw.is_valid() and get_tree().process_frame.is_connected(_warm_draw):
		get_tree().process_frame.disconnect(_warm_draw)
	_warm_draw = Callable()
