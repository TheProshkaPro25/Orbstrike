extends SceneTree
## Реальный Boot, три обычные дуэли: выбор карты, физический полёт, ожидание результата.
const WindowTest := preload("res://tools/test_window.gd")
const AutoPlay := preload("res://tools/autoplay.gd")
class ResultWaiter extends Node:
	var game: Node
	var finished := false
	func wait_result() -> void:
		var result := BattleResult.new()
		result.attacker_uid = 0
		result.defender_uid = 3
		result.winner_uid = 0
		result.loser_uid = 3
		result.powers = [410,390]
		await game.battle_overlay.show_result(result)
		finished = true
var checks := 0
var failures := 0
var loader: GameLoading
var main: Node
var counts: Array = []
var identities: Dictionary = {}
var out := "res://build/checks/duel-exit"
func _initialize() -> void:
	if not has_meta("sfery_background_draw"): WindowTest.background(self)
	call_deferred("run")
func _finalize() -> void: WindowTest.finish(self)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func until(predicate: Callable, seconds := 30.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if predicate.call(): return true
	return false
func frames(n: int) -> void:
	for f in n: await process_frame
func click(at: Vector2) -> void:
	for pressed in [true,false]:
		var e := InputEventMouseButton.new()
		e.position = at
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
func preparation_counts() -> Array:
	return [loader.preparation_count,loader.actor_build_count,loader.arena_build_count,loader.fighter_build_count,SoundFx.i().catalog_load_count]
func start_duel() -> bool:
	current_scene._on_play()
	if not await until(func(): return current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn"): return false
	main = current_scene
	main.rng.seed = 424242
	main.team_menu.hide()
	var deck := CardDB.preset_deck(1)
	var creatures: Array[StringName] = []
	var gates: Array[StringName] = []
	var abilities: Array[StringName] = []
	for d in deck.creatures: creatures.append(d.id)
	for d in deck.arena: gates.append(d.id)
	for d in deck.abilities: abilities.append(d.id)
	main._on_deck_chosen(creatures,gates,abilities)
	if not await until(func():
		if not main._preparing: AutoPlay.press_next_turn(main)
		return not main._preparing and main.setup_panel._panel.visible): return false
	check(main._duel_menu.visible and not main._duel_menu.disabled,"обычная дуэль показывает активную кнопку В меню")
	check(preparation_counts()==counts,"после Boot нет новой подготовки моделей/арен/звуков")
	check(loader._leased.size()==6,"матч арендует ровно шесть существ")
	for uid in main._prepared_balls:
		var ball: CreatureBall = main._prepared_balls[uid]
		if identities.has(uid): check(identities[uid]==ball.get_instance_id(),"повтор использует тот же экземпляр uid=%d"%uid)
		else: identities[uid]=ball.get_instance_id()
		check(ball.uid==uid and ball.slot==-1 and not ball._shape.disabled and not ball._open,"uid/коллайдер/поза сброшены uid=%d"%uid)
	return true
func menu_exit() -> void:
	var previous := main
	var old_ref: WeakRef = weakref(previous)
	await click(main._duel_menu.get_global_rect().get_center())
	check(is_instance_valid(main._duel_exit_confirm) and main._duel_exit_confirm.visible,"кнопка запрашивает подтверждение выхода")
	await click(Vector2(main._duel_exit_confirm.position)+main._duel_exit_confirm.get_ok_button().get_global_rect().get_center())
	check(await until(func(): return current_scene != null and current_scene.scene_file_path=="res://scenes/menu/main_menu.tscn"),"выход приводит в главное меню")
	main = null
	previous = null
	await frames(8)
	check(old_ref.get_ref()==null,"сцена дуэли и владельцы await освобождены")
	check(loader._leased.is_empty() and loader._arenas.size()==3,"все существа и три арены возвращены в каталог")
	check(preparation_counts()==counts,"выход не пересоздаёт каталог")
	for id in loader._balls:
		for ball: CreatureBall in loader._balls[id]:
			check(not ball.visible and ball.process_mode==Node.PROCESS_MODE_DISABLED,"резерв скрыт и отключён")
			check(ball.surface_bounced.get_connections().is_empty(),"нет старого callback полёта в резерве")
			check(ball._stage_tween==null and ball._throw_tween==null,"твины арендуемых актёров остановлены")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Engine.time_scale = 4.0
	root.size = Vector2i(1280,720)
	root.content_scale_size=root.size
	change_scene_to_file("res://scenes/loading/boot.tscn")
	if not await until(func(): return current_scene != null and current_scene.scene_file_path=="res://scenes/menu/main_menu.tscn",180):
		check(false,"Boot завершается")
		await finish()
		return
	loader=GameLoading.i()
	counts=preparation_counts()
	if not await start_duel():
		check(false,"первая дуэль начинается")
		await finish()
		return
	# Выбранная карта сохраняется после отмены подтверждения.
	var card: Button = main.setup_panel._card_buttons.values()[0]
	await click(card.get_global_rect().get_center())
	var selected: StringName = main.setup_panel._selected
	await click(main._duel_menu.get_global_rect().get_center())
	await click(Vector2(main._duel_exit_confirm.position)+main._duel_exit_confirm.get_cancel_button().get_global_rect().get_center())
	check(main.setup_panel._selected==selected and selected!=&"","отмена выхода сохраняет выбор карты")
	check(not main._duel_exit_confirm.visible,"отмена закрывает подтверждение")
	for size in [Vector2i(1280,720),Vector2i(960,540)]:
		root.size=size
		root.content_scale_size=size
		await frames(5)
		var rect: Rect2 = main._duel_menu.get_global_rect()
		check(root.get_visible_rect().encloses(rect),"кнопка целиком в экране %d"%size.x)
		for control in [main.setup_panel._panel,main.setup_panel._cards_box,main.ability_panel._panel]:
			if control.visible: check(not rect.intersects(control.get_global_rect()),"кнопка не перекрывает руку/управление %d"%size.x)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("duel-%d.png"%size.x))
		main.hud.set_battle_mode(true)
		main.battle_hud.open(["Атакующий","Защитник"],[0,1],[410,390])
		await frames(12)
		for plate in main.battle_hud._plates:
			check(not main._duel_menu.get_global_rect().intersects(plate.get_global_rect()),"В меню не перекрывает боевую силу %d"%size.x)
		check(main._duel_menu.get_global_rect().end.y<64,"в бою В меню находится в свободной верхней полосе")
		main.hud.set_battle_mode(false)
		main.battle_hud.close()
		await frames(12)
	await menu_exit()
	if not await start_duel():
		check(false,"вторая дуэль начинается")
		await finish()
		return
	var bot := AIPlayer.new(0,4242)
	var target := 0
	var deadline := Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if main.hud._reading>0: main.hud._skip_flag=true
		if main.director.flying and main._active_ball!=null and not main._active_ball.freeze: break
		if AutoPlay.press_next_turn(main): continue
		var view: MatchState = main.ctrl.get_view(0)
		if main.setup_panel._panel.visible:
			var choice := bot.choose_setup(view,main.ctrl.legal_setup_slots(),main.ctrl.can_skip_gate())
			main.setup_panel.hide_panel()
			if choice.is_empty(): main._on_setup_skipped()
			else: main._on_setup_placed(choice.card_id,int(choice.slot))
		elif main.hud._creature_panel.visible:
			var choice := bot.choose_throw(view)
			target=int(choice.target_slot)
			main._on_creature_chosen(int(choice.uid))
		elif main._active_ball!=null and not main.director.flying and not main.events.is_busy(): main._on_slot_picked(target)
	check(main.director.flying and main._active_ball!=null and not main._active_ball.freeze,"выход проверяется во время настоящего физического полёта")
	await menu_exit()
	if not await start_duel():
		check(false,"третья дуэль начинается")
		await finish()
		return
	# Реальный экран результата намеренно оставлен ждать пользователя.
	var waiter := ResultWaiter.new()
	waiter.game=main
	main.add_child(waiter)
	main.events.push(waiter.wait_result)
	check(await until(func(): return main.battle_overlay._open),"EventPlayer ждёт подтверждения реального BattleOverlay")
	Engine.time_scale=1.0
	var moving: CreatureBall = main._spawn_ball(0)
	moving.stage_at(moving.global_position+Vector3(12,0,0),Vector3.ZERO)
	var vanishing: CreatureBall = main._spawn_ball(1)
	main._anim_remove_ball(1,true)
	check(main._prepared_balls.get(1)==vanishing and not main.balls.has(1),"исчезающий актёр учтён до завершения await")
	check(vanishing._open_tween!=null and vanishing._open_tween.is_running(),"выход прерывает живую vanish-анимацию")
	main.events.push(func(): check(false,"отменённая очередь не должна исполняться"))
	await menu_exit()
	check(Engine.max_fps==60,"лимит теста 60FPS сохранён")
	await finish()
func finish() -> void:
	if is_instance_valid(current_scene): current_scene.queue_free()
	await frames(3)
	if is_instance_valid(GameLoading._inst): GameLoading._inst.queue_free()
	await frames(3)
	if is_instance_valid(SoundFx._inst): SoundFx._inst.queue_free()
	await frames(3)
	print("DUEL EXIT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
