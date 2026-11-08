extends SceneTree
## Narrow source UI review. Run through tools/check.py's minimized 60 FPS wrapper.
## Isolated settings fixture; no Boot, actors, physical match, or listening.

class UiOnlyTeam extends TeamMenu:
	func _show_preview(_id: StringName, _pose: bool) -> void:
		if _preview != null:
			_preview.show_hint("Проверка интерфейса · 3D-предпросмотр отключён")


var output := "res://build/checks/presentation/device-ui"
var checks := 0
var failures := 0
var menu: MainMenu
var _fixture := "user://device-ui-review-settings.cfg"
var _previous_device_path: String
var _previous_audio_path: String


func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures += 1
	print("PASS: " if condition else "FAIL: ", description)


func frames(count: int) -> void:
	for _i in range(count): await process_frame


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP PNG (headless; no visual acceptance): ", name)
		return
	await frames(4)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size() == root.size, name + " viewport size")
	check(image.save_png(output.path_join(name + ".png")) == OK, name + " saved")
	check(Engine.max_fps == 60 and root.unfocusable and root.mode == Window.MODE_MINIMIZED, name + " minimized unfocusable 60 FPS")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	_previous_device_path = DeviceSettings.settings_path
	_previous_audio_path = AudioSettings.settings_path
	DeviceSettings.settings_path = _fixture
	AudioSettings.settings_path = _fixture
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_fixture))
	DeviceSettings.reload_settings()
	check(DeviceSettings.current() == DeviceSettings.CLASSIC, "missing preference defaults to classic")
	var fixture := ConfigFile.new()
	fixture.set_value("graphics", "sentinel", 17)
	fixture.set_value("audio", "music", 0.6)
	fixture.save(_fixture)
	AudioSettings.load_and_apply()
	GraphicsSettings.force_level(GraphicsSettings.Level.LOW)
	GraphicsSettings.max_fps = 60
	root.size = Vector2i(1280, 720)
	menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	menu.city.paused = true
	await frames(140)
	var shared_theme := UiTheme.get_theme()
	var classic_button: StyleBoxFlat = shared_theme.get_stylebox("normal", "Button")
	check(classic_button.border_color.is_equal_approx(UiTheme.GOLD_DIM), "classic button palette preserved")
	check(menu._buttons[0].text == "Играть", "main menu groups game modes under Play")
	for viewport in [Vector2i(1280,720), Vector2i(960,540)]:
		root.size = viewport
		await frames(6)
		for button in menu._visible_buttons():
			check(root.get_visible_rect().encloses(button.get_global_rect()), "classic menu contains " + button.text + " at " + str(viewport))
		await capture("classic-menu-%d" % viewport.x)
		menu._settings.open()
		await frames(16)
		check(root.get_visible_rect().encloses(menu._settings._panel.get_global_rect()), "classic settings fit " + str(viewport))
		await capture("classic-settings-%d" % viewport.x)
		menu._settings.close()
	var parked := Node.new()
	root.add_child(parked)
	menu.reparent(parked)
	await frames(3)
	menu.reparent(root)
	await frames(3)
	check(DeviceSettings.set_style(DeviceSettings.DEVICE) == OK, "device preference saved")
	DeviceSettings.reload_settings()
	check(DeviceSettings.is_device(), "device preference survives reload")
	fixture.load(_fixture)
	check(int(fixture.get_value("graphics", "sentinel", 0)) == 17, "style write preserves other settings")
	check(UiTheme.get_theme() == shared_theme, "resident UI keeps same shared Theme identity")
	check(shared_theme.get_stylebox("normal", "Button").border_color.is_equal_approx(UiTheme.DEVICE_DIM), "resident button palette changes live")
	check(menu.ui.get_node("DeviceFrame").visible, "reparented resident menu receives device frame")
	check(DeviceSettings.events().changed.is_connected(menu.ui.get_node("DeviceFrame")._changed), "resident frame reconnects after reparent")
	parked.queue_free()
	for viewport in [Vector2i(1280,720), Vector2i(960,540)]:
		root.size = viewport
		await frames(6)
		for button in menu._visible_buttons():
			check(root.get_visible_rect().encloses(button.get_global_rect()), "device menu contains " + button.text + " at " + str(viewport))
		await capture("device-menu-%d" % viewport.x)
		menu._settings.open()
		await frames(16)
		check(root.get_visible_rect().encloses(menu._settings._panel.get_global_rect()), "device settings fit " + str(viewport))
		await capture("device-settings-%d" % viewport.x)
		menu._settings.close()
	menu.ui.hide()
	var team := UiOnlyTeam.new()
	root.add_child(team)
	team.set_process(false)
	for style in [DeviceSettings.CLASSIC,DeviceSettings.DEVICE]:
		DeviceSettings.set_style(style)
		for viewport in [Vector2i(1280,720), Vector2i(960,540)]:
			root.size = viewport
			await frames(8)
			check(root.get_visible_rect().encloses(team._next_btn.get_global_rect()), "team navigation fits " + str(viewport))
			await capture(("device" if style == DeviceSettings.DEVICE else "classic")+"-team-%d" % viewport.x)
	team.queue_free()
	await frames(3)
	var career_panel: Control = load("res://scenes/ui/career_panel.gd").new()
	var career: RefCounted = load("res://core/career.gd").create("fire",1,92026,"Проверка","" )
	root.add_child(career_panel)
	career_panel.display(career)
	for style in [DeviceSettings.CLASSIC,DeviceSettings.DEVICE]:
		DeviceSettings.set_style(style)
		for viewport in [Vector2i(1280,720), Vector2i(960,540)]:
			root.size = viewport
			await frames(6)
			check(root.get_visible_rect().encloses(career_panel._action.get_global_rect()), "career action fits " + str(viewport))
			await capture(("device" if style == DeviceSettings.DEVICE else "classic")+"-career-%d" % viewport.x)
	career_panel.queue_free()
	await frames(3)
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.theme = shared_theme
	root.add_child(canvas)
	var background := ColorRect.new()
	background.color = Color(0.075, 0.10, 0.14)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(background)
	var battle := BattleHud.new()
	canvas.add_child(battle)
	var fighter := FighterPlate.new(0, "Ваш персонаж")
	fighter.position = Vector2(24,300)
	canvas.add_child(fighter)
	fighter.set_team([Color.RED,Color.CYAN,Color.PURPLE],[0,1,4])
	fighter.set_active(true)
	fighter.set_gates(2)
	fighter.set_momentum(1)
	for style in [DeviceSettings.CLASSIC, DeviceSettings.DEVICE]:
		DeviceSettings.set_style(style)
		await frames(4)
		for viewport in [Vector2i(1280,720), Vector2i(960,540)]:
			root.size = viewport
			battle.open(["Дракон Пламени", "Страж Прилива"], [0,5], [680,720])
			battle.set_chain([], [false,false],0,[],[1,2])
			await frames(40)
			for plate in battle._plates:
				check(root.get_visible_rect().encloses(plate.get_global_rect()), "battle panel fits " + str(viewport) + " style " + str(style))
			check(battle._powers[0].text == "680" and battle._powers[1].text == "720", "presentation preserves actual powers")
			await capture(("device" if style == DeviceSettings.DEVICE else "classic")+"-battle-%d" % viewport.x)
			battle.close()
			await frames(20)
	var sound := SoundFx.i()
	for cue in SoundFx.DEVICE_SFX_NAMES:
		check(sound.has_sfx(cue), "preloaded original cue " + cue)
	var loads := sound.catalog_load_count
	var button := Button.new()
	canvas.add_child(button)
	sound._on_node_added(button)
	sound._on_node_added(button)
	check(button.pressed.get_connections().size() == 1, "automatic click hooked once after repeated notifications")
	AudioSettings.set_volume("Interface", 0.35)
	AudioSettings.set_interface_muted(false)
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Interface")), SoundFx.SFX_DB+linear_to_db(.35)), "independent interface gain")
	var next := sound._next
	button.pressed.emit()
	check(sound._next == (next+1)%SoundFx.POOL, "one button press schedules exactly one sound")
	next = sound._next
	button.pressed.emit()
	check(sound._next == next, "duplicate click in same instant throttled")
	sound._last_play.clear()
	next = sound._next
	sound.play("device_hover")
	sound.play("device_hover")
	check(sound._next == (next+1)%SoundFx.POOL, "device hover burst throttled")
	AudioSettings.set_interface_muted(true)
	next = sound._next
	sound.play("device_power")
	check(sound._next == next, "interface mute prevents cue playback")
	AudioSettings.load_and_apply()
	check(AudioSettings.interface_muted and is_equal_approx(AudioSettings.interface_volume,.35), "interface mute and gain survive reload")
	check(sound.catalog_load_count == loads, "interface interactions perform no additional sound loads")
	check(DeviceSettings.set_style(DeviceSettings.CLASSIC) == OK, "classic preference restored")
	await frames(4)
	check(not menu.ui.get_node("DeviceFrame").visible, "classic toggle hides console detailing")
	check(shared_theme.get_stylebox("normal","Button").border_color.is_equal_approx(UiTheme.GOLD_DIM), "classic toggle restores palette")
	var invalid := ConfigFile.new()
	invalid.set_value("interface", "style", "invalid")
	invalid.save(_fixture)
	DeviceSettings.reload_settings()
	check(DeviceSettings.current() == DeviceSettings.CLASSIC, "malformed preference safely falls back to classic")
	var result := {"checks":checks,"failures":failures,"limits":["standalone source UI without Boot or match","no audio listening","not a performance measurement"]}
	var report := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(result,"  "))
	print("DEVICE UI ",JSON.stringify(result))
	canvas.queue_free()
	menu.queue_free()
	await frames(3)
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(3)
	DeviceSettings.settings_path = _previous_device_path
	AudioSettings.settings_path = _previous_audio_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_fixture))
	quit(1 if failures else 0)
