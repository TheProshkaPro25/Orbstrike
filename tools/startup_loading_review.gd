extends SceneTree
## Настоящий путь Boot → меню → команда → матч → «Ещё раз».
## Тест сам защищает рабочий стол и пригоден для отдельного свёрнутого запуска.
var failures := 0
var checks := 0
var out_dir := "user://startup_loading_review"
var main: Node
var loader: GameLoading
var initial_counts: Array[int] = []
var startup_seconds := 0.0
var max_transition_ms := 0.0
var team_to_match_ms: Array[float] = []
var actor_checkout_ms: Array[float] = []
var restart_ms: Array[float] = []
var map_preview_ms: Array[float] = []
var map_preview_cpu_ms: Array[float] = []
var memory_samples: Array[Dictionary] = []
var final_counts: Array[int] = []

func _initialize() -> void:
	if not has_meta("sfery_background_draw"):
		preload("res://tools/test_window.gd").background(self)
	call_deferred("run")

func _finalize() -> void:
	preload("res://tools/test_window.gd").finish(self)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.max_fps = 60
	GraphicsSettings.max_fps = 60
	Engine.time_scale = 1.0
	BattleTempo.loaded = true
	BattleTempo.selected = 3
	var begin := Time.get_ticks_msec()
	change_scene_to_file("res://scenes/loading/boot.tscn")
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.scene_file_path == "res://scenes/loading/boot.tscn", "первый экран — загрузка перед меню")
	await save("initial-loading")
	if not await wait_for_scene("res://scenes/menu/main_menu.tscn", 180.0):
		check(false, "начальная загрузка завершается главным меню за 180 с")
		await finish()
		return
	startup_seconds = (Time.get_ticks_msec() - begin) / 1000.0
	loader = GameLoading.i()
	check(loader.ready_to_play, "всё готово до показа главного меню")
	check(is_equal_approx(Engine.time_scale, 1.0), "скрытая подготовка не ускоряет главное меню темпом боя")
	initial_counts = counts()
	memory_samples.append(memory_snapshot("main_menu_ready"))
	# Скрытая заранее созданная команда уже показывает первый вид: временно
	# отпускаем этот предпросмотр, чтобы проверить обе каталожные копии.
	var prepared_preview: CreaturePreview
	var prepared_preview_id: StringName = &""
	if loader._game != null:
		prepared_preview = loader._game.team_menu._preview
		prepared_preview_id = prepared_preview._shown_id
		prepared_preview.release()
	var defs := CreatureModels.catalog_defs()
	check(defs.size() == 67, "в стартовом каталоге 66 обычных вариантов и редкий Ликорез")
	check(loader.actor_build_count == defs.size() * 2, "две готовые сферы каждого определения для двух игроков")
	check(loader.arena_build_count == 3, "все три локации построены перед меню")
	for def in defs:
		check(loader.has_ball(def.id), "готовый вид %s" % def.id)
		var first: CreatureBall = loader.take_ball(def.id, 1001, Vector3(0, CreatureBall.RADIUS, 12))
		var second: CreatureBall = loader.take_ball(def.id, 1002, Vector3(0, CreatureBall.RADIUS, -12))
		check(first != null and second != null and first != second, "два независимых экземпляра %s" % def.id)
		if first != null:
			check(first.uid == 1001 and first._anim != null and first._anim.is_inside_tree(), "готовая модель и uid %s" % def.id)
			loader.return_ball(first)
		if second != null: loader.return_ball(second)
	check(counts() == initial_counts, "выдача всех сфер не создаёт новые модели")
	# Восстанавливаем исходный показ до переноса всей сцены из загрузчика.
	if prepared_preview != null and prepared_preview_id != &"":
		prepared_preview.show_creature(CardDB.creature(prepared_preview_id))
	await save("main-menu")

	var original_quality := GraphicsSettings.current()
	var original_fps := GraphicsSettings.fps_limit()
	GraphicsSettings.force_level(GraphicsSettings.Level.LOW)
	GraphicsSettings.max_fps = 90
	current_scene._on_play()
	if not await wait_for_scene("res://scenes/main.tscn", 15.0):
		check(false, "меню открывает выбор команды без загрузочного экрана")
		await finish()
		return
	main = current_scene
	check(main.team_menu.visible, "готовое меню команды")
	check(is_equal_approx(Engine.time_scale, 2.0), "сохранённый темп применяется при входе в игру")
	check(not main._env.ssao_enabled and main.arena._motes.amount == 70, "качество из главного меню применено к подготовленному миру")
	check(main.team_menu._graphics_button.text == "Графика: Низкие" and main.team_menu._fps_button.text == "FPS: 90", "подписи готового меню отражают новые настройки")
	GraphicsSettings.force_level(original_quality)
	GraphicsSettings.max_fps = original_fps
	main.apply_graphics()
	main.team_menu.refresh_settings_labels()
	var initial_preview: CreaturePreview = main.team_menu._preview
	check(initial_preview._borrowed_ball != null and initial_preview._anim != null,
		"исходный предпросмотр не опустел после переноса готовой сцены")
	check(initial_preview._shown_id == prepared_preview_id and prepared_preview_id != &"",
		"перенос сцены сохранил исходный вид предпросмотра")
	if initial_preview._borrowed_ball != null:
		check(initial_preview._borrowed_ball._figure.visible and initial_preview._anim.visible,
			"исходная фигура предпросмотра видима после переноса")
	# Предпросмотр берёт ту же пару моделей, а не новый CreatureAnim/set_model.
	var preview: CreaturePreview = main.team_menu._preview
	var def: CreatureDef = CardDB.creature(&"creature_ratnik_fire")
	if def == null: def = defs[0]
	preview.show_creature(def)
	await process_frame
	var shown: CreatureBall = preview._borrowed_ball
	check(shown != null, "предпросмотр получил готовую сферу")
	if shown != null:
		check(preview._anim == shown._anim, "предпросмотр использует аниматор готовой сферы")
	check(not preview._loading.visible and preview._pending.is_empty(), "наведение не включает загрузку модели")
	preview.release()
	check(preview._borrowed_ball == null, "предпросмотр вернул сферу перед боем")
	check(counts() == initial_counts, "предпросмотр не повторяет подготовку")

	# Перебор локаций и возврат к первой используют те же процедурные сцены.
	var arena_ids: Dictionary = {}
	main.team_menu._open_arena_picker()
	for index in 3:
		var preview_begin := Time.get_ticks_usec()
		main.team_menu._arena_picker.select(index)
		map_preview_cpu_ms.append((Time.get_ticks_usec() - preview_begin) / 1000.0)
		await process_frame
		map_preview_ms.append((Time.get_ticks_usec() - preview_begin) / 1000.0)
		arena_ids[index] = main.arena.get_instance_id()
		check(main.arena.location_id == index and main.arena.markers.size() == 6, "готовая арена %s" % index)
	for index in 3:
		var preview_begin := Time.get_ticks_usec()
		main.team_menu._arena_picker.select(index)
		map_preview_cpu_ms.append((Time.get_ticks_usec() - preview_begin) / 1000.0)
		await process_frame
		map_preview_ms.append((Time.get_ticks_usec() - preview_begin) / 1000.0)
		check(main.arena.get_instance_id() == arena_ids[index], "повторный выбор возвращает ту же арену %s" % index)
	main.team_menu._close_arena_picker()
	check(counts() == initial_counts, "смена арен не строит геометрию заново")
	await save("team-ready")

	for repeat in 2:
		var started := Time.get_ticks_usec()
		main.team_menu.pick_random_and_start()
		# Убираем автоматические ходы, оставляя настоящий запуск и резерв шести uid.
		if main.events.drained.is_connected(main._pump): main.events.drained.disconnect(main._pump)
		var actors_ready := false
		# The current client deliberately plays a7.2s location introduction.
		# Record resource readiness separately from that presentation interval.
		var start_deadline := Time.get_ticks_msec() + 15000
		while Time.get_ticks_msec() < start_deadline:
			await process_frame
			if not actors_ready and main._prepared_balls.size() == 6:
				actors_ready = true
				actor_checkout_ms.append((Time.get_ticks_usec() - started) / 1000.0)
			if not main._preparing: break
		var elapsed := (Time.get_ticks_usec() - started) / 1000.0
		max_transition_ms = maxf(max_transition_ms, elapsed)
		team_to_match_ms.append(elapsed)
		check(not main._preparing and main.ctrl._started, "матч %s начинает готовая команда" % repeat)
		check(main._prepared_balls.size() == 6, "матч %s получил шесть готовых сфер" % repeat)
		check(counts() == initial_counts, "матч %s не загружает и не создаёт новые модели/арены" % repeat)
		check(not has_loading_label(main), "после меню нет второго экрана подготовки")
		await save("match-%s-ready" % repeat)
		memory_samples.append(memory_snapshot("match_%s_started" % (repeat + 1)))
		if repeat == 0:
			var old := main
			var restart_begin := Time.get_ticks_usec()
			main.game_over_ui.restart_requested.emit()
			if not await wait_for_scene("res://scenes/main.tscn", 15.0, old):
				check(false, "«Ещё раз» возвращает к выбору команды")
				break
			restart_ms.append((Time.get_ticks_usec() - restart_begin) / 1000.0)
			main = current_scene
			await process_frame
			await process_frame
			check(is_equal_approx(Engine.time_scale, 2.0), "темп боя сохраняется после удаления прежней сцены")
			check(main.team_menu.visible and counts() == initial_counts, "повторная игра сохранила готовый каталог")
	await finish()

func counts() -> Array[int]:
	return [loader.preparation_count, loader.actor_build_count, loader.arena_build_count, SoundFx.i().catalog_load_count]

## Память выделений движка и ресурсы GPU. Это не RSS процесса и не FPS.
func memory_snapshot(stage: String) -> Dictionary:
	return {
		"stage": stage,
		"engine_static_bytes": OS.get_static_memory_usage(),
		"engine_static_max_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		"gpu_texture_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"gpu_buffer_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
		"gpu_total_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"counts": counts(),
	}

func has_loading_label(node: Node) -> bool:
	if node is Label and "Подготовка к бою" in (node as Label).text: return true
	for child in node.get_children():
		if has_loading_label(child): return true
	return false

func wait_for_scene(path: String, timeout_seconds: float, previous: Node = null) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene != previous and current_scene.scene_file_path == path:
			return true
	return false

func save(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(label + ".png"))

func finish() -> void:
	if is_instance_valid(loader):
		final_counts = counts()
	if is_instance_valid(main) and main.has_method("_release_game_resources"):
		main._release_game_resources()
	if current_scene != null:
		current_scene.queue_free()
	main = null
	await process_frame
	await process_frame
	var cache := root.get_node_or_null("GameLoading")
	if cache != null: cache.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await process_frame
	await create_timer(.2, true, false, true).timeout
	Engine.time_scale = 1.0
	var result := {
		"failures":failures, "checks":checks, "startup_seconds":startup_seconds,
		"max_team_to_match_ms":max_transition_ms, "team_to_match_ms":team_to_match_ms, "actor_checkout_ms":actor_checkout_ms,
		"timing_note":"team_to_match includes the designed location intro; actor_checkout measures six actors ready before it. Neither is FPS.",
		"restart_ms":restart_ms, "map_preview_ms":map_preview_ms,
		"max_map_preview_ms":map_preview_ms.max() if not map_preview_ms.is_empty() else 0.0,
		"map_preview_cpu_ms":map_preview_cpu_ms,
		"initial_counts":initial_counts, "final_counts":final_counts,
		"memory_samples":memory_samples,
		"memory_note":"Engine allocator and rendering resource bytes; not process RSS or FPS. Two match starts, complete matches are covered by autoplay.",
	}
	var file := FileAccess.open(out_dir.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("STARTUP ", JSON.stringify(result))
	quit(1 if failures else 0)
