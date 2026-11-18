extends SceneTree
## Narrow real Boot/menu LOW diagnostic; common background wrapper enforces 60 FPS.
var out := "res://build/checks/presentation/low-load"
var rows: Array = []
var checks := 0
var failures := 0
var preview: SubViewport
var source_hashes: Dictionary = {}
var functional_only := false
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: " + message)
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await process_frame
func cpu_ticks() -> int:
	var result: Array = []
	OS.execute("cat", ["/proc/%d/stat" % OS.get_process_id()], result)
	var raw := String(result[0]) if not result.is_empty() else ""
	var p := raw.substr(raw.rfind(")") + 2).split(" ")
	return int(p[11]) + int(p[12]) if p.size() > 12 else -1
func measure(label: String, city: MenuCity) -> void:
	city.anim_t=0.0
	city.phase=.5
	await frames(180)
	var cpu0 := cpu_ticks()
	var begin := Time.get_ticks_usec()
	var gpu := 0.0
	var preview_gpu := 0.0
	var rcpu := 0.0
	var draws := 0.0
	var process_ms := 0.0
	var samples := 360
	for i in samples:
		await process_frame
		if preview != null: preview_gpu += RenderingServer.viewport_get_measured_render_time_gpu(preview.get_viewport_rid())
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		rcpu += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
	var seconds := (Time.get_ticks_usec()-begin)/1000000.0
	check(cpu0>=0,"Linux CPU counter readable")
	var row := {"mode":label,"samples":samples,"seconds":seconds,"fps":samples/seconds,"cpu_process_one_core_percent":float(cpu_ticks()-cpu0)/seconds,"gpu_ms":gpu/samples,"preview_gpu_ms":preview_gpu/samples,"render_cpu_ms":rcpu/samples,"process_ms":process_ms/samples,"draws":draws/samples,"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"sky_mode":city.env.sky.process_mode,"sky_size":city.env.sky.radiance_size,"ambient_source":city.env.ambient_light_source,"reflection_source":city.env.reflected_light_source,"root_disable_3d":root.disable_3d,"city_visible":city.visible,"city_processing":city.can_process(),"scale_3d":root.scaling_3d_scale}
	rows.append(row)
	print("LOW_LOAD ", JSON.stringify(row))
	if city.has_meta("measurement_only"): city.free()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
	functional_only=OS.get_environment("ORBSTRIKE_LOW_FUNCTIONAL_ONLY")=="1"
	DirAccess.make_dir_recursive_absolute(out)
	for path in ["scenes/menu/main_menu.gd","scenes/menu/menu_settings.gd","scenes/menu/menu_city.gd","scenes/graphics_settings.gd","scenes/main.gd","scenes/arena.gd","scenes/ui/team_menu.gd","scenes/ui/creature_preview.gd","scenes/ui/vrm_preview.gd"]:
		source_hashes[path]=FileAccess.get_sha256("res://"+path)
	GraphicsSettings.force_level(GraphicsSettings.Level.LOW)
	GraphicsSettings.max_fps=60
	Engine.max_fps=60
	root.size=Vector2i(1280,720)
	root.content_scale_size=root.size
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	change_scene_to_file("res://scenes/loading/boot.tscn")
	var deadline := Time.get_ticks_msec()+180000
	while current_scene == null or current_scene.scene_file_path != "res://scenes/menu/main_menu.tscn":
		await process_frame
		if Time.get_ticks_msec()>deadline:
			printerr("FAIL: Boot timeout")
			quit(1)
			return
	var menu: MainMenu=current_scene
	var city: MenuCity=menu.city
	city.paused=true
	GraphicsSettings.set_option("vsync",false)
	root.scaling_3d_scale=1.0
	if OS.get_environment("ORBSTRIKE_LOW_SKY_DIAGNOSTIC")=="1":
		city.env.sky.radiance_size=Sky.RADIANCE_SIZE_256
		city.env.sky.process_mode=Sky.PROCESS_MODE_REALTIME
		await measure("before-realtime256",city)
		city.env.sky.process_mode=Sky.PROCESS_MODE_QUALITY
		city.env.sky.radiance_size=Sky.RADIANCE_SIZE_64
		await measure("quality64",city)
	# Real full-screen editor, with its own live 3D preview. Reconstruct old city
	# visibility on the same current source; only hidden background work differs.
	menu._on_character()
	await frames(30)
	var editor: CharacterEditor=menu._character_editor
	preview=editor.viewport
	RenderingServer.viewport_set_measure_render_time(preview.get_viewport_rid(),true)
	root.scaling_3d_scale=1.0
	preview.scaling_3d_scale=1.0
	menu._uncover_background(editor)
	city.env.sky.radiance_size=Sky.RADIANCE_SIZE_256
	city.env.sky.process_mode=Sky.PROCESS_MODE_REALTIME
	if not functional_only: await measure("editor-before-live-background",city)
	editor._set_playing(false)
	await frames(3)
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	before.save_png(out.path_join("editor-before.png"))
	menu._cover_background(editor)
	await frames(3)
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()
	after.save_png(out.path_join("editor-after.png"))
	check(before.get_data()==after.get_data(),"full-screen editor pixels unchanged when hidden background is disabled")
	editor._set_playing(true)
	if not functional_only: await measure("editor-after-hidden-background",city)
	check(editor.preview_time>0.0 and preview.render_target_update_mode!=SubViewport.UPDATE_DISABLED,"editor preview still animates and draws")
	preview=null
	editor._close()
	await frames(3)
	check(city.visible and city.can_process() and not root.disable_3d,"closing editor restores city and root 3D")
	menu._on_character()
	await frames(4)
	menu._character_editor.queue_free()
	await frames(4)
	check(city.visible and city.can_process() and not root.disable_3d and menu._column.visible,"unexpected editor removal restores background")
	await test_settings(menu)

	check(Engine.max_fps==60,"test FPS cap")
	if is_instance_valid(current_scene): current_scene.queue_free()
	await frames(3)
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	await frames(3)
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(3)
	var report := {"adapter":RenderingServer.get_video_adapter_name(),"date":Time.get_datetime_string_from_system(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":root.size,"quality":"LOW","fps_cap":Engine.max_fps,"source_hashes":source_hashes,"checks":checks,"failures":failures,"rows":rows}
	FileAccess.open(out.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("Low-load benchmark: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func select_option(control: OptionButton, index: int) -> void:
	control.select(index)
	control.item_selected.emit(index)
	await frames(3)
func test_settings(menu: MainMenu) -> void:
	menu._on_settings()
	await frames(4)
	var panel: MenuSettings=menu._settings
	check(panel.visible and root.gui_get_focus_owner()==panel._first,"normal menu opens settings and focuses profile")
	await select_option(panel._controls.preset,GraphicsSettings.Level.HIGH)
	await select_option(panel._controls.render_scale,GraphicsSettings.RENDER_SCALES.find(.67))
	await select_option(panel._controls.shadow_quality,0)
	await select_option(panel._controls.antialiasing,1)
	await select_option(panel._controls.screen_effects,0)
	await select_option(panel._controls.scene_detail,0)
	check(is_equal_approx(root.scaling_3d_scale,.67) and not menu.city.sun.shadow_enabled,"custom scale and shadow controls immediately affect actual menu")
	check(root.screen_space_aa==Viewport.SCREEN_SPACE_AA_FXAA and not menu.city.env.glow_enabled,"custom antialiasing and effects apply")
	check(GraphicsSettings.is_custom(),"manual quality recorded as custom")
	panel.close()
	GraphicsSettings.custom_options.clear()
	GraphicsSettings.level=-1
	GraphicsSettings.max_fps=-1
	GraphicsSettings.load_settings()
	menu._on_settings()
	await frames(4)
	check(panel._controls.render_scale.selected==1 and panel._controls.shadow_quality.selected==0 and panel._controls.antialiasing.selected==1,"save/reload/reopen preserves independent custom choices")
	for size_value in [Vector2i(640,360),Vector2i(480,720),Vector2i(960,540),Vector2i(1280,720)]:
		root.size=size_value
		root.content_scale_size=size_value
		await frames(4)
		check(Rect2(Vector2.ZERO,Vector2(size_value)).encloses(panel._panel.get_global_rect()),"settings panel fits "+str(size_value))
		var done: Button=panel.find_child("SettingsDone",true,false)
		check(panel._panel.get_global_rect().encloses(done.get_global_rect()),"done remains visible "+str(size_value))
		check(panel._scroll.get_v_scroll_bar().max_value>panel._scroll.size.y,"long settings scrolls "+str(size_value))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("settings-%dx%d.png" % [size_value.x,size_value.y]))
	panel._controls.antialiasing.grab_focus()
	await key(KEY_TAB)
	check(root.gui_get_focus_owner()==panel._controls.screen_effects,"Tab follows custom controls inside scrolling settings")
	await key(KEY_TAB,true)
	check(root.gui_get_focus_owner()==panel._controls.antialiasing,"ShiftTab reverses settings focus")
	panel._controls.fps.select(0)
	panel._controls.fps.item_selected.emit(0)
	check(Engine.max_fps==30 and GraphicsSettings.fps_limit()==30,"30 FPS selection applies immediately")
	await frames(2)
	check(Engine.max_fps==60,"test wrapper retains60FPS independently of saved FPS choice")
	await select_option(panel._controls.fps,GraphicsSettings.FPS_OPTIONS.find(60))
	await select_option(panel._controls.preset,GraphicsSettings.Level.LOW)
	check(GraphicsSettings.custom_options.size()==1 and not GraphicsSettings.is_custom(),"LOW clears manual quality while preserving vsync preference")
	check(is_equal_approx(root.scaling_3d_scale,.75) and not menu.city.sun.shadow_enabled,"LOW actual menu scale .75 and no shadows")
	check(root.msaa_3d==Viewport.MSAA_DISABLED and root.screen_space_aa==Viewport.SCREEN_SPACE_AA_DISABLED and not menu.city.env.glow_enabled,"LOW has no AA or screen effects")
	var main: Node=GameLoading.i()._game
	check(not main._sun.shadow_enabled and not main._env.ssao_enabled and not main._env.ssil_enabled and not main._env.ssr_enabled,"resident real match applies LOW light and effects")
	panel.close()
	# Enter the prepared game through its normal menu route before opening team settings.
	ArenaLocations.choose(3)
	menu._enter_game("")
	var enter_deadline := Time.get_ticks_msec()+10000
	while current_scene!=main and Time.get_ticks_msec()<enter_deadline: await process_frame
	await frames(6)
	check(current_scene==main and main.team_menu.is_visible_in_tree(),"normal menu route enters prepared team selection")
	main.team_menu._graphics_button.pressed.emit()
	await frames(4)
	var team_panel: MenuSettings=main.team_menu.get_node_or_null("TeamSettings")
	check(team_panel!=null and team_panel.is_visible_in_tree(),"team settings button opens full dialog")
	if team_panel!=null: team_panel.close()
	await frames(3)
	var actor_builds := GameLoading.i().actor_build_count
	var arena_builds := GameLoading.i().arena_build_count
	main.team_menu._rng.seed=777
	main.rng.seed=777
	main.team_menu.pick_random_and_start()
	var match_deadline := Time.get_ticks_msec()+20000
	while not main._lifecycle.input_allowed() and Time.get_ticks_msec()<match_deadline:
		if main._lifecycle.intro!=null: await key(KEY_ESCAPE)
		else: await process_frame
	await frames(40)
	check(main._lifecycle.input_allowed() and main.ctrl!=null,"actual local match enters after intro through normal start")
	check(main.arena.location_id==3 and main.arena.is_visible_in_tree(),"real resident Stone Bay is active")
	check(GameLoading.i().actor_build_count==actor_builds and GameLoading.i().arena_build_count==arena_builds,"match leases prepared actors and arena without rebuilding")
	check(is_equal_approx(root.scaling_3d_scale,.75) and not main._sun.shadow_enabled,"actual match preserves applied LOW resolution and sun shadows")
	check(not main._env.ssao_enabled and not main._env.ssil_enabled and not main._env.ssr_enabled and int(GraphicsSettings.param("motes"))==70 and not bool(GraphicsSettings.param("floaters")),"actual match LOW effects and decoration policy")
	main.cam.snap_overview()
	main.cam.set_process(false)
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("match-low.png"))
	# Reconstruct the previous effective LOW raster settings on this same scene.
	GraphicsSettings.overrides["shadow_enabled"]=true
	GraphicsSettings.overrides["render_scale"]=1.0
	main.apply_graphics()
	if not functional_only: await measure("arena-old-effective-low-scale1-shadows",menu_city_for_measure(main))
	GraphicsSettings.overrides.clear()
	main.apply_graphics()
	if not functional_only: await measure("arena-new-low-scale075-no-sun-shadows",menu_city_for_measure(main))

func menu_city_for_measure(_main: Node) -> MenuCity:
	# Measurement metadata needs a sky holder; detached fixture has no processing.
	var holder := MenuCity.new()
	holder.env=Environment.new()
	holder.env.sky=Sky.new()
	holder.set_meta("measurement_only",true)
	return holder

func key(code: Key, shift: bool = false) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.shift_pressed=shift
		event.pressed=down
		Input.parse_input_event(event)
		await process_frame
	await frames(3)
