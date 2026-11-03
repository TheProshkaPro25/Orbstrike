extends SceneTree
## Изолированная проверка публичной ленты: настоящая мышь, полные условия и отменённые карты.
var failures := 0
var checks := 0
var out_dir := "user://battle-card-hover"

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	CardDB.load_all()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.theme = UiTheme.get_theme()
	var hud := BattleHud.new()
	root.add_child(hud)
	var plays: Array = [[0, &"ability_fire_drain"], [1, &"ability_klykar_bite"], [0, &"ability_dragnar_heart"], [1, &"ability_light_purge"], [0, &"ability_rogozhuk_shell"], [1, &"ability_stone_copy"]]
	var cancelled: Array = plays.slice(0, 1)
	for viewport_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		await process_frame
		await process_frame
		hud.open(["Атакующий", "Защитник"], [0, 2], [340, 330])
		hud.set_chain(plays, [true, true], 1, cancelled)
		await create_timer(.6).timeout
		check(hud._chain.get_child_count() == 8, "шесть карт и два паса доступны")
		for index in plays.size():
			var chip: Control = hud._chain.get_child(index)
			var rect := chip.get_global_rect()
			check(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(rect), "название карты внутри экрана: %s" % plays[index][1])
			var card := CardDB.card(plays[index][1])
			check(chip.help[4] == card.full_text(), "полные условия сыгранной карты: " + String(card.id))
			check(String(chip.help[6]).contains("отменена") == (index == 0), "состояние отмены получено из расчёта")
			var motion := InputEventMouseMotion.new()
			motion.position = rect.get_center()
			Input.parse_input_event(motion)
			await process_frame
			check(root.gui_get_hovered_control() == chip, "реальное наведение достигает карты любой стороны")
			var explanation: Control = chip._make_custom_tooltip(chip.tooltip_text)
			root.add_child(explanation)
			await process_frame
			check(explanation.size.x < viewport_size.x and explanation.size.y < viewport_size.y - 24, "подсказка помещается в экран")
			explanation.queue_free()
			await process_frame
		var kept := hud._chain.get_child(1)
		hud.set_chain(plays, [true, true], 0, cancelled)
		check(hud._chain.get_child(1) == kept, "повтор снимка сохраняет Control под мышью")
		# Действительная стандартная подсказка должна появиться от движения мыши.
		var motion := InputEventMouseMotion.new()
		motion.position = kept.get_global_rect().get_center()
		Input.parse_input_event(motion)
		await create_timer(1.0).timeout
		for frame in 4: await process_frame
		RenderingServer.force_draw(false)
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		check(capture.get_pixel(0, 0) != capture.get_pixel(10, viewport_size.y / 2), "кадр содержит отрисованный интерфейс")
		capture.save_png(out_dir + "/hover-%d.png" % viewport_size.x)
		check(_has_tooltip(root), "движок показал подсказку от реального наведения")
		hud.set_chain(plays, [false, false], 0, [])
		await process_frame
		check(not String(hud._chain.get_child(0).help[6]).contains("отменена"), "снятие отмены обновляет объяснение")
	hud.set_chain(plays.slice(0, 2), [false, false], 0, [], [3, 1])
	check(hud._counts[0].text.contains("3/3"), "счётчик показывает потраченные карты ушедшего при замене бойца")
	hud.close()
	check(not hud._chain.visible, "после боя лента скрыта")
	hud.queue_free()
	await process_frame
	await process_frame
	print("Подсказки сыгранных карт: %d проверок, %d ошибок" % [checks, failures])
	quit(1 if failures else 0)

func _has_tooltip(node: Node) -> bool:
	if node is PopupPanel and node.visible:
		return true
	for child in node.get_children(true):
		if _has_tooltip(child): return true
	return false
