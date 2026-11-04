extends SceneTree
## Узкий воспроизводимый осмотр окружения меню, без Boot и подготовки существ.
## Запуск только свёрнуто, вне экрана; test_window удерживает60FPS.
var menu: MainMenu
var output := "res://build/checks/menu-environment/open-panorama"
var failures := 0
var checks := 0
var luma := {}

func _initialize() -> void:
	preload("res://tools/test_window.gd").background(self)
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	_run.call_deferred()

func _finalize() -> void:
	preload("res://tools/test_window.gd").finish(self)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1
	print("PASS: " if condition else "FAIL: ", message)

func frames(count: int) -> void:
	for _i in range(count): await process_frame

func capture(size: Vector2i, phase: float, name: String) -> void:
	root.size = size
	menu.city.phase = phase
	menu.city.anim_t = 0.0
	menu.city._parallax = Vector2.ZERO
	menu.city._update(0.0)
	await frames(20)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size() == size, name + " viewport size")
	check(image.save_png(output.path_join(name + ".png")) == OK, name + " PNG saved")
	var sum := 0.0
	var count := 0
	for y in range(int(size.y*.86),int(size.y*.96),3):
		for x in range(int(size.x*.64),int(size.x*.80),3):
			var c := image.get_pixel(x,y)
			sum += c.r*.2126+c.g*.7152+c.b*.0722
			count += 1
	luma[name] = sum/maxi(count,1)
	check(Engine.max_fps == 60 and root.unfocusable and root.mode == Window.MODE_MINIMIZED, name + " safe60FPS window")
	for button in menu._buttons:
		check(root.get_visible_rect().encloses(button.get_global_rect()), name + " visible button: " + button.text)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
	GraphicsSettings.max_fps = 60
	root.size = Vector2i(1920,1050)
	menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	menu.city.paused = true
	await frames(90)
	await capture(Vector2i(1920,1050), .66, "wide-day")
	await capture(Vector2i(960,540), .66, "narrow-day")
	await capture(Vector2i(1920,1050), .752, "wide-sunset")
	await capture(Vector2i(1920,1050), .0, "wide-night")
	check(menu.city.get_node_or_null("Overlook") == null,"open panorama has no foreground platform")
	check(menu.city.find_children("*","Light3D",true,false).size() == 1,"one existing directional light, no added local lights")
	check(menu.city.cam.environment == menu.city.env,"camera keeps menu environment")
	check(luma["wide-night"] < luma["wide-day"]*.65,"night darkens the near bank")
	GraphicsSettings.force_level(GraphicsSettings.Level.LOW)
	menu.city.apply_quality(GraphicsSettings.Level.LOW)
	await capture(Vector2i(960,540), .0, "narrow-night-low")
	GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
	menu.city.apply_quality(GraphicsSettings.Level.HIGH)
	var result := {"checks": checks, "failures": failures, "near_bank_luminance":luma, "max_fps": Engine.max_fps, "limits": ["standalone menu without Boot or match", "minimized NVIDIA/Vulkan texture rendering", "muted audio, no listening", "not a performance benchmark"]}
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	print("MENU ENVIRONMENT ", JSON.stringify(result))
	menu.queue_free()
	await frames(3)
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(3)
	quit(1 if failures else 0)
