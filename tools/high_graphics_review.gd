extends SceneTree
## Сравнение света и теней уровней без показа тестового окна.
var main: Node
var failures := 0
var report: Array = []
var out_dir := "user://high-graphics"
func _initialize() -> void:
	if not has_meta("sfery_background_draw"):
		preload("res://tools/test_window.gd").background(self)
	call_deferred("run")
func _finalize() -> void: preload("res://tools/test_window.gd").finish(self)
func check(ok: bool, reason: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", reason)
func frames(n: int) -> void:
	for i in n: await process_frame
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name+".png"))
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir=args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.max_fps=60
	GraphicsSettings.max_fps=60
	GraphicsSettings.level=GraphicsSettings.Level.MEDIUM
	root.size=Vector2i(1280,720)
	main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(3)
	main._preview_arena_location(0)
	main.team_menu.hide()
	main.ui_layer.visible=false
	main.arena._motes.emitting=false
	var ball := CreatureBall.new()
	main.world.add_child(ball)
	ball.setup(CardDB.creature(&"creature_dragnar_fire"),0)
	ball.freeze_at(Vector3(10,.36,11))
	ball.set_label_allowed(false)
	await ball.open_animated(false)
	ball._anim.idle_on=false
	ball._anim.set_process(false)
	ball.set_process(false)
	for level in [GraphicsSettings.Level.LOW,GraphicsSettings.Level.MEDIUM,GraphicsSettings.Level.HIGH,GraphicsSettings.Level.MEDIUM]:
		GraphicsSettings.level=level
		main.apply_graphics()
		main.cam.snap_overview()
		await frames(60 if level==GraphicsSettings.Level.HIGH else 12)
		var name := GraphicsSettings.level_name(level)
		var suffix := str(report.size())+"-"+str(level)
		await shot(suffix+"-wide")
		main.cam._set_static(Vector3(39,12,36),Vector3(7,4,4),{"fov":54.0,"smooth":4.0,"hand":0.0})
		main.cam.cut()
		await frames(12)
		await shot(suffix+"-shadow")
		var textures: Array = []
		for l in main.arena._sanctuary_lights:
			if l.has_meta("window_projector"):
				textures.append(l.light_projector.get_width())
				check(l.shadow_enabled,"projector retains a valid shadow matrix")
		var high: bool = level==GraphicsSettings.Level.HIGH
		check(root.positional_shadow_atlas_size==(8192 if high else 1024),"positional atlas follows quality")
		check(main._env.ssil_enabled==high and main._env.ssr_enabled==high,"indirect/reflection are high only")
		check(root.msaa_3d==(Viewport.MSAA_4X if high else Viewport.MSAA_DISABLED),"MSAA follows quality")
		for width in textures:check(width==(512 if high else 128),"window cookie resolution follows quality")
		report.append({"level":name,"atlas":root.positional_shadow_atlas_size,"msaa":root.msaa_3d,"ssil":main._env.ssil_enabled,"ssr":main._env.ssr_enabled,"projector_pixels":textures})
	main._env.ssr_enabled=false
	main._env.ssil_enabled=false
	await frames(4)
	main.queue_free()
	await frames(12)
	if is_instance_valid(SoundFx._inst):SoundFx._inst.queue_free()
	await create_timer(.2,true,false,true).timeout
	var f:=FileAccess.open(out_dir.path_join("summary.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"failures":failures,"quality":report,"limits":["not an FPS benchmark","NVIDIA/Vulkan only","test window minimized"]},"  "))
	print("HIGH GRAPHICS ",JSON.stringify({"failures":failures,"quality":report}))
	quit(1 if failures else 0)
