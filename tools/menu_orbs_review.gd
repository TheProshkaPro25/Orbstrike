extends SceneTree
## Только перенос ночного кольца: реальные PNG и проекция анимации, без Boot/матчей.
const WindowTest := preload("res://tools/test_window.gd")
var menu: MainMenu
var checks := 0
var failures := 0
var output := "res://build/checks/menu-orbs-mountains"
var bounds := Rect2()
func _initialize() -> void:
	WindowTest.background(self)
	call_deferred("run")
func _finalize() -> void: WindowTest.finish(self)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
func frames(n: int) -> void:
	for i in n: await process_frame
func check_ring() -> void:
	var camera: Camera3D = menu.city.cam
	var viewport: Vector2 = root.get_visible_rect().size
	var padded := Rect2(Vector2(viewport.x*.64,viewport.y*.12),Vector2(viewport.x*.32,viewport.y*.41))
	for i in range(6):
		var item: Transform3D = menu.city.orbs._mm.get_instance_transform(i)
		var projected := camera.unproject_position(item.origin)
		check(not camera.is_position_behind(item.origin),"сфера перед камерой")
		# Запас включает ореол и максимальный разлёт искр, а не только центр билборда.
		var margin: Vector2 = (camera.unproject_position(item.origin+camera.global_basis.x*160.0)-projected).abs()
		var halo := Rect2(projected-Vector2.ONE*margin.x,Vector2.ONE*margin.x*2.0)
		check(padded.encloses(halo),"кольцо с искрами целиком в правом небе")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	GraphicsSettings.force_level(GraphicsSettings.Level.HIGH)
	GraphicsSettings.max_fps=60
	root.size=Vector2i(1280,720)
	root.content_scale_size=root.size
	menu=load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	menu.city.paused=true
	await frames(150)
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size=size
		root.content_scale_size=size
		await frames(5)
		for t in [0.0,15.0,30.0,45.0,60.0]:
			menu.city.phase=.025
			menu.city.anim_t=t
			menu.city._parallax=Vector2.ZERO
			menu.city._update(0.0)
			check_ring()
		menu.city.phase=.025
		menu.city.anim_t=15.0
		menu.city._update(0.0)
		await frames(12)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output.path_join("night-%d.png"%size.x))==OK,"PNG ночного меню")
		check(root.mode==Window.MODE_MINIMIZED and root.unfocusable and Engine.max_fps==60,"свёрнутое нефокусируемое окно60FPS")
		for button in menu._buttons:
			check(root.get_visible_rect().encloses(button.get_global_rect()),"кнопка меню внутри кадра")
	check(menu.city.orbs._mm.instance_count==6,"шесть прежних сфер")
	var ground_distance := Vector2(MenuOrbs.CENTER.x-MenuCity.CAM_POS.x,MenuOrbs.CENTER.z-MenuCity.CAM_POS.z).length()
	check(ground_distance>4400.0 and ground_distance<5000.0,"кольцо на дальнем плане последнего пояса гор")
	check(menu.city._water_mat.get_shader_parameter("orbs_on")==1.0,"водные отражения включены")
	var f:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"max_fps":Engine.max_fps,"center":str(MenuOrbs.CENTER)},"  "))
	menu.queue_free()
	await frames(3)
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(3)
	print("MENU ORBS RIGHT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
