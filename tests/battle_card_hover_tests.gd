extends "res://tests/run_tests.gd"
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
	_add_test_creatures()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.theme = UiTheme.get_theme()
	if OS.get_environment("ORBSTRIKE_HOVER_FOCUS") == "1":
		await _real_battle()
		print("Подсказки сыгранных карт: %d проверок, %d ошибок" % [checks, failures])
		quit(1 if failures else 0)
		return
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
			var explanation: Control = UiTheme.help_panel(chip.help)
			root.add_child(explanation)
			await process_frame
			check(explanation.size.x < viewport_size.x and explanation.size.y < viewport_size.y - 24, "подсказка помещается в экран: %s %s %s" % [card.id, viewport_size, explanation.size])
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
	await _real_battle()
	print("Подсказки сыгранных карт: %d проверок, %d ошибок" % [checks, failures])
	quit(1 if failures else 0)

func _has_tooltip(node: Node) -> bool:
	if node is BattleHud and is_instance_valid(node._chain_help): return true
	if node is PopupPanel and node.visible:
		return true
	for child in node.get_children(true):
		if _has_tooltip(child): return true
	return false

func _tooltip(node: Node) -> Control:
	if node is BattleHud and is_instance_valid(node._chain_help): return node._chain_help
	for child in node.get_children(true):
		var found := _tooltip(child)
		if found != null: return found
	return null

func _real_battle() -> void:
	# Та же сцена и порядок слоёв, что в дуэли; standalone BattleHud не видит перекрытий.
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await create_timer(.3).timeout
	game.team_menu.hide()
	game.setup_panel.set_dock_visible(false)
	HudUI._coached.erase("attach")
	game.hud.coach("attach", "Существо встало на пустые ворота. Можно прикрепить карту: она сработает в его следующем бою (видна сопернику). Или завершить ход без неё.")
	await process_frame
	check(is_instance_valid(game.hud._coach), "вход в бой начинается с недочитанного совета прежней фазы")
	game.hud.set_battle_mode(true)
	check(not is_instance_valid(game.hud._coach) and game.hud._coach_queue.is_empty(), "вход в бой убирает устаревшие советы, освобождая блок ответа")
	game.hud.set_hint("Ваша способность?")
	var sizes := [Vector2i(960,540)] if OS.get_environment("ORBSTRIKE_HOVER_FOCUS") == "1" else [Vector2i(960,540), Vector2i(1280,720), Vector2i(1920,1080)]
	for viewport_size in sizes:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		await process_frame
		game.battle_hud.open(["Драгнар", "Грифалон"], [0,1], [420,390])
		var controller := _battle_ctrl([&"ability_fire_drain",&"ability_fire_assault",&"ability_dragnar_heart"],[&"ability_gale_rebuttal",&"ability_gale_gust",&"ability_gale_counter"],NEUTRAL,0,0,902)
		controller.state.manual_gates = true
		game.ctrl = controller
		game._index_creatures()
		check(controller.play_ability(0,&"ability_fire_drain") == OK,"настоящий контроллер принимает первую способность")
		check(controller.play_ability(1,&"ability_gale_rebuttal") == OK,"настоящий контроллер принимает ответную отмену")
		game._refresh_hand()
		game._do_ability(0)
		await create_timer(.4).timeout
		var latest: Control = game.battle_hud._chain.get_child(1)
		await _hover_chip(latest, viewport_size, "последняя активированная отмена из контроллера")
		await create_timer(.8).timeout
		check(_has_tooltip(root),"реальный боевой ответ показывает последнюю способность")
		check(latest.help[4] == CardDB.card(&"ability_gale_rebuttal").full_text(),"реальная последняя карта содержит полные условия")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out_dir + "/controller-battle-%d.png" % viewport_size.x)
		var plays: Array = [[0,&"ability_fire_drain"],[1,&"ability_tide_counter"],[0,&"ability_fire_counter"],[1,&"ability_light_purge"],[0,&"ability_dragnar_heart"],[1,&"ability_stone_copy"]]
		game.battle_hud.set_chain(plays,[false,false],0)
		game.ability_panel.set_hand([&"ability_fire_assault",&"ability_fire_counter",&"ability_fire_drain"])
		game.ability_panel.show_options([{"id":&"ability_fire_assault"}],"Ваш ответ: способность или пас",{"moment":&"battle","can_open_gate":true,"note":"Ворота закрыты. Два паса подряд завершат бой. На карту соперника можно ответить."})
		await create_timer(.6).timeout
		var action_rect: Rect2 = game.ability_panel._panel.get_global_rect()
		check(root.get_visible_rect().encloses(action_rect),"боевое управление целиком в экране")
		for plate in game.battle_hud._plates:
			check(not action_rect.intersects(plate.get_global_rect()),"ответ не перекрывает плашки бойцов")
		for cv in game.ability_panel._cards:
			check(not action_rect.intersects(cv.get_global_rect()),"ответ не перекрывает руку способностей")
		for cv in game.setup_panel._card_buttons.values():
			check(not action_rect.intersects(cv.get_global_rect()),"ответ не перекрывает опущенные ворота")
		await _animated_titles(game.ability_panel._cards)
		for chip in game.battle_hud._chain.get_children():
			check(not action_rect.intersects(chip.get_global_rect()),"ответ не перекрывает ни одну сыгранную карту")
			await _hover_chip(chip,viewport_size,chip.get_child(0).text)
		await create_timer(1.0).timeout
		check(_has_tooltip(root),"реальная сцена показывает полные условия последней карты %s" % viewport_size)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out_dir + "/real-battle-%d.png" % viewport_size.x)
	game.queue_free()
	for frame in 5: await process_frame
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	for frame in 5: await process_frame

func _hover_chip(chip: Control, viewport_size: Vector2i, description: String) -> void:
	# Центр не обнаруживает частичное перекрытие букв/краёв соседним UI.
	var rect := chip.get_global_rect()
	# Завершить чтение предыдущего раскрытия: над закрытой им надписью
	# указатель всё ещё находится на читаемой карте, а не выбирает новую.
	var leave := InputEventMouseMotion.new()
	leave.position = root.get_final_transform() * Vector2(8,viewport_size.y - 8)
	Input.parse_input_event(leave)
	await create_timer(.2).timeout
	var start := InputEventMouseMotion.new()
	start.position = root.get_final_transform() * rect.get_center()
	Input.parse_input_event(start)
	await create_timer(.8).timeout
	var popup := _tooltip(root)
	check(popup != null,"подсказка открыта перед проходом всей надписи: " + description)
	if popup != null:
		check(popup.get_child(0).card_id == chip.help[7].card_id, "раскрыта именно выбранная надпись: " + description)
		check(not popup.get_global_rect().intersects(rect), "раскрытие не закрывает свою надпись: " + description)
	for fy in [.12, .5, .88]:
		for fx in [.02, .25, .5, .75, .98]:
			var motion := InputEventMouseMotion.new()
			# parse_input_event принимает координаты окна, включая stretch/масштаб
			# (менеджер окон может ограничить физические 1080px свёрнутого окна).
			motion.position = root.get_final_transform() * (rect.position + rect.size * Vector2(fx, fy))
			Input.parse_input_event(motion)
			await process_frame
			check(root.gui_get_hovered_control() == chip,"реальная сцена: вся плашка %s %s (%s,%s); попали в %s; rect%s mouse%s" % [description,viewport_size,fx,fy,root.gui_get_hovered_control(),rect,root.get_mouse_position()])
			check(popup != null and _tooltip(root) == popup,"движение по надписи сохраняет ту же подсказку: " + description)
	var title: Label = chip.get_child(0)
	check(rect.grow(.5).encloses(title.get_global_rect()), "вся область названия внутри hover: " + description)
	var center_motion := InputEventMouseMotion.new()
	center_motion.position = root.get_final_transform() * rect.get_center()
	Input.parse_input_event(center_motion)
	await process_frame
	if popup != null:
		var reading_rect: Rect2 = popup.get_global_rect()
		var reading := InputEventMouseMotion.new()
		reading.position = root.get_final_transform() * reading_rect.get_center()
		Input.parse_input_event(reading)
		await create_timer(.4).timeout
		check(is_instance_valid(popup) and _tooltip(root) == popup, "мышь на раскрытой карте сохраняет чтение: %s; target%s mouse%s hovered%s active%s" % [description,reading_rect,root.get_mouse_position(),root.gui_get_hovered_control(),_tooltip(root)])
		Input.parse_input_event(center_motion)
		await process_frame

func _animated_titles(cards: Array) -> void:
	for cv: CardView in cards:
		cv.button_pressed = true
		cv._sync_selected()
		cv._on_hover(true)
	for frame in 12:
		await process_frame
		for cv: CardView in cards:
			var r: Rect2 = cv._lay["title"]
			r = Rect2(r.position * cv._card_size.x, r.size * cv._card_size.x)
			var title: Label = cv._title
			check(r.grow(.5).encloses(Rect2(title.position,title.size)),"название внутри плашки во время подъёма: " + String(cv.card_id))
			check(title.scale == Vector2.ONE and title.clip_text,"анимация не меняет масштаб/границы имени")
	for cv: CardView in cards:
		cv.button_pressed = false
		cv._sync_selected()
		cv._on_hover(false)
