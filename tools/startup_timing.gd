extends SceneTree
## Узкий замер реального Boot до меню, без матчей и массовых тестовых профилей.
var output := "user://startup-timing.json"
var variant := "after"
var stages: Dictionary = {}
var begin := 0
var last_stage := ""
var last_tick := 0

func _initialize() -> void:
	preload("res://tools/test_window.gd").background(self)
	call_deferred("run")

func _finalize() -> void:
	preload("res://tools/test_window.gd").finish(self)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: output = args[0]
	if args.size() > 1: variant = args[1]
	Engine.max_fps = 60
	GraphicsSettings.max_fps = 60
	GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
	ArenaLocations._current = 0
	root.size = Vector2i(1280,720)
	root.unfocusable = true
	if ResourceLoader.exists("res://scenes/loading/preparation_store.gd"):
		var store = load("res://scenes/loading/preparation_store.gd")
		store.enabled = variant != "before"
		store.writing_enabled = variant == "build"
	begin = Time.get_ticks_usec()
	last_tick = begin
	change_scene_to_file("res://scenes/loading/boot.tscn")
	while current_scene == null or current_scene.scene_file_path != "res://scenes/menu/main_menu.tscn":
		await process_frame
		if Time.get_ticks_usec()-begin > 180000000:
			printerr("FAIL: startup timeout")
			quit(1)
			return
		var boot := current_scene
		if boot != null and boot.get("_status") != null:
			var title: String = boot._status.text.split(" · ")[0]
			if title != last_stage:
				if not last_stage.is_empty(): stages[last_stage] = (Time.get_ticks_usec()-last_tick)/1000.0
				last_stage = title
				last_tick = Time.get_ticks_usec()
	if not last_stage.is_empty(): stages[last_stage] = (Time.get_ticks_usec()-last_tick)/1000.0
	var elapsed := (Time.get_ticks_usec()-begin)/1000000.0
	var pool := GameLoading.i()
	var totals := {"animations":0.0,"support":0.0,"cloth":0.0,"total":0.0}
	var per_model: Dictionary = {}
	var all_balls: Array = []
	for list in pool._balls.values(): all_balls.append_array(list)
	if pool._game.team_menu._preview._borrowed_ball != null:
		all_balls.append(pool._game.team_menu._preview._borrowed_ball)
	for ball in all_balls:
		var data: Dictionary = ball._anim.preparation_ms
		for key in totals: totals[key] += float(data[key])
		if not per_model.has(String(ball.def.id)): per_model[String(ball.def.id)] = []
		per_model[String(ball.def.id)].append(data.duplicate())
	var result := {"variant":variant,"seconds_to_menu":elapsed,"stage_wall_ms":stages,"actor_cpu_ms":totals,
		"model_cpu_ms":per_model,"prepared_actors":pool.actor_build_count,"arenas":pool.arena_build_count,
		"resolution":[1280,720],"quality":"HIGH","limits":"minimized offscreen; not FPS; fresh process, OS caches retained"}
	if ResourceLoader.exists("res://scenes/loading/preparation_store.gd"):
		var store = load("res://scenes/loading/preparation_store.gd")
		result["cache"] = store.statistics()
	if variant == "after":
		# Один необходимый интеграционный путь: кэш остаётся пригоден для матча
		# и повторной игры, новой подготовки актёров после меню нет.
		var counts := [pool.actor_build_count,pool.arena_build_count]
		pool.show_game()
		await process_frame
		var game := current_scene
		game.team_menu._preview.release()
		game.team_menu.pick_random_and_start()
		game.events.drained.disconnect(game._pump)
		for frame in 30:
			await process_frame
			if not game._preparing: break
		var ok: bool = not game._preparing and game.ctrl._started and game._prepared_balls.size() == 6
		ok = ok and root.world_3d.environment == game._env
		for ball in game._prepared_balls.values():
			ok = ok and ball._anim != null and not ball.visible and ball.process_mode == Node.PROCESS_MODE_DISABLED
		game._on_restart()
		await process_frame
		await process_frame
		ok = ok and current_scene != game and root.world_3d.environment == current_scene._env
		ok = ok and counts == [pool.actor_build_count,pool.arena_build_count]
		result["cached_match_and_restart_ok"] = ok
		if not ok: printerr("FAIL: cached startup match/restart")
	print("STARTUP TIMING ",JSON.stringify(result))
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	if current_scene.has_method("_release_game_resources"): current_scene._release_game_resources()
	current_scene.queue_free()
	await process_frame
	pool.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await process_frame
	await create_timer(.2,true,false,true).timeout
	quit()
