extends SceneTree
## Только меню и сохранённые этапы кампании: без каталога49моделей и физической автоигры.
var checks := 0
var failures := 0
var out := "res://build/checks/campaign-ui"
var panel: TournamentPanel
var campaign: Campaign
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: "+message)
func _run() -> void:
	CardDB.load_all()
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var menu := preload("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	await create_timer(2.2).timeout
	check(menu._buttons.size()==10,"десять режимов и действий главного меню")
	for button in menu._buttons:
		check(button.get_global_rect().position.y>=0 and button.get_global_rect().end.y<=720,"кнопка меню в экране: "+button.text)
	await shot("menu-1280")
	root.size=Vector2i(960,540)
	root.content_scale_size=root.size
	await settle()
	for button in menu._buttons:
		check(button.get_global_rect().position.y>=0 and button.get_global_rect().end.y<=540,"узкая кнопка меню в экране: "+button.text)
	await shot("menu-960")
	menu.queue_free()
	await settle()
	root.size=Vector2i(1280,720)
	root.content_scale_size=root.size
	var deck := CardDB.preset_deck(0)
	campaign = Campaign.create(deck,1,202611031,"Haru Akiyama",out+"/ui-campaign.json")
	check(campaign!=null,"кампания создана для UI")
	if campaign==null:
		quit(1)
		return
	panel=TournamentPanel.new()
	root.add_child(panel)
	panel.advance_requested.connect(func():
		if campaign.can_advance(): campaign.advance_cup()
		panel.display(campaign.cup,[],campaign))
	panel.display(campaign.cup,[],campaign)
	await settle()
	await shot("cup-1")
	while not campaign.cup.completed():
		var fixture := campaign.cup.next_match()
		var winner := 0 if int(fixture.a)==0 or int(fixture.b)==0 else int(fixture.a)
		var alive := [3,0] if winner==int(fixture.a) else [0,3]
		check(campaign.record_result(fixture.id,winner,alive,"knockout",{"throws":4,"abilities":3,"gate_opens":2})==OK,"контрольный результат этапа сохранён")
	panel.display(campaign.cup,[],campaign)
	await settle()
	check(panel.primary_button.visible and panel.primary_button.text=="Следующий кубок →","завершённый кубок показывает продолжение")
	await shot("cup-complete")
	await click(panel.primary_button.get_global_rect().get_center())
	check(campaign.cup_index()==1 and panel._title.text=="Кубок Гавани","настоящая кнопка открывает следующий сохранённый кубок")
	await settle()
	await shot("cup-2")
	while not campaign.cup.next_match().is_empty():
		var fixture := campaign.cup.next_match()
		if int(fixture.a)==0 or int(fixture.b)==0: break
		check(String(campaign.simulate_next_npc().error).is_empty(),"фоновые встречи до реванша")
	panel.display(campaign.cup,[],campaign)
	await settle()
	await shot("rematch-brief")
	check(Engine.max_fps==60,"лимит60FPS удержан после меню и смены этапов")
	Engine.max_fps=144
	await process_frame
	await process_frame
	check(Engine.max_fps==60,"wrapper восстанавливает60FPS после попытки сменить лимит")
	panel.queue_free()
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	await settle()
	print("Campaign UI: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func settle() -> void:
	for frame in 10: await process_frame
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(out+"/"+name+".png")==OK,"PNG "+name)
func click(pos:Vector2) -> void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=pos
		event.pressed=down
		event.button_index=MOUSE_BUTTON_LEFT
		root.push_input(event,true)
		await process_frame
