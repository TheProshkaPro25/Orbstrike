extends SceneTree
## Реальные музыкальные потоки, прерванные переходы и меню → колода → меню.
var checks := 0
var failures := 0
var sound: SoundFx

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

func settle() -> void:
	check(await until(func(): return sound._music_tw == null or not sound._music_tw.is_running(), 15.0), "музыкальный переход завершился")
	await process_frame

func until(predicate: Callable, seconds := 30.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		if predicate.call(): return true
	return false

func playing_count() -> int:
	var count := 0
	for player in sound._mus:
		if player.playing: count += 1
	return count

func sole_track(path: String, label: String) -> void:
	check(sound._mus_path == path, label + ": выбран нужный трек")
	check(playing_count() == 1, label + ": играет ровно один плеер")
	check(sound._mus[sound._mus_cur].stream == load(path), label + ": реальная композиция")
	check(is_equal_approx(sound._mus[sound._mus_cur].volume_db, 0.0), label + ": fade достиг полной громкости")

func reset_music() -> void:
	if sound._music_tw != null: sound._music_tw.kill()
	for player in sound._mus: player.stop()
	sound._mus_path = ""
	sound._mus_resume.clear()

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	Engine.time_scale = 1.0
	sound = SoundFx.i()
	await process_frame
	var menu_stream: AudioStream = load(SoundFx.MUSIC_MENU)
	var team_stream: AudioStream = load(SoundFx.MUSIC_TEAM)
	check(menu_stream != team_stream and menu_stream.get_length() > 1.0 and team_stream.get_length() > 1.0, "главное меню и колода имеют две реальные разные композиции")
	# Прежний повтор терял callback остановки уходящего MENU.
	sound.play_music(SoundFx.MUSIC_MENU, .05)
	await wait(.10)
	sound.play_music(SoundFx.MUSIC_TEAM, .5)
	await wait(.12)
	var player := sound._mus[sound._mus_cur]
	var position := player.get_playback_position()
	var volume := player.volume_db
	sound.play_music(SoundFx.MUSIC_TEAM, .12)
	check(sound._mus[sound._mus_cur] == player and player.get_playback_position() >= position - .05, "повтор не перезапускает композицию")
	check(is_equal_approx(player.volume_db, volume), "повтор не скачет по громкости в момент команды")
	await wait(.20)
	sole_track(SoundFx.MUSIC_TEAM, "повтор в середине кроссфейда")
	reset_music()
	sound.play_music(SoundFx.MUSIC_MENU, .05)
	await wait(.10)
	sound.play_music(SoundFx.MUSIC_TEAM, .5)
	await wait(.12)
	sound.stop_music(.12)
	await wait(.20)
	check(playing_count() == 0 and sound._mus_path.is_empty(), "stop во время кроссфейда останавливает оба плеера")
	reset_music()
	sound.play_music(SoundFx.MUSIC_MENU, .05)
	await wait(.10)
	sound.play_music(SoundFx.MUSIC_TEAM, .5)
	await wait(.12)
	sound.duck_music(-14.0, .12)
	await wait(.20)
	check(playing_count() == 1, "duck во время кроссфейда не оставляет прежнюю музыку")
	check(is_equal_approx(sound._mus[sound._mus_cur].volume_db, -14.0), "duck достигает заданной громкости")
	sound.play_music(SoundFx.MUSIC_TEAM, .12)
	await wait(.20)
	sole_track(SoundFx.MUSIC_TEAM, "снятие приглушения")
	# Ещё слышный MENU при реверсии не перезапускается и не меняет амплитуду.
	sound.play_music(SoundFx.MUSIC_MENU, .5)
	await wait(.12)
	var old_team := sound._mus[1 - sound._mus_cur]
	position = old_team.get_playback_position()
	volume = old_team.volume_db
	sound.play_music(SoundFx.MUSIC_TEAM, .12)
	check(sound._mus[sound._mus_cur] == old_team and old_team.get_playback_position() >= position - .05, "быстрый возврат сохраняет живой декодер и позицию")
	check(is_equal_approx(old_team.volume_db, volume), "быстрый возврат сохраняет мгновенную амплитуду")
	await wait(.20)
	sole_track(SoundFx.MUSIC_TEAM, "разворот кроссфейда")
	for path in [SoundFx.MUSIC_MENU, SoundFx.MUSIC_TEAM, SoundFx.MUSIC_MENU, sound.turn_music(), SoundFx.MUSIC_CLASH, sound.turn_music()]:
		sound.play_music(path, .2, path != SoundFx.MUSIC_CLASH)
		await wait(.06)
	await wait(.3)
	sole_track(sound.turn_music(), "быстрые меню/ход/схватка/возврат")
	reset_music()
	# Настоящие сцены, обычный переход главного меню и кнопка возврата из регистрации.
	# Матч/профиль/турнир не создаются и не сохраняются; Boot-каталог не нужен.
	change_scene_to_file("res://scenes/menu/main_menu.tscn")
	check(await until(func(): return current_scene is MainMenu), "открыто настоящее главное меню")
	await settle()
	sole_track(SoundFx.MUSIC_MENU, "главное меню")
	var menu: MainMenu = current_scene
	menu._on_settings()
	check(sound._mus_path == SoundFx.MUSIC_MENU, "настройки сохраняют музыку родительского меню")
	menu._settings.close()
	menu._on_help()
	check(sound._mus_path == SoundFx.MUSIC_MENU, "справка сохраняет музыку родительского меню")
	menu._help.queue_free()
	menu._on_new_tournament()
	check(await until(func(): return current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn"), "настоящий переход в сборку колоды")
	var game := current_scene
	for step in 3:
		game.team_menu._show_step(step)
		check(sound._mus_path == SoundFx.MUSIC_TEAM, "подготовка команды/ворот/способностей использует TEAM: %d" % step)
		await process_frame
	await settle()
	sole_track(SoundFx.MUSIC_TEAM, "колода")
	var back: Button
	for button in game.team_menu.find_children("*", "Button", true, false):
		if button.text == "В меню": back = button
	check(back != null, "у регистрации есть настоящая кнопка В меню")
	if back != null: back.pressed.emit()
	check(await until(func(): return current_scene is MainMenu), "кнопка вернула настоящее главное меню")
	await settle()
	sole_track(SoundFx.MUSIC_MENU, "возврат из колоды")
	check(Engine.max_fps == 60, "тест ограничен 60 FPS")
	check(root.unfocusable and root.mode == Window.MODE_MINIMIZED, "тест свёрнут и нефокусируем")
	current_scene.queue_free()
	await process_frame
	sound.stop_music(.05)
	await wait(.12)
	print("Menu music: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
