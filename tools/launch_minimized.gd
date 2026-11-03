extends SceneTree
## Пользовательский запуск: начинается свёрнутым, затем окно можно открыть с панели задач.
func _initialize() -> void:
	root.unfocusable = true
	root.mode = Window.MODE_MINIMIZED
	call_deferred("start_game")

func start_game() -> void:
	# Параметры окна из командной строки могут примениться после _initialize.
	for frame in 5:
		root.unfocusable = true
		root.mode = Window.MODE_MINIMIZED
		await process_frame
	root.position = Vector2i(80, 80)
	root.mode = Window.MODE_MINIMIZED
	root.unfocusable = false
	var begin := Time.get_ticks_msec()
	change_scene_to_file(str(ProjectSettings.get_setting("application/run/main_scene")))
	print("Player game started minimized; window mode=%d; restore from taskbar" % root.mode)
	while current_scene == null or current_scene.scene_file_path != "res://scenes/menu/main_menu.tscn":
		await process_frame
	print("Player main menu ready after %.2f s; window mode=%d" % [(Time.get_ticks_msec() - begin) / 1000.0, root.mode])
