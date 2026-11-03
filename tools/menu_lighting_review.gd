extends SceneTree
## Реальный Boot → меню: глобальный WorldEnvironment, переход суток и возврат света.
## Все кадры получены в свёрнутом нефокусируемом окне.
const WindowTest := preload("res://tools/test_window.gd")
var failures := 0
var checks := 0
var out_dir := "user://menu-lighting"
var menu: Node
var loader: GameLoading
var captures: Dictionary = {}
var metrics: Dictionary = {}

func _initialize() -> void:
	if not has_meta("sfery_background_draw"):
		WindowTest.background(self)
	call_deferred("run")

func _finalize() -> void:
	WindowTest.finish(self)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func frames(count: int) -> void:
	for frame in count:
		await process_frame

func wait_scene(path: String, previous: Node = null) -> bool:
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene != previous and current_scene.scene_file_path == path:
			return true
	return false

func snapshot(phase: float, name: String) -> Image:
	var city: MenuCity = menu.city
	city.phase = phase
	city.anim_t = 0.0
	city._parallax = Vector2.ZERO
	city._update(0.0)
	await frames(12)
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.save_png(out_dir.path_join(name + ".png"))
	captures[name] = result
	return result

func luminance(image: Image, region: Rect2) -> float:
	var total := 0.0
	var samples := 0
	var rect := Rect2i(Vector2(image.get_width(),image.get_height()) * region.position, Vector2(image.get_width(),image.get_height()) * region.size)
	for y in range(rect.position.y, rect.end.y, 3):
		for x in range(rect.position.x, rect.end.x, 3):
			var color := image.get_pixel(x,y)
			total += color.r*.2126 + color.g*.7152 + color.b*.0722
			samples += 1
	return total / maxi(samples,1)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir=args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
	GraphicsSettings.max_fps=60
	Engine.max_fps=60
	Engine.time_scale=1.0
	root.size=Vector2i(1280,720)
	root.unfocusable=true
	change_scene_to_file("res://scenes/loading/boot.tscn")
	if not await wait_scene("res://scenes/menu/main_menu.tscn"):
		check(false,"Boot reaches main menu")
		await finish()
		return
	menu=current_scene
	loader=GameLoading.i()
	var city: MenuCity = menu.city
	city.paused=true
	menu.ui.visible=false
	check(loader.ready_to_play and loader._game != null,"prepared game remains resident behind menu")
	check(root.world_3d.environment == city.env,"menu owns root World3D after reparent")
	check(city.cam.environment == city.env,"menu camera explicitly uses its changing environment")
	check(not loader._game.world.visible and not loader._game._sun.is_visible_in_tree() and not loader._game._fill.is_visible_in_tree(),"prepared battle lights are hidden")
	var main_environment: WorldEnvironment = loader._game.world.find_children("*","WorldEnvironment",true,false)[0]
	check(main_environment.environment == null and main_environment.has_meta("loading_parked_environment"),"hidden prepared game releases global environment")
	var day := await snapshot(.5,"day")
	var night := await snapshot(.0,"night")
	var regions := {
		"city":Rect2(.40,.38,.53,.28),
		"foreground":Rect2(.05,.77,.87,.18),
		"skyline":Rect2(.25,.20,.65,.15),
	}
	for name in regions:
		var day_value := luminance(day,regions[name])
		var night_value := luminance(night,regions[name])
		metrics[name] = {"day":day_value,"night":night_value,"night_to_day":night_value / maxf(day_value,.0001)}
		check(day_value > .015,"day shows " + name)
		check(night_value < day_value*.78,"night darkens " + name)
	check(city._bld_mat.get_shader_parameter("win_on") > .25,"windows light up at night")
	check(city.env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY,"city fill follows changing sky")
	check(root.world_3d.environment == city.env,"day/night keeps ownership of global environment")
	# Воспроизводим прежнее загрязнение для диагностического кадра: скрытая Main
	# имела первое Environment, а явной привязки city.cam.environment не было.
	city.cam.environment=null
	root.world_3d.environment=loader._game._env
	await snapshot(.0,"previous-contamination-night")
	city.cam.environment=city.env
	root.world_3d.environment=city.env
	var returned := await snapshot(.5,"day-return")
	for name in regions:
		check(absf(luminance(returned,regions[name])-luminance(day,regions[name])) < .025,"day returns consistently for " + name)
	# Переход из меню должен вернуть именно игровое окружение.
	menu.ui.visible=true
	menu._on_play()
	if await wait_scene("res://scenes/main.tscn",menu):
		var game: Node = current_scene
		await frames(2)
		check(root.world_3d.environment == game._env,"entering prepared game restores battle environment")
		var active_environment: WorldEnvironment = game.world.find_children("*","WorldEnvironment",true,false)[0]
		check(active_environment.environment == game._env,"battle environment node restored without rebuild")
		var first_game := game
		game._on_restart()
		if await wait_scene("res://scenes/main.tscn",first_game):
			await frames(2)
			check(root.world_3d.environment == current_scene._env,"restart owns the new battle environment after old scene exits")
			check(not is_instance_valid(first_game),"old scene is released after restart")
		else:
			check(false,"restart creates the next prepared game")
	else:
		check(false,"main menu opens prepared game")
	await finish()

func finish() -> void:
	if current_scene != null:
		if current_scene.has_method("_release_game_resources"): current_scene._release_game_resources()
		current_scene.queue_free()
	await frames(2)
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	await frames(2)
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(2)
	await create_timer(.2,true,false,true).timeout
	captures.clear()
	var result := {"checks":checks,"failures":failures,"regions":metrics,"limits":["minimized NVIDIA/Vulkan rendering","not an FPS benchmark"]}
	var file:=FileAccess.open(out_dir.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("MENU LIGHTING ",JSON.stringify(result))
	quit(1 if failures else 0)
