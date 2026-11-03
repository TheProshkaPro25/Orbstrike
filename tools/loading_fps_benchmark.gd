extends SceneTree
## Сравнение прежнего пути подготовки шести существ и резидентного каталога.
## Оба варианта используют текущие одинаковые правила, модели и рендерер.
const WindowTest := preload("res://tools/test_window.gd")
const SEED := 271828
const SHOTS := ["overview", "battle", "closeup"]
var variant := "startup_catalog"
var out_dir := "user://loading_fps_benchmark"
var warmup_seconds := 2.0
var measure_seconds := 4.0
var main: Node
var failures: Array[String] = []
var stage: Dictionary = {}
var results: Array[Dictionary] = []
var roster: Array[Dictionary] = []
var actors: Array[CreatureBall] = []
var _initial_us := 0
var _post_draw_total := 0
var _draw_callback: Callable
var _csv: FileAccess
var _finished := false

func _initialize() -> void:
	WindowTest.background(self)
	_initial_us = Time.get_ticks_usec()
	stage["initialize_epoch_seconds"] = Time.get_unix_time_from_system()
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() != 2: continue
		match pair[0]:
			"variant": variant = pair[1]
			"out": out_dir = pair[1]
			"warmup": warmup_seconds = float(pair[1])
			"measure": measure_seconds = float(pair[1])
	_draw_callback = func() -> void: _post_draw_total += 1
	RenderingServer.frame_post_draw.connect(_draw_callback)
	call_deferred("run")

func _finalize() -> void:
	if _draw_callback.is_valid() and RenderingServer.frame_post_draw.is_connected(_draw_callback):
		RenderingServer.frame_post_draw.disconnect(_draw_callback)
	WindowTest.finish(self)

func check(ok: bool, message: String) -> bool:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
	return ok

func run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not check(variant in ["legacy_path", "startup_catalog"], "известный вариант загрузки"):
		await finish(); return
	seed(SEED)
	GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
	GraphicsSettings.max_fps = 60
	Engine.max_fps = 60
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	ArenaLocations._current = 0
	root.size = Vector2i(1920, 1080)
	# KWin ограничивает клиент окна до1050px из-за рамки. Внутренний viewport
	# остаётся точным FHD и не зависит от размеров свёрнутого окна.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_factor = 1.0
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.unfocusable = true
	root.scaling_3d_scale = 1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	change_scene_to_file("res://scenes/loading/boot.tscn" if variant == "startup_catalog" else "res://scenes/menu/main_menu.tscn")
	if not await wait_for_scene("res://scenes/menu/main_menu.tscn", 240.0):
		check(false, "загрузка дошла до главного меню"); await finish(); return
	# Одинаковая готовность menu._ready + один нарисованный кадр в обоих путях.
	await process_frame
	stage["menu_epoch_seconds"] = Time.get_unix_time_from_system()
	stage["time_to_menu_seconds"] = (Time.get_ticks_usec() - _initial_us) / 1e6
	var menu_us := Time.get_ticks_usec()
	check(GameLoading.i().ready_to_play == (variant == "startup_catalog"), "состояние каталога соответствует выбранному пути")
	var play_us := Time.get_ticks_usec()
	current_scene._on_play()
	if not await wait_for_scene("res://scenes/main.tscn", 30.0):
		check(false, "главное меню открыло команду"); await finish(); return
	main = current_scene
	stage["play_to_team_seconds"] = (Time.get_ticks_usec() - play_us) / 1e6
	main.rng.seed = SEED
	main.team_menu._rng.seed = SEED
	Engine.time_scale = 1.0
	main.team_menu._preview.release()
	main.team_menu.hide()
	var loading: ColorRect
	var progress: ProgressBar
	var team_us := Time.get_ticks_usec()
	if variant == "legacy_path":
		# Только тестовый слой восстанавливает прежний индикатор перед fallback.
		loading = loading_overlay()
		progress = loading.get_meta("progress")
		await process_frame
		await process_frame
	var deck := CardDB.preset_deck(1)
	var creatures: Array[StringName] = []
	var gates: Array[StringName] = []
	var abilities: Array[StringName] = []
	for def in deck.creatures: creatures.append(def.id)
	for def in deck.arena: gates.append(def.id)
	for def in deck.abilities: abilities.append(def.id)
	main._on_deck_chosen(creatures, gates, abilities)
	if main.events.drained.is_connected(main._pump): main.events.drained.disconnect(main._pump)
	var deadline := Time.get_ticks_msec() + 120000
	while main._preparing and Time.get_ticks_msec() < deadline:
		await process_frame
		if progress != null: progress.value = main._prepared_balls.size()
	if not check(not main._preparing and main.ctrl._started and main._prepared_balls.size() == 6, "шесть существ готовы и контроллер запущен"):
		await finish(); return
	stage["battle_ready_epoch_seconds"] = Time.get_unix_time_from_system()
	stage["team_to_battle_ready_seconds"] = (Time.get_ticks_usec() - team_us) / 1e6
	stage["menu_to_battle_ready_seconds"] = (Time.get_ticks_usec() - menu_us) / 1e6
	stage["battle_ready_seconds_total"] = (Time.get_ticks_usec() - _initial_us) / 1e6
	if loading != null: loading.queue_free()
	# Дренирование уже начатых анимаций без следующего игрового хода.
	deadline = Time.get_ticks_msec() + 30000
	while main.events.is_busy() and Time.get_ticks_msec() < deadline:
		main.hud._skip_flag = true
		await process_frame
	if not check(not main.events.is_busy(), "очередь стартовых эффектов завершилась"):
		await finish(); return
	main._pending.clear()
	main.setup_panel.hide_panel()
	main.ability_panel.hide_panel()
	main.ability_panel.set_dock_visible(true)
	main.hud.clear_flash()
	main.hud._coach_queue.clear()
	main.hud._close_coach()
	main.hover_tips.resolver = Callable()
	main.ui_layer.visible = true
	GraphicsSettings.max_fps = 0
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	seed(SEED)
	var slot := 0
	for owner in 2:
		for uid in main.ctrl.get_view(0).players[owner].creature_uids:
			var ball: CreatureBall = main._spawn_ball(uid)
			ball.freeze_at(main.arena.slot_position(slot) + Vector3(0, main.BALL_Y + .02, 0))
			ball.face_toward(ball.global_position + Vector3(0, 0, -1.0 if owner == 0 else 1.0))
			ball.open_animated(false)
			actors.append(ball)
			roster.append({"uid":uid,"owner":owner,"id":String(main._creature_def(uid).id),"slot":slot})
			slot += 1
	await wait_seconds(2.0)
	reset_idle()
	var size := root.get_texture().get_size()
	stage["actual_render_resolution"] = [int(size.x), int(size.y)]
	stage["actual_viewport_resolution"] = [int(root.get_visible_rect().size.x), int(root.get_visible_rect().size.y)]
	stage["client_window_resolution"] = [root.size.x, root.size.y]
	stage["window_minimized"] = root.mode == Window.MODE_MINIMIZED
	stage["window_unfocusable"] = root.unfocusable
	check(size == Vector2(1920, 1080), "рендер действительно 1920×1080")
	check(root.mode == Window.MODE_MINIMIZED and root.unfocusable, "свёрнутый стенд не принимает фокус")
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_csv = FileAccess.open(out_dir.path_join("frames.csv"), FileAccess.WRITE)
	_csv.store_csv_line(PackedStringArray(["shot","sample","wall_frame_ms","gpu_render_ms","cpu_render_ms","cpu_frame_setup_ms","engine_drawn_delta","post_draw_delta"]))
	var reference: CreatureBall = actors[4]
	for shot in SHOTS.size():
		main.cam.set_process(true)
		main.cam._t = 0.0
		reset_idle()
		match shot:
			0: main.cam.snap_overview()
			1: main.cam.battle_view(main.arena.slot_position(4), reference.figure_height())
			2: main.cam.close_up(reference.global_position, Vector3(0,0,-1), reference.figure_height(), reference.figure_size())
		# Камеры те же, но без зависимого от FPS дрейфа/тряски для сравнения.
		main.cam._drift = 0.0
		main.cam._hand = 0.0
		main.cam.cut()
		await wait_seconds(warmup_seconds)
		main.cam.set_process(false)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out_dir.path_join(SHOTS[shot] + ".png"))
		results.append(await measure(SHOTS[shot]))
	await finish()

func reset_idle() -> void:
	for index in actors.size():
		var anim: CreatureAnim = actors[index]._anim
		anim._phase = fposmod(float(index) * .731, TAU)
		anim._clock = 0.0
		anim.reset()
		anim.idle_on = true
		anim.set_process(true)

func loading_overlay() -> ColorRect:
	var loading := ColorRect.new()
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.color = Color(.018,.026,.042,.98)
	loading.theme = UiTheme.get_theme()
	main.ui_layer.add_child(loading)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 420
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	var label := VisualUtil.label("Подготовка к бою", 26)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	var progress := ProgressBar.new()
	progress.max_value = 6
	progress.show_percentage = false
	progress.custom_minimum_size.y = 12
	column.add_child(progress)
	loading.set_meta("progress", progress)
	return loading

func measure(shot: String) -> Dictionary:
	var times: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var setup: Array[float] = []
	var begin := Time.get_ticks_usec()
	var last := begin
	var drawn_start := Engine.get_frames_drawn()
	var posts_start := _post_draw_total
	var last_drawn := drawn_start
	var last_posts := posts_start
	while Time.get_ticks_usec() - begin < int(measure_seconds * 1e6):
		await process_frame
		var now := Time.get_ticks_usec()
		var wall_ms := (now - last) / 1000.0
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		var cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		var setup_ms := RenderingServer.get_frame_setup_time_cpu()
		var drawn := Engine.get_frames_drawn()
		var posts := _post_draw_total
		times.append(wall_ms); gpu.append(gpu_ms); cpu.append(cpu_ms); setup.append(setup_ms)
		_csv.store_csv_line(PackedStringArray([shot,str(times.size()),str(wall_ms),str(gpu_ms),str(cpu_ms),str(setup_ms),str(drawn-last_drawn),str(posts-last_posts)]))
		last = now; last_drawn = drawn; last_posts = posts
	var elapsed := (Time.get_ticks_usec() - begin) / 1e6
	var drawn_count := Engine.get_frames_drawn() - drawn_start
	var posts_count := _post_draw_total - posts_start
	var sorted := times.duplicate()
	sorted.sort()
	var count := times.size()
	var result := {
		"shot":shot,"wall_seconds":elapsed,"process_frame_count":count,
		"mean_fps":count / maxf(elapsed,.000001),
		"mean_frame_ms":mean(times),"median_frame_ms":percentile(sorted,.5),"p95_frame_ms":percentile(sorted,.95),
		"gpu_render_ms_mean":mean(gpu),"cpu_render_ms_mean":mean(cpu),"cpu_frame_setup_ms_mean":mean(setup),
		"engine_frames_drawn_delta":drawn_count,"frame_post_draw_count":posts_count,
		"engine_drawn_per_process_frame":float(drawn_count)/maxi(count,1),
		"post_draw_per_process_frame":float(posts_count)/maxi(count,1),
		"gpu_timing_available":gpu.max() > 0.0 if not gpu.is_empty() else false,
		"camera_position":[main.cam.global_position.x,main.cam.global_position.y,main.cam.global_position.z],
		"camera_basis":[vector_values(main.cam.global_basis.x),vector_values(main.cam.global_basis.y),vector_values(main.cam.global_basis.z)],
		"camera_fov":main.cam.fov,
		"memory":memory_snapshot(),
	}
	print("BENCH_SHOT ", JSON.stringify(result))
	return result

func vector_values(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values: total += value
	return total / maxi(values.size(), 1)

func percentile(sorted: Array[float], fraction: float) -> float:
	if sorted.is_empty(): return 0.0
	var index := fraction * (sorted.size() - 1)
	return lerpf(sorted[int(floor(index))], sorted[int(ceil(index))], index - floor(index))

func memory_snapshot() -> Dictionary:
	return {"engine_static_bytes":OS.get_static_memory_usage(),
		"gpu_texture_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"gpu_buffer_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)}

func wait_seconds(seconds: float) -> void:
	var until := Time.get_ticks_usec() + int(seconds * 1e6)
	while Time.get_ticks_usec() < until: await process_frame

func wait_for_scene(path: String, timeout_seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(timeout_seconds * 1000)
	while Time.get_ticks_msec() < until:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path: return true
	return false

func finish() -> void:
	if _finished: return
	_finished = true
	if _csv != null: _csv.close()
	var result := {
		"variant":variant,"seed":SEED,"resolution":[1920,1080],"quality":"HIGH",
		"time_scale":1.0,"physics_ticks":60,"fps_limit":0,"vsync":"disabled",
		"interface":"normal HUD and ability hand; team/setup/help/hover overlays closed",
		"warmup_seconds":warmup_seconds,"measure_seconds":measure_seconds,
		"stages":stage,"creatures":roster,"shots":results,"failures":failures,
		"adapter":RenderingServer.get_video_adapter_name(),"godot_version":Engine.get_version_info(),
		"limitation":"Reproduced legacy six-creature preparation path versus startup catalogue in the same current code; no historical pre-task snapshot. Baseline loading overlay exists only in this test. Minimized offscreen rendering without screen presentation or swap; FPS is not fullscreen player FPS. Driver/OS caches are not flushed. Animated idle, cloth, particles and shader TIME prevent pixel-identical screenshots. GPU/CPU values measure the latest viewport draw, and draw/process counters expose any extra force_draw rendering.",
	}
	var file := FileAccess.open(out_dir.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  ")); file.close()
	if is_instance_valid(main):
		main._release_game_resources()
		main.queue_free()
	elif current_scene != null:
		current_scene.queue_free()
	main = null
	await process_frame
	await process_frame
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await process_frame
	await create_timer(.2,true,false,true).timeout
	print("LOADING_FPS_BENCHMARK ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
