extends RefCounted
## Графические проверки рендерят в свёрнутый viewport, не забирая экран автора.
static func background(tree: SceneTree) -> void:
	Engine.max_fps = 60
	if DisplayServer.get_name() == "headless": return
	AudioServer.set_bus_mute(0, true)
	var window: Window = tree.root
	window.always_on_top = false
	window.unfocusable = true
	window.mode = Window.MODE_MINIMIZED
	# Обычный цикл пропускает отрисовку свёрнутого окна. Для PNG рисуем в текстуру
	# без показа/обмена оконного буфера; игровой процесс и камеры остаются настоящими.
	var draw: Callable = func() -> void:
		if Engine.max_fps != 60: Engine.max_fps = 60
		if not window.unfocusable: window.unfocusable = true
		if window.mode != Window.MODE_MINIMIZED: window.mode = Window.MODE_MINIMIZED
		RenderingServer.viewport_set_update_mode(window.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
		# force_draw по умолчанию получает frame_step=0: в свёрнутом окне тогда
		# замирают TIME и GPU-частицы. Продвигаем их тем же временем, что SceneTree.
		RenderingServer.force_draw(false,window.get_process_delta_time())
	tree.process_frame.connect(draw)
	tree.set_meta("sfery_background_draw", draw)
	print("Background GPU test: minimized, unfocusable, offscreen rendering")

static func finish(tree: SceneTree) -> void:
	if not tree.has_meta("sfery_background_draw"): return
	var draw: Callable = tree.get_meta("sfery_background_draw")
	if tree.process_frame.is_connected(draw): tree.process_frame.disconnect(draw)
	tree.remove_meta("sfery_background_draw")
