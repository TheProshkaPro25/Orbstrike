extends SceneTree
## Настоящий ввод в обе руки и полупрозрачные места арены; без каталога моделей.
var checks := 0
var failures := 0
var out := "res://build/checks/hand-placement"
var gates: SetupPanel
var abilities: AbilityPanel
var arena: Arena
var camera: Camera3D
var chosen: Array = []
var skipped := 0
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + text)
func _run() -> void:
	CardDB.load_all()
	await process_frame
	check(Engine.max_fps == 60,"общий wrapper удерживает лимит60FPS")
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var world := Node3D.new()
	root.add_child(world)
	arena = Arena.new()
	arena.location_id = 1
	world.add_child(arena)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 66, 58)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, -30, 0)
	world.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("152238")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .8
	world.add_child(environment)
	gates = SetupPanel.new()
	abilities = AbilityPanel.new()
	root.add_child(gates)
	root.add_child(abilities)
	arena.slot_clicked.connect(gates.pick_slot)
	gates.placed.connect(func(cid, slot): chosen.append([cid,slot,false]))
	gates.placed_throw.connect(func(cid,slot): chosen.append([cid,slot,true]))
	gates.skipped.connect(func(): skipped += 1)
	var ids := CardDB.arena_ids().slice(0,3)
	var hand := CardDB.ability_ids().slice(0,6)
	abilities.set_hand(hand)
	abilities.set_dock_visible(true)
	var entries: Array = []
	for id in ids: entries.append({"id":id})
	gates.begin(entries, [0,1,2], false, true)
	arena.set_highlight([0,1,2],true)
	await settle()
	check(gates.find_children("*", "GridContainer",true,false).is_empty(),"нет отдельной сетки выбора места")
	check(not gates._skip_btn.visible,"обязательная постановка не предлагает пропуск")
	await click(camera.unproject_position(arena.slot_position(1)))
	check(chosen.is_empty(),"место без выбранной карты не расходует карту")
	await click(gates._card_buttons[ids[0]].get_global_rect().get_center())
	check(gates._selected == ids[0],"реальный клик выбирает карту в левой руке")
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await process_frame
	check(gates._selected == &"" and chosen.is_empty(),"Escape снимает выбор без расхода")
	await click(gates._card_buttons[ids[1]].get_global_rect().get_center())
	await click(camera.unproject_position(arena.slot_position(5)))
	check(chosen.is_empty(),"недопустимое поле не кладёт карту")
	await click(camera.unproject_position(arena.slot_position(1)))
	check(chosen.size()==1 and chosen[0]==[ids[1],1,false],"щелчок по полупрозрачному полю ставит выбранные ворота")
	for size in [Vector2i(1280,720),Vector2i(960,540),Vector2i(1920,1080)]:
		root.size = size
		root.content_scale_size = size
		gates.begin(entries,[0,1,2],true,true)
		abilities.show_options([{"id":hand[0]},{"id":hand[1]}],"Ваш ответ: способность или пас",{"moment":&"battle","can_open_gate":true,"note":"Ворота закрыты. Два паса завершают бой."})
		await settle()
		for card in gates._card_buttons.values():
			check(card.get_global_rect().end.x < size.x*.51,"ворота находятся слева %d"%size.x)
		for card in abilities._cards:
			check(card.get_global_rect().position.x > size.x*.5,"способности находятся справа %d"%size.x)
		check(gates._panel.get_global_rect().end.x <= size.x*.51,"действия ворот остаются слева")
		for card in abilities._cards:
			check(not card.get_global_rect().intersects(abilities._panel.get_global_rect()),"карты не перекрывают управление способностей")
		await shot("hands-%d"%size.x)
		gates.hide_panel()
		abilities.hide_panel()
		await settle()
		await shot("idle-%d"%size.x)
	gates.begin(entries,[0,1,2],true,true)
	await settle()
	await click(gates._throw_btn.get_global_rect().get_center())
	await click(gates._card_buttons[ids[0]].get_global_rect().get_center())
	await click(camera.unproject_position(arena.slot_position(0)))
	check(chosen.size()==2 and chosen[1][2],"ворота+бросок использует прямой выбор арены")
	await click(gates._skip_btn.get_global_rect().get_center())
	check(skipped==1,"разрешённый пропуск доступен")
	var four: Array = []
	for id in CardDB.arena_ids().slice(0,4): four.append({"id":id})
	gates.begin(four,[0,1,2],true,true)
	await settle()
	await click(gates._card_buttons[four[0].id].get_global_rect().get_center())
	await click(gates._next.get_global_rect().get_center())
	check(gates._selected==&"" and gates._page==1,"смена страницы снимает невидимый выбор")
	check(gates._pager.get_global_rect().end.y<=root.get_visible_rect().size.y,"пейджер ворот целиком в экране")
	var before := chosen.size()
	await click(camera.unproject_position(arena.slot_position(0)))
	check(chosen.size()==before,"одна карта на странице не означает одну карту в руке")
	await shot("gates-page-2")
	gates.queue_free()
	abilities.queue_free()
	world.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await settle()
	print("Hands placement: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func settle() -> void:
	for frame in 12: await process_frame
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(out+"/"+name+".png")==OK,"PNG "+name)
func click(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	root.push_input(motion,true)
	await process_frame
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event,true)
		await process_frame
