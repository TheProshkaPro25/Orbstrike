extends SceneTree
## GPU проверка выбора цели, анимации карты, волны и большой руки на трёх размерах окна.
var main: Node
var out_dir := "user://experience_review"
var failures := 0
const Locations := preload("res://data/arena_locations.gd")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.max_fps = 60
	GraphicsSettings.max_fps = 60
	GraphicsSettings.level = GraphicsSettings.Level.HIGH
	Engine.time_scale = 1.0
	var camera := CameraRig.new()
	root.add_child(camera)
	await process_frame
	camera.set_process(false)
	camera._set_static(Vector3(0, 4, 12), Vector3(0, 1, 0), {"fov": 65.0, "smooth": 7.0, "hand": 0.0})
	camera.cut()
	var entry := camera.global_transform
	camera.reveal_orbit(Vector3.ZERO, 12, Vector3.FORWARD, 15)
	check(camera.global_transform.is_equal_approx(entry), "начало раскрытия не переключает камеру мгновенно")
	camera._process(1.0/60)
	check(camera.global_position.distance_to(entry.origin) < .25, "первый кадр облёта движется плавно")
	camera.queue_free()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# Настоящий выбор локации: предпросмотр, сохранение и одинаковая сетка ворот.
	main.team_menu._open_arena_picker()
	for location in Locations.LOCATIONS.size():
		main.team_menu._arena_picker.select(location)
		await _frames(12)
		check(main.arena.location_id == location, "выбранная локация применяется")
		check(Locations.current() == location, "выбор локации сохраняется")
		check(main.arena.markers.size() == 6, "у каждой арены шесть мест")
		for slot in 6:
			check(main.arena.slot_at(main.arena.slot_position(slot)) == slot, "локация сохраняет геометрию слотов")
		if location == 0:
			check(main.arena._decor.get_meta("closed_sanctuary", false), "святилище использует закрытый интерьер")
			check(Vector2(main.cam.global_position.x, main.cam.global_position.z).length() < 102, "предпросмотр находится внутри стен")
		await save("location-%d" % location)
	main.team_menu._arena_picker.select(0)
	main.cam._set_static(Vector3(0, 8, 36), Vector3(0, 36, -55), {"fov": 64.0, "smooth": 4.0, "hand": 0.0})
	main.cam.cut()
	await _frames(8)
	await save("sanctuary-vault")
	main.team_menu._close_arena_picker()
	await _frames(3)
	check(not main.team_menu._arena_picker.visible and main.team_menu._arena_btn.visible, "возврат из выбора к команде")
	var deck := CardDB.preset_deck(0)
	main.team_menu.hide()
	var ids: Array[StringName] = []
	var gates: Array[StringName] = []
	var abilities: Array[StringName] = []
	for d in deck.creatures: ids.append(d.id)
	for d in deck.arena: gates.append(d.id)
	for d in deck.abilities: abilities.append(d.id)
	main._on_deck_chosen(ids, gates, abilities)
	for frame in 1800:
		await process_frame
		if not main._preparing: break
	check(not main._preparing and main.ctrl._started, "подготовка команды завершилась до начала матча")
	await _settle()
	main.hud._close_coach()
	check(main.setup_panel._panel.visible, "старт матча запрашивает ворота")
	main.setup_panel._on_card_pressed(main.ctrl.get_view(0).players[0].arena_hand[0])
	var slot: int = main.ctrl.legal_setup_slots()[0]
	main._on_slot_picked(slot)
	await create_timer(0.20).timeout
	var thrown_card: ArenaCardNode = main.card_nodes[slot]
	check(thrown_card.scale.is_equal_approx(thrown_card.get_meta("flight_scale")), "в начале полёта карта маленькая")
	check(thrown_card.get_meta("placement_stage") == &"held", "карта удерживается до выпуска")
	var grip: Transform3D = main.fighters[0].card_hand_transform("Right")
	check(thrown_card.global_position.distance_to(grip.origin) < .025,"карта привязана к правой кисти")
	await save("card-held")
	await _card_stage(thrown_card,&"flight")
	check(thrown_card.get_meta("placement_stage") == &"flight", "начался полёт карты")
	await save("card-flight")
	await create_timer(0.50).timeout
	check(thrown_card.scale.is_equal_approx(thrown_card.get_meta("flight_scale")), "карта не растёт в полёте")
	var strength: Variant = main.arena._floor_mat.get_shader_parameter("wave_strength")
	check(strength == null or is_zero_approx(float(strength)), "до касания поля нет волны")
	await save("card-flight-late")
	await _card_stage(thrown_card,&"expanding")
	await create_timer(.12).timeout
	check(thrown_card.get_meta("placement_stage") == &"expanding", "рост начинается на поле")
	check(thrown_card.position.y < 0.01 and thrown_card.scale.x > main.director.CARD_FLIGHT_SCALE and thrown_card.scale.x < 1.0, "рост идёт после приземления")
	check(float(main.arena._floor_mat.get_shader_parameter("wave_strength")) > 0.0, "при росте идёт волна стихии")
	check(SoundFx.i().has_sfx("gate_flight_wind") and SoundFx.i().has_sfx("gate_expand_wave"), "мягкие звуки полёта и волны загружены")
	await save("element-wave")
	await _settle()
	check(main.hud._creature_panel.visible, "после выкладки доступен выбор существа")
	main._on_creature_chosen(main.ctrl.legal_creatures(0)[0])
	await _settle()
	main.hud._close_coach()
	check(main.arena._pick and main._active_ball != null, "цель выбирается щелчком без рогатки")
	var final_shell := [Transform3D.IDENTITY]
	main._active_ball.settled.connect(func(ball: CreatureBall, _p: Vector3) -> void: final_shell[0] = ball._shell.global_transform)
	main._on_slot_picked(slot)
	await create_timer(main.fighters[0].ball_release_time()+.15).timeout
	check(main.cam.mode == CameraRig.Mode.FOLLOW, "камера следует за летящей сферой")
	await save("sphere-flight")
	var shot: CreatureBall = main._active_ball
	for frame in 420:
		check(not shot.has_meta("landing_montage_views"), "быстрые переключения ракурсов удалены")
		if not main.director.flying: break
		await process_frame
	print("Dynamic sphere: seconds=",shot._t," montage=disabled")
	check(shot.bounce_count >= 2, "сфера отскакивает от поверхности несколько раз")
	var stopped := shot.global_position
	check(shot._shell.global_transform.is_equal_approx(final_shell[0]), "остановка сохраняет полный мировой transform оболочки")
	check(shot._shell.global_position.y-shot._shell.scale.x >= ArenaCardNode.SURFACE_Y-.001,"маленькая сфера стоит поверх карты ворот")
	check(Vector2(stopped.x, stopped.z).distance_to(Vector2(main.arena.slot_position(slot).x, main.arena.slot_position(slot).z)) > .1, "сфера остаётся в физической точке, а не в центре ворот")
	check(not main.director.flying, "полёт завершается за ограниченное время")
	for frame in 120:
		if main.cam.mode == CameraRig.Mode.ORBIT: break
		await process_frame
	check(main.ctrl.get_view(0).creature(0).slot == slot, "сфера остановилась на выбранных воротах")
	check(Vector2(shot.global_position.x, shot.global_position.z).distance_to(Vector2(stopped.x, stopped.z)) < .01, "раскрытие не переносит сферу в центр")
	check(main.cam.mode == CameraRig.Mode.ORBIT, "раскрытие существа показывается одним облётом")
	check(float(main.cam._orb.get("enter", 0)) >= .5, "в облёт есть плавный вход без ката")
	check(shot._shell.global_position.distance_to(final_shell[0].origin) < .001, "центр оболочки не прыгает в начале раскрытия")
	check(shot._shell.global_basis.orthonormalized().is_equal_approx(final_shell[0].basis.orthonormalized()), "раскрытие сохраняет финальный физический поворот оболочки")
	await create_timer(.75).timeout
	await save("creature-reveal")
	# Остановить только очередь хода: обзор руки не запускает решение ИИ.
	main.interaction.clear_request()
	main.events.drained.disconnect(main._pump)
	await _settle()
	# Такой же маленький полёт соперника: камера с противоположной стороны.
	main.director.card_placed(1, 2)
	await create_timer(.20).timeout
	var opponent_card: ArenaCardNode = main.card_nodes[2]
	check(opponent_card.scale.is_equal_approx(opponent_card.get_meta("flight_scale")), "карта соперника тоже летит маленькой")
	await _card_stage(opponent_card,&"flight")
	await _frames(2)
	check(main.cam._goal_pos.z < opponent_card.global_position.z, "камера карты соперника зеркальна")
	await save("opponent-card-flight")
	await create_timer(1.9).timeout
	check(opponent_card.get_meta("placement_stage") == &"ready", "карта соперника выросла после касания")
	opponent_card.queue_free()
	main.card_nodes.erase(2)
	var hand: Array = CardDB.ability_ids().slice(0, 19)
	var entries: Array = []
	for id in hand.slice(0, 3): entries.append({"id": id})
	main.ability_panel.set_hand(hand)
	for resolution in [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(960, 540)]:
		root.size = resolution
		await _frames(3)
		main.ability_panel.show_options(entries, "Ваш ответ: способность или пас", {"moment": &"battle", "can_open_gate": true, "note": "Ворота закрыты. Два паса подряд завершат бой. На карту соперника можно ответить."})
		await _frames(5)
		var panel: AbilityPanel = main.ability_panel
		var controls := panel._panel.get_global_rect()
		var screen := panel.get_viewport_rect().size
		check(controls.position.x > screen.x * .70 and controls.end.x <= screen.x and controls.end.y <= screen.y, "панель паса справа внизу")
		check(controls.size.y < screen.y * .55, "панель с открытием ворот остаётся компактной")
		var seen: Array = []
		var pages := ceili(float(hand.size()) / panel._capacity)
		for page in pages:
			for card in panel._cards:
				seen.append(card.card_id)
				check(not card.get_global_rect().intersects(controls), "рука слева не перекрывает управление")
				var rect := card.get_global_rect()
				check(rect.position.x >= 0 and rect.end.x <= panel.get_viewport_rect().size.x, "карта внутри экрана %s" % resolution)
			panel._change_page(1)
		check(seen.size() == hand.size(), "каждая карта достижима через страницы")
		panel._page = 0
		panel._rebuild()
		await _frames(3)
		await save("hand-%dx%d" % [resolution.x, resolution.y])
		var rejected := [false]
		panel.unavailable.connect(func(_reason: String) -> void: rejected[0] = true, CONNECT_ONE_SHOT)
		panel._legal.clear()
		panel._on_card_pressed(panel._cards[0])
		check(rejected[0], "недоступная карта объясняет отказ")
	root.size = Vector2i(1280, 720)
	# Скорость движений не сокращает реальное время чтения.
	for speed in [0.75, 2.0]:
		Engine.time_scale = speed
		var start := Time.get_ticks_msec()
		await main.hud.wait_read(0.25)
		var elapsed := (Time.get_ticks_msec() - start) / 1000.0
		check(elapsed >= 0.23 and elapsed < 1.5, "чтение сохраняет время при темпе %s: %.3f с" % [speed, elapsed])
	Engine.time_scale = 1.0
	main.ability_panel.hide_panel()
	main.hud.set_hint("")
	main.cam.snap_overview()
	await _frames(15)
	await save("arena")
	main.queue_free()
	await _frames(4)
	SoundFx.i().queue_free()
	await _frames(2)
	# Дать звуковому потоку обработать stop и отпустить декодер Ogg.
	await create_timer(.15, true, false, true).timeout
	print("Experience review: %d ошибок" % failures)
	quit(1 if failures else 0)

func _settle() -> void:
	for i in 1200:
		await process_frame
		if not main.events.is_busy():
			return
	check(false, "очередь событий завершилась за 1200 кадров")

func _frames(n: int) -> void:
	for i in n: await process_frame

func save(name: String) -> void:
	if main.arena.location_id == 0:
		var p: Vector3 = main.cam.global_position
		var radial := Vector2(p.x, p.z).length()
		check(radial < 104, "камера внутри стен святилища: " + name)
		var ceiling := 65 + 43 * sqrt(maxf(0, 1 - pow(radial / 106, 2)))
		check(p.y < ceiling - 1, "камера под закрытым куполом: " + name)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))

func _card_stage(card: ArenaCardNode,stage: StringName) -> void:
	for frame in 240:
		if card.get_meta("placement_stage") == stage: return
		await process_frame
	check(false,"достигнута стадия карты %s" % stage)
